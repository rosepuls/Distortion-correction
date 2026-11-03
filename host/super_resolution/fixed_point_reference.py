"""Calibrate and run an int8-activation reference for the 3:2 residual CNN.

Weights are symmetric int8 per output channel. Activations are unsigned int8
after ReLU, signed int8 at the phase head, biases are quantized to int32 in
the corresponding accumulator domain, and every convolution accumulates in
int32. This Python implementation emulates those integer boundaries while
using float convolution for the multiply/accumulate itself.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F

from model import ResidualSR32


def _fixed_requant(ratio: float) -> tuple[int, int]:
    mantissa, exponent = math.frexp(ratio)
    multiplier = int(round(mantissa * (1 << 31)))
    if multiplier == (1 << 31):
        multiplier >>= 1
        exponent += 1
    return multiplier, 31 - exponent


def _requant_positive(value: torch.Tensor, ratio: float) -> torch.Tensor:
    multiplier, shift = _fixed_requant(ratio)
    product = value.to(torch.int64) * multiplier
    if shift > 0:
        product = (product + (1 << (shift - 1))) >> shift
    elif shift < 0:
        product = product << (-shift)
    return product


def residual_join(skip: torch.Tensor, branch: torch.Tensor,
                  skip_scale: float, branch_scale: float,
                  output_scale: float) -> torch.Tensor:
    skip_q = torch.round(skip / skip_scale).to(torch.int64)
    branch_q = torch.round(branch / branch_scale).to(torch.int64)
    skip_out = _requant_positive(skip_q, skip_scale / output_scale)
    branch_out = _requant_positive(branch_q, branch_scale / output_scale)
    return (skip_out + branch_out).clamp(0, 255).to(skip.dtype) * output_scale


def _scale(x: torch.Tensor, signed: bool = False) -> float:
    peak = float(x.detach().abs().amax())
    return peak / (127.0 if signed else 255.0) if peak else 1.0


@torch.no_grad()
def calibrate(model: ResidualSR32, lr_dir: Path, frames: int,
              patches_per_frame: int, patch: int, device: torch.device) -> dict:
    files = sorted([*lr_dir.glob("*.png"), *lr_dir.glob("*.jpg")])[:frames]
    if not files:
        raise ValueError(f"no calibration images in {lr_dir}")
    maxima = {k: 0.0 for k in (
        "stem", "block1.depthwise", "block1.pointwise", "block1.output",
        "block2.depthwise", "block2.pointwise", "block2.output", "phase")}
    rng = np.random.default_rng(20261030)
    for path in files:
        bgr = cv2.imread(str(path))
        if bgr is None:
            raise RuntimeError(f"cannot read {path}")
        y = cv2.cvtColor(bgr, cv2.COLOR_BGR2YCrCb)[:, :, 0]
        h, w = y.shape
        for _ in range(patches_per_frame):
            top = int(rng.integers(0, max(1, h - patch + 1))) // 2 * 2
            left = int(rng.integers(0, max(1, w - patch + 1))) // 2 * 2
            x = torch.from_numpy(y[top:top+patch, left:left+patch].copy())
            x = x.to(device=device, dtype=torch.float32)[None, None]
            a = F.relu(model.stem[0](x))
            maxima["stem"] = max(maxima["stem"], float(a.max()))
            for index, block in enumerate((model.block1, model.block2), start=1):
                d = F.relu(block.depthwise(a))
                maxima[f"block{index}.depthwise"] = max(
                    maxima[f"block{index}.depthwise"], float(d.max()))
                p = F.relu(block.pointwise(d))
                maxima[f"block{index}.pointwise"] = max(
                    maxima[f"block{index}.pointwise"], float(p.max()))
                a = a + p
                maxima[f"block{index}.output"] = max(
                    maxima[f"block{index}.output"], float(a.max()))
            phases = torch.cat((a[:, :, 0::2, 0::2], a[:, :, 0::2, 1::2],
                                a[:, :, 1::2, 0::2], a[:, :, 1::2, 1::2]), dim=1)
            r = model.phase_head(phases)
            maxima["phase"] = max(maxima["phase"], float(r.abs().max()))
    return {name: max(value / (127 if name == "phase" else 255), 1e-12)
            for name, value in maxima.items()}


def _qconv(x: torch.Tensor, conv: torch.nn.Conv2d, input_scale: float,
           output_scale: float, relu: bool, activation_signed: bool = False):
    dims = tuple(range(1, conv.weight.ndim))
    peak = conv.weight.detach().abs().amax(dim=dims, keepdim=True)
    wscale = torch.where(peak > 0, peak / 127.0, torch.ones_like(peak))
    qw = torch.round(conv.weight.detach() / wscale).clamp(-127, 127)
    bias = conv.bias.detach() if conv.bias is not None else torch.zeros(
        conv.out_channels, device=x.device)
    bias_scale = (wscale.reshape(-1) * input_scale)
    qb = torch.round(bias / bias_scale).clamp(-(2**31), 2**31 - 1)
    # Inputs, weights and bias are exact integers here. The bound of all layers
    # is below 2**24, so float32 convolution preserves these integer sums
    # exactly while PyTorch has no portable int32 Conv2d kernel.
    xq = torch.round(x / input_scale).clamp(0, 255)
    acc = F.conv2d(xq, qw, qb, conv.stride, conv.padding,
                   conv.dilation, conv.groups).round().to(torch.int64)
    ratios = (wscale.reshape(-1) * input_scale / output_scale).cpu().tolist()
    fixed_multipliers, right_shifts = [], []
    for ratio in ratios:
        multiplier, shift = _fixed_requant(ratio)
        fixed_multipliers.append(multiplier)
        right_shifts.append(shift)
    qout = torch.empty_like(acc)
    for channel, (mult, shift) in enumerate(zip(fixed_multipliers, right_shifts)):
        product = acc[:, channel] * mult
        if shift > 0:
            half = 1 << (shift - 1)
            positive = torch.bitwise_right_shift(product.clamp_min(0) + half, shift)
            negative = -torch.bitwise_right_shift((-product).clamp_min(0) + half, shift)
            value = torch.where(product >= 0, positive, negative)
        elif shift < 0:
            value = product << (-shift)
        else:
            value = product
        qout[:, channel] = value
    if relu:
        qout = qout.clamp_min(0)
    levels = 127 if activation_signed else 255
    qout = qout.clamp(-levels if activation_signed else 0, levels)
    return qout.to(x.dtype) * output_scale


@torch.no_grad()
def integer_emulated(model: ResidualSR32, luma: torch.Tensor,
                     scales: dict[str, float]) -> torch.Tensor:
    a = _qconv(luma, model.stem[0], 1.0, scales["stem"], True)
    for index, block in enumerate((model.block1, model.block2), start=1):
        incoming_scale = scales["stem"] if index == 1 else scales["block1.output"]
        dscale = scales[f"block{index}.depthwise"]
        pscale = scales[f"block{index}.pointwise"]
        oscale = scales[f"block{index}.output"]
        d = _qconv(a, block.depthwise, incoming_scale, dscale, True)
        p = _qconv(d, block.pointwise, dscale, pscale, True)
        a = residual_join(a, p, incoming_scale, pscale, oscale)
    phase = torch.cat((a[:, :, 0::2, 0::2], a[:, :, 0::2, 1::2],
                       a[:, :, 1::2, 0::2], a[:, :, 1::2, 1::2]), dim=1)
    residual = _qconv(phase, model.phase_head, scales["block2.output"],
                      scales["phase"], False, activation_signed=True)
    residual = residual.reshape(residual.shape[0], 1, 3, 3,
                                residual.shape[-2], residual.shape[-1])
    residual = residual.permute(0, 1, 4, 2, 5, 3).reshape(
        residual.shape[0], 1, residual.shape[-2] * 3, residual.shape[-1] * 3)
    base = F.interpolate(luma, size=(luma.shape[-2] * 3 // 2,
                                     luma.shape[-1] * 3 // 2),
                         mode="bicubic", align_corners=False)
    return torch.clamp(base + residual.clamp(-model.residual_limit,
                                              model.residual_limit), 0, 255)


@torch.no_grad()
def export_manifest(model: ResidualSR32, scales: dict[str, float],
                    checkpoint: Path, output: Path) -> dict:
    layers = {
        "stem": (model.stem[0], 1.0, scales["stem"], 1),
        "block1_depthwise": (model.block1.depthwise, scales["stem"], scales["block1.depthwise"], 9),
        "block1_pointwise": (model.block1.pointwise, scales["block1.depthwise"], scales["block1.pointwise"], 8),
        "block2_depthwise": (model.block2.depthwise, scales["block1.output"], scales["block2.depthwise"], 9),
        "block2_pointwise": (model.block2.pointwise, scales["block2.depthwise"], scales["block2.pointwise"], 8),
        "phase_head": (model.phase_head, scales["block2.output"], scales["phase"], 32),
    }
    result = {"format": "pango-sr-int8-activation-reference-v1",
              "checkpoint_sha256": hashlib.sha256(checkpoint.read_bytes()).hexdigest(),
              "input": {"dtype": "uint8", "scale": 1.0},
              "activation_scales": scales, "accumulator": "int32",
              "layers": {}, "residual_joins": {}}
    for name, (conv, in_scale, out_scale, fanin) in layers.items():
        dims = tuple(range(1, conv.weight.ndim))
        peaks = conv.weight.detach().abs().amax(dim=dims)
        ws = torch.where(peaks > 0, peaks / 127.0, torch.ones_like(peaks))
        qweights = torch.round(conv.weight.detach() / ws.reshape(-1, *([1] * (conv.weight.ndim - 1))))
        qweights = qweights.clamp(-127, 127).to(torch.int8)
        biases = conv.bias.detach() if conv.bias is not None else torch.zeros(conv.out_channels)
        qb = torch.round(biases / (ws * in_scale)).clamp(-(2**31), 2**31 - 1).to(torch.int32)
        result["layers"][name] = {
            "weight_shape": list(conv.weight.shape), "weight_scales": ws.tolist(),
            "weights_int8": qweights.flatten().tolist(),
            "bias_int32": qb.tolist(), "input_scale": in_scale,
            "output_scale": out_scale, "fanin": fanin,
            "worst_case_mac_bound": int(fanin * 255 * 127 + int(qb.abs().max())),
            "requant_real_multiplier": (ws * in_scale / out_scale).tolist(),
            "requant_multiplier_q31": [], "requant_right_shift": [],
        }
        for ratio in (ws * in_scale / out_scale).tolist():
            multiplier, shift = _fixed_requant(ratio)
            result["layers"][name]["requant_multiplier_q31"].append(multiplier)
            result["layers"][name]["requant_right_shift"].append(shift)
    for index in (1, 2):
        skip_scale = scales["stem"] if index == 1 else scales["block1.output"]
        branch_scale = scales[f"block{index}.pointwise"]
        output_scale = scales[f"block{index}.output"]
        skip_multiplier, skip_shift = _fixed_requant(skip_scale / output_scale)
        branch_multiplier, branch_shift = _fixed_requant(branch_scale / output_scale)
        result["residual_joins"][f"block{index}"] = {
            "skip_multiplier_q31": skip_multiplier,
            "skip_right_shift": skip_shift,
            "branch_multiplier_q31": branch_multiplier,
            "branch_right_shift": branch_shift,
            "output_scale": output_scale,
        }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, separators=(",", ":")), encoding="utf-8")
    return result


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("checkpoint", type=Path)
    ap.add_argument("calibration_lr_dir", type=Path)
    ap.add_argument("output_manifest", type=Path)
    ap.add_argument("--frames", type=int, default=64)
    ap.add_argument("--patches-per-frame", type=int, default=4)
    ap.add_argument("--patch", type=int, default=96)
    ap.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    args = ap.parse_args()
    saved = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model = ResidualSR32().to(args.device)
    model.load_state_dict(saved["state_dict"])
    model.eval()
    device = torch.device(args.device)
    scales = calibrate(model, args.calibration_lr_dir, args.frames,
                       args.patches_per_frame, args.patch, device)
    data = export_manifest(model, scales, args.checkpoint, args.output_manifest)
    print(json.dumps({"output": str(args.output_manifest),
                      "checkpoint_sha256": data["checkpoint_sha256"],
                      "activation_scales": scales,
                      "layers": list(data["layers"])}, indent=2))


if __name__ == "__main__":
    main()

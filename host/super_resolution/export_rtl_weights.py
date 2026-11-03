"""Write the calibrated quantized model, ROM images and deterministic goldens."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
import torch

from fixed_point_reference import _qconv, residual_join
from fixed_bicubic_3x2 import phase_weights_q14, resize_bicubic_3x2_q14
from model import ResidualSR32


def signed_hex(value: int, bits: int) -> str:
    return f"{int(value) & ((1 << bits) - 1):0{(bits + 3) // 4}x}"


@torch.no_grad()
def write_golden(model, scales: dict, out_dir: Path) -> None:
    side = 16
    yy, xx = torch.meshgrid(torch.arange(side), torch.arange(side), indexing="ij")
    image = ((xx * 13 + yy * 7 + ((xx ^ yy) & 7) * 11) & 255).float()[None, None]
    a = _qconv(image, model.stem[0], 1.0, scales["stem"], True)
    stages = {"stem_u8.hex": torch.round(a / scales["stem"]).to(torch.int32)}
    for index, block in enumerate((model.block1, model.block2), start=1):
        incoming = scales["stem"] if index == 1 else scales["block1.output"]
        ds, ps, os = (scales[f"block{index}.{part}"]
                      for part in ("depthwise", "pointwise", "output"))
        d = _qconv(a, block.depthwise, incoming, ds, True)
        stages[f"block{index}_depthwise_u8.hex"] = torch.round(d / ds).to(torch.int32)
        p = _qconv(d, block.pointwise, ds, ps, True)
        stages[f"block{index}_pointwise_u8.hex"] = torch.round(p / ps).to(torch.int32)
        a = residual_join(a, p, incoming, ps, os)
        stages[f"block{index}_output_u8.hex"] = torch.round(a / os).to(torch.int32)
    phases = torch.cat((a[:, :, 0::2, 0::2], a[:, :, 0::2, 1::2],
                        a[:, :, 1::2, 0::2], a[:, :, 1::2, 1::2]), dim=1)
    phase = _qconv(phases, model.phase_head, scales["block2.output"],
                   scales["phase"], False, activation_signed=True)
    stages["phase_s8.hex"] = torch.round(phase / scales["phase"]).to(torch.int32)
    phase_real = phase[0].cpu().numpy()
    residual = np.empty((side * 3 // 2, side * 3 // 2), dtype=np.int16)
    for tile_y in range(side // 2):
        for tile_x in range(side // 2):
            for phase_y in range(3):
                for phase_x in range(3):
                    phase_index = phase_y * 3 + phase_x
                    raw = float(phase_real[phase_index, tile_y, tile_x])
                    value = math.floor(raw + 0.5) if raw >= 0 else math.ceil(raw - 0.5)
                    residual[tile_y * 3 + phase_y, tile_x * 3 + phase_x] = min(
                        max(value, -24), 24)
    base = resize_bicubic_3x2_q14(image[0, 0].to(torch.uint8).cpu().numpy())
    final = np.clip(base.astype(np.int16) + residual, 0, 255).astype(np.uint8)
    stages["residual_y_s8.hex"] = torch.from_numpy(residual.astype(np.int32))
    (out_dir / "golden_input_u8.hex").write_text(
        "\n".join(signed_hex(v, 8) for v in image.to(torch.int32).flatten().tolist()) + "\n",
        encoding="ascii")
    for name, values in stages.items():
        bits = 8 if name.endswith(("u8.hex", "s8.hex")) else 16
        (out_dir / name).write_text(
            "\n".join(signed_hex(v, bits) for v in values.flatten().tolist()) + "\n",
            encoding="ascii")
    (out_dir / "output_u8.hex").write_text(
        "\n".join(signed_hex(v, 8) for v in final.flatten().tolist()) + "\n",
        encoding="ascii")
    (out_dir / "bicubic_phase_q14.json").write_text(
        json.dumps(phase_weights_q14(), indent=2) + "\n", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("checkpoint", type=Path)
    ap.add_argument("manifest", type=Path)
    ap.add_argument("output_dir", type=Path)
    args = ap.parse_args()
    saved = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model = ResidualSR32().eval()
    model.load_state_dict(saved["state_dict"])
    result = json.loads(args.manifest.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    index = {"format": result["format"],
             "checkpoint_sha256": result["checkpoint_sha256"],
             "manifest_sha256": hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
             "files": {}}
    for layer, data in result["layers"].items():
        stem = layer.lower()
        wfile, bfile = f"{stem}_weights_s8.hex", f"{stem}_bias_s32.hex"
        mfile, sfile = f"{stem}_requant_q31.hex", f"{stem}_requant_shift.hex"
        (args.output_dir / wfile).write_text(
            "\n".join(signed_hex(v, 8) for v in data["weights_int8"]) + "\n",
            encoding="ascii")
        (args.output_dir / bfile).write_text(
            "\n".join(signed_hex(v, 32) for v in data["bias_int32"]) + "\n",
            encoding="ascii")
        (args.output_dir / mfile).write_text(
            "\n".join(signed_hex(v, 32) for v in data["requant_multiplier_q31"]) + "\n",
            encoding="ascii")
        (args.output_dir / sfile).write_text(
            "\n".join(signed_hex(v, 8) for v in data["requant_right_shift"]) + "\n",
            encoding="ascii")
        index["files"][layer] = {"weights": wfile, "bias": bfile,
                                 "requant_multiplier": mfile, "requant_shift": sfile,
                                 "weight_shape": data["weight_shape"],
                                 "input_scale": data["input_scale"],
                                 "output_scale": data["output_scale"],
                                 "requant_multiplier_q31": data["requant_multiplier_q31"],
                                 "requant_right_shift": data["requant_right_shift"],
                                 "worst_case_mac_bound": data["worst_case_mac_bound"]}
    index["activation_scales"] = result["activation_scales"]
    index["bicubic_base"] = {
        "coefficient_file": "bicubic_phase_q14.json",
        "kernel": "Keys cubic a=-0.75 (PyTorch bicubic compatible)",
        "coefficient_format": "signed Q2.14",
        "edge_rule": "replicate nearest edge sample for each tap",
        "rounding": "nearest, ties away from zero after 2D sum",
        "output_scale_rule": "clamp to uint8 after adding integer residual",
    }
    index["residual_joins"] = result["residual_joins"]
    for block, data in result["residual_joins"].items():
        join_file = f"{block}_join_constants.hex"
        values = (data["skip_multiplier_q31"], data["skip_right_shift"],
                  data["branch_multiplier_q31"], data["branch_right_shift"])
        widths = (32, 8, 32, 8)
        (args.output_dir / join_file).write_text(
            "\n".join(signed_hex(value, bits) for value, bits in zip(values, widths)) + "\n",
            encoding="ascii")
        index["residual_joins"][block]["rom"] = join_file
    (args.output_dir / "deploy_index.json").write_text(
        json.dumps(index, indent=2), encoding="utf-8")
    write_golden(model, result["activation_scales"], args.output_dir)
    print(f"wrote {len(index['files'])} layer ROM pairs and golden vectors to {args.output_dir}")


if __name__ == "__main__":
    main()

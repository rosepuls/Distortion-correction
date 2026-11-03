"""Compare the activation-int8 deployment reference against floating CNN/baselines."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import cv2
import numpy as np
import torch

from evaluate_video import luma
from fixed_point_reference import integer_emulated
from metrics import psnr, ssim_global, temporal_error
from model import ResidualSR32


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("lr_dir", type=Path)
    ap.add_argument("hr_dir", type=Path)
    ap.add_argument("checkpoint", type=Path)
    ap.add_argument("manifest", type=Path)
    ap.add_argument("output_csv", type=Path)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    args = ap.parse_args()
    device = torch.device(args.device)
    saved = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model = ResidualSR32().to(device).eval()
    model.load_state_dict(saved["state_dict"])
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    scales = manifest["activation_scales"]
    lrs, hrs = sorted(args.lr_dir.glob("*.png")), sorted(args.hr_dir.glob("*.png"))
    if not lrs or [p.name for p in lrs] != [p.name for p in hrs]:
        raise RuntimeError("LR/HR frame lists must match")
    if args.limit:
        lrs, hrs = lrs[:args.limit], hrs[:args.limit]
    rows = []
    previous = {}
    for i, (lp, hp) in enumerate(zip(lrs, hrs)):
        lr, hr = cv2.imread(str(lp)), cv2.imread(str(hp))
        if lr is None or hr is None:
            raise RuntimeError(f"failed to read pair {lp.name}")
        ycc = cv2.cvtColor(lr, cv2.COLOR_BGR2YCrCb)
        x = torch.from_numpy(ycc[:, :, 0].copy()).to(device=device, dtype=torch.float32)[None, None]
        with torch.no_grad():
            fp = model(x).squeeze().cpu().numpy()
            q = integer_emulated(model, x, scales).squeeze().cpu().numpy()
        cr = cv2.resize(ycc[:, :, 1], (1920, 1080), interpolation=cv2.INTER_LINEAR)
        cb = cv2.resize(ycc[:, :, 2], (1920, 1080), interpolation=cv2.INTER_LINEAR)
        outputs = {
            "bicubic": cv2.resize(lr, (1920, 1080), interpolation=cv2.INTER_CUBIC),
            "float_cnn": cv2.cvtColor(cv2.merge((np.rint(np.clip(fp, 0, 255)).astype(np.uint8), cr, cb)), cv2.COLOR_YCrCb2BGR),
            "int8_activations": cv2.cvtColor(cv2.merge((np.rint(np.clip(q, 0, 255)).astype(np.uint8), cr, cb)), cv2.COLOR_YCrCb2BGR),
        }
        ref = luma(hr)
        for name, image in outputs.items():
            out = luma(image)
            row = {"frame": lp.name, "method": name,
                   "y_psnr": psnr(ref, out), "y_ssim_global": ssim_global(ref, out)}
            if name in previous:
                prev_ref, prev_out = previous[name]
                row["temporal_error"] = temporal_error(prev_ref, ref, prev_out, out)
            else:
                row["temporal_error"] = ""
            previous[name] = (ref, out)
            rows.append(row)
    args.output_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.output_csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    for method in ("bicubic", "float_cnn", "int8_activations"):
        selected = [r for r in rows if r["method"] == method]
        print(f"{method}: frames={len(selected)} mean_y_psnr={np.mean([r['y_psnr'] for r in selected]):.4f} "
              f"mean_y_ssim={np.mean([r['y_ssim_global'] for r in selected]):.6f} "
              f"mean_temporal={np.mean([float(r['temporal_error']) for r in selected[1:]]):.6f}")
    print(f"wrote metrics to {args.output_csv}")


if __name__ == "__main__":
    main()

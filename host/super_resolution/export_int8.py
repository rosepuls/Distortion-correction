"""Export model weights as symmetric signed int8 JSON for RTL ROM generation."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch

from model import ResidualSR32


def export(checkpoint: Path, output: Path) -> dict:
    data = torch.load(checkpoint, map_location="cpu", weights_only=False)
    model = ResidualSR32()
    model.load_state_dict(data["state_dict"])
    tensors = {}
    for name, value in model.state_dict().items():
        maximum = float(value.abs().max())
        scale = maximum / 127.0 if maximum else 1.0
        q = torch.clamp(torch.round(value / scale), -127, 127).to(torch.int8)
        tensors[name] = {"shape": list(value.shape), "scale": scale,
                         "values": q.flatten().tolist()}
    result = {"format": "pango-sr-int8-v1", "input_scale": 1.0,
              "residual_limit": model.residual_limit, "weights": tensors}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, separators=(",", ":")), encoding="utf-8")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = export(args.checkpoint, args.output)
    print(f"exported {len(data['weights'])} tensors to {args.output}")


if __name__ == "__main__":
    main()

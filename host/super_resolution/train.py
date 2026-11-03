"""Train ResidualSR32 on paired LR/HR PNG directories."""

from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import torch
from torch import nn
from torch.utils.data import DataLoader, Dataset

from model import ResidualSR32


class PairedLuma(Dataset):
    def __init__(self, lr_dir: Path, hr_dir: Path, patch: int = 96,
                 random_crop: bool = True, extra_pairs=None,
                 frame_subsample: int = 1, crops_per_frame: int = 1,
                 cache_frames: bool = False,
                 temporal_pair: bool = False) -> None:
        if frame_subsample < 1:
            raise ValueError("frame_subsample must be positive")
        if crops_per_frame < 1:
            raise ValueError("crops_per_frame must be positive")
        folders = [(lr_dir, hr_dir), *(extra_pairs or [])]
        self.pairs = []
        self.next_pair = []
        for lr_folder, hr_folder in folders:
            lr_files = sorted([*lr_folder.glob("*.png"), *lr_folder.glob("*.jpg")])
            hr_files = sorted([*hr_folder.glob("*.png"), *hr_folder.glob("*.jpg")])
            if not lr_files or [p.name for p in lr_files] != [p.name for p in hr_files]:
                raise ValueError(f"LR/HR folders must contain matching frames: {lr_folder}")
            selected = list(zip(lr_files[::frame_subsample], hr_files[::frame_subsample]))
            first = len(self.pairs)
            self.pairs.extend(selected)
            self.next_pair.extend(first + min(i + 1, len(selected) - 1)
                                  for i in range(len(selected)))
        if patch < 16 or patch % 2:
            raise ValueError("patch size must be an even integer >= 16")
        self.patch = patch
        self.random_crop = random_crop
        self.crops_per_frame = crops_per_frame
        self.cache = {} if cache_frames else None
        self.temporal_pair = temporal_pair

    def __len__(self) -> int:
        return len(self.pairs) * self.crops_per_frame

    def load_pair(self, pair_index: int):
        lr_path, hr_path = self.pairs[pair_index]
        if self.cache is not None and pair_index in self.cache:
            x, y = self.cache[pair_index]
        else:
            x = cv2.imread(str(lr_path))
            y = cv2.imread(str(hr_path))
            if x is None or y is None:
                raise RuntimeError(f"failed to decode pair {lr_path.name}")
            x = cv2.cvtColor(x, cv2.COLOR_BGR2YCrCb)[:, :, 0]
            y = cv2.cvtColor(y, cv2.COLOR_BGR2YCrCb)[:, :, 0]
            if self.cache is not None:
                self.cache[pair_index] = (x, y)
        return x, y

    def __getitem__(self, index: int):
        pair_index = index // self.crops_per_frame
        x, y = self.load_pair(pair_index)
        h, w = x.shape
        p = self.patch
        if self.random_crop:
            top = torch.randint(0, h - p + 1, ()).item() // 2 * 2
            left = torch.randint(0, w - p + 1, ()).item() // 2 * 2
        else:
            top, left = ((h - p) // 4) * 2, ((w - p) // 4) * 2
        xa, ya = x[top:top+p, left:left+p], y[top*3//2:(top+p)*3//2, left*3//2:(left+p)*3//2]
        if self.temporal_pair:
            x_next, y_next = self.load_pair(self.next_pair[pair_index])
            xb = x_next[top:top+p, left:left+p]
            yb = y_next[top*3//2:(top+p)*3//2, left*3//2:(left+p)*3//2]
        flip_x = torch.rand(()) < 0.5
        flip_y = torch.rand(()) < 0.5
        if flip_x:
            xa, ya = xa[:, ::-1].copy(), ya[:, ::-1].copy()
            if self.temporal_pair:
                xb, yb = xb[:, ::-1].copy(), yb[:, ::-1].copy()
        if flip_y:
            xa, ya = xa[::-1].copy(), ya[::-1].copy()
            if self.temporal_pair:
                xb, yb = xb[::-1].copy(), yb[::-1].copy()
        tx = torch.from_numpy(xa.copy()).float().unsqueeze(0) / 255.0 * 255.0
        ty = torch.from_numpy(ya.copy()).float().unsqueeze(0) / 255.0 * 255.0
        if self.temporal_pair:
            return tx, ty, torch.from_numpy(xb.copy()).float().unsqueeze(0), \
                torch.from_numpy(yb.copy()).float().unsqueeze(0)
        return tx, ty


def gradient_loss(a: torch.Tensor, b: torch.Tensor) -> torch.Tensor:
    dx_a, dx_b = a[..., :, 1:] - a[..., :, :-1], b[..., :, 1:] - b[..., :, :-1]
    dy_a, dy_b = a[..., 1:, :] - a[..., :-1, :], b[..., 1:, :] - b[..., :-1, :]
    return (dx_a - dx_b).abs().mean() + (dy_a - dy_b).abs().mean()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lr_dir", type=Path)
    parser.add_argument("hr_dir", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--patch", type=int, default=96)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--val-lr-dir", type=Path)
    parser.add_argument("--val-hr-dir", type=Path)
    parser.add_argument("--val-every", type=int, default=5)
    parser.add_argument("--extra-pair", nargs=2, action="append", type=Path,
                        metavar=("LR_DIR", "HR_DIR"), default=[])
    parser.add_argument("--frame-subsample", type=int, default=1)
    parser.add_argument("--crops-per-frame", type=int, default=1)
    parser.add_argument("--cache-frames", action="store_true")
    parser.add_argument("--val-frame-subsample", type=int, default=1)
    parser.add_argument("--save-last", type=Path)
    parser.add_argument("--temporal-lambda", type=float, default=0.0)
    parser.add_argument("--init-checkpoint", type=Path)
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    args = parser.parse_args()
    ds = PairedLuma(args.lr_dir, args.hr_dir, args.patch,
                    extra_pairs=[tuple(pair) for pair in args.extra_pair],
                    frame_subsample=args.frame_subsample,
                    crops_per_frame=args.crops_per_frame,
                    cache_frames=args.cache_frames,
                    temporal_pair=args.temporal_lambda > 0)
    loader = DataLoader(ds, batch_size=args.batch_size, shuffle=True, num_workers=0)
    val_loader = None
    if bool(args.val_lr_dir) != bool(args.val_hr_dir):
        parser.error("provide both --val-lr-dir and --val-hr-dir")
    if args.val_lr_dir:
        val_ds = PairedLuma(args.val_lr_dir, args.val_hr_dir, args.patch,
                            random_crop=False,
                            frame_subsample=args.val_frame_subsample,
                            cache_frames=args.cache_frames)
        val_loader = DataLoader(val_ds, batch_size=args.batch_size, shuffle=False, num_workers=0)
    if args.val_every < 1:
        parser.error("val-every must be positive")
    model = ResidualSR32().to(args.device)
    if args.init_checkpoint:
        saved = torch.load(args.init_checkpoint, map_location="cpu", weights_only=False)
        model.load_state_dict(saved["state_dict"])
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    best_val = float("inf")
    for epoch in range(args.epochs):
        model.train()
        total = 0.0
        for batch in loader:
            lr_img, hr_img = batch[:2]
            lr_img = lr_img.to(args.device)
            hr_img = hr_img.to(args.device)
            prediction = model(lr_img)
            loss = nn.functional.l1_loss(prediction, hr_img) + 0.08 * gradient_loss(prediction, hr_img)
            if args.temporal_lambda > 0:
                lr_next, hr_next = batch[2].to(args.device), batch[3].to(args.device)
                prediction_next = model(lr_next)
                next_loss = (nn.functional.l1_loss(prediction_next, hr_next) +
                             0.08 * gradient_loss(prediction_next, hr_next))
                loss = 0.5 * (loss + next_loss) + args.temporal_lambda * nn.functional.l1_loss(
                    prediction_next - prediction, hr_next - hr_img)
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            optimizer.step()
            total += loss.item()
        message = f"epoch {epoch + 1}/{args.epochs}: train_loss={total / max(1, len(loader)):.5f}"
        should_validate = val_loader is not None and (
            (epoch + 1) % args.val_every == 0 or epoch + 1 == args.epochs
        )
        val_loss = None
        if should_validate:
            model.eval()
            val_total = 0.0
            with torch.no_grad():
                for lr_img, hr_img in val_loader:
                    lr_img, hr_img = lr_img.to(args.device), hr_img.to(args.device)
                    prediction = model(lr_img)
                    val_total += (nn.functional.l1_loss(prediction, hr_img) +
                                  0.08 * gradient_loss(prediction, hr_img)).item()
            val_loss = val_total / max(1, len(val_loader))
            message += f" val_loss={val_loss:.5f}"
        print(message)
        if args.save_last:
            args.save_last.parent.mkdir(parents=True, exist_ok=True)
            torch.save({"epoch": epoch + 1, "state_dict": model.state_dict()},
                       args.save_last)
        if val_loader is None:
            torch.save({"epoch": epoch + 1, "state_dict": model.state_dict()}, args.output)
        elif val_loss is not None and val_loss < best_val:
            best_val = val_loss
            torch.save({"epoch": epoch + 1, "val_loss": val_loss,
                        "state_dict": model.state_dict()}, args.output)


if __name__ == "__main__":
    main()

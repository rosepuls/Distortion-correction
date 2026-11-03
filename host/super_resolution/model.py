"""Compact luma residual model for rational 3:2 image enlargement."""

from __future__ import annotations

import torch
from torch import nn
import torch.nn.functional as F


class DepthwiseSeparableBlock(nn.Module):
    def __init__(self, channels: int = 8) -> None:
        super().__init__()
        self.depthwise = nn.Conv2d(
            channels, channels, 3, padding=1, groups=channels, bias=True
        )
        self.pointwise = nn.Conv2d(channels, channels, 1, bias=True)
        self.activation = nn.ReLU(inplace=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return x + self.activation(self.pointwise(self.activation(self.depthwise(x))))


class ResidualSR32(nn.Module):
    """Predict nine luma residual phases for every 2x2 LR block.

    Input:  N x 1 x H x W, with even H/W.
    Output: N x 1 x (3H/2) x (3W/2), matching align_corners=False 3:2 resize.
    """

    def __init__(self, channels: int = 8, residual_limit: float = 24.0) -> None:
        super().__init__()
        self.residual_limit = float(residual_limit)
        self.stem = nn.Sequential(
            nn.Conv2d(1, channels, 3, padding=1, bias=True), nn.ReLU(inplace=False)
        )
        self.block1 = DepthwiseSeparableBlock(channels)
        self.block2 = DepthwiseSeparableBlock(channels)
        self.phase_head = nn.Conv2d(channels * 4, 9, 1, bias=True)
        nn.init.zeros_(self.phase_head.weight)
        nn.init.zeros_(self.phase_head.bias)

    @staticmethod
    def _phase_tiles(phases: torch.Tensor) -> torch.Tensor:
        # N,9,H/2,W/2 -> N,1,3H/2,3W/2. Channel order is row-major phase.
        n, _, h, w = phases.shape
        tiles = phases.reshape(n, 1, 3, 3, h, w)
        return tiles.permute(0, 1, 4, 2, 5, 3).reshape(n, 1, h * 3, w * 3)

    def forward(self, luma: torch.Tensor) -> torch.Tensor:
        if luma.ndim != 4 or luma.shape[1] != 1:
            raise ValueError("luma must have shape N x 1 x H x W")
        h, w = luma.shape[-2:]
        if h % 2 or w % 2:
            raise ValueError("3:2 phase output requires even input width and height")

        base = F.interpolate(luma, size=(h * 3 // 2, w * 3 // 2),
                             mode="bicubic", align_corners=False)
        feat = self.block2(self.block1(self.stem(luma)))
        # Gather the four feature phases for each 2x2 source block.
        phase_features = torch.cat(
            (feat[:, :, 0::2, 0::2], feat[:, :, 0::2, 1::2],
             feat[:, :, 1::2, 0::2], feat[:, :, 1::2, 1::2]), dim=1
        )
        residual = self._phase_tiles(self.phase_head(phase_features))
        residual = torch.clamp(residual, -self.residual_limit, self.residual_limit)
        return torch.clamp(base + residual, 0.0, 255.0)

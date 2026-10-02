"""Logical bilinear-neighbor address tracing for the distortion pipeline."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import numpy as np
from numpy.typing import ArrayLike


RGB_BYTES_PER_PIXEL = 3


@dataclass(frozen=True)
class BilinearAddressRequest:
    """The four logical source-pixel addresses for one output pixel."""

    output_index: int
    x0: int
    y0: int
    addresses: tuple[int, int, int, int]


@dataclass(frozen=True)
class AddressTraceMetrics:
    """Summary of the logical source-pixel request sequence."""

    total_outputs: int
    valid_outputs: int
    invalid_outputs: int
    total_source_reads: int
    unique_source_addresses: int
    repeated_source_reads: int
    cross_row_pairs: int
    logical_bytes_read: int
    average_consecutive_run: float
    maximum_consecutive_run: int


def logical_pixel_address(x: int, y: int, frame_stride_pixels: int) -> int:
    """Return a logical pixel number, not an RGB byte address."""

    if frame_stride_pixels <= 0:
        raise ValueError("frame_stride_pixels must be greater than zero")
    if x < 0 or y < 0:
        raise ValueError("pixel coordinates must be non-negative")
    return y * frame_stride_pixels + x


def _validate_inputs(
    x0: np.ndarray,
    y0: np.ndarray,
    coord_valid: np.ndarray,
    width: int,
    height: int,
    frame_stride_pixels: int,
) -> None:
    if width <= 0 or height <= 0:
        raise ValueError("width and height must be greater than zero")
    if frame_stride_pixels < width:
        raise ValueError("frame_stride_pixels must be at least width")
    if x0.shape != y0.shape or x0.shape != coord_valid.shape:
        raise ValueError("x0, y0, and coord_valid must have equal shapes")
    if x0.ndim == 0:
        raise ValueError("x0, y0, and coord_valid must be array-like")
    if not np.issubdtype(x0.dtype, np.integer):
        raise TypeError("x0 must contain integer coordinates")
    if not np.issubdtype(y0.dtype, np.integer):
        raise TypeError("y0 must contain integer coordinates")


def _consecutive_run_lengths(addresses: Sequence[int]) -> list[int]:
    if not addresses:
        return []

    runs: list[int] = []
    current_length = 1
    for previous, current in zip(addresses, addresses[1:]):
        if current == previous + 1:
            current_length += 1
        else:
            runs.append(current_length)
            current_length = 1
    runs.append(current_length)
    return runs


def _build_metrics(
    total_outputs: int,
    valid_outputs: int,
    addresses: Sequence[int],
    frame_stride_pixels: int,
) -> AddressTraceMetrics:
    unique_addresses = len(set(addresses))
    runs = _consecutive_run_lengths(addresses)
    cross_row_pairs = sum(
        previous // frame_stride_pixels != current // frame_stride_pixels
        for previous, current in zip(addresses, addresses[1:])
    )

    return AddressTraceMetrics(
        total_outputs=total_outputs,
        valid_outputs=valid_outputs,
        invalid_outputs=total_outputs - valid_outputs,
        total_source_reads=len(addresses),
        unique_source_addresses=unique_addresses,
        repeated_source_reads=len(addresses) - unique_addresses,
        cross_row_pairs=cross_row_pairs,
        logical_bytes_read=len(addresses) * RGB_BYTES_PER_PIXEL,
        average_consecutive_run=(sum(runs) / len(runs)) if runs else 0.0,
        maximum_consecutive_run=max(runs, default=0),
    )


def generate_address_trace(
    x0: ArrayLike,
    y0: ArrayLike,
    coord_valid: ArrayLike,
    width: int,
    height: int,
    *,
    frame_stride_pixels: int | None = None,
) -> tuple[list[BilinearAddressRequest], AddressTraceMetrics]:
    """Generate logical P00/P10/P01/P11 requests for a coordinate stream.

    ``coord_valid`` is treated as an additional validity assertion. A request
    is emitted only when it is true and all four interpolation neighbors are
    inside the source image. The returned addresses are logical pixel numbers;
    RGB byte packing is represented only by ``logical_bytes_read``.
    """

    x0_array = np.asarray(x0)
    y0_array = np.asarray(y0)
    valid_array = np.asarray(coord_valid, dtype=bool)
    stride = width if frame_stride_pixels is None else frame_stride_pixels
    _validate_inputs(x0_array, y0_array, valid_array, width, height, stride)

    requests: list[BilinearAddressRequest] = []
    addresses: list[int] = []
    valid_outputs = 0

    for output_index, (x_value, y_value, is_valid) in enumerate(
        zip(x0_array.flat, y0_array.flat, valid_array.flat)
    ):
        x_integer = int(x_value)
        y_integer = int(y_value)
        neighbors_valid = (
            bool(is_valid)
            and 0 <= x_integer < width - 1
            and 0 <= y_integer < height - 1
        )
        if not neighbors_valid:
            continue

        request_addresses = (
            logical_pixel_address(x_integer, y_integer, stride),
            logical_pixel_address(x_integer + 1, y_integer, stride),
            logical_pixel_address(x_integer, y_integer + 1, stride),
            logical_pixel_address(x_integer + 1, y_integer + 1, stride),
        )
        requests.append(
            BilinearAddressRequest(
                output_index=output_index,
                x0=x_integer,
                y0=y_integer,
                addresses=request_addresses,
            )
        )
        addresses.extend(request_addresses)
        valid_outputs += 1

    metrics = _build_metrics(
        total_outputs=x0_array.size,
        valid_outputs=valid_outputs,
        addresses=addresses,
        frame_stride_pixels=stride,
    )
    return requests, metrics

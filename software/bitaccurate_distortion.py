"""Bit-accurate fixed-point reference model for distortion correction.

The implementation mirrors the first fixed-point proposal in
``docs/numeric_spec.md``:

* normalized coordinates and distortion coefficients use Q4.28;
* camera coordinates use Q13.19;
* inverse focal lengths use Q2.30;
* bilinear fractions use Q0.16;
* products are kept at their full Python-integer precision and are reduced
  with arithmetic right shifts at the same points as the RTL specification;
* invalid bilinear neighborhoods produce a black pixel.

Python integers are deliberately used for intermediate values.  This makes
implicit NumPy overflow impossible and keeps the model suitable as a source
of RTL comparison vectors.  The returned coordinate maps are converted to
signed 64-bit integers after the final Q13.19 reduction.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Callable

import numpy as np
from numpy.typing import ArrayLike, NDArray


@dataclass(frozen=True)
class FixedPointConfig:
    """Fixed-point formats used by the first RTL-compatible model."""

    normalized_frac_bits: int = 28
    coefficient_frac_bits: int = 28
    inverse_focal_frac_bits: int = 30
    pixel_coord_frac_bits: int = 19
    src_coord_frac_bits: int = 19
    interpolation_frac_bits: int = 16

    @property
    def src_coord_scale(self) -> int:
        return 1 << self.src_coord_frac_bits

    @property
    def interpolation_scale(self) -> int:
        return 1 << self.interpolation_frac_bits


DEFAULT_CONFIG = FixedPointConfig()


def _round_half_away_from_zero(value: float) -> int:
    """Quantize a real value without relying on Python's banker rounding."""

    if not math.isfinite(value):
        raise ValueError("fixed-point inputs must be finite")
    scaled = value
    if scaled >= 0.0:
        return math.floor(scaled + 0.5)
    return math.ceil(scaled - 0.5)


def quantize_real(value: float, frac_bits: int) -> int:
    """Convert a real scalar to a signed fixed-point integer."""

    if frac_bits < 0:
        raise ValueError("frac_bits must be non-negative")
    return _round_half_away_from_zero(float(value) * (1 << frac_bits))


def fixed_to_float(value: ArrayLike | int, frac_bits: int) -> float | NDArray[np.float64]:
    """Convert a fixed-point scalar or array to floating point."""

    if frac_bits < 0:
        raise ValueError("frac_bits must be non-negative")
    values = np.asarray(value, dtype=np.float64) / float(1 << frac_bits)
    if values.ndim == 0:
        return float(values)
    return values


@dataclass(frozen=True)
class FixedPointCameraModel:
    """Camera parameters stored as fixed-point integers.

    ``fx``, ``fy``, ``cx`` and ``cy`` use Q13.19.  ``inv_fx`` and ``inv_fy``
    use Q2.30.  Distortion coefficients use Q4.28.
    """

    fx: int
    fy: int
    cx: int
    cy: int
    inv_fx: int
    inv_fy: int
    k1: int = 0
    k2: int = 0
    p1: int = 0
    p2: int = 0

    @classmethod
    def from_parameters(
        cls,
        *,
        fx: float,
        fy: float,
        cx: float,
        cy: float,
        k1: float = 0.0,
        k2: float = 0.0,
        p1: float = 0.0,
        p2: float = 0.0,
        config: FixedPointConfig = DEFAULT_CONFIG,
    ) -> "FixedPointCameraModel":
        """Quantize floating-point camera parameters using the fixed formats."""

        if fx <= 0.0 or fy <= 0.0:
            raise ValueError("fx and fy must be greater than zero")
        return cls(
            fx=quantize_real(fx, config.src_coord_frac_bits),
            fy=quantize_real(fy, config.src_coord_frac_bits),
            cx=quantize_real(cx, config.src_coord_frac_bits),
            cy=quantize_real(cy, config.src_coord_frac_bits),
            inv_fx=quantize_real(1.0 / fx, config.inverse_focal_frac_bits),
            inv_fy=quantize_real(1.0 / fy, config.inverse_focal_frac_bits),
            k1=quantize_real(k1, config.coefficient_frac_bits),
            k2=quantize_real(k2, config.coefficient_frac_bits),
            p1=quantize_real(p1, config.coefficient_frac_bits),
            p2=quantize_real(p2, config.coefficient_frac_bits),
        )

    @classmethod
    def from_camera_model(
        cls,
        camera: object,
        config: FixedPointConfig = DEFAULT_CONFIG,
    ) -> "FixedPointCameraModel":
        """Quantize a ``distortion_float.CameraModel``-compatible object."""

        fields = ("fx", "fy", "cx", "cy", "k1", "k2", "p1", "p2")
        try:
            values = {field: float(getattr(camera, field)) for field in fields}
        except AttributeError as exc:
            raise TypeError("camera must expose the CameraModel fields") from exc
        return cls.from_parameters(config=config, **values)


@dataclass(frozen=True)
class InternalFormat:
    """Signed internal widths and Q formats for the narrowed Horner path.

    Each width includes its sign bit.  Every stage is explicitly saturated
    after it is rescaled, so candidate measurements model the exact overflow
    policy that the optimized RTL must implement.
    """

    centered_width: int = 25
    centered_frac_bits: int = 12
    inverse_width: int = 24
    inverse_frac_bits: int = 22
    normalized_width: int = 26
    normalized_frac_bits: int = 22
    coefficient_width: int = 24
    coefficient_frac_bits: int = 20
    radius_width: int = 28
    radius_frac_bits: int = 22
    radial_width: int = 26
    radial_frac_bits: int = 22
    distorted_width: int = 26
    distorted_frac_bits: int = 22
    focal_width: int = 25
    focal_frac_bits: int = 12

    def __post_init__(self) -> None:
        for name in (
            "centered",
            "inverse",
            "normalized",
            "coefficient",
            "radius",
            "radial",
            "distorted",
            "focal",
        ):
            width = getattr(self, f"{name}_width")
            frac_bits = getattr(self, f"{name}_frac_bits")
            if width < 2:
                raise ValueError(f"{name}_width must include sign and integer bits")
            if frac_bits < 0 or frac_bits >= width:
                raise ValueError(f"{name}_frac_bits must be in range 0..width-1")

    @classmethod
    def default_candidate(cls) -> "InternalFormat":
        """Return the narrowest candidate evaluated before RTL generation."""

        return cls()


@dataclass(frozen=True)
class CandidateMetrics:
    """Measured difference between one narrowed candidate and the baseline."""

    max_error_pixels: float
    mean_error_pixels: float
    rmse_pixels: float
    coord_valid_mismatches: int
    ranges: dict[str, tuple[int, int]]


def _object_array(values: ArrayLike) -> NDArray[object]:
    """Return an array whose arithmetic values are ordinary Python integers."""

    array = np.asarray(values)
    return np.asarray(array, dtype=object)


def _elementwise(values: ArrayLike, operation: Callable[[int], int]) -> NDArray[object]:
    array = _object_array(values)
    result = [operation(int(value)) for value in array.flat]
    return np.asarray(result, dtype=object).reshape(array.shape)


def _rescale(values: ArrayLike, source_frac_bits: int, target_frac_bits: int) -> NDArray[object]:
    """Rescale fixed-point integers using arithmetic right shift when needed."""

    shift = source_frac_bits - target_frac_bits
    if shift >= 0:
        return _elementwise(values, lambda value: value >> shift)
    return _elementwise(values, lambda value: value << (-shift))


def _as_int64(values: ArrayLike) -> NDArray[np.int64]:
    result = _elementwise(values, int)
    return np.asarray(result, dtype=np.int64)


def _saturate_signed(values: ArrayLike, width: int) -> NDArray[object]:
    """Clamp ordinary integer values to a signed two's-complement width."""

    minimum = -(1 << (width - 1))
    maximum = (1 << (width - 1)) - 1
    return _elementwise(values, lambda value: min(max(value, minimum), maximum))


def _quantize_stage(
    values: ArrayLike,
    source_frac_bits: int,
    target_width: int,
    target_frac_bits: int,
) -> NDArray[object]:
    """Rescale then explicitly saturate one candidate arithmetic stage."""

    return _saturate_signed(
        _rescale(values, source_frac_bits, target_frac_bits), target_width
    )


def _record_range(ranges: dict[str, tuple[int, int]], name: str, values: ArrayLike) -> None:
    array = _object_array(values)
    ranges[name] = (min(int(value) for value in array.flat), max(int(value) for value in array.flat))


def _integer_coordinate_array(values: ArrayLike) -> NDArray[object]:
    array = np.asarray(values, dtype=np.float64)
    if not np.all(np.isfinite(array)) or not np.all(array == np.floor(array)):
        raise ValueError("output coordinates must be finite integers")
    return _elementwise(array, int)


def source_coordinates_fixed(
    u: ArrayLike,
    v: ArrayLike,
    camera: FixedPointCameraModel,
    config: FixedPointConfig = DEFAULT_CONFIG,
) -> tuple[NDArray[np.int64], NDArray[np.int64]]:
    """Map integer output coordinates to Q13.19 source coordinates.

    The returned arrays contain raw signed fixed-point integers, not pixel
    coordinates in floating-point units.  All reductions use arithmetic
    shifts, including the reduction of ``u-cx`` times ``inv_fx`` to Q4.28.
    """

    if not isinstance(camera, FixedPointCameraModel):
        raise TypeError("camera must be a FixedPointCameraModel")

    output_x = _integer_coordinate_array(u)
    output_y = _integer_coordinate_array(v)
    if output_x.shape != output_y.shape:
        raise ValueError("u and v must have equal shapes")

    pixel_frac = config.pixel_coord_frac_bits
    normalized_frac = config.normalized_frac_bits
    coefficient_frac = config.coefficient_frac_bits

    u_fixed = _elementwise(output_x, lambda value: value << pixel_frac)
    v_fixed = _elementwise(output_y, lambda value: value << pixel_frac)
    centered_x = u_fixed - camera.cx
    centered_y = v_fixed - camera.cy

    x = _rescale(
        centered_x * camera.inv_fx,
        pixel_frac + config.inverse_focal_frac_bits,
        normalized_frac,
    )
    y = _rescale(
        centered_y * camera.inv_fy,
        pixel_frac + config.inverse_focal_frac_bits,
        normalized_frac,
    )

    square_frac = normalized_frac * 2
    x_squared = x * x
    y_squared = y * y
    xy = x * y
    radius_squared = x_squared + y_squared
    radius_fourth = radius_squared * radius_squared

    radial_frac = square_frac
    one = np.full(x.shape, 1 << radial_frac, dtype=object)
    radial = (
        one
        + _rescale(
            camera.k1 * radius_squared,
            coefficient_frac + square_frac,
            radial_frac,
        )
        + _rescale(
            camera.k2 * radius_fourth,
            coefficient_frac + square_frac * 2,
            radial_frac,
        )
    )

    radial_x = _rescale(x * radial, normalized_frac + radial_frac, normalized_frac)
    radial_y = _rescale(y * radial, normalized_frac + radial_frac, normalized_frac)

    tangential_x = (
        _rescale(
            2 * camera.p1 * xy,
            coefficient_frac + square_frac,
            square_frac,
        )
        + _rescale(
            camera.p2 * (radius_squared + 2 * x_squared),
            coefficient_frac + square_frac,
            square_frac,
        )
    )
    tangential_y = (
        _rescale(
            camera.p1 * (radius_squared + 2 * y_squared),
            coefficient_frac + square_frac,
            square_frac,
        )
        + _rescale(
            2 * camera.p2 * xy,
            coefficient_frac + square_frac,
            square_frac,
        )
    )

    distorted_x = radial_x + _rescale(tangential_x, square_frac, normalized_frac)
    distorted_y = radial_y + _rescale(tangential_y, square_frac, normalized_frac)

    source_x = (
        _rescale(
            camera.fx * distorted_x,
            config.src_coord_frac_bits + normalized_frac,
            config.src_coord_frac_bits,
        )
        + camera.cx
    )
    source_y = (
        _rescale(
            camera.fy * distorted_y,
            config.src_coord_frac_bits + normalized_frac,
            config.src_coord_frac_bits,
        )
        + camera.cy
    )

    return _as_int64(source_x), _as_int64(source_y)


def _source_coordinates_horner_quantized_internal(
    u: ArrayLike,
    v: ArrayLike,
    camera: FixedPointCameraModel,
    internal_format: InternalFormat,
    config: FixedPointConfig,
) -> tuple[NDArray[np.int64], NDArray[np.int64], dict[str, tuple[int, int]]]:
    """Evaluate the narrowed fixed-point path and expose its stage ranges."""

    if not isinstance(camera, FixedPointCameraModel):
        raise TypeError("camera must be a FixedPointCameraModel")
    if not isinstance(internal_format, InternalFormat):
        raise TypeError("internal_format must be an InternalFormat")

    output_x = _integer_coordinate_array(u)
    output_y = _integer_coordinate_array(v)
    if output_x.shape != output_y.shape:
        raise ValueError("u and v must have equal shapes")

    fmt = internal_format
    ranges: dict[str, tuple[int, int]] = {}
    pixel_frac = config.pixel_coord_frac_bits

    u_fixed = _elementwise(output_x, lambda value: value << pixel_frac)
    v_fixed = _elementwise(output_y, lambda value: value << pixel_frac)
    centered_x = _quantize_stage(
        u_fixed - camera.cx, pixel_frac, fmt.centered_width, fmt.centered_frac_bits
    )
    centered_y = _quantize_stage(
        v_fixed - camera.cy, pixel_frac, fmt.centered_width, fmt.centered_frac_bits
    )
    inv_fx = _quantize_stage(
        [camera.inv_fx],
        config.inverse_focal_frac_bits,
        fmt.inverse_width,
        fmt.inverse_frac_bits,
    )[0]
    inv_fy = _quantize_stage(
        [camera.inv_fy],
        config.inverse_focal_frac_bits,
        fmt.inverse_width,
        fmt.inverse_frac_bits,
    )[0]
    x = _quantize_stage(
        centered_x * inv_fx,
        fmt.centered_frac_bits + fmt.inverse_frac_bits,
        fmt.normalized_width,
        fmt.normalized_frac_bits,
    )
    y = _quantize_stage(
        centered_y * inv_fy,
        fmt.centered_frac_bits + fmt.inverse_frac_bits,
        fmt.normalized_width,
        fmt.normalized_frac_bits,
    )
    _record_range(ranges, "centered_x", centered_x)
    _record_range(ranges, "centered_y", centered_y)
    _record_range(ranges, "normalized_x", x)
    _record_range(ranges, "normalized_y", y)

    k1 = _quantize_stage(
        [camera.k1], config.coefficient_frac_bits, fmt.coefficient_width, fmt.coefficient_frac_bits
    )[0]
    k2 = _quantize_stage(
        [camera.k2], config.coefficient_frac_bits, fmt.coefficient_width, fmt.coefficient_frac_bits
    )[0]
    p1 = _quantize_stage(
        [camera.p1], config.coefficient_frac_bits, fmt.coefficient_width, fmt.coefficient_frac_bits
    )[0]
    p2 = _quantize_stage(
        [camera.p2], config.coefficient_frac_bits, fmt.coefficient_width, fmt.coefficient_frac_bits
    )[0]

    x_squared = _quantize_stage(
        x * x,
        2 * fmt.normalized_frac_bits,
        fmt.radius_width,
        fmt.radius_frac_bits,
    )
    y_squared = _quantize_stage(
        y * y,
        2 * fmt.normalized_frac_bits,
        fmt.radius_width,
        fmt.radius_frac_bits,
    )
    xy = _quantize_stage(
        x * y,
        2 * fmt.normalized_frac_bits,
        fmt.radius_width,
        fmt.radius_frac_bits,
    )
    radius_squared = _saturate_signed(x_squared + y_squared, fmt.radius_width)
    _record_range(ranges, "x_squared", x_squared)
    _record_range(ranges, "y_squared", y_squared)
    _record_range(ranges, "xy", xy)
    _record_range(ranges, "radius_squared", radius_squared)

    t = _saturate_signed(
        _quantize_stage(
            [k1], fmt.coefficient_frac_bits, fmt.radial_width, fmt.radial_frac_bits
        )
        + _quantize_stage(
            k2 * radius_squared,
            fmt.coefficient_frac_bits + fmt.radius_frac_bits,
            fmt.radial_width,
            fmt.radial_frac_bits,
        ),
        fmt.radial_width,
    )
    radial = _saturate_signed(
        _elementwise(t, lambda _value: 1 << fmt.radial_frac_bits)
        + _quantize_stage(
            radius_squared * t,
            fmt.radius_frac_bits + fmt.radial_frac_bits,
            fmt.radial_width,
            fmt.radial_frac_bits,
        ),
        fmt.radial_width,
    )
    _record_range(ranges, "horner_t", t)
    _record_range(ranges, "radial", radial)

    radial_x = _quantize_stage(
        x * radial,
        fmt.normalized_frac_bits + fmt.radial_frac_bits,
        fmt.distorted_width,
        fmt.distorted_frac_bits,
    )
    radial_y = _quantize_stage(
        y * radial,
        fmt.normalized_frac_bits + fmt.radial_frac_bits,
        fmt.distorted_width,
        fmt.distorted_frac_bits,
    )
    tangential_x = _saturate_signed(
        _quantize_stage(
            2 * p1 * xy,
            fmt.coefficient_frac_bits + fmt.radius_frac_bits,
            fmt.distorted_width,
            fmt.distorted_frac_bits,
        )
        + _quantize_stage(
            p2 * (radius_squared + 2 * x_squared),
            fmt.coefficient_frac_bits + fmt.radius_frac_bits,
            fmt.distorted_width,
            fmt.distorted_frac_bits,
        ),
        fmt.distorted_width,
    )
    tangential_y = _saturate_signed(
        _quantize_stage(
            p1 * (radius_squared + 2 * y_squared),
            fmt.coefficient_frac_bits + fmt.radius_frac_bits,
            fmt.distorted_width,
            fmt.distorted_frac_bits,
        )
        + _quantize_stage(
            2 * p2 * xy,
            fmt.coefficient_frac_bits + fmt.radius_frac_bits,
            fmt.distorted_width,
            fmt.distorted_frac_bits,
        ),
        fmt.distorted_width,
    )
    distorted_x = _saturate_signed(radial_x + tangential_x, fmt.distorted_width)
    distorted_y = _saturate_signed(radial_y + tangential_y, fmt.distorted_width)
    _record_range(ranges, "distorted_x", distorted_x)
    _record_range(ranges, "distorted_y", distorted_y)

    fx = _quantize_stage(
        [camera.fx], config.src_coord_frac_bits, fmt.focal_width, fmt.focal_frac_bits
    )[0]
    fy = _quantize_stage(
        [camera.fy], config.src_coord_frac_bits, fmt.focal_width, fmt.focal_frac_bits
    )[0]
    cx = _quantize_stage(
        [camera.cx], config.src_coord_frac_bits, fmt.focal_width, fmt.focal_frac_bits
    )[0]
    cy = _quantize_stage(
        [camera.cy], config.src_coord_frac_bits, fmt.focal_width, fmt.focal_frac_bits
    )[0]
    source_x = _quantize_stage(
        fx * distorted_x,
        fmt.focal_frac_bits + fmt.distorted_frac_bits,
        63,
        config.src_coord_frac_bits,
    ) + _rescale([cx], fmt.focal_frac_bits, config.src_coord_frac_bits)[0]
    source_y = _quantize_stage(
        fy * distorted_y,
        fmt.focal_frac_bits + fmt.distorted_frac_bits,
        63,
        config.src_coord_frac_bits,
    ) + _rescale([cy], fmt.focal_frac_bits, config.src_coord_frac_bits)[0]
    _record_range(ranges, "source_x_q19", source_x)
    _record_range(ranges, "source_y_q19", source_y)
    return _as_int64(source_x), _as_int64(source_y), ranges


def source_coordinates_horner_quantized(
    u: ArrayLike,
    v: ArrayLike,
    camera: FixedPointCameraModel,
    internal_format: InternalFormat,
    config: FixedPointConfig = DEFAULT_CONFIG,
) -> tuple[NDArray[np.int64], NDArray[np.int64]]:
    """Map output pixels with a narrowed, saturated Horner arithmetic path."""

    source_x, source_y, _ = _source_coordinates_horner_quantized_internal(
        u, v, camera, internal_format, config
    )
    return source_x, source_y


def evaluate_internal_format(
    width: int,
    height: int,
    camera: FixedPointCameraModel,
    internal_format: InternalFormat,
    *,
    stride: int = 1,
) -> CandidateMetrics:
    """Measure one candidate against the full-precision fixed-point model."""

    if width <= 1 or height <= 1:
        raise ValueError("width and height must both be greater than one")
    if stride <= 0:
        raise ValueError("stride must be greater than zero")

    sampled_y, sampled_x = np.indices(
        ((height + stride - 1) // stride, (width + stride - 1) // stride),
        dtype=np.int64,
    )
    sampled_x *= stride
    sampled_y *= stride
    sampled_x = np.clip(sampled_x, 0, width - 1)
    sampled_y = np.clip(sampled_y, 0, height - 1)
    corners_x = np.asarray([0, width - 1, 0, width - 1], dtype=np.int64)
    corners_y = np.asarray([0, 0, height - 1, height - 1], dtype=np.int64)
    horizontal_x = np.arange(width, dtype=np.int64)
    vertical_y = np.arange(height, dtype=np.int64)
    output_x = np.concatenate(
        (
            sampled_x.ravel(),
            corners_x,
            horizontal_x,
            horizontal_x,
            np.zeros(height, dtype=np.int64),
            np.full(height, width - 1, dtype=np.int64),
        )
    )
    output_y = np.concatenate(
        (
            sampled_y.ravel(),
            corners_y,
            np.zeros(width, dtype=np.int64),
            np.full(width, height - 1, dtype=np.int64),
            vertical_y,
            vertical_y,
        )
    )

    baseline_x, baseline_y = source_coordinates_fixed(output_x, output_y, camera)
    candidate_x, candidate_y, ranges = _source_coordinates_horner_quantized_internal(
        output_x, output_y, camera, internal_format, DEFAULT_CONFIG
    )
    errors = np.concatenate(
        (
            np.abs(candidate_x - baseline_x),
            np.abs(candidate_y - baseline_y),
        )
    ).astype(np.float64) / float(DEFAULT_CONFIG.src_coord_scale)
    _, _, _, _, baseline_valid = split_source_coordinates(
        baseline_x, baseline_y, width=width, height=height
    )
    _, _, _, _, candidate_valid = split_source_coordinates(
        candidate_x, candidate_y, width=width, height=height
    )
    return CandidateMetrics(
        max_error_pixels=float(np.max(errors)),
        mean_error_pixels=float(np.mean(errors)),
        rmse_pixels=float(np.sqrt(np.mean(errors * errors))),
        coord_valid_mismatches=int(np.count_nonzero(baseline_valid != candidate_valid)),
        ranges=ranges,
    )


def build_distortion_map_fixed(
    width: int,
    height: int,
    camera: FixedPointCameraModel,
    config: FixedPointConfig = DEFAULT_CONFIG,
) -> tuple[NDArray[np.int64], NDArray[np.int64]]:
    """Build Q13.19 source maps for an output frame."""

    if width <= 0 or height <= 0:
        raise ValueError("width and height must be greater than zero")
    output_y, output_x = np.indices((height, width), dtype=np.int64)
    return source_coordinates_fixed(output_x, output_y, camera, config=config)


def split_fixed_coordinate(
    coordinate: int,
    frac_bits: int = DEFAULT_CONFIG.src_coord_frac_bits,
) -> tuple[int, int]:
    """Return mathematical floor and non-negative fractional remainder."""

    if frac_bits < 0:
        raise ValueError("frac_bits must be non-negative")
    integer_part = int(coordinate) >> frac_bits
    fractional_part = int(coordinate) - (integer_part << frac_bits)
    return integer_part, fractional_part


def split_source_coordinates(
    source_x: ArrayLike,
    source_y: ArrayLike,
    *,
    width: int,
    height: int,
    config: FixedPointConfig = DEFAULT_CONFIG,
) -> tuple[
    NDArray[np.int64],
    NDArray[np.int64],
    NDArray[np.int64],
    NDArray[np.int64],
    NDArray[np.bool_],
]:
    """Split Q13.19 coordinates and determine four-neighbor validity."""

    x = _object_array(source_x)
    y = _object_array(source_y)
    if x.shape != y.shape:
        raise ValueError("source_x and source_y must have equal shapes")

    x0 = _elementwise(x, lambda value: split_fixed_coordinate(value, config.src_coord_frac_bits)[0])
    y0 = _elementwise(y, lambda value: split_fixed_coordinate(value, config.src_coord_frac_bits)[0])
    dx_full = _elementwise(x, lambda value: split_fixed_coordinate(value, config.src_coord_frac_bits)[1])
    dy_full = _elementwise(y, lambda value: split_fixed_coordinate(value, config.src_coord_frac_bits)[1])
    dx = _rescale(dx_full, config.src_coord_frac_bits, config.interpolation_frac_bits)
    dy = _rescale(dy_full, config.src_coord_frac_bits, config.interpolation_frac_bits)

    valid = (
        (x0 >= 0)
        & (x0 < width - 1)
        & (y0 >= 0)
        & (y0 < height - 1)
    )
    return (
        _as_int64(x0),
        _as_int64(y0),
        _as_int64(dx),
        _as_int64(dy),
        np.asarray(valid, dtype=np.bool_),
    )


def source_coordinate_trace(
    u: int,
    v: int,
    camera: FixedPointCameraModel,
    *,
    width: int = 1280,
    height: int = 720,
    config: FixedPointConfig = DEFAULT_CONFIG,
) -> dict[str, int | bool]:
    """Return one RTL-ready Q-format coordinate transaction.

    The trace exposes the same externally visible fields as the final stage
    of ``distortion_core.sv``.  It is deliberately scalar so a testbench or
    vector generator can compare an individual transaction without relying
    on NumPy array layout.
    """

    if width <= 1 or height <= 1:
        raise ValueError("width and height must both be greater than one")

    source_x, source_y = source_coordinates_fixed(
        np.asarray([[u]], dtype=np.int64),
        np.asarray([[v]], dtype=np.int64),
        camera,
        config=config,
    )
    x0, y0, dx, dy, coord_valid = split_source_coordinates(
        source_x,
        source_y,
        width=width,
        height=height,
        config=config,
    )
    return {
        "src_x": int(source_x[0, 0]),
        "src_y": int(source_y[0, 0]),
        "x0": int(x0[0, 0]),
        "y0": int(y0[0, 0]),
        "dx": int(dx[0, 0]),
        "dy": int(dy[0, 0]),
        "coord_valid": bool(coord_valid[0, 0]),
    }


def bilinear_remap_fixed(
    image: ArrayLike,
    source_x: ArrayLike,
    source_y: ArrayLike,
    *,
    border_value: int = 0,
    config: FixedPointConfig = DEFAULT_CONFIG,
) -> NDArray[np.uint8]:
    """Remap an image with integer two-stage bilinear interpolation.

    The interpolation keeps both horizontal and vertical products in integer
    form and performs the final arithmetic right shift by 32 bits.  Pixels
    whose four neighbors are not available are filled with ``border_value``.
    """

    source = np.asarray(image)
    if source.ndim not in (2, 3):
        raise ValueError("image must be a 2-D grayscale or 3-D color array")
    if not 0 <= border_value <= 255:
        raise ValueError("border_value must be in the range 0..255")

    height, width = source.shape[:2]
    map_x = np.asarray(source_x, dtype=np.int64)
    map_y = np.asarray(source_y, dtype=np.int64)
    if map_x.ndim != 2 or map_y.ndim != 2 or map_x.shape != map_y.shape:
        raise ValueError("source maps must be 2-D arrays with equal shapes")

    x0, y0, dx, dy, valid = split_source_coordinates(
        map_x,
        map_y,
        width=width,
        height=height,
        config=config,
    )
    output_shape = map_x.shape + (() if source.ndim == 2 else (source.shape[2],))
    output = np.full(output_shape, border_value, dtype=np.uint8)
    if not np.any(valid):
        return output

    rows, columns = np.nonzero(valid)
    x_valid = x0[valid]
    y_valid = y0[valid]
    dx_valid = dx[valid]
    dy_valid = dy[valid]
    scale = config.interpolation_scale

    p00 = source[y_valid, x_valid].astype(np.int64)
    p10 = source[y_valid, x_valid + 1].astype(np.int64)
    p01 = source[y_valid + 1, x_valid].astype(np.int64)
    p11 = source[y_valid + 1, x_valid + 1].astype(np.int64)
    if source.ndim == 3:
        dx_valid = dx_valid[:, np.newaxis]
        dy_valid = dy_valid[:, np.newaxis]

    top = p00 * scale + (p10 - p00) * dx_valid
    bottom = p01 * scale + (p11 - p01) * dx_valid
    result = (top * scale + (bottom - top) * dy_valid) >> (2 * config.interpolation_frac_bits)
    result = np.clip(result, 0, 255).astype(np.uint8)
    output[rows, columns] = result
    return output


def correct_distortion_fixed(
    image: ArrayLike,
    camera: FixedPointCameraModel,
    *,
    border_value: int = 0,
    config: FixedPointConfig = DEFAULT_CONFIG,
) -> tuple[NDArray[np.uint8], NDArray[np.int64], NDArray[np.int64]]:
    """Return ``(corrected_image, source_x, source_y)`` for a fixed camera."""

    source = np.asarray(image)
    if source.ndim not in (2, 3):
        raise ValueError("image must be a 2-D grayscale or 3-D color array")

    height, width = source.shape[:2]
    map_x, map_y = build_distortion_map_fixed(width, height, camera, config=config)
    corrected = bilinear_remap_fixed(
        source,
        map_x,
        map_y,
        border_value=border_value,
        config=config,
    )
    return corrected, map_x, map_y

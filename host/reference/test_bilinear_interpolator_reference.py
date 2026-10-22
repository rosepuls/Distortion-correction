import pytest

from bilinear_interpolator_reference import bilinear_interpolate_rgbx8888


def rgbx(r, g, b, x=0):
    return (r << 24) | (g << 16) | (b << 8) | x


def test_zero_fraction_selects_p00_and_forces_x_to_zero():
    pixel = bilinear_interpolate_rgbx8888(
        rgbx(12, 34, 56, 0xAA),
        rgbx(200, 201, 202),
        rgbx(210, 211, 212),
        rgbx(220, 221, 222),
        fx=0,
        fy=0,
    )

    assert pixel == rgbx(12, 34, 56)


def test_half_pixel_returns_exact_four_pixel_average():
    pixel = bilinear_interpolate_rgbx8888(
        rgbx(10, 20, 30),
        rgbx(20, 30, 40),
        rgbx(30, 40, 50),
        rgbx(40, 50, 60),
        fx=0x8000,
        fy=0x8000,
    )

    assert pixel == rgbx(25, 35, 45)


def test_invalid_neighbors_contribute_black_without_renormalization():
    pixel = bilinear_interpolate_rgbx8888(
        rgbx(255, 255, 255),
        rgbx(100, 20, 40),
        rgbx(255, 255, 255),
        rgbx(200, 60, 80),
        fx=0xC000,
        fy=0x8000,
        neighbor_valid=0b1010,
    )

    assert pixel == rgbx(113, 30, 45)


def test_rounds_half_up_after_full_precision_accumulation():
    pixel = bilinear_interpolate_rgbx8888(
        rgbx(0, 0, 0),
        rgbx(1, 1, 1),
        rgbx(0, 0, 0),
        rgbx(1, 1, 1),
        fx=0x8000,
        fy=0,
    )

    assert pixel == rgbx(1, 1, 1)


def test_no_valid_neighbors_produce_black():
    assert bilinear_interpolate_rgbx8888(
        rgbx(255, 1, 2),
        rgbx(3, 255, 4),
        rgbx(5, 6, 255),
        rgbx(255, 255, 255),
        fx=0x1234,
        fy=0x5678,
        neighbor_valid=0,
    ) == 0


def test_full_scale_white_does_not_overflow_wide_accumulator():
    assert bilinear_interpolate_rgbx8888(
        rgbx(255, 255, 255),
        rgbx(255, 255, 255),
        rgbx(255, 255, 255),
        rgbx(255, 255, 255),
        fx=0xE731,
        fy=0x294A,
    ) == rgbx(255, 255, 255)


@pytest.mark.parametrize("fx,fy", [(-1, 0), (0x10000, 0), (0, -1), (0, 0x10000)])
def test_fraction_must_fit_unsigned_q0_16(fx, fy):
    with pytest.raises(ValueError):
        bilinear_interpolate_rgbx8888(0, 0, 0, 0, fx=fx, fy=fy)

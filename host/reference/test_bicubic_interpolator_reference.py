from bicubic_interpolator_reference import (
    bicubic_interpolate_rgbx8888,
    catmull_rom_weights_q14,
)


def pixel(r, g, b, x=0):
    return (r << 24) | (g << 16) | (b << 8) | x


def neighborhood(rows):
    return [[pixel(value, value, value, 0xA5) for value in row] for row in rows]


def test_catmull_rom_half_weights_are_signed_and_sum_to_one():
    weights = catmull_rom_weights_q14(0x8000)
    assert weights == (-1_024, 9_216, 9_216, -1_024)
    assert sum(weights) == 1 << 14


def test_integer_coordinate_reproduces_center_sample_exactly():
    samples = neighborhood([
        [0, 20, 40, 60],
        [80, 100, 120, 140],
        [160, 180, 200, 220],
        [240, 250, 255, 10],
    ])

    result = bicubic_interpolate_rgbx8888(samples, 0, 0)

    assert result == pixel(100, 100, 100)


def test_half_pixel_linear_ramp_matches_linear_value():
    samples = neighborhood([
        [10, 20, 30, 40],
        [10, 20, 30, 40],
        [10, 20, 30, 40],
        [10, 20, 30, 40],
    ])

    result = bicubic_interpolate_rgbx8888(samples, 0x8000, 0x8000)

    assert result == pixel(25, 25, 25)


def test_constant_neighborhood_is_preserved_and_rgbx_padding_is_zero():
    samples = [[pixel(73, 131, 249) for _ in range(4)] for _ in range(4)]

    result = bicubic_interpolate_rgbx8888(samples, 0x3456, 0xABCD)

    assert result == pixel(73, 131, 249)


def test_catmull_rom_overshoot_is_saturated_to_rgb_range():
    high = neighborhood([
        [0, 255, 255, 0],
        [0, 255, 255, 0],
        [0, 255, 255, 0],
        [0, 255, 255, 0],
    ])
    low = neighborhood([
        [255, 0, 0, 255],
        [255, 0, 0, 255],
        [255, 0, 0, 255],
        [255, 0, 0, 255],
    ])

    assert bicubic_interpolate_rgbx8888(high, 0x4000, 0) == pixel(255, 255, 255)
    assert bicubic_interpolate_rgbx8888(low, 0x4000, 0) == pixel(0, 0, 0)

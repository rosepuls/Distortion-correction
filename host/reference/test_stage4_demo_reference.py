from stage4_demo_reference import map_demo_radial, procedural_pixel, stage4_demo_pixel


def test_radial_center_and_corner_match_rtl_literals():
    assert map_demo_radial(640, 360) == (0x02800000, 0x01680000)
    assert map_demo_radial(1279, 719) == (0x0527EBD5, 0x02E5FD7B)


def test_procedural_gradient_and_grid_colors():
    assert procedural_pixel(5, 7) == 0x05070200
    assert procedural_pixel(6, 8) == 0x06080E00
    assert procedural_pixel(64, 65) == 0xFFFFFF00
    assert procedural_pixel(1279, 719) == 0xFFFFFF00


def test_fractional_and_black_border_pipeline_pixels_match_rtl_literals():
    assert stage4_demo_pixel(1240, 360) == 0xF2689A00
    assert stage4_demo_pixel(1000, 500) == 0xEEF61800
    assert stage4_demo_pixel(0, 0) == 0x00000000
    assert stage4_demo_pixel(1279, 719) == 0x00000000

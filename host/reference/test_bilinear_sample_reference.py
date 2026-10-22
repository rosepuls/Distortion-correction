import pytest

from bilinear_sample_reference import plan_bilinear


def test_interior_coordinate_uses_floor_and_q16_fraction():
    plan = plan_bilinear(0x00054000, 0x00078000)

    assert plan == {
        "x0": 5,
        "x1": 6,
        "y0": 7,
        "y1": 8,
        "fx": 0x4000,
        "fy": 0x8000,
        "neighbor_valid": 0b1111,
        "geometry_valid": True,
    }


def test_negative_fraction_has_floor_minus_one_and_partial_black_mask():
    plan = plan_bilinear(-0x00004000, 0x00008000, border_mode="black")

    assert plan["x0"] == 0
    assert plan["x1"] == 0
    assert plan["y0"] == 0
    assert plan["y1"] == 1
    assert plan["fx"] == 0xC000
    assert plan["fy"] == 0x8000
    assert plan["neighbor_valid"] == 0b1010


def test_lower_right_fraction_keeps_only_p00_in_black_mode():
    plan = plan_bilinear(0x04FFC000, 0x02CF4000, border_mode="black")

    assert (plan["x0"], plan["x1"]) == (1279, 1279)
    assert (plan["y0"], plan["y1"]) == (719, 719)
    assert (plan["fx"], plan["fy"]) == (0xC000, 0x4000)
    assert plan["neighbor_valid"] == 0b0001


def test_replicate_clamps_coordinates_but_preserves_fraction():
    plan = plan_bilinear(-0x00004000, 0x02CF4000, border_mode="replicate")

    assert (plan["x0"], plan["x1"]) == (0, 0)
    assert (plan["y0"], plan["y1"]) == (719, 719)
    assert (plan["fx"], plan["fy"]) == (0xC000, 0x4000)
    assert plan["neighbor_valid"] == 0b1111


@pytest.mark.parametrize("border_mode", ["black", "replicate"])
def test_geometry_invalid_clears_every_neighbor(border_mode):
    plan = plan_bilinear(0x00010000, 0x00020000,
                         border_mode=border_mode, geometry_valid=False)

    assert plan["geometry_valid"] is False
    assert plan["neighbor_valid"] == 0


@pytest.mark.parametrize("width,height", [(0, 720), (1280, 0), (-1, 720)])
def test_dimensions_must_be_positive(width, height):
    with pytest.raises(ValueError):
        plan_bilinear(0, 0, width=width, height=height)


def test_border_mode_must_be_known():
    with pytest.raises(ValueError):
        plan_bilinear(0, 0, border_mode="mirror")

"""Behavior tests for the public Q16.16 identity-mapping reference."""

from __future__ import annotations

import importlib

import pytest


def reference_module():
    try:
        return importlib.import_module("host.reference.identity_map_reference")
    except ModuleNotFoundError as exc:
        pytest.fail(f"identity-map reference is not implemented: {exc}")


def test_identity_map_encodes_720p_corner_coordinates_exactly() -> None:
    reference = reference_module()

    assert reference.identity_map(0, 0) == (0, 0, True)
    assert reference.identity_map(1279, 719) == (83_820_544, 47_120_384, True)


def test_identity_map_reports_exact_q16_16_jacobian() -> None:
    reference = reference_module()

    assert reference.identity_jacobian() == (65_536, 0, 0, 65_536, True)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        (0x0001_8000, (1, 0x8000)),
        (-0x0000_8000, (-1, 0x8000)),
        (-0x0001_0001, (-2, 0xFFFF)),
    ],
)
def test_split_q16_16_uses_mathematical_floor_for_negative_coordinates(
    raw: int, expected: tuple[int, int]
) -> None:
    reference = reference_module()

    assert reference.split_q16_16(raw) == expected


def test_identity_frame_reference_assigns_order_and_boundary_metadata() -> None:
    reference = reference_module()

    records = list(
        reference.iter_identity_frame(
            width=3,
            height=2,
            frame_id=0x1234,
            param_version=7,
        )
    )

    assert records == [
        {
            "u": 0, "v": 0, "pixel_id": 0,
            "sx_q16_16": 0, "sy_q16_16": 0,
            "geometry_valid": True, "frame_id": 0x1234, "param_version": 7,
            "jacobian_q16_16": (65_536, 0, 0, 65_536), "j_valid": True,
            "sof": True, "eol": False, "eof": False,
        },
        {
            "u": 1, "v": 0, "pixel_id": 1,
            "sx_q16_16": 65_536, "sy_q16_16": 0,
            "geometry_valid": True, "frame_id": 0x1234, "param_version": 7,
            "jacobian_q16_16": (65_536, 0, 0, 65_536), "j_valid": True,
            "sof": False, "eol": False, "eof": False,
        },
        {
            "u": 2, "v": 0, "pixel_id": 2,
            "sx_q16_16": 131_072, "sy_q16_16": 0,
            "geometry_valid": True, "frame_id": 0x1234, "param_version": 7,
            "jacobian_q16_16": (65_536, 0, 0, 65_536), "j_valid": True,
            "sof": False, "eol": True, "eof": False,
        },
        {
            "u": 0, "v": 1, "pixel_id": 3,
            "sx_q16_16": 0, "sy_q16_16": 65_536,
            "geometry_valid": True, "frame_id": 0x1234, "param_version": 7,
            "jacobian_q16_16": (65_536, 0, 0, 65_536), "j_valid": True,
            "sof": False, "eol": False, "eof": False,
        },
        {
            "u": 1, "v": 1, "pixel_id": 4,
            "sx_q16_16": 65_536, "sy_q16_16": 65_536,
            "geometry_valid": True, "frame_id": 0x1234, "param_version": 7,
            "jacobian_q16_16": (65_536, 0, 0, 65_536), "j_valid": True,
            "sof": False, "eol": False, "eof": False,
        },
        {
            "u": 2, "v": 1, "pixel_id": 5,
            "sx_q16_16": 131_072, "sy_q16_16": 65_536,
            "geometry_valid": True, "frame_id": 0x1234, "param_version": 7,
            "jacobian_q16_16": (65_536, 0, 0, 65_536), "j_valid": True,
            "sof": False, "eol": True, "eof": True,
        },
    ]


@pytest.mark.parametrize(
    ("width", "height"),
    [(0, 1), (1, 0), (-1, 1), (1, -1)],
)
def test_identity_frame_reference_rejects_non_positive_dimensions(
    width: int, height: int
) -> None:
    reference = reference_module()

    with pytest.raises(ValueError, match="positive"):
        list(reference.iter_identity_frame(width, height))

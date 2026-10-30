"""Generate monotonic 8-bit enhancement LUTs from editable JSON parameters."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np

from lighting_profile import PROFILE_NAMES


def load_parameters(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        config = json.load(stream)
    if config.get("schema_version") != 1:
        raise ValueError("unsupported lighting curve schema_version")
    profiles = config.get("profiles")
    expected_ids = {str(profile_id) for profile_id in PROFILE_NAMES}
    if not isinstance(profiles, dict) or set(profiles) != expected_ids:
        raise ValueError("curve parameters must define profile IDs 0 through 5")
    for profile_id, name in PROFILE_NAMES.items():
        if profiles[str(profile_id)].get("name") != name:
            raise ValueError(f"profile {profile_id} must be named {name!r}")
    return config


def _gamma(values: np.ndarray, gamma: float) -> np.ndarray:
    if not 0.0 < gamma <= 1.0:
        raise ValueError("gamma must be in (0, 1]")
    normalized = values.astype(np.float64) / 255.0
    return 255.0 * np.power(normalized, gamma)


def _shoulder(values: np.ndarray, knee: int, power: float) -> np.ndarray:
    if not 0 <= knee < 255:
        raise ValueError("knee must be in [0, 254]")
    if power < 1.0:
        raise ValueError("shoulder power must be at least 1")
    output = values.astype(np.float64).copy()
    mask = values > knee
    span = 255.0 - knee
    normalized = (values[mask] - knee) / span
    output[mask] = knee + span * np.power(normalized, power)
    return output


def generate_luts(config: dict[str, Any]) -> dict[int, np.ndarray]:
    """Return profile ID to 256-entry uint8 lookup table."""
    values = np.arange(256, dtype=np.float64)
    luts: dict[int, np.ndarray] = {}
    for profile_id in PROFILE_NAMES:
        parameters = config["profiles"][str(profile_id)]
        kind = parameters.get("kind")
        if kind == "identity":
            output = values.copy()
        elif kind == "gamma":
            output = _gamma(values, float(parameters["gamma"]))
        elif kind == "shoulder":
            output = _shoulder(values, int(parameters["knee"]),
                               float(parameters["power"]))
        elif kind == "toe_shoulder":
            toe = _gamma(values, float(parameters["gamma"]))
            output = _shoulder(toe, int(parameters["knee"]),
                               float(parameters["power"]))
        else:
            raise ValueError(f"unsupported curve kind for profile {profile_id}: {kind}")

        table = np.clip(np.rint(output), 0, 255).astype(np.uint8)
        if table.shape != (256,) or np.any(np.diff(table.astype(np.int16)) < 0):
            raise ValueError(f"profile {profile_id} LUT must be monotonic with 256 entries")
        if table[0] != 0 or table[255] != 255:
            raise ValueError(f"profile {profile_id} LUT must preserve endpoints 0 and 255")
        luts[profile_id] = table
    return luts

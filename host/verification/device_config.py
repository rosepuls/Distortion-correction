"""Shared video and UART device defaults for the verification scripts."""

from __future__ import annotations

import json
from pathlib import Path


CONFIG_PATH = Path(__file__).with_name("device_config.json")


def load_device_config() -> dict:
    data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    for key in ("obs_virtual_camera_index", "hdmi_capture_index", "width", "height"):
        if not isinstance(data.get(key), int) or data[key] < 0:
            raise ValueError(f"{CONFIG_PATH}: invalid {key}")
    if data["obs_virtual_camera_index"] == data["hdmi_capture_index"]:
        raise ValueError(f"{CONFIG_PATH}: OBS and HDMI capture indices must differ")
    if not isinstance(data.get("uart_port"), str) or not data["uart_port"].upper().startswith("COM"):
        raise ValueError(f"{CONFIG_PATH}: invalid uart_port")
    if data["width"] < 1 or data["height"] < 1:
        raise ValueError(f"{CONFIG_PATH}: video dimensions must be positive")
    return data

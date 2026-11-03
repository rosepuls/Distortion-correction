"""Replace the frame-rate FIC buses with frame timing and backpressure probes."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
rtl = root / "source/rtl/fram_buf.v"
fic = root / "synthesize/HDMI_IN_DDR3_HDMI_OUT_top_syn.fic"

frame = rtl.read_bytes().decode("cp1252")
for name in ("copied_count", "capture_dropped_count", "output_dropped_count"):
    pattern = re.compile(r"(\b" + name + r"\s*/\* synthesis PAP_MARK_DEBUG=\")true(\" \*/)" )
    frame, count = pattern.subn(r"\g<1>1\g<2>", frame)
    if count != 1:
        raise RuntimeError(f"expected one debug marker for {name}, got {count}")
rtl.write_bytes(frame.encode("cp1252"))

source = fic.read_text(encoding="utf-8")
header = source.split("Project.unit<0>.triggerChannel<0><0>=", 1)[0]
footer = "Project.unit<0>.triggerMatchCount<0>=" + source.split(
    "Project.unit<0>.triggerMatchCount<0>=", 1
)[1]
groups = [
    ("input_published_count", 32),
    ("display_take_count", 32),
    ("copy_last_frame_cycles", 32),
    ("copy_last_frame_request_stall_cycles", 32),
]
lines = [header.rstrip("\n")]
start = 0
for group_index, (name, width) in enumerate(groups):
    path = f"fram_buf/{name}"
    channels = list(range(start, start + width))
    for bit, channel in enumerate(channels):
        lines.append(f"Project.unit<0>.triggerChannel<0><{channel}>={path}[{bit}]")
    lines.append(f"Project.unit<0>.triggerBus<0><{start}><{start + width - 1}>={path}")
    joined = "/".join(map(str, channels))
    lines.append(f"Project.unit<0>.busInserter<{group_index}><{joined}>={path}")
    start += width
assert start == 128
footer = re.sub(r"Project.unit<0>.triggerPortWidth<0>=\d+",
                "Project.unit<0>.triggerPortWidth<0>=128", footer)
lines.append(footer.rstrip("\n"))
fic.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"PASS: configured {start} Stage12 profile channels")

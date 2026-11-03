"""Reduce the Stage 12 debug probe to the five essential frame-rate counters."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
rtl = root / "source/rtl/fram_buf.v"
fic = root / "synthesize/HDMI_IN_DDR3_HDMI_OUT_top_syn.fic"

frame = rtl.read_bytes().decode("cp1252")
for signal in (
    "copy_error_count", "copy_fetched_rows", "display_read_error_count",
    "read_arbiter_error_count", "incomplete_output_count", "pipeline_status",
):
    pattern = re.compile(r"(\b" + signal + r"\s*/\* synthesis PAP_MARK_DEBUG=\")true(\" \*/)" )
    frame, count = pattern.subn(r"\g<1>1\g<2>", frame)
    if count != 1:
        raise RuntimeError(f"expected one debug marker for {signal}, got {count}")
rtl.write_bytes(frame.encode("cp1252"))

source = fic.read_text(encoding="utf-8")
header = source.split("Project.unit<0>.triggerChannel<0><0>=", 1)[0]
footer = "Project.unit<0>.triggerMatchCount<0>=" + source.split(
    "Project.unit<0>.triggerMatchCount<0>=", 1
)[1]
footer = footer.replace("Project.unit<0>.triggerPortWidth<0>=256",
                        "Project.unit<0>.triggerPortWidth<0>=128")
groups = [
    ("input_published_count", 32),
    ("copied_count", 32),
    ("display_take_count", 32),
    ("capture_dropped_count", 16),
    ("output_dropped_count", 16),
]
lines = [header.rstrip("\n")]
start = 0
for group_index, (name, width) in enumerate(groups):
    path = f"fram_buf/{name}"
    channels = list(range(start, start + width))
    for bit, channel in enumerate(channels):
        lines.append(f"Project.unit<0>.triggerChannel<0><{channel}>={path}[{bit}]")
    lines.append(f"Project.unit<0>.triggerBus<0><{start}><{start+width-1}>={path}")
    lines.append(f"Project.unit<0>.busInserter<{group_index}><{'/'.join(map(str, channels))}>={path}")
    start += width
assert start == 128
lines.append(footer.rstrip("\n"))
fic.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("PASS: reduced DebugCore to 128 frame-rate channels")

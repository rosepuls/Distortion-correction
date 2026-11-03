"""Add a frame-rate Fabric DebugCore to this isolated Stage 12 project once."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
rtl = root / "source/rtl/fram_buf.v"
project = root / "HDMI_IN_DDR3_HDMI_OUT.pds"
template = root.parent / "stage11_720p60hz_adaptive_image_enhancement_test/debug_core.fic"
fic = root / "synthesize/HDMI_IN_DDR3_HDMI_OUT_top_syn.fic"


def one(text, old, new):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"expected one anchor, got {count}: {old[:70]!r}")
    return text.replace(old, new)


frame = rtl.read_bytes().decode("cp1252")
if "input_published_count" in frame:
    raise RuntimeError("Debug counters already present")
frame = one(frame, "    wire copy_active;", """    wire copy_active;
    wire [31:0] copy_fetched_rows /* synthesis PAP_MARK_DEBUG=\"true\" */;
    reg [31:0] input_published_count /* synthesis PAP_MARK_DEBUG=\"true\" */;
    reg [31:0] display_take_count /* synthesis PAP_MARK_DEBUG=\"true\" */;""")
for signal in (
    "copied_count", "copy_error_count", "capture_dropped_count",
    "output_dropped_count", "display_read_error_count",
    "read_arbiter_error_count", "incomplete_output_count", "pipeline_status",
):
    pattern = re.compile(r"(\b" + signal + r"\s*/\* synthesis PAP_MARK_DEBUG=\")1(\" \*/)" )
    frame, count = pattern.subn(r"\g<1>true\g<2>", frame)
    if count != 1:
        raise RuntimeError(f"debug marker not found once: {signal}, {count}")
frame = one(frame, ".fetched_rows(), .tile_read_errors()",
            ".fetched_rows(copy_fetched_rows), .tile_read_errors()")
frame = one(frame, "    frame_pipeline_ownership ownership (", """    wire output_take_event = output_frame_start && display_take_ready &&
        (!display_valid || output_frame_complete);
    frame_pipeline_ownership ownership (""")
frame, count = re.subn(
    r"\.display_take\(output_frame_start && display_take_ready &&\s*\(!display_valid \|\| output_frame_complete\)\),",
    ".display_take(output_take_event),", frame,
)
if count != 1:
    raise RuntimeError("display_take anchor missing")
frame = one(frame, "            seen_output_vsync <= 1'b0;", """            seen_output_vsync <= 1'b0;
            input_published_count <= 32'd0;
            display_take_count <= 32'd0;""")
frame = one(frame, "        end else begin\r\n            if (output_frame_start)", """        end else begin
            if (capture_publish && input_published_count != 32'hffff_ffff)
                input_published_count <= input_published_count + 1'b1;
            if (output_take_event && display_take_count != 32'hffff_ffff)
                display_take_count <= display_take_count + 1'b1;
            if (output_frame_start)""".replace("\n", "\r\n"))
rtl.write_bytes(frame.encode("cp1252"))

groups = [
    ("input_published_count", 32),
    ("copied_count", 32),
    ("display_take_count", 32),
    ("capture_dropped_count", 16),
    ("output_dropped_count", 16),
    ("copy_error_count", 32),
    ("copy_fetched_rows", 32),
    ("display_read_error_count", 16),
    ("read_arbiter_error_count", 16),
    ("incomplete_output_count", 16),
    ("pipeline_status", 16),
]
assert sum(width for _, width in groups) == 256
source = template.read_text(encoding="utf-8")
header = source.split("Project.unit<0>.triggerChannel<0><0>=", 1)[0]
footer = "Project.unit<0>.triggerMatchCount<0>=" + source.split(
    "Project.unit<0>.triggerMatchCount<0>=", 1
)[1]
header = re.sub(
    r"Project.device.designInputFile=.*",
    "Project.device.designInputFile=" +
    (root / "synthesize/HDMI_IN_DDR3_HDMI_OUT_top_syn.adf").as_posix(),
    header,
)
header = header.replace("#Generated for stage5_identity_fps_debug",
                        "#Generated for stage12_1080p60_cache8_test")
lines = [header.rstrip("\n")]
start = 0
for group_index, (name, width) in enumerate(groups):
    path = f"fram_buf/{name}"
    channels = list(range(start, start + width))
    for bit, channel in enumerate(channels):
        lines.append(f"Project.unit<0>.triggerChannel<0><{channel}>={path}[{bit}]")
    lines.append(f"Project.unit<0>.triggerBus<0><{start}><{start+width-1}>={path}")
    joined = "/".join(map(str, channels))
    lines.append(f"Project.unit<0>.busInserter<{group_index}><{joined}>={path}")
    start += width
lines.append(footer.rstrip("\n"))
fic.parent.mkdir(exist_ok=True)
fic.write_text("\n".join(lines) + "\n", encoding="utf-8")

pds = project.read_text(encoding="utf-8")
pds, count = re.subn(
    r"\(_widget wgt_my_fic_src\s*\)",
    '(_widget wgt_my_fic_src\n            (_input\n'
    '                (_file "synthesize/HDMI_IN_DDR3_HDMI_OUT_top_syn.fic"\n'
    '                    (_format text)\n'
    '                    (_timespec "2026-10-30T00:00:00")\n'
    '                )\n            )\n        )',
    pds,
)
if count != 1:
    raise RuntimeError(f"PDS FIC widget anchor count: {count}")
project.write_text(pds, encoding="utf-8")
print(f"PASS: configured {start} debug channels in {fic}")

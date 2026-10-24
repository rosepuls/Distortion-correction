"""Map this project's 256 Fabric Debugger channels after cloning it."""

from pathlib import Path


ROOT = Path(__file__).resolve().parent
FIC = ROOT / "synthesize/HDMI_IN_DDR3_HDMI_OUT_top_syn.fic"
BUSES = [
    ("raw_input_vsync_count", 16),
    ("input_published_count", 16),
    ("copied_count", 16),
    ("display_take_count", 16),
    ("capture_dropped_count", 16),
    ("perf_error_flags", 8),
    ("perf_frame_cycles", 24),
    ("perf_coord_stall_cycles", 24),
    ("perf_cache_miss_count", 24),
    ("perf_cache_fill_cycles", 24),
    ("perf_write_phase_cycles", 24),
    ("perf_write_wait_cycles", 24),
    ("copy_frame_cycles_max", 24),
]

lines = FIC.read_text(encoding="utf-8").splitlines()
start = next(i for i, line in enumerate(lines)
             if line.startswith("Project.unit<0>.triggerChannel<0><"))
end = next(i for i, line in enumerate(lines)
           if line.startswith("Project.unit<0>.triggerMatchCount<0>="))
generated = []
offset = 0
for bus_id, (signal, width) in enumerate(BUSES):
    indices = list(range(offset, offset + width))
    for bit, channel in enumerate(indices):
        generated.append(
            f"Project.unit<0>.triggerChannel<0><{channel}>="
            f"fram_buf/{signal}[{bit}]"
        )
    generated.append(
        f"Project.unit<0>.triggerBus<0><{indices[0]}><{indices[-1]}>="
        f"fram_buf/{signal}"
    )
    generated.append(
        f"Project.unit<0>.busInserter<{bus_id}><{'/'.join(map(str, indices))}>="
        f"fram_buf/{signal}"
    )
    offset += width
if offset != 256:
    raise RuntimeError(f"Expected 256 FIC bits, got {offset}")
FIC.write_text("\n".join(lines[:start] + generated + lines[end:]) + "\n",
               encoding="utf-8")
print("Configured Stage 7 write-overlap 256-bit FIC map")

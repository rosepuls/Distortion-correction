# Stage 8 Rotation Performance Diagnostic Design

## Goal

Create an isolated Stage 8 test project that exposes the existing per-frame cache and DDR read diagnostics needed to investigate the rotation-related throughput drop, without changing the mapping, cache, interpolation, or frame-processing behavior.

## Current findings

The source project already computes and latches these values for the most recently completed frame in `frame_identity_transform_engine.sv`:

- `perf_cache_miss_count`
- `perf_cache_fill_cycles`
- `perf_read_response_wait_cycles`
- `perf_frame_cycles`
- `perf_coord_stall_cycles`

The source project also has published, completed, and display-take frame counters; capture drop/reject/abort counters; and a 16-bit `perf_error_flags` signal. The current 256-channel FIC does not expose all of the performance buses. Therefore the diagnostic project will primarily change debug preservation, FIC wiring, build validation, and measurement documentation.

## Approaches considered

1. **Recommended: expose existing counters in a cloned project.** This keeps the change limited to a new project copy and debug configuration. It is sufficient to compare cache misses and fill/read wait cycles against total processing and coordinate-stall cycles during the same rotated workload.
2. Add new cache hit counters and more granular DDR state counters. This could provide additional detail, but changes more RTL and adds implementation/timing risk before the existing counters have been measured.

The first approach is selected. The algorithm and data path remain unchanged.

## Project isolation

Copy `fpga/project/stage8_720p60hz_bilinear_uart_angle_correction` to `fpga/project/stage8_rotation_perf_diag_test`. Perform all edits and builds only in the new directory. Preserve the source project and the current working tree, including its pre-existing changes and deletions. Keep the project inputs needed for PDS reproducible builds, including the `.pds`, FDC, RTL, IP sources, implementation script, waveform file, build script, and FIC template. Regenerated implementation outputs are local to the diagnostic copy.

The copied build script must validate 256 channel entries and the presence of each bus in the diagnostic map before copying the same-build FIC beside the generated bitstream. Its log and expected project paths must use the new project name.

## Diagnostic channel map

The FIC has exactly 256 trigger channels. Use this layout:

| Channels | Signal | Interpretation |
|---:|---|---|
| 0–23 | `input_published_count[23:0]` | Published input frames; low 24 bits |
| 24–47 | `copied_count[23:0]` | Completed processing frames; low 24 bits |
| 48–71 | `display_take_count[23:0]` | New processed frames taken for display; low 24 bits |
| 72–87 | `capture_dropped_count[15:0]` | Published READY input frames overwritten |
| 88–103 | `capture_rejected_count[15:0]` | Input frames rejected at capture admission |
| 104–119 | `capture_abort_count[15:0]` | Input capture abort events |
| 120–135 | `perf_error_flags[15:0]` | Existing sticky display/read/write/copy error flags |
| 136–159 | `perf_cache_miss_count[23:0]` | Cache misses in the most recently completed frame |
| 160–183 | `perf_cache_fill_cycles[23:0]` | Cache fill cycles in the most recently completed frame |
| 184–207 | `perf_read_response_wait_cycles[23:0]` | DDR read-response wait cycles in the most recently completed frame |
| 208–231 | `perf_frame_cycles[23:0]` | Total processing cycles in the most recently completed frame |
| 232–255 | `perf_coord_stall_cycles[23:0]` | Coordinate backpressure cycles in the most recently completed frame |

The three frame counters are exposed as their low 24 bits. A 30–60 second measurement window is far below the 2^24 wrap interval at 60 fps; calculate differences modulo 2^24. The existing 16-bit drop/reject/abort counters retain their existing wrap/saturation semantics. The performance buses are per-frame snapshots, not cumulative totals; read them directly at each snapshot and do not subtract successive snapshots.

`output_dropped_count`, `incomplete_output_count`, and `copy_error_count` will not have separate FIC buses in this revision. Their relevant sticky error conditions remain represented by `perf_error_flags`; the core frame-rate and input-loss counters remain directly observable.

## Measurement and interpretation

Capture matching-build `.sbit` and `.fic`, then take two time-stamped Listing snapshots 30–60 seconds apart for no-rotation and rotated settings under otherwise identical input conditions. For each window, compute published/completed/display frame-rate deltas and capture-drop/reject/abort deltas. At each endpoint, record the latest completed frame's miss, fill, DDR response-wait, total-cycle, and coordinate-stall snapshots.

Compare cache misses against the fixed 921,600 output pixels per 1280×720 frame. Compare fill and DDR response-wait values with coordinate stalls and total frame cycles. These counters can overlap and must not be summed as disjoint costs. Higher miss and fill counts under rotation would support a cache-locality explanation; high read-response wait with stable miss counts would point toward DDR latency/contestion. This diagnostic does not by itself prove a single causal bottleneck.

## Scope and acceptance

- The diagnostic project is a standalone copy; no source-project files are changed.
- Mapping, interpolation, cache dimensions/replacement behavior, UART protocol, and frame scheduling are unchanged.
- The new FIC contains exactly 256 channels matching the table and is copied from the same PDS build as the bitstream.
- The build validation checks all expected diagnostic bus names and channel count.
- The JTAG README documents the map, counter widths and snapshot semantics, modulo frame-rate calculation, and the no-rotation/rotation sampling procedure.
- Simulation or PDS construction may be limited by tool availability. Only completed checks may be reported; FIC edits alone do not constitute a successful bitstream build.

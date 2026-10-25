# Stage 8 baseline: Fabric Debugger channels

Use only the `.fic` generated with this project's `.sbit`. Capture Listing
twice about 60 seconds apart. Frame counters are cumulative; `perf_*` and
`copy_frame_cycles_max` are snapshots or maxima, so read them directly.

| Channels | Signal | Meaning |
| --- | --- | --- |
| 0–15 | `raw_input_vsync_count` | Input frame boundaries |
| 16–31 | `input_published_count[15:0]` | Complete input frames published |
| 32–47 | `copied_count[15:0]` | Completed processing frames |
| 48–63 | `display_take_count[15:0]` | New processed frames selected for display |
| 64–79 | `capture_dropped_count` | Published READY input frames overwritten |
| 80–87 | `perf_error_flags[7:0]` | Pipeline errors; expected zero |
| 88–111 | `perf_frame_cycles` | Latest complete processing frame through physical write drain |
| 112–135 | `perf_coord_stall_cycles` | `COLLECT` cycles with a blocked pixel request |
| 136–159 | `perf_cache_miss_count` | Cache misses in latest frame |
| 160–183 | `perf_cache_fill_cycles` | Cache refill and retry cycles in latest frame |
| 184–207 | `perf_write_phase_cycles` | Writer in output AW or W phase |
| 208–231 | `perf_write_wait_cycles` | Writer valid but DDR not ready |
| 232–255 | `copy_frame_cycles_max` | Longest completed processing frame since reset |

The new writer runs concurrently with coordinate collection. Write-phase,
cache-fill and coordinate-stall counters may overlap in time; they must not
be added to obtain `perf_frame_cycles`. The difference between write-phase
and write-wait counts includes successful AW and W handshake cycles. At
125 MHz, 125,000 cycles equal 1 ms; 60 fps allows about 2,083,333 cycles
between frames, and the 25% headroom target is 1,562,500 processing cycles.

For a fair comparison with Stage 7, use the same camera and scene. Check the
visible image and error flags,
then record all cumulative deltas and the terminal frame-cycle, maximum,
stall, cache and write-phase snapshots. The current FIC has no frame-gap
counter; a near-60 fps processing result alone does not establish the
25% headroom target.

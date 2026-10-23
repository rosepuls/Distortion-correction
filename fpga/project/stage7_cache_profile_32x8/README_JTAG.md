# Stage 7 cache profile: JTAG channel map

Program `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` and import the
matching `.fic` from the same build. Use a moving 1280×720@60 HDMI pattern.
Capture two Listing snapshots about 60 seconds apart for cumulative frame and
drop counts. Per-frame timing/cache fields show the most recently completed
transform at each capture.

| Channels | Signal | Meaning |
|---|---|---|
| 0–15 | `input_published_count[15:0]` | Published input frames, low 16 bits |
| 16–31 | `copied_count[15:0]` | Completed transforms, low 16 bits |
| 32–47 | `display_take_count[15:0]` | New output frames selected for display |
| 48–63 | `capture_dropped_count[15:0]` | Dropped input frames |
| 64–79 | `perf_error_flags[15:0]` | Error and live status flags; see bit map below |
| 80–103 | `perf_frame_cycles[23:0]` | DDR cycles from transform start through write drain |
| 104–127 | `perf_coord_stall_cycles[23:0]` | Cycles coordinate input was backpressured |
| 128–151 | `perf_cache_miss_count[23:0]` | Tile refill starts during the frame |
| 152–175 | `perf_cache_fill_cycles[23:0]` | Cycles spent refilling/retrying cache misses |
| 176–199 | `perf_read_ar_wait_cycles[23:0]` | Read request cycles waiting for arbiter/DDR acceptance |
| 200–223 | `perf_read_response_wait_cycles[23:0]` | Cycles waiting for DDR read data during a tile row |
| 224–247 | `perf_write_wait_cycles[23:0]` | Output AW and W backpressure cycles combined |
| 248–255 | `pipeline_status[7:0]` | Live status flags from the existing frame pipeline |

`perf_error_flags` bit 0 is display-read error, bit 1 read-arbiter error,
bit 2 write-arbiter error, bit 3 write-protocol error, bit 4 transform error,
bit 5 incomplete output, bit 6 display blocked, bit 7 fatal transform fault,
and bit 8 indicates an output drop. Bits 9–15 are reserved. A 24-bit cycle counter represents up to 134 ms at
125 MHz; values are per-frame snapshots, not cumulative totals.

The fixed mapper coefficients are visual trial values, not camera calibration.
The profile measures stalls for this exact mapper and input scene.

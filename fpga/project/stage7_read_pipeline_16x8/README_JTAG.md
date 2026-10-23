# Stage 7 read pipeline: JTAG channel map

Program this project's repaired `.sbit` (SHA-256 `1C76E121F392B1F459793E005C614E99E344DABCDCA298CDEA26E20119509913`) and import the matching `.fic` from the same build. The earlier bitstream with SHA-256 `726B8F73E43FFBEB146807D084AD37B0C516997075230F6C872D4B6681F4E771` deadlocks after the first cache row. Use the same moving 1280x720@60 HDMI input. Capture two Listing snapshots about 60 seconds apart. Frame counters are cumulative; the 24-bit performance counters are snapshots from the most recently completed transform.

| Channels | Signal | Meaning |
|---|---|---|
| 0–15 | `input_published_count[15:0]` | Published input frames, low 16 bits |
| 16–31 | `copied_count[15:0]` | Completed transforms, low 16 bits |
| 32–47 | `display_take_count[15:0]` | New output frames selected for display |
| 48–63 | `capture_dropped_count[15:0]` | Dropped input frames |
| 64–79 | `perf_error_flags[15:0]` | Error and live status flags; see Stage 7 README_JTAG.md |
| 80–103 | `perf_frame_cycles[23:0]` | Transform cycles through write drain |
| 104–127 | `perf_read_arbiter_wait_cycles[23:0]` | Client 1 waits while another read burst owns the arbiter or client 0 is selected |
| 128–151 | `perf_cache_miss_count[23:0]` | Tile refill starts in the frame |
| 152–175 | `perf_cache_fill_cycles[23:0]` | Cycles spent refilling/retrying cache misses |
| 176–199 | `perf_read_arready_wait_cycles[23:0]` | Client 1 selected, but DDR has not accepted its AR request |
| 200–223 | `perf_read_first_beat_wait_cycles[23:0]` | Cycles from accepted AR until the first R beat |
| 224–247 | `perf_read_interbeat_wait_cycles[23:0]` | Gaps waiting for later R beats within a tile row |
| 248–255 | `pipeline_status[7:0]` | Existing live pipeline status flags |

The four wait counters are independent diagnostic bins. The address bins partition the old aggregate AR wait; first-beat and inter-beat bins partition the old read-response wait. Counters saturate at 24'hffffff (about 134 ms at 125 MHz).

This candidate can have four transform row bursts outstanding under AXI ID 1. The adapter expects the DDR controller to return bursts for this ID in request order; it checks `RLAST` every four beats and raises the existing read error flags on a mismatch. Verify the output image and zero error flags after programming before using the measured frame rate.

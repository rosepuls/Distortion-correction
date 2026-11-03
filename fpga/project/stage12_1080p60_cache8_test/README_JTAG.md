# Stage 12 1080p60 cache 16x8: Fabric Debugger profiling

Program the matching `.sbit` and import `.fic` from `generate_bitstream/`.
Connect `CORE:0 MyFLA0` in Pango Fabric Debugger and select **Trigger
Immediate**. Keep a moving 1280x720@60 input on the board.

| Channels | Signal | Interpretation |
| --- | --- | --- |
| 0-31 | `input_published_count[31:0]` | Complete input frames published |
| 32-63 | `display_take_count[31:0]` | New completed frames taken by display |
| 64-95 | `copy_last_frame_cycles[31:0]` | DDR clock cycles for the latest completed frame transformation |
| 96-127 | `copy_last_frame_request_stall_cycles[31:0]` | Cycles the transform engine had a pixel request but the processing pipeline could not accept it |

The two last-frame values update after each processed frame and show whether
cache/DDR backpressure consumes a substantial part of processing time. Divide
`copy_last_frame_cycles` by 125 MHz for the latest frame's processing time.
Compare request-stall cycles with total frame cycles. A large stall fraction
points to cache fill/DDR latency; a small fraction points toward work outside
the request pipeline, such as output burst writes or arbitration.

For sustained frame rates, take two snapshots about 10-30 seconds apart and
subtract the hexadecimal input and display counters, accounting for 32-bit
wraparound. Divide each delta by elapsed seconds. The display counter measures
new frames shown; the HDMI raster itself remains 1080p60. Input frames not
accounted for by display frames were skipped before processing, provided the
output-drop LED/status remains clear.

These are diagnostic counters in the 125 MHz DDR clock domain. LED4/LED5
continue to flag read errors. The previous frame-rate-only diagnostic pair is
preserved under `generate_bitstream/baseline_frame_rate/` for rollback.

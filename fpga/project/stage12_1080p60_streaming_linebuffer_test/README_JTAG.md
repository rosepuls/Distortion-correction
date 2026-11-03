# Stage 12 streaming line-buffer Fabric Debugger counters

Program the `.sbit` and import the `.fic` from this project's
`generate_bitstream/` directory as a pair. Connect `CORE:0 MyFLA0` and use
**Trigger Immediate** with a moving 1280x720@60 input.

| Channels | Signal | Interpretation |
| --- | --- | --- |
| 0-31 | `input_published_count` | Complete captured input frames |
| 32-63 | `display_take_count` | New processed frames taken by the display |
| 64-95 | `copy_last_frame_cycles` | Cycles for the latest completed transform at 125 MHz |
| 96-127 | `copy_last_frame_request_stall_cycles` | Cycles a valid pixel request was blocked by the processing pipeline |

Take two snapshots 10-30 seconds apart to calculate input and displayed FPS.
The last-frame counters update once per processed frame. Divide total cycles
by 125 MHz for processing time; compare request-stall cycles to total cycles
to estimate the blocked fraction. This stall signal includes cache/DDR waits
and other upstream pipeline backpressure, so it does not alone prove the DDR
controller is the cause.

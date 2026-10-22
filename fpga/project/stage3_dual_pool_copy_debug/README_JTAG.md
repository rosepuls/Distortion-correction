# Stage 3 DDR3 copy: JTAG frame-counter diagnostic

This is a separate diagnostic copy of `stage3_dual_pool_copy_cdc_fix`. It adds two DDR-clock counters and a Fabric DebugCore. The stable project and its accepted bitstream are unchanged.

## Build artifacts

- Bitstream: `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`
- Matching Debugger configuration: `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic`
- PDS source configuration: `synthesize/HDMI_IN_DDR3_HDMI_OUT_top_syn.fic`

Use the `.sbit` and same-named `.fic` together. This diagnostic bitstream is different from the current stable bitstream.

## Capture a 30-minute run

1. In Pango Fabric Debugger, connect the board's JTAG cable and load `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`. The matching `.fic` is beside the bitstream; load it if Debugger does not import it automatically.
2. Start motion video and leave this diagnostic bitstream running for the desired interval.
3. Select **Trigger Setup → Trigger Immediate**. The core captures 512 consecutive `core_clk` (DDR clock) samples. Open the core's **Listing** view and export the values to TXT/CSV. Use the final sample row. The window spans only a few microseconds, so counters should normally be constant across it.

## Listing bus map

The single 256-bit bus groups these signals. Bit numbering is least-significant bit first within each signal.

| Channels | Signal | Meaning |
|---|---|---|
| 0–23 | `input_published_count[23:0]` | Fully written input frames published to the input pool |
| 24–47 | `display_take_count[23:0]` | Ready output frames acquired by the display path |
| 48–79 | `copied_count[31:0]` | Completed input-to-output frame copies |
| 80–111 | `copy_error_count[31:0]` | Frame-copy errors |
| 112–143 | `displayed_sequence[31:0]` | Sequence number of the selected output frame |
| 144–159 | `capture_dropped_count[15:0]` | Input-pool frame drops |
| 160–175 | `output_dropped_count[15:0]` | Output-pool frame drops |
| 176–191 | `incomplete_output_count[15:0]` | Output frames abandoned before completion |
| 192–207 | `display_read_error_count[15:0]` | Display read-adapter errors |
| 208–223 | `read_arbiter_error_count[15:0]` | DDR read-arbiter errors |
| 224–239 | `write_arbiter_error_count[15:0]` | DDR write-arbiter errors |
| 240–255 | `write_protocol_error_count[15:0]` | DDR write-protocol errors |

The first two bus fields expose the low 24 bits of 32-bit saturating counters. They wrap only after 16,777,216 frames, far beyond a 30-minute 720p60 run. Error/drop counters are 16-bit saturating counters. `input_published_count` increments only after the input frame's DDR writes drain and the frame is published. `display_take_count` increments when a ready output frame is selected at an output frame boundary.

Compare the counts after the run. Similar input-published, completed-copy, and display-take counts with zero error counters are a good sign. Differences identify where to investigate; pools may intentionally drop frames under backpressure, so compare deltas and the drop counters together.

## Build record

PDS 2022.2-SP6.4, target PG2L200H-6FBB676. Synthesis, DebugCore insertion, device mapping, placement/routing, timing report, and bitstream generation completed. Physical JTAG capture on the board has not yet been performed.

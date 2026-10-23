# Stage 6 Brown-Conrady mapping: JTAG frame-rate diagnostic

This project is a diagnostic clone of `stage6_radial_ddr`: fixed Brown-Conrady
mapping is enabled, and a 256-channel Fabric DebugCore exposes the same frame
and error counters as the Stage 5 diagnostic project.

## Files and capture procedure

- Program `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`.
- Import the matching `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic`.
- Connect to `CORE:0 MyFLA0`, choose **Trigger Setup → Trigger Immediate**, and
  read the final Listing row.
- Use a moving numbered 1280×720 at 60 Hz HDMI pattern. Record two captures
  about 60 seconds apart with their actual Console timestamps.
- Compute each rate as `(second count - first count) / elapsed seconds`.
  Compare input published, completed transform, and display take rates along
  with drop and error counter deltas. Browser FPS and monitor refresh are
  separate measures.

## Listing bus map

Bit numbering is least-significant bit first within each signal.

| Channels | Signal | Meaning |
|---|---|---|
| 0–23 | `input_published_count[23:0]` | Fully written input frames published to the input pool |
| 24–47 | `display_take_count[23:0]` | Ready output frames acquired by the display path |
| 48–79 | `copied_count[31:0]` | Completed Brown-Conrady transforms published to the output pool |
| 80–111 | `copy_error_count[31:0]` | Frame transform ownership errors |
| 112–143 | `displayed_sequence[31:0]` | Sequence number of the selected output frame |
| 144–159 | `capture_dropped_count[15:0]` | Input-pool frame drops |
| 160–175 | `output_dropped_count[15:0]` | Output-pool frame drops |
| 176–191 | `incomplete_output_count[15:0]` | Output frames abandoned before completion |
| 192–207 | `display_read_error_count[15:0]` | Display read-adapter errors |
| 208–223 | `read_arbiter_error_count[15:0]` | DDR read-arbiter errors |
| 224–239 | `write_arbiter_error_count[15:0]` | DDR write-arbiter errors |
| 240–255 | `write_protocol_error_count[15:0]` | DDR write-protocol errors |

The first two bus fields show the low 24 bits of saturating 32-bit counters.
`copied_count` and `copy_error_count` are full 32-bit saturating counters;
`displayed_sequence` is the full selected output sequence. Drop and error
counters are 16-bit saturating counters. For the first comparison, use about
60 seconds. For long-term stability, run motion video for 30 minutes and
compare the start/end deltas and errors.

The fixed trial coefficients are `k1=-0.25`, `k2=+0.0625`, `p1=+0.03125`,
`p2=-0.03125` with normalized coordinates divided by 512. They are not from
camera calibration. This diagnostic bitstream has not yet been measured on a
physical board; use the matching `.sbit`/`.fic` pair from the same build.

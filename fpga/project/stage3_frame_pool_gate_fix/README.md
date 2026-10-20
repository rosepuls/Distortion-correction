# Stage 3 pixel-gate polarity fix

This PDS project is an isolated copy of `stage3_frame_pool_diagnostic`. It preserves the diagnostic LED milestones and changes only `capture_pixel_gate` so DE alone qualifies active pixels. VS still marks frame boundaries and samples the capture permission at the first active pixel; the gate no longer assumes a particular VS level during DE.

| LED | Meaning |
| --- | --- |
| LED4 | Raw HDMI input DE has occurred |
| LED5 | A pixel passed `capture_pixel_gate` into `wr_buf` |
| LED6 | At least one complete frame was published by the capture pool |
| LED7 | The display consumer took a frame and `display_valid` became true |

The original diagnostic project and Stage 2 RGBX8888 baseline are not modified. Build the PDS project in this directory. The output bitstream is `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`.

## Accepted board baseline

- Board: Pango 200Pro+ (PG2L200H).
- User-reported validation: the moving-image test ran continuously for at least 30 minutes and passed, with no reported flicker, tearing, or line displacement.
- The bitstream is a local generated output and is not committed. Its SHA-256 is `D52ADE23197CC6E318147A1C08F7AF91FD15B248FCECC39C757E28548B5B271B`.
- Rebuild with PDS 2022.2-SP6.4 from `HDMI_IN_DDR3_HDMI_OUT.pds`; the stable Stage 2 RGBX8888 project remains available as a separate fallback.

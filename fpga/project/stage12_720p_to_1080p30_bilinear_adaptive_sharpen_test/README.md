# Stage 12 720p-to-1080p adaptive bilinear sharpening test

Independent feasibility project copied from Stage 5 identity DDR. It keeps
the 1280×720 capture path and the existing 2×2 tile-cache bilinear sampler,
then maps processed output samples to 1920×1080 and applies bounded adaptive
edge sharpening before DDR output. The current HDMI scanout target is 1080p60
for a monitor-compatibility test; repeated or dropped processed frames are
acceptable in this test.

The output-to-source transform uses center-aligned 3:2 scaling. Per RGB
channel, adaptive sharpening is enabled when the 2×2 neighborhood range is
at least 12; it adds one quarter of the bilinear-value deviation from the
neighbor mean, clamped to the neighborhood range. The low RGBX byte stays 0.
The vertical multiply and final sum/sharpen operations occupy separate
elastic pipeline stages to meet the 125 MHz DDR processing clock.

This project intentionally has no Brown distortion correction, angle
correction, adaptive lighting LUT, or UART control. Those are later integration
steps after this project's image quality, 1080p30 throughput, and timing have
been measured. Stage 5 and later projects remain unchanged.

## Verification status

- Vivado mapper and adaptive-sharpener directed simulations pass.
- The full 1920×1080 frame-engine simulation writes 2,073,600 pixels in 16,200
  bursts. Its idealized DDR model measured 3,802,249 cycles at 125 MHz
  (about 32 fps); it does not model real DDR controller latency or concurrent
  HDMI display-read traffic, so this is not a board-level 30 fps guarantee.
- PDS 2022.2-SP6.4 completed compile, synthesis, device mapping, placement,
  routing, timing, power report, netlist, and bitstream generation for the
  current 1080p60 scanout. The timing report says `All Constraints Met`;
  DDR processing-clock WNS is +0.575 ns, output pixel-clock WNS is +1.583 ns,
  and TNS is 0.
- The first 1080p30 bitstream was programmed on the board; a SANC M2753 monitor
  showed an unsupported-input message. The current bitstream outputs 1080p60
  with a 148.5 MHz pixel clock and CTA VIC 16; monitor lock has not yet been
  retested. Image continuity under real DDR contention and visual A/B image
  quality also remain unverified. See
  `../../../docs/results/stage12-super-resolution-feasibility.md`.

Run the checks from this directory:

```powershell
./sim/Run-ScaleMapper.ps1
./sim/Run-AdaptiveSharpener.ps1
./sim/Run-Stage12FullFrame.ps1
./Build-Stage12.ps1
```

The PDS reports and bitstream are generated under this Stage 12 directory.
Stage 5, Stage 8, Stage 10, and Stage 11 remain unchanged.

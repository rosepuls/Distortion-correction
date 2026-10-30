# Stage 12 1080p60 Stage 11 super-resolution integration test

This isolated project is based on `stage11_720p60hz_adaptive_image_enhancement_calibrated_baseline` and adds the Stage 12 3:2 output path. The Stage 11 65-byte UART protocol, frame-atomic homography/profile update, calibrated Brown K3 mapping, adaptive lighting LUT, and cache8 source reader are retained.

The output raster is 1920x1080 at 60 Hz. Each output coordinate is mapped to the 1280x720 pixel-center grid using the exact 3:2 transform, then passed through the Stage 11 homography and Brown mapping before 2x2 sampling. Adaptive edge sharpening runs on those four neighbors and the selected Stage 11 LUT runs afterward. Output DDR frame slots reserve 2^22 words each and accept 2,073,600 RGBX pixels.

The original integrated mapper had a scale/homography normalization bug: it multiplied all homogeneous terms by six, while the denominator range check and reciprocal lookup remained normalized to the original scale. Even identity homography therefore failed the valid denominator range. The repaired implementation keeps the exact center-aligned 3:2 fractional coordinate in Q16.16, feeds it into the Stage 11 homography and calibrated Brown K3 chain, and registers the coefficient/coordinate inputs before the wide multiply. The added stage preserves one-pixel-per-cycle throughput and adds one cycle of latency.

## Build result (2026-10-30)

PDS 2022.2-SP6.4 completed synthesis, placement, routing, Fabric Debugger insertion, and bitstream generation for the repaired RTL. The final report says `All Constraints Met`; slow-corner setup WNS is +0.052 ns on the 125 MHz DDR processing clock and +1.764 ns on the 148.5 MHz HDMI output clock. The Stage12 PLL configuration is included in this project.

- Bitstream SHA-256: `490DD940074C7141D63D47D9F9C20B34F679C860D38A7EC9BA2774B69381D8B4`
- Paired FIC SHA-256: `680DFAAFDB1FA79F243D339F80410A5A54E8A88BF9873F7EDE0392F460BBC24C`

The paired files are in `generate_bitstream/`. RTL regressions passed for the homography/Brown chain, 60 reference vectors, strict four-neighbor border, calibrated K3 reference, and 3:2 plus identity homography coordinates. This build has not yet been flashed and validated on the board; visible correction, HDMI output, and live frame rate still need hardware measurement.

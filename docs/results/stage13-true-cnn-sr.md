# Stage12 true CNN SR deployment progress

This is an interim engineering record. The isolated project now contains an
integrated CNN path and a generated `.sbit`; the current implementation still
fails full-chip timing and has not been validated on the board.

## 2026-10-31 pipeline timing iteration and bitstream

Several timing pipeline boundaries were added in one iteration across the CNN
and its source/control path:

- `sr_depthwise3x3.sv`: split the 3×3 accumulation and requantization work
  across additional registered stages.
- `sr_pointwise1x1_residual.sv`: capture inputs, weights and channel groups
  before the MAC and separate accumulation, requantization and residual join.
- `sr_phase_head_3x2.sv`: register selected features and phase weights to
  isolate tile-memory selection from the phase MAC.
- `sr_cnn_source_pipeline.sv` and `sr_frame_texture_gate.sv`: pipeline source
  luma/coordinate metadata and frame texture accumulation/control.

The pointwise pipeline initially used the wrong weight-ROM stride for channel
groups 1 and 2. This was corrected to address weights as
`output_channel * 8 + input_group_offset + input_channel`. The full small-frame
CNN residual map regression then passed for all 288 output pixels.

PDS 2022.2-SP6.4 completed synthesis, device mapping, placement, detailed
routing, timing analysis and programming-file generation for PG2L200H. The
generated integrated-CNN bitstream is:

`fpga/project/stage12_1080p60_true_cnn_sr_test/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`

- Size: 9,188,552 bytes.
- SHA-256:
  `9A0D233E2FD2945B69B538A3A2ADD1664183D8B4F292544A95CF884EE8D03214`.
- Matching `.fic` SHA-256:
  `CB0053A1B3E51A4973DB6C45F19C29B41717E492F85574245FFFF619374455FC`.
- Post-route setup WNS: `−5.097 ns` on `ddrphy_sysclk`; TNS is `−18778.217 ns`.
- The worst reported path starts at DDR `dfi_init_complete`, whose high-fanout
  net reaches CNN/window control and a stem APM input. Full-chip constraints
  therefore remain violated; this build is generated, but not timing-closed.
- The PDS build wrapper exits with a timing-constraint error after file
  generation. It checks for `All Constraints Met`, so that nonzero script exit
  is expected for this report and does not indicate a missing `.sbit`.

The WNS improved from `−17 ns` reported at the start of this iteration to
`−5.097 ns` post-route. The CNN map regression passed, but no 1080p/30 fps
throughput or board-display test has been performed.

## Independent-copy build check

The isolated project `stage12_1080p60_true_cnn_sr_test` completed a PDS
2022.2-SP6.4 build on PG2L200H. This validates the copied project and debug
insertion only: its top-level RTL still uses the existing phase-filter
interpolator. The generated `.sbit` is therefore a baseline smoke-build output,
not the requested CNN result.

- Timing: `All Constraints Met`; WNS is +0.605 ns on `ddrphy_sysclk` and
  +2.133 ns on the 148.5 MHz output-related clock; TNS is 0.
- Resources: 14 APM, 24 DRM, 9,481 LUT.
- Baseline smoke-build `.sbit` SHA-256:
  `DECE2E74FBC1804B002E5303C328AB009D35B1F7A05EDE39CC05ABEE660C7D09`.

## Quantized activation reference

The software reference now calibrates unsigned int8 post-ReLU activation
scales, signed int8 phase output, per-output-channel int8 weights, int32 biases,
and Q31 requantization multipliers/shifts. The checked checkpoint is
`model_temporal_last.pt`, SHA-256
`6b60b40506ea6c8c57360f9a81c8d8bf86a87d8706da91388cbb0e48d051de1d`.
Activation ranges were calibrated on 32 training frames with four 96×96 crops
per frame. Worst-case convolution accumulators in the manifest are below
1,040,000, so signed int32 is sufficient for the listed layer fan-ins.

The Python reference represents integer inputs, weights, biases and accumulators
as exact integer-valued tensors during convolution, then applies the same Q31
multiplier and rounded shift as the proposed RTL contract. The convolution
operation itself uses float32 because PyTorch has no portable integer Conv2d
kernel; the measured accumulator bounds are below 2²⁴, so all integer products
and sums are exactly representable in float32. It is an integer arithmetic
emulation, not RTL verification.

| Clip | Frames | Bicubic Y-PSNR | Float CNN | Int8 activation reference | Int8 temporal error | Bicubic temporal error |
|---|---:|---:|---:|---:|---:|---:|
| Held-out street | 155 | 25.8709 dB | 26.7921 dB | 26.7927 dB | 11.4861 | 12.9110 |
| Cloud validation | 127 | 48.3395 dB | 48.7036 dB | 48.6803 dB | 0.8670 | 0.7230 |

The activation quantization changed street quality by less than 0.001 dB and
cloud quality by −0.0233 dB from floating CNN. The known smooth-scene temporal
instability remains; the experimental frame-level scene gate is not yet in
RTL.

Using this checkpoint, the frame-level hysteresis sweep was repeated at enable
2.5 / disable 1.8. The street segment (mean texture 13.025) kept CNN enabled on
all 155 frames and measured 26.7921 dB / temporal error 11.4859. The cloud
segment (mean texture 0.819) stayed on bicubic for all 127 frames and measured
48.2302 dB / temporal error 0.7410. Each clip had zero mode transitions. This
confirms the software gate still separates these two clips; scene changes and
frame-metadata handoff remain to be implemented.

Deployment assets and deterministic vectors were exported to
`fpga/project/stage12_1080p60_true_cnn_sr_test/source/rtl/sr/weights/`.
`deploy_index.json` SHA-256 is
`196E9558866F78734B63BC94FD4D8145628ACC2B24EC30648DFB66C3BEB7785C`.
The calibration manifest SHA-256 is
`3F83450CC6BF8E76AA312D1446DBEEFD72BF69563CC986EA0FFF185BFFB43FDA`.

## Initial RTL blocks

The isolated source tree includes an RGBX-to-Y luma front end, streaming 3×3
feature windows, trained 8-channel stem, two depthwise/pointwise residual
blocks, a feature stack, and a nine-phase output head. ModelSim passed directed
checks for these stages and the end-to-end `sr_cnn_inference` against generated
Python golden tensors. The end-to-end test checked a 16×16 RGBX raster and all
16 emitted 3×2 phase tiles; this is arithmetic/ordering evidence, not a
full-frame throughput measurement.

The new `sr_source_dma.sv` reads one 16-beat burst into a 128-pixel RGBX stream
with raster coordinates and frame ID. ModelSim passed a directed 128-pixel
test with downstream stalls, and the PDS `compile` action completed with the
new module in the source list. The DMA is not instantiated in `fram_buf` yet,
so the PDS hierarchy still selects the phase-filter implementation.

`sr_cnn_source_pipeline.sv` now connects the DMA stream directly to the trained
inference core. Its ModelSim test emulated two 16-beat reads for a 16×16 frame
and confirmed all 16 phase tiles match the generated golden values. The frame
completion handshake waits for both the last source read and the last CNN tile.
`sr_tile_residual_reorder.sv` adds a 3-row, 9-bank tile-to-raster residual
reorder; its 16-tile test verified all 288 output positions, zeroed six-pixel
borders, coordinate order, and backpressure. Both modules remain outside the
`fram_buf` hierarchy.

Applying the CNN residual to the existing phase-filter base measured 25.7893
dB on the street clip versus 24.7012 dB for that base, but remained 0.0574 dB
below bicubic. On the cloud clip it measured 47.3327 dB versus 46.9962 dB for
the phase filter, while temporal error rose to 0.9125 (bicubic: 0.7410). The
output join therefore needs a bicubic-to-current-base correction and a
smooth-scene gate; adding only the CNN residual does not meet the quality goal.

## Remaining work

The integrated hierarchy synthesizes and produces a bitstream, but the present
`.sbit` should be treated as a timing-failing engineering build. The next timing
work should reduce the DDR initialization control fanout into the CNN path and
address the remaining CNN timing paths, then rerun post-route timing. The
1080p/30 fps target, multi-frame DDR ownership behavior, and board display have
not been measured. Image-quality and temporal metrics above are software
reference results and do not establish FPGA image quality.

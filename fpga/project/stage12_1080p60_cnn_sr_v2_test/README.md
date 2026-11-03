# Stage12 1080p60 pure CNN super-resolution experiment (v2)

This isolated project starts from `stage12_1080p60_streaming_linebuffer_test`,
which has a board-confirmed display recovery and an observed processing rate
above 30 new frames/s with its original non-CNN path. The source project is
left unchanged.

## Scope

- Input: 1280x720 RGBX8888 HDMI video stored in the existing DDR input pool.
- Output: 1920x1080 RGBX8888 at 60 Hz through the existing HDMI output pool.
- Processing target: 3:2 luma residual CNN on a bicubic luma base, with RGB base
  and output/frame ownership retained from the source project.
- No homography/Brown correction, UART control, lighting LUT, stabilization,
  or adaptive sharpener is part of the CNN experiment.

## Initial state

This directory is an isolated **project skeleton** copied from the streaming
line-buffer baseline. The RTL still contains the baseline scaler/sharpener and
is **not a CNN implementation**. No bitstream, timing report, or board result
from the source project is valid for this project. Every PDS build and its
matching `.sbit/.fic` must be generated here after CNN integration.

The isolated baseline PDS build completed with `All Constraints Met` before
CNN RTL changes. DDR 125 MHz setup WNS is +0.711 ns, TNS is 0. The baseline
smoke-build `.sbit` SHA-256 is
`7174052646CBA0CD6EF25224C52A396F6BD7E111CDD0EE3D71B04244DA813359`; paired
`.fic` SHA-256 is
`599FECAE43DD8F1575043DC19C42FE2FA0733F4C990C95B27340020E6076F440`. This
only validates the copied baseline project and debug mapping.

The first frozen CNN deployment inputs are staged in `source/rtl/sr/weights/`:
the int8 activation manifest, six layer ROM text files, residual join constants,
and 16x16 intermediate/output golden vectors. Source checkpoint SHA-256:
`6B60B40506EA6C8C57360F9A81C8D8BF86A87D8706DA91388CBB0E48D051DE1D`.
`deploy_index.json` SHA-256:
`8371E841FFE506DF17665B22D2788F7274B0C73269C1944288300231AE93A461`.
`bicubic_phase_q14.json` defines the 3:2 center-aligned phase taps using Keys
cubic `a=-0.75`, matching PyTorch bicubic, signed Q2.14 coefficients, edge
replication, one final ties-away-from-zero rounding after the 2D sum, and uint8
saturation after adding the integer residual. All three phase coefficient sums
are exactly 16384. `output_u8.hex` and `residual_y_s8.hex` are now generated from
this fixed-point path. On a deterministic 16x16 pattern, the fixed-point base
differs from PyTorch float bicubic by at most 0.5 luma level, with zero mismatch
after nearest-integer rounding and uint8 clipping.

## Timing-first implementation rule

Add the CNN in isolated pipeline stages and inspect synthesis/timing after each
stage. Register RAM outputs, MAC inputs/partial sums, requantization and residual
joins; use local registered enables and shallow ready/valid FIFOs. DDR
initialization status must terminate in frame-start control and must not fan out
into CNN datapath/window logic. Do not use a timing-failing bitstream for board
validation.

## RTL progress

The first isolated RTL block is `source/rtl/sr/sr_luma_frontend.sv`. It uses
four elastic register stages for RGB capture, constant products, partial sum,
and rounded luma output. Only stage-valid bits reset. Metadata is carried with
the pixel. `sim/Run-SRLumaFrontend.ps1` runs its directed ModelSim check for
arithmetic, metadata alignment, continuous input, and output backpressure.
This module is not connected to the frame engine yet, so the baseline PDS timing
result does not describe its routed timing. The four-level ready path must be
checked after integration and buffered if it becomes critical.

`source/rtl/sr/sr_luma_window3x3.sv` adds a three-bank synchronous line store
and 3x3 luma sliding window. Its input contract is a raster with a one-pixel
zero halo (`1282x722` for the 720p source); output windows cover the original
`1280x720` raster and match zero-padded CNN convolution semantics. It separates
synchronous RAM response from output backpressure with a response register and
an output register. `sim/Run-SRLumaWindow.ps1` checks all taps and metadata on a
small padded frame with backpressure. Estimated storage is about 30.8 kbit;
DRM inference and routed timing remain unverified until the source path is
integrated into the frame engine.

`source/rtl/sr/sr_source_dma.sv` adds a one-row-at-a-time DDR source path. It
fetches 16-beat bursts into eight interleaved 32-bit row banks, then emits a
1282x722 raster with generated zero halo rows and edge pixels. Row RAM reads
use an explicit synchronous read state before the output register; the row is
not overwritten until its pixels have been staged. `sim/Run-SRSourceDMA.ps1`
checks DDR row addresses, lane ordering, halo pixels, raster metadata, source
completion and output backpressure on a two-row test image. Its `source_done`
pulse means the padded source raster entered the luma frontend; it does not
mean downstream CNN/window work has drained. This module is
listed in the PDS project but is not instantiated in the top-level datapath;
resource mapping and routed timing remain unverified.

`source/rtl/sr/sr_input_pipeline.sv` now connects the source DMA, four-stage
luma frontend, and 3x3 line window. A four-entry FIFO between luma and window
uses registered occupancy for backpressure isolation. `sim/Run-SRInputPipeline.ps1`
checks every output window and all nine taps on a two-row grayscale frame with
irregular output stalls. This integration module is also only a standalone
block: the display/frame-pool top remains unchanged, so no routed timing or
device resource result applies to this chain yet.
The PDS compile action recognizes the DMA and pipeline modules with no compile
errors (`source-pipeline-pds-compile.log`); the constant-probe warnings in that
whole-project compile have not been attributed to these modules.

`source/rtl/sr/sr_stem_conv.sv` now implements the trained 1-to-8-channel 3x3
stem with 72 parallel int8 products and registered reduction/bias/requant
stages. The requant tail was split into absolute-value, shift/round-bit, and
clamp stages after the first integrated synthesis exposed a long carry chain.
The `Run-SRStemConv.ps1` golden-vector, metadata, and backpressure regression
passes. The standalone integrated timing harness synthesizes at 125 MHz with
estimated setup slack +3.411 ns (estimated period 4.589 ns); this is a
synthesis estimate, not placed-and-routed timing. Its worst reported path is
now the source-DMA DRM read to pixel register path. Mapping is 87/740 APM,
5.5/415 DRM, 2194/159800 LUT, and 3653 FF. The harness exposes 491 I/Os against
400 available, so this timing harness cannot be used for P&R; it also has only
the 8 ns clock constraint. Synthesis also reports signed/unsigned extension
packing warnings for several stem adders; these should be reviewed during
resource optimization. The existing board top remains unchanged and the stem
has not yet been integrated into it.

The standalone block `source/rtl/sr/sr_depthwise_conv.sv` implements
block1's 8-channel 3x3 depthwise convolution. It accepts a tap-major 3x3
neighborhood with eight byte lanes per tap and uses the trained block1
depthwise weights and requant constants. `sim/Run-SRDepthwiseConv.ps1` compares
all 16x16x8 activations against `block1_depthwise_u8.hex`, including metadata
and backpressure, and passes. Its PDS synthesis estimate at 125 MHz is
+3.649 ns slack (4.351 ns estimated period), with 85 APM, 1729 LUT, and 2880
FF. The reported worst path is the elastic-pipeline enable chain from
`valid_pipe[8]` to an APM clock-enable, with fanout 381; data arithmetic is not
the current estimated critical path. This is again synthesis-only: the
standalone harness has 800 I/Os and has not been placed or routed. The
depthwise arithmetic block is also included in the integrated stem/window
chain described below; the standalone harness itself remains a diagnostic
block rather than the integrated top.

`source/rtl/sr/sr_feature_window3x3.sv` and `sr_feature_line_ram.sv` add the
three-row, eight-channel feature window required between CNN layers. The
interface consumes an explicitly zero-padded feature raster, emits 3x3 taps
with the top-left tap in the high bits (matching the existing luma window
convention), and carries pixel/frame markers through output stalls. The
small-frame test checks all 9x8 values per output for halo behavior and
backpressure. PDS maps the three 64-bit row memories to 12 DRM total, 391 LUT,
and 1180 FF; estimated 125 MHz setup slack is +4.615 ns. The standalone top has
778 I/Os and has not been placed or routed.

`sr_feature_halo.sv` inserts the zero border around an unpadded feature stream,
and `sr_feature_window_pipeline.sv` joins halo insertion to the three-row line
window. The multi-frame regression checks all 12 windows and all 9x8 taps per
frame under output stalls. PDS synthesis estimates +4.229 ns slack at 125 MHz,
with 12 DRM, 583 LUT, and 1368 FF. Its reported worst path is the halo
coordinate/control path to a row-DRM enable; the top has 755 I/Os and has not
been placed or routed.

`sr_stem_depthwise_chain.sv` connects the trained stem, 4-entry feature FIFO,
halo/window, 1-entry wide-window ready buffer, block1 depthwise, pointwise and
residual join. A 2-entry registered-ready feature/skip FIFO now sits between
depthwise and pointwise, isolating the depthwise enable network from pointwise
backpressure while supporting simultaneous push/pop at one queued item. The
skip feature is taken from the window center and carried through both
convolution pipelines with its metadata. The 16x16 chain regression matches
every final activation against `block1_output_u8.hex`; independent pointwise/join
and full-chain ModelSim regressions pass under irregular output stalls.

Deployment weights and quantization constants are now generated as PDS-
synthesizable case ROMs by `host/super_resolution/generate_sr_rom_cases.py`.
Run it with `--check` to verify that the generated tables still match every
entry in the deployment hex files. The stem, depthwise, pointwise/join, and
full-chain ModelSim regressions all pass; the chain output still matches
`block1_output_u8.hex`. PDS no longer reports the weight and join ROM nets as
undriven.

The mapped diagnostic chain completed PDS synthesis and placement/routing with
an 8 ns internal clock. Post-route utilization is about 267 APM, 12 DRM, 8060
LUT and 12614 FF. Slow-corner setup WNS is +1.075 ns, TNS 0, and hold WHS
+0.141 ns; estimated Fmax is 144.40 MHz. PDS reports `All Constraints Met`.
The previous cross-layer ready path into depthwise is gone. The worst path now
starts at `feature_fifo/count[2]` and reaches a stem MAC pipeline enable (11
logic levels, 6.49 ns data path; 69% route contribution). The next timing focus
is the stem's internal ready propagation and its high-fanout enables.

The harness constrains only the internal 8 ns clock; input/output delays are
not specified, so these results cover register-to-register timing in this
diagnostic chain and do not establish complete board-interface timing. PDS
also emits constant-case-pruning and signed/unsigned adder-packing warnings,
which remain to be reviewed during timing/resource optimization.


# Stage 8 planar angle-mapping contract

> Status, 2026-10-24: Stage 8 contains the parameter bank and the homography
> → fractional Brown RTL chain. Targeted mapper, interpolator, display
> adapter and full-frame cache replay simulations pass. A Stage 8 `.sbit`
> has now completed PDS place/route with all constraints met: 125 MHz
> `ddrphy_sysclk` setup WNS +0.228 ns, hold WHS +0.103 ns, zero failing
> endpoints. The packet input remains tied low; dynamic angle operation and
> on-board behavior have not been validated.

## Geometry and word order

For each ideal zero-view output pixel `(u,v)`, the source ideal pixel is

```text
N_x = h00*u + h01*v + h02
N_y = h10*u + h11*v + h12
D   = h20*u + h21*v + h22
source_x = N_x / D
source_y = N_y / D
```

The PC derives `H` from a saved board plane and `track_pose.py`'s relative
pose. `H` maps ideal zero-view output pixels to ideal current-view source
pixels. This is a planar transform: it does not remove parallax in a scene
with varying depth. When lens correction is combined later, its Brown source
mapping must be applied **after** this transform in ideal pixel space.

`cfg_words[287:0]` packs word 0 at bits `[31:0]`, through word 8 at
`[287:256]`, in row-major order `h00,h01,h02,h10,h11,h12,h20,h21,h22`.
Rows 0–1 use signed Q16.16; row 2 uses signed Q2.30. Output source
coordinates use signed Q16.16, matching the existing bilinear planner.
`h22` is normalized to `1.0`, encoded as `0x40000000`.

## Supported numeric profile

For the first 1280×720 implementation, a validated packet must satisfy all
four image-corner checks before it enters the pending bank:

- `0.5 <= D < 2.0` in real units (`2^29 <= D_Q30 < 2^31`). Since `D` is
  affine in `(u,v)`, corner bounds cover the whole image.
- `abs(N_x_Q16)` and `abs(N_y_Q16)` are at most `2^30` at each corner.
  Affine numerator bounds at the corners cover the whole image and keep
  the final reciprocal product within signed 64-bit arithmetic.
- `h22 == 0x40000000`; all nine words arrive as one CRC-checked, validated
  packet in the 125 MHz clock domain. Coefficient values outside the profile
  are rejected before the bank's `cfg_valid` pulse.

Signed 44-bit accumulators cover the unvalidated sum of two 32-bit
coefficient products with 11-bit `u` and 10-bit `v` at this frame size.
The validated denominator and numerators then keep subsequent products
within signed 64 bits. Source coordinates are rounded to signed Q16.16;
the sampler uses its four-neighbor in-frame mask and paints invalid samples
black. A zero denominator, unsupported packet or out-of-range coordinate
must not reach the DDR read planner as a valid request.

## Reciprocal candidate and throughput

An iterative divider that takes many clocks per pixel would exceed the
remaining Stage 7 frame budget. The current Stage 7 result is about
1,849,511 processing cycles at 125 MHz; 60 fps allows about 2,083,333
cycles. That leaves 233,822 cycles, about 0.25 extra cycles per output pixel
before any increase in DDR cache misses. The Stage 8 mapper therefore needs
an initiation interval of **one pixel per clock** when downstream is ready.
Pipeline latency may be several clocks, with valid/ready stalls and pixel
metadata held together.

The selected candidate for implementation is:

1. Accumulate `N_x,N_y` as Q16.16 and `D` as Q2.30 in signed 44-bit registers.
2. Address a 1024-word unsigned Q2.30 reciprocal seed ROM with
   `(D_Q30 - 2^29) >> 21`. Each address covers `1/512` of the real
   denominator. The supported range `[0.5,2.0)` uses addresses 0–767.
3. Refine once with `r1 = r0 * (2 - D*r0)`, rounding each Q2.30 product to
   nearest. When `D_Q30 == 2^30`, select the exact reciprocal `2^30`, so the
   identity map keeps exact integer border coordinates.
4. Multiply `N_x,N_y` by `r1`, round the signed products to Q16.16, and
   apply the four-neighbor validity policy.

The model rounds ROM seeds to nearest with ties to even. The two positive
Q2.30 products add `2^29` before shifting right 30 bits; the signed final
products round half values away from zero. The eventual RTL must use the
same rules before a bit-for-bit comparison is meaningful.

The host integer model is selected by `--analyze-reciprocal` in
`host/pose/export_pose_homography.py`. On its ten synthetic `0°, ±10°,
±20°` X/Y cases, all ten pass this numeric profile; the largest coordinate
error shared by valid pixels is **0.0148 px**, and the valid-mask difference
is **20 pixels in total**. The two identity cases have zero error and zero
mask differences. These figures include coefficient and integer reciprocal
rounding. They do not predict Pango synthesis resources, routed timing, DDR
cache behavior, or real-lens accuracy. The ROM size is 1024×32 bits before
vendor memory packing.

## Frame-atomic parameter switching

`source/rtl/correction/homography_parameter_bank.sv` has active and pending
coefficient sets. Reset selects identity with `active_pose_valid=0` and
version 0. A `cfg_valid` pulse means the entire packet has already passed
UART framing, CRC and numeric-profile checks in this clock domain. A valid
pose packet stages its nine words and version; an explicit invalid-pose
packet stages identity with `pending_pose_valid=0`. The latest accepted
packet replaces an older pending packet.

`frame_start` must pulse on `start && start_ready` of the output-frame
engine. The pending set becomes active on that clock edge, before the first
coordinate request. If `cfg_valid` and `frame_start` coincide, the older
pending set is used for this frame and the new packet waits for the next
frame. The frame engine must latch the post-commit `active_version` and
`active_pose_valid` in `START_FRAME`, pass the version with every pixel, and
check the returned version against that latched value. An explicit invalid
pose then yields identity mapping on the next frame, rather than continuing
to apply the last measured angle. A missing UART stream still needs a
separate timeout policy.

## Stage 8 integration points

The Stage 8 PDS tree is cloned from the committed Stage 7 project. The first
three integration points below are implemented in Stage 8 RTL and have
passed targeted simulation:

1. `homography_mapper.sv` calculates the ideal Q16.16 source coordinate.
   `fractional_brown_mapper.sv` applies the existing trial coefficients to
   this fractional coordinate; Stage 7's integer mapper remains untouched.
   To bound its intermediate squares, the trial Brown stage rejects ideal
   coordinates more than 2048 pixels from either image-center axis and
   sends those samples to the black-pixel path.
2. The planner applies strict four-neighbor black-border behavior for mode 2.
3. The frame engine latches the active parameter version after frame commit,
   sends it with each pixel, and accepts invalid mapped pixels as black.
4. Complete the UART parser, CRC, range validator and any clock crossing
   before connecting `cfg_valid`. Then simulate the full DDR-backed frame
   path and measure board throughput and crop. Stage 7 remains the
   comparison baseline.

The parameter-bank simulation passed reset, replacement, frame commit,
coincident load/commit, version and explicit invalid-pose cases before this
integration. Vivado Simulator 2020.2 then passed a composed homography/trial
Brown test with stalls and a separate 60-point bit-exact comparison of both
coordinates to the host integer model, sampling six points from each of ten
synthetic X/Y poses. The interpolator also matches its reference for 100
transactions under output stalls; the display-adapter credit test passes;
and a five-frame 1280×720 cache replay matches all 41,145 model miss/victim
events. PDS 2022.2-SP6.4 synthesis reports a worst listed slack of -0.006 ns
on planner metadata writes to cache RAM, with the Brown mapper path at
+0.042 ns. This remains a synthesis estimate: no routed timing or board
result exists. The current top-level packet inputs are tied low, so dynamic
homography cost and timing are not represented until a validated UART
source is connected. Meanwhile, the static Stage 8 bitstream can be used to
bring up the video path on hardware; it runs identity homography and trial
Brown coefficients.

## Timing optimization progress (2026-10-24)

The initial fresh synthesis reported -2.055 ns on cache victim selection.
Stage 8 now snapshots valid/LRU/PLRU metadata after an older hit can retire
and uses that snapshot for victim selection. The fractional bilinear
interpolator adds an elastic stage between vertical products and summation,
and the display adapter compares committed occupancy directly to its burst
reservation threshold. Targeted simulations passed after each change.

The successive worst slacks were -2.055 ns (cache), -0.363 ns (interpolator),
-0.133 ns (display credit), then -0.006 ns (planner metadata to cache RAM).
The final PDS SNR estimates 23,365 LUTs and 12,035 FFs total. The full PDS
flow completed place/route and generated
`fpga/project/stage8_angle_correction/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`.
The post-route report says all constraints are met; on `ddrphy_sysclk` the
setup WNS is +0.228 ns and hold WHS is +0.103 ns, both with zero failing
endpoints. Its SHA-256 is
`BD29230F6845FF5D7A3BB6E9D4E7CB2058AA4DDAFC047CE476DD01C8FE945BBB`.
Dynamic angle configuration is tied off, so these resources and timing do
not establish the cost or timing of live homography updates.

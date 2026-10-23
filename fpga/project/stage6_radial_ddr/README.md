# Stage 6 wide-angle visual trial

This PG2L200H project takes real 1280×720 HDMI frames through DDR tile cache,
Brown-Conrady output-to-source mapping, bilinear sampling and HDMI output.
The fixed trial coefficients are `k1=-0.25`, `k2=+0.0625`, `p1=+0.03125`,
`p2=-0.03125`, with normalized coordinates `x=(u-640)/512`,
`y=(v-360)/512`. They are deliberately strong for the 120° wide-angle
camera test. They are not measured camera calibration values.

The mapper source is `source/rtl/correction/demo_radial_mapper.sv`, copied
from `fpga/rtl/correction/stage6_brown_mapper.sv`. The inherited module name
and `RADIAL_DENOM_SHIFT` parameter are retained for project compatibility;
the four coefficients above define this build. The optical center pixel
stays fixed mathematically while neighboring pixels are remapped.

Program `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` to inspect the
image. Use `stage6_radial_fps_debug` for frame-rate counters. Build hash and
timing are recorded in `docs/results/stage6-radial-ddr.md`.

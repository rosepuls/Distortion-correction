# Stage 6 Brown-Conrady FPS diagnostic

This project has the same mapper as `stage6_radial_ddr`: `k1=-0.25`,
`k2=+0.0625`, `p1=+0.03125`, `p2=-0.03125`, with normalized coordinates
`x=(u-640)/512`, `y=(v-360)/512`. Its Fabric DebugCore exposes input,
processed and displayed frame counters for this exact image transform.

Program its own `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` and
import the matching `.fic` from the same directory in Fabric Debugger.
See `README_JTAG.md` for the channel map and capture procedure. Build hash
and timing are recorded in `docs/results/stage6-radial-fps-diagnostic.md`.

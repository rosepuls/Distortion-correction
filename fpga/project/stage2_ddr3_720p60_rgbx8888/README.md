# Stage 2 DDR3 720p60 RGBX8888 video stream

This directory contains the complete reproducible PDS project for the RGBX8888
three frame-slot video path:

- `HDMI_IN_DDR3_HDMI_OUT.pds` — Pango project file
- `HDMI_IN_DDR3_HDMI_OUT_top.fdc` — pin and timing constraints
- `impl.tcl` — synthesis, place-and-route, timing report, and bitstream flow
- `source/` — top-level RTL, HDMI control, DDR3 frame buffers, and slot manager
- `ipcore/` — generated vendor IP source required by the project

Build from this directory with the Pango Fabric Compiler installation:

```text
source impl.tcl
```

The implementation output directories (`compile/`, `synthesize/`,
`generate_bitstream/`, `generate_netlist/`, and reports/logs) are intentionally
ignored by Git. They are reproducible from the tracked project, constraints,
RTL, IP sources, and build script.

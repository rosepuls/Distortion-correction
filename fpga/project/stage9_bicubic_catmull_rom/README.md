# Stage 9 Catmull–Rom bicubic interpolation

This project is based on the committed Stage 8 angle-correction project.
Stage 8 remains unchanged as the bilinear baseline. Stage 9 keeps its
homography and fractional Brown coordinate chain, then gathers a strict 4×4
source neighborhood from the existing 16×8 tile cache and applies separable
Catmull–Rom interpolation (`a=-0.5`) to RGB. The pixel format remains
RGBX8888, with the X byte set to zero.

The 4×4 reader performs four ordered 2×2 cache lookups per output sample. A
sample is geometrically valid only when all 16 source neighbors are in frame;
otherwise the output is black. The interpolator uses Q2.14 signed weights,
elastic ready/valid stages and the existing pixel/frame/version metadata.

## UART byte input

The Pangu 200 Pro+ board's CP2102 USB-UART input is connected to FPGA pin P14.
After rebuilding this project, open the board's USB-UART COM port with 115200
baud, 8 data bits, no parity and 1 stop bit (8-N-1). The Stage 9 top level
synchronizes and decodes each byte; a valid byte produces an internal
one-cycle `uart_rx_valid` pulse with `uart_rx_data[7:0]`. A low stop bit pulses
`uart_rx_frame_error` and discards the byte. The receiver is held in reset
until DDR initialization completes.

The byte stream is not yet parsed as commands and does not change interpolation
or homography settings. There is no UART TX acknowledgement. The source and
pin constraint are ready in this project. Board pin details are in the
[Pangu 2L200H manual](https://www.meyesemi.com/upload/202506161410082.pdf).

## Compile-time interpolation selection

The default build uses the existing Catmull–Rom bicubic 4×4 path. The project
also contains a bilinear 2×2 planner, tile-cache reader, and pipelined RGBX
interpolator. To select bilinear for a new build, uncomment
`` `define STAGE9_USE_BILINEAR `` in
[`source/rtl/correction/stage9_interpolation_config.vh`](source/rtl/correction/stage9_interpolation_config.vh),
then run the full PDS build. Leave that line commented for bicubic. The
preprocessor includes only the selected path before synthesis, so the default
build does not need to retain a second sampler in hardware. Bilinear outputs
black when its full 2×2 neighborhood is out of bounds; bicubic requires its
full 4×4 neighborhood. Both preserve the existing frame metadata and counters.

This setting is fixed in the generated bitstream. The UART byte receiver does
not currently choose the interpolation mode. Changing the setting requires a
new `.sbit` and its matching same-build `.fic`.

## Simulations

Run from the repository root:

```powershell
.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9BicubicPlanner.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'
.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9BicubicReader.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'
.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9CatmullRomInterpolator.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'
.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9BicubicFrame.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'
.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9BicubicFrame.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2' -Bilinear
.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9BilinearInterpolator.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'
.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9BicubicFrame.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2' -FullHd
pytest host\reference\test_bicubic_interpolator_reference.py -q
```

The frame integration test defaults to a deterministic 64×8 image. Pass
`-FullHd` to validate a complete 1280×720 identity-map frame, cache reads,
interpolation, output ordering and strict borders.

## Build and board measurement

Build this project's own `.sbit` and matching `.fic` with:

```powershell
.\fpga\project\stage9_bicubic_catmull_rom\Build-Stage9Bicubic.ps1
```

The script verifies Fabric Debugger channel coverage, required frame-rate and
cycle counters, bitstream generation, and `All Constraints Met`; it copies the
FIC produced by the same PDS build to
`generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic`. Program only this project's
`.sbit` and import this project's matching `.fic`. Never use the Stage 8 FIC
to read Stage 9 counters. See [README_JTAG.md](README_JTAG.md) for channel
definitions and [the Stage 9 results record](../../../docs/results/stage9-bicubic-catmull-rom.md)
for verified build data and later board measurements.

The previous UART-enabled full build produced a bitstream but its DDR PHY
setup timing failed by 0.179 ns. That bitstream predates the interpolation
selection in this source tree. Rebuild and inspect the new timing report
before using a newly selected mode on hardware.

Top-level angle packet inputs remain tied low, as in the Stage 8 starting
project. Dynamic angle packets are not part of this interpolation experiment.

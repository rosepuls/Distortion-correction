# Stage 4 Algorithm Demo

This independent PG2L200H project keeps the accepted Stage 3 board clocks,
HDMI transmitter setup, DDR3 IP and pin constraints.  `fram_buf.v` is replaced
with the Stage 4 procedural algorithm path:

`radial Q16.16 mapper -> coordinate FIFO -> bilinear planner -> procedural
RGBX8888 grid reader -> bilinear interpolator -> HDMI output`.

The DDR3 device is initialized so the original board top and pins remain valid,
but the demo issues no AXI read or write requests.  It is an algorithm and video
timing test before the Tile Cache is connected to captured camera frames.

After a complete displayed frame, LED4/LED5/LED6 are expected on.  LED7 is the
pipeline error indicator and is expected off.  The displayed pattern is a
colored gradient with white 64-pixel grid lines, radially displaced outward;
the four corners fade to the constant-black border.
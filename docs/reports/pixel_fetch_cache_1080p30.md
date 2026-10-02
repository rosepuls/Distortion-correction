# Pixel Fetch Cache Summary

This report is a deterministic full-raster physical-traffic model, not a board measurement.
It uses RGBX8888 source pixels, 256-bit DDR beats, set-associative Tile Cache accounting,
and does not claim DDR controller or PHY efficiency.

- output coordinates evaluated: `2073600`
- image size: `1920×1080`
- frame rate: `30 fps`
- raster: `full`
- valid source coordinates use the four-neighbor policy `0 <= x0 < width-1` and `0 <= y0 < height-1`.
- four frame-equivalent RGBX streams: `33177600` bytes/frame, `995328000` bytes/s.

## Cache candidates

`tile_32x4_128_8way_skewed` is the 1080P30 RTL candidate. Its physical source traffic is measured
directly from the complete raster rather than extrapolated from stride sampling.

| camera | policy | output requests | source pixel requests | cache hit rate | DDR read bytes | DDR bursts | DDR beats | average burst length (pixels) | average burst (beats) | cache capacity (pixels) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| identity | no_cache | 2073600 | 8294400 | 0.000000 | 24883200 | 8294400 | 8294400 | 1.000000 | 1.000000 | 1 |
| identity | row_window | 2073600 | 8294400 | 0.594010 | 80818560 | 6734880 | 6734880 | 4.000000 | 1.000000 | 8 |
| identity | tile_16x4 | 2073600 | 8294400 | 0.832740 | 266365440 | 5549280 | 5549280 | 16.000000 | 1.000000 | 64 |
| identity | tile_32x4_128_8way_skewed | 2073600 | 8294400 | 0.998047 | 8294400 | 64800 | 259200 | 32.000000 | 4.000000 | 16384 |
| barrel | no_cache | 2073600 | 8294400 | 0.000000 | 24883200 | 8294400 | 8294400 | 1.000000 | 1.000000 | 1 |
| barrel | row_window | 2073600 | 8294400 | 0.589503 | 81715800 | 6809650 | 6809650 | 4.000000 | 1.000000 | 8 |
| barrel | tile_16x4 | 2073600 | 8294400 | 0.830491 | 269946624 | 5623888 | 5623888 | 16.000000 | 1.000000 | 64 |
| barrel | tile_32x4_128_8way_skewed | 2073600 | 8294400 | 0.998011 | 8447488 | 65996 | 263984 | 32.000000 | 4.000000 | 16384 |
| pincushion | no_cache | 1839773 | 7359092 | 0.000000 | 22077276 | 7359092 | 7359092 | 1.000000 | 1.000000 | 1 |
| pincushion | row_window | 1839773 | 7359092 | 0.591752 | 72104088 | 6008674 | 6008674 | 4.000000 | 1.000000 | 8 |
| pincushion | tile_16x4 | 1839773 | 7359092 | 0.831727 | 237760704 | 4953348 | 4953348 | 16.000000 | 1.000000 | 64 |
| pincushion | tile_32x4_128_8way_skewed | 1839773 | 7359092 | 0.997737 | 8528384 | 66628 | 266512 | 32.000000 | 4.000000 | 16384 |

## Interpretation

`no_cache` is a lower-complexity traffic baseline with no reuse. The candidate cache
loads one aligned 32×4 RGBX region on a miss and retains eight ways per set.
DDR controller scheduling, read/write arbitration, and board measurements remain separate.


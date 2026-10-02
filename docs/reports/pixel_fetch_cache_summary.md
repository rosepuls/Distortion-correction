# Pixel Fetch Cache Summary

This report is a deterministic logical-pixel model estimate, not a board measurement.
It uses RGB888 (3 bytes per logical source pixel), a 1280×720 frame, raster stride 8,
and every border coordinate. DDR byte packing, controller scheduling, and PHY overhead
are intentionally outside this pre-study.

- sampled output coordinates: `18147`
- image size: `1280×720`
- raster stride: `8`
- valid source coordinates use the four-neighbor policy `0 <= x0 < width-1` and `0 <= y0 < height-1`.

## First RTL cache candidate

The first candidate for RTL prototyping is `row_window`: an aligned 4×2 pixel region,
burst length 4, and 8 logical RGB888 pixels of modeled capacity. Based on the sampled
identity trace, the proportional full-frame estimate is `53846143` bytes/frame
or `3230768580` bytes/s at 60 fps. This is an extrapolated model estimate,
not a board measurement; the sparse trace and one-region policy must be re-evaluated with
a full raster trace before freezing DDR bandwidth claims.

| camera | policy | output requests | source pixel requests | cache hit rate | DDR read bytes | DDR bursts | average burst length | cache capacity (pixels) |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| identity | no_cache | 18147 | 72588 | 0.000000 | 217764 | 72588 | 1.000000 | 1 |
| identity | row_window | 18147 | 72588 | 0.390064 | 1062576 | 88548 | 4.000000 | 8 |
| identity | tile_16x4 | 18147 | 72588 | 0.537389 | 6447360 | 134320 | 16.000000 | 64 |
| barrel | no_cache | 18147 | 72588 | 0.000000 | 217764 | 72588 | 1.000000 | 1 |
| barrel | row_window | 18147 | 72588 | 0.471221 | 921192 | 76766 | 4.000000 | 8 |
| barrel | tile_16x4 | 18147 | 72588 | 0.652932 | 4837056 | 100772 | 16.000000 | 64 |
| pincushion | no_cache | 12734 | 50936 | 0.000000 | 152808 | 50936 | 1.000000 | 1 |
| pincushion | row_window | 12734 | 50936 | 0.453824 | 667680 | 55640 | 4.000000 | 8 |
| pincushion | tile_16x4 | 12734 | 50936 | 0.625000 | 3667392 | 76404 | 16.000000 | 64 |

## Interpretation

`no_cache` is a lower-complexity traffic baseline with no reuse. `row_window` and
`tile_16x4` load one aligned in-bounds region on a miss and retain only that region.
The estimates are intended to choose a first cache architecture before DDR3 and
board measurements are available.


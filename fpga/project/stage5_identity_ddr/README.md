# Stage 5 DDR identity integration

Independent PG2L200H board project cloned from the Stage 3 CDC-fixed
camera -> DDR -> HDMI baseline. The frame ownership manager and capture/display
paths are unchanged. The middle frame-copy engine is replaced by a coordinate
pipeline, DDR tile-row reader, pixel tile cache, bilinear interpolator, and
DDR output writer. Identity coordinates should reproduce the source image.

LED4 reports display-adapter or transform fatal error, LED5 reports read-arbiter
error, LED6 reports an active display gate, and LED7 records any nonzero RGB
output. A transform fatal error requires reset and never publishes a partial
output frame. Keep the Stage 3 project as the board fallback.

The full PDS flow passed with all timing constraints met. DDR 125 MHz setup
slack is +0.538 ns. The generated bitstream is a board-test candidate, not
yet board-validated. Its SHA-256 is
06A0B9B33B0A5C4FEE63DE2F9A595D1B743D85ED370EBA699BBEB69C73E5F714.
See docs/results/stage5-identity-ddr.md for the test procedure and limits.

# Stage 12 streaming line-buffer resizer design

## Goal

Create an isolated project copied from `stage12_1080p60_cache8_test` that keeps its 1080p60 HDMI raster, fixed 3:2 bilinear scaling, adaptive edge sharpening, frame ownership, and DDR write/display path, while replacing the large associative tile cache with sequential source-row DMA and on-chip line buffers. Include a paired Fabric Debugger `.fic` for frame rate and per-frame stall measurements.

## Rationale

The 16x8 candidate measures about 19.8 new display frames/s. Its 6.30M DDR-clock processing time includes about 3.52M cycles (55.9%) where the transform engine has a pixel request but the pipeline cannot accept it. The fixed 1280x720 to 1920x1080 3:2 mapping advances monotonically in raster order, so random tile lookup is unnecessary. The current ideal simulation performs 28,800 four-beat tile-row reads per frame. Sequential line DMA can transfer each 1280-pixel source row as ten 16-beat bursts, for 7,200 bursts/frame, while returning the same 3.69 MB of source pixels.

## Architecture

- Keep frame-slot ownership and output burst writer in the transform engine.
- Replace the associative tile-cache reader with a sequential line-buffer reader for monotonically increasing bilinear coordinates.
- Use three source-row slots, each divided into eight 32-bit pixel banks. Each 256-bit DDR response beat writes one word to each bank. The slots hold 1280 pixels per row and use about 15 KiB total pixel storage.
- Load rows in ascending order with 16-beat reads (160 beats / ten bursts per source row). Track each slot's source-row tag, valid state, and outstanding pixel references so a row is not overwritten until all requests using it have returned and future coordinates have advanced past it.
- Keep the existing coordinate mapper, bilinear planner, and adaptive sharpener. Serve `x0/x1` from even/odd banks and `y0/y1` from their tagged row slots; preserve border replication, metadata ordering, and ready/valid behavior.
- Permit DDR to fill a third row while the current two rows serve output pixels. The read arbiter remains the shared path with live display reads.
- Retain 1080p60 output timing and Stage 12 frame-drop behavior.
- Add `.fic` channels for cumulative input/display frame counts, source-row burst count, latest completed frame cycles, and latest-frame pixel-request blocked cycles. Copy the generated FIC beside the matching `.sbit` after a timing-passing PDS build.

## Acceptance criteria

- New project directory starts with `stage12_1080p60_` and leaves the source project unchanged.
- Source rows are fetched exactly once per input frame, with correct addresses, ten 16-beat bursts per row, and no out-of-range requests.
- 3:2 pixel coordinates, border behavior, RGBX format, frame/line metadata, bilinear values, and adaptive edge compensation match the existing Stage 12 path.
- Backpressure cannot overwrite a line still referenced by queued pixels; output ownership is published only after all output writes drain.
- PDS completes bitstream generation with `All Constraints Met`; the `.fic` channel count, names, and hashes are recorded.
- Board comparison reports input FPS, new displayed FPS, source-row reads, frame cycles, and request-stall share.

## Risks

Multi-bank line-buffer inference and four source-pixel reads per output pixel can affect routing and BRAM inference. Three row slots and explicit outstanding-reference accounting are required to avoid overwriting rows while metadata is queued. A passing PDS build proves implementation/timing, not image correctness or improved board FPS; those still require board measurements.

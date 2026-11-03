# Stage 12 1080p60 streaming line-buffer experiment

This is an isolated copy of `stage12_1080p60_cache8_test`. It keeps 720p60
capture, 1080p60 HDMI output, the fixed 3:2 coordinate mapper, bilinear
interpolation, adaptive edge sharpening, frame ownership, and output writes.
The random 16x8 tile cache has been replaced by sequential source-row DMA and
three banked line buffers.

Each 1280-pixel RGBX source row is read as ten 16-beat bursts. The line store
uses eight banks so each 256-bit return beat writes eight adjacent pixels.
Three tagged rows provide the two bilinear source rows and a row being filled
ahead. Reference counts prevent replacing a row while accepted pixel lookups
still depend on it. The expected source storage is about 15 KiB.

The paired `.sbit` and `.fic` are in `generate_bitstream/`. The FIC exposes
input frames, display-taken frames, last-frame processing cycles, and blocked
pixel-request cycles. See [README_JTAG.md](README_JTAG.md). Build using
`Build-Stage12.ps1`; the script requires PDS 2022.2-SP6.4 and checks the timing
summary before copying the matching FIC next to the generated bitstream.

The current PDS build includes a fix to explicitly sign-extend line-slot
reference-count decrements. It completed with `All Constraints Met`. The
125 MHz DDR clock has +0.711 ns setup slack, and the 148.5 MHz HDMI output
clock has +1.207 ns; TNS is zero. Resource use is 24 DRM blocks, 9,906 LUTs,
and 9,967 FFs. Bitstream SHA-256:
`ED0C273E1DA8DF71958A64A8741278C77DFDA0C8DEC960F496EFB362420CBC33`.
FIC SHA-256: `A9A129747ED49C53C5EC4FABC43241C6D73E664649CE76698F392953B2E5DEDD`.

The first board report was black video with HDMI sync and the display-taken
and output-valid LEDs off. A signedness bug in `streaming_linebuffer_reader.sv`
could prevent completed lookups from decrementing 16-bit row reference counts.
After all three line slots filled, the DMA could wait indefinitely for a free
slot. The update now explicitly sign-extends the signed delta to 16 bits. The
user confirmed the regenerated bitstream restores the image. Two Fabric
Debugger snapshots about 44 seconds apart measured approximately 44.7 processed
frames/s (1,968 display-taken frames); the latest per-frame cycle count implies
about 44.45 frames/s. This exceeds the 30 fps target in the observed sample.

The board sample confirms throughput above 30 fps. A longer stability run and
visual comparison against the cache8 project are still needed before making a
claim about long-run stability or relative image quality.

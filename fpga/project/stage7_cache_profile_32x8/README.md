# Stage 7 cache throughput profile

Independent copy of the Stage 6 Brown-Conrady performance diagnostic project.
The only datapath change is a 32-set, 8-way tile cache (128 KiB of pixels)
instead of the 16-set, 4-way cache (32 KiB). The fixed mapping coefficients,
frame pipeline, and 256 Fabric DebugCore channels are unchanged.

Build with `../Run-Stage7CacheProfile.ps1`. Program this project's `.sbit` and
import the `.fic` from the same build. See `README_JTAG.md` for the channel map.
Compare approximately 60 seconds of the same moving 1280x720@60 input with the
recorded Stage 6 baseline.
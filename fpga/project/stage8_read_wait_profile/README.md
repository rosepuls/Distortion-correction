# Stage 8 DDR read wait profile

Independent 16-set, 8-way copy of the Stage 7 candidate with diagnostic-only RTL changes. It splits read-address waits into arbiter contention and DDR ARREADY backpressure, and read-data waits into first-beat latency and inter-beat gaps. The datapath, mapping coefficients, and DDR requests are unchanged.

Build this project's PDS file and program the resulting `.sbit` with its matching `.fic`. Use the same moving 1280x720@60 HDMI input and capture two Listing snapshots about 60 seconds apart. Channel 104-127 and 176-247 are reassigned for the four read-wait counters; see README_JTAG.md.
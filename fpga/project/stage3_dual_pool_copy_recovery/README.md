# Stage 3 dual frame-pool copy project

This project is generated from the board-accepted `stage3_frame_pool_gate_fix`
project. It is an independent checkout for the input-pool to output-pool frame
copy path. The generator refuses to overwrite an existing destination and
omits PDS build outputs, bitstreams, and local logs.

Regenerate with `New-Stage3DualPoolCopyProject.ps1` from `fpga/project/`.
The video top publishes captured frames to the input pool and directs display
reads to the separate output pool. The read and write burst arbiters connect
the raw frame-copy engine to DDR. Verify simulation, physical timing, and
board operation before treating its bitstream as accepted.

This recovery build removes the cumulative display-adapter error count from
`display_pipe_ok`. The adapter still blocks the current faulty frame and
clears that block at the next drained output VS; the cumulative counter remains
available for diagnosis. The read-arbiter error gate remains in place.

The first recovery bitstream (`3EF6458D...`) displayed an image, but the
image and LED6 flashed together. Photographs showed a frame with only its top
portion visible. The revised reader requests successive lines whenever the
display adapter is ready, using the adapter's 512-beat buffer for prefetch.
Its address advances only after the full line returns. A targeted two-frame
DDR stall simulation passed with this reader and failed with the DE-triggered
reader. Real board behavior remains to be checked.

Current bitstream SHA-256:
`88CA1504B104AAA9A3557FED42D1E4BDBB6904CC1CB1C20C0D11B27BF021A6E9`.
The PDS bitstream flow completed with all constrained paths met; the DDR clock
domain's slow-corner setup margin is +0.820 ns. This build FAILED board
verification: the LED state remained the same and partial-frame blacking
worsened. The subsequent `stage3_dual_pool_copy_cdc_fix` project registers the
source Gray pointer after a binary-carry skew reproduction demonstrated false
buffer-fault detection. This recovery directory remains the failing reference.

- LED4: display-adapter error count is nonzero (sticky).
- LED5: read-arbiter error count is nonzero (sticky).
- LED6: display output gate is currently open (live).
- LED7: at least one nonzero RGB pixel was observed during output DE (sticky).

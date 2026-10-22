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

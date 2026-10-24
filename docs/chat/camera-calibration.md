# Camera Calibration and Dynamic Pose Measurement Plan

> Status: planning. Camera calibration images have not yet been collected. The printed target is available at `picture/标定板_9x6内角点_25mm_A4横向.pdf`.

## Goal

Calibrate the UVC industrial camera at its final 1280×720 mode, establish a repeatable zero pose, and have the PC estimate camera pose from the UVC image and send only pose parameters to the FPGA. The PC will not geometrically correct the demonstration video; the FPGA remains responsible for coordinate mapping, DDR tile reads, and interpolation.

## Current Setup and Fixed Conventions

- Camera: Jierui Weitong DCXGW10, advertised as 720p60 with a 2.1 mm wide-angle lens and 150–210° field of view. Treat the advertised field of view as a product claim; use calibration results to select the camera model.
- Calibration target: 9×6 inner chessboard corners, 25 mm square edges, A4 landscape. The board contains 10×7 squares and measures 250×175 mm.
- Print at A4, landscape, 100% / actual size. Disable fit-to-page and measure the printed square edge. Use the measured edge if it differs from 25 mm.
- Capture original UVC frames at 1280×720. Keep lens, focus, resolution, and camera mode fixed throughout calibration and pose testing. Do not use screenshots of the Windows desktop or FPGA-corrected output.
- Existing scripts: `host/calibration/calibrate.py`, `host/calibration/export_fixed_parameters.py`, and `host/reference/render_reference.py`.

## Phase 1: Capture Calibration Images

1. In OBS, add the UVC camera as a **Video Capture Device** and set 1280×720 at 60 fps.
2. Save each frame using **Screenshot (Source)** for the camera source. Do not use Screenshot (Preview), which can include canvas transforms or overlays.
3. Collect 25–30 sharp, non-duplicate views; at least 20 must be accepted by the calibration script. Move the board through the image center, corners, and edges, and vary its tilt and distance. Keep it flat, well lit, and fully visible where practical.
4. Save the PNGs in `host/calibration/images/`. Record the camera model, lens, focus state, UVC mode, and measured square size.
5. Also save one clear image in the intended initial camera pose. This image will define pose zero later; it can also be part of the intrinsic-calibration set.

**Deliverable:** original 1280×720 images, capture notes, and a designated zero-pose image.

## Phase 2: Estimate Intrinsics and Lens Distortion

From the `Distortion-correction` directory, run the existing calibration command:

```powershell
.\.venv\Scripts\python.exe host\calibration\calibrate.py `
  --images host\calibration\images `
  --cols 9 --rows 6 --square-mm 25 `
  --out host\calibration\output `
  --camera-id "Jierui Weitong DCXGW10" `
  --lens-notes "2.1 mm; record actual focus and UVC settings"
```

The script checks resolution and chessboard detection, requires at least 20 accepted views by default, and writes `calibration.json` with the camera matrix, Brown–Conrady coefficients, per-view reprojection errors, and the estimated effect of setting `k3` to zero.

Review rejected images and residuals before exporting FPGA parameters. The lens is advertised as an extreme wide-angle / fisheye lens, so do not assume the standard pinhole Brown model is adequate. If residuals show a systematic edge error, compare an OpenCV fisheye calibration and its reference maps before choosing the model. The current FPGA Brown mapper supports `k1/k2/p1/p2`; use the existing export guard for `k3`, and extend the FPGA model if the measured `k3` effect exceeds the project threshold.

**Deliverable:** a reproducible calibration JSON and a written model-fit decision. Do not hand-tune coefficients to make the image look straighter.

## Phase 3: Define and Measure the Reference Pose

1. Fix the calibration board in the scene and rigidly mount the camera on the adjustable bracket.
2. Set the camera to the desired neutral view, capture a clear board image, and mark that pose as zero. Store the board corner layout and the calibration profile used for this reference.
3. For each later UVC frame, detect the board corners and estimate board-to-camera pose using the saved camera calibration. Compute pose change relative to the saved zero pose; do not recalibrate intrinsics per frame.
4. First test discrete movements at 0°, ±10°, and ±20°. Record the requested physical angle from the bracket scale and the PC-estimated pose. A printed protractor on the bracket can provide a ground-truth check for the pitch axis.
5. Chessboard corner ordering can become ambiguous after large rotations or detection loss. If pose jumps by roughly 180°, add an asymmetric orientation marker at a measured, fixed location or use a ChArUco/ArUco board for runtime pose tracking.

For this planar target, estimate pose or a board-plane homography. A single global homography can rectify the board plane; it cannot remove parallax across a general 3D scene when the camera translates.

**Deliverable:** zero-pose record, repeatable pose estimates, and comparison against the bracket angle at each test position.

## Phase 4: Send Pose to FPGA

1. Keep UVC capture and display pass-through on the PC. Run board detection and pose estimation on the PC, then send a compact angle or inverse mapping matrix over UART.
2. Define a packet with protocol version, sequence number, transform parameters, validity flag, and CRC. Reject incomplete or out-of-range packets.
3. FPGA stores active and pending parameter banks. Validate the complete packet first, then switch the full parameter set atomically at a frame boundary so a frame cannot mix two poses.
4. Apply the inverse pose transform before the existing lens-distortion source mapping, then retain the current DDR tile-cache fetch and bilinear interpolation path. The PC must not remap the displayed video.
5. Initially move the camera slowly through discrete angles and log the source frame time, pose packet sequence, FPGA parameter version, output frame rate, dropped frames, crop, and invalid-pixel area. Add timestamp/frame association if pose lag is visible.

## Acceptance Criteria

- At least 20 valid calibration views at exactly 1280×720; saved JSON identifies the camera, board dimensions, model, and per-view residuals.
- The zero pose can be restored and produces the same transform after recapturing the reference view.
- The PC estimates changing pose from the fixed target and sends parameters without applying geometric correction to the demonstration video.
- FPGA changes parameters only at a frame boundary and produces the expected correction at 0°, ±10°, and ±20°.
- Report actual new-frame rate, visible crop / invalid region, coordinate or line-straightness error, and behavior when the board is temporarily undetected. Do not claim 60 fps for angle changes until measured on the board.

## Recommended Execution Order

1. Print and measure the chessboard.
2. Capture and review the calibration image set.
3. Run calibration and decide whether Brown–Conrady is adequate for this lens.
4. Capture and store the zero pose; verify PC pose estimates against the bracket scale.
5. Define the UART packet and frame-boundary update in the FPGA.
6. Test FPGA correction at increasing angles and measure throughput and image quality.

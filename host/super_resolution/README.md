# Motion video 3:2 super-resolution prototype

This folder contains the software path for a compact luma residual network:

- `prepare_pairs.py` creates aligned 720p/1080p frame pairs from a higher-resolution clip.
- `make_synthetic_pairs.py` creates moving chart clips with known 1080p targets for pipeline bring-up only.
- `model.py` implements a 3:2 phase residual CNN over a bicubic base: an 8-channel stem, two depthwise-separable blocks, and nine phase outputs per 2x2 input block.
- `train.py` trains the model using paired luma frames and a pixel-plus-gradient objective.
- `export_int8.py` exports symmetric signed-int8 tensors and per-tensor scales for a later RTL ROM generator.
- `evaluate_video.py` compares bilinear, bicubic, and Lanczos baselines and reports per-frame luma PSNR/SSIM and temporal difference error.

Dependencies: Python 3.10–3.13, NumPy, OpenCV, PyTorch. Use clips with 1080p or better reference detail. The prepare script simulates a 720p camera input by applying blur/noise/JPEG degradation and downsampling; this is a starting model and must be calibrated against the actual camera.

Example:

```powershell
python host/super_resolution/prepare_pairs.py input_1080p.mp4 work/pairs
python host/super_resolution/make_synthetic_pairs.py work/synthetic --frames 24
python host/super_resolution/train.py work/pairs/lr720 work/pairs/hr1080 work/model.pt
python host/super_resolution/export_int8.py work/model.pt work/model_int8.json
python host/super_resolution/evaluate_video.py work/pairs/lr720 work/pairs/hr1080 work/baseline.csv
```

Add other training clips with repeated `--extra-pair LR_DIR HR_DIR`; use separate source videos for validation and test. The current experimental multi-scene snapshot is `weights/bicubic_residual_multiscene_int8_experimental.json`.

Motion-video training and held-out evaluations are recorded in
`../../docs/results/stage12-cnn-sr-training.md`. The current deployment
reference is `fixed_point_reference.py`; it calibrates int8 activation scales,
uses int8 weights/int32 biases and Q31 requantization, and emits a manifest.
`export_rtl_weights.py` writes per-layer ROM text files and deterministic
golden vectors for the isolated FPGA candidate. Current full-clip comparisons
are recorded in `../../docs/results/stage13-true-cnn-sr.md`.

These are software deployment assets only. The FPGA candidate does not yet
contain RTL that consumes the weights, and its baseline `.sbit` is still the
phase-filter design. Do not treat that bitstream as the CNN implementation.

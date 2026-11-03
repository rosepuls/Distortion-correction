# Stage12 3:2 motion-video CNN super-resolution training

Date: 2026-10-30. This report records the first GPU-trained candidate; it is a software result, not an FPGA result.

## Source video and paired data

- Source: `host/super_resolution/video/video_20261030_131922.mp4`.
- Capture metadata: 3840×2160, 60.074 fps, 1,528 frames, about 25.44 s.
- The 4K source frames were resized to 1920×1080 for targets. A 720p input was synthesized from the same frame by applying Gaussian blur (`sigma=0.45` at 1080p), downsampling with OpenCV `INTER_AREA`, adding Gaussian noise (`sigma=0.7`), and no additional JPEG loss (`quality=100`).
- Temporal split: 0–15 s training (301 frames sampled every third source frame), 15–21 s validation (120 frames sampled every third frame), 21–25.4 s held-out test (264 frames, every source frame). Each split is a contiguous scene segment; this is clip-separated but all segments come from one recording and one environment.
- Pair data and checkpoints are in ignored `host/super_resolution/.work/real/` and can be regenerated with `prepare_pairs.py`.

## Model and training

`ResidualSR32` processes luma, uses an 8-channel 3×3 stem, two depthwise-separable residual blocks, and a 9-phase head that predicts one residual for each 3×3 output tile generated from a 2×2 input block. After the first run showed the bilinear-residual model below bicubic, the base was changed to bicubic 3:2 interpolation. The head is zero-initialized, and residuals are clamped to ±24 luma levels.

Training used PyTorch 2.15.0+cu132 on an NVIDIA GeForce RTX 5070 Laptop GPU, 25 epochs, batch size 16, 96×96 LR crops, Adam with learning rate 0.0002, L1 loss plus 0.08 gradient loss. The best validation checkpoint was epoch 25. Weight-only symmetric int8 quantization uses per-output-channel scales; biases remain floating point in the current reference and are not yet an FPGA-ready numeric format.

## Held-out test results

Mean luma metrics over the 264-frame test segment:

| Method | Y-PSNR (dB) | Global Y-SSIM | Temporal error | Software time/frame |
|---|---:|---:|---:|---:|
| Bilinear | 42.0376 | 0.9984 | 1.5756 | 1.35 ms |
| Bicubic | 43.8048 | 0.9990 | 1.3376 | 1.08 ms |
| Lanczos4 | 43.7959 | 0.9991 | 1.3491 | 3.03 ms |
| CNN, floating weights | 44.3290 | 0.9990 | 0.6634 | 19.87 ms |
| CNN, weight-only int8 simulation | 44.3261 | 0.9990 | 0.6630 | 19.87 ms |

The int8 weight conversion changed held-out Y-PSNR by about −0.0029 dB. This comparison quantizes weights and dequantizes them back to float for software inference; activations, accumulators, and bias arithmetic are not yet integer/bit-exact.

## Independent outdoor clip check

A second video was then added: `host/super_resolution/video/video_20261030_142255.mp4`, 3840×2160, 60.072 fps, 663 frames, about 11.04 s. It contains indoor plants, a window view, outdoor foliage/courtyard, and a moving camera. All 221 frames sampled at every third frame were held out from training; paired LR/HR frames were generated using the same degradation parameters. The model used here is the weight-only int8 simulation, with floating activations and biases.

| Method | Y-PSNR (dB) | Global Y-SSIM | Temporal error |
|---|---:|---:|---:|
| Bilinear | 37.0004 | 0.9974 | 2.7838 |
| Adaptive sharpener reference | 37.0194 | 0.9974 | 2.7610 |
| Bicubic | 39.6513 | 0.9986 | 2.1010 |
| Lanczos4 | 39.7660 | 0.9987 | 2.0903 |
| CNN, weight-only int8 simulation | 40.1114 | 0.9987 | 1.0202 |

The CNN exceeds bicubic by about 0.46 dB on this separate outdoor clip, with lower temporal error. This supports using videos shot in this way for more independent evaluation. The new clip is still only one short handheld-style recording; test more indoor textures, fast subject motion, low light, and at least one additional independent scene before claiming general-purpose improvement.

## Multi-scene refit with the additional clips

Five more clips were added to the folder. Four were used for training: the dim Rubik's cube clip (`143451`, 220 generated pairs), the greenery/grass clip (`143705`, 162 pairs), the checkerboard clip (`145053`, 126 pairs), and the street/pedestrian/vehicle clip (`143905`, 155 pairs). The first video contributes its 0–15 s training segment, sampled at 10 fps after dataset subsampling. A cloudy sky clip (`143749`, 127 pairs) was reserved for validation. The courtyard/garden video (`142255`) remains an untouched external test set (221 pairs). The 16.11 s street clip was added to the final training run after an earlier exploratory test showed it was close to Lanczos but above bicubic. Training therefore covers five source clips; validation and test each remain separate clips.

The final run used the same 25-epoch GPU setup and selected epoch 5 by cloud validation loss (0.61076). Weight-only int8 simulation on the held-out garden clip measured:

| Method | Y-PSNR (dB) | Global Y-SSIM | Temporal error |
|---|---:|---:|---:|
| Bicubic | 39.6513 | 0.9986 | 2.1010 |
| Lanczos4 | 39.7660 | 0.9987 | 2.0903 |
| Multi-scene CNN | 39.9241 | 0.9987 | 1.0406 |

The final model remains about 0.27 dB above bicubic and reduces the measured temporal error by about half on the garden clip. This is useful cross-scene evidence but is still only one held-out test scene. The current integer simulation still quantizes weights only; FPGA activations, biases, and accumulators have not been implemented or measured.

## Interpretation and next gate

On this held-out segment, the bicubic-residual CNN improves Y-PSNR by about 0.52 dB over bicubic and reduces the measured temporal error. This is evidence to continue the candidate, not proof of generalization: train/validation/test are from one short recording, and the 720p observations are synthesized from the 4K source rather than captured by the project's UVC camera.

The model uses approximately 383 million MACs per 720p frame for its convolutions, or about 11.5 GMAC/s at 30 new frames/s, before bicubic interpolation and control overhead. This arithmetic count does not predict PDS timing or DDR behavior. The next engineering gate is integer activation/accumulator design and streaming RTL mapping, followed by PDS resource/timing and board measurement. The existing 44.7 new frames/s measurement belongs to the baseline line-buffer project and is not transferable to this CNN candidate.

## Independent street holdout audit, 2026-10-30

A new model was trained from scratch on the desk, Rubik's cube, greenery, and chart clips, with the street clip excluded. Cloud validation selected epoch 5. The first street CSV accidentally included the CNN method twice when `--methods` already named `cnn`, which invalidated its temporal-error aggregate. The evaluator now deduplicates method names; the corrected full 155-frame street comparison is:

| Method | Mean Y-PSNR (dB) | Temporal error |
| --- | ---: | ---: |
| Bilinear | 24.5768 | 15.0833 |
| Adaptive sharpener | 24.8140 | 14.6062 |
| Bicubic | 25.8709 | 12.9110 |
| Lanczos4 | 26.1663 | 12.4348 |
| 8-channel CNN, float | 25.9154 | 12.8516 |

The CNN improves only 0.0445 dB over bicubic and is 0.2509 dB below Lanczos4. It misses the plan's 1.5 dB improvement over the adaptive sharpener (actual 1.1014 dB). The training loader used one 96×96 random crop per selected video frame per epoch, while the cloud-only validation is dominated by smooth texture. These are concrete training/selection weaknesses, but causality must be checked by a new run. A corrected run now samples four crops per frame, caches decoded frames, and uses the independent garden clip for textured validation; the street clip remains the untouched test.

## Corrected texture-validation run

The four training clips remained desk, Rubik's cube, greenery, and chart. Each selected frame contributed four random 96×96 crops per epoch. Garden frames, sampled every sixth prepared pair, selected the checkpoint; the street and cloud clips were unseen during training and checkpoint selection. Garden validation loss decreased each epoch from 1.75769 to 1.62902, selecting epoch 15.

| Unseen clip | Bicubic Y-PSNR | Lanczos4 Y-PSNR | CNN Y-PSNR | Bicubic temporal error | CNN temporal error |
| --- | ---: | ---: | ---: | ---: | ---: |
| Street, 155 frames | 25.8709 | 26.1663 | **26.7111** | 12.9110 | **11.6086** |
| Clouds, 127 frames | 48.3395 | 48.1867 | **48.7500** | **0.7230** | 0.8419 |

Street CNN gains 0.8402 dB over bicubic and 1.8971 dB over the current adaptive sharpener from the same corrected evaluator. The cloud clip also gains 0.4105 dB over bicubic but its temporal error is worse by 0.1189. Before FPGA weight freeze, examine flat-region residual noise and try a local-contrast gate or training penalty for temporal inconsistency. The selected checkpoint is `host/super_resolution/.work/real/model_texture_val.pt`; `weights/texture_val_weight_int8.json` is still weight-only quantization with floating activations and biases.

Weight-only int8 simulation on all 155 street frames measured 26.7104 dB, a 0.0007 dB loss from floating weights. A 60-frame local-contrast residual gate experiment gave the following direct-Y results: at gate threshold 8, street Y-PSNR was essentially unchanged (26.51979 versus 26.51981 dB for no gate), while cloud temporal error fell from 0.9128 to 0.8246; cloud Y-PSNR also fell from 46.9802 to 46.7658 dB. A simple gate therefore trades temporal stability for detail and is not yet frozen as the deployment algorithm. The next trial should use a temporal consistency term or a smoother residual confidence function and re-evaluate on full clips.

Temporal-loss fine-tuning (`lambda=0.1`, eight epochs, same aligned crop in consecutive prepared frames) improved independent street CNN quality to 26.7921 dB and temporal error to 11.4859, versus bicubic 25.8709 dB and 12.9110. The unseen cloud clip remained at 48.7036 dB versus bicubic 48.3395 dB, but temporal error was 0.8605 versus 0.7230. Further fine-tuning with cloud frames in training (`lambda=0.15`) improved the independent street clip to 26.8522 dB and temporal error 11.3943. On the now-seen cloud clip, PSNR was 48.6625 dB and temporal error 0.8713. Thus adding cloud training did not solve temporal consistency there. The street spatial target is met (1.897–2.038 dB above the adaptive sharpener), while cloud temporal stability remains an explicit unresolved gate; neither run is yet an integer FPGA deployment model.

An additional six-epoch trial supervised both frames equally and raised the temporal-difference weight to 0.5. The cloud clip reached 48.7187 dB with temporal error 0.8530, still above bicubic's 0.7230. This excludes simply increasing the paired-frame loss as a sufficient fix. The mean first-neighbor absolute Y difference over 20 input frames was approximately 1.04 for clouds, 3.55 for garden, and 13.26 for street. A scene-level texture confidence or smooth-scene residual bypass is therefore a plausible, low-cost next experiment; it must use hysteresis and be evaluated across scene transitions before an RTL decision. The current FPGA candidate still contains the older 2×2 phase filter, not this CNN.

A 60-frame local-contrast gate sweep from thresholds 8 to 128 did not close the cloud temporal gap: error stayed around 0.812–0.824 versus 0.913 ungated and 0.723 bicubic. Stronger thresholds progressively removed street detail, dropping street PSNR from 26.520 to 26.167 dB. Reject this local gate as the fix. Next evaluate a scene-level static-texture confidence with hysteresis, or retain CNN only in scenes where the confidence is high; test transitions explicitly before encoding such control in RTL.

## Frame-level texture confidence prototype

`evaluate_scene_gate.py` uses the mean of horizontal and vertical absolute luma differences on each incoming 720p frame. CNN enables at score ≥2.5 and disables at score ≤1.8; the state is held between thresholds. With the texture-validation checkpoint, the 155-frame street clip averaged score 13.025, kept CNN enabled for every frame, and measured 26.711 dB Y-PSNR with temporal error 11.609. The 127-frame cloud clip averaged 0.819, kept CNN disabled throughout, and produced bicubic output with 48.230 dB and temporal error 0.741 in this RGB/YCrCb output path. The 221-frame garden clip averaged 4.156, enabled CNN for 96.4% of frames, made one mode transition, and measured 41.096 dB with temporal error 1.890.

This separates the observed low-texture failure from detailed motion content while keeping the classifier hysteretic. It is a software result only. Hardware integration requires calculating the frame statistic during capture and carrying the decision with the frame slot across clock domains; the true CNN stream and integer implementation are still pending.

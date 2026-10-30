"""Capture stable lighting-profile frames from OBS or a video source."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import sys
import time

import cv2

from lighting_profile import PROFILE_NAMES, analyze_bgr, classify_lighting


def source_value(value: str) -> int | str:
    return int(value) if value.isdecimal() else value


def existing_sample_count(directory: Path) -> int:
    return sum(1 for path in directory.glob("sample_*.png") if path.is_file())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source", type=source_value, default=2,
        help="OBS Virtual Camera index (default 2) or video file",
    )
    parser.add_argument(
        "--output", type=Path,
        default=Path(__file__).resolve().parent / "output" / "lighting_samples",
        help="output directory (default: host/pose/output/lighting_samples)",
    )
    parser.add_argument("--limit-per-profile", type=int, default=15,
                        help="maximum PNGs to save for each profile (default 15)")
    parser.add_argument("--stable-frames", type=int, default=3,
                        help="same classification required for N frames (default 3)")
    parser.add_argument("--interval-seconds", type=float, default=1.0,
                        help="minimum time between captures of one profile (default 1)")
    parser.add_argument("--sample-stride", type=int, default=8,
                        help="sample every Nth row and column for classification (default 8)")
    parser.add_argument("--width", type=int, default=1280,
                        help="required source width (default 1280)")
    parser.add_argument("--height", type=int, default=720,
                        help="required source height (default 720)")
    parser.add_argument("--no-preview", action="store_true",
                        help="do not open the preview window; Ctrl+C stops capture")
    args = parser.parse_args(argv)

    if args.limit_per_profile < 1:
        parser.error("--limit-per-profile must be positive")
    if args.stable_frames < 1:
        parser.error("--stable-frames must be positive")
    if args.interval_seconds < 0:
        parser.error("--interval-seconds must be nonnegative")
    if args.sample_stride < 1:
        parser.error("--sample-stride must be positive")
    if args.width < 1 or args.height < 1:
        parser.error("--width and --height must be positive")

    output_root = args.output.expanduser().resolve()
    directories = {
        profile: output_root / f"{profile}_{name}"
        for profile, name in PROFILE_NAMES.items()
    }
    for directory in directories.values():
        directory.mkdir(parents=True, exist_ok=True)
    counts = {profile: existing_sample_count(directory)
              for profile, directory in directories.items()}

    if all(count >= args.limit_per_profile for count in counts.values()):
        print(f"All profiles already have {args.limit_per_profile} samples: {output_root}")
        return 0

    capture = cv2.VideoCapture(args.source)
    if not capture.isOpened():
        raise SystemExit(f"could not open OBS/video source: {args.source}")
    if isinstance(args.source, int):
        capture.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
        capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    manifest_path = output_root / "manifest.jsonl"
    last_candidate: int | None = None
    candidate_streak = 0
    last_saved_at = {profile: float("-inf") for profile in PROFILE_NAMES}
    reported_full: set[int] = set()
    frame_index = 0
    saved_this_run = 0
    window_name = "Lighting sample capture — press q to stop"

    print(f"source={args.source}; output={output_root}")
    print(f"stable_frames={args.stable_frames}; interval={args.interval_seconds:g}s; "
          f"limit={args.limit_per_profile} per profile")
    print("Change the scene lighting; captures are automatic. The preview shows counts.")
    for profile, name in PROFILE_NAMES.items():
        print(f"  {profile}:{name} {counts[profile]}/{args.limit_per_profile}")

    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                print("source ended or stopped returning frames")
                break
            frame_index += 1
            height, width = frame.shape[:2]
            if (width, height) != (args.width, args.height):
                raise SystemExit(
                    f"expected {args.width}x{args.height} source, received {width}x{height}"
                )

            metrics = analyze_bgr(frame, sample_stride=args.sample_stride)
            candidate = classify_lighting(metrics)
            if candidate == last_candidate:
                candidate_streak += 1
            else:
                last_candidate = candidate
                candidate_streak = 1

            now = time.monotonic()
            stable = candidate_streak >= args.stable_frames
            if stable and counts[candidate] < args.limit_per_profile:
                due = now - last_saved_at[candidate] >= args.interval_seconds
                if due:
                    directory = directories[candidate]
                    sample_index = counts[candidate] + 1
                    image_path = directory / (
                        f"sample_{sample_index:02d}_"
                        f"{datetime.now().astimezone().strftime('%Y%m%d_%H%M%S_%f')}.png"
                    )
                    if not cv2.imwrite(str(image_path), frame):
                        raise OSError(f"failed to write image: {image_path}")
                    record = {
                        "frame_index": frame_index,
                        "captured_at": datetime.now().astimezone().isoformat(timespec="milliseconds"),
                        "profile": candidate,
                        "profile_name": PROFILE_NAMES[candidate],
                        "image": image_path.relative_to(output_root).as_posix(),
                        "width": width,
                        "height": height,
                        "metrics": {
                            "mean": metrics.mean,
                            "p10": metrics.p10,
                            "median": metrics.median,
                            "p90": metrics.p90,
                            "dark_ratio": metrics.dark_ratio,
                            "highlight_ratio": metrics.highlight_ratio,
                            "local_dark_ratio": metrics.local_dark_ratio,
                            "local_highlight_ratio": metrics.local_highlight_ratio,
                        },
                    }
                    with manifest_path.open("a", encoding="utf-8") as manifest:
                        manifest.write(json.dumps(record, ensure_ascii=False) + "\n")
                    counts[candidate] += 1
                    saved_this_run += 1
                    last_saved_at[candidate] = now
                    print(
                        f"saved {candidate}:{PROFILE_NAMES[candidate]} "
                        f"{counts[candidate]}/{args.limit_per_profile} -> {image_path}"
                    )
                    if counts[candidate] >= args.limit_per_profile:
                        print(f"profile {candidate}:{PROFILE_NAMES[candidate]} is full; skipping it")
                    if all(count >= args.limit_per_profile for count in counts.values()):
                        print("All profile quotas are full.")
                        break
            elif stable and counts[candidate] >= args.limit_per_profile:
                if candidate not in reported_full:
                    print(f"profile {candidate}:{PROFILE_NAMES[candidate]} is full; skipping it")
                    reported_full.add(candidate)

            if not args.no_preview:
                preview = frame.copy()
                current_state = "stable" if stable else f"settling {candidate_streak}/{args.stable_frames}"
                cv2.putText(
                    preview,
                    f"{candidate}:{PROFILE_NAMES[candidate]} ({current_state})",
                    (16, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2,
                    cv2.LINE_AA,
                )
                count_text = "  ".join(
                    f"{profile}:{counts[profile]}/{args.limit_per_profile}"
                    for profile in PROFILE_NAMES
                )
                cv2.putText(
                    preview, count_text, (16, 62), cv2.FONT_HERSHEY_SIMPLEX,
                    0.52, (0, 255, 255), 1, cv2.LINE_AA,
                )
                cv2.imshow(window_name, preview)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break
    except KeyboardInterrupt:
        print("capture interrupted")
    finally:
        capture.release()
        if not args.no_preview:
            cv2.destroyAllWindows()

    print(f"stopped after {frame_index} frames; saved {saved_this_run} new images")
    print(f"samples: {output_root}")
    for profile, name in PROFILE_NAMES.items():
        print(f"  {profile}:{name} {counts[profile]}/{args.limit_per_profile}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Preview adaptive enhancement choices from OBS or a video file, without UART."""

from __future__ import annotations

import argparse
import sys

import cv2

from lighting_profile import PROFILE_NAMES, LightingSelector, analyze_bgr, classify_lighting


def source_value(value: str) -> int | str:
    return int(value) if value.isdecimal() else value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=source_value, default=2,
                        help="OBS Virtual Camera index (default 2) or video file")
    parser.add_argument("--sample-stride", type=int, default=8,
                        help="sample every Nth row and column (default 8)")
    parser.add_argument("--report-every", type=int, default=15,
                        help="print every N frames and on profile changes (default 15)")
    args = parser.parse_args(argv)
    if args.sample_stride < 1 or args.report_every < 1:
        parser.error("--sample-stride and --report-every must be positive")

    capture = cv2.VideoCapture(args.source)
    if not capture.isOpened():
        raise SystemExit(f"could not open OBS/video source: {args.source}")
    if isinstance(args.source, int):
        capture.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    selector = LightingSelector(stable_frames=3)
    index = 0
    print(f"source={args.source}; observation only; UART remains closed")
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            index += 1
            metrics = analyze_bgr(frame, sample_stride=args.sample_stride)
            candidate = classify_lighting(metrics)
            previous = selector.active
            active = selector.update(candidate)
            if index == 1 or index % args.report_every == 0 or active != previous:
                print(
                    f"frame={index} candidate={candidate}:{PROFILE_NAMES[candidate]} "
                    f"active={active}:{PROFILE_NAMES[active]} "
                    f"mean={metrics.mean:.1f} p10={metrics.p10:.0f} "
                    f"median={metrics.median:.0f} p90={metrics.p90:.0f} "
                    f"dark={metrics.dark_ratio:.1%} highlight={metrics.highlight_ratio:.1%} "
                    f"local_dark={metrics.local_dark_ratio:.1%} "
                    f"local_highlight={metrics.local_highlight_ratio:.1%} "
                    f"samples={metrics.samples}"
                )
    except KeyboardInterrupt:
        pass
    finally:
        capture.release()
    print(f"stopped after {index} frames; active={selector.active}:{PROFILE_NAMES[selector.active]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""
Smoke test for the detector against a synthetic, clean, top-down image with
circles in each of the 5 known chip colors at known counts. This does not (and
can't) validate performance on real photos — lighting, felt texture, and
occlusion all behave differently — but it catches regressions in the detection
pipeline itself (e.g. a parameter change that silently breaks recall).

Run with: python -m tests.test_chip_detection
(from the ChipVisionService directory, or inside the container — see README)
"""

import numpy as np
import cv2

from app.chip_detection import detect_chips

_COLORS_BGR = {
    "White": (235, 235, 235),
    "Red": (40, 40, 210),
    "Blue": (200, 60, 30),
    "Green": (60, 160, 40),
    "Black": (25, 25, 25),
}


def _build_synthetic_image(expected_counts: dict, canvas: int = 700) -> np.ndarray:
    img = np.full((canvas, canvas, 3), (90, 60, 20), dtype=np.uint8)  # felt-green background
    radius = 22
    step = radius * 2 + 14
    margin = radius + 4
    x, y = margin, margin
    for color_name, count in expected_counts.items():
        bgr = _COLORS_BGR[color_name]
        for _ in range(count):
            # Wrap BEFORE drawing — wrapping after (as an earlier version of this
            # test did) can leave the last circle in a row centered past the
            # canvas edge, silently drawing it off-frame and making the detector
            # look like it missed a chip it was never actually shown.
            if x + radius > canvas - margin:
                x = margin
                y += step
            cv2.circle(img, (x, y), radius, bgr, -1)
            x += step
        x += step + 30
        if x + radius > canvas - margin:
            x = margin
            y += step
    assert y + radius < canvas, "test layout overflowed the canvas — widen `canvas`"
    return img


def test_detects_all_chips_with_correct_colors():
    expected_counts = {"White": 3, "Red": 5, "Blue": 2, "Green": 4, "Black": 3}
    img = _build_synthetic_image(expected_counts)

    counts, confidence = detect_chips(img)

    total_expected = sum(expected_counts.values())
    total_detected = sum(counts.values())
    assert confidence in ("low", "medium", "high")
    # A classical (non-ML) circle detector on a clean synthetic image with no
    # occlusion should recover essentially all chips — this is a floor for
    # catching regressions, not a claim about real photos (see README).
    assert total_detected >= total_expected * 0.9, (
        f"Detected only {total_detected}/{total_expected} chips — "
        "check whether a parameter change in chip_detection.py hurt recall."
    )
    for color, expected in expected_counts.items():
        assert abs(counts[color] - expected) <= 1, (
            f"{color}: expected ~{expected}, got {counts[color]}"
        )


if __name__ == "__main__":
    test_detects_all_chips_with_correct_colors()
    print("OK")

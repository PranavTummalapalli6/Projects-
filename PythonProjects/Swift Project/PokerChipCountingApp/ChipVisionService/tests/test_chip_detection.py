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

from app.chip_detection import detect_chips, detect_chips_detailed

_COLORS_BGR = {
    "White": (235, 235, 235),
    "Red": (40, 40, 210),
    "Blue": (200, 60, 30),
    "Green": (60, 160, 40),
    "Black": (25, 25, 25),
}


def _build_synthetic_image(expected_counts: dict, canvas: int = 700) -> np.ndarray:
    # A dark felt background (BGR ~90,60,20, luminance ~51) used to sit here.
    # Hough operates on grayscale, and that luminance was only ~15 units away
    # from Blue's (~67) — a near-invisible edge that forced the detector's
    # sensitivity to be tuned unrealistically high just to find it, which then
    # made it far too trigger-happy on real photos' background texture. This
    # light neutral gray (luminance ~173) sits at least ~60 units from every
    # chip color instead, which is a fairer bar: a real edge, not a coin flip.
    img = np.full((canvas, canvas, 3), (170, 175, 170), dtype=np.uint8)
    radius = 22
    step = radius * 2 + 14
    margin = radius + 4
    x, y = margin, margin

    # Interleaved round-robin, not grouped into one block per color — every
    # real photographed chip stack we've tested against has different colors
    # sitting right next to each other, not segregated. _keep_most_diverse_
    # cluster picks the spatial group with the most distinct colors to reject
    # background clutter (a colorful bottle, a basket, elsewhere in frame);
    # it needs that same local diversity here to recognize this as one real
    # stack instead of five separate single-color groups, each an easy loss
    # against a same-size same-color "cluster" of background noise.
    order = []
    remaining = dict(expected_counts)
    while any(count > 0 for count in remaining.values()):
        for color_name in expected_counts:
            if remaining[color_name] > 0:
                order.append(color_name)
                remaining[color_name] -= 1

    for color_name in order:
        # Wrap BEFORE drawing — wrapping after (as an earlier version of this
        # test did) can leave the last circle in a row centered past the
        # canvas edge, silently drawing it off-frame and making the detector
        # look like it missed a chip it was never actually shown.
        if x + radius > canvas - margin:
            x = margin
            y += step
        bgr = _COLORS_BGR[color_name]
        cv2.circle(img, (x, y), radius, bgr, -1)
        # A small contrasting "logo" dot, like a real chip's printed center
        # marking — needed so _has_chip_texture (added to catch shadows
        # being misread as black chips) has actual internal brightness
        # variance to find, the same way a real chip's rim pattern/logo
        # would give it. A flat solid disc, unlike a real chip, has none.
        logo_bgr = (30, 30, 30) if color_name == "White" else (240, 240, 240)
        cv2.circle(img, (x, y), max(3, radius // 6), logo_bgr, -1)
        x += step

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


def test_each_counted_chip_comes_with_a_position_the_app_can_draw():
    expected_counts = {"White": 3, "Red": 5, "Blue": 2, "Green": 4, "Black": 3}
    img = _build_synthetic_image(expected_counts)
    height, width = img.shape[:2]

    counts, confidence, detections = detect_chips_detailed(img)

    assert (counts, confidence) == detect_chips(img), "the older entry point answers the same"
    assert len(detections) == sum(counts.values()), "one marker per counted chip, no more"
    for color, expected in counts.items():
        assert sum(1 for d in detections if d.color == color) == expected
    for d in detections:
        # Fractions of the photo's width, so they survive any resize.
        assert 0 < d.x < 1 and 0 < d.y < height / width, d
        assert 0 < d.r < 0.5, d
        # Rounded for the wire: four places is well under a pixel on a 4,000-px photo.
        assert round(d.x, 4) == d.x and round(d.y, 4) == d.y and round(d.r, 4) == d.r


def test_a_photo_with_no_chips_has_no_detections():
    blank = np.full((400, 400, 3), 200, dtype=np.uint8)
    counts, confidence, detections = detect_chips_detailed(blank)
    assert sum(counts.values()) == 0 and confidence == "low" and detections == []


if __name__ == "__main__":
    test_detects_all_chips_with_correct_colors()
    print("OK")

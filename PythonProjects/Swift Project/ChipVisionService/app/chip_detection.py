"""
Best-effort poker chip detection: a Hough circle transform to find chip-face
candidates, then color-match each one against the five known chip colors the
app already uses (White/Red/Blue/Green/Black). A second, more permissive pass
rescues low-contrast candidates the first pass missed, but only keeps ones
that color-match as black and don't overlap an existing detection — that pass
exists specifically because dark chips have less edge contrast against a
shadowed/dark background than the other four colors, so a single threshold
that works well for them tends to be too strict for black.

This is classic computer vision, not a trained model. It does reasonably on
separated, top-down, well-lit chip stacks, and will undercount chips that are
fully hidden inside a tall stack (their faces simply aren't visible in a single
photo). That's a real, known limitation — the `confidence` this returns is a
coarse signal for that, and the app always requires the user to review and
correct the counts before a result is calculated. Don't remove that review step
on the client just because this looks confident.
"""

from typing import Dict, Tuple

import cv2
import numpy as np

# Reference colors in OpenCV's HSV space (H: 0-179, S/V: 0-255).
_REFERENCE_COLORS_HSV: Dict[str, Tuple[int, int, int]] = {
    "White": (0, 0, 220),
    "Red": (0, 200, 200),
    "Blue": (110, 200, 200),
    "Green": (60, 200, 180),
    "Black": (0, 0, 30),
}

_KNOWN_COLORS = list(_REFERENCE_COLORS_HSV.keys())


def _nearest_color(hsv_pixel: np.ndarray) -> str:
    h, s, v = hsv_pixel
    best_color = _KNOWN_COLORS[0]
    best_distance = float("inf")
    for color, (rh, rs, rv) in _REFERENCE_COLORS_HSV.items():
        # Hue is circular (0-179 in OpenCV) — use the shorter arc between the two hues.
        dh = min(abs(int(h) - rh), 180 - abs(int(h) - rh))
        distance = (dh * 2) ** 2 + (int(s) - rs) ** 2 + (int(v) - rv) ** 2
        if distance < best_distance:
            best_distance = distance
            best_color = color
    return best_color


def _hough_circles(gray_image: np.ndarray, param1: int, param2: int, min_radius: int, max_radius: int):
    circles = cv2.HoughCircles(
        gray_image,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=float(min_radius) * 1.5,
        param1=param1,
        param2=param2,
        minRadius=min_radius,
        maxRadius=max_radius,
    )
    if circles is None:
        return np.empty((0, 3), dtype=int)
    return np.round(circles[0]).astype(int)


def _sample_color(hsv_image: np.ndarray, x: int, y: int, r: int):
    """Returns (median_hsv_pixel, saturation_std) for a small patch at the
    circle's center, or None if the patch is empty. Sampling the center
    (not the whole disc) avoids picking up a neighboring chip's edge color;
    the median (not mean) shrugs off a stray contaminated pixel at the
    patch's edge rather than letting it skew the estimate.
    """
    sample_radius = max(2, r // 3)
    y0, y1 = max(0, y - sample_radius), min(hsv_image.shape[0], y + sample_radius)
    x0, x1 = max(0, x - sample_radius), min(hsv_image.shape[1], x + sample_radius)
    patch = hsv_image[y0:y1, x0:x1]
    if patch.size == 0:
        return None
    pixels = patch.reshape(-1, 3)
    return np.median(pixels, axis=0), pixels.std(axis=0)[1]


def detect_chips(image_bgr: np.ndarray) -> Tuple[Dict[str, int], str]:
    """Returns (counts_by_color, confidence) where confidence is "low"/"medium"/"high"."""
    counts: Dict[str, int] = {color: 0 for color in _KNOWN_COLORS}

    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blurred = cv2.medianBlur(gray, 5)

    height, width = gray.shape
    min_radius = max(8, min(height, width) // 60)
    max_radius = max(min_radius + 4, min(height, width) // 12)

    detected = _hough_circles(blurred, param1=80, param2=20, min_radius=min_radius, max_radius=max_radius)

    # Second pass, more permissive (lower param1/param2 = less strict edge
    # requirement) — needed because black chips have low edge contrast against
    # a dark/shadowed background, which the primary pass's stricter thresholds
    # sometimes miss entirely. Only candidates that (a) don't overlap something
    # already found and (b) actually color-match as black are kept from this
    # pass, so it can't introduce false positives or double-counts for the
    # other four colors, which the primary pass already handles well.
    hsv_image = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
    permissive = _hough_circles(blurred, param1=40, param2=18, min_radius=min_radius, max_radius=max_radius)
    rescued = []
    for (x, y, r) in permissive:
        if any(abs(int(x) - int(dx)) < min_radius and abs(int(y) - int(dy)) < min_radius for dx, dy, _ in detected):
            continue  # already found by the primary pass
        sample = _sample_color(hsv_image, x, y, r)
        if sample is None:
            continue
        median_pixel, _ = sample
        if _nearest_color(median_pixel) == "Black":
            rescued.append((x, y, r))

    all_circles = np.concatenate([detected, np.array(rescued, dtype=int).reshape(-1, 3)]) if rescued else detected

    if len(all_circles) == 0:
        return counts, "low"

    ambiguous = 0
    for (x, y, r) in all_circles:
        sample = _sample_color(hsv_image, x, y, r)
        if sample is None:
            continue
        median_pixel, saturation_std = sample
        color = _nearest_color(median_pixel)
        counts[color] += 1

        # High saturation variance in the sampled patch suggests we caught an
        # edge/overlap rather than a clean chip face — a proxy for uncertainty.
        if saturation_std > 60:
            ambiguous += 1

    total = len(all_circles)
    if ambiguous / total > 0.35:
        confidence = "low"
    elif ambiguous / total > 0.15:
        confidence = "medium"
    else:
        confidence = "high"

    return counts, confidence

"""
Best-effort poker chip detection: a Hough circle transform finds chip-face
candidates, then several filters throw out everything that isn't actually a
chip before color-matching survivors against the five known chip colors the
app already uses (White/Red/Blue/Green/Black):

  - _merge_overlapping_circles collapses duplicate hits on the same physical
    chip (its outer rim, inner rim pattern, and center logo are all distinct
    edges Hough can separately latch onto).
  - _is_isolated requires a real edge against the background — flat texture
    (a desk, a laptop lid) doesn't have one, even when it happens to pass
    Hough's own edge threshold.
  - _keep_consistent_radius rejects candidates whose size doesn't match the
    rest of the group — a real photo can contain other round, colorful
    objects at a different distance from the camera (a cup, a logo), and
    those are usually a size outlier because of that.
  - _keep_in_focus rejects candidates well outside the sharpest object in
    frame — a phone's shallow depth of field means background clutter often
    (not always) comes out visibly softer than the chips it focused on.
  - _keep_near_chromatic_anchors: White/Black are hard to tell apart from
    generic bright/dark background by color alone, so those two are only
    trusted near a Red/Green/Blue detection, which requires an actual
    saturated hue background rarely produces by chance. (A fancier version
    that clustered every candidate and kept whichever group had the most
    distinct colors was tried and reverted — it broke when the real chips
    in a photo weren't all mutually close enough to form one connected
    group. _keep_in_focus running first covers most of what that was
    reaching for, without that fragility.)
  - A second, more permissive Hough pass (restricted to near that trusted
    area) rescues black chips specifically — they have less edge contrast
    against a dark/shadowed background than the other four colors, so the
    primary pass's threshold sometimes misses them entirely.

Every one of these thresholds was tuned against a synthetic clean image (see
tests/) and 9 real, messy phone photos (different backgrounds, lighting, and
phone orientations) with known ground truth — not guessed. Even so, this is
classic computer vision, not a trained model. It does reasonably on separated,
top-down, well-lit chip stacks, and will undercount chips that are fully
hidden inside a tall stack or touching another chip (their faces simply
aren't visible, or aren't a separable circle, in a single top-down photo).
That's a real, known limitation — the `confidence` this returns is a coarse
signal for that, and the app always requires the user to review and correct
the counts before a result is calculated. Don't remove that review step on
the client just because this looks confident.
"""

from dataclasses import dataclass
from typing import Dict, List, Tuple

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

# Real phone photos come in at full camera resolution (often 12MP+). Running
# the Hough transform below on that directly is slow enough to time out the
# client, and buys nothing — it also floods the permissive second pass with
# false-positive "circles" from fine real-world texture that a synthetic test
# image doesn't have. Downscaling keeps detection fast and sane; the photo
# actually uploaded to Storage is unaffected (main.py uploads the original
# full-resolution bytes, not this resized working copy).
_MAX_DETECTION_DIMENSION = 1280


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
        # This only needs to reject near-identical duplicate votes for the same
        # edge — it is NOT what separates distinct chips from a single chip's
        # own internal edges (rim vs. inner logo). That used to be minDist's
        # job, scaled off max_radius, but max_radius is just a generic upper
        # bound on the search range, not the actual chip size in a given
        # photo — on a tightly-packed synthetic test it was far too large
        # (merging genuinely adjacent chips into one), and on a real photo
        # still too small (hundreds of bogus same-chip/background detections).
        # _merge_overlapping_circles below does that job properly, using each
        # candidate's own detected radius instead of a guessed bound.
        minDist=float(min_radius) * 1.5,
        param1=param1,
        param2=param2,
        minRadius=min_radius,
        maxRadius=max_radius,
    )
    if circles is None:
        return np.empty((0, 3), dtype=int)
    return np.round(circles[0]).astype(int)


def _merge_overlapping_circles(circles: np.ndarray, merge_factor: float = 1.8) -> np.ndarray:
    """Collapses circles that almost certainly belong to the same physical
    chip — its outer rim, inner rim pattern, and center logo are all distinct
    edges Hough can separately latch onto, and on a real (non-synthetic) photo
    that alone produced hundreds of duplicate "chips" for a handful of actual
    ones. Distance is compared against each candidate's own detected radius
    (not a fixed guess), so this scales correctly whether chips fill the frame
    or are small and numerous.

    1.8 (not the smaller value this used to be) was necessary once real test
    photos showed a red chip's printed logo/shadowed rim getting sampled as a
    *second*, separately-colored "black chip" duplicate ~1.5x its own radius
    away — just outside the old threshold. Verified this still doesn't merge
    two genuinely distinct adjacent chips: the closest real (different-chip)
    detections seen across test photos were ~2.4x radius apart.
    """
    if len(circles) == 0:
        return circles
    # Larger circles first — a chip's outer rim is a more reliable size/position
    # estimate than an inner logo/pattern edge, so it's kept over a nested one.
    ordered = sorted((tuple(c) for c in circles), key=lambda c: -c[2])
    kept = []
    for (x, y, r) in ordered:
        if any(
            ((x - kx) ** 2 + (y - ky) ** 2) ** 0.5 < merge_factor * max(r, kr)
            for kx, ky, kr in kept
        ):
            continue
        kept.append((x, y, r))
    return np.array(kept, dtype=int)


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


_MIN_ISOLATION_CONTRAST = 25.0


def _is_isolated(hsv_image: np.ndarray, x: int, y: int, r: int, center_hsv: np.ndarray) -> bool:
    """A real chip has a distinct edge against whatever it's sitting on; flat
    background texture (e.g. a laptop lid, a table) doesn't. This compares the
    circle's center color against a ring just outside its detected radius and
    requires a minimum contrast — on a real test photo this cleanly separated
    actual chips (contrast 59-200) from false positives Hough found on plain
    dark desk/laptop background (contrast 3-18), without needing per-color
    tuning to catch it.
    """
    outer = r * 1.4
    y0, y1 = max(0, int(y - outer)), min(hsv_image.shape[0], int(y + outer))
    x0, x1 = max(0, int(x - outer)), min(hsv_image.shape[1], int(x + outer))
    patch = hsv_image[y0:y1, x0:x1]
    if patch.size == 0:
        return False
    yy, xx = np.mgrid[y0:y1, x0:x1]
    dist = np.sqrt((xx - x) ** 2 + (yy - y) ** 2)
    ring_mask = (dist > r * 1.05) & (dist < outer)
    if ring_mask.sum() < 5:
        return False
    ring_hsv = np.median(patch[ring_mask], axis=0)
    contrast = float(np.linalg.norm(center_hsv.astype(float) - ring_hsv.astype(float)))
    return contrast >= _MIN_ISOLATION_CONTRAST


_MIN_CHIP_TEXTURE_STD = 15.0


def _has_chip_texture(hsv_image: np.ndarray, x: int, y: int, r: int) -> bool:
    """A cast shadow is dark and low-saturation, same as the Black reference
    color, and (unlike flat background) it does have a real edge where it
    meets a lit surface — so _is_isolated alone lets shadows through as false
    "black chips". A real chip face isn't a flat dark disc: it has printed rim
    segments and a center logo, which gives the brightness (V) channel real
    variance across the disc. A shadow is just a smooth falloff and won't.
    This is a general fix, not tuned against a specific failure photo — the
    threshold is a reasonable estimate; narrow it further if it's still
    letting shadows through, or loosen it if it starts rejecting real chips
    photographed in flat/diffuse lighting (which reduces their own texture
    contrast too).
    """
    sample_r = max(3, int(r * 0.75))
    y0, y1 = max(0, y - sample_r), min(hsv_image.shape[0], y + sample_r)
    x0, x1 = max(0, x - sample_r), min(hsv_image.shape[1], x + sample_r)
    patch = hsv_image[y0:y1, x0:x1]
    if patch.size == 0:
        return False
    yy, xx = np.mgrid[y0:y1, x0:x1]
    dist = np.sqrt((xx - x) ** 2 + (yy - y) ** 2)
    disc_mask = dist < sample_r
    if disc_mask.sum() < 10:
        return False
    value_channel = patch[disc_mask][:, 2]
    return float(value_channel.std()) >= _MIN_CHIP_TEXTURE_STD


def _sharpness(gray_image: np.ndarray, x: int, y: int, r: int) -> float:
    """Variance of the Laplacian — a standard focus/blur metric. A phone photo
    of chips has a shallow enough depth of field that background clutter
    (a bottle, a basket) sits outside the focus plane the camera locked onto
    for the chips and comes out visibly softer, even when it's otherwise
    passed every color/texture/isolation check above."""
    h, w = gray_image.shape
    y0, y1 = max(0, y - r), min(h, y + r)
    x0, x1 = max(0, x - r), min(w, x + r)
    patch = gray_image[y0:y1, x0:x1]
    if patch.size == 0:
        return 0.0
    return float(cv2.Laplacian(patch, cv2.CV_64F).var())


def _keep_in_focus(circles, gray_image: np.ndarray, reference=None, relative_threshold: float = 0.2):
    """Keeps only candidates reasonably close to the sharpest one found. Not a
    fixed sharpness floor — phones vary hugely in how much overall detail
    they capture — just relative to whatever this specific photo's sharpest
    in-frame object is, which should be a chip. This alone doesn't catch
    everything (something sitting right next to the chips, at the same
    distance from the camera, stays just as in-focus) — it's a complement to
    _keep_near_chromatic_anchors, not a replacement. Pass `reference` to
    compare a second batch (e.g. rescued candidates) against the peak
    sharpness of an already-trusted set instead of its own — a handful of
    already-suspicious candidates can otherwise all be blurry and still pass
    relative to each other.
    """
    circles = list(circles)
    if not circles:
        return circles
    pool = reference if reference is not None else circles
    pool_sharpness = [_sharpness(gray_image, x, y, r) for (x, y, r) in pool]
    peak = max(pool_sharpness) if pool_sharpness else 0
    if peak <= 0:
        return circles
    return [
        c for c in circles
        if _sharpness(gray_image, c[0], c[1], c[2]) >= relative_threshold * peak
    ]


def _keep_consistent_radius(circles, reference=None, tolerance: float = 0.25):
    """Every chip in a single photo is the same physical size, so a genuine
    stack's detections should all have roughly the same radius — a real photo
    can otherwise still contain other colorful round-ish objects at a
    different distance from the camera (a cup, a logo) that pass every other
    check here; those are typically a size outlier precisely because they're
    not sitting at the same distance as the chips. Median-based so a couple of
    outliers can't drag the reference point toward themselves. Pass
    `reference` to check a second batch (e.g. rescued candidates) against an
    already-established median rather than its own, usually too-small, sample.
    """
    circles = list(circles)
    pool = reference if reference is not None else circles
    if len(pool) < 3:
        return circles
    median_r = float(np.median([r for _, _, r in pool]))
    return [(x, y, r) for (x, y, r) in circles if abs(r - median_r) <= tolerance * median_r]


_CHROMATIC_COLORS = {"Red", "Green", "Blue"}


def _keep_near_chromatic_anchors(circles, hsv_image: np.ndarray, max_radius: int):
    """White and black chips are hard to tell apart from generic bright/dark
    background by color alone — measured directly against real photos, a
    false "White"/"Black" hit on messy background (a desk edge, a logo) can
    have just as much local contrast as an actual chip. Red/Green/Blue
    require an actual saturated hue, which background produces far less
    readily by chance, so those are trusted on their own; White/Black are
    only kept if they're near where a chromatic chip was actually found — a
    photographed chip stack is one group, not scattered across the frame.

    A fancier version of this that clustered every candidate by proximity and
    picked the most color-diverse group was tried and reverted — it broke on
    a real photo where the actual chips weren't all mutually close enough to
    form one connected group, and ended up preferring a coincidental same-
    color *pair* of false detections over correct, if scattered, singletons.
    Anchoring on chromatic color plus _keep_in_focus (which now runs first
    and already strips out most out-of-focus background) covers the same
    real failure cases with less of that fragility. Falls back to keeping
    everything if there are no chromatic anchors at all (e.g. an all-black or
    all-white stack), since there's nothing to anchor to.
    """
    circles = list(circles)
    if not circles:
        return circles

    def color_of(x, y, r):
        sample = _sample_color(hsv_image, x, y, r)
        return _nearest_color(sample[0]) if sample is not None else None

    labeled = [(x, y, r, color_of(x, y, r)) for (x, y, r) in circles]
    anchors = [(x, y, r) for (x, y, r, color) in labeled if color in _CHROMATIC_COLORS]
    if not anchors:
        return circles

    pad = max_radius * 3.5
    min_x = min(x for x, _, _ in anchors) - pad
    max_x = max(x for x, _, _ in anchors) + pad
    min_y = min(y for _, y, _ in anchors) - pad
    max_y = max(y for _, y, _ in anchors) + pad

    return [
        (x, y, r) for (x, y, r, color) in labeled
        if color in _CHROMATIC_COLORS or (min_x <= x <= max_x and min_y <= y <= max_y)
    ]


@dataclass(frozen=True)
class Detection:
    """One chip the detector counted, in coordinates that don't depend on how big
    the photo is shown: `x`/`y` are the centre and `r` the radius, each as a
    fraction of the image *width* (so a circle can be drawn at any display size
    and a photo of any aspect ratio, without the app knowing what resolution the
    server worked at)."""
    x: float
    y: float
    r: float
    color: str


def detect_chips(image_bgr: np.ndarray) -> Tuple[Dict[str, int], str]:
    """Returns (counts_by_color, confidence) where confidence is "low"/"medium"/"high"."""
    counts, confidence, _ = detect_chips_detailed(image_bgr)
    return counts, confidence


def detect_chips_detailed(image_bgr: np.ndarray) -> Tuple[Dict[str, int], str, List[Detection]]:
    """Like `detect_chips`, and also where each counted chip is, so the app can
    draw the detections over the photo and let the person correct them."""
    counts: Dict[str, int] = {color: 0 for color in _KNOWN_COLORS}
    detections: List[Detection] = []

    orig_height, orig_width = image_bgr.shape[:2]
    longest_side = max(orig_height, orig_width)
    if longest_side > _MAX_DETECTION_DIMENSION:
        scale = _MAX_DETECTION_DIMENSION / longest_side
        image_bgr = cv2.resize(
            image_bgr,
            (int(orig_width * scale), int(orig_height * scale)),
            interpolation=cv2.INTER_AREA,
        )

    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blurred = cv2.medianBlur(gray, 5)

    height, width = gray.shape
    min_radius = max(8, min(height, width) // 60)
    max_radius = max(min_radius + 4, min(height, width) // 12)

    hsv_image = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
    detected = _hough_circles(blurred, param1=100, param2=20, min_radius=min_radius, max_radius=max_radius)
    detected = _merge_overlapping_circles(detected)
    confident = [
        (x, y, r) for (x, y, r) in detected
        if (s := _sample_color(hsv_image, x, y, r)) is not None
        and _is_isolated(hsv_image, x, y, r, s[0])
        # A shadow can be just as dark and just as "isolated" (real edge where
        # it meets a lit surface) as an actual black chip — this is the extra
        # check that tells them apart. See _has_chip_texture.
        and (_nearest_color(s[0]) != "Black" or _has_chip_texture(hsv_image, x, y, r))
    ]
    confident = _keep_consistent_radius(confident)
    confident = _keep_in_focus(confident, gray)
    confident = _keep_near_chromatic_anchors(confident, hsv_image, max_radius)

    # A second, more permissive Hough pass used to run here specifically to
    # rescue black chips the primary pass missed (they have less edge contrast
    # against a dark/shadowed background than the other four colors). Removed
    # after real-photo testing showed it now does more harm than good: with
    # _keep_in_focus and _keep_near_chromatic_anchors already in place, the
    # primary pass finds real black chips on its own in the large majority of
    # cases, while the permissive pass kept finding extra background circles
    # (typically sitting right next to the real chips, at the same distance
    # from the camera, so _keep_in_focus doesn't discriminate them either) —
    # trading a rare missed black chip (the safe, expected, user-reviews-it
    # failure mode) for a much more frequent overcount (the actively
    # misleading one) was a bad trade.
    all_circles = np.array(confident, dtype=int).reshape(-1, 3)

    if len(all_circles) == 0:
        return counts, "low", detections

    ambiguous = 0
    kept = 0
    for (x, y, r) in all_circles:
        sample = _sample_color(hsv_image, x, y, r)
        if sample is None:
            continue
        median_pixel, saturation_std = sample
        # The primary pass's own detections still need this check — a flat
        # patch of dark desk/background can pass the Hough edge threshold too
        # (see docstring on _is_isolated), and this is what actually rejects it.
        if not _is_isolated(hsv_image, x, y, r, median_pixel):
            continue
        color = _nearest_color(median_pixel)
        counts[color] += 1
        kept += 1
        detections.append(Detection(
            x=round(float(x) / width, 4),
            y=round(float(y) / width, 4),
            r=round(float(r) / width, 4),
            color=color,
        ))

        # High saturation variance in the sampled patch suggests we caught an
        # edge/overlap rather than a clean chip face — a proxy for uncertainty.
        if saturation_std > 60:
            ambiguous += 1

    if kept == 0:
        return counts, "low", detections

    total = kept
    if ambiguous / total > 0.35:
        confidence = "low"
    elif ambiguous / total > 0.15:
        confidence = "medium"
    else:
        confidence = "high"

    return counts, confidence, detections

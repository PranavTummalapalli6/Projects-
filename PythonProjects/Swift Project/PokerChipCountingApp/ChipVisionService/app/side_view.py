"""
Counting chips in a photo taken from the side, or from a low angle.

The top-down counter (chip_detection.py) looks for circles, so it cannot read a
photo where each chip is a sliver or a squashed ellipse. This module reads those
photos instead. It finds each pile, names its colour, and estimates how many
chips are in it. The estimate is always a suggestion: the app shows it over the
photo and lets the person correct any pile.

How it works, in the order it runs:

  1. Camera pose. A phone knows which way it is pointing. The app sends the
     pitch (how far below the horizon the camera looks), the roll (how far the
     picture is tilted) and the focal length. With those the chip geometry is
     known: a chip seen at elevation θ shows a top face squashed to sin θ of its
     width, and a side wall cos θ of its thickness tall. The picture is rotated
     level first. Without a pose a typical 22° is assumed and every count is
     reported as low confidence.
  2. Piles. Red, green and blue piles are found by colour; each must show the
     bright rim "tabs" printed on poker chips, which is what separates a chip from
     a red or green object in the background. That fixes the size of a chip in
     the photo, and the row the chips stand in. White chips (white body, coloured
     tabs) and black chips (dark body, white tabs) are then looked for in that row.
     A chip is always named for the colour of its body, never for its tabs: a white
     chip with blue tabs is White, whatever colours the night is using.
  3. Counting. A pile's silhouette area, measured in units of one chip's side
     wall, says how many chips make it up: each chip added to a tidy stack adds one
     wall's worth of area. The constants are physical (a 3.3 mm chip in a 39 mm
     diameter) and were checked on photos of one chip set, not fitted to it. Black
     piles have no usable silhouette against a dark table, so they are counted from
     the rings of tabs alone.

What it cannot do, and says so:
  - It needs rim tabs. Chips with a plain edge are not found.
  - It needs at least one red, green or blue pile in the photo to learn the chip
    size from; a photo of only white and black chips finds nothing.
  - Loose piles (chips pushed off-centre) and very tall stacks are both estimates.
  - Nothing here has been validated beyond a handful of photos of one chip set,
    so confidence is never "high".
"""

import itertools
import math
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import cv2
import numpy as np

_KNOWN_COLORS = ["White", "Red", "Blue", "Green", "Black"]

# Same working size as the top-down detector: fast, and plenty for chip edges.
_MAX_DIMENSION = 1280

# A standard clay-composite chip: 3.3 mm thick, 39 mm across.
_THICKNESS_OVER_DIAMETER = 0.0846
# Of the width, the share of a chip's side wall that shows up as silhouette area
# once the curve of the base is allowed for.
_WALL_AREA_FACTOR = 0.95
# The pose assumed when the app sends none.
_DEFAULT_PITCH_DEG = 22.0
_DEFAULT_FOCAL_35MM = 24.0

# Tabs: bright, almost colourless rectangles on the rim of a chip.
_TAB_LIGHTNESS = 70.0
_TAB_MAX_CHROMA = 14.0
# Area of a tab as a share of the chip's width squared.
_TAB_AREA_RANGE = (0.0015, 0.016)
# A tab's centre sits this far out from the middle of the chip, as a share of its radius.
_TAB_RING = 0.86
# Piles within this factor of the median width count as one size.
_SIZE_TOLERANCE = 0.5

# n = 1 + floor(excess + this). Tidy stacks add exactly one wall of area per chip;
# loose pairs add a little more, so the boundary sits a quarter chip below the
# next whole number.
_COUNT_ROUNDING = 0.25


@dataclass(frozen=True)
class CameraPose:
    """How the photo was taken, from the phone's own sensors."""
    pitch_deg: float          # how far below the horizon the camera looks
    roll_deg: float = 0.0     # how far the picture is turned about the camera's axis
    focal_35mm: float = _DEFAULT_FOCAL_35MM


@dataclass(frozen=True)
class Stack:
    """One pile of chips. `x`/`y` are its centre and `w`/`h` its size, each as a
    fraction of the photo's width, in the photo as it was sent (not as rotated
    level here); `angle` is how far to turn a box drawn there."""
    x: float
    y: float
    w: float
    h: float
    angle: float
    color: str
    count: int
    confidence: str


@dataclass
class _Group:
    # Tabs found on the pile, as (x, y) centres; used to look for rings.
    color: str
    box: Tuple[int, int, int, int]                       # x, y, w, h in the level, resized image
    seed: Optional[np.ndarray] = None                    # what was found by colour, full-image size
    mask: Optional[np.ndarray] = None                    # silhouette, full-image size
    tabs: List[Tuple[float, float]] = field(default_factory=list)
    tab_areas: List[float] = field(default_factory=list)
    rings: int = 0                                       # chips counted from rings of tabs
    chip_width: float = 0.0                              # one chip's width in this photo, in pixels

    def tabs_for_rings(self) -> List[Tuple[float, float]]:
        return self.tabs
    excess: float = 0.0                                  # height in chip walls, for debugging


# MARK: - Public entry point

def detect_stacks(
    image_bgr: np.ndarray,
    pose: Optional[CameraPose] = None,
    colors: Optional[Sequence[str]] = None,
) -> Tuple[Dict[str, int], str, List[Stack]]:
    """Returns (counts_by_colour, confidence, stacks).

    A pile is named for the colour of its chips' bodies and nothing else: a white chip
    with blue tabs is White, even when the night uses no white chips (the app leaves a
    colour the night doesn't use out of the counts and says so). `colors`, the chip
    colours in play, is still accepted so that apps which send it keep working, but it
    no longer changes any name.
    """
    del colors
    counts: Dict[str, int] = {color: 0 for color in _KNOWN_COLORS}
    original_height, original_width = image_bgr.shape[:2]
    scale = min(1.0, _MAX_DIMENSION / max(original_height, original_width))
    image = image_bgr
    if scale < 1.0:
        image = cv2.resize(
            image_bgr, (int(original_width * scale), int(original_height * scale)), interpolation=cv2.INTER_AREA
        )

    roll = pose.roll_deg if pose else 0.0
    to_level: Optional[np.ndarray] = None
    if abs(roll) >= 1.0:
        image, to_level = _rotate(image, roll)
    height, width = image.shape[:2]

    lab = _lab(image)
    groups = _find_groups(image, lab, lambda row: _elevation_at(row, pose, height, width))
    if not groups:
        return counts, "low", []

    stacks: List[Stack] = []
    confidences: List[str] = []
    for group in groups:
        theta = _elevation(group, pose, height, width)
        count, confidence = _count_group(group, theta, known_pose=pose is not None)
        confidences.append(confidence)
        counts[group.color] += count
        stacks.append(_to_stack(group, count, confidence, original_width * scale, to_level, roll))

    overall = "low" if "low" in confidences else "medium"
    return counts, overall, stacks


# MARK: - Geometry helpers

def _rotate(image: np.ndarray, degrees: float) -> Tuple[np.ndarray, np.ndarray]:
    """Turns the picture level. Returns the result and the matrix that did it."""
    height, width = image.shape[:2]
    matrix = cv2.getRotationMatrix2D((width / 2.0, height / 2.0), degrees, 1.0)
    level = cv2.warpAffine(image, matrix, (width, height), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    return level, matrix


def _elevation(group: _Group, pose: Optional[CameraPose], height: int, width: int) -> float:
    """The angle above the table at which the camera sees this pile, in degrees."""
    x, y, w, h = group.box
    return _elevation_at(y + h / 2.0, pose, height, width)


def _elevation_at(row: float, pose: Optional[CameraPose], height: int, width: int) -> float:
    """The same, for a row of the (level) picture: lower in the frame is steeper."""
    pitch = pose.pitch_deg if pose else _DEFAULT_PITCH_DEG
    focal = (pose.focal_35mm if pose else _DEFAULT_FOCAL_35MM) * width / 36.0
    theta = pitch + math.degrees(math.atan((row - height / 2.0) / focal))
    return min(max(theta, 4.0), 80.0)


def _to_stack(
    group: _Group, count: int, confidence: str, unit: float, to_level: Optional[np.ndarray], roll: float,
) -> Stack:
    """`unit` is the width of the resized picture: what turns pixels into fractions."""
    x, y, w, h = group.box
    cx, cy = x + w / 2.0, y + h / 2.0
    if to_level is not None:
        cx, cy = cv2.invertAffineTransform(to_level) @ np.array([cx, cy, 1.0])
    return Stack(
        x=round(float(cx) / unit, 4), y=round(float(cy) / unit, 4),
        w=round(w / unit, 4), h=round(h / unit, 4),
        angle=round(-roll, 1), color=group.color, count=count, confidence=confidence,
    )


# MARK: - Colour

def _lab(image: np.ndarray) -> Dict[str, np.ndarray]:
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB).astype(np.float32)
    lightness = lab[..., 0] * 100.0 / 255.0
    a = lab[..., 1] - 128.0
    b = lab[..., 2] - 128.0
    return {"L": lightness, "a": a, "b": b, "C": np.hypot(a, b)}


def _odd(value: float, minimum: int = 3) -> int:
    size = max(minimum, int(round(value)))
    return size if size % 2 == 1 else size + 1


def _ellipse(size: int) -> np.ndarray:
    return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (size, size))


def _chromatic_masks(lab: Dict[str, np.ndarray]) -> Dict[str, np.ndarray]:
    L, a, b, C = lab["L"], lab["a"], lab["b"], lab["C"]
    return {
        # Chip red: a* around +45..+52. A table, a shadow and a white tab are all near zero.
        "Red": (a > 22) & (b > -5) & (C > 30) & (L > 20),
        # A pastel chip green sits at a* -24, b* +17; its shaded wall is a* -10, b* +9.
        "Green": (a < -8) & (b > 4) & (C > 12),
        "Blue": (b < -18) & (C > 22),
    }


def _tab_mask(lab: Dict[str, np.ndarray]) -> np.ndarray:
    mask = ((lab["L"] > _TAB_LIGHTNESS) & (lab["C"] < _TAB_MAX_CHROMA)).astype(np.uint8) * 255
    return cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))


def _components(mask: np.ndarray):
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask)
    return labels, [(i, stats[i], centroids[i]) for i in range(1, count)]


def _is_tab(stat: np.ndarray, width_ref: float, relax: float = 1.0) -> bool:
    low, high = _TAB_AREA_RANGE
    bw, bh, area = stat[cv2.CC_STAT_WIDTH], stat[cv2.CC_STAT_HEIGHT], stat[cv2.CC_STAT_AREA]
    if not (low * relax * width_ref ** 2 <= area <= high / relax * width_ref ** 2):
        return False
    return area / float(bw * bh) >= 0.35 and 0.3 <= bw / float(max(bh, 1)) <= 6.0


def _tabs_in(tab_mask: np.ndarray, box: Tuple[int, int, int, int], width_ref: float) -> List[Tuple[float, float, float]]:
    """Centres and areas of tab-sized, tab-shaped blobs inside a box."""
    x0, y0, w, h = box
    pad = int(0.1 * w)
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    crop = tab_mask[y0:y0 + h + 2 * pad, x0:x0 + w + 2 * pad]
    _, parts = _components(crop)
    return [(x0 + float(c[0]), y0 + float(c[1]), float(stat[cv2.CC_STAT_AREA])) for _, stat, c in parts if _is_tab(stat, width_ref)]


# MARK: - Finding the piles

def _find_groups(
    image: np.ndarray, lab: Dict[str, np.ndarray], theta_at: Callable[[float], float],
) -> List[_Group]:
    height, width = lab["L"].shape
    tab_mask = _tab_mask(lab)

    anchors = _consistent(_without_fragments(_merged(_chromatic_piles(lab, tab_mask))))
    if not anchors:
        return []
    chip_width = float(np.median([g.box[2] for g in anchors]))
    for group in anchors:
        group.mask = _grow(group.seed, lab, int(0.12 * chip_width))
        group.box = _bounds(group.mask) or group.box
    chip_width = float(np.median([g.box[2] for g in anchors]))

    groups = list(anchors)
    groups += _white_piles(lab, anchors, chip_width, groups)
    groups += _black_piles(lab, tab_mask, anchors, chip_width, groups, theta_at)
    # A loose pile is wider than one chip, so the narrowest of the photo's piles is the best
    # measure of a single chip's width.
    single = float(np.percentile([g.box[2] for g in anchors], 25))
    for group in groups:
        group.chip_width = single
    groups.sort(key=lambda g: g.box[0])
    return groups


def _chromatic_piles(lab: Dict[str, np.ndarray], tab_mask: np.ndarray) -> List[_Group]:
    """Red, green and blue piles: a compact coloured blob that shows rim tabs."""
    height, width = lab["L"].shape
    found: List[_Group] = []
    for name, raw in _chromatic_masks(lab).items():
        mask = cv2.morphologyEx(raw.astype(np.uint8) * 255, cv2.MORPH_CLOSE, _ellipse(_odd(0.012 * width, 5)))
        labels, parts = _components(mask)
        for i, stat, _centre in parts:
            x, y, w, h, area = (int(v) for v in stat)
            if not (0.0010 * width * height <= area <= 0.05 * width * height):
                continue
            part = (labels[y:y + h, x:x + w] == i).astype(np.uint8) * 255
            outline, _ = cv2.findContours(part, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            solid = cv2.contourArea(max(outline, key=cv2.contourArea)) if outline else 0.0
            if not (0.25 <= w / float(h) <= 7.0) or solid / float(w * h) < 0.30:
                continue
            tabs = _tabs_in(tab_mask, (x, y, w, h), w)
            if len(tabs) < 3:
                continue    # no printed rim: not a chip
            found.append(_Group(
                name, (x, y, w, h), seed=(labels == i).astype(np.uint8) * 255,
                tabs=[(t[0], t[1]) for t in tabs], tab_areas=[t[2] for t in tabs],
            ))
    return found


def _merged(groups: List[_Group]) -> List[_Group]:
    """A pile whose top face and side wall were found as two blobs of one colour,
    because the tabs between them are white, is one pile."""
    merged: List[_Group] = []
    for group in sorted(groups, key=lambda g: g.box[1]):
        for other in merged:
            if other.color != group.color:
                continue
            ax, ay, aw, ah = other.box
            bx, by, bw, bh = group.box
            gap_x = max(bx - (ax + aw), ax - (bx + bw), 0)
            gap_y = max(by - (ay + ah), ay - (by + bh), 0)
            if gap_x <= 0.15 * max(aw, bw) and gap_y <= 0.15 * max(aw, bw):
                x0, y0 = min(ax, bx), min(ay, by)
                x1, y1 = max(ax + aw, bx + bw), max(ay + ah, by + bh)
                other.box = (x0, y0, x1 - x0, y1 - y0)
                other.seed = cv2.bitwise_or(other.seed, group.seed)
                other.tabs = other.tabs + [t for t in group.tabs if t not in other.tabs]
                other.tab_areas = other.tab_areas + group.tab_areas
                break
        else:
            merged.append(group)
    return merged


def _without_fragments(groups: List[_Group]) -> List[_Group]:
    """A smudge of one colour on a bigger pile of another is part of that pile."""
    kept: List[_Group] = []
    for group in sorted(groups, key=lambda g: -g.box[2] * g.box[3]):
        if not _overlaps_any(group.box, kept, share=0.4):
            kept.append(group)
    return kept


def _consistent(groups: List[_Group]) -> List[_Group]:
    """The largest set of piles that are about the same size and stand in one row."""
    best: List[_Group] = []
    for seed in groups:
        width = float(seed.box[2])
        row = seed.box[1] + seed.box[3]
        members = [
            g for g in groups
            if abs(g.box[2] - width) <= _SIZE_TOLERANCE * width and abs((g.box[1] + g.box[3]) - row) <= 1.2 * width
        ]
        if len(members) > len(best):
            best = members
    return best


def _grow(seed: np.ndarray, lab: Dict[str, np.ndarray], radius: int) -> np.ndarray:
    """The pile's silhouette: what was found by colour, grown outwards over anything
    coloured or bright (its tabs and its shaded wall), one step at a time so the
    growth stops at the shadow under it instead of leaping over to the glare beyond."""
    solid = ((lab["C"] > 9.0) | (lab["L"] > _TAB_LIGHTNESS - 2.0)).astype(np.uint8)
    grown = (seed > 0).astype(np.uint8)
    step = np.ones((3, 3), np.uint8)
    for _ in range(max(1, radius)):
        grown = cv2.dilate(grown, step) & solid | grown
    grown = cv2.morphologyEx(grown * 255, cv2.MORPH_CLOSE, _ellipse(9))
    contours, _ = cv2.findContours(grown, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    filled = np.zeros_like(grown)
    cv2.drawContours(filled, contours, -1, 255, -1)
    return filled


def _bounds(mask: Optional[np.ndarray]) -> Optional[Tuple[int, int, int, int]]:
    if mask is None:
        return None
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)


def _in_row(anchors: List[_Group], chip_width: float) -> Callable[[float, float], bool]:
    """The strip the first piles stand in. A black chip has no outline of its own to
    check, so it is only looked for here, where chips are most likely to be."""
    top = min(g.box[1] for g in anchors) - 0.8 * chip_width
    bottom = max(g.box[1] + g.box[3] for g in anchors) + 0.8 * chip_width
    left = min(g.box[0] for g in anchors) - 3.0 * chip_width
    right = max(g.box[0] + g.box[2] for g in anchors) + 3.0 * chip_width
    return lambda x, y: left <= x <= right and top <= y <= bottom


def _near_anchors(anchors: List[_Group], chip_width: float) -> Callable[[float, float], bool]:
    """Where to look for the other chips: close to the piles already found. Chips
    are usually in a row, but a photo taken across the table puts them at all depths."""
    def near(x: float, y: float) -> bool:
        return any(
            g.box[0] - 4.5 * chip_width <= x <= g.box[0] + g.box[2] + 4.5 * chip_width
            and g.box[1] - 3.0 * chip_width <= y <= g.box[1] + g.box[3] + 3.0 * chip_width
            for g in anchors
        )
    return near


def _white_piles(lab: Dict[str, np.ndarray], anchors: List[_Group], chip_width: float, taken: List[_Group]) -> List[_Group]:
    """White chips in the same row: a bright, colourless face with coloured tabs."""
    near = _near_anchors(anchors, chip_width)
    # The face and its coloured logo and tabs together, so the logo does not cut it in two.
    body = (((lab["L"] > 72.0) & (lab["C"] < 12.0)) | ((lab["C"] > 25.0) & (lab["b"] < -8.0))).astype(np.uint8) * 255
    body = cv2.morphologyEx(body, cv2.MORPH_OPEN, _ellipse(_odd(0.04 * chip_width)))
    body = cv2.morphologyEx(body, cv2.MORPH_CLOSE, _ellipse(_odd(0.12 * chip_width)))
    labels, parts = _components(body)
    found: List[_Group] = []
    for i, stat, _centre in parts:
        x, y, w, h, area = (int(v) for v in stat)
        if not (0.6 * chip_width <= w <= 1.5 * chip_width):
            continue
        if not (1.1 <= w / float(h) <= 7.0) or area / float(w * h) < 0.5:
            continue
        if not near(x + w / 2.0, y + h / 2.0):
            continue
        if _overlaps_any((x, y, w, h), taken + found):
            continue
        accents = _accent_tabs(lab, (x, y, w, h), w)
        if len(accents) < 2:
            continue
        seed = (labels == i).astype(np.uint8) * 255
        mask = _grow(seed, lab, int(0.12 * chip_width))
        found.append(_Group("White", _bounds(mask) or (x, y, w, h), seed=seed, mask=mask, tabs=accents))
    return found


def _accent_tabs(lab: Dict[str, np.ndarray], box: Tuple[int, int, int, int], width_ref: float) -> List[Tuple[float, float]]:
    """Tab-sized coloured rectangles on a white chip (its blue or red stripes)."""
    x, y, w, h = box
    pad = int(0.1 * w)
    x0, y0 = max(0, x - pad), max(0, y - pad)
    mask = cv2.morphologyEx((lab["C"] > 25.0).astype(np.uint8) * 255, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    crop = mask[y0:y + h + pad, x0:x + w + pad]
    _, parts = _components(crop)
    return [(x0 + float(c[0]), y0 + float(c[1])) for _, stat, c in parts if _is_tab(stat, width_ref, relax=1.3)]


def _black_piles(
    lab: Dict[str, np.ndarray], tab_mask: np.ndarray, anchors: List[_Group], chip_width: float,
    taken: List[_Group], theta_at: Callable[[float], float],
) -> List[_Group]:
    """Black chips in the same row. A black chip on a dark table has no outline, so
    it is found from its white tabs: four or more on one ring of the right size.
    Glare on the table makes bright blobs too, but they do not sit on a ring."""
    near = _in_row(anchors, chip_width)
    points: List[Tuple[float, float]] = []
    _, parts = _components(tab_mask)
    for _, stat, c in parts:
        cx, cy = float(c[0]), float(c[1])
        if not _is_tab(stat, chip_width) or not near(cx, cy):
            continue
        if any(_inside(g.box, cx, cy, 0.05) for g in taken):
            continue
        points.append((cx, cy))

    row = float(np.mean([g.box[1] + g.box[3] / 2.0 for g in anchors]))
    sine = max(0.15, math.sin(math.radians(theta_at(row))))
    rings = _find_rings(points, _TAB_RING * chip_width / 2.0, sine, min_inliers=4)
    piles: List[List[Tuple[float, float, int]]] = []
    for cx, cy, inliers in rings:
        for pile in piles:
            if abs(pile[0][0] - cx) < 0.4 * chip_width and abs(pile[0][1] - cy) < 0.7 * chip_width:
                pile.append((cx, cy, inliers))
                break
        else:
            piles.append([(cx, cy, inliers)])

    found: List[_Group] = []
    radius = chip_width / 2.0
    for pile in piles:
        cx = float(np.mean([p[0] for p in pile]))
        cy = float(np.mean([p[1] for p in pile]))
        top_y = min(p[1] for p in pile) - radius * sine
        bottom_y = max(p[1] for p in pile) + radius * sine + 0.1 * chip_width
        found.append(_Group(
            "Black", (int(cx - radius), int(top_y), int(chip_width), int(bottom_y - top_y)), rings=len(pile),
        ))
    return found


def _inside(box: Tuple[int, int, int, int], x: float, y: float, margin: float) -> bool:
    bx, by, bw, bh = box
    return bx - margin * bw <= x <= bx + (1 + margin) * bw and by - margin * bh <= y <= by + (1 + margin) * bh


def _find_rings(
    points: List[Tuple[float, float]], radius: float, sine: float, min_inliers: int,
    scales: Sequence[float] = (0.9, 1.0, 1.1),
) -> List[Tuple[float, float, int]]:
    """Chips as rings of tabs. Seen at elevation θ a chip's ring of tabs is an
    ellipse `radius` wide and `radius * sine` tall; each ring found must carry
    enough tabs, spread round it rather than bunched. Returns (x, y, tab count)."""
    if len(points) < min_inliers:
        return []
    squash = 1.0 / sine
    flat = np.array([(x, y * squash) for x, y in points], dtype=float)   # the ring becomes a circle
    rings: List[Tuple[float, float, int]] = []
    remaining = set(range(len(flat)))
    for _ in range(6):
        best: Optional[Tuple[np.ndarray, List[int]]] = None
        for scale in scales:
            r = radius * scale
            for i, j in itertools.combinations(sorted(remaining), 2):
                p, q = flat[i], flat[j]
                chord = float(np.linalg.norm(q - p))
                if chord < 0.25 * r or chord > 2 * r:
                    continue
                mid = (p + q) / 2.0
                lift = math.sqrt(max(r * r - (chord / 2.0) ** 2, 0.0))
                normal = np.array([-(q - p)[1], (q - p)[0]]) / chord
                for sign in (1, -1):
                    centre = mid + sign * lift * normal
                    inliers = [k for k in remaining if abs(np.linalg.norm(flat[k] - centre) - r) < 0.13 * r]
                    if len(inliers) < min_inliers or not _spread_out(flat, inliers, centre):
                        continue
                    if best is None or len(inliers) > len(best[1]):
                        best = (centre, inliers)
        if best is None:
            break
        centre, inliers = best
        rings.append((float(centre[0]), float(centre[1] / squash), len(inliers)))
        remaining -= set(inliers)
    return rings


def _spread_out(flat: np.ndarray, indices: List[int], centre: np.ndarray, min_gap_deg: float = 40.0) -> bool:
    """Tabs on one chip are 60° apart; blobs closer in angle than that are not tabs."""
    angles = sorted(math.degrees(math.atan2(flat[k][1] - centre[1], flat[k][0] - centre[0])) % 360 for k in indices)
    gaps = [(angles[(i + 1) % len(angles)] - angles[i]) % 360 for i in range(len(angles))]
    return min(gaps) >= min_gap_deg


def _overlaps_any(box: Tuple[int, int, int, int], groups: List[_Group], share: float = 0.25) -> bool:
    """Whether the box lies mostly on top of one of the groups (`share` of the smaller one)."""
    x, y, w, h = box
    for g in groups:
        gx, gy, gw, gh = g.box
        ix = max(0, min(x + w, gx + gw) - max(x, gx))
        iy = max(0, min(y + h, gy + gh) - max(y, gy))
        if ix * iy > share * min(w * h, gw * gh):
            return True
    return False


# MARK: - Counting

# A stack this many chip walls tall (or more) is counted by its height; a smaller
# pile is counted from the rings of tabs showing on it.
_TALL_STACK = 4.0


def _count_group(group: _Group, theta_deg: float, known_pose: bool) -> Tuple[int, str]:
    sine, cosine = math.sin(math.radians(theta_deg)), math.cos(math.radians(theta_deg))
    box = _bounds(group.mask)
    if group.mask is None or box is None:
        # No silhouette to measure (a black chip on a dark table): the rings of tabs are all there is.
        return max(1, group.rings), "low"

    diameter = group.chip_width or float(box[2])
    wall = _THICKNESS_OVER_DIAMETER * diameter * cosine
    height = _central_height(group.mask)
    walls = (height - diameter * sine) / wall if wall > 0 else 0.0
    group.excess = walls
    if walls >= _TALL_STACK:
        return int(round(walls)), "low"

    rings = _find_rings(
        group.tabs_for_rings(), _TAB_RING * diameter / 2.0, max(0.15, sine), min_inliers=3, scales=(0.9, 1.0, 1.1),
    )
    return max(1, len(rings)), "low"


def _central_height(mask: np.ndarray) -> float:
    """How tall the silhouette is through its middle, where the stack is least
    spoiled by the curve of a rim."""
    ys, xs = np.nonzero(mask)
    left, right = int(xs.min()), int(xs.max())
    middle = (left + right) // 2
    reach = max(1, int(0.12 * (right - left)))
    heights = []
    for x in range(middle - reach, middle + reach + 1):
        column = np.nonzero(mask[:, x])[0]
        if len(column):
            heights.append(column.max() - column.min() + 1)
    return float(np.median(heights)) if heights else float(ys.max() - ys.min() + 1)

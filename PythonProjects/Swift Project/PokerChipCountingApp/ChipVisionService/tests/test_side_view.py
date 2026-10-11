"""
Tests for the side-view counter (app/side_view.py).

Two kinds of check, and they prove different things:

  * Drawn scenes. Piles are rendered with the same geometry the counter assumes
    (a chip is 0.0846 as thick as it is wide; seen at elevation θ its top is an
    ellipse sin θ as tall as it is wide). These catch regressions in the code
    path. They cannot show the counter is right about the real world, only that
    it agrees with its own model.
  * Real photos. Seven photos of one chip set, kept out of git, are read when they
    are present. The accuracy asserted is a floor set just below what was measured,
    not a promise.

Run with: python -m pytest tests/test_side_view.py
"""

import json
import math
import os

import cv2
import numpy as np
import pytest

from app.side_view import CameraPose, detect_stacks

PHOTOS = os.path.join(os.path.dirname(__file__), "..", "..", "PokerChipApp", "test_photos", "side_view")

_BODY_BGR = {"Red": (45, 45, 205), "Green": (110, 190, 95), "Blue": (200, 90, 30)}
_WALL_BGR = {"Red": (30, 30, 150), "Green": (70, 120, 60), "Blue": (140, 60, 20)}
_TABLE = (70, 70, 72)


def _draw_stack(image, cx, base_y, diameter, chips, color, pitch_deg, seed):
    """One upright stack seen from `pitch_deg` above the table, base centre at (cx, base_y)."""
    rng = np.random.default_rng(seed)
    a = diameter / 2.0
    sine, cosine = math.sin(math.radians(pitch_deg)), math.cos(math.radians(pitch_deg))
    b = a * sine
    wall = 0.0846 * diameter * cosine
    for k in range(chips):
        top = base_y - (k + 1) * wall
        cv2.ellipse(image, (int(cx), int(top + wall)), (int(a), max(1, int(b))), 0, 0, 360, _WALL_BGR[color], -1)
        cv2.rectangle(image, (int(cx - a), int(top)), (int(cx + a), int(top + wall)), _WALL_BGR[color], -1)
        cv2.ellipse(image, (int(cx), int(top)), (int(a), max(1, int(b))), 0, 0, 360, _BODY_BGR[color], -1)
        start = rng.uniform(15, 55)
        for step in range(3):                       # three tabs show on the front of every chip
            phi = math.radians(start + 60 * step)
            x = cx + a * 0.93 * math.cos(phi)
            y = top + b * math.sin(phi)
            half = 0.085 * diameter * max(0.4, math.sin(phi))
            cv2.rectangle(image, (int(x - half), int(y)), (int(x + half), int(y + wall)), (240, 240, 240), -1)
    top = base_y - chips * wall
    for step in range(3):                           # and three on the far half of the top face
        phi = math.radians(200 + 60 * step + rng.uniform(-10, 10))
        x = cx + a * 0.86 * math.cos(phi)
        y = top + b * 0.86 * math.sin(phi)
        half = 0.085 * diameter
        cv2.rectangle(image, (int(x - half), int(y - 0.03 * diameter)), (int(x + half), int(y + 0.03 * diameter)), (240, 240, 240), -1)


def _scene(piles, pitch_deg=12.0, diameter=150):
    # The piles stand near the middle row of the picture, where the camera's elevation is its pitch.
    image = np.full((720, 1280, 3), _TABLE, dtype=np.uint8)
    for index, (color, chips) in enumerate(piles):
        _draw_stack(image, 280 + 330 * index, 420, diameter, chips, color, pitch_deg, seed=index + 1)
    return image


def test_a_photo_with_no_chips_finds_nothing():
    counts, confidence, stacks = detect_stacks(np.full((600, 800, 3), _TABLE, np.uint8), CameraPose(20))
    assert stacks == []
    assert sum(counts.values()) == 0
    assert confidence == "low"


@pytest.mark.parametrize("piles", [
    [("Red", 8), ("Green", 12), ("Blue", 6)],
    [("Green", 20), ("Red", 5)],
])
def test_tall_stacks_drawn_to_the_models_own_geometry_are_counted_within_one_chip(piles):
    counts, _confidence, stacks = detect_stacks(_scene(piles), CameraPose(pitch_deg=12.0))
    assert [s.color for s in stacks] == [color for color, _ in piles]
    for stack, (_color, chips) in zip(stacks, piles):
        assert abs(stack.count - chips) <= 1, f"{stack.color}: counted {stack.count}, drawn {chips}"
    assert counts["Red"] + counts["Green"] + counts["Blue"] == sum(s.count for s in stacks)


def test_a_counted_stack_is_never_reported_with_high_confidence():
    _counts, confidence, stacks = detect_stacks(_scene([("Red", 8), ("Green", 10)]), CameraPose(pitch_deg=12.0))
    assert confidence != "high"
    assert all(s.confidence != "high" for s in stacks)


def test_without_a_pose_every_count_says_so():
    _counts, confidence, stacks = detect_stacks(_scene([("Red", 8), ("Green", 10)]))
    assert stacks and confidence == "low"
    assert all(s.confidence == "low" for s in stacks)


def test_boxes_are_fractions_of_the_photos_width_and_follow_the_camera_roll():
    level = _scene([("Red", 8), ("Green", 10)])
    roll = 12.0
    height, width = level.shape[:2]
    matrix = cv2.getRotationMatrix2D((width / 2.0, height / 2.0), -roll, 1.0)
    tilted = cv2.warpAffine(level, matrix, (width, height), borderValue=_TABLE)

    _c, _conf, flat = detect_stacks(level, CameraPose(12.0, 0.0))
    _c, _conf, rolled = detect_stacks(tilted, CameraPose(12.0, roll))
    assert len(flat) == len(rolled) == 2
    for a, b in zip(flat, rolled):
        # Where the pile was drawn, mapped into the tilted photo, in the same units.
        x, y = matrix @ np.array([a.x * width, a.y * width, 1.0])
        assert abs(b.x - x / width) < 0.03 and abs(b.y - y / width) < 0.03
        assert b.angle == pytest.approx(-roll, abs=0.1)
        assert 0 < b.w < 0.5 and 0 < b.h < 0.5


def test_a_pile_is_named_for_its_own_colour_whatever_colours_are_in_play():
    # The night's colours never rename a pile: what is not in play is left out by the app, not renamed here.
    scene = _scene([("Red", 6), ("Green", 6)])
    for in_play in (None, ["Red", "Green"], ["Blue", "Black"], ["White"]):
        _c, _conf, stacks = detect_stacks(scene, CameraPose(12.0), colors=in_play)
        assert [s.color for s in stacks] == ["Red", "Green"], in_play


# MARK: - Real photos

def _real_photos():
    path = os.path.join(PHOTOS, "labels.json")
    if not os.path.exists(path):
        return []
    with open(path) as handle:
        labels = json.load(handle)
    return [(name, info) for name, info in sorted(labels["photos"].items())], labels["expected"]


def _pose(gravity):
    gx, gy, gz = gravity
    return CameraPose(pitch_deg=math.degrees(math.asin(-gz)), roll_deg=math.degrees(math.atan2(gy, -gx)), focal_35mm=24.0)


@pytest.mark.skipif(not os.path.exists(os.path.join(PHOTOS, "labels.json")), reason="the sample photos are not in this checkout")
def test_real_photos_of_one_chip_set_find_the_piles_and_count_most_of_them():
    photos, expected = _real_photos()
    found = right = total = 0
    for name, info in photos:
        image = cv2.imread(os.path.join(PHOTOS, f"{name}.jpg"))
        # The white chip with blue tabs is White, whatever the night's colours: Blue is in play here and White
        # is not, which used to rename it.
        _counts, _confidence, stacks = detect_stacks(
            image, _pose(info["gravity"]), colors=["Blue", "Red", "Green", "Black"]
        )
        seen = {}
        for stack in stacks:
            seen.setdefault(stack.color, stack)
        for color, chips in expected.items():
            total += 1
            if color in seen:
                found += 1
                right += seen[color].count == chips
    # Measured when this was written: 26 of 28 piles found, 18 of 28 counted correctly.
    # Piles of one chip are reliable; a pair is counted right about half the time.
    assert found >= 24, f"found {found} of {total} piles"
    assert right >= 16, f"counted {right} of {total} piles correctly"

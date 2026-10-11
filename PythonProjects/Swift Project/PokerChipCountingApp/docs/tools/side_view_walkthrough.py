"""
Runs the real side-view counter (ChipVisionService/app/side_view.py) on stacks drawn with the same
geometry the counter assumes (the scene generator the tests use), and prints what it measures and
what it counts, so the worked examples in docs/HOW_IT_WORKS.md can be reproduced.

A drawn scene follows the counter's own model by construction. This shows that the arithmetic and
the code path work and how a wrong camera angle moves the answer; it says nothing about how tidy a
real stack is. It needs numpy, OpenCV and pytest, so run it with the backend's environment:

    cd ChipVisionService && python3 -m venv .venv && source .venv/bin/activate
    pip install -r requirements-dev.txt
    python ../docs/tools/side_view_walkthrough.py
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "ChipVisionService"))

import numpy as np

from app import side_view as sv
from tests.test_side_view import _TABLE, _draw_stack

CHIP_WIDTH = 150


def scene(piles, pitch):
    image = np.full((720, 1280, 3), _TABLE, dtype=np.uint8)
    for index, (color, chips) in enumerate(piles):
        _draw_stack(image, 280 + 330 * index, 420, CHIP_WIDTH, chips, color, pitch, seed=index + 1)
    return image


def measure(image, pitch):
    """What detect_stacks does for an upright picture, keeping the intermediate numbers."""
    pose = sv.CameraPose(pitch_deg=pitch)
    height, width = image.shape[:2]
    lab = sv._lab(image)
    groups = sv._find_groups(image, lab, lambda row: sv._elevation_at(row, pose, height, width))
    rows = []
    for group in groups:
        theta = sv._elevation(group, pose, height, width)
        count, _confidence = sv._count_group(group, theta, known_pose=True)
        rows.append({
            "colour": group.color, "count": count, "theta": theta, "walls": group.excess,
            "height": sv._central_height(group.mask) if group.mask is not None else float("nan"),
            "chip_width": group.chip_width,
        })
    return rows


print("1. One red stack of n chips, drawn at 12 degrees, camera pose given correctly")
print("   n drawn | height through the middle (px) | chip width (px) | walls = (height - width*sin)/wall | counted | by")
for n in (1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20):
    rows = measure(scene([("Red", n)], 12.0), 12.0)
    if not rows:
        print(f"   {n:>7} | (no pile found)")
        continue
    r = rows[0]
    by = "height" if r["walls"] >= sv._TALL_STACK else "rings of tabs"
    print(f"   {n:>7} | {r['height']:>30.1f} | {r['chip_width']:>15.1f} | {r['walls']:>34.2f} | {r['count']:>7} | {by}")

print()
print("2. The same stack of 8 red chips drawn at different elevations; the counter is told the true angle, then angles 5 degrees too low and too high")
print("   drawn at | told true | told -5 | told +5")
for pitch in (8.0, 12.0, 20.0, 30.0, 45.0):
    image = scene([("Red", 8)], pitch)
    cells = []
    for told in (pitch, pitch - 5, pitch + 5):
        rows = measure(image, max(told, 1.0))
        cells.append(f"{rows[0]['count']:>2}" if rows else " -")
    print(f"   {pitch:>6.0f}   |   {cells[0]}      |   {cells[1]}    |   {cells[2]}")

print()
print("3. Three colours at once, left to right (red 8, green 12, blue 6), drawn at 12 degrees")
for r in measure(scene([("Red", 8), ("Green", 12), ("Blue", 6)], 12.0), 12.0):
    print(f"   {r['colour']:<6} counted {r['count']:>2}   (walls {r['walls']:.2f}, elevation used {r['theta']:.1f} deg)")

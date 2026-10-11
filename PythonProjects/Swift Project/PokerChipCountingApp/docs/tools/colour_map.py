"""
Maps how the top-view counter (ChipVisionService/app/chip_detection.py) names a colour, by asking
its real `_nearest_color` function, so the decision regions quoted in docs/HOW_IT_WORKS.md can be
reproduced. It needs numpy and OpenCV, so run it with the backend's environment:

    cd ChipVisionService && python3 -m venv .venv && source .venv/bin/activate
    pip install -r requirements-dev.txt
    python ../docs/tools/colour_map.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "ChipVisionService"))

import numpy as np

from app.chip_detection import _REFERENCE_COLORS_HSV, _nearest_color

print("reference colours (OpenCV HSV: H 0-179, S 0-255, V 0-255):", _REFERENCE_COLORS_HSV)


def runs(s, v):
    out, prev, start = [], None, 0
    for h in range(180):
        c = _nearest_color(np.array([h, s, v]))
        if c != prev:
            if prev is not None:
                out.append((prev, start, h - 1))
            prev, start = c, h
    out.append((prev, start, 179))
    return out


print()
for s, v in [(200, 200), (255, 255), (120, 200), (80, 200)]:
    print(f"hue runs at S={s}, V={v}:", ", ".join(f"{c} {a}-{b}" for c, a, b in runs(s, v)))

print()
print("grey axis (S=0, hue irrelevant): from this brightness V the pixel reads as...")
last = None
for v in range(0, 256):
    c = _nearest_color(np.array([0, 0, v]))
    if c != last:
        print(f"   V={v}: {c}")
        last = c

print()
print("how much saturation turns a bright pixel (V=220) from White into a colour, by hue")
for h, name in [(0, "red"), (60, "green"), (110, "blue"), (20, "orange"), (30, "yellow"), (140, "violet"), (160, "pink")]:
    first = next((s for s in range(0, 256) if _nearest_color(np.array([h, s, 220])) != "White"), None)
    col = _nearest_color(np.array([h, 255, 220]))
    print(f"   hue {h:>3} ({name:<6}): stops being White at S>={first}, then reads as {col}")

print()
print("some pixels:")
for px, note in [((5, 210, 190), "red chip face"), ((172, 210, 190), "red chip, hue wrapped"), ((105, 180, 170), "blue chip in shade"),
                 ((62, 150, 150), "green chip, pastel"), ((20, 200, 200), "orange"), ((28, 200, 200), "yellow"), ((150, 120, 150), "purple"),
                 ((0, 10, 230), "white chip, lit"), ((110, 25, 215), "white chip with a blue cast"), ((0, 0, 100), "mid grey"), ((0, 0, 125), "light grey"),
                 ((0, 5, 25), "black chip"), ((0, 0, 60), "shadowed table")]:
    print(f"   {px} {note:<28} -> {_nearest_color(np.array(px))}")

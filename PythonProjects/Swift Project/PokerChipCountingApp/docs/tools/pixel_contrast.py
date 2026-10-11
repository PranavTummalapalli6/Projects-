"""Measure the contrast of audit-flagged text from the rendered screenshot.

For each 'Contrast failed' finding: crop the element's frame from the stop's
screenshot; background = the most common colour in the crop; foreground = the
pixel whose luminance differs most from it (anti-aliased text reaches its true
colour at stroke centres). Ratio is WCAG relative luminance. This is an
independent check of the audit and of docs/DESIGN.md's token arithmetic.
"""
import re, sys, collections
import cv2, numpy as np

audit_path, shots_dir = sys.argv[1], sys.argv[2]

def lin(c):
    c = c / 255.0
    return np.where(c <= 0.03928, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def lum(rgb):
    r, g, b = lin(np.array(rgb[0])), lin(np.array(rgb[1])), lin(np.array(rgb[2]))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def ratio(a, b):
    la, lb = float(lum(a)), float(lum(b))
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

rows = []
for line in open(audit_path, encoding="utf-8").read().split("\n"):
    m = re.match(r"\[([^\]]+)\] .*? — Contrast failed — Attributes: (\w+), 0x[0-9a-f]+, \{\{([\d.]+), ([\d.]+)\}, \{([\d.]+), ([\d.]+)\}\}.*?(?:label: '([^']*)')?", line)
    if not m:
        continue
    stop, kind, x, y, w, h = m.group(1), m.group(2), *map(float, m.groups()[2:6])
    label = re.search(r"label: '([^']*)'", line)
    label = label.group(1) if label else ""
    img = cv2.imread(f"{shots_dir}/{stop}.png")
    if img is None:
        continue
    scale = img.shape[1] / 393.0
    x0, y0, x1, y1 = [int(round(v * scale)) for v in (x, y, x + w, y + h)]
    crop = img[max(0, y0):max(0, y1), max(0, x0):max(0, x1)]
    if crop.size == 0:
        continue
    rgb = crop[:, :, ::-1].reshape(-1, 3)
    # most common colour (quantised) = background
    q = (rgb // 6) * 6
    keys, counts = np.unique(q, axis=0, return_counts=True)
    bg = keys[counts.argmax()] + 3
    d = np.abs(lum(rgb.T) - float(lum(bg)))
    fg = rgb[d.argmax()]
    rows.append((stop, kind, label[:44], ratio(fg, bg)))

fails = [r for r in rows if r[3] < 4.5]
print(f"flagged elements measured: {len(rows)}")
print(f"  measured >= 4.5:1 (audit false positive): {len(rows) - len(fails)}")
print(f"  measured <  4.5:1: {len(fails)}")
print()
for stop, kind, label, r in sorted(fails, key=lambda t: t[3]):
    print(f"{r:5.2f}  [{stop}] {kind}: '{label}'")

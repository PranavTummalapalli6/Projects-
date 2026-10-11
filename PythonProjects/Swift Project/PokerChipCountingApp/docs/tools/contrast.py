"""WCAG 2.x contrast ratios for the app's real colours.

Text is drawn over (a) the backdrop gradient's two stops, (b) a card
(white 6% over the backdrop) and (c) a raised surface / text field (white 10%).
The worst case for light text is the *lightest* background, so every ratio is
computed against the gradient's lighter top stop plus the lightest overlay.
"""
def lin(c):
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

def lum(rgb):
    r, g, b = (lin(x) for x in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def over(fg, alpha, bg):
    return tuple(alpha * f + (1 - alpha) * b for f, b in zip(fg, bg))

def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

WHITE = (1, 1, 1)
TOP = (0.10, 0.07, 0.15)
BOTTOM = (0.02, 0.015, 0.035)
GOLD = (0.85, 0.68, 0.32)
GOLD_LIGHT = (0.96, 0.84, 0.56)
PURPLE = (0.46, 0.32, 0.70)
PURPLE_LIGHT = (0.72, 0.62, 0.92)
POS = (0.30, 0.80, 0.52)
NEG = (0.97, 0.45, 0.45)
WARN = (0.98, 0.72, 0.30)
BLACK = (0, 0, 0)

surfaces = {
    "backdrop top": TOP,
    "backdrop bottom": BOTTOM,
    "card on top": over(WHITE, 0.06, TOP),
    "raised / text field on top": over(WHITE, 0.10, TOP),
    "banner (tint 14%) on card": None,   # computed per tint below
}

print("== text levels (white at alpha) on each surface ==")
for name, alpha in [("primary 0.95", 0.95), ("secondary 0.72", 0.72), ("tertiary 0.58", 0.58),
                    ("old tertiary 0.55", 0.55), ("old caption 0.40", 0.40), ("old caption 0.45", 0.45)]:
    row = []
    for sname, s in surfaces.items():
        if s is None: continue
        row.append(f"{sname}: {ratio(over(WHITE, alpha, s), s):5.2f}")
    print(f"{name:<18}", " | ".join(row))

print("\n== accent and meaning colours on the lightest surfaces ==")
light = over(WHITE, 0.10, TOP)
card = over(WHITE, 0.06, TOP)
for name, c in [("gold", GOLD), ("gold light", GOLD_LIGHT), ("purple light", PURPLE_LIGHT),
                ("positive", POS), ("negative", NEG), ("warning", WARN), ("purple (decorative)", PURPLE)]:
    print(f"{name:<20} on backdrop top {ratio(c, TOP):5.2f} | on card {ratio(c, card):5.2f} | on raised {ratio(c, light):5.2f}")

print("\n== banners: tint text colour on tint(14%) over card ==")
for name, c in [("info (purple light)", PURPLE_LIGHT), ("success", POS), ("warning", WARN), ("error", NEG)]:
    bg = over(c, 0.14, card)
    print(f"{name:<20} tinted text {ratio(c, bg):5.2f} | primary white .95 text {ratio(over(WHITE, .95, bg), bg):5.2f}")

print("\n== buttons ==")
print(f"primary: black on gold light {ratio(BLACK, GOLD_LIGHT):5.2f}, on gold {ratio(BLACK, GOLD):5.2f}")
sec_bg = over(WHITE, 0.05, TOP)
print(f"secondary: purple light on its fill {ratio(PURPLE_LIGHT, sec_bg):5.2f}")
dest_bg = over(NEG, 0.10, TOP)
print(f"destructive: negative on its fill {ratio(NEG, dest_bg):5.2f}")
print(f"quiet: gold light on backdrop {ratio(GOLD_LIGHT, TOP):5.2f}")
print(f"selected quick-pick: black on gold {ratio(BLACK, GOLD):5.2f}; unselected gold light on gold 12% {ratio(GOLD_LIGHT, over(GOLD, .12, TOP)):5.2f}")

print("\n== non-text: chip fills vs backdrop (3:1 wanted for graphics) ==")
chips = {"White": (0.93, 0.93, 0.90), "Red": (0.80, 0.14, 0.17), "Blue": (0.13, 0.36, 0.80),
         "Green": (0.09, 0.55, 0.31), "Black": (0.10, 0.10, 0.11)}
for name, c in chips.items():
    print(f"{name:<6} vs backdrop top {ratio(c, TOP):5.2f} (outline: white 28% stroke adds an edge)")

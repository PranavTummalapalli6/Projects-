"""
The side-view geometry of docs/HOW_IT_WORKS.md as tables, computed with the same formulas
ChipVisionService/app/side_view.py uses (a chip is 0.0846 as thick as it is wide; seen at elevation
theta its top face is sin(theta) as deep as it is wide and its side wall cos(theta) as tall as it is
thick). Plain Python, no dependencies:

    python3 docs/tools/geometry_tables.py
"""
import math

K = 0.0846  # chip thickness / diameter (3.3 mm / 39 mm)
print("K =", K, " check 3.3/39 =", round(3.3 / 39, 4))

def wall(D, th):  return K * D * math.cos(math.radians(th))
def face(D, th):  return D * math.sin(math.radians(th))
def height(n, D, th): return n * wall(D, th) + face(D, th)
def count_from_height(H, D, th): return (H - face(D, th)) / wall(D, th)

D = 150.0
print("\n1. What one chip looks like from elevation theta (chip 150 px wide)")
print("theta  sin(theta)  top face (px tall)   cos(theta)  side wall (px tall)")
for th in (5, 10, 15, 20, 30, 45, 60, 90):
    print(f"{th:>4}   {math.sin(math.radians(th)):.3f}       {face(D, th):6.1f}              {math.cos(math.radians(th)):.3f}      {wall(D, th):6.2f}")

print("\n2. Silhouette height H(n) = n*wall + face, chip 150 px wide")
print("theta   n=1     n=3     n=5     n=10    n=20")
for th in (12, 20, 30):
    print(f"{th:>4}  " + "  ".join(f"{height(n, D, th):6.1f}" for n in (1, 3, 5, 10, 20)))

print("\n3. Elevation by image row (pitch 20, 24 mm lens, 1280 px wide picture, so focal = 24*1280/36 px)")
f = 24 * 1280 / 36
print("focal px =", round(f, 1))
print("row offset from centre (px) -> elevation")
for off in (-480, -300, -150, 0, 150, 300, 480):
    th = min(max(20 + math.degrees(math.atan(off / f)), 4.0), 80.0)
    print(f"   {off:>5} -> {th:5.1f} deg")

print("\n4. If the angle used is wrong by delta, a stack of n chips (true elevation theta0) is counted as...")
print("   (chip 150 px, height measured exactly)")
print("theta0  n    delta=-5  -2     0     +2    +5   +10")
for th0 in (15, 25):
    for n in (4, 10, 20):
        H = height(n, D, th0)
        row = [count_from_height(H, D, th0 + dl) for dl in (-5, -2, 0, 2, 5, 10)]
        print(f"{th0:>4}   {n:>3}  " + "  ".join(f"{x:5.1f}" for x in row))

print("\n5. If the chip's width in the picture is off by eps (D_est = D*(1+eps)), a stack of n chips (theta 20) is counted as...")
print("n    eps=-10%  -5%     0     +5%   +10%")
th0 = 20
for n in (4, 10, 20):
    H = height(n, D, th0)
    row = [count_from_height(H, D * (1 + e), th0) for e in (-0.10, -0.05, 0, 0.05, 0.10)]
    print(f"{n:>3}  " + "  ".join(f"{x:6.1f}" for x in row))

print("\n6. Focal length conversion: the code uses f_px = f35 * width / 36")
for name, (w, h) in {"landscape 4032x3024": (4032, 3024), "portrait 3024x4032": (3024, 4032)}.items():
    diag = math.hypot(w, h)
    f_code = 24 * w / 36
    f_diag = 24 * diag / 43.27
    half_v = h / 2
    print(f"   {name}: code f = {f_code:7.1f} px, diagonal-based f = {f_diag:7.1f} px, ratio {f_code / f_diag:.2f};"
          f" angle at the top/bottom edge: code {math.degrees(math.atan(half_v / f_code)):.1f} deg vs {math.degrees(math.atan(half_v / f_diag)):.1f} deg")

print("\n7. Flattening a ring of tabs: tab ring radius = 0.86 * D/2; seen at theta it is an ellipse radius R wide, R*sin(theta) tall")
for th in (10, 20, 30):
    R = 0.86 * D / 2
    print(f"   theta {th}: ring {2*R:5.1f} px wide x {2*R*math.sin(math.radians(th)):5.1f} px tall (black-chip code floors sin(theta) at 0.15)")

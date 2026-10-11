"""
An independent replica of DenominationEngine.swift's multi-colour search (no inventory limits, no
locked values), written by reading the Swift code. It exists to check that the account of the search
in docs/HOW_IT_WORKS.md is what the solver really does: it prints the replica's answer for a set of
inputs, and those answers match the compiled Swift solver's (docs/tools/solver_demo) on every input
listed here. It also prints, for the first example, the best candidate at each count scale.

    python3 docs/tools/solver_replica.py

The single-colour case and the planner layer (inventory, printed values, options) are not replicated.
"""
import math
import sys

ALL = ["White", "Red", "Blue", "Green", "Black"]
MULT = {"White": 0.3, "Red": 0.6, "Blue": 1.1, "Green": 2.0, "Black": 4.0}


def rnd(x):  # Swift's .rounded(): to nearest, ties away from zero
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def nice_nickel(raw):
    return max(5, int(rnd(raw / 5)) * 5)


def clean_near(raw):
    raw = max(raw, 5)
    if raw <= 17.5:
        return min([5, 10], key=lambda v: abs(v - raw))
    return max(25, int(rnd(raw / 25)) * 25)


def next_clean(v):
    if v < 10:
        return 10
    if v < 25:
        return 25
    return v + 25


def ladder(cap):
    if cap < 5:
        return []
    out = [5]
    if cap >= 10:
        out.append(10)
    v = 25
    while v <= cap:
        out.append(v)
        v += 25
    return out


def target_total(players):
    p = min(max(players, 2), 10)
    t = (p - 2) / 8
    return int(rnd(30 - 10 * t))


def weight(rank, decay=0.55):
    return math.exp(-decay * rank)


def assign_values(present, avg):
    values, prev = {}, 0
    for c in present:
        v = clean_near(avg * MULT[c])
        while v <= prev:
            v = next_clean(v)
        values[c] = v
        prev = v
    return values


def nickel_divisors(value, cap):
    fifths = value // 5
    if fifths <= 0:
        return []
    found, d = set(), 1
    while d * d <= fifths:
        if fifths % d == 0:
            found.add(d)
            found.add(fifths // d)
        d += 1
    return sorted(x * 5 for x in found if x * 5 <= cap)


def solve_multi(buy, players, present, verbose=False):
    target = target_total(players)
    avg = buy / target
    r1, r2, higher = present[0], present[1], present[2:]
    base = assign_values(present, avg)
    natural_v2 = base[r2]
    v2ceil = base[higher[0]] if higher else 10 ** 18
    v2c, b = [natural_v2], natural_v2
    for _ in range(4):
        b = next_clean(b)
        if b >= v2ceil:
            break
        v2c.append(b)
    allw = [weight(i) for i in range(len(present))]
    base_unit = target / sum(allw)
    state = {"best": None, "n": 0}
    per_scale = {}

    def higher_counts(scale):
        if not higher:
            return {}, 0, 0, True
        unit = base_unit * scale
        counts, prev, strict = {}, 10 ** 9, True
        for idx, c in enumerate(higher):
            count = max(1, int(rnd(allw[idx + 2] * unit)))
            if count >= prev:
                count = max(1, prev - 1)
                if count >= prev:
                    strict = False
            counts[c] = count
            prev = count
        return counts, sum(counts.values()), sum(counts[c] * base[c] for c in higher), strict

    def consider(cand):
        state["n"] += 1
        key = cand["scale"]
        cur = per_scale.get(key)
        if cur is None or better(cand, cur):
            per_scale[key] = cand
        best = state["best"]
        if best is None or better(cand, best):
            state["best"] = cand

    def better(a, b):
        if a["shape"] != b["shape"]:
            return a["shape"]
        if a["inrange"] != b["inrange"]:
            return a["inrange"]
        return a["score"] < b["score"]

    def search(v2, scales, v1fn):
        for sc in scales:
            counts, known, hv, hstrict = higher_counts(sc)
            first_h = counts[higher[0]] if higher else 0
            leftover = buy - hv
            if leftover <= 0:
                continue
            c2max = min(40, leftover // v2)
            if c2max < 1:
                continue
            for c2 in range(1, c2max + 1):
                rem = leftover - c2 * v2
                if rem <= 0:
                    continue
                for v1 in v1fn(rem, v2 - 5):
                    c1 = rem // v1
                    if c1 < 1:
                        continue
                    total = c1 + c2 + known
                    inr = 20 <= total <= 30
                    shape = hstrict and c1 > c2 and (first_h == 0 or c2 > first_h)
                    rp = 0 if inr else min(abs(total - 20), abs(total - 30))
                    score = rp * 10 + 0.05 * abs(total - target) + 0.02 * abs(math.log(v2) - math.log(natural_v2))
                    consider(dict(score=score, shape=shape, inrange=inr, v1=v1, v2=v2, c1=c1, c2=c2,
                                  counts=counts, scale=sc, total=total))

    def ladder_div(rem, cap):
        return [d for d in ladder(min(rem, cap)) if rem % d == 0]

    def loose_div(rem, cap):
        return nickel_divisors(rem, min(rem, cap))

    def settled():
        b = state["best"]
        return b is not None and b["shape"] and b["inrange"]

    scales = [0.6, 0.75, 0.9, 1.0, 1.1, 1.25, 1.4]
    thin = [0.45, 0.3, 0.2, 0.12, 0.06]
    tier = 1
    for v2 in v2c:
        if settled():
            break
        search(v2, scales, ladder_div)
    if not settled():
        tier = 2
        for v2 in v2c:
            if settled():
                break
            search(v2, scales, loose_div)
    if state["best"] is None or not state["best"]["shape"]:
        tier = 3
        for v2 in v2c:
            if state["best"] is not None and state["best"]["shape"]:
                break
            search(v2, thin, ladder_div)
            if state["best"] is None or not state["best"]["shape"]:
                search(v2, thin, loose_div)
    best = state["best"]
    if best is None or not best["shape"]:
        return None
    counts = dict(best["counts"])
    counts[r1], counts[r2] = best["c1"], best["c2"]
    values = {c: base[c] for c in higher}
    values[r1], values[r2] = best["v1"], best["v2"]
    info = dict(target=target, avg=avg, base=base, base_unit=base_unit, weights=allw, tier=tier,
                considered=state["n"], per_scale=per_scale, natural_v2=natural_v2, v2_candidates=v2c)
    return counts, values, info


def show(label, buy_dollars, players, colors, verbose=False):
    present = [c for c in ALL if c in colors]
    buy = nice_nickel(buy_dollars * 100)
    if len(present) == 1:
        print(f"## {label}: (single colour: not covered by this replica)")
        return
    res = solve_multi(buy, players, present, verbose)
    print(f"## {label}: buy-in {buy / 100:g}, {players} players, {'/'.join(present)}")
    if res is None:
        print("   -> no stack (too small)")
        return
    counts, values, info = res
    total_c = total_v = 0
    for c in present:
        print(f"   {c:<6} {counts[c]:<3} x {values[c] / 100:g}")
        total_c += counts[c]
        total_v += counts[c] * values[c]
    print(f"   chips {total_c}, worth {total_v / 100:g}   [tier {info['tier']}, considered {info['considered']} candidates]")
    if verbose:
        print(f"   target {info['target']} chips, average chip {info['avg']:.1f}c, weights {[round(w, 3) for w in info['weights']]}, base unit {info['base_unit']:.2f}")
        print(f"   natural values {info['base']}, rank-2 candidates {info['v2_candidates']}")
        for sc in sorted(info['per_scale']):
            p = info['per_scale'][sc]
            allc = dict(p['counts'])
            print(f"   scale {sc:<5} best: v1={p['v1']} x{p['c1']}, v2={p['v2']} x{p['c2']}, higher={allc}, total {p['total']}, shape={p['shape']}, in-range={p['inrange']}, score={p['score']:.3f}")


if __name__ == "__main__":
    show("A", 25, 6, ALL, verbose=True)
    show("B", 20, 4, ["White", "Red", "Blue"], verbose=True)
    show("C", 50, 8, ALL, verbose=True)
    show("D", 100, 10, ALL)
    show("E", 10, 2, ["White", "Red"])
    show("F", 20, 5, ["White", "Red", "Blue", "Green"])
    show("G-nickel", 25.03, 6, ["White", "Red", "Blue"])
    show("H-odd cents", 19.95, 6, ALL)
    show("I-tiny", 1.35, 6, ["White", "Green", "Black"])
    show("J-floor5", 3.15, 6, ALL)
    show("K-below floor", 3.10, 6, ALL)
    for p in [2, 4, 6, 8, 10]:
        show(f"P{p}", 50, p, ALL)
    print("target totals by players:", {p: target_total(p) for p in range(2, 11)})

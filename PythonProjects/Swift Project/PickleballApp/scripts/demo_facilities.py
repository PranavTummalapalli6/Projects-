"""Single source for fictional demo facilities.

Writes:
  PickleballApp/Resources/DemoFacilities.json  (bundled; drives the app's offline demo mode)
  supabase/seed.sql                            (local `supabase db reset` seed via import_facility)

All names are fictional. Run: python3 scripts/demo_facilities.py
"""
import json, pathlib, uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
NS = uuid.UUID("6f1c2d3e-4b5a-4c6d-8e7f-9a0b1c2d3e4f")

PARK = [{"day_of_week": d, "opens": "07:00", "closes": "22:00"} for d in range(7)]
INDOOR = [{"day_of_week": d, "opens": "06:00", "closes": "23:00"} for d in range(7)]
SCHOOL = [{"day_of_week": d, "opens": "16:00", "closes": "21:00"} for d in range(1, 6)] + \
         [{"day_of_week": d, "opens": "08:00", "closes": "21:00"} for d in (0, 6)]

def f(key, name, lat, lng, city, state, tz, courts, pb, court_type, io, lights, play, access, cost,
      hours=PARK, notes=None, price=None, reservable=None, skill=None, culture=(), game=None, **amen):
    return {
        "id": str(uuid.uuid5(NS, key)), "name": name, "latitude": lat, "longitude": lng,
        "city": city, "state": state, "time_zone": tz,
        "total_physical_courts": courts, "default_pickleball_courts": pb,
        "court_type": court_type, "indoor_outdoor": io, "has_lights": lights,
        "has_restrooms": amen.get("restrooms", True), "has_water": amen.get("water", True),
        "has_parking": amen.get("parking", True),
        "play_system": play, "typical_game_minutes": game, "source": "demo",
        "existence_status": amen.get("status", "verified"), "existence_confidence": amen.get("conf", 0.9),
        "access": {"access_type": access, "access_notes": notes, "reservation_available": reservable,
                   "reservation_required": amen.get("res_required"),
                   "verification_status": "verified", "confidence": 0.8},
        "cost": {"cost_type": cost, "day_pass_price": price},
        "hours": hours,
        "skill": None if not skill else {"bands": [{"band": b, "weight": w} for b, w in skill],
                                         "observation_count": int(sum(w for _, w in skill)), "newest_days_ago": 4},
        "culture": [{"tag": t, "share": s, "observation_count": 8} for t, s in culture],
    }

VA, CA = "America/New_York", "America/Los_Angeles"
FACILITIES = [
    f("laurel-creek", "Laurel Creek Park", 38.8462, -77.3064, "Fairfax", "VA", VA, 6, 4, "pickleball_lined_tennis", "outdoor", True,
      "paddle_stack", "public_walk_on", "free", game=13,
      skill=[("3.0-3.5", 10), ("3.5-4.0", 12), ("4.0-4.5", 5)], culture=[("open_play", .8), ("mostly_doubles", .7)]),
    f("dinkhouse", "Dinkhouse Indoor Club", 38.8601, -77.2742, "Fairfax", "VA", VA, 8, 8, "dedicated_pickleball", "indoor", True,
      "reservation_only", "day_pass_available", "day_pass", hours=INDOOR, price=15, reservable=True,
      notes="$15 day pass; reserve a court in their app", skill=[("3.5-4.0", 9), ("4.0-4.5", 9), ("4.5+", 3)],
      culture=[("competitive", .5)]),
    f("oak-hollow", "Oak Hollow Community Courts", 38.8303, -77.3290, "Fairfax", "VA", VA, 4, 4, "dedicated_pickleball", "outdoor", True,
      "stay_until_finished", "public_walk_on", "free",
      skill=[("beginner", 6), ("2.5-3.0", 9), ("3.0-3.5", 6)], culture=[("beginner_friendly", .7), ("casual", .6)]),
    f("ridgeview-hoa", "Ridgeview HOA Courts", 38.8689, -77.3215, "Fairfax", "VA", VA, 2, 2, "pickleball_lined_tennis", "outdoor", False,
      "stay_until_finished", "resident_guest_allowed", "membership", notes="Residents and accompanied guests only"),
    f("mason-ridge", "Mason Ridge Recreation Center", 38.8389, -77.2867, "Fairfax", "VA", VA, 6, 6, "multi_use", "indoor", True,
      "organized_open_play", "day_pass_available", "day_pass", hours=INDOOR, price=8, game=12,
      notes="$8 recreation center day pass", skill=[("2.5-3.0", 5), ("3.0-3.5", 8), ("3.5-4.0", 4)],
      culture=[("open_play", .9), ("mixed", .6)]),
    f("willow-pond", "Willow Pond Park", 38.8792, -77.3011, "Fairfax", "VA", VA, 4, 4, "convertible_tennis", "outdoor", False,
      "stay_until_finished", "public_walk_on", "free", skill=[("3.0-3.5", 3), ("3.5-4.0", 2)]),
    f("cedar-run", "Cedar Run Pickleball Complex", 38.8211, -77.2650, "Fairfax", "VA", VA, 10, 10, "dedicated_pickleball", "outdoor", True,
      "paddle_stack", "public_walk_on", "free", game=14,
      skill=[("3.5-4.0", 6), ("4.0-4.5", 12), ("4.5+", 8)], culture=[("competitive", .7), ("challenge_court", .5)]),
    f("pine-hill-es", "Pine Hill Elementary Courts", 38.8550, -77.3400, "Fairfax", "VA", VA, 2, 2, "multi_use", "outdoor", False,
      "stay_until_finished", "school_restricted", "free", hours=SCHOOL, notes="Public after school hours and weekends"),
    f("hunters-mill", "Hunters Mill Racquet Club", 38.8920, -77.2930, "Vienna", "VA", VA, 12, 6, "mixed_facility", "both", True,
      "reservation_only", "membership_required", "membership", hours=INDOOR, notes="Members only",
      skill=[("3.5-4.0", 5), ("4.0-4.5", 5)]),
    f("fox-glen", "Fox Glen Neighborhood Courts", 38.8660, -77.2600, "Fairfax", "VA", VA, 2, 2, "pickleball_lined_tennis", "outdoor", False,
      "unknown", "public_walk_on", "free", status="community_reported", conf=0.3),

    f("memorial-grove", "Memorial Grove Park", 37.3230, -122.0420, "Cupertino", "CA", CA, 8, 6, "pickleball_lined_tennis", "outdoor", True,
      "paddle_stack", "public_walk_on", "free", game=13,
      skill=[("3.0-3.5", 9), ("3.5-4.0", 11), ("4.0-4.5", 4)], culture=[("open_play", .8), ("mostly_doubles", .8)]),
    f("stevens-creek", "Stevens Creek Indoor Pickleball", 37.3236, -122.0130, "Cupertino", "CA", CA, 10, 10, "dedicated_pickleball", "indoor", True,
      "reservation_only", "day_pass_available", "day_pass", hours=INDOOR, price=18, reservable=True, notes="$18 day pass",
      skill=[("3.5-4.0", 8), ("4.0-4.5", 8), ("4.5+", 4)], culture=[("competitive", .5)]),
    f("linda-vista", "Linda Vista Courts", 37.3115, -122.0570, "Cupertino", "CA", CA, 4, 4, "dedicated_pickleball", "outdoor", True,
      "stay_until_finished", "public_walk_on", "free",
      skill=[("beginner", 5), ("2.5-3.0", 8), ("3.0-3.5", 5)], culture=[("beginner_friendly", .8), ("casual", .6)]),
    f("orchard-hoa", "Orchard Glen HOA Courts", 37.3390, -122.0300, "Cupertino", "CA", CA, 2, 2, "pickleball_lined_tennis", "outdoor", False,
      "stay_until_finished", "hoa", "membership", notes="HOA residents only"),
    f("de-anza-rec", "De Anza Recreation Courts", 37.3195, -122.0450, "Cupertino", "CA", CA, 6, 4, "multi_use", "outdoor", True,
      "organized_open_play", "public_reservation", "reservation_fee", price=6, reservable=True, res_required=False,
      notes="Walk-on when free; $6 reservations after 5 PM", skill=[("3.0-3.5", 6), ("3.5-4.0", 5)], culture=[("open_play", .7)]),
    f("apple-tree", "Appletree Park", 37.3460, -122.0050, "Sunnyvale", "CA", CA, 4, 4, "convertible_tennis", "outdoor", False,
      "stay_until_finished", "public_walk_on", "free"),
]

def sql_str(v):
    return "null" if v is None else "'" + str(v).replace("'", "''") + "'"

def seed_sql():
    out = ["-- Generated by scripts/demo_facilities.py — fictional demo facilities for local development.",
           "set search_path = public, extensions;", ""]
    for x in FACILITIES:
        attrs = {"courts": x["total_physical_courts"], "pickleball_courts": x["default_pickleball_courts"],
                 "court_type": x["court_type"], "indoor_outdoor": x["indoor_outdoor"], "lit": x["has_lights"],
                 "play_system": x["play_system"], "city": x["city"], "state": x["state"], "time_zone": x["time_zone"],
                 "access_type": x["access"]["access_type"], "access_notes": x["access"]["access_notes"],
                 "reservation_available": x["access"]["reservation_available"],
                 "cost_type": x["cost"]["cost_type"], "day_pass_price": x["cost"]["day_pass_price"],
                 "existence_status": x["existence_status"], "existence_confidence": x["existence_confidence"]}
        attrs = {k: v for k, v in attrs.items() if v is not None}
        out.append(f"select public.import_facility('demo', {sql_str(x['id'])}, {sql_str(x['name'])}, "
                   f"{x['latitude']}, {x['longitude']}, {sql_str(json.dumps(attrs))}::jsonb);")
    out.append("")
    for x in FACILITIES:
        fid = f"(select facility_id from public.facility_sources where source = 'demo' and external_id = {sql_str(x['id'])})"
        for h in x["hours"]:
            out.append(f"insert into public.facility_hours (facility_id, day_of_week, opens, closes) values "
                       f"({fid}, {h['day_of_week']}, '{h['opens']}', '{h['closes']}');")
        if x["skill"]:
            for b in x["skill"]["bands"]:
                out.append(f"insert into public.skill_observations (facility_id, band, trust_weight) "
                           f"select {fid}, '{b['band']}', 0.8 from generate_series(1, {int(b['weight'])});")
        for c in x["culture"]:
            n = round(c["share"] * 10)
            out.append(f"insert into public.play_culture_observations (facility_id, tag, trust_weight) "
                       f"select {fid}, '{c['tag']}', 0.8 from generate_series(1, {n});")
        if x["typical_game_minutes"]:
            out.append(f"update public.facilities set typical_game_minutes = {x['typical_game_minutes']} where id = {fid};")
    return "\n".join(out) + "\n"

(ROOT / "PickleballApp/Resources/DemoFacilities.json").write_text(json.dumps(FACILITIES, indent=1))
(ROOT / "supabase/seed.sql").write_text(seed_sql())
print(f"wrote {len(FACILITIES)} facilities")

// Pure OSM → facility normalization (unit-tested in normalize_test.ts).

export type OsmElement = {
  type: "node" | "way" | "relation";
  id: number;
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
};

export type Candidate = { externalId: string; name: string; lat: number; lng: number; attrs: Record<string, unknown> };

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

export function geohash(lat: number, lng: number, precision = 4): string {
  let latR = [-90, 90], lngR = [-180, 180], hash = "", bit = 0, ch = 0, even = true;
  while (hash.length < precision) {
    const r = even ? lngR : latR, v = even ? lng : lat, mid = (r[0] + r[1]) / 2;
    if (v >= mid) { ch |= 1 << (4 - bit); r[0] = mid; } else { r[1] = mid; }
    even = !even;
    if (bit < 4) bit++; else { hash += BASE32[ch]; bit = 0; ch = 0; }
  }
  return hash;
}

export function geohashBounds(hash: string): { s: number; w: number; n: number; e: number } {
  let latR = [-90, 90], lngR = [-180, 180], even = true;
  for (const c of hash) {
    const idx = BASE32.indexOf(c);
    for (let b = 4; b >= 0; b--) {
      const r = even ? lngR : latR, mid = (r[0] + r[1]) / 2;
      if ((idx >> b) & 1) r[0] = mid; else r[1] = mid;
      even = !even;
    }
  }
  return { s: latR[0], w: lngR[0], n: latR[1], e: lngR[1] };
}

function distanceMeters(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6371008.8, toRad = Math.PI / 180;
  const dLat = (bLat - aLat) * toRad, dLng = (bLng - aLng) * toRad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(aLat * toRad) * Math.cos(bLat * toRad) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

/// OSM often maps every court as its own pitch. Group pitches within 80 m into one facility.
export function normalize(elements: OsmElement[]): Candidate[] {
  const points = elements
    .map((e) => ({ e, lat: e.lat ?? e.center?.lat, lng: e.lon ?? e.center?.lon, tags: e.tags ?? {} }))
    .filter((p): p is { e: OsmElement; lat: number; lng: number; tags: Record<string, string> } =>
      typeof p.lat === "number" && typeof p.lng === "number");
  const clusters: (typeof points)[] = [];
  for (const p of points) {
    const c = clusters.find((c) => c.some((q) => distanceMeters(p.lat, p.lng, q.lat, q.lng) <= 80));
    if (c) c.push(p); else clusters.push([p]);
  }
  return clusters.map((c) => {
    const named = c.find((p) => p.tags.name);
    const tags = Object.assign({}, ...c.map((p) => p.tags)) as Record<string, string>;
    const sports = (tags.sport ?? "").split(";").map((s) => s.trim());
    const indoor = tags.indoor === "yes" || tags.building !== undefined || tags.leisure === "sports_centre";
    const courtsTag = Number.parseInt(tags.courts ?? "", 10);
    const pitchCount = c.filter((p) => p.tags.leisure === "pitch").length;
    const courts = Number.isFinite(courtsTag) ? courtsTag : pitchCount > 0 ? pitchCount : undefined;
    const access = tags.access === "private" ? "private"
      : tags.access === "customers" || tags.access === "members" ? "membership_required"
      : tags.access === "yes" || tags.access === "public" ? "public_walk_on" : undefined;
    const ids = c.map((p) => `${p.e.type}/${p.e.id}`).sort();
    return {
      externalId: ids[0],
      name: named?.tags.name ?? "Pickleball courts",
      lat: c.reduce((s, p) => s + p.lat, 0) / c.length,
      lng: c.reduce((s, p) => s + p.lng, 0) / c.length,
      attrs: {
        osm_ids: ids,
        courts,
        pickleball_courts: courts,
        court_type: sports.includes("tennis") ? "pickleball_lined_tennis" : sports.length === 1 ? "dedicated_pickleball" : "multi_use",
        indoor_outdoor: indoor ? "indoor" : "outdoor",
        lit: tags.lit === "yes" ? true : tags.lit === "no" ? false : undefined,
        access_type: access,
        cost_type: tags.fee === "yes" ? "paid" : tags.fee === "no" ? "free" : undefined,
        existence_status: "partially_verified",
        existence_confidence: 0.55,
      },
    };
  });
}


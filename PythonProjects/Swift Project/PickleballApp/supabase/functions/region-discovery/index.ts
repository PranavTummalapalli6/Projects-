// Region cold-start discovery (docs/ARCHITECTURE.md §8).
// The app calls this ONLY when a real map region returns no facilities. The database decides
// (region_claim_import) whether an external import may run: fresh cells are served from cache, failed
// cells back off, and a global hourly budget protects the free Overpass service.
// Source is pluggable: swap `fetchOverpass` for scheduled OSM extracts or a self-hosted Overpass.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OVERPASS_URL = Deno.env.get("OVERPASS_URL") ?? "https://overpass-api.de/api/interpreter";

import { type OsmElement, geohash, geohashBounds, normalize } from "./normalize.ts";

async function fetchOverpass(b: { s: number; w: number; n: number; e: number }): Promise<OsmElement[]> {
  const bbox = `${b.s},${b.w},${b.n},${b.e}`;
  const query = `[out:json][timeout:25];nwr["sport"~"pickleball"](${bbox});out center tags;`;
  const res = await fetch(OVERPASS_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "PickleballNow/1.0 (region backfill)" },
    body: "data=" + encodeURIComponent(query),
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) throw new Error(`overpass ${res.status}`);
  return (await res.json()).elements ?? [];
}

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`${fn} failed: ${res.status} ${await res.text()}`);
  return await res.json() as T;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  let lat: number, lng: number;
  try {
    ({ latitude: lat, longitude: lng } = await req.json());
  } catch {
    return json({ error: "invalid body" }, 400);
  }
  if (typeof lat !== "number" || typeof lng !== "number" || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return json({ error: "invalid coordinates" }, 400);
  }
  const cell = geohash(lat, lng, 4);
  const claim = await rpc<{ action: string; log_id?: number; facility_count?: number }>("region_claim_import", { p_geohash: cell });
  if (claim.action !== "import") return json({ geohash: cell, ...claim });

  let inserted = 0, merged = 0, fetched = 0;
  try {
    const elements = await fetchOverpass(geohashBounds(cell));
    fetched = elements.length;
    for (const c of normalize(elements)) {
      const result = await rpc<string>("import_facility", {
        p_source: "osm", p_external_id: c.externalId, p_name: c.name,
        p_latitude: c.lat, p_longitude: c.lng, p_attrs: c.attrs,
      });
      if (result === "inserted") inserted++; else merged++;
    }
    const done = await rpc<{ facility_count: number }>("region_finish_import", {
      p_geohash: cell, p_log_id: claim.log_id, p_status: "imported", p_fetched: fetched, p_inserted: inserted, p_merged: merged,
    });
    return json({ geohash: cell, action: "imported", inserted, merged, facility_count: done.facility_count });
  } catch (err) {
    await rpc("region_finish_import", {
      p_geohash: cell, p_log_id: claim.log_id, p_status: "failed", p_fetched: fetched, p_inserted: inserted,
      p_merged: merged, p_error: String(err),
    }).catch(() => {});
    return json({ geohash: cell, action: "failed" }, 502);
  }
});

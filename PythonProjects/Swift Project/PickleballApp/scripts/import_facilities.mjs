#!/usr/bin/env node
// Imports facilities from a city/county dataset or a manual seed file into Supabase through the
// deduplicating `import_facility` RPC. Accepts CSV or JSON.
//
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/import_facilities.mjs <file> --source city:fairfax_va
//
// Columns / keys: external_id (optional), name, latitude, longitude, plus any optional attrs:
//   courts, pickleball_courts, court_type, indoor_outdoor, lit, play_system, address, city, state, postal_code,
//   time_zone, access_type, access_notes, cost_type, day_pass_price, reservation_available
// The service-role key must never ship in the app; run this only from a trusted machine or CI.
import { readFileSync } from "node:fs";

const [file, ...rest] = process.argv.slice(2);
const source = rest[rest.indexOf("--source") + 1];
const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY: KEY } = process.env;
if (!file || !source || rest.indexOf("--source") < 0 || !SUPABASE_URL || !KEY) {
  console.error("usage: SUPABASE_URL=.. SUPABASE_SERVICE_ROLE_KEY=.. node scripts/import_facilities.mjs <file.csv|json> --source <name>");
  process.exit(1);
}

export function parseCSV(text) {
  const rows = [];
  let row = [], field = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field); field = "";
      if (row.some((v) => v !== "")) rows.push(row);
      row = [];
    } else field += c;
  }
  row.push(field);
  if (row.some((v) => v !== "")) rows.push(row);
  const [header, ...data] = rows;
  return data.map((r) => Object.fromEntries(header.map((h, i) => [h.trim(), r[i]?.trim() ?? ""])));
}

const text = readFileSync(file, "utf8");
const records = file.endsWith(".json") ? JSON.parse(text) : parseCSV(text);
const numeric = new Set(["courts", "pickleball_courts", "day_pass_price"]);
const bools = new Set(["lit", "reservation_available"]);
const counts = { inserted: 0, merged: 0, updated: 0, failed: 0 };

for (const [i, r] of records.entries()) {
  const { external_id, name, latitude, longitude, ...rawAttrs } = r;
  const attrs = {};
  for (const [k, v] of Object.entries(rawAttrs)) {
    if (v === "" || v === null || v === undefined) continue;
    attrs[k] = numeric.has(k) ? Number(v) : bools.has(k) ? ["true", "yes", "1", true].includes(v) : v;
  }
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/import_facility`, {
    method: "POST",
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      p_source: source, p_external_id: String(external_id || `${source}-${i}`), p_name: name,
      p_latitude: Number(latitude), p_longitude: Number(longitude), p_attrs: attrs,
    }),
  });
  if (res.ok) counts[await res.json()]++;
  else { counts.failed++; console.error(`row ${i} (${name}): ${res.status} ${await res.text()}`); }
}
console.log(counts);

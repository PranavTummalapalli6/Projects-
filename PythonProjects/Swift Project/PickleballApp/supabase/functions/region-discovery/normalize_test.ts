import { assertEquals } from "jsr:@std/assert@1";
import { geohash, geohashBounds, normalize } from "./normalize.ts";

Deno.test("geohash matches reference and bounds contain the point", () => {
  assertEquals(geohash(57.64911, 10.40744, 11), "u4pruydqqvj");
  const b = geohashBounds(geohash(38.85, -77.3, 4));
  assertEquals(b.s <= 38.85 && b.n >= 38.85 && b.w <= -77.3 && b.e >= -77.3, true);
});

Deno.test("adjacent OSM pitches collapse into one facility", () => {
  const els = [
    { type: "way", id: 2, center: { lat: 38.85, lon: -77.3 }, tags: { leisure: "pitch", sport: "tennis;pickleball", name: "Elm Park" } },
    { type: "way", id: 1, center: { lat: 38.8501, lon: -77.3001 }, tags: { leisure: "pitch", sport: "tennis;pickleball", lit: "yes" } },
    { type: "node", id: 9, lat: 38.9, lon: -77.4, tags: { sport: "pickleball", access: "private" } },
  ] as const;
  const out = normalize(els as never);
  assertEquals(out.length, 2);
  const park = out.find((c) => c.name === "Elm Park")!;
  assertEquals(park.externalId, "way/1");
  assertEquals(park.attrs.courts, 2);
  assertEquals(park.attrs.court_type, "pickleball_lined_tennis");
  assertEquals(park.attrs.lit, true);
  assertEquals(out.find((c) => c.name === "Pickleball courts")!.attrs.access_type, "private");
});

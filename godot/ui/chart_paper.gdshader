shader_type canvas_item;
// THE CHART, DRAWN ON THE GPU.
//
// WHY A SHADER AND NOT A BIGGER IMAGE. The plate was built in GDScript by
// interpolating the 96x64 terrain grid up to 384x256, then drawn across ~680 px
// and zoomed to 2.6x — about 1768 px of screen from 96 samples of field.
// Interpolation cannot invent detail, only smooth what is there, so the result
// was guaranteed blurry no matter how large the intermediate image got. Baking a
// larger one would have cost seconds of main thread and still had no detail
// beyond the grid.
//
// THE ONE RULE THIS FILE MUST NOT BREAK: the 96x64 field is the single source of
// truth for everything the game reads — pins, roads, costs, placement. It
// arrives here as `height_tex` and is never recomputed. What this shader adds on
// top is DETAIL OCTAVES, and nothing gameplay-facing may ever read them. That
// split is deliberate: re-implementing the terrain function in GLSL would mean
// two versions of one truth, which is the drift this repo has paid for six times
// over (see the art-key prefixes in Invariants.md).
//
// So: base height is sampled, detail is invented, and the invented part only
// ever changes what a pixel looks like.

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float sea_level = 0.5;
uniform float land_band = 0.25;
uniform float hill_at = 1.0;
uniform float peak_at = 1.0;
uniform float detail = 1.0;        // how much high-frequency relief to invent
uniform float relief = 1.0;        // the family's relief, so a city stays flat
// ── HOW BUILT-UP THIS WORLD IS ───────────────────────────────────────────────
// Changing the COLOURS of a city chart to concrete was only half the fix. The
// SHAPES were still natural terrain — smooth fbm hills — so Neon Spire read as
// grey moorland rather than a city. A settled world's ground is rectilinear:
// blocks with streets between them, which is what CHART_GROUND has said all
// along ("dense city blocks and arterial roads", "packed brick districts").
//
// Applied on top of the height field, never into it: the blocks change what a
// pixel looks like and nothing else. The roads still route over the same
// authoritative 96x64 field, so a street drawn here can never disagree with a
// road drawn there — one is decoration, the other is the map.
uniform float urban = 0.0;
uniform vec4 accent : source_color = vec4(0.72, 0.61, 0.96, 1.0);
uniform vec4 c_deep : source_color = vec4(0.05, 0.12, 0.28, 1.0);
uniform vec4 c_shallow : source_color = vec4(0.30, 0.50, 0.62, 1.0);
uniform vec4 c_strand : source_color = vec4(0.82, 0.76, 0.58, 1.0);
uniform vec4 c_low : source_color = vec4(0.30, 0.44, 0.26, 1.0);
uniform vec4 c_high : source_color = vec4(0.46, 0.53, 0.30, 1.0);
uniform vec4 c_hill : source_color = vec4(0.47, 0.45, 0.30, 1.0);
uniform vec4 c_peak : source_color = vec4(0.96, 0.96, 0.97, 1.0);

// ── AT-8: REGIONS HAVE EXTENT ────────────────────────────────────────────────
// Regions were real in the data — name, lore, biome, position, GM-chartered via
// [[region]] — and drawn as floating letterspaced text and nothing else. No
// boundary, no tint, no area, so "different regions" read as words lying on
// grass. The only spatial expression was dimming everything outside a focused
// one, which says where a region ISN'T.
//
// The extent is a Voronoi over the region hearts, computed HERE rather than
// baked into an index texture. A 96x64 index map would step in 7-pixel blocks at
// the Atlas's own size and worse as you zoom in; solved analytically the
// boundary is exact at every magnification, for less work. Same reason the
// coastline is a stroke rather than a colour change.
//
// Only regions the player has reached are passed — world_map gates the list, so
// fog is honoured without this shader knowing what fog is.
uniform int region_n = 0;
uniform vec2 region_at[8];

// ── value noise, the cheap kind ──────────────────────────────────────────────
float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);              // smoothstep, so the field is C1
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += vnoise(p) * amp;
		p *= 2.03;                             // not exactly 2, or the octaves
		amp *= 0.5;                            // line up and the field bands
	}
	return v;
}

// Height at a point: the AUTHORITATIVE field, plus invented detail that fades to
// nothing at the coast so the coastline the player sees still matches the
// coastline the roads were routed over.
float h_at(vec2 uv) {
	float base = texture(height_tex, uv).r;
	float near_sea = smoothstep(0.0, land_band * 0.5, abs(base - sea_level));
	float d = (fbm(uv * 34.0) - 0.5) * 0.055 * detail * relief * near_sea;
	return base + d;
}

void fragment() {
	vec2 px = 1.0 / vec2(textureSize(height_tex, 0));
	float h = h_at(UV);
	vec3 col;

	if (h <= sea_level) {
		// Bathymetry in bands rather than a smooth fade — a chart says how deep
		// the water is, and stepped shelves read as cartography where a gradient
		// reads as fog.
		float deep = clamp((sea_level - h) / max(sea_level * 0.5, 0.0001), 0.0, 1.0);
		float banded = floor(deep * 4.0) / 4.0;
		col = mix(c_shallow.rgb, c_deep.rgb, mix(deep, banded, 0.55));
	} else {
		float up = (h - sea_level) / max(land_band, 0.0001);
		if (h < sea_level + land_band * 0.045) {
			col = c_strand.rgb;
		} else if (h >= peak_at) {
			col = mix(c_hill.rgb, c_peak.rgb,
				clamp((h - peak_at) / max(1.0 - peak_at, 0.0001), 0.0, 1.0));
		} else if (h >= hill_at) {
			col = mix(c_hill.rgb * 0.92, c_hill.rgb * 1.18,
				clamp((h - hill_at) / max(peak_at - hill_at, 0.0001), 0.0, 1.0));
		} else {
			col = mix(c_low.rgb, c_high.rgb, clamp(up * 2.2, 0.0, 1.0));
		}

		// ── HILLSHADE ────────────────────────────────────────────────────────
		// The single biggest reason the flat ramp read as a 90s handheld map.
		// A surface normal from the height gradient, lit from the north-west,
		// which is the convention every printed relief map uses.
		float hx = h_at(UV + vec2(px.x, 0.0)) - h_at(UV - vec2(px.x, 0.0));
		float hy = h_at(UV + vec2(0.0, px.y)) - h_at(UV - vec2(0.0, px.y));
		vec3 n = normalize(vec3(-hx * 26.0 * relief, -hy * 26.0 * relief, 1.0));
		float lambert = clamp(dot(n, normalize(vec3(-0.6, -0.6, 0.55))), 0.0, 1.0);
		col *= 0.62 + 0.62 * lambert;

		// City blocks. Each cell takes its own tone, and the gaps between them are
		// streets — which is the difference between a picture of ground and a
		// picture of a place people built.
		if (urban > 0.001) {
			vec2 gv = UV * vec2(52.0, 35.0);
			vec2 gi = floor(gv);
			vec2 gf = fract(gv);
			float blk = hash21(gi);
			vec3 blocky = col * (0.82 + 0.34 * blk);
			float street = min(min(gf.x, 1.0 - gf.x), min(gf.y, 1.0 - gf.y));
			// Two widths: most gaps are lanes, a few are arterials. A grid of
			// identical streets reads as graph paper.
			float wide = step(0.86, hash21(gi * 0.5)) * 0.05;
			blocky = mix(blocky * 0.55, blocky, smoothstep(0.0, 0.055 + wide, street));
			col = mix(col, blocky, urban);
		}

		// Contours, faint — every eighth of the land band. They cost nothing and
		// they are what makes a picture of ground read as a MAP of it.
		float bands = up * 8.0;
		float line = abs(fract(bands) - 0.5) * 2.0;
		float w = fwidth(bands) * 1.6;
		col *= 1.0 - 0.13 * (1.0 - smoothstep(0.0, max(w, 0.001), 1.0 - line));
	}

	// Region tint and edge. Land only: a border drawn across open sea claims the
	// water is owned, and no region in this game claims water.
	if (region_n > 0 && h > sea_level) {
		float d1 = 1e9;
		float d2 = 1e9;
		int best = 0;
		for (int i = 0; i < 8; i++) {
			if (i >= region_n) { break; }
			// EACH HEART'S FIELD WOBBLES ON ITS OWN. A plain Voronoi over three
			// sites draws dead-straight radial lines, which read as debug
			// wireframe rather than as a border — and no real march is a laser
			// line, because borders follow ridges and rivers. The offset is
			// per-site (i shifts the sample), so the fields disagree and the
			// boundary between them wanders. Same noise as the terrain, so it
			// wanders WITH the ground rather than across it.
			float d = distance(UV, region_at[i])
				+ (fbm(UV * 6.5 + vec2(float(i) * 37.1, float(i) * 11.3)) - 0.5) * 0.055;
			if (d < d1) { d2 = d1; d1 = d; best = i; }
			else if (d < d2) { d2 = d; }
		}
		// Hues walk the wheel from the world's own accent, so the regions of one
		// world are relatives rather than a random assortment.
		float hue = fract(float(best) * 0.19 + 0.5);
		vec3 rc = clamp(abs(fract(hue + vec3(0.0, 0.333, 0.667)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
		col = mix(col, mix(rc, accent.rgb, 0.4), 0.13);
		// The march between two hearts: where the nearest two are equidistant.
		//
		// INK, NOT THE REGION HUE. Taking the edge colour from `rc` gave a fully
		// saturated green or cyan hairline that shouted over a muted map — the
		// tint said "this area is Mournwood" quietly while the border screamed.
		// A border on a chart is drawn in the same ink as everything else; the
		// COLOUR belongs to the area, the LINE belongs to the map.
		float gap = d2 - d1;
		float ew = fwidth(gap) * 2.0;
		col = mix(mix(col, vec3(0.13, 0.11, 0.10), 0.62), col,
			smoothstep(0.0, max(ew, 0.00001), gap));
	}

	// The coastline itself, drawn as a stroke rather than left as a colour
	// change. `fwidth` keeps it one screen pixel wide at every zoom, which is
	// the whole point of doing this on the GPU instead of in a baked image.
	float d_sea = h - sea_level;
	float edge = fwidth(d_sea) * 1.4;
	col = mix(vec3(0.16, 0.13, 0.10), col,
		smoothstep(0.0, max(edge, 0.0001), abs(d_sea)));

	// Paper grain, and the world's accent over everything so a chart wears its
	// own skin. Tinted, never replaced: land has to keep reading as land.
	col *= 0.965 + 0.07 * vnoise(UV * 520.0);
	// Lighter than it was: at 0.13 the tint washed the low-saturation city ramps
	// into one hazy mauve, because concrete has no colour of its own to hold
	// against it. Wilderness had enough to survive it and cities did not.
	col = mix(col, accent.rgb, 0.09);
	COLOR = vec4(col, 1.0);
}

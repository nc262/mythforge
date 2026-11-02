shader_type canvas_item;
// THE CHART AS INK ON PARCHMENT.
//
// WHY THE STYLE CHANGED. This drew coloured relief: green land, blue sea,
// hillshading, contours. It was CORRECT — the pins stood on ground that agreed
// with them — and it looked like a strategy-game minimap, because that is what
// shaded relief looks like.
//
// The target is a hand-drawn book map: ink line-work on aged paper, a hatched
// shoreline, drawn mountains and trees, lettering in the land. That style is
// STYLISED, which is exactly why it is the right target — flat shapes and hard
// lines are CORRECT there, where in shaded relief they read as unfinished.
// Chasing realism made every simplification look like a failure; in ink the
// simplifications ARE the style.
//
// WHAT DID NOT CHANGE: anything the game reasons about. `height_tex` is the same
// 96x64 field the pins are placed on and the roads routed over, and this file
// only decides what a pixel looks like. Replacing the whole visual language
// without touching a line of placement or routing is the dividend of having
// inverted the pipeline — when the picture was a generated painting, a restyle
// meant re-baking six worlds and hoping the pins still landed.
//
// No hillshade and no contours any more. A pen-and-ink map has neither:
// elevation is DRAWN, as little peaks, by the layer above this one.

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float sea_level = 0.5;
uniform float land_band = 0.25;
uniform float hill_at = 1.0;
uniform float peak_at = 1.0;
uniform float detail = 1.0;
uniform float relief = 1.0;
uniform float urban = 0.0;
uniform vec4 accent : source_color = vec4(0.72, 0.61, 0.96, 1.0);
// Paper and ink, per world. A fantasy chart is warm vellum; a cyber world's is a
// cold blueprint. Same drawing, different stock — which is how an atlas tells a
// sea chart from a survey without redrawing anything.
uniform vec4 c_paper : source_color = vec4(0.87, 0.80, 0.63, 1.0);
uniform vec4 c_paper_dark : source_color = vec4(0.74, 0.65, 0.47, 1.0);
uniform vec4 c_ink : source_color = vec4(0.20, 0.14, 0.09, 1.0);
uniform vec4 c_land : source_color = vec4(0.83, 0.75, 0.56, 1.0);

uniform int region_n = 0;
uniform vec2 region_at[8];

float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
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
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

// C1 reconstruction. Plain bilinear is only C0 and its derivative jumps at every
// texel edge, which drew the 96x64 grid across the map as a mesh of fine lines.
// It mattered for hillshading and it matters here too: the shore hatch is spaced
// off the same field.
float h_smooth(vec2 uv) {
	vec2 ts = vec2(textureSize(height_tex, 0));
	vec2 t = uv * ts - 0.5;
	vec2 i = floor(t);
	vec2 f = fract(t);
	f = f * f * (3.0 - 2.0 * f);
	return texture(height_tex, (i + 0.5 + f) / ts).r;
}

float h_at(vec2 uv) {
	float base = h_smooth(uv);
	float near_sea = smoothstep(0.0, land_band * 0.5, abs(base - sea_level));
	return base + (fbm(uv * 34.0) - 0.5) * 0.055 * detail * relief * near_sea;
}

void fragment() {
	float h = h_at(UV);
	float d_sea = h - sea_level;

	// THE PAPER. Aged, not flat: a broad stain at one scale, fibre at another,
	// and a darkening toward the edges as if the sheet has been handled. Paper
	// that is one colour reads as a background; paper with age reads as a page.
	float stain = fbm(UV * 3.1);
	float fibre = vnoise(UV * 260.0) * 0.5 + vnoise(UV * 700.0) * 0.5;
	vec3 col = mix(c_paper.rgb, c_paper_dark.rgb, stain * 0.55 + fibre * 0.14);
	vec2 ev = abs(UV - 0.5) * 2.0;
	col = mix(col, c_paper_dark.rgb * 0.86, pow(max(ev.x, ev.y), 3.4) * 0.55);

	if (d_sea > 0.0) {
		// Land is slightly different stock — enough to read the coast by,
		// nowhere near enough to be "colour".
		col = mix(col, c_land.rgb, 0.42);
		float up = clamp(d_sea / max(land_band, 0.0001), 0.0, 1.0);
		col = mix(col, c_paper_dark.rgb, up * 0.16);
	} else {
		// SHORE HATCHING — the stacked lines following a coast on every engraved
		// chart. Not a texture: spaced off the DEPTH, so they hug the shore,
		// crowd where it drops steeply and fade to open paper, which is what a
		// hand with a pen actually produces. Costs one fract().
		float bands = (-d_sea) / max(land_band * 0.055, 0.0001);
		float line = abs(fract(bands) - 0.5) * 2.0;
		float w = fwidth(bands) * 1.5;
		float hatch = 1.0 - smoothstep(0.0, max(w, 0.001), 1.0 - line);
		hatch *= smoothstep(6.0, 0.6, bands);
		col = mix(col, c_ink.rgb, hatch * 0.34);
	}

	// Region wash, kept very light: on paper a province is a WASH, and a wash
	// that competes with the ink is a printing error.
	if (region_n > 0 && d_sea > 0.0) {
		float dd1 = 1e9;
		float dd2 = 1e9;
		int best = 0;
		for (int i = 0; i < 8; i++) {
			if (i >= region_n) { break; }
			float d = distance(UV, region_at[i])
				+ (fbm(UV * 6.5 + vec2(float(i) * 37.1, float(i) * 11.3)) - 0.5) * 0.055;
			if (d < dd1) { dd2 = dd1; dd1 = d; best = i; }
			else if (d < dd2) { dd2 = d; }
		}
		float hue = fract(float(best) * 0.19 + 0.5);
		vec3 rc = clamp(abs(fract(hue + vec3(0.0, 0.333, 0.667)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
		col = mix(col, mix(rc, accent.rgb, 0.55), 0.055);
		float seam = dd2 - dd1;
		// A DASHED march. A solid one competes with the coastline for the same
		// kind of attention, and on a drawn map a border is always the lighter
		// mark of the two.
		float dash = step(0.42, fract(distance(UV, region_at[best]) * 150.0));
		col = mix(mix(col, c_ink.rgb, 0.5 * dash), col,
			smoothstep(0.0, max(fwidth(seam) * 2.6, 0.00001), seam));
	}

	// THE COASTLINE, heaviest line on the map and drawn last so nothing sits on
	// top of it. `fwidth` holds it at one screen pixel however far you zoom,
	// which is the reason this is a shader and not a baked image.
	float edge = fwidth(d_sea) * 1.7;
	col = mix(c_ink.rgb, col, smoothstep(0.0, max(edge, 0.0001), abs(d_sea)));

	COLOR = vec4(col, 1.0);
}

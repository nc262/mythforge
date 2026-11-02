shader_type canvas_item;
// THE SHEET A LOCAL MAP IS DRAWN ON.
//
// AT-11 — the Atlas became ink on parchment and the tier below it stayed
// coloured relief: green ground, blue water, beige buildings under a paper
// world map. Two tiers of one atlas have to be on the same stock, or clicking
// into a town looks like leaving the book.
//
// The Atlas's own shader cannot serve here: it reads `height_tex`, and a town
// has no height field — its geometry is streets and footprints, drawn as vectors
// on top of this. So this is the PAPER HALF of chart_paper.gdshader and nothing
// else, with the same stain/fibre/vignette so the two sheets are visibly cut
// from one hide.

uniform vec4 c_paper : source_color = vec4(0.87, 0.80, 0.63, 1.0);
uniform vec4 c_paper_dark : source_color = vec4(0.74, 0.65, 0.47, 1.0);

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

void fragment() {
	float stain = fbm(UV * 3.1);
	float fibre = vnoise(UV * 260.0) * 0.5 + vnoise(UV * 700.0) * 0.5;
	vec3 col = mix(c_paper.rgb, c_paper_dark.rgb, stain * 0.55 + fibre * 0.14);
	vec2 ev = abs(UV - 0.5) * 2.0;
	col = mix(col, c_paper_dark.rgb * 0.86, pow(max(ev.x, ev.y), 3.4) * 0.55);
	COLOR = vec4(col, 1.0);
}

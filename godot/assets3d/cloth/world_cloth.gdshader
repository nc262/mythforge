shader_type spatial;
// The world's cloth, poured over a garment the outfit pack never made for that
// genre. See docs/CharacterRender.md — four families (cyber, everyday, space,
// steam) have no geometry of their own, and a material is a shader input, so
// form x material is addition rather than multiplication.
//
// Deliberately NO render_mode: the figurine's lighting must not change when a
// garment is dyed, or the pour would be judged against a different picture.
// Only ALBEDO is touched.

// The poured tileable texture, sampled TRIPLANAR — by object position, never by
// UV. A garment's atlas is laid out for its own painted texture, so pushing a
// tileable material through it comes back stretched and scrambled. That was
// measured in spike3d/portrait_spike.gd; triplanar ignores UVs entirely, which
// is the whole reason one cloth can cover any garment from any source.
uniform sampler2D cloth : source_color, hint_default_white;

// The garment's OWN albedo, sampled by UV and used for its LUMINANCE only.
// Without this the piece becomes a flat silhouette in one colour: every strap,
// lace, seam and belt is painted into that texture, and it is the only record
// of the tailoring. Keeping the light/dark and replacing the hue is the whole
// trick — the garment stays tailored, the world supplies the substance.
uniform sampler2D garment : source_color, hint_default_white;

// Object units, so it must be tuned to the mesh's size, not to taste: 0.25 read
// as cloth on a 1.5-unit figure, 2.2 tiled so tightly it read as pattern.
uniform float tri_scale = 0.25;
// How much of the garment's own shading survives. 0 = pure poured material,
// flat and untailored; 1 = full shading, which can crush the darks. The knob
// stays because the right value is a look, and looks get retuned.
uniform float keep : hint_range(0.0, 1.0) = 0.55;

varying vec3 tri_pos;
varying vec3 tri_nrm;

void vertex() {
	tri_pos = VERTEX * tri_scale;
	tri_nrm = NORMAL;
}

vec3 tri_sample(sampler2D t, vec3 p, vec3 n) {
	// Weight the three projections by how much the surface faces each axis; pow
	// sharpens the blend so a flat face reads as one clean projection.
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	return texture(t, p.yz).rgb * w.x
		 + texture(t, p.xz).rgb * w.y
		 + texture(t, p.xy).rgb * w.z;
}

void fragment() {
	vec3 c = tri_sample(cloth, tri_pos, normalize(tri_nrm));
	float l = dot(texture(garment, UV).rgb, vec3(0.2126, 0.7152, 0.0722));
	// Normalised around mid-grey so an averagely-lit garment neither brightens
	// nor darkens the cloth, and clamped so a white highlight cannot blow out.
	//
	// The FLOOR is the part that was learned by rendering it. Without one, a
	// dark cloth multiplied by a dark garment albedo compounds into near-black:
	// the first pass came out as a figure smeared with soot, with every fold and
	// strap lost. 0.55 keeps the deepest crease legible while still reading as a
	// crease.
	float shade = mix(1.0, clamp(l / 0.5, 0.55, 1.6), keep);
	ALBEDO = c * shade;
	SPECULAR = 0.1;
	ROUGHNESS = 0.85;
}

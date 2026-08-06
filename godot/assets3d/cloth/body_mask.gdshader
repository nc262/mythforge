shader_type spatial;
// HIDDEN SURFACE REMOVAL for the skin. See scripts/bake_body_masks.py for why
// this, and not a swelled garment: separation enforced in one pose is undone by
// the next, while absent geometry cannot poke through anything ever.
//
// The mask is white where some worn garment covers this skin. The doll unions
// the masks of everything currently worn into one image and hands it here, so
// this shader never needs to know how many pieces are on.

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform sampler2D cover_mask : source_color, hint_default_black;

void fragment() {
	// discard, not alpha: a transparent skin would still write depth and sort
	// against the cloth, which is the same fight in a different form.
	if (texture(cover_mask, UV).r > 0.5) {
		discard;
	}
	ALBEDO = texture(albedo_tex, UV).rgb;
	SPECULAR = 0.1;
	ROUGHNESS = 0.85;
}

shader_type spatial;
// HIDDEN SURFACE REMOVAL for the skin, plus the skin's own surface. See
// scripts/bake_body_masks.py for why removal and not a swelled garment:
// separation enforced in one pose is undone by the next, while absent geometry
// cannot poke through anything ever.
//
// The mask is white where some worn garment covers this skin. The doll unions
// the masks of everything currently worn into one image and hands it here, so
// this shader never needs to know how many pieces are on.
//
// IT CARRIES THE PBR MAPS THROUGH, and that is not a flourish. The pack's skin
// ships a normal map and a roughness map and the material references both — but
// this shader replaced that material the moment ANY garment went on, sampling
// albedo alone and hard-coding a flat roughness. A bare hero rendered with pores
// and a dressed one rendered like painted plastic, which is every hero, always,
// on every surface in the game.
//
// It is also where the skin is TINTED, because a tint applied anywhere else
// would only reach a dressed figure — this material is the one thing the skin
// always wears.

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform sampler2D cover_mask : source_color, hint_default_black;
uniform sampler2D normal_tex : hint_normal;
uniform sampler2D rough_tex : hint_default_white;
// Booleans rather than relying on a default texture: a missing normal map has
// to mean "leave the geometry normal alone", and hint_normal's flat blue is
// only approximately that once it has been through the tangent basis.
uniform bool has_normal = false;
uniform bool has_rough = false;
uniform float normal_depth : hint_range(0.0, 3.0) = 1.0;
// Multiplied over the albedo, so freckles, lips and brows survive it. A flat
// fill would give a hero the face of a mannequin dipped in paint.
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float rough_flat : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	// discard, not alpha: a transparent skin would still write depth and sort
	// against the cloth, which is the same fight in a different form.
	if (texture(cover_mask, UV).r > 0.5) {
		discard;
	}
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	// glTF packs roughness in GREEN; a standalone roughness map is grey, so the
	// green channel reads correctly either way.
	ROUGHNESS = has_rough ? texture(rough_tex, UV).g : rough_flat;
	SPECULAR = 0.28;
}

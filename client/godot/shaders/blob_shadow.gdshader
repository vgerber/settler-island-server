shader_type spatial;
// A soft contact shadow: a flat quad under a piece, black with a radial falloff. Works in every renderer
// (no shadow map), which is why Compatibility uses it for all pieces. The quad's UV runs 0..1.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	float distance_from_centre = length(UV - vec2(0.5)) * 2.0;
	float falloff = 1.0 - smoothstep(0.15, 1.0, distance_from_centre);
	ALBEDO = vec3(0.07, 0.04, 0.03);
	ALPHA = strength * falloff * falloff;
}

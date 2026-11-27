shader_type spatial;
// Matte clay for every piece of the clay kit. The vertex colour is the sRGB albedo with the ambient
// occlusion baked in (ClayBuilder), `tint` recolours white seat pieces, a faint fingerprint ridge pattern
// breaks up the flat colour, and a rim term keeps pieces readable against terrain: a light edge on dark
// pieces (Ember, Cobalt, Charcoal), a dark edge on light ones (Ivory), the outline rule of visual-style.md
// without a hull. Plain Lambert lighting, so it runs the same in Compatibility and Forward+.
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 rim_color : source_color = vec4(0.96, 0.94, 0.89, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;
uniform float rim_power : hint_range(0.5, 8.0) = 2.2;
uniform float fingerprint_strength : hint_range(0.0, 0.3) = 0.035;
uniform float fingerprint_scale = 46.0;
// Walnut grain along x for the table; 0 for everything else.
uniform float grain_strength : hint_range(0.0, 0.5) = 0.0;
// Forward+ takes vertex colours as linear, Compatibility converts them itself; ClayMaterials sets this.
uniform bool convert_vertex_color = false;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;

varying vec3 local_position;

vec3 srgb_to_linear(vec3 color) {
	return mix(pow((color + vec3(0.055)) / 1.055, vec3(2.4)), color / 12.92, lessThan(color, vec3(0.04045)));
}

float hash3(vec3 cell) {
	cell = fract(cell * 0.3183099 + vec3(0.71, 0.113, 0.419));
	cell *= 17.0;
	return fract(cell.x * cell.y * cell.z * (cell.x + cell.y + cell.z));
}

float value_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float x00 = mix(hash3(cell), hash3(cell + vec3(1.0, 0.0, 0.0)), blend.x);
	float x10 = mix(hash3(cell + vec3(0.0, 1.0, 0.0)), hash3(cell + vec3(1.0, 1.0, 0.0)), blend.x);
	float x01 = mix(hash3(cell + vec3(0.0, 0.0, 1.0)), hash3(cell + vec3(1.0, 0.0, 1.0)), blend.x);
	float x11 = mix(hash3(cell + vec3(0.0, 1.0, 1.0)), hash3(cell + vec3(1.0, 1.0, 1.0)), blend.x);
	return mix(mix(x00, x10, blend.y), mix(x01, x11, blend.y), blend.z);
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec3 vertex_albedo = convert_vertex_color ? srgb_to_linear(COLOR.rgb) : COLOR.rgb;
	vec3 albedo = vertex_albedo * tint.rgb;
	// Curved ridges like a thumb pressed into clay: sin of a warped noise field.
	float warp = value_noise(local_position * fingerprint_scale * 0.35) * 4.0;
	float ridge = sin(value_noise(local_position * fingerprint_scale * 0.18) * 22.0 + warp) * 0.5;
	albedo *= 1.0 + ridge * fingerprint_strength;
	if (grain_strength > 0.0) {
		float grain = sin(local_position.z * 9.0 + value_noise(vec3(local_position.x * 0.5, 0.0, local_position.z * 2.0)) * 11.0);
		albedo *= 1.0 + grain * grain_strength;
	}
	float edge = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	float rim = edge * rim_strength;
	albedo = mix(albedo, rim_color.rgb, rim);
	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.12;
	// A little emission so a light rim stays visible in shade; a dark rim must not glow.
	EMISSION = rim_color.rgb * rim * 0.25 * step(0.4, dot(rim_color.rgb, vec3(0.33)));
}

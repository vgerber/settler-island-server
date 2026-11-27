shader_type spatial;
// One flat-shaded water hex of the table. The hexes are a MultiMesh, so MODEL_MATRIX tells each one apart: its
// position hashes to a slight colour variation and to the phase of a slow bob (the whole top moves, the
// chamfer follows through the vertex alpha), which keeps the water alive for a few operations per vertex.
// The vertex colour holds a grey AO in red and the bob weight in alpha (a ClayBuilder slab).
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.165, 0.4, 0.447, 1.0);
uniform vec4 crest_color : source_color = vec4(0.208, 0.478, 0.525, 1.0);
uniform float bob_height = 0.012;
uniform float bob_speed = 0.7;

varying float variation;
varying float occlusion;

float hash(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec2 cell = MODEL_MATRIX[3].xz;
	variation = hash(floor(cell * 10.0));
	VERTEX.y += sin(TIME * bob_speed + variation * 6.2831) * bob_height * COLOR.a;
	occlusion = COLOR.r;
}

void fragment() {
	ALBEDO = mix(deep_color.rgb, crest_color.rgb, variation * 0.7) * mix(1.0, occlusion, 0.8);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}

shader_type spatial;
// One flat-shaded water hex of the table. The hexes are a MultiMesh, so MODEL_MATRIX tells each one apart: its
// position hashes to a slight colour variation and to the phase of a slow bob (the whole top moves, the
// chamfer follows through the vertex alpha). INSTANCE_CUSTOM carries the coast: x is a bitmask of the hex edges
// that touch land (foam on those edges), y the shoal level (lighter, shallower water beside the island).
// The vertex colour holds a grey AO in red, the foam weight as (red - blue) * 2 and the bob weight in alpha.
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.165, 0.4, 0.447, 1.0);
uniform vec4 crest_color : source_color = vec4(0.208, 0.478, 0.525, 1.0);
uniform vec4 shoal_color : source_color = vec4(0.28, 0.6, 0.6, 1.0);
uniform vec4 foam_color : source_color = vec4(0.88, 0.95, 0.92, 1.0);
uniform float bob_height = 0.012;
uniform float bob_speed = 0.7;
// How much a facet's own hash lightens or darkens it (one shade per triangle, continuous across hexes).
uniform float facet_range = 0.12;
uniform float shoal_lift = 0.012;

varying float variation;
varying float occlusion;
varying float foam_weight;
varying float shoal;
varying float land_edges;
varying vec2 hex_position;
varying flat float facet;

float hash(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec2 cell = MODEL_MATRIX[3].xz;
	variation = hash(floor(cell * 10.0));
	shoal = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	land_edges = INSTANCE_CUSTOM.x;
	VERTEX.y += sin(TIME * bob_speed + variation * 6.2831) * bob_height * COLOR.a;
	VERTEX.y += shoal * shoal_lift * COLOR.a;
	occlusion = COLOR.r;
	foam_weight = (COLOR.r - COLOR.b) * 2.0;
	hex_position = VERTEX.xz;
	facet = hash(floor((MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * 37.0));
}

void fragment() {
	vec3 color = mix(deep_color.rgb, crest_color.rgb, variation * 0.7);
	color = mix(color, shoal_color.rgb, shoal * 0.75);
	color *= 1.0 + (facet - 0.5) * facet_range;
	color *= mix(1.0, occlusion, 0.8);
	float foam = 0.0;
	// atan is undefined at the hex centre, so the sector is only worked out on the foam ring.
	if (foam_weight > 0.05 && land_edges > 0.5) {
		float sector = mod(floor(atan(hex_position.y, hex_position.x) / 1.0471976 + 0.5 + 6.0), 6.0);
		float toward_land = mod(floor(land_edges / exp2(sector) + 0.01), 2.0);
		// The foam edge is broken up by the facet hash, so it reads as surf and not as a drawn line.
		foam = toward_land * smoothstep(0.35, 0.75, foam_weight) * (0.5 + 0.5 * facet);
	}
	ALBEDO = mix(color, foam_color.rgb, foam);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}

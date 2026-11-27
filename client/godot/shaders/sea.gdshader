shader_type spatial;
// The sea sheet: soft blue clay with calm ridges that drift slowly. The sheet is a ClayBuilder slab, so the
// vertex colour holds a grey AO and the vertex alpha fades the ridges out toward the bevel. Ridges are a sum
// of two slow sine waves; the normal comes from their analytic slope, so the light slides over them without
// any normal map.
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.165, 0.4, 0.447, 1.0);
uniform vec4 crest_color : source_color = vec4(0.208, 0.478, 0.525, 1.0);
uniform float ridge_height = 0.014;
uniform float drift_speed = 0.12;

varying float crest;
varying float occlusion;

void vertex() {
	vec2 point = VERTEX.xz;
	float time = TIME * drift_speed;
	float first_phase = point.x * 4.1 + point.y * 2.3 + time * 6.0;
	float second_phase = point.x * -2.6 + point.y * 5.0 - time * 4.5;
	float height = (sin(first_phase) * 0.6 + sin(second_phase) * 0.4) * ridge_height * COLOR.a;
	float slope_x = (cos(first_phase) * 4.1 * 0.6 + cos(second_phase) * -2.6 * 0.4) * ridge_height * COLOR.a;
	float slope_z = (cos(first_phase) * 2.3 * 0.6 + cos(second_phase) * 5.0 * 0.4) * ridge_height * COLOR.a;
	VERTEX.y += height;
	NORMAL = normalize(mix(NORMAL, vec3(-slope_x * 1.6, 1.0, -slope_z * 1.6), COLOR.a));
	crest = clamp(height / ridge_height * 0.5 + 0.5, 0.0, 1.0);
	occlusion = COLOR.r;
}

void fragment() {
	ALBEDO = mix(deep_color.rgb, crest_color.rgb, crest * 0.4) * mix(1.0, occlusion, 0.8);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}

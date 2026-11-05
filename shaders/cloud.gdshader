shader_type spatial;
render_mode blend_mix, cull_back, specular_disabled;

uniform vec4 albedo : source_color = vec4(0.9, 0.93, 0.97, 0.7);
uniform vec4 shadow_tint : source_color = vec4(0.5, 0.56, 0.64, 1.0);

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a * COLOR.a;
	ROUGHNESS = 1.0;
}

void light() {
	float nd = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float lit = smoothstep(0.4, 0.72, nd);
	DIFFUSE_LIGHT += mix(shadow_tint.rgb, vec3(0.94), lit) * LIGHT_COLOR;
}

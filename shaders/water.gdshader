shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_linear;
uniform vec4 shallow_color : source_color = vec4(0.42, 0.78, 0.84, 0.46);
uniform vec4 deep_color : source_color = vec4(0.08, 0.32, 0.58, 0.84);
uniform vec4 foam_color : source_color = vec4(0.86, 0.96, 0.97, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.28, 0.4, 0.52, 1.0);

varying vec3 v_color;
varying vec3 v_world;

void vertex() {
	v_color = COLOR.rgb;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 up = normalize(VERTEX);
	float wave = sin(v_world.x * 1.55 + TIME * 1.2) * sin(v_world.z * 1.35 + TIME * 0.85);
	wave += sin(v_world.y * 1.45 + TIME * 1.05) * 0.45;
	VERTEX += up * wave * 0.016 * v_color.r;
}

void fragment() {
	float mask = v_color.r;
	float stored = clamp(v_color.g, 0.0, 1.0);
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	view.xyz /= view.w;
	float thickness = clamp((-view.z + VERTEX.z) / 2.7, 0.0, 1.0);
	float depth = clamp(max(thickness, stored), 0.0, 1.0);
	vec3 color = mix(shallow_color.rgb, deep_color.rgb, depth);
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.6);
	float shimmer = sin(TIME * 1.6 + v_world.x * 2.2 + v_world.z * 1.7 + v_world.y) * 0.5 + 0.5;
	float foam = (1.0 - smoothstep(0.0, 0.09, thickness)) * mask;
	color = mix(color, foam_color.rgb, foam * 0.55 + fresnel * 0.16);
	ALBEDO = color;
	ROUGHNESS = 0.42;
	EMISSION = color * (0.045 + shimmer * 0.05 * mask);
	ALPHA = mix(shallow_color.a, deep_color.a, depth) + fresnel * 0.12;
}

void light() {
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float lit = smoothstep(0.22, 0.68, ndotl) * clamp(ATTENUATION, 0.0, 1.0);
	DIFFUSE_LIGHT += mix(shadow_color.rgb, vec3(1.0), lit) * LIGHT_COLOR;
}

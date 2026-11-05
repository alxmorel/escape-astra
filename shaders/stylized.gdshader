shader_type spatial;
render_mode cull_back, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float saturation : hint_range(0.0, 2.0) = 1.2;
uniform float pastel : hint_range(0.0, 1.0) = 0.06;
uniform vec4 shadow_color : source_color = vec4(0.38, 0.34, 0.46, 1.0);
uniform float toon_softness : hint_range(0.02, 0.5) = 0.22;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.12;
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.82, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.2;

void fragment() {
	vec3 color = albedo.rgb * COLOR.rgb;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luma), color, saturation);
	color = mix(color, vec3(luma * 0.45 + 0.55), pastel);
	ALBEDO = color;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = rim_color.rgb * rim * rim_strength;
}

void light() {
	float atten = clamp(ATTENUATION, 0.0, 1.0);
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float softness = clamp(toon_softness, 0.02, 0.49);
	float wrap = smoothstep(0.5 - softness, 0.5 + softness, ndotl);
	vec3 factor = mix(shadow_color.rgb, vec3(0.70), wrap);
	DIFFUSE_LIGHT += factor * LIGHT_COLOR * atten;
}

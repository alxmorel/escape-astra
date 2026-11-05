shader_type sky;

// EYEDIR, up and sun_dir are world-space directions.
uniform vec3 up = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 zenith_color : source_color = vec3(0.4, 0.62, 0.9);
uniform vec3 nadir_color : source_color = vec3(0.5, 0.7, 0.93);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.88);
uniform vec3 sunset_color : source_color = vec3(0.9, 0.48, 0.28);
uniform float sunset = 0.0;
uniform float energy = 1.0;

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 nup = dot(up, up) > 0.0001 ? normalize(up) : vec3(0.0, 1.0, 0.0);
	float height = dot(dir, nup);
	vec3 col = mix(nadir_color, zenith_color, clamp(height * 0.5 + 0.5, 0.0, 1.0)) * energy;
	if (dot(sun_dir, sun_dir) > 0.0001) {
		vec3 sun = normalize(sun_dir);
		float sun_h = dot(sun, nup);
		float facing = dot(dir, sun);
		float disc = smoothstep(0.9945, 0.9982, facing) * smoothstep(-0.1, 0.08, sun_h);
		col = mix(col, sun_color, disc);
		float glow = pow(max(facing, 0.0), 3.0) * sunset;
		col = mix(col, sunset_color, glow * 0.4);
	}
	COLOR = col;
}

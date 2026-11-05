shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec3 player_position = vec3(0.0);
uniform float interaction_radius = 1.8;
uniform float bend_strength = 0.8;
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.25);
uniform float base_wind_strength = 0.06;
uniform float gust_strength = 0.2;
uniform float gust_speed = 0.9;
uniform float gust_scale = 0.16;
uniform float turbulence_strength = 0.02;
uniform float max_bend = 0.7;
uniform float saturation = 1.2;
uniform float pastel = 0.06;
uniform vec3 shadow_color = vec3(0.32, 0.42, 0.26);

varying vec3 _tint;
varying vec3 _face_view;
varying vec3 _up_view;

void vertex() {
	_tint = COLOR.rgb;
	_face_view = mat3(MODELVIEW_MATRIX) * NORMAL;

	float tip = clamp(UV.y, 0.0, 1.0);
	tip *= tip;

	vec3 axis_x = MODEL_MATRIX[0].xyz;
	vec3 axis_y = MODEL_MATRIX[1].xyz;
	vec3 axis_z = MODEL_MATRIX[2].xyz;
	float width_scale = max(length(axis_x), 0.001);
	float height_scale = max(length(axis_y), 0.001);
	axis_x /= width_scale;
	axis_y /= height_scale;
	axis_z /= max(length(axis_z), 0.001);
	_up_view = mat3(VIEW_MATRIX) * axis_y;
	NORMAL = vec3(0.0, 1.0, 0.0);
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	vec3 wind = wind_direction - axis_y * dot(wind_direction, axis_y);
	float wind_len = length(wind);
	vec3 wind_dir = mix(axis_x, wind / max(wind_len, 0.0001), step(0.001, wind_len));
	vec3 side = cross(axis_y, wind_dir);
	float side_len = length(side);
	side = mix(axis_z, side / max(side_len, 0.0001), step(0.001, side_len));
	wind_dir = normalize(wind_dir + side * sin(dot(origin, side) * 0.05) * 0.1);

	float along = dot(origin, wind_dir);
	float wave = along * gust_scale - TIME * gust_speed;
	float gust = smoothstep(-0.2, 1.0, sin(wave));
	float detail = sin(along * gust_scale * 2.1 - TIME * gust_speed * 0.55);
	float flex = clamp(height_scale / 0.24, 0.45, 1.0);
	float wind_mag = (base_wind_strength + gust * gust_strength + detail * turbulence_strength) * flex;

	vec3 away = origin - player_position;
	vec3 planar = away - axis_y * dot(away, axis_y);
	float dist = length(planar);
	float reach = max(interaction_radius, 0.2);
	float influence = 1.0 - smoothstep(reach * 0.22, reach, dist);
	influence *= influence;
	vec3 push_dir = mix(wind_dir, planar / max(dist, 0.0001), step(0.001, dist));
	vec3 horiz = wind_dir * wind_mag + push_dir * bend_strength * influence;
	float horiz_len = length(horiz);
	float limit = height_scale * tan(clamp(max_bend, 0.05, 1.15));
	horiz *= min(limit / max(horiz_len, 0.0001), 1.0);

	VERTEX.x += dot(horiz, axis_x) / width_scale * tip;
	VERTEX.z += dot(horiz, axis_z) / width_scale * tip;
	VERTEX.y += 0.03 / height_scale * tip;

	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float view_len = max(length(view_pos.xyz), 0.001);
	view_pos.xyz -= view_pos.xyz / view_len * 0.05 * tip;
	VERTEX = (inverse(MODELVIEW_MATRIX) * view_pos).xyz;
}

void fragment() {
	vec3 color = _tint;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luma), color, saturation);
	color = mix(color, vec3(luma * 0.45 + 0.55), pastel);
	ALBEDO = color;
	ROUGHNESS = 1.0;
}

void light() {
	float atten = clamp(ATTENUATION, 0.0, 1.0);
	vec3 face_n = normalize(_face_view);
	vec3 up_n = normalize(_up_view);
	float face_nd = abs(dot(face_n, LIGHT));
	float up_nd = clamp(dot(up_n, LIGHT), 0.0, 1.0);
	float nd = max(up_nd, face_nd);
	float lit = smoothstep(0.55, 0.7, nd);
	DIFFUSE_LIGHT += mix(shadow_color, vec3(0.70), lit) * LIGHT_COLOR * atten;
}

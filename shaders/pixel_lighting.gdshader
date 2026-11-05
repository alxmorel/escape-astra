shader_type canvas_item;

uniform int light_levels = 4;
uniform float dither_strength = 0.55;

float bayer4(ivec2 p) {
	int x = p.x & 3;
	int y = p.y & 3;
	if (y == 0) {
		if (x == 0) return 0.0;
		if (x == 1) return 8.0;
		if (x == 2) return 2.0;
		return 10.0;
	}
	if (y == 1) {
		if (x == 0) return 12.0;
		if (x == 1) return 4.0;
		if (x == 2) return 14.0;
		return 6.0;
	}
	if (y == 2) {
		if (x == 0) return 3.0;
		if (x == 1) return 11.0;
		if (x == 2) return 1.0;
		return 9.0;
	}
	if (x == 0) return 15.0;
	if (x == 1) return 7.0;
	if (x == 2) return 13.0;
	return 5.0;
}

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	ivec2 texel = ivec2(clamp(floor(UV * tex_size), vec2(0.0), tex_size - vec2(1.0)));
	vec4 src = texture(TEXTURE, UV);
	float luma = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));
	float levels = max(float(light_levels), 2.0);
	float band = 1.0 / levels;
	float dither = (bayer4(texel) / 16.0 - 0.5) * band * dither_strength;
	float index = clamp(floor((luma + dither) * levels), 0.0, levels - 1.0);
	float stepped = index / max(levels - 1.0, 1.0);
	vec3 color = src.rgb * (stepped / max(luma, 0.0001));
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), src.a);
}

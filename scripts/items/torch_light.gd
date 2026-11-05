extends RefCounted

## Params partagés torche tenue / posée.
## Atténuation élevée : intensité ≈ 0 avant omni_range → pas de coupe nette.
## Ombres cube : le terrain / constructions proches bloquent la lumière.

const COLOR := Color(1.0, 0.74, 0.4)
const ENERGY := 0.9
const RANGE := 8.5
const ATTENUATION := 2.4
const INDIRECT := 0.22
const SPECULAR := 0.35
const SHADOW_BIAS := 0.04
const SHADOW_NORMAL_BIAS := 1.0
const SHADOW_BLUR := 1.0
const FADE_BEGIN := 18.0
const FADE_SHADOW := 14.0
const FADE_LENGTH := 8.0


static func apply(light: OmniLight3D) -> void:
	if light == null:
		return
	light.light_color = COLOR
	light.light_energy = ENERGY
	light.light_indirect_energy = INDIRECT
	light.light_specular = SPECULAR
	light.omni_range = RANGE
	light.omni_attenuation = ATTENUATION
	light.shadow_enabled = true
	light.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	light.shadow_bias = SHADOW_BIAS
	light.shadow_normal_bias = SHADOW_NORMAL_BIAS
	light.shadow_blur = SHADOW_BLUR
	light.distance_fade_enabled = true
	light.distance_fade_begin = FADE_BEGIN
	light.distance_fade_shadow = FADE_SHADOW
	light.distance_fade_length = FADE_LENGTH

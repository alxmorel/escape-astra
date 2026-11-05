#!/usr/bin/env python3
"""Validation hors-moteur : torches craftables / tenues / posables."""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PASS = 0
FAIL = 0


def check(name: str, ok: bool, detail: str = "") -> None:
	global PASS, FAIL
	if ok:
		PASS += 1
		print(f"PASS  {name}" + (f" — {detail}" if detail else ""))
	else:
		FAIL += 1
		print(f"FAIL  {name}" + (f" — {detail}" if detail else ""))


def main() -> int:
	model = ROOT / "assets/models/torch.glb"
	recipes = (ROOT / "scripts/resources/recipe_catalog.gd").read_text(encoding="utf-8")
	previews = (ROOT / "scripts/ui/item_preview_scenes.gd").read_text(encoding="utf-8")
	icons = (ROOT / "scripts/ui/item_icons.gd").read_text(encoding="utf-8")
	locale = (ROOT / "locale/game.csv").read_text(encoding="utf-8")
	tools = (ROOT / "scripts/items/tool_scenes.gd").read_text(encoding="utf-8")
	player_tools = (ROOT / "scripts/player/player_tools.gd").read_text(encoding="utf-8")
	session = (ROOT / "scripts/core/world_session.gd").read_text(encoding="utf-8")
	torch_script = (ROOT / "scripts/machines/torch.gd").read_text(encoding="utf-8")
	held = ROOT / "scenes/items/torch.tscn"
	preview_scene = ROOT / "scenes/ui/item_previews/torch.tscn"
	preview_text = preview_scene.read_text(encoding="utf-8") if preview_scene.is_file() else ""
	held_text = held.read_text(encoding="utf-8") if held.is_file() else ""

	check("torch.glb exists", model.is_file(), f"{model.stat().st_size} bytes" if model.is_file() else "")
	check("preview scene exists", preview_scene.is_file())
	check("held scene exists", held.is_file())
	check("held has OmniLight", "OmniLight3D" in held_text)
	light = (ROOT / "scripts/items/torch_light.gd").read_text(encoding="utf-8")
	held_script = (ROOT / "scripts/items/torch_held.gd").read_text(encoding="utf-8")
	fire = (ROOT / "scripts/items/torch_fire.gd").read_text(encoding="utf-8")
	check("shared torch_light", "ENERGY" in light and "ATTENUATION" in light and "static func apply" in light)
	check("shared torch_fire", "GPUParticles3D" in fire and "color_ramp" in fire and "BLEND_MODE_ADD" in fire)
	check("held applies fire", "TorchFire.apply" in held_script)
	check("placed applies fire", "TorchFire.apply" in torch_script)
	check("soft falloff", "ATTENUATION := 2.4" in light and "ENERGY := 0.9" in light and "RANGE := 8.5" in light)
	check("torch shadows enabled", "shadow_enabled = true" in light and "SHADOW_CUBE" in light)
	check("torch shadow bias", "SHADOW_BIAS" in light and "distance_fade_enabled = true" in light)
	check("held applies shared light", "torch_light.gd" in held_script and "TorchLight.apply" in held_script)
	stylized = (ROOT / "shaders/stylized.gdshader").read_text(encoding="utf-8")
	check("stylized respects ATTENUATION", "LIGHT_COLOR * atten" in stylized and "return" not in stylized.split("void light()")[-1])
	check("held scene uses torch_held", "torch_held.gd" in held_text)
	check("placed script exists", (ROOT / "scripts/machines/torch.gd").is_file())
	check("placed harvestable", "harvestable.gd" in torch_script and 'add_to_group(&"machine")' in torch_script)
	check("placed OmniLight", "OmniLight3D" in torch_script and "TorchLight.apply" in torch_script)
	check("preview embeds torch.glb", "torch.glb" in preview_text)
	check("recipe torch", '"result_id": "torch"' in recipes)
	check("result_amount 10", '"result_id": "torch"' in recipes and '"result_amount": 10' in recipes)
	check("cost sticks 10 charcoal 2", '"sticks": 10' in recipes and '"charcoal": 2' in recipes)
	check("use torch not place", '"torch": "torch"' in recipes and '"torch": "place"' not in recipes)
	check("placeable_script torch", 'resource_id == "torch"' in recipes and "TORCH_SCRIPT" in recipes)
	check("tool_scenes torch", '"torch"' in tools and "scenes/items/torch.tscn" in tools)
	check("player place torch", "_try_place_torch" in player_tools and "_use_torch" in player_tools)
	check("consume on success", 'add_resource", "torch", -1)' in player_tools or 'add_resource", "torch", -1' in player_tools)
	check("surface attach", "_can_attach_torch" in player_tools and "_basis_from_normal" in player_tools)
	check("save machine id", 'ends_with("torch.gd")' in session)
	check("preview MODELS", "torch.glb" in previews and '"torch"' in previews)
	check("icon torch", '"torch"' in icons and "_draw_torch" in icons)
	check("locale ITEM_TORCH", "ITEM_TORCH" in locale)

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())

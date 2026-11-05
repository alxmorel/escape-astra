#!/usr/bin/env python3
"""Validation hors-moteur : UI four éditable."""

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
	scene = ROOT / "scenes/ui/furnace_panel.tscn"
	script = ROOT / "scripts/ui/furnace_panel.gd"
	furnace = ROOT / "scripts/machines/furnace.gd"
	scene_text = scene.read_text(encoding="utf-8") if scene.is_file() else ""
	script_text = script.read_text(encoding="utf-8") if script.is_file() else ""
	furnace_text = furnace.read_text(encoding="utf-8") if furnace.is_file() else ""
	hud = (ROOT / "scripts/ui/hud.gd").read_text(encoding="utf-8")
	interact = (ROOT / "scripts/player/player_interact.gd").read_text(encoding="utf-8")
	locale = (ROOT / "locale/game.csv").read_text(encoding="utf-8")

	check("furnace_panel.tscn exists", scene.is_file())
	check("furnace_panel.gd exists", script.is_file())
	check("scene has ProgressBar", "CookProgress" in scene_text and "ProgressBar" in scene_text)
	check("scene has InputSlot FuelSlot ResultSlot", all(x in scene_text for x in ("InputSlot", "FuelSlot", "ResultSlot")))
	check("scene uses item_slot.gd", "item_slot.gd" in scene_text)
	check("scene PanelContainer layout", "PanelContainer" in scene_text and "PlayerGrid" in scene_text)
	check("script open/close", "func open(" in script_text and "func close(" in script_text)
	check("script set_cook_progress hook", "func set_cook_progress" in script_text)
	check("furnace storage 3 slots", "SLOT_COUNT := 3" in furnace_text and "ItemContainer" in furnace_text)
	check("furnace open_ui", "func open_ui" in furnace_text)
	check("furnace cook hooks", "can_accept_fuel" in furnace_text and "cook_tick" in furnace_text and "get_cook_progress" in furnace_text)
	check("hud open_furnace", "open_furnace" in hud and "furnace_panel.tscn" in hud)
	check("interact open_ui", 'open_ui' in interact)
	check("locale FURNACE_*", "FURNACE_INPUT" in locale and "FURNACE_FUEL" in locale and "FURNACE_RESULT" in locale)
	check("smelt wood charcoal", "SMELT_RECIPES" in furnace_text and "wood" in furnace_text)

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())

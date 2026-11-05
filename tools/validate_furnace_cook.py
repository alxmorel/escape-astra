#!/usr/bin/env python3
"""Validation hors-moteur : recette charbon (10 s, fuel bois 50 %)."""

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
	furnace = (ROOT / "scripts/machines/furnace.gd").read_text(encoding="utf-8")
	panel = (ROOT / "scripts/ui/furnace_panel.gd").read_text(encoding="utf-8")
	player = (ROOT / "scripts/player/player.gd").read_text(encoding="utf-8")
	interact = (ROOT / "scripts/player/player_interact.gd").read_text(encoding="utf-8")
	hud = (ROOT / "scripts/ui/hud.gd").read_text(encoding="utf-8")

	check("smelt wood->charcoal", "SMELT_RECIPES" in furnace and '"wood"' in furnace and '"charcoal"' in furnace)
	check("cook_seconds 10", "cook_seconds: float = 10.0" in furnace)
	check("fuel energy 1/4/8", '"wood": 1.0' in furnace and '"charcoal": 4.0' in furnace and '"coal": 8.0' in furnace)
	check("cook fuel cost 0.5", "COOK_FUEL_COST := 0.5" in furnace and "fuel_partial" in furnace)
	check("consume only on success", "_try_complete_cook" in furnace and "_can_output" in furnace)
	check("no early fuel consume", "_try_consume_fuel" not in furnace)
	check("progress bar sync", "_sync_progress_from_machine" in panel and "set_process(true)" in panel)
	check("RMB / Esc", "try_open_aimed_furnace" in interact and "ui_cancel" in hud)
	check("continues without UI", "_process" in furnace and "cook_tick" in furnace)

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())

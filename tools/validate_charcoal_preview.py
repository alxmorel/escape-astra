#!/usr/bin/env python3
"""Validation hors-moteur : preview 3D charbon de bois."""

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
	model = ROOT / "assets/models/Charcoal.glb"
	preview = ROOT / "scenes/ui/item_previews/charcoal.tscn"
	previews = (ROOT / "scripts/ui/item_preview_scenes.gd").read_text(encoding="utf-8")
	recipes = (ROOT / "scripts/resources/recipe_catalog.gd").read_text(encoding="utf-8")
	preview_text = preview.read_text(encoding="utf-8") if preview.is_file() else ""

	check("Charcoal.glb exists", model.is_file(), f"{model.stat().st_size} bytes" if model.is_file() else "")
	check("preview scene charcoal.tscn", preview.is_file())
	check("preview embeds Charcoal.glb", "Charcoal.glb" in preview_text)
	check("MODELS charcoal", '"charcoal"' in previews and "Charcoal.glb" in previews)
	check("coal preview separate", 'path_for' in previews)  # coal → coal.tscn quand ajouté
	check("no charcoal craft recipe", '"result_id": "charcoal"' not in recipes)
	check("charcoal name kept", '"charcoal": "Charcoal"' in recipes)

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())

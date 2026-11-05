#!/usr/bin/env python3
"""Validation hors-moteur : buissons procéduraux (buisson_01.glb)."""

from __future__ import annotations

import pathlib
import re
import struct
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


def glb_has_mesh(path: pathlib.Path) -> bool:
	data = path.read_bytes()
	if len(data) < 20 or data[0:4] != b"glTF":
		return False
	json_len = struct.unpack_from("<I", data, 12)[0]
	js = data[20 : 20 + json_len].decode("utf-8", "replace")
	return '"meshes"' in js and '"accessors"' in js


def main() -> int:
	model = ROOT / "assets/models/buisson_01.glb"
	flora = (ROOT / "scripts/world/planet_flora.gd").read_text(encoding="utf-8")
	planet = (ROOT / "scripts/world/planet_generator.gd").read_text(encoding="utf-8")
	agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")

	check("buisson_01.glb exists", model.is_file(), f"{model.stat().st_size} bytes" if model.is_file() else "")
	check("buisson_01 has mesh", model.is_file() and glb_has_mesh(model))
	check("BUSH_SCENE preload", "buisson_01.glb" in flora and "BUSH_SCENE" in flora)
	check("bush mesh from GLB", "_first_mesh(BUSH_SCENE)" in flora)
	check("flora bush_density export", "var bush_density" in flora)
	check("flora bush_frequency export", "var bush_frequency" in flora)
	check("planet bush params", "bush_density" in planet and "bush_frequency" in planet)
	check("deterministic scatter seed", "world_seed" in flora and "kind * 97" in flora)
	check("bush kind 7 scatter", re.search(r"_scatter\(.*kind.*7|,\s*7\)", flora) is not None or ", 7)" in flora)
	check("slope gate for bushes", "kind == 7" in flora and "_slope_up" in flora)
	check("blockers include trees/iron/builds", "_collect_blockers" in flora and "construction" in flora and '"wood"' in flora)
	check("MultiMesh keep_material for bush", '"Bushes"' in flora and "keep_material" in flora)
	check("no cut_bushes save required", "cut_bush" not in flora)  # décor régénéré par seed
	check("AGENTS mentions bushes", "buisson" in agents.lower() or "bush" in agents.lower())

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())

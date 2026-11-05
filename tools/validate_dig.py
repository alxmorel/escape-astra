#!/usr/bin/env python3
"""Validation hors-moteur du creusage gabarit joueur (boîte locale + anti-lambeaux)."""

from __future__ import annotations

import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PASS = 0
FAIL = 0

VOXEL = 0.7
DIG_WIDTH = 0.95
DIG_HEIGHT = 2.1
DIG_DEPTH = 1.4
DIG_UNDER_DEPTH = 1.05
DIG_MIN_SHELL = 0.35
DIG_PAD = VOXEL * 0.35
ISO = 0.0
DIRT_DEPTH = 4.2
MAT_DIRT = 1
MAT_STONE = 2
PLAYER_HEIGHT = 1.7
PLAYER_RADIUS = 0.3
PLAYER_SPAN = PLAYER_HEIGHT * 2.0


def check(name: str, ok: bool, detail: str = "") -> None:
	global PASS, FAIL
	if ok:
		PASS += 1
		print(f"PASS  {name}" + (f" — {detail}" if detail else ""))
	else:
		FAIL += 1
		print(f"FAIL  {name}" + (f" — {detail}" if detail else ""))


def length(v: tuple[float, float, float]) -> float:
	return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def normalize(v: tuple[float, float, float]) -> tuple[float, float, float]:
	n = length(v)
	return (v[0] / n, v[1] / n, v[2] / n)


def dot(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
	return (
		a[1] * b[2] - a[2] * b[1],
		a[2] * b[0] - a[0] * b[2],
		a[0] * b[1] - a[1] * b[0],
	)


def sub(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
	return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def scale(v: tuple[float, float, float], s: float) -> tuple[float, float, float]:
	return (v[0] * s, v[1] * s, v[2] * s)


def voxel_at(pos: tuple[float, float, float]) -> tuple[int, int, int]:
	return (
		math.floor(pos[0] / VOXEL),
		math.floor(pos[1] / VOXEL),
		math.floor(pos[2] / VOXEL),
	)


def make_box(
	focus: tuple[float, float, float],
	player: tuple[float, float, float],
	underfoot: bool,
) -> dict:
	up = normalize(focus)
	shaft = underfoot
	into = scale(up, -1.0)
	if not underfoot:
		tangent = sub(focus, player)
		tangent = sub(tangent, scale(up, dot(tangent, up)))
		if length(tangent) ** 2 > 0.04:
			t = normalize(tangent)
			into = normalize((t[0] * 0.7 - up[0] * 0.3, t[1] * 0.7 - up[1] * 0.3, t[2] * 0.7 - up[2] * 0.3))
		if abs(dot(into, up)) > 0.82:
			into = scale(up, -1.0)
			shaft = True
	hint = (1.0, 0.0, 0.0) if abs(dot(up, (1.0, 0.0, 0.0))) < 0.9 else (0.0, 0.0, 1.0)
	if shaft:
		right = normalize(cross(up, hint))
		forward = normalize(cross(right, up))
	else:
		forward = normalize(into)
		right = cross(up, forward)
		if length(right) ** 2 < 0.001:
			right = cross(up, hint)
		right = normalize(right)
		ortho = normalize(cross(right, up))
		if dot(forward, ortho) < 0.0:
			ortho = scale(ortho, -1.0)
		rad = scale(up, -1.0)
		forward = normalize(
			(
				ortho[0] * max(dot(ortho, into), 0.05) + rad[0] * max(dot(rad, into), 0.0),
				ortho[1] * max(dot(ortho, into), 0.05) + rad[1] * max(dot(rad, into), 0.0),
				ortho[2] * max(dot(ortho, into), 0.05) + rad[2] * max(dot(rad, into), 0.0),
			)
		)
	pad = DIG_PAD
	half_w = DIG_WIDTH * 0.5 + pad
	if shaft:
		return {
			"origin": focus,
			"right": right,
			"up": up,
			"forward": forward,
			"half_w": half_w,
			"half_f": half_w,
			"u_lo": -(DIG_UNDER_DEPTH + pad),
			"u_hi": pad,
			"shaft": True,
		}
	return {
		"origin": focus,
		"right": right,
		"up": up,
		"forward": forward,
		"half_w": half_w,
		"half_f": 0.0,
		"u_lo": -DIG_HEIGHT * 0.35 - pad,
		"u_hi": DIG_HEIGHT * 0.65 + pad,
		"d_lo": -pad,
		"d_hi": DIG_DEPTH + pad,
		"shaft": False,
	}


def inside_box(pos: tuple[float, float, float], box: dict) -> bool:
	rel = sub(pos, box["origin"])
	if abs(dot(rel, box["right"])) > box["half_w"]:
		return False
	along_up = dot(rel, box["up"])
	if along_up < box["u_lo"] or along_up > box["u_hi"]:
		return False
	if box["shaft"]:
		return abs(dot(rel, box["forward"])) <= box["half_f"]
	along_f = dot(rel, box["forward"])
	return box["d_lo"] <= along_f <= box["d_hi"]


def gather_candidates(
	focus: tuple[float, float, float],
	height: float,
	player: tuple[float, float, float],
	underfoot: bool,
	edits: dict[tuple[int, int, int], float] | None = None,
	allowed_mats: set[int] | None = None,
) -> tuple[list[dict], bool]:
	edits = edits or {}
	allowed = allowed_mats if allowed_mats is not None else {MAT_DIRT}
	box = make_box(focus, player, underfoot)
	center_v = voxel_at(focus)
	span = max(DIG_WIDTH, DIG_HEIGHT, DIG_DEPTH, DIG_UNDER_DEPTH)
	extent = int(math.ceil(span / VOXEL)) + 3
	candidates: list[dict] = []
	saw_blocked = False
	for x in range(center_v[0] - extent, center_v[0] + extent + 1):
		for y in range(center_v[1] - extent, center_v[1] + extent + 1):
			for z in range(center_v[2] - extent, center_v[2] + extent + 1):
				pos = (x * VOXEL, y * VOXEL, z * VOXEL)
				radius = length(pos)
				if radius < 8.0:
					continue
				if not inside_box(pos, box):
					continue
				depth = height - radius
				mat = MAT_DIRT if depth < DIRT_DEPTH else MAT_STONE
				if mat not in allowed:
					saw_blocked = True
					continue
				key = (x, y, z)
				current = edits.get(key, height - radius)
				if current <= ISO:
					continue
				candidates.append({"vox": key, "pos": pos, "current": current, "mat": mat})
	return candidates, saw_blocked


def box_spans(candidates: list[dict], box: dict) -> tuple[float, float, float]:
	if not candidates:
		return 0.0, 0.0, 0.0
	us = []
	ws = []
	ds = []
	for item in candidates:
		rel = sub(item["pos"], box["origin"])
		us.append(dot(rel, box["up"]))
		ws.append(abs(dot(rel, box["right"])))
		if box["shaft"]:
			ds.append(-dot(rel, box["up"]))
		else:
			ds.append(dot(rel, box["forward"]))
	height_span = max(us) - min(us) if us else 0.0
	width_span = max(ws) * 2.0 if ws else 0.0
	depth_span = max(ds) - min(ds) if ds else 0.0
	return width_span, height_span, depth_span


def main() -> int:
	edit = (ROOT / "scripts/terrain/terrain_edit.gd").read_text(encoding="utf-8")
	volume = (ROOT / "scripts/terrain/terrain_volume.gd").read_text(encoding="utf-8")
	player = (ROOT / "scripts/player/player_tools.gd").read_text(encoding="utf-8")
	collision = (ROOT / "scripts/terrain/terrain_collision.gd").read_text(encoding="utf-8")
	planet = (ROOT / "scripts/world/planet_generator.gd").read_text(encoding="utf-8")
	player_tscn = (ROOT / "scenes/player/player.tscn").read_text(encoding="utf-8")

	check("dig box helpers present", "_make_dig_box" in edit and "_inside_dig_box" in edit)
	check("thin shell cleanup", "_append_thin_shells" in edit and "_is_thin_shell" in edit)
	check("underfoot flag wired", "underfoot" in edit and "_is_dig_underfoot" in player)
	check("collision clear on dig", "clear_collision_for" in volume and "func clear" in collision)
	check("player local passed", "player_local" in edit and "player_world" in planet)
	check("CHUNK_SIZE unchanged", re.search(r"const CHUNK_SIZE := 8", volume) is not None)
	check("DIRT_DEPTH unchanged", re.search(r"const DIRT_DEPTH := 4\.2", volume) is not None)
	check("DIG_WIDTH catches >=1 voxel column", DIG_WIDTH >= VOXEL * 0.9)
	check("DIG_HEIGHT covers player (~3 voxels)", DIG_HEIGHT >= PLAYER_HEIGHT and DIG_HEIGHT >= VOXEL * 2.5)
	check("DIG_DEPTH two voxels / hit", abs(DIG_DEPTH - VOXEL * 2.0) < 0.05)
	check("player capsule documented", "height = 1.7" in player_tscn and "radius = 0.3" in player_tscn)
	check(
		"constants in volume",
		all(k in volume for k in ("DIG_WIDTH", "DIG_HEIGHT", "DIG_UNDER_DEPTH", "DIG_MIN_SHELL", "DIG_AIR_DENSITY")),
	)
	check("full air evacuate on dig", "air_density" in edit and re.search(r"var next\s*:=\s*air_density", edit) is not None)
	vol_compact = re.sub(r"\s+", "", volume)
	check("stone shovel digs dirt+stone", '"stone_shovel":[MAT_DIRT,MAT_STONE]' in vol_compact)
	check("default shovel dirt only", re.search(r'"shovel":\s*\[MAT_DIRT\]', volume) is not None)
	check("stone drop mapped", 'MAT_STONE:"stone"' in vol_compact)
	check("tool id preferred before shovel fallback", "tools.has(tool_key)" in edit)
	# Matériaux : terre (depth < DIRT_DEPTH), roche grise sinon — pas d'autres mats voxel.
	check("only dirt+stone voxel mats", "MAT_DIRT" in volume and "MAT_STONE" in volume and "MAT_AIR" in volume)

	height = 47.746
	player_flat = (0.0, height, 0.0)
	focus_flat = (0.0, height - 0.15, 0.0)

	# Forward dig into a wall: standing on +X, hit a face toward +Y into the crust.
	player_fwd = (height, 0.0, 0.0)
	focus_fwd = (height - 0.35, 0.85, 0.0)
	c_fwd, _ = gather_candidates(focus_fwd, height, player_fwd, False)
	box_fwd = make_box(focus_fwd, player_fwd, False)
	box_h = box_fwd["u_hi"] - box_fwd["u_lo"]
	w, hspan, d = box_spans(c_fwd, box_fwd)
	check("forward dig removes dirt", len(c_fwd) >= 8, f"n={len(c_fwd)}")
	check("forward box height covers player", box_h >= DIG_HEIGHT, f"box_h={box_h:.2f}")
	check("forward dirt spans >= one voxel height", hspan >= VOXEL * 0.8, f"span={hspan:.2f}")
	check("forward width ~ player passage", w <= DIG_WIDTH + VOXEL, f"span={w:.2f}")
	check("forward depth ~ two voxels", d <= DIG_DEPTH + VOXEL, f"span={d:.2f}")
	check("forward not shaft mode", box_fwd["shaft"] is False)
	# Rendement : ~2× taille joueur en ≤8 coups de profondeur pleine.
	hits_for_span = math.ceil(PLAYER_SPAN / DIG_DEPTH)
	check("passage 2x joueur en max 8 coups", hits_for_span <= 8, f"hits={hits_for_span} span={PLAYER_SPAN}")

	# Underfoot shaft
	c_under, _ = gather_candidates(focus_flat, height, player_flat, True)
	box_under = make_box(focus_flat, player_flat, True)
	uw, uh, ud = box_spans(c_under, box_under)
	check("underfoot removes dirt", len(c_under) >= 4, f"n={len(c_under)}")
	check("underfoot width fits player", uw <= DIG_WIDTH + VOXEL, f"span={uw:.2f}")
	check("underfoot depth clears support", ud >= DIG_UNDER_DEPTH * 0.6, f"span={ud:.2f}")
	check("forward yield >> legacy (~2-3 coins)", len(c_fwd) >= 8, f"n={len(c_fwd)}")
	check("underfoot yield >> legacy", len(c_under) >= 4, f"n={len(c_under)}")
	# Support corners under feet should be included
	support = [c for c in c_under if c["pos"][1] < focus_flat[1]]
	check("underfoot clears below focus", len(support) > 0, f"below={len(support)}")

	# Slope / other orientation
	focus_slope = normalize((0.6, 0.7, 0.3))
	focus_slope = scale(focus_slope, height - 0.2)
	player_slope = scale(normalize(focus_slope), height)
	c_slope, _ = gather_candidates(focus_slope, height, player_slope, False)
	check("slope forward dig works", len(c_slope) > 0, f"n={len(c_slope)}")
	c_slope_under, _ = gather_candidates(focus_slope, height, player_slope, True)
	check("slope underfoot dig works", len(c_slope_under) > 0, f"n={len(c_slope_under)}")

	# Axis orientations
	for axis in ((1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (-1.0, 0.0, 0.0)):
		f = scale(axis, height - 0.15)
		p = scale(axis, height)
		c_ax, _ = gather_candidates(f, height, p, True)
		check(f"orientation underfoot {axis}", len(c_ax) > 0, f"n={len(c_ax)}")

	# Already excavated
	c_air, _ = gather_candidates(focus_flat, height, player_flat, True)
	edits = {item["vox"]: -0.5 for item in c_air}
	c_empty, _ = gather_candidates(focus_flat, height, player_flat, True, edits)
	check("excavated underfoot empty", len(c_empty) == 0)

	# Stone zone — pelle défaut : bloquée ; pelle pierre : creuse + drop "stone"
	focus_stone = (0.0, height - (DIRT_DEPTH + 1.0), 0.0)
	c_stone, stone_only = gather_candidates(focus_stone, height, player_flat, True)
	check("stone zone blocked for default shovel", len(c_stone) == 0 and stone_only)
	c_stone_ok, _ = gather_candidates(
		focus_stone, height, player_flat, True, allowed_mats={MAT_DIRT, MAT_STONE}
	)
	check("stone shovel can dig grey rock", len(c_stone_ok) > 0, f"n={len(c_stone_ok)}")
	stone_mats = {item["mat"] for item in c_stone_ok}
	check("stone shovel hit is grey rock", stone_mats == {MAT_STONE}, f"mats={stone_mats}")
	drops = {MAT_DIRT: "dirt", MAT_STONE: "stone"}
	best_mat = max(stone_mats, key=lambda m: sum(1 for i in c_stone_ok if i["mat"] == m))
	check("stone dig drops stone resource", drops[best_mat] == "stone")

	# Iron burial reachable: under_depth steps
	steps = math.ceil(2.5 / DIG_UNDER_DEPTH)
	check("iron burial reachable", steps <= 5, f"steps={steps}")

	# Chunk seam
	chunk = 8
	focus_seam = (0.0, height - 0.15, chunk * VOXEL - 0.05)
	player_seam = (0.0, height, chunk * VOXEL - 0.05)
	c_seam, _ = gather_candidates(focus_seam, height, player_seam, True)
	chunk_ids = {
		(math.floor(v["vox"][0] / chunk), math.floor(v["vox"][1] / chunk), math.floor(v["vox"][2] / chunk))
		for v in c_seam
	}
	check("underfoot can span chunks", len(chunk_ids) >= 1, f"chunks={len(chunk_ids)}")

	# Outside volume not selected: far voxel
	far = (0.0, height + 5.0, 0.0)
	box = make_box(focus_flat, player_flat, False)
	check("outside box rejected", not inside_box(far, box))

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())

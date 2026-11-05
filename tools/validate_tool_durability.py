#!/usr/bin/env python3
"""Validation hors-moteur : durabilité des outils."""

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
	cfg = (ROOT / "scripts/items/tool_durability.gd").read_text(encoding="utf-8")
	bag = (ROOT / "scripts/inventory/slot_bag.gd").read_text(encoding="utf-8")
	caps = (ROOT / "scripts/inventory/capacities.gd").read_text(encoding="utf-8")
	inv = (ROOT / "scripts/player/inventory.gd").read_text(encoding="utf-8")
	tools = (ROOT / "scripts/player/player_tools.gd").read_text(encoding="utf-8")
	slot = (ROOT / "scripts/ui/item_slot.gd").read_text(encoding="utf-8")
	ops = (ROOT / "scripts/inventory/slot_stack_ops.gd").read_text(encoding="utf-8")
	cursor = (ROOT / "scripts/inventory/cursor_stack.gd").read_text(encoding="utf-8")

	check("config MAX present", "const MAX" in cfg and "wooden_pickaxe" in cfg and "iron_pickaxe" in cfg)
	check("wear per use", "WEAR_PER_USE" in cfg)
	check("tools stack limit 1", "has_durability" in caps and "return 1" in caps)
	check("slot_durability array", "slot_durability" in bag and "wear_at" in bag)
	check("export durability", '"slot_durability"' in bag)
	check("inventory wear API", "wear_selected_tool" in inv and "can_use_selected_tool" in inv)
	check("tools wear on use", "_wear_selected_tool" in tools and "_tool_usable" in tools)
	check("UI durability bar", "_dur_fill" in slot and "Durabilité" in slot)
	check("cursor carries durability", "var durability" in cursor and "item_durability" in cursor)
	check("ops pass durability", "cursor_dur" in ops and "slot_dur" in ops)

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())

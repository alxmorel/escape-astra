# Escape Astra — carte IA

Survival / crafting / building en **Godot 4** (4.7). Scripts sous `scripts/`, scènes sous `scenes/`. Réponses utilisateur en **français**.

## Boot

1. Autoloads : `Settings`, `SaveManager`, `AudioManager`
2. Scène principale : `scenes/ui/main_menu.tscn`
3. Nouvelle partie / charger → `scenes/world/test_planet.tscn` (`world_session.gd`)
4. Monde instancie `Player` + `HUD` ; `Planet` / Flora / météo / ciel en nœuds dédiés
5. Quitter (pause) → `world_session.save_and_quit` → menu

## Domaines

| Dossier | Rôle | Fichiers clés |
|---------|------|----------------|
| `scripts/core/` | Session, settings, save | `settings.gd`, `save_manager.gd`, `world_session.gd` |
| `scripts/audio/` | Audio global (autoload) | `audio_manager.gd` |
| `scripts/ui/` | HUD + panneaux | `hud.gd` (orchestre), `hud_slot_session.gd`, `inventory_panel_view.gd`, `hotbar_view.gd`, `craft_catalog_view.gd`, `build_menu_view.gd`, `hud_vitals_view.gd`, `build_help_view.gd`, `cursor_ghost_view.gd`, `hud_chrome.gd`, `storage_panel.gd`, `furnace_panel.gd` + `scenes/ui/furnace_panel.tscn`, `item_slot.gd` |
| `scripts/inventory/` | Stacks, curseur, clics / drags | `slot_bag.gd`, `slot_stack_ops.gd`, `slot_pointer_session.gd`, `slot_inventory_adapter.gd` |
| `scripts/player/` | Joueur | `player.gd` (orchestre), `player_vitals.gd`, `player_build_mode.gd`, `player_tools.gd`, `player_locomotion.gd`, `player_interact.gd`, `inventory.gd` |
| `scripts/world/` | Planète, flore, météo | `planet_generator.gd`, `planet_height.gd`, `planet_hydro_network.gd` (drainage seed), `planet_flora.gd`, `planet_forest.gd`, `procedural_tree.gd`, `chopable_tree.gd`, `falling_tree_body.gd`, `planet_rocks.gd`, `weather_manager.gd`, `weather_profiles.gd`, `weather_debug_console.gd` |
| `scripts/terrain/` | Voxel, eau, meshing | `terrain_volume.gd` (façade), `terrain_edit.gd`, `terrain_stream.gd`, `terrain_collision.gd`, `terrain_mesh_job.gd`, `terrain_debug_overlay.gd`, `terrain_surface_build.gd`, `water_volume.gd` (voxels + flow), `water_hydro.gd`, `water_mesh_build.gd`, `ocean_surface.gd`, `marching_cubes.gd` |
| `scripts/storage/` | Conteneur coffre | `item_container.gd` (délègue à `SlotBag`) |
| `scripts/resources/` | Catalogues items / world drops | `recipe_catalog.gd`, `ground_item.gd`, `harvestable.gd` |
| `scripts/items/` | Outils main + arc | `tool_scenes.gd`, `bow_held.gd`, `arrow_projectile.gd` → `scenes/items/`, `scenes/projectiles/` |
| `scripts/building/` `farming/` `machines/` | Domaines jeu | pièces, culture, machines placeables (`furnace`, `flour_grinder`, `fermentation_tank`, `distillery` — pas d’UI usage V0) |
| `scripts/creatures/` | Faune | `astra_grazer` / `astra_dodo` (+ anim) ; pop. réutilisable `buffalo_population.gd` |

## Groupes

Hubs : `player`, `planet`, `hud`, `weather`, `farming`, `world_session`, `buffalo_population`.  
Entités : `construction`, `machine`, `harvestable`, `ground_item`, `farm_plot`, `safe_zone`, `creature`.

## Flux critiques

### Inventaire
- Données slots : `SlotBag` partagé par `inventory.gd` et `item_container.gd`.
- Ops UI : `SlotStackOps` + `SlotInventoryAdapter` + `SlotPointerSession`.
- Fantôme : `CursorGhostView` (layer 50) via `HudSlotSession` (orchestre `hud.gd`).
- Session slots / curseur / pending / pointer : `ui/hud_slot_session.gd` ; API HUD (`get_cursor_stack`, etc.) déléguée pour `storage_panel`.

### Coffre / hotbar
- Coffre layer 25 ; hotbar HUD layer 26 ; adapter joueur partagé.
- Maj+clic / Maj+glissé / double-clic par zone (voir décisions).

### Météo debug
- Console `/` : `weather_debug_console.gd` (enfant de `weather_manager`) ; profils / mesh nuages : `weather_profiles.gd`.
- Debug test : `/xray` (`on`/`off`) → terrain semi-transparent + marqueurs orange sur gisements `iron_ore` (`planet.set_xray`).
- Debug hydro : `/hydro` (`on`/`off`) → overlay lignes drainage + croix bassins (`planet_hydro_network`, calcul boot only ; pas d’eau ni carve V0).

### Terrain (modules)
- Façade : `terrain_volume.gd` (apply mesh, horizon, eau/océan, boot).
- Stream gather/enqueue/drop : `terrain_stream.gd`.
- Collision pump/update : `terrain_collision.gd`.
- Dig / flatten / plot_plane : `terrain_edit.gd` (dig radial + volume cible `DIG_TARGET_VOXELS`, statuts `ok|partial|empty|stone`).
- Job mesh async : `terrain_mesh_job.gd` (fill + WorkerThreadPool) → `terrain_surface_build.gd` → `marching_cubes.gd`.
- Overlay F3 : `terrain_debug_overlay.gd` (stats via `_debug_stats()`).
- Eau dynamique : `water_volume` (setup host/planet/voxel/chunk) + `ocean_surface` ; mer/lacs procéduraux `water_hydro` ; mesh chunks `water_mesh_build` ; flow/sources runtime ; save `water`/`springs` via `export_rows`/`export_springs`.

### Planète
- Façade : `planet_generator.gd` (springs, spawn props, API terrain).
- Height / crater / rocky : `planet_height.gd`.
- Herbe décorative (nœud `Flora`) : `planet_flora.gd` (`rebuild_grass`, vent, `cut_at`, `export_cuts`) ; buissons `buisson_01.glb` (MultiMesh, seed, `bush_density`/`bush_frequency`, pas de save dédié).
- Forêts / arbres : `chopable_tree` → `falling_tree_body` (même RigidBody chute + découpe au sol).
- Rochers récoltables / landmarks / cut rocks : `planet_rocks.gd` via `planet_generator` (`cut_rocks` dans save, miroir `cut_trees`).
- Gisements fer / charbon enfouis : `spawn_iron_deposit` / `spawn_coal_deposit` (`_spawn_*_deposits`, RNG dédiés, clés `iron_*` / `coal_*` dans `cut_rocks`) ; `skip_terrain_snap` ; récolte si `is_point_air` ; charbon plus dense (`coal_*` > `iron_*`).

### Pipeline items
1. **Identité / recettes / noms** : `recipe_catalog.gd` (`NAMES`, `USES`, `RECIPES`, `display_name`, `use_of`, placeable).
2. **Icônes HUD** : `item_icons.gd` (générées) ; fallback preview 3D : `build_preview.gd` + `item_preview_scenes.gd` → `scenes/ui/item_previews/`.
3. **Outil en main** : `tool_scenes.gd` → `scenes/items/*.tscn` (monté par `player.gd`).
4. **Farming visuals / nourriture** : `farming_config.gd` (`VISUALS`, `CROPS`, `FOODS`) ; stages `scenes/visuals/wheat_stage_*.tscn`.
5. **Sol** : `ground_item.gd` (groupe `ground_item`) ; spawn via harvestable / farming drops / démolition. **V0 :** non persistés entre sessions (session only).
6. **Slots** : id string + qty dans `SlotBag` ; pas d’objet Item runtime.

**Orphelins (ne pas supprimer sans confirmation)** : `scenes/visuals/farmland.tscn`, `wheat_wild.tscn`, `hoe.tscn` — non référencés ; `wheat_wild` runtime utilise `wheat_stage_5` via `farming_config.VISUALS`.

## Conventions

- Réutiliser `SlotBag` / `SlotStackOps` / adapters / session ; pas de logique inventaire parallèle.
- Stack max : `Capacities.MAX_STACK` (100) ; outils (`use: tool`) stack **1** + durabilité (`tool_durability.gd`, `slot_durability` dans `SlotBag` / save).
- Sources Blender (`.blend`) : `assets/blender_source/` + `.gdignore` — jamais sous `assets/models/` (Godot importe = PackedScene ; arbres monde = pièces `tronc_arbre`/`feuillage_*` via `procedural_tree`).
- Diff minimal ; mettre à jour ce fichier après changement de flux / chemin.

## Fichiers encore denses

`terrain/terrain_volume.gd`, `terrain/water_volume.gd`, `world/weather_manager.gd` (FX runtime) — façades OK ; splits optionnels seulement.

## Migration architecture

- **A–U** : découpe core/ui/player/terrain/water/planet (voir historique commits / chat).
- **V** : height → `planet_height.gd` ; rochers/landmarks → `planet_rocks.gd`
- **W** : profils météo + mesh nuages → `weather_profiles.gd`
- **Statut** : migration structurelle **terminée** ; pas de suite obligatoire.

## Dernières décisions

- Abattage : un seul `falling_tree_body` ; le segment de coupe devient la 1re bûche au sol (découpable) ; feuillage → RigidBody (gravité planétaire, 2 s) ; bounce hache sur segment frappé ; 1 `wood`/segment.
- Arbres procéduraux : `procedural_tree.gd` (`tronc_arbre` + `feuillage_01/02`, MultiMesh, seed) ; placement `planet_forest` inchangé.
- Eau dynamique restaurée : `WaterVolume` + `WaterHydro` + `water_mesh_build` + `OceanSurface` ; retiré `static_water` / `planet_water_gen`.
- Hydro debug : `planet_hydro_network` (drainage seed, boot) + `/hydro` ; distinct de l’eau voxel/océan runtime.
- `WaterVolume.contains_point` : niveau voxel ou `_is_ocean_cell` (pas de fallback `_below_sea`).
- Four : `wood`→`charcoal` 10 s ; fuel bûche=1 / charcoal=4 / coal=8 ; cuisson 0,5 via `fuel_partial`.
- Torches : craft ×10 ; `use: torch` ; OmniLight `torch_light.gd` ; LMB pose ; harvestable ; save machine.
- Buissons : `buisson_01.glb` via `planet_flora` MultiMesh ; `bush_density`/`bush_frequency`.
- Console `/xray` : terrain xray + marqueurs `iron_ore`.
- Craft / build : icônes ; coûts preview `have/need` ; nom tooltip.
- Creusage pelle : boîte (`DIG_WIDTH/HEIGHT/DEPTH`) ; `stone_shovel` → terre+roche.
- Gisements fer/charbon : params `iron_*`/`coal_*` ; items `iron_ore`/`coal`.
- Mort : totem proche sinon aléatoire ; `ground_item` non persisté V0.
- Arc `wooden_bow` : RMB visée ; bétail `astra_grazer` / `astra_dodo`.

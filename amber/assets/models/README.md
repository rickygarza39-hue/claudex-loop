# Model slots (drop-in 3D models)

Every model in Amber is requested by a **slot name**. If a file with that name exists in this folder, the game uses it instead of the built-in placeholder. Supported: `.glb`, `.gltf`, `.obj` (and `.tscn` if you want to build a scene in Godot).

## Using Forge (or any 3D tool)

1. Build the model in Forge. Kenney's **Asset Forge** exports glTF (`.glb` / `.gltf`) and OBJ, which Godot imports directly.
2. Export it, name the file after a slot below (for example `killer_brute.glb`), and copy it into `amber/assets/models/`.
3. Open (or re-focus) the project in Godot so it imports the file, then play. No code changes needed.

Conventions the game assumes:

- **Up is +Y; the model faces -Z** (Godot's forward). If a model faces the wrong way, rotate it in Forge before exporting.
- **Scale doesn't matter.** Each model is scaled so its height matches the slot's target size, centred on X/Z, with its lowest point on the ground.
- **Origin doesn't matter** for the same reason.
- Characters made in Forge won't have skeletons. They bob as they move instead of walking. If your glTF has an `AnimationPlayer` with animations, you can wire them in `scripts/actors/actor.gd` (`update_visual`).
- Walls and doors are 2 m wide (one map tile).

## Characters

| File name | Target height (m) | What it is |
|---|---|---|
| `survivor.glb` | 1.75 | Survivor, feet at origin, facing -Z |
| `killer_tracker.glb` | 1.95 | Tracker killer: lean, hunched, clawed |
| `killer_brute.glb` | 2.55 | Brute killer: huge tank |
| `killer_lurker.glb` | 2.2 | Lurker killer: tall, thin, long neck |
| `elite.glb` | 1.8 | Elite infected (turned survivor) |
| `husk.glb` | 1.6 | Swarm husk (AI infected) |

## Radio station, helicopter and terminals

| File name | Target height (m) | What it is |
|---|---|---|
| `station_base.glb` | 1.0 | Radio station crate/table (before stage 1) |
| `station_antenna.glb` | 6.0 | Radio stage 1: antenna mast |
| `station_generator.glb` | 1.3 | Radio stage 2: generator |
| `station_transmitter.glb` | 1.6 | Radio stage 3: transmitter with dish |
| `helicopter.glb` | 3.2 | Rescue helicopter (length about 11 m) |
| `shop_terminal.glb` | 1.9 | Company supply terminal |
| `nest.glb` | 2.0 | The Nest: amber heart of the infection |

## Items

| File name | Target height (m) | What it is |
|---|---|---|
| `part_cable.glb` | 0.5 | Cable spool |
| `part_fuel.glb` | 0.5 | Fuel can |
| `part_spark.glb` | 0.3 | Spark plug / battery |
| `part_circuit.glb` | 0.15 | Circuit board |
| `part_cell.glb` | 0.45 | Power cell |
| `part_dish.glb` | 0.6 | Radio dish |
| `cash.glb` | 0.3 | Cash lockbox |
| `scrap.glb` | 0.45 | Scrap pile |
| `flare_gun.glb` | 0.25 | Flare gun (knockdown item) |
| `trap_snare.glb` | 0.2 | Snare trap |
| `trap_flash.glb` | 0.3 | Flash trap |

## Base building

| File name | Target height (m) | What it is |
|---|---|---|
| `build_wall.glb` | 3.0 | Survivor-built wall section, 2 m wide |
| `build_door.glb` | 3.0 | Survivor-built door, 2 m wide |
| `build_barricade.glb` | 1.4 | Quick barricade |
| `build_alarm.glb` | 1.2 | Alarm post |
| `build_floodlight.glb` | 3.0 | Floodlight |
| `build_decoy.glb` | 0.6 | Noise decoy |
| `build_locker.glb` | 2.0 | Hiding locker |
| `build_hatch.glb` | 1.2 | Escape hatch |

## Props and set dressing

| File name | Target height (m) | What it is |
|---|---|---|
| `vehicle.glb` | 1.5 | Abandoned car or truck (length about 4 m) |
| `telegraph_pole.glb` | 7.0 | Telegraph pole |
| `lantern_post.glb` | 2.9 | Lantern on a post |
| `wall_lantern.glb` | 0.4 | Wall-mounted lantern |
| `mine_frame.glb` | 4.0 | Timber frame at a mine entrance |
| `watchtower_top.glb` | 4.0 | Watchtower cabin on stilts |
| `crate.glb` | 1.0 | Wooden crate |

The map itself (floors, walls, cliffs, roofs, tunnels) is generated from a grid each match, so it isn't a model slot. Its look comes from the procedural materials in `scripts/world/mats.gd`. You can swap any material there for textures (a `.png` albedo) exported from Forge or anywhere else.

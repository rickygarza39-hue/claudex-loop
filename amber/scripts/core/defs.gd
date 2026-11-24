class_name Defs
extends RefCounted
## Shared enums, names and colours. Numbers that need balancing live in Tuning.

const TILE := 2.0  # metres per grid tile

# ---- Map tiles ---------------------------------------------------------------
enum T {
	VOID,       # chasm: blocks movement, not sight
	FLOOR,
	WALL,
	WATER,      # walkable, slow
	GAP,        # squeeze gap: survivors only
	CLIFF,
	RAMP,
	BOARDS,     # boarded passage: killers can smash it open
	CELL_DOOR,  # quarantine cell door
	PROP,       # solid low prop (crate, vehicle, boulder)
	FENCE,      # low fence: blocks movement, not sight
	RUBBLE,     # collapsed tunnel (killer route edit)
	SEALED,     # sealed squeeze gap (killer route edit)
	TREE,       # tree trunk: blocks movement, not sight
}

enum Z { NONE, TOWN, SWAMP, FIELD, MINE, LAB, HIGH }
const ZONE_NAMES := ["?", "Town", "Swamp", "Fields", "Mines", "Flooded Lab", "High Ground"]

# Material styles
enum S {
	NONE, DIRT, MUD, GRASS, ROCK, LAB, WOOD, PLANK, METAL, CLIFF, QUARANTINE,
	CRATE, VEHICLE, BRIDGE, PLATEAU, BOULDER, FENCE, LABFLOOR, MINEFLOOR,
}

# Roof kinds
enum R { NONE, CEILING, ROOF }

# ---- Radio parts -------------------------------------------------------------
enum P { CABLE, FUEL, SPARK, CIRCUIT, CELL, DISH }
const PART_NAMES := ["Cable Spool", "Fuel Can", "Spark Plug", "Circuit Board", "Power Cell", "Radio Dish"]
const PART_HINTS := [
	"in town, near buildings and telegraph poles",
	"just inside the mine entrances",
	"in old vehicles",
	"in the flooded lab",
	"deep in the mine shafts",
	"on the watchtower and cliff edges",
]
const PART_COLORS := [
	Color(0.85, 0.55, 0.25), Color(0.85, 0.15, 0.12), Color(0.75, 0.75, 0.8),
	Color(0.2, 0.8, 0.4), Color(0.3, 0.6, 1.0), Color(0.9, 0.9, 0.95),
]
const STAGE_NAMES := ["Antenna", "Generator", "Transmitter"]
const STAGE_PARTS := [[P.CABLE], [P.FUEL, P.SPARK], [P.CIRCUIT, P.CELL, P.DISH]]

# ---- Sides, roles, killers ---------------------------------------------------
enum Side { SURVIVOR, KILLER }
enum Role { ENGINEER, MEDIC, TRAPPER }
const ROLE_NAMES := ["Engineer", "Medic", "Trapper"]
const ROLE_COLORS := [Color(0.95, 0.75, 0.2), Color(0.85, 0.95, 0.9), Color(0.35, 0.65, 0.95)]
const ROLE_BLURBS := [
	"Builds and repairs faster. Quick barricade (Q). Can upgrade walls to spiked or metal. Weak in fights; building is noisy.",
	"Heals faster. Revives a downed partner once. Scent mask spray (Q) hides survivors and trails from the Tracker. Builds slowly.",
	"Carries more traps and places them faster (Q). Snares hold killers; flash traps disorient them.",
]

enum K { TRACKER, BRUTE, LURKER }
const KILLER_NAMES := ["Tracker", "Brute", "Lurker"]
const KILLER_BLURBS := [
	"Stalk (RMB): invisible and fast, but blind to survivors — only tracks, blood and noise. Countered by the scent mask.",
	"Charge (RMB): smash through walls and knock survivors down. Turns badly, stunned on a miss, stopped by metal walls.",
	"Tongue (RMB): long-range grab that pulls a survivor in. No warning sound. Must stand still while pulling; weak once spotted.",
]

enum Health { HEALTHY, WOUNDED, DOWNED }
const HEALTH_NAMES := ["Healthy", "Wounded", "Downed"]

enum Item { PART, CASH, SCRAP, FLARE }

enum Trap { SNARE, FLASH }
const TRAP_NAMES := ["Snare", "Flash trap"]

enum Card { BLACKOUT, PULSE, SWARM, JAM }
const CARD_NAMES := ["Blackout", "Pulse", "Swarm", "Signal Jam"]
const CARD_BLURBS := [
	"Lights out. Survivor vision drops.",
	"Reveals every survivor for a few seconds.",
	"A wave of infected hits a chosen base.",
	"Pauses all radio progress briefly.",
]

# Buildable base structures
enum B { WALL, DOOR, BARRICADE, ALARM, FLOODLIGHT, DECOY, LOCKER, SNARE, FLASH, HATCH }
const BUILD_NAMES := ["Wall", "Door", "Barricade", "Alarm", "Floodlight", "Decoy", "Locker", "Snare", "Flash trap", "Escape hatch"]

# Elite skill branches per class
const ELITE_BRANCHES := [
	["Speed", "Senses", "Pack"],    # Tracker
	["Smash", "Tank", "Bully"],     # Brute
	["Vents", "Traps", "Disguise"], # Lurker
]
const ELITE_BRANCH_BLURBS := {
	"Speed": "+6% move speed per rank",
	"Senses": "See trails and hear noise from further away",
	"Pack": "Nearby killers move 3% faster per rank",
	"Smash": "Break structures 35% faster per rank",
	"Tank": "Stuns and traps hold you 20% shorter per rank",
	"Bully": "Your hits slow survivors briefly",
	"Vents": "Rank 1+: squeeze through survivor gaps",
	"Traps": "Spot survivor traps from further away; disarm faster",
	"Disguise": "Survivors' bots mistake you for a survivor at range",
}

const DUO_COLORS := [
	Color(0.95, 0.35, 0.3), Color(0.35, 0.8, 0.95), Color(0.6, 0.95, 0.35),
	Color(0.95, 0.85, 0.3), Color(0.8, 0.5, 0.95),
]
const DUO_NAMES := ["Red", "Blue", "Green", "Yellow", "Violet"]

const AMBER := Color(1.0, 0.58, 0.12)

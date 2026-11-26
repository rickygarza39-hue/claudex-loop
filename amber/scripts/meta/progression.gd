class_name Progression
extends RefCounted
## Between-match progression, kept in a profile on this computer.
##
## - Every match pays out Amber (points) for what you did, win or lose.
## - Lifetime Amber raises your level along a reward track: each level gives a
##   bonus, and some levels add loadout slots.
## - Amber buys ranks in Diablo-style skill trees: one shared Survivor Kit tree
##   (it unlocks the items you can carry), one tree per survivor role and one per
##   killer. Each tree has three branches of four tiers; a tier opens once you
##   have spent enough points in that tree, and the last tier holds the capstones.
## - Items are no longer bought in a match. You pick them before it, in your loadout.

const SAVE_PATH := "user://amber_profile.json"
const TIER_GATE := [0, 2, 5, 9]          # ranks spent in a tree to open tiers 1..4
const SLOT_LEVELS := [1, 3, 8]           # account levels that give loadout slots 1..3
const LEVEL_BONUS := 250                 # Amber paid out on every level up
const START_AMBER := 800                 # a new profile's starting balance
const RESPEC_REFUND := 0.8

const ITEMS := {
	"flare": {"name": "Flare gun", "unlock": "flare_gun", "desc": "Knocks a killer down. LMB with tool 1."},
	"medkit": {"name": "Medkit", "unlock": "medkit", "desc": "Heal yourself from wounded at once. Tool 4."},
	"cure": {"name": "Cure", "unlock": "cure", "desc": "Saves a downed survivor from turning. Hold E on them."},
	"traps": {"name": "Trap kit", "unlock": "trap_kit", "desc": "+1 snare and +1 flash trap."},
	"scanner": {"name": "Part scanner", "unlock": "scanner", "desc": "Shows the nearest parts your radio needs. Tool 5."},
}

## Tree definitions. Each node: [id, name, tier, ranks, stat, per_rank, description]
## {v} in a description is the node's total at its next rank, {p} the same as a percentage.
const TREES := {
	"kit": {"name": "Survivor Kit", "side": "survivor", "branches": [
		["Arsenal", [
			["flare_gun", "Flare Gun", 1, 1, "unlock", 1.0, "Unlocks the flare gun for your loadout."],
			["phosphor", "Phosphor Rounds", 2, 3, "flare_stun", 0.5, "Flare knockdowns last +{v} s."],
			["trap_kit", "Trap Kit", 3, 1, "unlock", 1.0, "Unlocks the trap kit for your loadout."],
			["second_barrel", "Second Barrel", 4, 1, "flare_count", 1.0, "Your flare gun holds {v} more shot."],
		]],
		["Remedies", [
			["medkit", "Medkit", 1, 1, "unlock", 1.0, "Unlocks the medkit for your loadout."],
			["dressing", "Field Dressing", 2, 3, "heal", 0.10, "Heal, revive and cure {p} faster."],
			["cure", "The Cure", 3, 1, "unlock", 1.0, "Unlocks the cure for your loadout."],
			["stubborn", "Stubborn Blood", 4, 2, "turn", 15.0, "+{v} s before you turn when downed."],
		]],
		["Scavenger", [
			["scanner", "Part Scanner", 1, 1, "unlock", 1.0, "Unlocks the part scanner for your loadout."],
			["keen_eyes", "Keen Eyes", 2, 3, "spot", 0.12, "Spot items {p} further away."],
			["stash", "Hidden Stash", 3, 3, "money", 15.0, "Your duo starts with +${v} for building."],
			["pack_rat", "Pack Rat", 4, 2, "scrap", 2.0, "Your duo starts with +{v} scrap."],
		]],
	]},
	"engineer": {"name": "Engineer", "side": "survivor", "branches": [
		["Fortify", [
			["steady_hands", "Steady Hands", 1, 3, "build", 0.06, "Build and repair {p} faster."],
			["quick_brace", "Quick Brace", 2, 3, "ability_cd", 0.10, "Barricade cooldown {p} shorter."],
			["salvager", "Salvager", 3, 2, "scrap", 2.0, "Your duo starts with +{v} scrap."],
			["master_builder", "Master Builder", 4, 1, "build", 0.20, "Build and repair another {p} faster."],
		]],
		["Tinker", [
			["lockbreaker", "Lockbreaker", 1, 3, "pick", 0.12, "Pick locks and work levers {p} faster."],
			["rigged", "Rigged", 2, 2, "trap_cap", 1.0, "Carry {v} more of each trap."],
			["sparks", "Sparks", 3, 3, "flare_stun", 0.4, "Flare knockdowns last +{v} s."],
			["contractor", "Contractor", 4, 2, "money", 30.0, "Your duo starts with +${v}."],
		]],
		["Grit", [
			["light_step", "Light Step", 1, 3, "quiet", 0.08, "Running makes {p} less noise."],
			["sprinter", "Sprinter", 2, 3, "move", 0.025, "Move {p} faster."],
			["deflect", "Deflect", 3, 2, "parry", 0.03, "Parry window +{v} s."],
			["last_stand", "Last Stand", 4, 1, "turn", 25.0, "+{v} s before you turn when downed."],
		]],
	]},
	"medic": {"name": "Medic", "side": "survivor", "branches": [
		["Mercy", [
			["gentle", "Gentle Hands", 1, 3, "heal", 0.08, "Heal, revive and cure {p} faster."],
			["triage", "Triage", 2, 3, "turn", 8.0, "+{v} s before you turn when downed."],
			["crawler", "Crawler", 3, 2, "crawl", 0.20, "Crawl {p} faster when downed."],
			["angel", "Angel of the Ward", 4, 1, "heal", 0.25, "Heal, revive and cure another {p} faster."],
		]],
		["Ghost", [
			["hush", "Hush", 1, 3, "quiet", 0.10, "Running makes {p} less noise."],
			["mask_master", "Mask Master", 2, 3, "ability_cd", 0.10, "Scent mask cooldown {p} shorter."],
			["wanderer", "Wanderer", 3, 3, "spot", 0.10, "Spot items {p} further away."],
			["phantom", "Phantom", 4, 1, "move", 0.06, "Move {p} faster."],
		]],
		["Nerve", [
			["composure", "Composure", 1, 3, "parry", 0.02, "Parry window +{v} s."],
			["adrenal", "Adrenal", 2, 3, "move", 0.02, "Move {p} faster."],
			["picklock", "Picklock", 3, 2, "pick", 0.15, "Pick locks {p} faster."],
			["unbroken", "Unbroken", 4, 1, "turn", 30.0, "+{v} s before you turn when downed."],
		]],
	]},
	"trapper": {"name": "Trapper", "side": "survivor", "branches": [
		["Snares", [
			["deep_pockets", "Deep Pockets", 1, 2, "trap_cap", 1.0, "Carry {v} more of each trap."],
			["quick_set", "Quick Set", 2, 3, "ability_cd", 0.10, "Trap drop cooldown {p} shorter."],
			["blinding", "Blinding Powder", 3, 3, "flare_stun", 0.5, "Flare knockdowns last +{v} s."],
			["killing_floor", "Killing Floor", 4, 1, "trap_cap", 2.0, "Carry {v} more of each trap."],
		]],
		["Stalk", [
			["soft_soles", "Soft Soles", 1, 3, "quiet", 0.10, "Running makes {p} less noise."],
			["tracker_eye", "Hunter's Eye", 2, 3, "spot", 0.12, "Spot items {p} further away."],
			["fleet", "Fleet", 3, 3, "move", 0.02, "Move {p} faster."],
			["vanish", "Vanish", 4, 1, "quiet", 0.25, "Running makes another {p} less noise."],
		]],
		["Wits", [
			["nimble", "Nimble Fingers", 1, 3, "pick", 0.12, "Pick locks {p} faster."],
			["reflex", "Reflex", 2, 3, "parry", 0.02, "Parry window +{v} s."],
			["handy", "Handy", 3, 3, "build", 0.06, "Build and repair {p} faster."],
			["survivalist", "Survivalist", 4, 1, "turn", 25.0, "+{v} s before you turn when downed."],
		]],
	]},
	"tracker": {"name": "The Tracker", "side": "killer", "branches": [
		["Hunt", [
			["long_legs", "Long Legs", 1, 3, "k_move", 0.02, "Move {p} faster."],
			["unseen", "Unseen", 2, 3, "stalk", 0.12, "Stalk {p} longer."],
			["restless", "Restless", 3, 3, "k_power", 0.08, "Power cooldown {p} shorter."],
			["apex", "Apex", 4, 1, "k_move", 0.05, "Move another {p} faster."],
		]],
		["Butcher", [
			["follow_through", "Follow Through", 1, 3, "k_recover", 0.08, "Recover from swings {p} faster."],
			["hooks", "Meat Hooks", 2, 3, "k_catch", 0.12, "Catch downed survivors {p} faster."],
			["wrecker", "Wrecker", 3, 3, "k_smash", 0.15, "Deal {p} more damage to walls and stations."],
			["frenzy", "Frenzy", 4, 1, "k_recover", 0.20, "Recover from swings another {p} faster."],
		]],
		["Iron", [
			["thick_skin", "Thick Skin", 1, 3, "k_stun", 0.08, "Stuns and knockdowns {p} shorter."],
			["second_wind", "Second Wind", 2, 3, "k_fatigue", 4.0, "Tire {v} s later in a chase."],
			["bloodhound", "Bloodhound", 3, 2, "k_power", 0.10, "Power cooldown {p} shorter."],
			["relentless", "Relentless", 4, 1, "k_stun", 0.20, "Stuns and knockdowns another {p} shorter."],
		]],
	]},
	"brute": {"name": "The Brute", "side": "killer", "branches": [
		["Rage", [
			["battering", "Battering Ram", 1, 3, "charge", 0.04, "Charge {p} faster."],
			["short_fuse", "Short Fuse", 2, 3, "k_power", 0.08, "Charge cooldown {p} shorter."],
			["momentum", "Momentum", 3, 3, "k_move", 0.02, "Move {p} faster."],
			["juggernaut", "Juggernaut", 4, 1, "charge", 0.10, "Charge another {p} faster."],
		]],
		["Siege", [
			["demolisher", "Demolisher", 1, 3, "k_smash", 0.15, "Deal {p} more damage to walls and stations."],
			["heavy_hands", "Heavy Hands", 2, 3, "k_recover", 0.08, "Recover from swings {p} faster."],
			["dragger", "Dragger", 3, 3, "k_catch", 0.12, "Catch downed survivors {p} faster."],
			["earthshaker", "Earthshaker", 4, 1, "k_smash", 0.35, "Deal another {p} damage to walls and stations."],
		]],
		["Hide", [
			["callous", "Callous", 1, 3, "k_stun", 0.08, "Stuns and knockdowns {p} shorter."],
			["endurance", "Endurance", 2, 3, "k_fatigue", 4.0, "Tire {v} s later in a chase."],
			["shrug", "Shrug It Off", 3, 2, "k_stun", 0.10, "Stuns and knockdowns another {p} shorter."],
			["unstoppable", "Unstoppable", 4, 1, "k_fatigue", 10.0, "Tire {v} s later in a chase."],
		]],
	]},
	"lurker": {"name": "The Lurker", "side": "killer", "branches": [
		["Tongue", [
			["reach", "Reach", 1, 3, "tongue", 0.06, "Tongue reaches {p} further."],
			["hungry", "Hungry", 2, 3, "k_power", 0.08, "Tongue cooldown {p} shorter."],
			["long_reach", "Long Reach", 3, 2, "tongue", 0.08, "Tongue reaches another {p} further."],
			["gullet", "Gullet", 4, 1, "k_power", 0.20, "Tongue cooldown another {p} shorter."],
		]],
		["Shadow", [
			["creep", "Creep", 1, 3, "k_move", 0.02, "Move {p} faster."],
			["crawlspace", "Crawlspace", 2, 3, "k_squeeze", 0.15, "Crawl through crevices {p} faster."],
			["patience", "Patience", 3, 3, "k_fatigue", 4.0, "Tire {v} s later in a chase."],
			["unseen_hunger", "Unseen Hunger", 4, 1, "k_move", 0.05, "Move another {p} faster."],
		]],
		["Feast", [
			["gorge", "Gorge", 1, 3, "k_catch", 0.12, "Catch downed survivors {p} faster."],
			["rending", "Rending", 2, 3, "k_recover", 0.08, "Recover from swings {p} faster."],
			["slick", "Slick", 3, 3, "k_stun", 0.08, "Stuns and knockdowns {p} shorter."],
			["glutton", "Glutton", 4, 1, "k_recover", 0.20, "Recover from swings another {p} faster."],
		]],
	]},
	"foreman": {"name": "The Foreman", "side": "killer", "branches": [
		["Quarry", [
			["heavy_swing", "Heavy Swing", 1, 3, "slam", 0.06, "Slam reaches {p} further."],
			["shift_change", "Shift Change", 2, 3, "k_power", 0.08, "Slam cooldown {p} shorter."],
			["cave_in", "Cave-in", 3, 3, "k_smash", 0.15, "Deal {p} more damage to walls and stations."],
			["foremans_word", "The Foreman's Word", 4, 1, "slam", 0.15, "Slam reaches another {p} further."],
		]],
		["Overtime", [
			["steel_toes", "Steel Toes", 1, 3, "k_move", 0.02, "Move {p} faster."],
			["double_shift", "Double Shift", 2, 3, "k_fatigue", 4.0, "Tire {v} s later in a chase."],
			["hardened", "Hardened", 3, 3, "k_stun", 0.08, "Stuns and knockdowns {p} shorter."],
			["no_breaks", "No Breaks", 4, 1, "k_fatigue", 10.0, "Tire {v} s later in a chase."],
		]],
		["Discipline", [
			["quick_hands", "Quick Hands", 1, 3, "k_recover", 0.08, "Recover from swings {p} faster."],
			["haul", "Haul", 2, 3, "k_catch", 0.12, "Catch downed survivors {p} faster."],
			["pick_master", "Pick Master", 3, 3, "k_recover", 0.06, "Recover from swings another {p} faster."],
			["layoffs", "Layoffs", 4, 1, "k_catch", 0.3, "Catch downed survivors another {p} faster."],
		]],
	]},
	"hollow": {"name": "The Hollow", "side": "killer", "branches": [
		["Crawl", [
			["long_skitter", "Long Skitter", 1, 3, "skitter", 0.1, "Skitter lasts {p} longer."],
			["restless_limbs", "Restless Limbs", 2, 3, "k_power", 0.08, "Skitter cooldown {p} shorter."],
			["crawlspace_h", "Crawlspace", 3, 3, "k_squeeze", 0.15, "Crawl through crevices {p} faster."],
			["endless", "Endless", 4, 1, "skitter", 0.3, "Skitter lasts another {p} longer."],
		]],
		["Hunger", [
			["gape", "Gape", 1, 3, "k_catch", 0.12, "Catch downed survivors {p} faster."],
			["rend", "Rend", 2, 3, "k_recover", 0.08, "Recover from swings {p} faster."],
			["gorge_h", "Gorge", 3, 3, "k_catch", 0.1, "Catch downed survivors another {p} faster."],
			["bottomless", "Bottomless", 4, 1, "k_recover", 0.2, "Recover from swings another {p} faster."],
		]],
		["Husk", [
			["numb", "Numb", 1, 3, "k_stun", 0.08, "Stuns and knockdowns {p} shorter."],
			["sinew", "Sinew", 2, 3, "k_move", 0.02, "Move {p} faster."],
			["tireless_h", "Tireless", 3, 3, "k_fatigue", 4.0, "Tire {v} s later in a chase."],
			["empty", "Empty", 4, 1, "k_stun", 0.2, "Stuns and knockdowns another {p} shorter."],
		]],
	]},
	"furnace": {"name": "The Furnace", "side": "killer", "branches": [
		["Blaze", [
			["kindling", "Kindling", 1, 3, "fire", 0.1, "Firebreak burns {p} longer."],
			["stoke", "Stoke", 2, 3, "k_power", 0.08, "Firebreak cooldown {p} shorter."],
			["white_heat", "White Heat", 3, 3, "fire", 0.1, "Firebreak burns another {p} longer."],
			["inferno", "Inferno", 4, 1, "k_power", 0.2, "Firebreak cooldown another {p} shorter."],
		]],
		["Slag", [
			["molten", "Molten", 1, 3, "k_smash", 0.15, "Deal {p} more damage to walls and stations."],
			["searing", "Searing", 2, 3, "k_recover", 0.08, "Recover from swings {p} faster."],
			["brand", "Brand", 3, 3, "k_catch", 0.12, "Catch downed survivors {p} faster."],
			["meltdown", "Meltdown", 4, 1, "k_smash", 0.35, "Deal another {p} damage to walls and stations."],
		]],
		["Cinder", [
			["ash_skin", "Ash Skin", 1, 3, "k_stun", 0.08, "Stuns and knockdowns {p} shorter."],
			["bellows", "Bellows", 2, 3, "k_fatigue", 4.0, "Tire {v} s later in a chase."],
			["heat_wave", "Heat Wave", 3, 3, "k_move", 0.02, "Move {p} faster."],
			["phoenix", "Phoenix", 4, 1, "k_stun", 0.2, "Stuns and knockdowns another {p} shorter."],
		]],
	]},
	"tally": {"name": "The Tally Man", "side": "killer", "branches": [
		["Count", [
			["one_step", "One Step Further", 1, 3, "blink", 0.08, "Blink {p} further."],
			["recount", "Recount", 2, 3, "k_power", 0.08, "Blink cooldown {p} shorter."],
			["long_count", "The Long Count", 3, 3, "blink", 0.08, "Blink another {p} further."],
			["zero", "Zero", 4, 1, "k_power", 0.2, "Blink cooldown another {p} shorter."],
		]],
		["Quarantine", [
			["sterile", "Sterile", 1, 3, "k_catch", 0.12, "Catch downed survivors {p} faster."],
			["procedure", "Procedure", 2, 3, "k_recover", 0.08, "Recover from swings {p} faster."],
			["isolation", "Isolation", 3, 3, "k_catch", 0.1, "Catch downed survivors another {p} faster."],
			["containment", "Containment", 4, 1, "k_recover", 0.2, "Recover from swings another {p} faster."],
		]],
		["Patience", [
			["slow_walk", "Slow Walk", 1, 3, "k_fatigue", 4.0, "Tire {v} s later in a chase."],
			["unmoved", "Unmoved", 2, 3, "k_stun", 0.08, "Stuns and knockdowns {p} shorter."],
			["long_stride", "Long Stride", 3, 3, "k_move", 0.02, "Move {p} faster."],
			["inevitable", "Inevitable", 4, 1, "k_move", 0.05, "Move another {p} faster."],
		]],
	]},
	"choir": {"name": "The Choir", "side": "killer", "branches": [
		["Hymn", [
			["crescendo", "Crescendo", 1, 3, "scream", 0.06, "Scream carries {p} further."],
			["encore", "Encore", 2, 3, "k_power", 0.08, "Scream cooldown {p} shorter."],
			["dissonance", "Dissonance", 3, 3, "scream", 0.08, "Scream carries another {p} further."],
			["requiem", "Requiem", 4, 1, "k_power", 0.2, "Scream cooldown another {p} shorter."],
		]],
		["Communion", [
			["many_hands", "Many Hands", 1, 3, "k_catch", 0.12, "Catch downed survivors {p} faster."],
			["chorus", "Chorus", 2, 3, "k_recover", 0.08, "Recover from swings {p} faster."],
			["congregation", "Congregation", 3, 3, "k_smash", 0.15, "Deal {p} more damage to walls and stations."],
			["one_voice", "One Voice", 4, 1, "k_catch", 0.3, "Catch downed survivors another {p} faster."],
		]],
		["Procession", [
			["march", "March", 1, 3, "k_move", 0.02, "Move {p} faster."],
			["vigil", "Vigil", 2, 3, "k_fatigue", 4.0, "Tire {v} s later in a chase."],
			["three_hearts", "Three Hearts", 3, 3, "k_stun", 0.08, "Stuns and knockdowns {p} shorter."],
			["amen", "Amen", 4, 1, "k_stun", 0.2, "Stuns and knockdowns another {p} shorter."],
		]],
	]},
}

static var profile := {}
static var loaded := false


# ------------------------------------------------------------------------------
# Profile

static func _new_profile() -> Dictionary:
	return {"version": 1, "amber": START_AMBER, "lifetime": 0, "level": 1, "matches": 0,
		"ranks": {"flare_gun": 1, "medkit": 1}, "loadout": ["flare", "", ""]}


static func ensure() -> void:
	if loaded:
		return
	loaded = true
	profile = _new_profile()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var data = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				for k in data:
					profile[k] = data[k]
	# JSON numbers come back as floats
	for k in ["amber", "lifetime", "level", "matches"]:
		profile[k] = int(profile[k])
	var r := {}
	for k in profile["ranks"]:
		r[k] = int(profile["ranks"][k])
	profile["ranks"] = r
	while profile["loadout"].size() < 3:
		profile["loadout"].append("")


## Test and recording runs (any command-line option) never touch the player's profile.
static func can_save() -> bool:
	return OS.get_cmdline_user_args().is_empty()


static func save() -> void:
	if not can_save():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(profile, "\t"))


static func amber() -> int:
	ensure()
	return profile["amber"]


# ------------------------------------------------------------------------------
# Levels (the reward track)

static func level_cost(lv: int) -> int:
	## Lifetime Amber needed to go from level lv to lv + 1.
	return 1000 + 250 * (lv - 1)


static func level_progress() -> Array:
	## [level, Amber into this level, Amber needed for the next]
	ensure()
	var lv := 1
	var rest: int = profile["lifetime"]
	while rest >= level_cost(lv):
		rest -= level_cost(lv)
		lv += 1
	return [lv, rest, level_cost(lv)]


static func loadout_slots() -> int:
	var lv: int = level_progress()[0]
	var n := 0
	for need in SLOT_LEVELS:
		if lv >= need:
			n += 1
	return n


# ------------------------------------------------------------------------------
# Trees

static func node_def(id: String) -> Array:
	for tid in TREES:
		for br in TREES[tid]["branches"]:
			for n in br[1]:
				if n[0] == id:
					return n
	return []


static func tree_of(id: String) -> String:
	for tid in TREES:
		for br in TREES[tid]["branches"]:
			for n in br[1]:
				if n[0] == id:
					return tid
	return ""


static func rank(id: String) -> int:
	ensure()
	return profile["ranks"].get(id, 0)


static func spent_in(tree_id: String) -> int:
	var total := 0
	for br in TREES[tree_id]["branches"]:
		for n in br[1]:
			total += rank(n[0])
	return total


static func rank_cost(n: Array, r: int) -> int:
	## Cost of buying rank r + 1 of node n.
	return int(200 * n[2] * (1.0 + 0.5 * r))


static func why_locked(id: String) -> String:
	var n := node_def(id)
	var tid := tree_of(id)
	if rank(id) >= n[3]:
		return "Maxed"
	var need: int = TIER_GATE[n[2] - 1]
	if spent_in(tid) < need:
		return "Spend %d points in this tree to open tier %d" % [need, n[2]]
	if amber() < rank_cost(n, rank(id)):
		return "Needs %d Amber" % rank_cost(n, rank(id))
	return ""


static func buy(id: String) -> String:
	var why := why_locked(id)
	if why != "":
		return why
	var n := node_def(id)
	profile["amber"] -= rank_cost(n, rank(id))
	profile["ranks"][id] = rank(id) + 1
	save()
	return ""


static func respec(tree_id: String) -> int:
	## Refunds most of what was spent in a tree. Returns the refund.
	var refund := 0
	for br in TREES[tree_id]["branches"]:
		for n in br[1]:
			for r in rank(n[0]):
				refund += rank_cost(n, r)
			profile["ranks"].erase(n[0])
	refund = int(refund * RESPEC_REFUND)
	profile["amber"] += refund
	# a refunded item can't stay in the loadout
	for i in profile["loadout"].size():
		if not item_unlocked(profile["loadout"][i]):
			profile["loadout"][i] = ""
	save()
	return refund


static func describe(n: Array, at_rank: int) -> String:
	var v: float = n[5] * max(1, at_rank)
	var vs := str(int(v)) if is_equal_approx(v, roundf(v)) else "%.2f" % v
	return n[6].replace("{v}", vs).replace("{p}", "%d%%" % roundi(v * 100.0))


## Summed stats from every node bought in these trees.
static func mods_for(tree_ids: Array) -> Dictionary:
	ensure()
	var out := {}
	for tid in tree_ids:
		for br in TREES[tid]["branches"]:
			for n in br[1]:
				var r := rank(n[0])
				if r > 0 and n[4] != "unlock":
					out[n[4]] = out.get(n[4], 0.0) + n[5] * r
	return out


static func survivor_tree(role: int) -> String:
	return ["engineer", "medic", "trapper"][role]


static func killer_tree(k: int) -> String:
	return ["tracker", "brute", "lurker", "foreman", "hollow", "furnace", "tally", "choir"][k]


# ------------------------------------------------------------------------------
# Loadout

static func item_unlocked(item: String) -> bool:
	return item != "" and ITEMS.has(item) and rank(ITEMS[item]["unlock"]) > 0


static func loadout() -> Array:
	ensure()
	var out: Array = []
	for i in loadout_slots():
		var it: String = profile["loadout"][i]
		if item_unlocked(it) and not out.has(it):
			out.append(it)
	return out


static func set_loadout(slot_i: int, item: String) -> void:
	ensure()
	profile["loadout"][slot_i] = item
	save()


# ------------------------------------------------------------------------------
# Match rewards

## Works out the Amber a human earned in a finished match and banks it.
## Returns {"lines": [[label, amount]], "total", "level_before", "level_after", "bonus"}.
static func award(mt: Match, s: Slot) -> Dictionary:
	ensure()
	var lines: Array = []
	lines.append(["Played a match", 250])
	var st := s.stats
	var t_end: float = s.outcome_time if s.outcome != "" else mt.time
	if s.duo != null:
		lines.append(["Time survived", mini(900, int(t_end / 2.0))])
		var stages: int = s.duo.base.stage if s.duo.base != null else 0
		if stages > 0:
			lines.append(["Radio stages built (%d)" % stages, 250 * stages])
		if st.get("earned", 0) > 0:
			lines.append(["Scavenging, saves and stuns", int(st["earned"]) * 2])
		if st.get("parries", 0) > 0:
			lines.append(["Perfect parries (%d)" % st["parries"], 100 * int(st["parries"])])
		if s.outcome == "escaped":
			lines.append(["ESCAPED", 1500])
	if st.get("assists", 0) > 0:
		lines.append(["Hits (%d)" % st["assists"], 120 * int(st["assists"])])
	if st.get("catches", 0) > 0:
		lines.append(["Catches (%d)" % st["catches"], 450 * int(st["catches"])])
	if st.get("elite_catches", 0) > 0:
		lines.append(["Catches as an elite (%d)" % st["elite_catches"], 250 * int(st["elite_catches"])])
	if s.duo == null and mt.result.get("killers_win", false):
		lines.append(["The killers won", 800])
	var total := 0
	for l in lines:
		total += l[1]
	var before: int = level_progress()[0]
	profile["amber"] += total
	profile["lifetime"] += total
	profile["matches"] += 1
	var after: int = level_progress()[0]
	var bonus := (after - before) * LEVEL_BONUS
	profile["amber"] += bonus
	profile["level"] = after
	save()
	return {"lines": lines, "total": total, "level_before": before, "level_after": after, "bonus": bonus}

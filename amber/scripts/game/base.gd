class_name Base
extends RefCounted
## A duo's base: the radio station, stored parts, structures and helicopter state.

var duo: Duo
var tile := Vector2i.ZERO
var pos := Vector2.ZERO
var stage := 0               # completed stages (0..3)
var progress := 0.0          # seconds of building toward the next stage
var paid := false            # money for the next stage already paid
var storage: Array = []      # stored part ids
var hp := Tuning.STATION_HP
var broken := false
var repair_progress := 0.0
var revealed := false        # killers know where it is (permanent: turned member, heli)
var reveal_until := -1.0     # temporary reveal
var gen_noise_t := 0.0
var structures: Array = []   # Structure
var hatch: Structure = null
var lockdown_until := -1.0
var heli: Node = null        # Heli
var heli_called := false
var heli_calls := 0
var node: Node3D = null      # station visual
var last_damage_time := -100.0
var exposed_until := -1.0    # revealed to killers by a turned member


func known_to_killers(now: float) -> bool:
	return revealed or now < reveal_until


func radius_m() -> float:
	return Tuning.BASE_RADIUS * Defs.TILE


func contains(p: Vector2) -> bool:
	return p.distance_to(pos) <= radius_m()


func next_parts() -> Array:
	if stage >= 3:
		return []
	return Defs.STAGE_PARTS[stage]


func missing_parts() -> Array:
	## Parts the next stage still needs that are not in storage.
	var need: Array = next_parts().duplicate()
	var have := storage.duplicate()
	var out: Array = []
	for p in need:
		var i := have.find(p)
		if i >= 0:
			have.remove_at(i)
		else:
			out.append(p)
	return out


func all_missing() -> Array:
	## Every part still needed for all remaining stages, minus storage.
	var need: Array = []
	for s in range(stage, 3):
		need.append_array(Defs.STAGE_PARTS[s])
	var have := storage.duplicate()
	var out: Array = []
	for p in need:
		var i := have.find(p)
		if i >= 0:
			have.remove_at(i)
		else:
			out.append(p)
	return out


func repair_cost() -> int:
	return Tuning.REPAIR_COST[clampi(stage - 1, 0, 2)]


func next_cost() -> int:
	if stage >= 3:
		return 0
	return Tuning.STAGE_COST[stage]


func complete() -> bool:
	return stage >= 3

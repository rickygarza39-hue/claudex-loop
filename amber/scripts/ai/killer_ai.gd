class_name KillerAI
extends RefCounted
## Bot killer / elite / husk: patrol, hunt by sight, sound and trails, chase,
## use the signature power, catch downed survivors, siege revealed bases.

var mt: Match
var k: Killer
var think_t := 0.0
var state := "patrol"
var target: Survivor = null
var last_seen := Vector2(INF, INF)
var last_seen_t := -100.0
var investigate := Vector2(INF, INF)
var investigate_t := -100.0
var patrol := Vector2(INF, INF)
var patrol_t := 0.0
var siege: Base = null
var stuck_t := 0.0
var last_pos := Vector2.ZERO
var route_cd := 0.0
var nest_cd := 0.0
var aggression := 0.5
var recent_victims := {}   # duo id -> time (mild anti-tunnel memory)
var goal_until := 0.0      # long-term goals (patrol / siege / guard) stick until this time
var chase_target: Survivor = null
var chase_since := 0.0
var ignore := {}           # Survivor -> time until which we leave them alone
var seen_since := {}       # Survivor -> time they first came into view (reaction delay)


func _init(match_ref: Match, killer: Killer) -> void:
	mt = match_ref
	k = killer
	think_t = mt.rng.randf() * 0.3
	aggression = mt.rng.randf_range(0.35, 0.8)


func think(dt: float) -> void:
	if not is_instance_valid(k) or not k.released:
		k.want_move = Vector2.ZERO
		return
	think_t -= dt
	route_cd -= dt
	nest_cd -= dt
	if think_t <= 0.0:
		think_t = 0.2
		_decide()
	_act(dt)


# ------------------------------------------------------------------------------
# Perception

func _can_see(s: Survivor) -> bool:
	if s.hidden_in != null:
		return false
	if k.stalking() and k.ktype == Defs.K.TRACKER:
		return false
	if mt.time < s.revealed_until:
		return true
	var r := Tuning.KILLER_SIGHT_CROUCHED if s.crouched() else Tuning.KILLER_SIGHT
	if k.elite or k.husk:
		r = minf(r, Tuning.ELITE_SIGHT)
	if k.elite and k.ktype == Defs.K.TRACKER:
		r += 2.0 * k.perk("Senses")
	if k.disoriented():
		r *= 0.4
	r *= mt.killer_bot_mult()["sight"]
	return mt.can_see(k, s, r)


func _visible_target() -> Survivor:
	var best: Survivor = null
	var best_score := INF
	for s in mt.living_survivors():
		if s.is_downed():
			continue
		if mt.time < ignore.get(s, -1.0):
			continue
		if not _can_see(s):
			seen_since.erase(s)
			continue
		if not seen_since.has(s):
			seen_since[s] = mt.time
		var react = Tuning.BOT_REACTION * (1.4 if k.elite or k.husk else 1.0) * mt.killer_bot_mult()["react"]
		if s != target and mt.time - seen_since[s] < react and s.pos.distance_to(k.pos) > 4.0 and mt.time >= s.revealed_until:
			continue
		var d = s.pos.distance_to(k.pos)
		var score = d
		if s.health == Defs.Health.WOUNDED:
			score -= 4.0
		if s == target:
			score -= 6.0
		if s.pinned_by != null and s.pinned_by != k:
			score -= 3.0
		score += 6.0 if mt.time - recent_victims.get(s.duo.id, -999.0) < 60.0 else 0.0
		if k.husk and k.swarm_base != null and s.pos.distance_to(k.swarm_base.pos) > 30.0:
			score += 30.0
		if score < best_score:
			best_score = score
			best = s
	return best


func _downed_near() -> Survivor:
	if k.husk or (k.elite and not Tuning.ELITES_CAN_CATCH):
		return null
	var best: Survivor = null
	var bd := 16.0
	for s in mt.living_survivors():
		if not s.is_downed():
			continue
		var d = s.pos.distance_to(k.pos)
		if d < bd and (d < 3.0 or mt.can_see(k, s, 16.0) or s.downed_by == k):
			# another killer is already catching it
			var taken := false
			for o in mt.killers:
				if o != k and not o.channel.is_empty() and o.channel.get("id") == "catch" and o.channel.get("target") == s:
					taken = true
			if not taken:
				bd = d
				best = s
	return best


func _heard() -> Vector2:
	var best := Vector2(INF, INF)
	var bscore := -INF
	var range_mult := 1.0 + 0.25 * k.perk("Senses")
	for n in mt.noises:
		if mt.time - n["t"] > 2.5:
			continue
		var src = n["src"]
		if src is Killer:
			continue
		var d: float = n["pos"].distance_to(k.pos)
		if d > n["r"] * range_mult:
			continue
		var score: float = -d + (mt.time - n["t"]) * -4.0
		if n["kind"] in ["build", "steal", "generator", "smash", "scream", "flare", "alarm"]:
			score += 15.0
		if n["kind"] == "decoy":
			score += 8.0
		if score > bscore:
			bscore = score
			best = n["pos"]
	return best


func _trail_next() -> Vector2:
	## Tracker: follow the freshest footprints near us.
	var best := Vector2(INF, INF)
	var bt := -INF
	var r := 11.0 + 3.0 * k.perk("Senses")
	for tr in mt.trails:
		var s: Survivor = tr["s"]
		if not is_instance_valid(s) or s.slot.outcome != "" or s.masked():
			continue
		var d: float = tr["pos"].distance_to(k.pos)
		if d > r or d < 1.2:
			continue
		if tr["t"] > bt:
			bt = tr["t"]
			best = tr["pos"]
	return best


# ------------------------------------------------------------------------------

func _decide() -> void:
	if k.stunned() or k.held():
		return
	if k.atk_state != "" or k.power_state in ["charge_windup", "charge", "tongue_fly", "tongue_pull"]:
		return
	_maybe_nest()
	var downed := _downed_near()
	var vis := _visible_target()
	if downed != null and (vis == null or vis.pos.distance_to(k.pos) > downed.pos.distance_to(k.pos) - 6.0 or mt.rng.randf() < 0.7):
		state = "catch"
		target = downed
		return
	if vis != null:
		if vis != chase_target:
			chase_target = vis
			chase_since = mt.time
		elif mt.time - chase_since > Tuning.BOT_CHASE_GIVEUP * mt.killer_bot_mult()["giveup"] and mt.time - k.last_hit_time > Tuning.BOT_CHASE_GIVEUP * mt.killer_bot_mult()["giveup"]:
			# a long chase going nowhere: drop it and pressure someone else
			ignore[vis] = mt.time + 25.0
			chase_target = null
			state = "patrol"
			patrol = _patrol_point()
			goal_until = mt.time + 15.0
			return
		target = vis
		last_seen = vis.pos
		last_seen_t = mt.time
		state = "chase"
		return
	if target != null and (not is_instance_valid(target) or target.slot.outcome != ""):
		target = null
	if mt.time - last_seen_t < 5.0 and last_seen.x < INF and k.pos.distance_to(last_seen) > 2.0:
		state = "search"
		return
	# Tracker: follow footprints
	if k.ktype == Defs.K.TRACKER and not k.husk:
		var tr := _trail_next()
		if tr.x < INF:
			investigate = tr
			investigate_t = mt.time
			state = "trail"
			return
	var heard := _heard()
	if heard.x < INF:
		investigate = heard
		investigate_t = mt.time
		state = "investigate"
		return
	if mt.time - investigate_t < 6.0 and investigate.x < INF and k.pos.distance_to(investigate) > 2.5:
		state = "investigate"
		return
	# keep a long-term goal for a while instead of re-rolling every think
	if mt.time < goal_until and state in ["patrol", "siege", "guard"]:
		if state != "siege" or (siege != null and siege.stage > 0 and not siege.broken and siege.duo.active()):
			return
	if k.husk and k.swarm_base != null:
		state = "patrol"
		patrol = k.swarm_base.pos + Vector2(mt.rng.randf_range(-6, 6), mt.rng.randf_range(-6, 6))
		return
	# helicopter landing zones
	for d in mt.duos:
		var b: Base = d.base
		if b != null and b.heli != null and b.heli.state in ["inbound", "approach", "hover", "landed"] and d.active() and b.pos.distance_to(k.pos) < Tuning.HELI_RESPONSE_RANGE:
			if _claimed_by_other("lz", b) and mt.rng.randf() < 0.5:
				continue
			state = "guard"
			siege = b
			goal_until = mt.time + 20.0
			return
	# revealed bases worth sieging
	var sb := _siege_target()
	if sb != null and mt.rng.randf() < 0.45 + aggression * 0.3:
		state = "siege"
		siege = sb
		goal_until = mt.time + 25.0
		return
	state = "patrol"
	patrol = _patrol_point()
	patrol_t = mt.time + 35.0
	goal_until = mt.time + mt.rng.randf_range(12.0, 22.0)


func _claimed_by_other(kind: String, b: Base) -> bool:
	for o in mt.killers:
		if o == k or not mt.brains.has(o):
			continue
		var ai: KillerAI = mt.brains[o]
		if (kind == "lz" and ai.state == "guard" and ai.siege == b) or (kind == "siege" and ai.state == "siege" and ai.siege == b):
			return true
	return false


func _siege_target() -> Base:
	var best: Base = null
	var bs := -INF
	for d in mt.duos:
		var b: Base = d.base
		if b == null or not d.active():
			continue
		if not (b.known_to_killers(mt.time) or b.pos.distance_to(k.pos) < 18.0):
			continue
		if b.stage == 0 or b.broken:
			continue
		if mt.time < b.lockdown_until:
			continue
		var sc := b.stage * 12.0 - b.pos.distance_to(k.pos) * 0.15
		if b.broken:
			sc -= 20.0
		if _claimed_by_other("siege", b):
			sc -= 15.0
		if sc > bs:
			bs = sc
			best = b
	return best


func _maybe_nest() -> void:
	if nest_cd > 0.0 or not mt.nest.can_trigger() or not k.is_main():
		return
	nest_cd = 3.0
	# the first living main killer bot decides
	for o in mt.killers:
		if o.is_main():
			if o != k:
				return
			break
	var card := mt.nest.card
	var go := false
	match card:
		Defs.Card.PULSE, Defs.Card.SWARM:
			go = true
		Defs.Card.BLACKOUT:
			go = true
		Defs.Card.JAM:
			for d in mt.duos:
				if d.base != null and (d.base.heli_called or d.base.stage >= 2):
					go = true
	if go:
		mt.nest.trigger(k)


func _patrol_point() -> Vector2:
	var opts: Array = []
	var w: Array = []
	# closed cells early on (rushing makes noise and lets survivors out too)
	if mt.time < Tuning.KILLER_RELEASE + 40.0:
		for c in mt.cells:
			if not c["open"]:
				opts.append(MapData.center_of(c["door"]))
				w.append(2.0)
	for t in mt.shop.open_terminals():
		opts.append(t["pos"])
		w.append(3.0)
	for hz in mt.hotzones:
		opts.append(hz["pos"])
		w.append(1.0)
	for z in [Defs.Z.LAB, Defs.Z.MINE, Defs.Z.HIGH, Defs.Z.TOWN, Defs.Z.SWAMP, Defs.Z.FIELD]:
		var tl := mt.m.random_walkable_in_zone(mt.rng, z)
		if tl.x >= 0:
			opts.append(MapData.center_of(tl))
			w.append(1.5 if z in [Defs.Z.TOWN, Defs.Z.LAB, Defs.Z.MINE] else 1.0)
	for d in mt.duos:
		if d.base != null and d.active() and (d.base.known_to_killers(mt.time) or mt.rng.randf() < 0.15):
			opts.append(d.base.pos)
			w.append(1.5)
	if opts.is_empty():
		return k.pos
	var total := 0.0
	for x in w:
		total += x
	var r := mt.rng.randf() * total
	for i in opts.size():
		r -= w[i]
		if r <= 0.0:
			return opts[i]
	return opts[0]


# ------------------------------------------------------------------------------

func _act(dt: float) -> void:
	k.want_attack = false
	k.want_power = false
	k.want_interact = false
	k.want_face = Vector2.ZERO
	k.power_aim = Vector2.ZERO
	if k.stunned() or k.held():
		k.want_move = Vector2.ZERO
		return
	if k.power_state == "tongue_fly" or k.power_state == "tongue_pull" or k.power_state == "charge_windup":
		k.want_move = Vector2.ZERO
		if target != null and is_instance_valid(target):
			k.power_aim = (target.pos - k.pos).normalized()
		return
	if k.power_state == "charge":
		if target != null and is_instance_valid(target):
			k.power_aim = (target.pos - k.pos).normalized()
		return
	match state:
		"catch":
			if target == null or not is_instance_valid(target) or not target.is_downed():
				state = "patrol"
				return
			var d := target.pos.distance_to(k.pos)
			if d > 1.6:
				_go(target.pos)
			else:
				k.want_move = Vector2.ZERO
				k.want_face = target.pos - k.pos
				var opt := mt.interact.find(k, "catch", target)
				if not opt.is_empty() and opt["blocked"] == "":
					mt.interact.begin(k, opt)
					k.want_interact = true
					recent_victims[target.duo.id] = mt.time
		"chase":
			_chase(dt)
		"search":
			if k.stalking():
				pass
			elif k.ktype == Defs.K.TRACKER and k.is_main() and k.pos.distance_to(last_seen) > 12.0 and mt.time >= k.power_cd_until:
				k.want_power = true
			_go(last_seen)
			if k.pos.distance_to(last_seen) < 2.0:
				last_seen = Vector2(INF, INF)
				last_seen_t = -100.0
		"trail", "investigate":
			if k.ktype == Defs.K.TRACKER and k.is_main() and not k.stalking() and k.pos.distance_to(investigate) > 14.0 and mt.time >= k.power_cd_until:
				k.want_power = true
			if k.stalking() and k.pos.distance_to(investigate) < 4.0:
				k.want_power = true  # toggles stalk off near the end of the trail
			_go(investigate)
			if k.pos.distance_to(investigate) < 2.0:
				investigate_t = -100.0
				_smash_nearby()
		"guard":
			if siege == null or siege.heli == null:
				state = "patrol"
				return
			var lz: Vector2 = siege.heli.lz
			if k.pos.distance_to(lz) > 3.0:
				_go(lz + Vector2(1.5, 0))
			else:
				k.want_move = Vector2.ZERO
		"siege":
			_siege()
		_:
			if patrol.x == INF or k.pos.distance_to(patrol) < 3.0 or mt.time > patrol_t:
				patrol = _patrol_point()
				patrol_t = mt.time + 35.0
			if not _go(patrol):
				patrol = Vector2(INF, INF)
			_smash_nearby()


func _chase(_dt: float) -> void:
	if target == null or not is_instance_valid(target) or target.slot.outcome != "":
		state = "patrol"
		return
	var to := target.pos - k.pos
	var d := to.length()
	if k.stalking():
		k.want_power = true  # drop stalk as soon as we have eyes on prey
	# signature powers
	if mt.time >= k.power_cd_until and k.atk_state == "" and not k.husk and mt.rng.randf() < mt.killer_bot_mult()["power"]:
		match k.ktype:
			Defs.K.BRUTE:
				if d > 3.5 and d < 10.0 and mt.m.clear_line(k.pos, target.pos, k.radius, false, mt.solid_fn_for(k)) and mt.rng.randf() < 0.2 + aggression * 0.25:
					k.power_aim = to.normalized()
					k.want_power = true
					return
			Defs.K.LURKER:
				var rng_t = Tuning.TONGUE_RANGE * (0.5 if k.elite else 1.0)
				if d > 3.5 and d < rng_t - 1.0 and target.pinned_by == null and mt.m.los(k.pos, k.y + 1.6, target.pos, target.y + 1.0) and mt.rng.randf() < 0.45:
					k.power_aim = (target.pos + target.vel * 0.15 - k.pos).normalized()
					k.facing = Actor.yaw_of(k.power_aim)
					k.want_power = true
					return
	# melee
	if d < Tuning.ATTACK_RANGE + target.radius - 0.2:
		k.want_face = to
		k.facing = Actor.yaw_of(to)
		k.want_attack = true
		k.want_move = to.normalized() * 0.5
		return
	# lead the target a little
	var lead := target.pos + target.vel * clampf(d / 8.0, 0.0, 0.6)
	_go(lead if mt.nav.is_open(MapData.tile_of(lead), false) else target.pos)
	if d < Tuning.ATTACK_RANGE + 1.2 and k.atk_state == "":
		k.want_attack = mt.rng.randf() < 0.35
	# target vanished into a squeeze gap? seal it sometimes
	if k.is_main() and route_cd <= 0.0 and k.route_charges > 1 and d < 6.0:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var tl := MapData.tile_of(target.pos) + Vector2i(dx, dy)
				if mt.m.tv(tl) == Defs.T.GAP and MapData.center_of(tl).distance_to(k.pos) < 4.0 and mt.rng.randf() < 0.25:
					mt.route_edit(k, tl)
					route_cd = 20.0
					return


func _siege() -> void:
	if siege == null or siege.duo.base != siege or not siege.duo.active():
		state = "patrol"
		return
	var b := siege
	if mt.time < b.lockdown_until:
		state = "patrol"
		return
	var d := b.pos.distance_to(k.pos)
	if d > 2.2:
		if not k.nav_to(b.pos, true):
			state = "patrol"
			return
		var dir := k.steer_path()
		# blocked by a structure? hit it
		var ahead := MapData.tile_of(k.pos + dir * (k.radius + 0.8))
		var st := mt.structure_at(ahead)
		if st != null and st.blocks_killer():
			k.want_move = Vector2.ZERO
			k.want_face = MapData.center_of(ahead) - k.pos
			k.facing = Actor.yaw_of(k.want_face)
			if k.ktype == Defs.K.BRUTE and k.is_main() and mt.time >= k.power_cd_until and not st.metal and mt.rng.randf() < 0.3:
				k.power_aim = k.want_face.normalized()
				k.want_power = true
			else:
				k.want_attack = true
			return
		k.want_move = dir
		_unstick(dir)
		return
	if b.stage == 0 or b.broken:
		state = "patrol"
		return
	k.want_move = Vector2.ZERO
	k.want_face = b.pos - k.pos
	k.facing = Actor.yaw_of(k.want_face)
	k.want_attack = true


func _smash_nearby() -> void:
	var opts := mt.interact.options(k)
	for o in opts:
		if o["id"] == "smash" and o["blocked"] == "" and mt.rng.randf() < 0.5:
			mt.interact.begin(k, o)
			k.want_interact = true
			return


func _go(dest: Vector2) -> bool:
	if not k.nav_to(dest):
		k.want_move = Vector2.ZERO
		return false
	var dir = k.steer_path()
	if dir == Vector2.ZERO and k.pos.distance_to(dest) > 0.35:
		dir = (dest - k.pos).normalized()
	k.want_move = dir
	_unstick(dir)
	return true


func _unstick(dir: Vector2) -> void:
	if k.pos.distance_to(last_pos) < 0.02 and dir != Vector2.ZERO and k.atk_state == "":
		stuck_t += mt.dt_last
		if stuck_t > 1.5:
			stuck_t = 0.0
			k.clear_path()
			patrol = Vector2(INF, INF)
			k.want_move = Vector2(mt.rng.randf_range(-1, 1), mt.rng.randf_range(-1, 1)).normalized()
	else:
		stuck_t = 0.0
	last_pos = k.pos

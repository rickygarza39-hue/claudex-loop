class_name Match
extends Node3D
## One match: owns the map, all actors and systems, and runs the main loop.

signal feed_msg(text: String, kind: String, duration: float, scope: String, duo_id: int)
signal match_over(result: Dictionary)

const SURVIVOR_NAMES := ["Ada", "Boone", "Cass", "Della", "Eli", "Faye", "Gus", "Hattie", "Ike", "June", "Kit", "Lou", "Mae", "Ned"]

var cfg := {}
var m: MapData
var nav: Nav
var view: WorldView = null
var visuals := true
var rng := RandomNumberGenerator.new()
var time := 0.0
var dt_last := 0.016
var over := false
var paused := false
var final_push := false
var released := false
var sim_log := false
var difficulty := 1             # 0 easy, 1 normal, 2 hard (applies to bots on the other side)

var slots: Array = []
var duos: Array = []
var survivors: Array = []      # Survivor actors still on the map
var killers: Array = []        # Killer actors (main, elite, husk)
var items: Array = []
var structures := {}           # Vector2i -> Structure
var structure_list: Array = []
var solid_tiles := {}          # stations and terminals
var cells: Array = []
var noises: Array = []
var trails: Array = []
var hotzones: Array = []       # killers' vague knockdown-item zones
var log_lines: Array = []
var brains := {}               # Actor -> AI brain
var noise_gate := {}
var interact: Interact
var bases: BaseSys
var nest: NestSys
var player_slot: Slot = null
var controller = null   # PlayerController (untyped: also null in headless sims)
var hud = null          # Hud
var sfx: Sfx = null
var _disc_t := 0.0
var _hot_t := 0.0
var _vis_t := 0.0
var result := {}
var later: Array = []          # [time, Callable] scheduled on match time
var gap_tiles: Array = []      # squeeze gaps (for bot escapes)


# ==============================================================================
# Setup

func setup(config: Dictionary, with_visuals: bool) -> void:
	cfg = config
	visuals = with_visuals
	difficulty = int(cfg.get("difficulty", 1))
	rng.seed = int(cfg.get("seed", 1)) * 7919 + 13
	SurvivorAI.reset_shared()
	m = MapGen.new().generate(int(cfg.get("seed", 1)))
	nav = Nav.new(m)
	if visuals:
		view = WorldView.new()
		add_child(view)
		view.build(m)
	for yy in m.h:
		for xx in m.w:
			if m.t(xx, yy) == Defs.T.GAP:
				gap_tiles.append(Vector2i(xx, yy))
	if visuals:
		sfx = Sfx.new()
		add_child(sfx)
	interact = Interact.new(self)
	bases = BaseSys.new(self)
	for t in m.terminals:
		solid_tiles[t] = true
	nest = NestSys.new(self, int(cfg.get("card", Defs.Card.PULSE)))
	for c in m.cells:
		var cc: Dictionary = c.duplicate()
		cc["open"] = false
		cc["progress"] = 0.0
		cells.append(cc)
	_create_slots()
	_spawn_items()
	_spawn_actors()
	_apply_loadouts()
	if visuals:
		for d in m.drops:
			var lm := Models.make("drop_ledge")
			var top := MapData.center_of(d["top"])
			var dir := Vector2(d["tile"] - d["top"])
			var at := top + dir * 0.75
			lm.position = Vector3(at.x, m.tile_height(d["top"]), at.y)
			lm.rotation.y = Actor.yaw_of(dir)
			add_child(lm)
	_shift_hotzones()
	feed_all("Escape your quarantine cell. The killers are released in %d seconds." % int(Tuning.KILLER_RELEASE), "alert", 7.0)


## Items now come from loadouts, not a shop or map pickups. The player brings
## what they equipped (plus the stats from their skill trees); bots roll a kit.
func _apply_loadouts() -> void:
	for sl in slots:
		var a: Actor = sl.actor
		if a == null:
			continue
		if sl.is_human and not cfg.get("spectate", false):
			if a is Survivor:
				var s := a as Survivor
				sl.mods = Progression.mods_for(["kit", Progression.survivor_tree(s.role)])
				for it in Progression.loadout():
					_give_item(s, it)
				s.duo.money += int(s.meta("money"))
				s.duo.scrap += int(s.meta("scrap"))
			else:
				sl.mods = Progression.mods_for([Progression.killer_tree((a as Killer).ktype)])
		elif a is Survivor:
			var s2 := a as Survivor
			for it in Tuning.BOT_LOADOUT_ODDS:
				if rng.randf() < Tuning.BOT_LOADOUT_ODDS[it]:
					_give_item(s2, it)


func _give_item(s: Survivor, item: String) -> void:
	match item:
		"flare":
			s.flare = 1 + int(s.meta("flare_count"))
		"medkit":
			s.medkit += 1
		"cure":
			s.cure += 1
		"traps":
			s.traps[0] = mini(s.traps[0] + 1, s.trap_capacity())
			s.traps[1] = mini(s.traps[1] + 1, s.trap_capacity())
		"scanner":
			s.scanner += 1


func start_drop(s: Survivor, d: Dictionary) -> void:
	if not s.can_act():
		return
	s.start_drop(d)
	make_noise(s.pos, 6.0, "drop", s)
	if s.slot.is_human and hud and hud.has_method("toast"):
		hud.toast("Press E as you land to roll!")
	# bots commit their timing now: better bots land cleanly more often
	if not s.slot.is_human:
		var skill: float = brains[s].skill if brains.has(s) else 0.5
		var w := s.landing_window()
		if rng.randf() < 0.5 + 0.4 * skill:
			s.drop["press"] = rng.randf_range(w[0] + 0.03, w[1] - 0.02)
		else:
			s.drop["press"] = rng.randf_range(0.1, w[0] - 0.05)


func on_drop_landed(s: Survivor, clean: bool) -> void:
	log_event("%s dropped off a ledge (%s)" % [s.slot.name, "clean" if clean else "hurt"])
	if clean:
		s.boost_until = maxf(s.boost_until, time + Tuning.DROP_ROLL_BOOST)
		make_noise(s.pos, 7.0, "drop", s)
		if s.slot.is_human and hud:
			hud.toast("Clean landing!")
	else:
		# a bad landing hurts, but never downs you
		make_noise(s.pos, 15.0, "scream", s)
		s.slow_until = time + Tuning.DROP_FAIL_SLOW
		if s.health == Defs.Health.HEALTHY:
			s.health = Defs.Health.WOUNDED
		if sfx != null:
			sfx.play3d("thud", Vector3(s.pos.x, s.y + 0.5, s.pos.y), 0.0)
		if s.slot.is_human and hud:
			hud.toast("Bad landing: you're hurt and limping.")
			if "hurt" in hud:
				hud.hurt.color.a = 0.45
	if s.slot.is_human and controller and controller.has_method("hit_feedback"):
		controller.hit_feedback(0.25 if clean else 0.8)


func use_medkit(s: Survivor) -> bool:
	if s.medkit <= 0 or s.health != Defs.Health.WOUNDED or not s.can_act():
		return false
	s.medkit -= 1
	s.heal_one()
	feed_to_duo(s.duo, "%s used a medkit." % s.slot.name, "good", 2.5)
	return true


func use_scanner(s: Survivor) -> bool:
	if s.scanner <= 0:
		return false
	s.scanner -= 1
	scan_parts(s)
	return true


func _shuffled(arr: Array) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a


func _create_slots() -> void:
	var side: int = int(cfg.get("side", Defs.Side.SURVIVOR))
	var spectate: bool = cfg.get("spectate", false)
	var names := _shuffled(SURVIVOR_NAMES)
	var sid := 0
	for d in Tuning.DUOS:
		var duo := Duo.new()
		duo.id = d
		duo.name = Defs.DUO_NAMES[d]
		duo.color = Defs.DUO_COLORS[d]
		duo.money = Tuning.START_MONEY
		duo.scrap = Tuning.START_SCRAP
		duo.cell = cells[d]
		cells[d]["duo"] = duo
		if cells[d]["worse"]:
			duo.worse_start = true
			duo.money += Tuning.WORSE_TRAP_BONUS
		var human_here := d == 0 and side == Defs.Side.SURVIVOR and not spectate
		var r1 := rng.randi_range(0, 2)
		if human_here:
			r1 = int(cfg.get("role", Defs.Role.ENGINEER))
		var r2 := (r1 + rng.randi_range(1, 2)) % 3
		if not human_here and rng.randf() < 0.15:
			r2 = r1
		for i in 2:
			var s := Slot.new()
			s.id = sid
			sid += 1
			s.side = Defs.Side.SURVIVOR
			s.duo = duo
			s.role = r1 if i == 0 else r2
			s.is_human = human_here and i == 0
			s.name = names[(d * 2 + i) % names.size()]
			if s.is_human:
				s.name += " (you)"
			duo.members.append(s)
			slots.append(s)
			if s.is_human:
				player_slot = s
		duos.append(duo)
	# three different killers each match, drawn from all eight
	var types: Array = range(Defs.KILLER_NAMES.size())
	for i in range(types.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = types[i]
		types[i] = types[j]
		types[j] = tmp
	if cfg.has("killers"):
		types = cfg["killers"].duplicate()
	if side == Defs.Side.KILLER and not spectate:
		var pk := int(cfg.get("killer", Defs.K.TRACKER))
		types.erase(pk)
		types.push_front(pk)
	for i in Tuning.KILLERS:
		var s := Slot.new()
		s.id = sid
		sid += 1
		s.side = Defs.Side.KILLER
		s.ktype = types[i % types.size()]
		s.is_human = i == 0 and side == Defs.Side.KILLER and not spectate
		s.name = "The " + Defs.KILLER_NAMES[s.ktype] + (" (you)" if s.is_human else "")
		slots.append(s)
		if s.is_human:
			player_slot = s


func _spawn_items() -> void:
	for it in m.items:
		if it["kind"] == Defs.Item.FLARE:
			continue        # flare guns are loadout items now, not map pickups
		_make_item(it["kind"], it["part"], it["amount"], MapData.center_of(it["tile"]))


func _make_item(kind: int, part: int, amount: int, at: Vector2) -> ItemPickup:
	var ip := ItemPickup.new()
	add_child(ip)
	ip.setup(self, kind, part, amount, at)
	items.append(ip)
	if kind == Defs.Item.FLARE:
		for d in duos:
			d.known_items[ip] = true
	return ip


func _spawn_actors() -> void:
	for d in duos:
		var c: Dictionary = d.cell
		for i in d.members.size():
			var s: Slot = d.members[i]
			var sv := Survivor.new()
			add_child(sv)
			sv.setup_survivor(self, s, c["spawns"][i])
			sv.facing = Actor.yaw_of(MapData.center_of(c["door"]) - sv.pos)
			s.actor = sv
			survivors.append(sv)
			if not s.is_human:
				brains[sv] = SurvivorAI.new(self, sv)
	var ki := 0
	for s in slots:
		if s.side != Defs.Side.KILLER:
			continue
		var k := Killer.new()
		add_child(k)
		k.setup_killer(self, s, m.killer_spawns[ki % m.killer_spawns.size()], s.ktype, false)
		k.facing = rng.randf() * TAU
		s.actor = k
		killers.append(k)
		if not s.is_human:
			brains[k] = KillerAI.new(self, k)
		ki += 1


# ==============================================================================
# Main loop

func _process(delta: float) -> void:
	if over or paused:
		return
	step(minf(delta, 0.1))


func step(dt: float) -> void:
	dt_last = dt
	time += dt
	_phases()
	if controller != null and controller.has_method("update_intents"):
		controller.update_intents(dt)
	for a in brains.keys():
		if is_instance_valid(a):
			brains[a].think(dt)
	for s in survivors.duplicate():
		if is_instance_valid(s):
			s.tick(dt)
	for k in killers.duplicate():
		if is_instance_valid(k):
			k.tick(dt)
	for a in all_actors():
		if a.want_interact:
			interact.hold(a, dt)
		elif not a.channel.is_empty():
			interact.on_cancel(a, a.channel)
			a.channel = {}
	for a in all_actors():
		if a is Killer and (a as Killer).power_state == "charge":
			continue
		a.physics_step(dt)
	_separate()
	bases.tick(dt)
	nest.tick(dt)
	_tick_fires(dt)
	for s in survivors:
		bases.auto_deposit(s)
	_disc_t -= dt
	if _disc_t <= 0.0:
		_disc_t = 0.4
		_discover()
		_tick_chases()
	_hot_t -= dt
	if _hot_t <= 0.0:
		_shift_hotzones()
	_respawns()
	_run_later()
	_prune()
	if visuals:
		for a in all_actors():
			a.update_visual(dt)
		_update_visibility()
	_check_end()


func _phases() -> void:
	if not released and time >= Tuning.KILLER_RELEASE:
		released = true
		for k in killers:
			k.released = true
		feed_all("THE KILLERS HAVE BEEN RELEASED.", "alert", 6.0)
		log_event("Killers released")
	if not final_push and time >= Tuning.FINAL_PUSH_AT:
		final_push = true
		feed_all("FINAL PUSH: the company purges the town at %d:00. Get out." % int(Tuning.PURGE_AT / 60.0), "alert", 8.0)
	if time >= Tuning.PURGE_AT and not over:
		for s in survivors.duplicate():
			if s.slot.outcome == "":
				s.slot.outcome = "purged"
				s.slot.outcome_time = time
		feed_all("The purge has begun. Nobody else is getting out.", "alert", 8.0)
		_end_match("purge")


func all_actors() -> Array:
	var out: Array = []
	for s in survivors:
		if is_instance_valid(s):
			out.append(s)
	for k in killers:
		if is_instance_valid(k):
			out.append(k)
	return out


func living_survivors() -> Array:
	var out: Array = []
	for s in survivors:
		if is_instance_valid(s) and s.slot.outcome == "":
			out.append(s)
	return out


func _separate() -> void:
	var acts := all_actors()
	for i in acts.size():
		var a: Actor = acts[i]
		if a is Survivor and ((a as Survivor).hidden_in != null):
			continue
		for j in range(i + 1, acts.size()):
			var b: Actor = acts[j]
			if b is Survivor and ((b as Survivor).hidden_in != null):
				continue
			var d := b.pos - a.pos
			var min_d := a.radius + b.radius
			var dl := d.length()
			if dl < min_d and dl > 0.0001:
				var push := d / dl * (min_d - dl)
				var wa := 0.5
				if a is Killer and b is Survivor:
					wa = 0.2
				elif a is Survivor and b is Killer:
					wa = 0.8
				a.move_by(-push * wa)
				b.move_by(push * (1.0 - wa))


# ==============================================================================
# Queries used by actors and systems

func struct_blocks(tl: Vector2i, a: Actor) -> bool:
	if solid_tiles.has(tl):
		return true
	var st: Structure = structures.get(tl)
	if st == null:
		return false
	if a is Survivor:
		return st.blocks_survivor()
	return st.blocks_killer()


func struct_blocks_sight(tl: Vector2i) -> bool:
	var st: Structure = structures.get(tl)
	return st != null and st.blocks_sight_h() > 1.5


func solid_fn_for(a: Actor) -> Callable:
	return func(x: int, yy: int, surv: bool) -> bool:
		var tt := m.t(x, yy)
		if tt == Defs.T.GAP:
			return true
		if not MapData.walkable_type(tt, surv):
			return true
		return struct_blocks(Vector2i(x, yy), a)


func structure_at(tl: Vector2i) -> Structure:
	return structures.get(tl)


# ------------------------------------------------------------------------------
# New killers' powers

var fires: Array = []          # Furnace burning ground: {pos, until, by, node}
var map_jam_until := -1.0      # the human survivor's map is scrambled (Choir)


## The Foreman's slam: slows, reveals and interrupts survivors near the impact; cracks walls.
func slam(k: Killer, at: Vector2, radius: float) -> void:
	make_noise(at, 30.0, "smash", k)
	if sfx != null:
		sfx.play3d("smash", Vector3(at.x, m.height_at(at), at.y), 6.0)
	for s in living_survivors():
		var d: float = s.pos.distance_to(at)
		if d > radius or s.hidden_in != null:
			continue
		s.slow_until = maxf(s.slow_until, time + Tuning.SLAM_SLOW)
		s.revealed_until = maxf(s.revealed_until, time + Tuning.SLAM_REVEAL)
		s.cancel_channel()
		if s.slot.is_human and controller and controller.has_method("hit_feedback"):
			controller.hit_feedback(clampf(1.0 - d / radius, 0.3, 1.0))
		feed_to_duo(s.duo, "%s was caught in the Foreman's slam!" % s.slot.name, "danger", 3.0)
	for st in structures_near(at, 4.0):
		st.damage(Tuning.SLAM_STRUCT_DMG, k)


## The Furnace drops a burning patch.
func add_fire(p: Vector2, k: Killer) -> void:
	var f := {"pos": p, "until": time + Tuning.FIRE_PATCH_LIFE, "by": k, "node": null}
	if visuals:
		var n := Node3D.new()
		n.position = Vector3(p.x, m.height_at(p) + 0.02, p.y)
		Models.cyl(n, Tuning.FIRE_RADIUS * 0.8, Tuning.FIRE_RADIUS, 0.04, Mats.flat(Color(0.1, 0.03, 0.01)), Vector3(0, 0.02, 0))
		for i in 5:
			var a := float(i) * 1.3
			Models.cyl(n, 0.0, 0.12, 0.5 + 0.25 * float(i % 3), Mats.flat(Color(1.0, 0.45, 0.08), 4.0, 0.5), Vector3(sin(a) * 0.6, 0.3, cos(a) * 0.6))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.5, 0.15)
		l.light_energy = 1.6
		l.omni_range = 5.0
		l.position = Vector3(0, 0.8, 0)
		n.add_child(l)
		add_child(n)
		f["node"] = n
	fires.append(f)


func _tick_fires(_dt: float) -> void:
	if fires.is_empty():
		return
	var keep: Array = []
	for f in fires:
		if time > f["until"]:
			if f["node"] != null:
				f["node"].queue_free()
			continue
		keep.append(f)
		if f["node"] != null:
			(f["node"] as Node3D).scale = Vector3.ONE * (0.9 + 0.1 * sin(time * 9.0 + f["pos"].x))
		for s in living_survivors():
			if s.is_downed() or s.dropping() or s.pos.distance_to(f["pos"]) > Tuning.FIRE_RADIUS:
				continue
			s.slow_until = maxf(s.slow_until, time + 2.0)
			s.revealed_until = maxf(s.revealed_until, time + 3.0)
			if s.health == Defs.Health.HEALTHY and time - s.get_meta("burned_at", -99.0) > Tuning.FIRE_WOUND_LOCKOUT:
				s.set_meta("burned_at", time)
				s.health = Defs.Health.WOUNDED
				make_noise(s.pos, 15.0, "scream", s)
				feed_to_duo(s.duo, "%s was burned!" % s.slot.name, "danger", 3.0)
				if s.slot.is_human and hud:
					hud.hurt.color.a = 0.5
	fires = keep


## The Tally Man steps through space to the furthest clear point along a direction.
func blink(k: Killer, dir: Vector2, dist: float) -> void:
	var best := k.pos
	var steps := int(dist / 0.5)
	for i in range(1, steps + 1):
		var p := k.pos + dir * (i * 0.5)
		if not m.clear_line(k.pos, p, k.radius, false, solid_fn_for(k)):
			break
		best = p
	if best.distance_to(k.pos) < 1.0:
		return
	make_noise(k.pos, 6.0, "whisper", k)
	k.pos = best
	k.facing = Actor.yaw_of(dir)
	k.clear_path()
	make_noise(best, 6.0, "whisper", k)


## The Choir screams: everyone close drops what they were doing, slows and shows up for the killers.
func scream(k: Killer, radius: float) -> void:
	make_noise(k.pos, 40.0, "roar", k)
	if sfx != null:
		sfx.play3d("scream", Vector3(k.pos.x, k.y + 1.8, k.pos.y), 8.0)
	for s in living_survivors():
		if s.pos.distance_to(k.pos) > radius:
			continue
		s.cancel_channel()
		s.slow_until = maxf(s.slow_until, time + Tuning.SCREAM_SLOW)
		s.revealed_until = maxf(s.revealed_until, time + Tuning.SCREAM_REVEAL)
		if s.hidden_in != null:
			bases.unhide(s)
		if s.slot.is_human:
			map_jam_until = time + Tuning.SCREAM_MAP_JAM
			if controller and controller.has_method("hit_feedback"):
				controller.hit_feedback(0.6)
		feed_to_duo(s.duo, "%s heard the Choir. Their map is scrambled." % s.slot.name if s.slot.is_human else "%s heard the Choir!" % s.slot.name, "danger", 3.0)


## Is any Tally Man close enough to the player to be felt?
func tally_near(p: Vector2) -> bool:
	for k in killers:
		if k.ktype == Defs.K.TALLY and k.released and k.pos.distance_to(p) < Tuning.TALLY_DREAD:
			return true
	return false


func structures_near(p: Vector2, r: float) -> Array:
	var out: Array = []
	for st in structure_list:
		if st.pos.distance_to(p) <= r:
			out.append(st)
	return out


func items_near(p: Vector2, r: float) -> Array:
	var out: Array = []
	for it in items:
		if not it.taken and it.pos.distance_to(p) <= r:
			out.append(it)
	return out


func build_mult(a: Actor) -> float:
	if a is Survivor:
		var bm := 1.0 + a.meta("build")
		match (a as Survivor).role:
			Defs.Role.ENGINEER:
				return Tuning.ENGINEER_BUILD_MULT * bm
			Defs.Role.MEDIC:
				return Tuning.MEDIC_BUILD_MULT * bm
		return bm
	return 1.0


func jammed() -> bool:
	return time < nest.jam_until


func blackout() -> bool:
	return time < nest.blackout_until


func base_site_ok(p: Vector2, d: Duo) -> bool:
	var tl := MapData.tile_of(p)
	if m.tv(tl) != Defs.T.FLOOR or solid_tiles.has(tl) or structures.has(tl):
		return false
	if tl.x < 4 or tl.y < 4 or tl.x > m.w - 5 or tl.y > m.h - 5:
		return false
	if Vector2(tl - m.nest).length() < 14.0:
		return false
	for c in cells:
		if c["rect"].grow(1).has_point(tl):
			return false
	for od in duos:
		if od != d and od.base != null and Vector2(od.base.tile - tl).length() < Tuning.BASE_MIN_SPACING:
			return false
	return true


func pack_bonus(k: Killer) -> float:
	var b := 1.0
	for o in killers:
		if o != k and o.elite and o.slot != null and o.slot.perk("Pack") > 0 and o.pos.distance_to(k.pos) < 10.0:
			b += 0.03 * o.slot.perk("Pack")
	return minf(b, 1.12)


func lurker_seen(k: Killer) -> bool:
	for s in living_survivors():
		if s.is_downed():
			continue
		var d = k.pos - s.pos
		if d.length() > 14.0:
			continue
		if absf(s.forward2().angle_to(d)) > deg_to_rad(55.0):
			continue
		if m.los(s.pos, s.y + s.eye_height(), k.pos, k.y + 1.4):
			return true
	for st in structure_list:
		if st.kind == Defs.B.FLOODLIGHT and st.pos.distance_to(k.pos) < Tuning.FLOODLIGHT_RADIUS:
			return true
	return false


func can_see(a: Actor, b: Actor, max_d: float) -> bool:
	var d := a.pos.distance_to(b.pos)
	if d > max_d:
		return false
	return m.los(a.pos, a.y + a.eye_height(), b.pos, b.y + b.body_height())


func survivor_ai_for(s: Survivor) -> SurvivorAI:
	return brains.get(s)


# ==============================================================================
# Noise, trails, discovery, hot zones

func make_noise(p: Vector2, r: float, kind: String, source: Actor, interval: float = 0.0) -> void:
	if interval > 0.0 and source != null:
		var key := str(source.get_instance_id()) + kind
		if time < noise_gate.get(key, -1.0):
			return
		noise_gate[key] = time + interval
	noises.append({"pos": p, "r": r, "t": time, "kind": kind, "src": source})
	if sfx != null and r < 900.0:
		sfx.on_noise(kind, Vector3(p.x, m.height_at(p) + 1.0, p.y))


func add_trail(p: Vector2, s: Survivor, blood: bool) -> void:
	trails.append({"pos": p, "t": time, "blood": blood, "s": s})


func _prune() -> void:
	while not noises.is_empty() and time - noises[0]["t"] > 4.0:
		noises.pop_front()
	while not trails.is_empty() and time - trails[0]["t"] > (Tuning.BLOOD_LIFETIME if trails[0]["blood"] else Tuning.TRAIL_LIFETIME):
		trails.pop_front()
	if trails.size() > 1400:
		trails = trails.slice(trails.size() - 1400)


func _discover() -> void:
	for s in living_survivors():
		if s.is_downed():
			continue
		var sight: float = Tuning.SURV_SIGHT_DARK if blackout() else Tuning.ITEM_SPOT_RANGE * (1.0 + s.meta("spot"))
		for it in items:
			if it.taken or s.duo.known_items.has(it):
				continue
			if it.pos.distance_to(s.pos) > sight:
				continue
			if m.los(s.pos, s.y + s.eye_height(), it.pos, it.base_y + 0.3):
				s.duo.known_items[it] = true


func _shift_hotzones() -> void:
	_hot_t = Tuning.HOTZONE_SHIFT
	hotzones.clear()
	for it in items:
		if it.taken or it.kind != Defs.Item.FLARE:
			continue
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.0, Tuning.HOTZONE_RADIUS * 0.7)
		hotzones.append({"pos": it.pos + off, "r": Tuning.HOTZONE_RADIUS, "item": it})


func _tick_chases() -> void:
	for s in living_survivors():
		var chased := false
		for k in killers:
			if not k.released or k.husk:
				continue
			if k.pos.distance_to(s.pos) < 16.0 and m.los(k.pos, k.y + 1.6, s.pos, s.y + 1.0):
				chased = true
				s.chased_by = k
				break
		if chased:
			if s.slot.is_human and sfx and time - s.last_seen_by_killer > 12.0:
				sfx.play2d("stinger", -3.0)
			s.last_seen_by_killer = time
			if s.chase_start < 0.0:
				s.chase_start = time
		elif s.chase_start >= 0.0 and time - s.last_seen_by_killer > 8.0:
			if s.last_seen_by_killer - s.chase_start > 10.0 and not s.is_downed():
				reward(s.duo, Tuning.REWARD_CHASE_ESCAPE, "lost a killer", s.slot)
			s.chase_start = -1.0
			s.chased_by = null


# ==============================================================================
# Events

func pickup(s: Survivor, it: ItemPickup) -> void:
	if it.taken:
		return
	match it.kind:
		Defs.Item.PART:
			if s.carry_space() <= 0:
				return
			if s.slot.is_human and sfx:
				sfx.play2d("pickup", -4.0)
			s.parts.append(it.part)
			feed_to_duo(s.duo, "%s picked up a %s." % [s.slot.name, Defs.PART_NAMES[it.part]], "info")
		Defs.Item.CASH:
			reward(s.duo, it.amount, "found scrip", s.slot)
		Defs.Item.SCRAP:
			s.duo.scrap += it.amount
			feed_to_duo(s.duo, "+%d scrap" % it.amount, "info", 2.0)
		Defs.Item.FLARE:
			if s.flare > 0:
				return
			s.flare = 1
			feed_all("%s found a flare gun. %d knockdown items left on the map." % [s.slot.name, _flares_left() - 1], "info")
			_shift_hotzones()
	it.taken = true
	items.erase(it)
	for d in duos:
		d.known_items.erase(it)
	SurvivorAI.claims.erase(it)
	it.queue_free()


func _flares_left() -> int:
	var n := 0
	for it in items:
		if it.kind == Defs.Item.FLARE and not it.taken:
			n += 1
	return n


func drop_part(p: int, at: Vector2) -> void:
	var tl := nav.snap(MapData.tile_of(at), true)
	var pos2 := at if tl == MapData.tile_of(at) else MapData.center_of(tl)
	var ip := _make_item(Defs.Item.PART, p, 1, pos2 + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)))
	for d in duos:
		if d.living().size() > 0:
			for sl in d.living():
				if sl.actor and sl.actor.pos.distance_to(at) < 14.0:
					d.known_items[ip] = true


func scan_parts(s: Survivor) -> void:
	var need: Array = s.duo.base.all_missing() if s.duo.base != null else [Defs.P.CABLE, Defs.P.FUEL, Defs.P.SPARK]
	var marked := 0
	for p in need:
		var best: ItemPickup = null
		var bd := INF
		for it in items:
			if it.taken or it.kind != Defs.Item.PART or it.part != p:
				continue
			var d = it.pos.distance_to(s.pos)
			if d < bd:
				bd = d
				best = it
		if best != null and not s.duo.known_items.has(best):
			s.duo.known_items[best] = true
			marked += 1
	feed_to_duo(s.duo, "Scanner: %d part locations marked on your map." % marked, "good")


func open_cell(c: Dictionary) -> void:
	if c["open"]:
		return
	c["open"] = true
	var door: Vector2i = c["door"]
	m.set_t(door.x, door.y, Defs.T.FLOOR)
	nav.refresh_tile(door)
	if view:
		view.open_tile(door)
	var d: Duo = c.get("duo")
	if d:
		feed_to_duo(d, "You're out of the cell! Find radio parts and pick a spot for your base.", "good", 7.0)
		log_event("%s duo escaped their cell at %.0fs" % [d.name, time])
	make_noise(MapData.center_of(door), 14.0, "door", null)


func smash_tile(tl: Vector2i, k: Killer) -> void:
	var tt := m.tv(tl)
	if tt == Defs.T.CELL_DOOR:
		for c in cells:
			if c["door"] == tl:
				open_cell(c)
				feed_all("A killer smashed open a quarantine cell!", "danger")
		return
	if tt == Defs.T.BOARDS:
		m.set_t(tl.x, tl.y, Defs.T.FLOOR)
		nav.refresh_tile(tl)
		if view:
			view.open_tile(tl)
		make_noise(MapData.center_of(tl), Tuning.NOISE_SMASH, "smash", k)


func damage_in_front(k: Killer, dmg: float) -> bool:
	var fwd := k.forward2()
	var probe := k.pos + fwd * (k.radius + 0.9)
	var tl := MapData.tile_of(probe)
	var st: Structure = structures.get(tl)
	if st == null:
		for o in structures_near(probe, 1.2):
			if o.is_trap() or o.kind in [Defs.B.ALARM, Defs.B.DECOY, Defs.B.FLOODLIGHT]:
				st = o
				break
	if st != null and st.kind != Defs.B.HATCH:
		st.damage(dmg, k)
		return true
	for d in duos:
		var b: Base = d.base
		if b != null and b.pos.distance_to(probe) < 1.4:
			bases.damage_station(b, dmg * Tuning.STATION_DAMAGE_MULT, k)
			return true
	return false


func add_structure(st: Structure) -> void:
	structures[st.tile] = st
	structure_list.append(st)
	if st.base != null:
		st.base.structures.append(st)
	if st.kind == Defs.B.HATCH:
		return
	nav.set_struct(st.tile, st.blocks_survivor(), st.blocks_killer())
	var h := st.blocks_sight_h()
	if h > 0.0:
		m.dyn_top[m.idx(st.tile.x, st.tile.y)] = h


func remove_structure(st: Structure, broken: bool) -> void:
	if structures.get(st.tile) == st:
		structures.erase(st.tile)
	structure_list.erase(st)
	if st.base != null:
		st.base.structures.erase(st)
	if st.kind != Defs.B.HATCH:
		nav.set_struct(st.tile, false, false)
	m.dyn_top[m.idx(st.tile.x, st.tile.y)] = 0.0
	if st.occupant != null:
		bases.unhide(st.occupant)
	if broken and not st.is_trap():
		nest.add(Tuning.NEST_STRUCTURE_BROKEN, "base damage")
	st.queue_free()


func reward(d: Duo, amount: int, why: String, s: Slot) -> void:
	d.money += amount
	d.earned_total += amount
	if s != null:
		s.stats["earned"] += amount
	feed_to_duo(d, "+$%d  %s" % [amount, why], "money", 2.5)


func on_hit(s: Survivor, k: Killer, res: String) -> void:
	if sfx != null and res != "none":
		sfx.play3d("thud", Vector3(s.pos.x, s.y + 1.0, s.pos.y), 2.0)
		if s.slot.is_human and hud:
			hud.hurt.color.a = 0.55
	if sim_log and brains.has(s):
		var ai = brains[s]
		print("   HIT %s (%s) by %s goal=%s chased=%s since_seen=%.1f d_threat=%.1f run=%s crouch=%s" % [s.slot.name, res, k.slot.name, ai.goal, str(time - s.last_seen_by_killer < 2.5), time - s.last_seen_by_killer, (ai.threat.pos.distance_to(s.pos) if ai.threat else -1.0), str(s.want_run), str(s.want_crouch)])
	if res == "wounded":
		feed_to_duo(s.duo, "%s was hit!" % s.slot.name, "danger", 3.0)
		k.slot.stats["assists"] += 1


func on_parry(s: Survivor, k: Killer) -> void:
	s.slot.stats["parries"] += 1
	var key := s.duo.id
	if time - k.parry_paid.get(key, -999.0) >= Tuning.PARRY_REWARD_LOCKOUT:
		k.parry_paid[key] = time
		reward(s.duo, Tuning.PARRY_REWARD, "perfect parry", s.slot)
	else:
		feed_to_duo(s.duo, "Perfect parry!", "good", 2.0)
	make_noise(s.pos, 12.0, "clang", s)


func on_survivor_downed(s: Survivor, by: Killer) -> void:
	feed_all("%s is DOWN%s." % [s.slot.name, (" (" + by.slot.name + ")") if by and by.slot else ""], "danger", 4.0)
	log_event("%s downed by %s" % [s.slot.name, by.slot.name if by and by.slot else "?"])
	if by and by.slot:
		by.slot.stats["assists"] += 1


func on_caught(s: Survivor, k: Killer) -> void:
	if s.slot.outcome != "":
		return
	s.slot.outcome = "caught"
	s.slot.outcome_time = time
	var lost := s.duo.money / 2
	s.duo.money -= lost
	if k != null:
		k.bounty += maxi(lost, Tuning.BOUNTY_MIN)
		k.slot.stats["catches"] += 1
		if k.elite:
			k.slot.stats["elite_catches"] += 1
			elite_xp(k.slot, Tuning.ELITE_XP_CATCH)
		for o in killers:
			if o != k and o.elite and o.pos.distance_to(s.pos) < 12.0:
				elite_xp(o.slot, Tuning.ELITE_XP_ASSIST)
	nest.add(Tuning.NEST_CATCH, "catch")
	feed_all("%s was CAUGHT by %s. Their duo's pot was halved; a $%d bounty is on %s." % [s.slot.name, k.slot.name if k else "the infection", maxi(lost, Tuning.BOUNTY_MIN), k.slot.name if k else "nobody"], "danger", 6.0)
	log_event("%s caught by %s at %.0fs" % [s.slot.name, k.slot.name if k else "?", time])
	_retire_survivor(s, false)


func on_turned(s: Survivor) -> void:
	if s.slot.outcome != "":
		return
	s.slot.outcome = "turned"
	s.slot.outcome_time = time
	s.duo.money -= s.duo.money / 2
	nest.add(Tuning.NEST_CATCH, "turned")
	var inside := s.duo.base != null and s.duo.base.contains(s.pos)
	feed_all("%s has TURNED into one of them%s." % [s.slot.name, " — inside their own base" if inside else ""], "danger", 6.0)
	log_event("%s turned at %.0fs (inside base: %s)" % [s.slot.name, time, str(inside)])
	_retire_survivor(s, inside)


func _retire_survivor(s: Survivor, turned_in_base: bool) -> void:
	var at := s.pos
	var slot := s.slot
	for p in s.parts:
		drop_part(p, at)
	s.parts.clear()
	s.flare = 0
	if s.hidden_in:
		bases.unhide(s)
	s.release_pin()
	survivors.erase(s)
	brains.erase(s)
	SurvivorAI.release_claims(s)
	if controller and controller.has_method("on_actor_retired"):
		controller.on_actor_retired(s)
	s.queue_free()
	slot.actor = null
	# become an elite infected
	slot.side = Defs.Side.KILLER
	slot.elite = true
	slot.ktype = rng.randi_range(0, 2)
	if turned_in_base:
		slot.respawn_at = time + 0.1
		slot.set_meta("spawn_at", at)
		slot.set_meta("dazed", true)
		slot.set_meta("reveal_base", s.duo.base)
	else:
		slot.respawn_at = time + Tuning.ELITE_RESPAWN
	if slot.is_human and hud and hud.has_method("ask_elite_class"):
		hud.ask_elite_class(slot)


func _respawns() -> void:
	if not Tuning.ELITES_ENABLED:
		return
	for s in slots:
		if s.elite and s.actor == null and s.respawn_at > 0.0 and time >= s.respawn_at:
			s.respawn_at = -1.0
			var at: Vector2 = s.get_meta("spawn_at") if s.has_meta("spawn_at") else m.killer_spawns[rng.randi() % m.killer_spawns.size()]
			var k := Killer.new()
			add_child(k)
			k.setup_killer(self, s, at, s.ktype, true)
			k.released = true
			s.actor = k
			killers.append(k)
			if s.has_meta("dazed"):
				k.stun(Tuning.DAZE_TIME, "dazed")
				var b: Base = s.get_meta("reveal_base")
				s.remove_meta("dazed")
				s.remove_meta("spawn_at")
				if b != null:
					later.append([time + Tuning.DAZE_TIME, func(): _expose_base(b)])
			if s.is_human:
				if controller and controller.has_method("possess"):
					controller.possess(k)
			else:
				brains[k] = KillerAI.new(self, k)
			feed_all("%s rises as an elite %s." % [s.name, Defs.KILLER_NAMES[s.ktype]], "danger", 4.0)


func _run_later() -> void:
	if later.is_empty():
		return
	var keep: Array = []
	for e in later:
		if time >= e[0]:
			(e[1] as Callable).call()
		else:
			keep.append(e)
	later = keep


func _expose_base(b: Base) -> void:
	b.revealed = true
	b.exposed_until = time + 9999.0
	for st in b.structures:
		st.found = true
	if b.hatch:
		b.hatch.found = true
	feed_all("The turned survivor revealed %s duo's base, traps and hatch to the killers!" % b.duo.name, "danger", 6.0)


func elite_xp(s: Slot, amount: int) -> void:
	if s == null or not s.elite:
		return
	s.elite_xp += amount
	while s.elite_level < Tuning.ELITE_MAX_LEVEL and s.elite_xp >= (s.elite_level + 1) * Tuning.ELITE_XP_PER_LEVEL:
		s.elite_level += 1
		var branches: Array = Defs.ELITE_BRANCHES[s.ktype]
		if s.is_human and hud and hud.has_method("ask_perk"):
			hud.ask_perk(s)
		else:
			var b: String = branches[rng.randi() % branches.size()]
			s.perks[b] = s.perks.get(b, 0) + 1
		feed_all("%s reached elite level %d." % [s.name, s.elite_level], "info")


func on_trap(st: Structure, k: Killer) -> void:
	var snare := st.kind == Defs.B.SNARE
	var ok := k.stun(Tuning.SNARE_HOLD if snare else Tuning.FLASH_DISORIENT, "snare" if snare else "flash")
	if ok and st.owner_duo != null:
		reward(st.owner_duo, Tuning.REWARD_SNARE if snare else Tuning.REWARD_FLASH, "%s caught %s" % ["snare" if snare else "flash trap", k.slot.name], null)
		_collect_bounty(k, st.owner_duo)
	make_noise(st.pos, 16.0, "trap", null)
	if k.slot.is_human and hud and hud.has_method("flash_screen") and not snare:
		hud.flash_screen()
	remove_structure(st, false)


func _collect_bounty(k: Killer, d: Duo) -> void:
	if k.bounty > 0 and d != null:
		var amt := k.bounty
		k.bounty = 0
		reward(d, amt, "BOUNTY on %s" % k.slot.name, null)
		feed_all("%s duo collected the bounty on %s ($%d)." % [d.name, k.slot.name, amt], "good")


func use_flare(s: Survivor) -> bool:
	if s.flare <= 0 or not s.can_act():
		return false
	var best: Killer = null
	var bd := INF
	for k in killers:
		if not k.released:
			continue
		var d = k.pos - s.pos
		var dist = d.length()
		if dist > Tuning.FLARE_RANGE:
			continue
		if absf(s.forward2().angle_to(d)) > deg_to_rad(28.0):
			continue
		if not m.los(s.pos, s.y + 1.4, k.pos, k.y + 1.2):
			continue
		if dist < bd:
			bd = dist
			best = k
	s.flare -= 1
	make_noise(s.pos, 30.0, "flare", s)
	if best == null:
		feed_to_duo(s.duo, "The flare missed!", "danger", 2.5)
		return true
	best.stun(Tuning.KNOCKDOWN_STUN + s.meta("flare_stun"), "knockdown")
	reward(s.duo, Tuning.REWARD_KNOCKDOWN, "knocked down %s" % best.slot.name, s.slot)
	s.slot.stats["stuns"] += 1
	_collect_bounty(best, s.duo)
	feed_all("%s knocked down %s with a flare!" % [s.slot.name, best.slot.name], "good")
	if best.slot.is_human and hud and hud.has_method("flash_screen"):
		hud.flash_screen()
	return true


func place_trap(s: Survivor, which: int) -> bool:
	var tl := MapData.tile_of(s.pos + s.forward2() * 1.2)
	if m.tv(tl) != Defs.T.FLOOR:
		tl = MapData.tile_of(s.pos)
	var kind := Defs.B.SNARE if which == 0 else Defs.B.FLASH
	var st := bases.place(s, kind, tl)
	return st != null


func scent_mask(s: Survivor) -> bool:
	if s.role != Defs.Role.MEDIC or time < s.ability_cd_until or not s.can_act():
		return false
	s.ability_cd_until = time + Tuning.SCENT_MASK_COOLDOWN * (1.0 - s.meta("ability_cd"))
	for o in living_survivors():
		if o.pos.distance_to(s.pos) <= Tuning.SCENT_MASK_RADIUS:
			o.masked_until = time + Tuning.SCENT_MASK_TIME
	# wipe nearby trails
	var keep: Array = []
	for tr in trails:
		if tr["pos"].distance_to(s.pos) > Tuning.SCENT_MASK_RADIUS * 1.6:
			keep.append(tr)
	trails = keep
	feed_to_duo(s.duo, "Scent mask sprayed: hidden from the Tracker for %ds." % int(Tuning.SCENT_MASK_TIME), "good", 3.0)
	return true


func on_tongue(k: Killer, s: Survivor) -> void:
	feed_all("%s is being dragged by a tongue! Break it!" % s.slot.name, "danger", 4.0)


func on_spotted(k: Killer) -> void:
	feed_survivors("The Lurker has been SPOTTED.", "good", 3.0)


func on_stalk(_k: Killer, _on: bool) -> void:
	pass


func on_alarm(st: Structure, k: Killer) -> void:
	if st.owner_duo:
		feed_to_duo(st.owner_duo, "ALARM: %s is at your base!" % k.slot.name, "danger", 4.0)
		for sl in st.owner_duo.living():
			if sl.actor and brains.has(sl.actor):
				brains[sl.actor].alert(k.pos)
	make_noise(st.pos, 20.0, "alarm", null)


func on_steal_started(_s: Survivor, _b: Base) -> void:
	pass


func on_boarded(s: Survivor, h: Heli) -> void:
	s.slot.outcome = "escaped"
	s.slot.outcome_time = time
	feed_all("%s ESCAPED by helicopter!" % s.slot.name, "good", 5.0)
	log_event("%s escaped at %.0fs" % [s.slot.name, time])
	survivors.erase(s)
	brains.erase(s)
	SurvivorAI.release_claims(s)
	if controller and controller.has_method("on_actor_retired"):
		controller.on_actor_retired(s)
	s.queue_free()
	s.slot.actor = null


func on_heli_departed(h: Heli) -> void:
	var left := h.base.duo.living()
	if left.is_empty():
		if h.boarded.is_empty():
			feed_all("The helicopter leaves %s duo's base empty." % h.base.duo.name, "danger")
		else:
			feed_all("The helicopter lifts off with %s duo aboard." % h.base.duo.name, "good")
	else:
		var names: Array = []
		for sl in left:
			names.append(sl.name)
		feed_all("The helicopter left without %s!" % ", ".join(names), "danger", 6.0)
		h.base.heli_called = false


## How sharp the killer bots are (only against a human survivor; bot-vs-bot stays Normal).
func killer_bot_mult() -> Dictionary:
	var human_killer := player_slot != null and player_slot.side == Defs.Side.KILLER and not player_slot.elite
	var d := difficulty if not human_killer else 1
	return [{"react": 1.6, "sight": 0.85, "giveup": 0.7, "power": 0.6},
		{"react": 1.0, "sight": 1.0, "giveup": 1.0, "power": 1.0},
		{"react": 0.55, "sight": 1.15, "giveup": 1.5, "power": 1.3}][d]


## How sharp the survivor bots are (only when a human plays a killer).
func survivor_bot_skill() -> Vector2:
	var human_killer := player_slot != null and player_slot.side == Defs.Side.KILLER
	if not human_killer:
		return Vector2(0.3, 0.75)
	return [Vector2(0.15, 0.45), Vector2(0.35, 0.8), Vector2(0.65, 0.98)][difficulty]


## Killer route editing: seal a squeeze gap or found hatch, or collapse a narrow tunnel.
func route_edit(k: Killer, tl: Vector2i) -> String:
	if not k.is_main():
		return "Only the three main killers can edit routes"
	if k.route_charges <= 0:
		return "No route charges left (the Nest refills them)"
	if MapData.center_of(tl).distance_to(k.pos) > 4.5:
		return "Too far away"
	var tt := m.tv(tl)
	if tt == Defs.T.BOARDS:
		smash_tile(tl, k)
		return ""
	if tt == Defs.T.GAP:
		var st := structure_at(tl)
		if st != null and st.kind == Defs.B.HATCH:
			if not st.found:
				return "Nothing there you know of"
			bases.seal_hatch(k, st)
			return ""
		for a in all_actors():
			if MapData.tile_of(a.pos) == tl:
				return "Someone is in the gap"
		m.set_t(tl.x, tl.y, Defs.T.SEALED)
		nav.refresh_tile(tl)
		if view:
			view.update_tile(tl)
		k.route_charges -= 1
		make_noise(MapData.center_of(tl), 20.0, "seal", k)
		feed_survivors("A killer sealed a squeeze gap.", "danger", 3.0)
		return ""
	if tt == Defs.T.FLOOR and m.zone(tl.x, tl.y) in [Defs.Z.MINE, Defs.Z.LAB] and m.roof[m.idx(tl.x, tl.y)] == Defs.R.CEILING:
		var lr := m.is_solid_static(tl.x - 1, tl.y) and m.is_solid_static(tl.x + 1, tl.y)
		var ud := m.is_solid_static(tl.x, tl.y - 1) and m.is_solid_static(tl.x, tl.y + 1)
		if not (lr or ud):
			return "Only narrow tunnels can be collapsed"
		if structures.has(tl) or solid_tiles.has(tl):
			return "Something is in the way"
		for a in all_actors():
			if MapData.tile_of(a.pos) == tl:
				return "Someone is standing there"
		for it in items:
			if MapData.tile_of(it.pos) == tl:
				return "Something is lying there"
		# never cut the map in two
		var a1 := tl + (Vector2i(0, -1) if lr else Vector2i(-1, 0))
		var a2 := tl + (Vector2i(0, 1) if lr else Vector2i(1, 0))
		m.set_t(tl.x, tl.y, Defs.T.RUBBLE)
		nav.refresh_tile(tl)
		if not nav.reachable(MapData.center_of(a1), MapData.center_of(a2), false):
			m.set_t(tl.x, tl.y, Defs.T.FLOOR)
			nav.refresh_tile(tl)
			return "Collapsing this would cut the mine off"
		if view:
			view.update_tile(tl)
		k.route_charges -= 1
		make_noise(MapData.center_of(tl), 35.0, "collapse", k)
		feed_survivors("A tunnel collapsed somewhere in the mines.", "danger", 3.0)
		return ""
	return "Aim at a squeeze gap, a found hatch, boards or a narrow mine tunnel"


func best_swarm_target() -> Base:
	var best: Base = null
	var score := -1.0
	for d in duos:
		var b: Base = d.base
		if b == null or not d.active():
			continue
		var sc := b.stage * 10.0 + (5.0 if b.known_to_killers(time) else 0.0) + (8.0 if b.heli_called else 0.0)
		if sc > score:
			score = sc
			best = b
	return best


func spawn_swarm(b: Base) -> void:
	for i in Tuning.SWARM_HUSKS:
		var a := rng.randf() * TAU
		var p := b.pos + Vector2(cos(a), sin(a)) * rng.randf_range(12.0, 18.0)
		var tl := nav.snap(MapData.tile_of(p), false, false, 8)
		if tl.x < 0:
			continue
		var s := Slot.new()
		s.name = "Husk"
		s.side = Defs.Side.KILLER
		var k := Killer.new()
		add_child(k)
		k.setup_killer(self, s, MapData.center_of(tl), Defs.K.TRACKER, false, true)
		k.released = true
		k.husk_until = time + Tuning.SWARM_TIME
		k.swarm_base = b
		s.actor = k
		killers.append(k)
		brains[k] = KillerAI.new(self, k)


func remove_husk(k: Killer) -> void:
	killers.erase(k)
	brains.erase(k)
	k.queue_free()




# ==============================================================================
# Visibility for the local player

func _update_visibility() -> void:
	var viewer: Actor = controller.actor if controller != null and "actor" in controller and controller.actor != null else null
	for a in all_actors():
		var show := true
		if a is Killer:
			var k := a as Killer
			if not k.released and viewer != null and viewer is Survivor:
				show = true
			if k.stalking() and viewer is Survivor and viewer.pos.distance_to(k.pos) > 3.0:
				show = false
			if k.ktype == Defs.K.TALLY and k.is_main() and viewer is Survivor and viewer.pos.distance_to(k.pos) > Tuning.TALLY_VISIBLE:
				show = false
		elif a is Survivor:
			var s := a as Survivor
			if s.hidden_in != null:
				show = false
			if viewer is Killer and (viewer as Killer).stalking() and (viewer as Killer).ktype == Defs.K.TRACKER:
				show = false
		if a == viewer and not (controller.has_method("shows_own_body") and controller.shows_own_body()):
			show = false
		if a.shown != show:
			a.set_shown(show)


# ==============================================================================
# Feed and logging

func feed_all(text: String, kind: String = "info", dur: float = 4.0) -> void:
	feed_msg.emit(text, kind, dur, "all", -1)
	_log(text)


func feed_survivors(text: String, kind: String = "info", dur: float = 4.0) -> void:
	feed_msg.emit(text, kind, dur, "survivors", -1)


func feed_killers(text: String, kind: String = "info", dur: float = 4.0) -> void:
	feed_msg.emit(text, kind, dur, "killers", -1)


func feed_to_duo(d: Duo, text: String, kind: String = "info", dur: float = 4.0) -> void:
	feed_msg.emit(text, kind, dur, "duo", d.id)


func _log(text: String) -> void:
	if sim_log:
		print("[%5.0fs] %s" % [time, text])


func log_event(text: String) -> void:
	log_lines.append("[%s] %s" % [fmt_time(time), text])


static func fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# ==============================================================================
# End

func _check_end() -> void:
	if over:
		return
	if living_survivors().is_empty():
		_end_match("done")


func _end_match(reason: String) -> void:
	if over:
		return
	over = true
	var escaped := 0
	var caught := 0
	var rows: Array = []
	for s in slots:
		if s.side == Defs.Side.SURVIVOR or s.elite or s.outcome != "":
			if s.outcome == "escaped":
				escaped += 1
			elif s.outcome != "":
				caught += 1
		rows.append({"name": s.name, "human": s.is_human, "duo": s.duo.name if s.duo else "", "outcome": s.outcome, "time": s.outcome_time,
			"elite": s.elite, "ktype": s.ktype, "stats": s.stats, "role": s.role, "killer": s.duo == null})
	var killers_win := escaped == 0
	result = {"reason": reason, "time": time, "escaped": escaped, "caught": caught, "killers_win": killers_win, "rows": rows,
		"log": log_lines, "seed": cfg.get("seed", 0), "player": player_slot.name if player_slot else ""}
	log_event("Match over (%s): %d escaped, %d caught or turned" % [reason, escaped, caught])
	if player_slot != null and visuals and not cfg.get("spectate", false):
		result["progress"] = Progression.award(self, player_slot)
	match_over.emit(result)

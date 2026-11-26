class_name Survivor
extends Actor
## A survivor: two-hit health, downed crawling and turning, inventory, role kit.

var role := Defs.Role.ENGINEER
var duo: Duo
var health := Defs.Health.HEALTHY
var boost_until := -1.0
var turn_left := 0.0
var base_bonus_given := false
var pinned_by: Killer = null
var masked_until := -1.0
var parry_until := -1.0
var parry_cd_until := 0.0
var parts: Array = []
var flare := 0
var traps := [0, 0]
var cure := 0
var medkit := 0
var scanner := 0
var revive_used := false
var ability_cd_until := 0.0
var hidden_in: Structure = null
var dazed_until := -1.0
var trail_acc := 0.0
var blood_acc := 0.0
var noise_cd := 0.0
var chased_by: Killer = null
var chase_start := -1.0
var last_seen_by_killer := -100.0
var slow_until := -1.0
var downed_by: Killer = null
var revealed_until := -1.0  # Pulse event


func _build_model() -> void:
	attach_model(Models.make("survivor", {"color": Defs.ROLE_COLORS[role]}))


func setup_survivor(match_ref: Match, s: Slot, p: Vector2) -> void:
	is_survivor = true
	radius = Tuning.SURV_RADIUS
	role = s.role
	duo = s.duo
	traps = [Tuning.TRAP_START[role], Tuning.TRAP_START[role]]
	setup(match_ref, s, p)


func eye_height() -> float:
	if health == Defs.Health.DOWNED:
		return 0.45
	if hidden_in != null:
		return 1.5
	return lerpf(1.62, 1.05, crouch_amount)


func body_height() -> float:
	if health == Defs.Health.DOWNED:
		return 0.3
	return lerpf(1.1, 0.75, crouch_amount)


func is_downed() -> bool:
	return health == Defs.Health.DOWNED


func can_act() -> bool:
	return health != Defs.Health.DOWNED and pinned_by == null and mt.time >= dazed_until and hidden_in == null


func crouched() -> bool:
	return want_crouch or in_gap


func move_speed() -> float:
	if pinned_by != null or mt.time < dazed_until or hidden_in != null:
		return 0.0
	if not channel.is_empty():
		return 0.0
	var s := Tuning.SURV_WALK
	if health == Defs.Health.DOWNED:
		s = Tuning.SURV_CRAWL
	elif in_gap:
		s = Tuning.SURV_SQUEEZE
	elif want_crouch:
		s = Tuning.SURV_CROUCH
	elif want_run:
		s = Tuning.SURV_RUN
	if mt.time < boost_until and health != Defs.Health.DOWNED:
		s = Tuning.SURV_WOUND_BOOST
	if in_water:
		s *= Tuning.WATER_MULT
	if mt.time < slow_until:
		s *= 0.75
	if health == Defs.Health.DOWNED:
		s *= 1.0 + meta("crawl")
	else:
		s *= 1.0 + meta("move")
	return s


func carry_space() -> int:
	return Tuning.CARRY_PARTS - parts.size()


func trap_capacity() -> int:
	return Tuning.TRAP_CAPACITY[role] + int(meta("trap_cap"))


func masked() -> bool:
	return mt.time < masked_until


# ------------------------------------------------------------------------------
# Damage and health

## Resolves a killer's hit. Returns "parried", "wounded", "downed" or "none".
func take_hit(by: Killer, unparryable: bool = false, instant_down: bool = false) -> String:
	if health == Defs.Health.DOWNED or slot.outcome != "":
		return "none"
	if hidden_in != null:
		return "none"
	if not unparryable and mt.time <= parry_until:
		return "parried"
	if instant_down or health == Defs.Health.WOUNDED:
		go_down(by)
		return "downed"
	health = Defs.Health.WOUNDED
	boost_until = mt.time + Tuning.SURV_WOUND_BOOST_TIME
	cancel_channel()
	mt.make_noise(pos, 10.0, "scream", self)
	return "wounded"


func go_down(by: Killer) -> void:
	health = Defs.Health.DOWNED
	turn_left = Tuning.TURN_TIME + meta("turn")
	base_bonus_given = false
	downed_by = by
	boost_until = -1.0
	cancel_channel()
	release_pin()
	for p in parts:
		mt.drop_part(p, pos)
	parts.clear()
	mt.make_noise(pos, 16.0, "scream", self)
	mt.on_survivor_downed(self, by)


func heal_one() -> void:
	if health == Defs.Health.WOUNDED:
		health = Defs.Health.HEALTHY


func get_up() -> void:
	## Revived or cured: back on your feet, wounded, infection cleared.
	health = Defs.Health.WOUNDED
	turn_left = 0.0
	downed_by = null
	boost_until = mt.time + 1.0


func release_pin() -> void:
	if pinned_by != null:
		var k := pinned_by
		pinned_by = null
		k.tongue_released()


func cancel_channel() -> void:
	if not channel.is_empty():
		mt.interact.on_cancel(self, channel)
	channel = {}


# ------------------------------------------------------------------------------
# Per-frame

func tick(dt: float) -> void:
	var tm := mt.time
	if health == Defs.Health.DOWNED:
		turn_left -= dt
		if duo.base != null and duo.base.contains(pos) and not base_bonus_given:
			base_bonus_given = true
			turn_left += Tuning.BASE_TURN_BONUS
			mt.feed_to_duo(duo, "%s crawled home: %d more seconds before turning." % [slot.name, int(Tuning.BASE_TURN_BONUS)], "info")
		if turn_left <= 0.0:
			mt.on_turned(self)
			return
	# being pulled by a tongue
	if pinned_by != null:
		var to := pinned_by.pos - pos
		var d := to.length()
		if d < pinned_by.radius + radius + 0.35:
			pinned_by.tongue_arrived(self)
		else:
			move_by(to / d * Tuning.TONGUE_PULL * pinned_by.power_mult() * dt)
	crouch_amount = move_toward(crouch_amount, 1.0 if (crouched() and health != Defs.Health.DOWNED) else 0.0, dt * 5.0)
	downed_pose = move_toward(downed_pose, 1.0 if health == Defs.Health.DOWNED else 0.0, dt * 3.0)
	noise_cd -= dt


func _post_move(dt: float) -> void:
	if moved <= 0.0:
		return
	if want_move != Vector2.ZERO:
		face_dir(want_move if want_face == Vector2.ZERO else want_face, dt, 10.0)
	# footprints for the Tracker
	if not masked() and not want_crouch and health != Defs.Health.DOWNED:
		trail_acc += moved
		if trail_acc >= Tuning.TRAIL_INTERVAL:
			trail_acc = 0.0
			mt.add_trail(pos, self, false)
	if health != Defs.Health.HEALTHY and not masked():
		blood_acc += moved
		if blood_acc >= 2.2:
			blood_acc = 0.0
			mt.add_trail(pos, self, true)
	if want_run and not want_crouch and health == Defs.Health.HEALTHY and noise_cd <= 0.0 and moved > 0.03:
		noise_cd = 0.6
		mt.make_noise(pos, Tuning.NOISE_RUN * maxf(0.4, 1.0 - meta("quiet")), "steps", self)


func status_text() -> String:
	match health:
		Defs.Health.DOWNED:
			return "DOWNED — turning in %ds" % int(maxf(turn_left, 0.0))
		Defs.Health.WOUNDED:
			return "Wounded"
	return "Healthy"

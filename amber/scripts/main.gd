extends Node
## App root: input map, title menu, match lifecycle and command-line modes.

var menu: MainMenu
var mt: Match
var pc: PlayerController
var hud: Hud
var last_cfg := {}
# automated screenshots / autopilot (testing): --shots=DIR --times=2,60 --autopilot [--map_at=N]
var autopilot := false
var shot_dir := ""
var shot_times: Array = []
var shot_i := 0
var shot_wait := 0


func _ready() -> void:
	_setup_window()
	_setup_input()
	if Game.has_arg("ui_demo"):
		_ui_demo()
		return
	if Game.has_arg("input_smoke"):
		_input_smoke()
		return
	if Game.has_arg("video"):
		_video(Game.arg("video"))
		return
	if Game.has_arg("lineup"):
		_lineup(Game.arg("lineup"))
		return
	if Game.has_arg("soak"):
		_soak(Game.arg("soak"))
		return
	if Game.has_arg("play"):
		_start({"seed": int(Game.arg("seed", "7")), "side": Defs.Side.KILLER if Game.arg("play") == "killer" else Defs.Side.SURVIVOR,
			"role": int(Game.arg("role", "0")), "killer": int(Game.arg("killer", "0")), "card": int(Game.arg("card", "1")), "spectate": Game.arg("play") == "watch"})
	else:
		_show_menu()


var menu_layer: CanvasLayer


func _show_menu() -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	menu = MainMenu.new()
	menu_layer.add_child(menu)
	menu.start.connect(_start_with_loading)
	menu.quit_game.connect(func(): get_tree().quit())


const LOADING_TIPS := [
	"Drop off a ledge to lose a killer, and press E again as you land to roll.",
	"Squeeze through cracks in the walls. Only the Lurker can crawl in after you.",
	"Radio stages need parts, not money. Money builds walls, doors and traps.",
	"Your loadout is set before the match. Unlock items in the Survivor Kit tree.",
	"A perfect parry needs timing: press right mouse button as the swing lands.",
	"Calling the helicopter alerts the whole map. Hold the landing zone together.",
	"Killers tire after a long chase. Keep running.",
	"Every match earns Amber, win or lose. Spend it in the skill trees.",
]


## The menu's way in: shows a loading screen while the map and world are built.
func _start_with_loading(cfg: Dictionary) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.015, 0.01)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.position = Vector2(-450, -120)
	box.custom_minimum_size = Vector2(900, 240)
	box.add_theme_constant_override("separation", 22)
	layer.add_child(box)
	var title := Label.new()
	title.text = "ENTERING THE QUARANTINE ZONE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ts := LabelSettings.new()
	ts.font_size = 44
	ts.font_color = Defs.AMBER
	ts.shadow_size = 18
	ts.shadow_color = Color(1.0, 0.45, 0.0, 0.3)
	title.label_settings = ts
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Seed %d  ·  generating the town, the mines and the lab..." % int(cfg.get("seed", 0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ss := LabelSettings.new()
	ss.font_size = 18
	ss.font_color = Color(0.75, 0.7, 0.62)
	sub.label_settings = ss
	box.add_child(sub)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(900, 10)
	bar.show_percentage = false
	bar.value = 35
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.9, 0.5, 0.1)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	var tip := Label.new()
	tip.text = "TIP: " + LOADING_TIPS[randi() % LOADING_TIPS.size()]
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(900, 0)
	var tps := LabelSettings.new()
	tps.font_size = 20
	tps.font_color = Color(0.9, 0.86, 0.78)
	tip.label_settings = tps
	box.add_child(tip)
	# let the screen draw before the heavy build blocks the frame
	for i in 3:
		await get_tree().process_frame
	_start(cfg)
	bar.value = 100
	sub.text = "Ready."
	await get_tree().process_frame
	var tw := create_tween()
	tw.tween_property(bg, "modulate:a", 0.0, 0.6)
	tw.parallel().tween_property(box, "modulate:a", 0.0, 0.4)
	await tw.finished
	layer.queue_free()


func _start(cfg: Dictionary) -> void:
	last_cfg = cfg
	if menu:
		menu_layer.queue_free()
		menu = null
	mt = Match.new()
	add_child(mt)
	mt.setup(cfg, true)
	pc = PlayerController.new()
	mt.add_child(pc)
	pc.setup(mt)
	mt.controller = pc
	hud = Hud.new()
	add_child(hud)
	hud.setup(mt, pc)
	mt.hud = hud
	hud.quit_to_menu.connect(_to_menu)
	hud.play_again.connect(func():
		var c := last_cfg.duplicate()
		c["seed"] = randi() % 100000
		_teardown()
		_start_with_loading(c))
	if mt.player_slot != null and mt.player_slot.actor != null:
		pc.possess(mt.player_slot.actor)
	else:
		pc.spectating = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Game.has_arg("autopilot") and mt.player_slot != null and mt.player_slot.actor != null:
		autopilot = true
		_attach_autopilot()
	if Game.has_arg("shots"):
		shot_dir = Game.arg("shots")
		DirAccess.make_dir_recursive_absolute(shot_dir)
		for x in Game.arg("times", "2,60,150,300").split(","):
			shot_times.append(float(x))


func _teardown() -> void:
	if hud:
		hud.queue_free()
		hud = null
	if mt:
		mt.queue_free()
		mt = null
	pc = null


func _to_menu() -> void:
	_teardown()
	_show_menu()


func _setup_window() -> void:
	## The same stretch settings as project.godot, applied here too so the HUD keeps
	## its layout when the files are copied into another project.
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(1600, 900)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C], "interact": [KEY_E], "ability": [KEY_Q], "flashlight": [KEY_F],
		"build": [KEY_B], "lockdown": [KEY_L], "map": [KEY_TAB, KEY_M], "route": [KEY_R], "nest": [KEY_N], "pause": [KEY_ESCAPE],
		"help": [KEY_F1], "camera_toggle": [KEY_V], "shoulder_swap": [KEY_X], "donate": [KEY_G], "hatch_key": [KEY_H], "upgrade_spikes": [KEY_U], "upgrade_metal": [KEY_M],
		"tool_1": [KEY_1], "tool_2": [KEY_2], "tool_3": [KEY_3], "tool_4": [KEY_4], "tool_5": [KEY_5], "tool_6": [KEY_6],
		"tool_7": [KEY_7], "tool_8": [KEY_8], "tool_9": [KEY_9],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for pair in [["primary", MOUSE_BUTTON_LEFT], ["alt", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)


func _attach_autopilot() -> void:
	var a := mt.player_slot.actor
	if a is Survivor:
		mt.brains[a] = SurvivorAI.new(mt, a)
	elif a is Killer:
		mt.brains[a] = KillerAI.new(mt, a)
	pc.set_meta("autopilot", true)


func _process(_delta: float) -> void:
	if autopilot and mt != null and mt.player_slot != null:
		var a := mt.player_slot.actor
		if a != null and is_instance_valid(a) and not mt.brains.has(a):
			_attach_autopilot()
		if a != null and is_instance_valid(a):
			# smooth the bot's snappy turns so the recording reads like a player's view
			pc.yaw = lerp_angle(pc.yaw, a.facing, 0.12)
			pc.pitch = lerpf(pc.pitch, -0.06, 0.05)
	if shot_dir == "" or mt == null:
		return
	if shot_i >= shot_times.size() or mt.over:
		get_tree().quit()
		return
	var target: float = shot_times[shot_i]
	if mt.time < target - 0.6:
		var guard := 0
		while mt.time < target - 0.6 and not mt.over and guard < 4000:
			mt.step(0.05)
			guard += 1
		shot_wait = 0
		return
	shot_wait += 1
	hud.force_map = Game.has_arg("map_at") and int(Game.arg("map_at")) == shot_i
	if shot_wait < 12:
		return
	var img := get_viewport().get_texture().get_image()
	var path := "%s/shot_%02d_%03ds.png" % [shot_dir, shot_i, int(mt.time)]
	img.save_png(path)
	print("saved ", path)
	shot_i += 1
	shot_wait = 0


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var dir := Game.arg("ui_demo")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("saved ", name)


func _ui_demo() -> void:
	## Walks through the screens bots never open, saving a screenshot of each.
	_show_menu()
	await get_tree().create_timer(1.0).timeout
	await _snap("ui_0_menu")
	# a profile a few matches in (demo only: test runs never save)
	Progression.ensure()
	Progression.profile["lifetime"] = 5200
	Progression.profile["amber"] = 2350
	for id in ["flare_gun", "phosphor", "medkit", "dressing", "scanner", "keen_eyes", "keen_eyes", "dressing"]:
		Progression.profile["ranks"][id] = Progression.rank(id) + (1 if Progression.rank(id) < Progression.node_def(id)[3] else 0)
	Progression.profile["loadout"] = ["flare", "medkit", ""]
	menu._open_progression()
	await get_tree().create_timer(0.6).timeout
	await _snap("ui_0b_trees_kit")
	menu.prog_menu._show_tree("brute")
	await get_tree().create_timer(0.4).timeout
	await _snap("ui_0c_trees_brute")
	menu.prog_menu.closed.emit()
	_start({"seed": 21, "side": Defs.Side.SURVIVOR, "role": Defs.Role.ENGINEER, "card": 1, "spectate": false})
	var me := mt.player_slot.actor as Survivor
	# skip ahead: out of the cell, with money and scrap, and a base
	open_and_setup(me)
	await get_tree().create_timer(1.5).timeout
	pc.build_mode = true
	pc.pitch = -0.6
	await get_tree().create_timer(0.5).timeout
	await _snap("ui_2_build")
	pc.build_mode = false
	# get caught: pick an elite class
	mt.on_caught(me, mt.killers[0] as Killer)
	await get_tree().create_timer(0.5).timeout
	await _snap("ui_3_elite_pick")
	hud.choice_panel.visible = false
	hud._set_block(false)
	mt._end_match("demo")
	await get_tree().create_timer(0.5).timeout
	await _snap("ui_4_results")
	get_tree().quit()


func open_and_setup(me: Survivor) -> void:
	mt.open_cell(me.duo.cell)
	me.duo.money = 420
	me.duo.scrap = 12
	# find open ground near the cell for a base
	for r in range(3, 14):
		var p := me.pos + Vector2(r * 2.0, 0)
		if mt.base_site_ok(p, me.duo):
			me.pos = p
			break
	mt.bases.claim(me)
	var stand := mt.nav.snap(MapData.tile_of(me.pos) + Vector2i(-2, 1), true)
	if stand.x >= 0:
		me.pos = MapData.center_of(stand)
	pc.yaw = Actor.yaw_of(me.duo.base.pos - me.pos) if me.duo.base else 0.0


func _tap(action: String, frames: int = 2) -> void:
	Input.action_press(action)
	for i in frames:
		await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame


func _input_smoke() -> void:
	## Presses every action in survivor and killer matches; any script error shows in the log.
	for side in [Defs.Side.SURVIVOR, Defs.Side.KILLER]:
		for role_or_killer in 3:
			_start({"seed": 30 + role_or_killer, "side": side, "role": role_or_killer, "killer": role_or_killer, "card": role_or_killer, "spectate": false})
			var me = mt.player_slot.actor
			if side == Defs.Side.SURVIVOR:
				open_and_setup(me)
				me.flare = 1
				me.traps = [2, 2]
				me.cure = 1
			# fast-forward past the killer release so everything is live
			while mt.time < 45.0:
				mt.step(0.05)
			for a in ["move_forward", "run", "crouch", "interact", "ability", "flashlight", "tool_1", "primary", "tool_2", "primary", "tool_3", "primary", "alt", "lockdown", "donate", "route", "nest", "map"]:
				await _tap(a, 3)
			# build mode: cycle and place every structure type
			await _tap("build")
			for t in ["tool_1", "tool_2", "tool_3", "tool_4", "tool_5", "tool_6", "tool_7", "tool_8", "tool_9", "hatch_key"]:
				await _tap(t)
				await _tap("primary")
			await _tap("upgrade_spikes")
			await _tap("upgrade_metal")
			await _tap("alt")
			# pause and resume
			await _tap("pause")
			await _tap("pause")
			# take a hit / get downed / get caught as a survivor
			if side == Defs.Side.SURVIVOR and is_instance_valid(me) and me is Survivor:
				var k: Killer = mt.killers[0]
				me.take_hit(k)
				mt.on_hit(me, k, "wounded")
				me.take_hit(k)
				for i in 30:
					await get_tree().process_frame
				me.cure = 1
				await _tap("interact", 5)
				mt.on_caught(me, k)
				if hud.choice_panel.visible:
					hud.choice_panel.visible = false
					hud._set_block(false)
				while mt.time < 140.0 and not mt.over:
					mt.step(0.05)
				for i in 10:
					await get_tree().process_frame
				print("smoke: survivor role %d done; now playing as %s" % [role_or_killer, "elite" if mt.player_slot.actor is Killer else "spectator"])
			else:
				print("smoke: killer %d done" % role_or_killer)
			mt._end_match("smoke")
			for i in 5:
				await get_tree().process_frame
			_teardown()
			for i in 3:
				await get_tree().process_frame
	# watch mode
	_start({"seed": 40, "spectate": true})
	for i in 60:
		await get_tree().process_frame
	await _tap("primary")
	print("smoke: watch mode done")
	get_tree().quit()


# ------------------------------------------------------------------------------
# Video director (--video=survivor|killer, run with --write-movie): records
# stretches of autopilot play, fast-forwarding between them.

func _ff_to(t: float) -> void:
	while mt != null and not mt.over and mt.time < t:
		mt.step(0.05)


func _ff_until(cond: Callable, limit: float) -> bool:
	while mt != null and not mt.over and mt.time < limit:
		mt.step(0.05)
		if cond.call():
			return true
	return false


func _record(seconds: float, show_map: bool = false) -> void:
	var end_t := mt.time + seconds
	hud.force_map = show_map
	while mt != null and not mt.over and mt.time < end_t:
		await get_tree().process_frame
	hud.force_map = false


# Character lineup (--lineup=DIR): every character model side by side, in a few poses.
func _lineup(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var stage := Node3D.new()
	add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.02, 0.025)
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.environment.ambient_light_energy = 0.25
	env.environment.fog_enabled = true
	env.environment.fog_light_color = Color(0.08, 0.08, 0.09)
	env.environment.fog_density = 0.02
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	stage.add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 1.0, 4.5)
	rim.omni_range = 16.0
	rim.light_color = Color(1.0, 0.6, 0.3)
	rim.light_energy = 1.5
	stage.add_child(rim)
	Models.box(stage, Vector3(40, 0.1, 30), Mats.flat(Color(0.12, 0.11, 0.1)), Vector3(0, -0.05, -3))
	var lineup := [["survivor", {"color": Defs.ROLE_COLORS[0], "role": 0, "variant": 0}], ["survivor", {"color": Defs.ROLE_COLORS[1], "role": 1, "variant": 1}],
		["survivor", {"color": Defs.ROLE_COLORS[2], "role": 2, "variant": 2}], ["elite", {"color": Color(0.6, 0.2, 0.2)}]]
	for sl in Defs.KILLER_SLOTS:
		lineup.append([sl, {}])
	var models: Array = []
	for i in lineup.size():
		var n := Models.make(lineup[i][0], lineup[i][1])
		var killer_row := i >= 4
		n.position = Vector3((i - 1.5) * 1.6, 0, -6.0) if not killer_row else Vector3((i - 4 - 3.5) * 2.4, 0, 0)
		n.rotation.y = PI
		stage.add_child(n)
		models.append(n)
	var cam := Camera3D.new()
	cam.fov = 50
	stage.add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 1.7, 11.5)
	cam.look_at(Vector3(0, 1.1, 0))
	for f in 3:
		await get_tree().process_frame
	await _snap_to(dir, "lineup_killers")
	for k in 4:
		cam.position = Vector3((k * 2 - 3.5 + 0.5) * 2.4, 1.5, 4.0)
		cam.look_at(Vector3((k * 2 - 3.5 + 0.5) * 2.4, 1.2, 0))
		await _snap_to(dir, "lineup_killers_pair%d" % k)
	cam.position = Vector3(0, 1.4, -1.5)
	cam.look_at(Vector3(0, 1.0, -6.0))
	await _snap_to(dir, "lineup_survivors")
	get_tree().quit()


func _snap_to(dir: String, name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])


# Soak test (--soak=survivor|killer|watch): a whole match with the HUD, map and
# autopilot, fast-forwarded about 1 s of match time per frame, to catch runtime errors.
func _soak(side: String) -> void:
	_start({"seed": int(Game.arg("seed", "5")), "side": Defs.Side.KILLER if side == "killer" else Defs.Side.SURVIVOR,
		"role": int(Game.arg("role", "0")), "killer": int(Game.arg("killer", "0")), "card": int(Game.arg("card", "1")),
		"spectate": side == "watch"})
	if side != "watch":
		autopilot = true
		_attach_autopilot()
	var frames := 0
	while mt != null and not mt.over:
		for i in 20:
			if mt.over:
				break
			mt.step(0.05)
		hud.force_map = frames % 3 == 0
		frames += 1
		await get_tree().process_frame
	print("soak: %s seed %d finished at %s (%s), %d frames" % [side, mt.cfg.get("seed", 0), Match.fmt_time(mt.time), mt.result.get("reason", "?"), frames])
	for i in 30:
		await get_tree().process_frame
	get_tree().quit()


func _killer_near_player(dist: float) -> bool:
	var a = mt.player_slot.actor
	if a == null or not is_instance_valid(a):
		return false
	for k in mt.killers:
		if k.released and k.is_main() and k.pos.distance_to(a.pos) < dist and mt.m.los(a.pos, a.y + 1.6, k.pos, k.y + 1.4):
			return true
	return false


func _video(plan: String) -> void:
	var killer := plan == "killer"
	_start({"seed": int(Game.arg("seed", "11")), "side": Defs.Side.KILLER if killer else Defs.Side.SURVIVOR,
		"role": int(Game.arg("role", "0")), "killer": int(Game.arg("killer", "2")), "card": int(Game.arg("card", "1")),
		"spectate": false, "difficulty": 1})
	autopilot = true
	_attach_autopilot()
	pc.flash_on = true
	if not killer:
		await _record(16.0)                     # locked in, picking the cell lock with your partner
		_ff_to(34.0)
		await _record(10.0)                     # out, scavenging, killers released
		_ff_to(150.0)
		await _record(5.0, true)                # the map (Tab)
		if _ff_until(func(): return _killer_near_player(16.0), 900.0):
			await _record(16.0)                 # a killer closes in
		if _ff_until(func(): return mt.player_slot.duo != null and mt.player_slot.duo.base != null and mt.player_slot.duo.base.stage >= 2, 1200.0):
			await _record(8.0)
		if _ff_until(func(): return _killer_near_player(12.0), 1500.0):
			await _record(14.0)
	else:
		await _record(6.0)                      # waiting at the Nest
		_ff_to(Tuning.KILLER_RELEASE - 1.0)
		await _record(12.0)                     # released into the lab
		var hunting := func():
			var ai = mt.brains.get(mt.player_slot.actor)
			return ai != null and ai.state == "chase" and ai.target != null and is_instance_valid(ai.target) and ai.target.pos.distance_to(mt.player_slot.actor.pos) < 13.0
		if _ff_until(hunting, 600.0):
			await _record(18.0)                 # a chase
		_ff_to(mt.time + 60.0)
		await _record(5.0, true)                # the killer's map: hot zones, noises, known bases
		if _ff_until(hunting, 1200.0):
			await _record(18.0)
	get_tree().quit()

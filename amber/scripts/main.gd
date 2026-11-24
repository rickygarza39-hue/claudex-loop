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
	_setup_input()
	if Game.has_arg("ui_demo"):
		_ui_demo()
		return
	if Game.has_arg("input_smoke"):
		_input_smoke()
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
	menu.start.connect(_start)
	menu.quit_game.connect(func(): get_tree().quit())


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
		_start(c))
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


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C], "interact": [KEY_E], "ability": [KEY_Q], "flashlight": [KEY_F],
		"build": [KEY_B], "lockdown": [KEY_L], "map": [KEY_TAB, KEY_M], "route": [KEY_R], "nest": [KEY_N], "pause": [KEY_ESCAPE],
		"help": [KEY_F1], "donate": [KEY_G], "hatch_key": [KEY_H], "upgrade_spikes": [KEY_U], "upgrade_metal": [KEY_M],
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
			pc.yaw = a.facing
			pc.pitch = lerpf(pc.pitch, -0.12, 0.1)
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
	_start({"seed": 21, "side": Defs.Side.SURVIVOR, "role": Defs.Role.ENGINEER, "card": 1, "spectate": false})
	var me := mt.player_slot.actor as Survivor
	# skip ahead: out of the cell, with money and scrap, a base and an open shop
	open_and_setup(me)
	await get_tree().create_timer(1.5).timeout
	hud.open_shop(mt.shop.terminals[0])
	await _snap("ui_1_shop")
	hud.close_shop()
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
	for t in mt.shop.terminals:
		t["open"] = true
		mt.shop._paint(t)


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

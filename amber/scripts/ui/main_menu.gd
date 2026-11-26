class_name MainMenu
extends Control
## Title screen: pick a side, a role or killer, the Nest card and a seed.

signal start(cfg: Dictionary)
signal quit_game

var side := Defs.Side.SURVIVOR
var role := Defs.Role.ENGINEER
var killer := Defs.K.TRACKER
var card := Defs.Card.PULSE
var spectate := false
var difficulty := 1
var diff_buttons: Array = []
var seed_edit: LineEdit
var role_box: HBoxContainer
var killer_box: VBoxContainer
var survivor_box: VBoxContainer
var info: RichTextLabel
var role_buttons: Array = []
var killer_buttons: Array = []
var card_buttons: Array = []
var side_buttons: Array = []
var prog_button: Button
var prog_menu: ProgressionMenu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float t = 0.0;
void fragment() {
	vec2 uv = UV - vec2(0.5, 0.35);
	float glow = exp(-dot(uv * vec2(1.2, 2.2), uv * vec2(1.2, 2.2)) * 6.0);
	float flick = 0.9 + 0.1 * sin(TIME * 7.0) * sin(TIME * 2.3);
	vec3 col = mix(vec3(0.02, 0.022, 0.025), vec3(0.55, 0.28, 0.05), glow * 0.55 * flick);
	float grain = fract(sin(dot(UV * 800.0 + TIME, vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(col + grain * 0.025, 1.0);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	bg.material = mat
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(900, 0)
	center.add_child(col)
	var title := Label.new()
	title.text = "A M B E R"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ts := LabelSettings.new()
	ts.font_size = 84
	ts.font_color = Defs.AMBER
	ts.outline_size = 14
	ts.outline_color = Color(0.1, 0.04, 0.0)
	ts.shadow_size = 24
	ts.shadow_color = Color(1.0, 0.5, 0.0, 0.25)
	title.label_settings = ts
	col.add_child(title)
	var sub := _lbl("Ten survivors. Three killers. One quarantined mining town.\nBuild your radio, call the helicopter, get out — or join the hunt.", 18, Color(0.85, 0.8, 0.72))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	# side choice
	var sides := HBoxContainer.new()
	sides.alignment = BoxContainer.ALIGNMENT_CENTER
	sides.add_theme_constant_override("separation", 12)
	col.add_child(sides)
	side_buttons = [
		_toggle("Play as a survivor", func(): _set_side(Defs.Side.SURVIVOR, false)),
		_toggle("Play as a killer", func(): _set_side(Defs.Side.KILLER, false)),
		_toggle("Watch the bots", func(): _set_side(Defs.Side.SURVIVOR, true)),
	]
	for b in side_buttons:
		sides.add_child(b)
	# survivor roles
	survivor_box = VBoxContainer.new()
	col.add_child(survivor_box)
	role_box = HBoxContainer.new()
	role_box.alignment = BoxContainer.ALIGNMENT_CENTER
	role_box.add_theme_constant_override("separation", 10)
	survivor_box.add_child(role_box)
	for i in 3:
		var idx := i
		var b := _toggle(Defs.ROLE_NAMES[i], func(): _set_role(idx))
		role_buttons.append(b)
		role_box.add_child(b)
	# killers
	killer_box = VBoxContainer.new()
	col.add_child(killer_box)
	var kc := CenterContainer.new()
	killer_box.add_child(kc)
	var kb := GridContainer.new()
	kb.columns = 4
	kb.add_theme_constant_override("h_separation", 10)
	kb.add_theme_constant_override("v_separation", 8)
	kc.add_child(kb)
	for i in Defs.KILLER_NAMES.size():
		var idx2 := i
		var b2 := _toggle(Defs.KILLER_NAMES[i], func(): _set_killer(idx2))
		killer_buttons.append(b2)
		kb.add_child(b2)
	var cl := _lbl("Nest event card (the killer team's pick):", 16, Color(0.85, 0.8, 0.72))
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	killer_box.add_child(cl)
	var cb := HBoxContainer.new()
	cb.alignment = BoxContainer.ALIGNMENT_CENTER
	cb.add_theme_constant_override("separation", 10)
	killer_box.add_child(cb)
	for i in 4:
		var idx3 := i
		var b3 := _toggle(Defs.CARD_NAMES[i], func(): _set_card(idx3))
		card_buttons.append(b3)
		cb.add_child(b3)
	info = RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.custom_minimum_size = Vector2(900, 60)
	info.add_theme_font_size_override("normal_font_size", 17)
	col.add_child(info)
	# seed + settings
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	row.add_child(_lbl("Map seed:", 17))
	seed_edit = LineEdit.new()
	seed_edit.text = str(randi() % 100000)
	seed_edit.custom_minimum_size = Vector2(140, 36)
	row.add_child(seed_edit)
	var rb := Button.new()
	rb.text = "Shuffle"
	rb.pressed.connect(func(): seed_edit.text = str(randi() % 100000))
	row.add_child(rb)
	row.add_child(_lbl("   Mouse:", 17))
	var sens := HSlider.new()
	sens.min_value = 0.0006
	sens.max_value = 0.006
	sens.step = 0.0001
	sens.value = Game.mouse_sensitivity
	sens.custom_minimum_size = Vector2(180, 30)
	sens.value_changed.connect(func(v): Game.mouse_sensitivity = v)
	row.add_child(sens)
	var inv := CheckBox.new()
	inv.text = "Invert Y"
	inv.button_pressed = Game.invert_y
	inv.toggled.connect(func(v): Game.invert_y = v)
	row.add_child(inv)
	var drow := HBoxContainer.new()
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	drow.add_theme_constant_override("separation", 10)
	col.add_child(drow)
	drow.add_child(_lbl("Bot difficulty:", 17))
	for i in 3:
		var idx4 := i
		var db := _toggle(["Easy", "Normal", "Hard"][i], func(): _set_diff(idx4))
		db.custom_minimum_size = Vector2(120, 36)
		diff_buttons.append(db)
		drow.add_child(db)
	_set_diff(1)
	prog_button = Button.new()
	prog_button.custom_minimum_size = Vector2(0, 46)
	prog_button.add_theme_font_size_override("font_size", 19)
	prog_button.pressed.connect(_open_progression)
	col.add_child(prog_button)
	_update_prog_button()
	var go := Button.new()
	go.text = "ENTER THE QUARANTINE ZONE"
	go.custom_minimum_size = Vector2(0, 56)
	go.add_theme_font_size_override("font_size", 24)
	go.pressed.connect(_go)
	col.add_child(go)
	var help := _lbl("F1 in-game: controls   ·   Tab: map   ·   Esc: pause", 15, Color(0.65, 0.62, 0.56))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(help)
	var q := Button.new()
	q.text = "Quit"
	q.pressed.connect(func(): quit_game.emit())
	col.add_child(q)
	_set_side(Defs.Side.SURVIVOR, false)
	_set_role(Defs.Role.ENGINEER)
	_set_killer(Defs.K.TRACKER)
	_set_card(Defs.Card.PULSE)


func _update_prog_button() -> void:
	var lp := Progression.level_progress()
	var lo := Progression.loadout()
	var names: Array = []
	for it in lo:
		names.append(Progression.ITEMS[it]["name"])
	prog_button.text = "SKILL TREES & LOADOUT   ·   Level %d   ·   %d Amber   ·   Loadout: %s" % [lp[0], Progression.amber(), ", ".join(names) if not names.is_empty() else "empty"]


func _open_progression() -> void:
	prog_menu = ProgressionMenu.new()
	add_child(prog_menu)
	prog_menu.closed.connect(func():
		prog_menu.queue_free()
		prog_menu = null
		_update_prog_button())


func _lbl(t: String, size: int, c: Color = Color(0.9, 0.88, 0.82)) -> Label:
	var l := Label.new()
	l.text = t
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = c
	ls.outline_size = 4
	ls.outline_color = Color(0, 0, 0)
	l.label_settings = ls
	return l


func _toggle(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(190, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b


func _set_side(s: int, spec: bool) -> void:
	side = s
	spectate = spec
	for i in side_buttons.size():
		side_buttons[i].button_pressed = (i == 0 and s == Defs.Side.SURVIVOR and not spec) or (i == 1 and s == Defs.Side.KILLER) or (i == 2 and spec)
	survivor_box.visible = s == Defs.Side.SURVIVOR and not spec
	killer_box.visible = s == Defs.Side.KILLER
	_info()


func _set_diff(d: int) -> void:
	difficulty = d
	for i in diff_buttons.size():
		diff_buttons[i].button_pressed = i == d


func _set_role(r: int) -> void:
	role = r
	for i in 3:
		role_buttons[i].button_pressed = i == r
	_info()


func _set_killer(k: int) -> void:
	killer = k
	for i in killer_buttons.size():
		killer_buttons[i].button_pressed = i == k
	_info()


func _set_card(c: int) -> void:
	card = c
	for i in 4:
		card_buttons[i].button_pressed = i == c
	_info()


func _info() -> void:
	if info == null:
		return
	if spectate:
		info.text = "[center]All 13 slots are bots. Fly along with any of them (left click to switch, Tab for the map).[/center]"
	elif side == Defs.Side.SURVIVOR:
		info.text = "[center][b]%s[/b] — %s\nYour partner is a bot. Four more bot duos are trying to get out too.[/center]" % [Defs.ROLE_NAMES[role], Defs.ROLE_BLURBS[role]]
	else:
		info.text = "[center][b]%s[/b] — %s\n[b]%s[/b]: %s[/center]" % [Defs.KILLER_NAMES[killer], Defs.KILLER_BLURBS[killer], Defs.CARD_NAMES[card], Defs.CARD_BLURBS[card]]


func _go() -> void:
	var sd := int(seed_edit.text) if seed_edit.text.is_valid_int() else randi() % 100000
	start.emit({"seed": sd, "side": side, "role": role, "killer": killer, "card": card if side == Defs.Side.KILLER else randi() % 4, "spectate": spectate, "difficulty": difficulty})

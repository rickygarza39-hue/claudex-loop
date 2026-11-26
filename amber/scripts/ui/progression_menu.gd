class_name ProgressionMenu
extends Control
## Skill trees and loadout, opened from the title screen.
## Diablo-style trees: three branches, four tiers each, tiers open as you spend points.

signal closed

const C_GOLD := Color(1.0, 0.72, 0.25)
const C_TEXT := Color(0.88, 0.84, 0.76)
const C_DIM := Color(0.55, 0.52, 0.48)
const TREE_ORDER := ["kit", "engineer", "medic", "trapper", "tracker", "brute", "lurker", "foreman", "hollow", "furnace", "tally", "choir"]

var tree_id := "kit"
var tab_buttons: Array = []
var amber_lbl: Label
var level_lbl: Label
var level_bar: ProgressBar
var body: HBoxContainer
var footer: HBoxContainer
var loadout_row: HBoxContainer
var msg: Label


func _ready() -> void:
	Progression.ensure()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.02, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	# header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	col.add_child(head)
	head.add_child(_lbl("SKILL TREES & LOADOUT", 30, C_GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	level_lbl = _lbl("", 18, C_TEXT)
	head.add_child(level_lbl)
	level_bar = ProgressBar.new()
	level_bar.custom_minimum_size = Vector2(220, 20)
	level_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.5, 0.1)
	level_bar.add_theme_stylebox_override("fill", fill)
	head.add_child(level_bar)
	amber_lbl = _lbl("", 22, C_GOLD)
	head.add_child(amber_lbl)
	var close := Button.new()
	close.text = "Back"
	close.custom_minimum_size = Vector2(110, 40)
	close.pressed.connect(func(): closed.emit())
	head.add_child(close)
	var intro := _lbl("Earn Amber by playing: surviving, building, saving, stunning and escaping, or hitting and catching as a killer. Amber raises your level and buys ranks. A tier opens once you've spent enough points in that tree.", 15, C_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(1200, 0)
	col.add_child(intro)
	# tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	col.add_child(tabs)
	for tid in TREE_ORDER:
		var b := Button.new()
		b.text = Progression.TREES[tid]["name"]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(118, 38)
		b.add_theme_font_size_override("font_size", 14)
		var t2: String = tid
		b.pressed.connect(func(): _show_tree(t2))
		tabs.add_child(b)
		tab_buttons.append(b)
	# tree body
	body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	# loadout + respec
	footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	col.add_child(footer)
	loadout_row = HBoxContainer.new()
	loadout_row.add_theme_constant_override("separation", 10)
	loadout_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(loadout_row)
	var respec := Button.new()
	respec.text = "Reset this tree (80% back)"
	respec.custom_minimum_size = Vector2(240, 40)
	respec.pressed.connect(func():
		var got := Progression.respec(tree_id)
		_say("Refunded %d Amber." % got)
		_refresh())
	footer.add_child(respec)
	msg = _lbl("", 16, Color(1.0, 0.6, 0.5))
	col.add_child(msg)
	_show_tree("kit")


func _show_tree(tid: String) -> void:
	tree_id = tid
	for i in TREE_ORDER.size():
		tab_buttons[i].button_pressed = TREE_ORDER[i] == tid
	_refresh()


func _refresh() -> void:
	var lp := Progression.level_progress()
	level_lbl.text = "Level %d" % lp[0]
	level_bar.max_value = lp[2]
	level_bar.value = lp[1]
	level_bar.tooltip_text = "%d / %d Amber to level %d" % [lp[1], lp[2], lp[0] + 1]
	amber_lbl.text = "%d Amber" % Progression.amber()
	for c in body.get_children():
		c.queue_free()
	var tree: Dictionary = Progression.TREES[tree_id]
	var spent := Progression.spent_in(tree_id)
	for br in tree["branches"]:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color(0.08, 0.05, 0.04, 0.95)
		ps.border_color = Color(0.45, 0.22, 0.08)
		ps.set_border_width_all(2)
		ps.set_corner_radius_all(6)
		ps.set_content_margin_all(12)
		panel.add_theme_stylebox_override("panel", ps)
		body.add_child(panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		panel.add_child(v)
		var t := _lbl(br[0].to_upper(), 22, C_GOLD)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
		for i in br[1].size():
			var n: Array = br[1][i]
			if i > 0:
				var link := _lbl("│", 18, C_DIM if Progression.rank(br[1][i - 1][0]) == 0 else C_GOLD)
				link.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				v.add_child(link)
			v.add_child(_node_button(n, spent))
	_fill_loadout()


func _node_button(n: Array, spent: int) -> Button:
	var r := Progression.rank(n[0])
	var maxed: bool = r >= n[3]
	var tier_open: bool = spent >= Progression.TIER_GATE[n[2] - 1]
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 92)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cap := "   ★ CAPSTONE" if n[2] == 4 else ""
	var line2 := Progression.describe(n, r + (0 if maxed else 1))
	var line3 := ""
	if maxed:
		line3 = "Maxed"
	elif not tier_open:
		line3 = "Tier %d opens at %d points spent here (%d so far)" % [n[2], Progression.TIER_GATE[n[2] - 1], spent]
	else:
		line3 = "Rank %d: %d Amber" % [r + 1, Progression.rank_cost(n, r)]
	b.text = "%s   %d/%d%s\n%s\n%s" % [n[1], r, n[3], cap, line2, line3]
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	if maxed:
		sb.bg_color = Color(0.32, 0.2, 0.05)
		sb.border_color = C_GOLD
	elif r > 0:
		sb.bg_color = Color(0.2, 0.12, 0.05)
		sb.border_color = Color(0.85, 0.5, 0.15)
	elif tier_open:
		sb.bg_color = Color(0.13, 0.09, 0.07)
		sb.border_color = Color(0.5, 0.32, 0.18)
	else:
		sb.bg_color = Color(0.07, 0.06, 0.06)
		sb.border_color = Color(0.2, 0.18, 0.17)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.border_color = Color(1.0, 0.8, 0.4)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_color_override("font_color", C_TEXT if tier_open or r > 0 else C_DIM)
	b.add_theme_font_size_override("font_size", 15)
	var id: String = n[0]
	b.pressed.connect(func():
		var e := Progression.buy(id)
		_say(e if e != "" else "Bought %s rank %d." % [n[1], Progression.rank(id)])
		_refresh())
	return b


func _fill_loadout() -> void:
	for c in loadout_row.get_children():
		c.queue_free()
	var side: String = Progression.TREES[tree_id]["side"]
	if side != "survivor":
		loadout_row.add_child(_lbl("Killers carry no items. Their trees shape their powers and stamina.", 16, C_DIM))
		return
	loadout_row.add_child(_lbl("LOADOUT", 20, C_GOLD))
	var slots := Progression.loadout_slots()
	for i in 3:
		if i >= slots:
			loadout_row.add_child(_lbl("[slot %d: level %d]" % [i + 1, Progression.SLOT_LEVELS[i]], 15, C_DIM))
			continue
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(190, 38)
		ob.add_item("— empty —")
		ob.set_item_metadata(0, "")
		var cur: String = Progression.profile["loadout"][i]
		for it in Progression.ITEMS:
			if Progression.item_unlocked(it):
				ob.add_item(Progression.ITEMS[it]["name"])
				var idx := ob.item_count - 1
				ob.set_item_metadata(idx, it)
				ob.set_item_tooltip(idx, Progression.ITEMS[it]["desc"])
				if it == cur:
					ob.select(idx)
		var si := i
		ob.item_selected.connect(func(idx2: int):
			var it2: String = ob.get_item_metadata(idx2)
			if it2 != "" and Progression.loadout().has(it2) and Progression.profile["loadout"][si] != it2:
				_say("That item is already in another slot.")
				_refresh()
				return
			Progression.set_loadout(si, it2)
			_say("Loadout saved."))
		loadout_row.add_child(ob)


func _say(t: String) -> void:
	msg.text = t


func _lbl(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = c
	ls.outline_size = 3
	ls.outline_color = Color(0, 0, 0)
	l.label_settings = ls
	return l

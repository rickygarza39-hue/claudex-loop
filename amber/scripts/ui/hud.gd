class_name Hud
extends CanvasLayer
## In-match interface: prompts, status, radio checklist, feed, map, shop, build,
## elite choices, pause menu and results.

signal quit_to_menu
signal play_again

var mt: Match
var pc: PlayerController

var root: Control
var crosshair: Control
var prompt: Label
var prompt_bar: ProgressBar
var status: Label
var tools: Label
var duo_panel: PanelContainer
var duo_text: RichTextLabel
var clock: Label
var feed_box: VBoxContainer
var alert: Label
var alert_t := 0.0
var toast_lbl: Label
var toast_t := 0.0
var vignette: ColorRect
var flash: ColorRect
var hurt: ColorRect
var map_layer: Control
var map_view: MapView
var shop_panel: PanelContainer
var shop_list: VBoxContainer
var shop_term: Dictionary = {}
var build_panel: PanelContainer
var build_text: RichTextLabel
var choice_panel: PanelContainer
var choice_box: VBoxContainer
var pause_panel: PanelContainer
var results_panel: PanelContainer
var help_panel: PanelContainer
var feed_items: Array = []
var last_health := -1
var beat_t := 0.0
var spectator_lbl: Label
var force_map := false


func setup(match_ref: Match, controller: PlayerController) -> void:
	mt = match_ref
	pc = controller
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build()
	mt.feed_msg.connect(_on_feed)
	mt.match_over.connect(_on_over)


# ------------------------------------------------------------------------------
# Construction helpers

func _label(size: int, color: Color = Color(0.92, 0.9, 0.85), outline: int = 6) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = Color(0, 0, 0, 0.85)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(alpha: float = 0.72) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.045, 0.04, alpha)
	sb.border_color = Color(0.85, 0.55, 0.15, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	return p


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b


func _build() -> void:
	# overlays first so text draws on top
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = """shader_type canvas_item;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.6, 0.0, 0.0, 1.0);
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.4, 1.0));
	float a = smoothstep(0.35, 0.85, d) * amount;
	COLOR = vec4(tint.rgb, a);
}"""
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vignette.material = vm
	root.add_child(vignette)
	hurt = ColorRect.new()
	hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt.color = Color(0.7, 0.0, 0.0, 0.0)
	hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hurt)
	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	# crosshair
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(func():
		crosshair.draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1, 0.75))
		crosshair.draw_arc(Vector2.ZERO, 7.0, 0, TAU, 24, Color(1, 1, 1, 0.18), 1.0))
	root.add_child(crosshair)
	# interaction prompt
	prompt = _label(22)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position = Vector2(-400, -230)
	prompt.size = Vector2(800, 30)
	root.add_child(prompt)
	prompt_bar = ProgressBar.new()
	prompt_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_bar.position = Vector2(-160, -195)
	prompt_bar.size = Vector2(320, 14)
	prompt_bar.show_percentage = false
	prompt_bar.max_value = 1.0
	prompt_bar.visible = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.62, 0.15)
	fill.set_corner_radius_all(3)
	var bgsb := StyleBoxFlat.new()
	bgsb.bg_color = Color(0, 0, 0, 0.6)
	bgsb.set_corner_radius_all(3)
	prompt_bar.add_theme_stylebox_override("fill", fill)
	prompt_bar.add_theme_stylebox_override("background", bgsb)
	root.add_child(prompt_bar)
	# status (bottom left)
	var sp := _panel(0.6)
	sp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	sp.position = Vector2(18, -190)
	sp.custom_minimum_size = Vector2(420, 0)
	root.add_child(sp)
	var sv := VBoxContainer.new()
	sp.add_child(sv)
	status = _label(18)
	sv.add_child(status)
	tools = _label(16, Color(0.85, 0.82, 0.75))
	sv.add_child(tools)
	# duo / radio panel (top right)
	duo_panel = _panel(0.62)
	duo_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	duo_panel.position = Vector2(-410, 16)
	duo_panel.custom_minimum_size = Vector2(390, 0)
	root.add_child(duo_panel)
	duo_text = RichTextLabel.new()
	duo_text.bbcode_enabled = true
	duo_text.fit_content = true
	duo_text.scroll_active = false
	duo_text.custom_minimum_size = Vector2(370, 10)
	duo_text.add_theme_font_size_override("normal_font_size", 16)
	duo_text.add_theme_font_size_override("bold_font_size", 17)
	duo_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	duo_panel.add_child(duo_text)
	# clock (top centre)
	clock = _label(22)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.set_anchors_preset(Control.PRESET_CENTER_TOP)
	clock.position = Vector2(-350, 12)
	clock.size = Vector2(700, 30)
	root.add_child(clock)
	# feed (top left)
	feed_box = VBoxContainer.new()
	feed_box.position = Vector2(18, 16)
	feed_box.custom_minimum_size = Vector2(560, 0)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed_box)
	# big alert
	alert = _label(34, Color(1.0, 0.75, 0.3), 10)
	alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alert.set_anchors_preset(Control.PRESET_CENTER)
	alert.position = Vector2(-600, -170)
	alert.size = Vector2(1200, 50)
	alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(alert)
	toast_lbl = _label(19, Color(1, 0.9, 0.7))
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_lbl.position = Vector2(-450, -270)
	toast_lbl.size = Vector2(900, 30)
	root.add_child(toast_lbl)
	spectator_lbl = _label(20, Color(0.8, 0.85, 1.0))
	spectator_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spectator_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	spectator_lbl.position = Vector2(-450, -120)
	spectator_lbl.size = Vector2(900, 30)
	root.add_child(spectator_lbl)
	# map overlay
	map_layer = Control.new()
	map_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_layer.visible = false
	map_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(map_layer)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(dim)
	map_view = MapView.new()
	map_view.setup(mt, self)
	map_layer.add_child(map_view)
	# shop
	shop_panel = _panel(0.92)
	shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	shop_panel.position = Vector2(-280, -230)
	shop_panel.custom_minimum_size = Vector2(560, 0)
	shop_panel.visible = false
	root.add_child(shop_panel)
	shop_list = VBoxContainer.new()
	shop_list.add_theme_constant_override("separation", 8)
	shop_panel.add_child(shop_list)
	# build
	build_panel = _panel(0.7)
	build_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	build_panel.position = Vector2(-380, -200)
	build_panel.custom_minimum_size = Vector2(360, 0)
	build_panel.visible = false
	root.add_child(build_panel)
	build_text = RichTextLabel.new()
	build_text.bbcode_enabled = true
	build_text.fit_content = true
	build_text.scroll_active = false
	build_text.custom_minimum_size = Vector2(340, 10)
	build_text.add_theme_font_size_override("normal_font_size", 15)
	build_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_panel.add_child(build_text)
	# choices (elite class / perk)
	choice_panel = _panel(0.92)
	choice_panel.set_anchors_preset(Control.PRESET_CENTER)
	choice_panel.position = Vector2(-300, -170)
	choice_panel.custom_minimum_size = Vector2(600, 0)
	choice_panel.visible = false
	root.add_child(choice_panel)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 8)
	choice_panel.add_child(choice_box)
	# pause
	pause_panel = _panel(0.94)
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-220, -170)
	pause_panel.custom_minimum_size = Vector2(440, 0)
	pause_panel.visible = false
	root.add_child(pause_panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	pause_panel.add_child(pv)
	var pt := _label(30, Color(1.0, 0.7, 0.25))
	pt.text = "Paused"
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(pt)
	pv.add_child(_button("Resume", func(): toggle_pause()))
	pv.add_child(_button("Controls (F1)", func(): help_panel.visible = not help_panel.visible))
	pv.add_child(_button("Quit to menu", func(): _quit()))
	# help
	help_panel = _panel(0.94)
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.position = Vector2(-430, -300)
	help_panel.custom_minimum_size = Vector2(860, 0)
	help_panel.visible = false
	root.add_child(help_panel)
	var ht := RichTextLabel.new()
	ht.bbcode_enabled = true
	ht.fit_content = true
	ht.custom_minimum_size = Vector2(830, 10)
	ht.add_theme_font_size_override("normal_font_size", 16)
	ht.text = HELP_TEXT
	help_panel.add_child(ht)
	# results
	results_panel = _panel(0.95)
	results_panel.set_anchors_preset(Control.PRESET_CENTER)
	results_panel.position = Vector2(-420, -320)
	results_panel.custom_minimum_size = Vector2(840, 0)
	results_panel.visible = false
	root.add_child(results_panel)


const HELP_TEXT := """[b][color=#ffb347]SURVIVOR[/color][/b]  WASD move · Shift run (noisy) · Ctrl/C crouch (quiet, harder to see) · E interact (hold) · RMB perfect parry (time it as a swing lands)
LMB use tool · 1 flare gun · 2 snare · 3 flash trap · Q role ability · F flashlight · B build mode · L lockdown · G give $25 to the poorest duo · V third/first person · X swap shoulder · Tab map
Goal: escape your cell, set up a base (hold E on open ground), find radio parts, build Antenna → Generator → Transmitter, call the helicopter and board it together.
Two hits put you down. Crawl home for 2 extra minutes; only a cure or your Medic partner can save you, or you turn.

[b][color=#ff6b5b]KILLER[/color][/b]  WASD move · LMB attack (hold on walls and the radio to smash) · RMB signature power · E catch a downed survivor / smash boards
R route edit (seal a squeeze gap or found hatch, collapse a narrow mine tunnel) · N unleash the Nest event when it glows · Tab map
Goal: catch every survivor. Caught survivors rise as elite infected on your side.

[b]BUILD MODE (B)[/b]  mouse wheel or 1-9 choose · LMB place · RMB leave · H escape hatch (aim at a wall) · U spikes · M metal (Engineer, aim at your wall/door)"""


# ------------------------------------------------------------------------------
# Per-frame

func _process(delta: float) -> void:
	if mt == null:
		return
	_update_clock()
	_update_status()
	_update_prompt()
	_update_duo()
	_update_overlays(delta)
	_update_feed(delta)
	if alert_t > 0.0:
		alert_t -= delta
		alert.modulate.a = clampf(alert_t, 0.0, 1.0)
	if toast_t > 0.0:
		toast_t -= delta
		toast_lbl.modulate.a = clampf(toast_t, 0.0, 1.0)
	map_layer.visible = (Input.is_action_pressed("map") or force_map) and not results_panel.visible
	if map_layer.visible:
		map_view.queue_redraw()
	build_panel.visible = pc.build_mode and pc.actor is Survivor
	if build_panel.visible:
		_update_build()
	crosshair.queue_redraw()


func _update_clock() -> void:
	var t := mt.time
	var txt := Match.fmt_time(t)
	if t < Tuning.KILLER_RELEASE:
		txt += "   ·   killers released in %ds" % int(Tuning.KILLER_RELEASE - t)
	elif not mt.final_push:
		var sto := mt.shop.time_to_open()
		if not mt.shop.open_terminals().is_empty():
			txt += "   ·   SHOPS OPEN"
		else:
			txt += "   ·   shops open in %s" % Match.fmt_time(sto)
	else:
		txt += "   ·   FINAL PUSH — purge in %s" % Match.fmt_time(maxf(0.0, Tuning.PURGE_AT - t))
	if mt.blackout():
		txt += "   ·   BLACKOUT"
	if mt.jammed():
		txt += "   ·   SIGNAL JAMMED"
	clock.text = txt


func _update_status() -> void:
	var a := pc.actor
	spectator_lbl.text = ""
	if a == null or not is_instance_valid(a):
		status.text = "Spectating"
		tools.text = ""
		var s := mt.player_slot
		if s != null and s.outcome == "escaped":
			status.text = "You escaped! Spectating the rest of the match."
		elif s != null and s.elite and s.respawn_at > 0.0:
			status.text = "You were caught. Rising as an elite in %ds…" % int(maxf(0.0, s.respawn_at - mt.time))
		spectator_lbl.text = "Left click: switch view   ·   Esc: menu"
		return
	if a is Survivor:
		var s2 := a as Survivor
		var hc = [Color(0.6, 1.0, 0.6), Color(1.0, 0.75, 0.3), Color(1.0, 0.3, 0.25)][s2.health]
		status.label_settings.font_color = hc
		var line := "%s  ·  %s" % [Defs.ROLE_NAMES[s2.role], s2.status_text()]
		if mt.time < s2.boost_until:
			line += "  ·  ADRENALINE"
		if s2.pinned_by != null:
			line += "  ·  CAUGHT BY A TONGUE!"
		if s2.masked():
			line += "  ·  masked %ds" % int(s2.masked_until - mt.time)
		if s2.slot.thief:
			line += "  ·  THIEF"
		status.text = line
		var parts: Array = []
		for p in s2.parts:
			parts.append(Defs.PART_NAMES[p])
		var abil := ""
		match s2.role:
			Defs.Role.ENGINEER: abil = "Q barricade"
			Defs.Role.MEDIC: abil = "Q scent mask"
			Defs.Role.TRAPPER: abil = "Q drop trap"
		var cd := s2.ability_cd_until - mt.time
		abil += " (%ds)" % int(cd) if cd > 0.0 else " (ready)"
		var tl := ["Flare x%d" % s2.flare, "Snare x%d" % s2.traps[0], "Flash x%d" % s2.traps[1]]
		tl[pc.tool] = "▶ " + tl[pc.tool]
		var parry := "RMB parry" + (" (…)" if mt.time < s2.parry_cd_until else "")
		tools.text = "Carrying: %s\n%s   ·   Cure x%d\n%s   ·   %s   ·   B build" % [", ".join(parts) if not parts.is_empty() else "—", "   ".join(tl), s2.cure, abil, parry]
		if s2.health != last_health:
			if last_health >= 0 and s2.health > last_health:
				hurt.color.a = 0.45
				pc.hit_feedback(0.8)
			last_health = s2.health
	else:
		var k := a as Killer
		status.label_settings.font_color = Color(1.0, 0.45, 0.35)
		var kind = ("Elite " if k.elite else "") + Defs.KILLER_NAMES[k.ktype]
		var line2 = kind
		if k.stunned():
			line2 += "  ·  STUNNED"
		elif k.held():
			line2 += "  ·  SNARED"
		elif k.disoriented():
			line2 += "  ·  DISORIENTED"
		if k.tired():
			line2 += "  ·  tired"
		if k.bounty > 0:
			line2 += "  ·  bounty $%d on your head" % k.bounty
		if k.ktype == Defs.K.LURKER and k.spotted():
			line2 += "  ·  SPOTTED"
		status.text = line2
		var pw = ["Stalk", "Charge", "Tongue"][k.ktype]
		var pcd := k.power_cd_until - mt.time
		var pws := "RMB %s %s" % [pw, ("(%ds)" % int(pcd)) if pcd > 0.0 else "(ready)"]
		if k.stalking():
			pws = "RMB Stalk ACTIVE (%ds) — you can't see survivors" % int(k.power_t)
		var nest := "N Nest: %s %d%%%s" % [Defs.CARD_NAMES[mt.nest.card], int(mt.nest.meter), " READY" if mt.nest.can_trigger() else ""]
		var extra := ""
		if k.elite and k.slot:
			var perks: Array = []
			for b in k.slot.perks:
				perks.append("%s %d" % [b, k.slot.perks[b]])
			extra = "\nElite level %d  ·  %s" % [k.slot.elite_level, ", ".join(perks) if not perks.is_empty() else "no perks yet"]
		tools.text = "%s   ·   R route edits x%d\n%s   ·   E catch / smash%s" % [pws, k.route_charges, nest, extra]


func _update_prompt() -> void:
	var a := pc.actor
	prompt.text = ""
	prompt_bar.visible = false
	if a == null or not is_instance_valid(a) or pc.ui_block:
		return
	if not a.channel.is_empty():
		var ch := a.channel
		prompt.text = ch["label"]
		prompt.label_settings.font_color = Color(1, 0.85, 0.5)
		prompt_bar.visible = true
		var prog: float = ch.get("progress", 0.0)
		var tot: float = ch["time"]
		match ch["id"]:
			"cell":
				prog = ch["target"]["progress"] / Tuning.CELL_PICK_TIME
				tot = 1.0
			"lever":
				prog = ch["target"]["cell"]["progress"] / Tuning.WORSE_LEVER_TIME
				tot = 1.0
				prompt.text = "Both levers must be held together!"
			"build", "repair":
				tot = 1.0
		prompt_bar.value = clampf(prog / maxf(tot, 0.001), 0.0, 1.0)
		return
	var opt := mt.interact.best_for_player(a)
	if opt.is_empty():
		if pc.build_mode:
			prompt.text = pc.build_error if pc.build_error != "" else "LMB: place %s" % Defs.BUILD_NAMES[pc.build_kind]
			prompt.label_settings.font_color = Color(1, 0.5, 0.4) if pc.build_error != "" else Color(0.6, 1, 0.6)
		return
	if opt["blocked"] != "":
		prompt.text = "%s — %s" % [opt["label"], opt["blocked"]]
		prompt.label_settings.font_color = Color(1, 0.55, 0.45)
	else:
		prompt.text = "[%s E] %s" % ["Hold" if opt["time"] > 0.0 else "", opt["label"]]
		prompt.label_settings.font_color = Color(1, 1, 1)


func _part_state(d: Duo, p: int) -> String:
	if d.base != null and d.base.storage.has(p):
		return "[color=#7dff8a]%s ✓[/color]" % Defs.PART_NAMES[p]
	for sl in d.members:
		if sl.actor is Survivor and (sl.actor as Survivor).parts.has(p):
			return "[color=#ffd36b]%s (carried)[/color]" % Defs.PART_NAMES[p]
	return "[color=#ff8a7a]%s[/color] [color=#8a8478]— %s[/color]" % [Defs.PART_NAMES[p], Defs.PART_HINTS[p]]


func _update_duo() -> void:
	var s := mt.player_slot
	if s == null or s.duo == null or (s.side != Defs.Side.SURVIVOR and not s.elite):
		_update_killer_panel()
		return
	if s.elite:
		_update_killer_panel()
		return
	var d := s.duo
	var t := "[b][color=#%s]%s duo[/color][/b]   $%d   ·   scrap %d\n" % [d.color.to_html(false), d.name, d.money, d.scrap]
	var partner := d.partner_of(s)
	if partner:
		var pst := "out"
		if partner.outcome == "escaped":
			pst = "escaped"
		elif partner.outcome != "":
			pst = partner.outcome
		elif partner.actor is Survivor:
			pst = (partner.actor as Survivor).status_text()
		t += "Partner %s (%s): %s\n" % [partner.name, Defs.ROLE_NAMES[partner.role], pst]
	var b := d.base
	if b == null:
		t += "[color=#ffb347]No base yet — hold E on open ground to set one up.[/color]\n"
		t += "Stage 1 Antenna: %s\n" % _part_state(d, Defs.P.CABLE)
	else:
		if b.broken:
			t += "[color=#ff6b5b]STATION BROKEN — repair it at the radio.[/color]\n"
		for i in 3:
			var nm: String = Defs.STAGE_NAMES[i]
			if i < b.stage:
				t += "[color=#7dff8a]%d %s ✓[/color]\n" % [i + 1, nm]
			elif i == b.stage:
				var parts: Array = []
				for p in Defs.STAGE_PARTS[i]:
					parts.append(_part_state(d, p))
				t += "[b]%d %s[/b] ($%d%s): %s\n" % [i + 1, nm, Tuning.STAGE_COST[i], ", paid" if b.paid else "", ", ".join(parts)]
				if b.progress > 0.0:
					t += "   building… %d%%\n" % int(b.progress / Tuning.STAGE_BUILD_TIME[i] * 100.0)
			else:
				t += "[color=#8a8478]%d %s[/color]\n" % [i + 1, nm]
		if b.stage >= 3:
			if b.heli != null and b.heli.state != "gone":
				match b.heli.state:
					"inbound", "approach":
						t += "[color=#ffd36b]Helicopter lands in %ds — hold the landing zone![/color]\n" % int(b.heli.time_left())
					"hover":
						t += "[color=#ff8a7a]Helicopter hovering — a killer is in the landing zone![/color]\n"
					"landed":
						t += "[color=#7dff8a][b]HELICOPTER LANDED — board within %ds![/b][/color]\n" % int(b.heli.t)
			else:
				t += "[color=#7dff8a]Transmitter ready: call the helicopter at your radio.[/color]\n"
		if not d.lockdown_used:
			t += "[color=#8a8478]L: lockdown (once) seals your base for %ds[/color]\n" % int(Tuning.LOCKDOWN_TIME)
	duo_text.text = t.strip_edges()


func _update_killer_panel() -> void:
	var t := "[b][color=#ff6b5b]The hunt[/color][/b]\n"
	var alive := mt.living_survivors().size()
	t += "Survivors still out there: %d\n" % alive
	var esc := 0
	for sl in mt.slots:
		if sl.outcome == "escaped":
			esc += 1
	t += "Escaped: %d\n" % esc
	for d in mt.duos:
		if d.base != null and d.active():
			var known = d.base.known_to_killers(mt.time)
			t += "%s duo: %s%s\n" % [d.name, ("radio stage %d" % d.base.stage) if known else "base unknown", "  ·  HELI CALLED" if d.base.heli_called else ""]
	t += "Nest: %d%%  (%s)" % [int(mt.nest.meter), Defs.CARD_NAMES[mt.nest.card]]
	duo_text.text = t


func _update_overlays(delta: float) -> void:
	var a := pc.actor
	var amt := 0.0
	var tint := Color(0.6, 0.0, 0.0, 1.0)
	if a is Survivor:
		var s := a as Survivor
		var nearest := INF
		for k in mt.killers:
			if not k.released or k.husk:
				continue
			if k.ktype == Defs.K.LURKER and k.is_main():
				continue
			nearest = minf(nearest, k.pos.distance_to(s.pos))
		if nearest < Tuning.TERROR_RADIUS:
			var near := 1.0 - nearest / Tuning.TERROR_RADIUS
			var before := floorf(beat_t)
			beat_t += delta * (1.2 + near * 2.4)
			if floorf(beat_t) != before and mt.sfx:
				mt.sfx.play2d("heart", lerpf(-16.0, 2.0, near))
			var beat := pow(absf(sin(beat_t * PI)), 8.0)
			amt = near * 0.55 + beat * near * 0.5
		if s.is_downed():
			amt = maxf(amt, 0.75)
	elif a is Killer:
		tint = Color(0.35, 0.02, 0.0, 1.0)
		amt = 0.35
	(vignette.material as ShaderMaterial).set_shader_parameter("amount", amt)
	(vignette.material as ShaderMaterial).set_shader_parameter("tint", tint)
	hurt.color.a = maxf(0.0, hurt.color.a - delta * 0.9)
	flash.color.a = maxf(0.0, flash.color.a - delta * 0.6)


func _update_feed(delta: float) -> void:
	for it in feed_items.duplicate():
		it["t"] -= delta
		var lbl: Label = it["l"]
		lbl.modulate.a = clampf(it["t"], 0.0, 1.0)
		if it["t"] <= 0.0:
			lbl.queue_free()
			feed_items.erase(it)


func _update_build() -> void:
	var s := pc.actor as Survivor
	var t := "[b]BUILD[/b]  $%d  ·  scrap %d\n" % [s.duo.money, s.duo.scrap]
	for i in PlayerController.BUILD_ORDER.size():
		var k: int = PlayerController.BUILD_ORDER[i]
		var def: Dictionary = Tuning.BUILD[k]
		var cost := ""
		if k == Defs.B.SNARE or k == Defs.B.FLASH:
			cost = "x%d left" % s.traps[0 if k == Defs.B.SNARE else 1]
		elif k == Defs.B.HATCH:
			cost = "free, once — aim at a wall (H)"
		else:
			cost = "%d scrap%s" % [def["scrap"], (" + $%d" % def["money"]) if def["money"] > 0 else ""]
		var line := "%d  %s  [color=#a09a8a]%s[/color]" % [(i + 1) % 10, Defs.BUILD_NAMES[k], cost]
		if k == pc.build_kind:
			line = "[color=#7dff8a]▶ " + line + "[/color]"
		t += line + "\n"
	if s.role == Defs.Role.ENGINEER:
		t += "[color=#ffd36b]U spikes (1 scrap + $30)  ·  M metal (2 scrap + $50) on your wall/door[/color]\n"
	t += "LMB place  ·  RMB/B exit"
	build_text.text = t


# ------------------------------------------------------------------------------
# Events

func _on_feed(text: String, kind: String, dur: float, scope: String, duo_id: int) -> void:
	var s := mt.player_slot
	var me_survivor := s != null and s.side == Defs.Side.SURVIVOR and s.outcome == ""
	match scope:
		"duo":
			# only your own duo's messages (spectators see everything)
			if s != null and (s.duo == null or s.duo.id != duo_id or not me_survivor):
				return
		"survivors":
			if s != null and not me_survivor:
				return
		"killers":
			if s != null and me_survivor:
				return
	var col := Color(0.9, 0.88, 0.82)
	match kind:
		"danger": col = Color(1.0, 0.5, 0.42)
		"good": col = Color(0.55, 1.0, 0.6)
		"money": col = Color(0.75, 0.95, 0.45)
		"alert": col = Color(1.0, 0.72, 0.25)
	var l := _label(17, col, 5)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	feed_box.add_child(l)
	feed_items.append({"l": l, "t": maxf(dur, 3.5) + 2.0})
	while feed_items.size() > 7:
		var old: Dictionary = feed_items.pop_front()
		(old["l"] as Label).queue_free()
	if kind == "alert" or (kind == "good" and scope == "duo" and dur >= 6.0):
		alert.text = text
		alert.label_settings.font_color = col
		alert_t = 4.0


func toast(text: String) -> void:
	toast_lbl.text = text
	toast_t = 2.5


func on_parry_pressed() -> void:
	crosshair.modulate = Color(0.5, 1.0, 1.0)
	get_tree().create_timer(0.15).timeout.connect(func(): crosshair.modulate = Color.WHITE)


func flash_screen() -> void:
	flash.color.a = 0.95


# ------------------------------------------------------------------------------
# Panels

func _set_block(on: bool) -> void:
	pc.ui_block = on
	if on:
		alert_t = 0.0
		alert.modulate.a = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED


func open_shop(t: Dictionary) -> void:
	shop_term = t
	_fill_shop()
	shop_panel.visible = true
	_set_block(true)


func _fill_shop() -> void:
	for c in shop_list.get_children():
		c.queue_free()
	var s := pc.actor as Survivor
	if s == null:
		return
	var title := _label(26, Color(1.0, 0.72, 0.25))
	title.text = "Company supply terminal   ·   $%d" % s.duo.money
	shop_list.add_child(title)
	for id in ["cure", "medkit", "traps", "scrap", "scanner"]:
		var item: Dictionary = Tuning.SHOP_ITEMS[id]
		var why := mt.shop.why_not(s, id)
		var extra := ""
		if id == "cure":
			extra = "  [%d left]" % mt.shop.cure_stock
		var b := _button("%s — $%d%s" % [item["name"], item["cost"], extra], func():
			var e := mt.shop.buy(s, id)
			toast(e if e != "" else "Bought: %s" % item["name"])
			_fill_shop())
		b.disabled = why != ""
		b.tooltip_text = item["desc"]
		shop_list.add_child(b)
		var d := _label(14, Color(0.7, 0.68, 0.62))
		d.text = item["desc"] + ("   (" + why + ")" if why != "" else "")
		shop_list.add_child(d)
	shop_list.add_child(_button("Close", func(): close_shop()))


func close_shop() -> void:
	shop_panel.visible = false
	_set_block(false)


func ask_elite_class(slot: Slot) -> void:
	_choice("You were caught. Choose your elite class:", [0, 1, 2].map(func(i): return "Elite %s — %s" % [Defs.KILLER_NAMES[i], ["fast hunter (Speed, Senses, Pack)", "wall-breaker (Smash, Tank, Bully)", "ambusher (Vents, Traps, Disguise)"][i]]), func(i: int):
		slot.ktype = i)


func ask_perk(slot: Slot) -> void:
	var branches: Array = Defs.ELITE_BRANCHES[slot.ktype]
	_choice("Elite level %d! Pick a skill branch:" % slot.elite_level, branches.map(func(b): return "%s (rank %d) — %s" % [b, slot.perk(b) + 1, Defs.ELITE_BRANCH_BLURBS[b]]), func(i: int):
		var b: String = branches[i]
		slot.perks[b] = slot.perk(b) + 1)


func _choice(title_text: String, options: Array, cb: Callable) -> void:
	for c in choice_box.get_children():
		c.queue_free()
	var t := _label(24, Color(1.0, 0.72, 0.25))
	t.text = title_text
	choice_box.add_child(t)
	for i in options.size():
		var idx := i
		choice_box.add_child(_button(options[i], func():
			cb.call(idx)
			choice_panel.visible = false
			_set_block(false)))
	choice_panel.visible = true
	_set_block(true)


func toggle_pause() -> void:
	if results_panel.visible:
		return
	if shop_panel.visible:
		close_shop()
		return
	if choice_panel.visible:
		return
	pause_panel.visible = not pause_panel.visible
	help_panel.visible = false
	mt.paused = pause_panel.visible
	_set_block(pause_panel.visible)


func _quit() -> void:
	mt.paused = true
	quit_to_menu.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("help"):
		help_panel.visible = not help_panel.visible


func _on_over(r: Dictionary) -> void:
	_set_block(true)
	shop_panel.visible = false
	choice_panel.visible = false
	pause_panel.visible = false
	for c in results_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	results_panel.add_child(v)
	var s := mt.player_slot
	var head := _label(34, Color(1.0, 0.72, 0.25), 8)
	var verdict := ""
	if s != null and s.duo != null and not s.elite:
		verdict = "YOU ESCAPED" if s.outcome == "escaped" else "YOU DIDN'T MAKE IT"
	elif s != null and s.elite:
		verdict = "CAUGHT — " + ("THE KILLERS WIN" if r["killers_win"] else "SOME SURVIVORS GOT OUT")
	elif s != null:
		verdict = "THE KILLERS WIN" if r["killers_win"] else "%d SURVIVOR%s ESCAPED" % [r["escaped"], "" if r["escaped"] == 1 else "S"]
	else:
		verdict = "Match over"
	head.text = verdict
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var sub := _label(18)
	sub.text = "%s  ·  %d escaped, %d caught or turned  ·  seed %d" % [Match.fmt_time(r["time"]), r["escaped"], r["caught"], r["seed"]]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(800, 10)
	rt.add_theme_font_size_override("normal_font_size", 15)
	var txt := ""
	for row in r["rows"]:
		if row["killer"]:
			txt += "[color=#ff8a7a]%s[/color]  catches %d\n" % [row["name"], row["stats"]["catches"]]
		else:
			var oc: String = row["outcome"] if row["outcome"] != "" else "—"
			var col := "#7dff8a" if oc == "escaped" else "#ff8a7a"
			txt += "%s duo · %s ([i]%s[/i]): [color=%s]%s[/color]%s  · earned $%d · parries %d%s\n" % [row["duo"], row["name"], Defs.ROLE_NAMES[row["role"]], col, oc, (" at " + Match.fmt_time(row["time"])) if row["outcome"] != "" else "", row["stats"]["earned"], row["stats"]["parries"], ("  · elite catches %d" % row["stats"]["elite_catches"]) if row["elite"] else ""]
	rt.text = txt
	v.add_child(rt)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(_button("Play again", func(): play_again.emit()))
	hb.add_child(_button("Main menu", func(): quit_to_menu.emit()))
	v.add_child(hb)
	results_panel.visible = true

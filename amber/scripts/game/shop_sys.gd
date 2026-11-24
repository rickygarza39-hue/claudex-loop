class_name ShopSys
extends RefCounted
## Company supply terminals: a random subset opens every few minutes.

var mt: Match
var terminals: Array = []   # {pos, tile, open, next, node}
var next_open := Tuning.SHOP_INTERVAL
var close_at := -1.0
var warned := false
var cure_stock := Tuning.CURE_STOCK


func _init(match_ref: Match) -> void:
	mt = match_ref
	for tl in mt.m.terminals:
		var t := {"pos": MapData.center_of(tl), "tile": tl, "open": false, "next": false, "node": null}
		terminals.append(t)
		mt.nav.set_struct(tl, true, true)
		if mt.visuals:
			var n := Models.make("shop_terminal")
			n.position = Vector3(t["pos"].x, mt.m.height_at(t["pos"]), t["pos"].y)
			# face away from the wall it stands against
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nt := mt.m.tv(tl + d)
				if nt == Defs.T.WALL or nt == Defs.T.CLIFF:
					n.rotation.y = Actor.yaw_of(-Vector2(d))
					break
			mt.add_child(n)
			t["node"] = n
			var lbl := Label3D.new()
			lbl.text = "SUPPLY TERMINAL"
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.font_size = 36
			lbl.pixel_size = 0.004
			lbl.outline_size = 8
			lbl.position = Vector3(0, 2.5, 0)
			lbl.modulate = Color(0.85, 0.75, 0.4)
			n.add_child(lbl)


func open_terminals() -> Array:
	var out: Array = []
	for t in terminals:
		if t["open"]:
			out.append(t)
	return out


func time_to_open() -> float:
	return next_open - mt.time


func tick(_dt: float) -> void:
	var tm := mt.time
	if not warned and tm >= next_open - Tuning.SHOP_WARNING:
		warned = true
		var order := terminals.duplicate()
		for i in range(order.size() - 1, 0, -1):
			var j := mt.rng.randi_range(0, i)
			var tmp = order[i]
			order[i] = order[j]
			order[j] = tmp
		for i in order.size():
			order[i]["next"] = i < Tuning.SHOP_OPEN_COUNT
		mt.feed_survivors("Supply terminals open in %d seconds (marked on your map)." % int(Tuning.SHOP_WARNING), "info")
	if tm >= next_open:
		for t in terminals:
			t["open"] = t["next"]
			t["next"] = false
			_paint(t)
		close_at = tm + Tuning.SHOP_OPEN_TIME
		next_open += Tuning.SHOP_INTERVAL
		warned = false
		mt.feed_all("Supply terminals are OPEN for %d seconds." % int(Tuning.SHOP_OPEN_TIME), "info")
		for t in open_terminals():
			mt.make_noise(t["pos"], 40.0, "terminal", null)
	if close_at > 0.0 and tm >= close_at:
		close_at = -1.0
		for t in terminals:
			t["open"] = false
			_paint(t)


func _paint(t: Dictionary) -> void:
	var n: Node3D = t["node"]
	if n == null:
		return
	var screen := n.find_child("Screen", true, false) as MeshInstance3D
	if screen:
		screen.material_override = Mats.get_mat("screen_on" if t["open"] else "screen_off")
	var lamp := n.find_child("Lamp", true, false) as MeshInstance3D
	if lamp:
		lamp.material_override = Mats.get_mat("lamp" if t["open"] else "lamp_red")


func use(s: Survivor, t: Dictionary) -> void:
	if not t["open"]:
		return
	if s.slot.is_human:
		mt.open_shop_ui(t)
	else:
		mt.survivor_ai_for(s).shop_visit(t)


func price(item: String) -> int:
	return Tuning.SHOP_ITEMS[item]["cost"]


func why_not(s: Survivor, item: String) -> String:
	var cost := price(item)
	if s.duo.money < cost:
		return "Need $%d" % cost
	match item:
		"cure":
			if cure_stock <= 0:
				return "Sold out"
			if s.slot.stats.get("cure_bought", false):
				return "One cure per person"
		"medkit":
			if s.health != Defs.Health.WOUNDED:
				return "You're not wounded"
		"traps":
			if s.traps[0] + s.traps[1] >= s.trap_capacity() * 2:
				return "Trap bag full"
	return ""


func buy(s: Survivor, item: String) -> String:
	var why := why_not(s, item)
	if why != "":
		return why
	s.duo.money -= price(item)
	match item:
		"cure":
			cure_stock -= 1
			s.cure += 1
			s.slot.stats["cure_bought"] = true
			mt.feed_all("%s bought a cure (%d left)." % [s.slot.name, cure_stock], "info")
		"medkit":
			s.heal_one()
		"traps":
			s.traps[0] = mini(s.traps[0] + 1, s.trap_capacity())
			s.traps[1] = mini(s.traps[1] + 1, s.trap_capacity())
		"scrap":
			s.duo.scrap += 4
		"scanner":
			mt.scan_parts(s)
	return ""

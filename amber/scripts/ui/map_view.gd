class_name MapView
extends Control
## Full-screen map (hold Tab). Survivors see what their duo knows; killers see
## revealed bases, knockdown hot zones and recent noises.

var mt: Match
var hud: Hud
var tex: ImageTexture
var cell := 6.0
var origin := Vector2.ZERO
var font: Font


func setup(match_ref: Match, h: Hud) -> void:
	mt = match_ref
	hud = h
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	_make_texture()


func _make_texture() -> void:
	var m := mt.m
	var img := Image.create(m.w, m.h, false, Image.FORMAT_RGBA8)
	var zc := {
		Defs.Z.TOWN: Color(0.36, 0.29, 0.21), Defs.Z.SWAMP: Color(0.2, 0.26, 0.19),
		Defs.Z.FIELD: Color(0.22, 0.3, 0.17), Defs.Z.MINE: Color(0.27, 0.25, 0.23),
		Defs.Z.LAB: Color(0.2, 0.3, 0.32), Defs.Z.HIGH: Color(0.33, 0.35, 0.28),
	}
	for y in m.h:
		for x in m.w:
			var i := m.idx(x, y)
			var c: Color = zc.get(int(m.zones[i]), Color(0.3, 0.3, 0.3))
			match m.tiles[i]:
				Defs.T.WALL:
					c = Color(0.07, 0.065, 0.06)
				Defs.T.CLIFF:
					c = Color(0.5, 0.5, 0.48)
				Defs.T.WATER:
					c = Color(0.1, 0.17, 0.24)
				Defs.T.GAP:
					c = Color(0.95, 0.85, 0.3)
				Defs.T.RAMP:
					c = Color(0.55, 0.55, 0.45)
				Defs.T.TREE:
					c = c.darkened(0.45)
				Defs.T.PROP, Defs.T.FENCE:
					c = c.darkened(0.3)
				Defs.T.BOARDS:
					c = Color(0.62, 0.46, 0.28)
				Defs.T.CELL_DOOR:
					c = Color(0.85, 0.75, 0.2)
				_:
					if m.roof[i] == Defs.R.ROOF:
						c = c.darkened(0.25)
					if m.floor_h[i] > 2.0:
						c = c.lightened(0.15)
			img.set_pixel(x, y, c)
	tex = ImageTexture.create_from_image(img)


func refresh_tile(_p: Vector2i) -> void:
	_make_texture()


func w2s(p: Vector2) -> Vector2:
	return origin + p / Defs.TILE * cell


func _txt(p: Vector2, s: String, col: Color, size: int = 13) -> void:
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_CENTER, -1, size, 4, Color(0, 0, 0, 0.9))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_CENTER, -1, size, col)


func _draw() -> void:
	var m := mt.m
	cell = minf(size.x / m.w, (size.y - 60.0) / m.h) * 0.95
	origin = (size - Vector2(m.w, m.h) * cell) * 0.5 + Vector2(0, 10)
	draw_texture_rect(tex, Rect2(origin, Vector2(m.w, m.h) * cell), false)
	draw_rect(Rect2(origin, Vector2(m.w, m.h) * cell), Color(0.9, 0.6, 0.2, 0.6), false, 2.0)
	var viewer: Actor = hud.pc.actor
	var slot := mt.player_slot
	var spectating := slot == null
	var as_survivor := viewer is Survivor
	# district names
	for cy in 4:
		for cx in 4:
			var l: String = m.macro[cy][cx]
			var nm = {"T": "Town", "S": "Swamp", "F": "Fields", "M": "Mines", "L": "Flooded Lab", "H": "High Ground"}.get(l, "")
			var c := origin + (Vector2(cx, cy) * 28.0 + Vector2(14, 3)) * cell
			_txt(c, nm, Color(1, 1, 1, 0.35), 15)
	# the Nest
	_txt(w2s(MapData.center_of(m.nest)) + Vector2(0, -8), "THE NEST", Defs.AMBER, 13)
	draw_circle(w2s(MapData.center_of(m.nest)), cell * 1.4, Color(1.0, 0.55, 0.1, 0.7))
	# terminals
	for t in mt.shop.terminals:
		var col := Color(0.4, 1.0, 0.5) if t["open"] else (Color(1.0, 0.85, 0.3) if t["next"] else Color(0.6, 0.6, 0.6))
		var p: Vector2 = w2s(t["pos"])
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), col)
		_txt(p + Vector2(0, -8), "SHOP" + (" OPEN" if t["open"] else (" SOON" if t["next"] else "")), col, 11)
	# quarantine cells
	for c in mt.cells:
		if not c["open"]:
			draw_rect(Rect2(w2s(MapData.center_of(c["door"])) - Vector2(4, 4), Vector2(8, 8)), Color(0.85, 0.75, 0.2), false, 2.0)
	# bases
	for d in mt.duos:
		var b: Base = d.base
		if b == null:
			continue
		var mine = slot != null and slot.duo == d and not slot.elite
		var show := spectating or as_survivor or b.known_to_killers(mt.time)
		if not show:
			continue
		var bp := w2s(b.pos)
		draw_rect(Rect2(bp - Vector2(7, 7), Vector2(14, 14)), d.color, mine)
		draw_arc(bp, b.radius_m() / Defs.TILE * cell, 0, TAU, 32, Color(d.color, 0.35), 1.5)
		_txt(bp + Vector2(0, -11), "%s%s %d/3%s" % ["YOUR BASE " if mine else "", d.name, b.stage, " BROKEN" if b.broken else ""], d.color, 12)
		if b.heli != null and b.heli.state != "gone":
			draw_circle(w2s(b.heli.lz), 6, Color(1, 1, 1, 0.8))
			_txt(w2s(b.heli.lz) + Vector2(0, 18), "LZ", Color.WHITE, 12)
	# items
	if as_survivor or spectating:
		var known: Dictionary = (viewer as Survivor).duo.known_items if as_survivor else {}
		for it in mt.items:
			if it.taken:
				continue
			if not spectating and not known.has(it):
				continue
			var ip := w2s(it.pos)
			match it.kind:
				Defs.Item.PART:
					draw_circle(ip, 4.5, Defs.PART_COLORS[it.part])
					_txt(ip + Vector2(0, -6), Defs.PART_NAMES[it.part].split(" ")[0], Defs.PART_COLORS[it.part], 10)
				Defs.Item.CASH:
					draw_circle(ip, 2.5, Color(0.5, 1.0, 0.4))
				Defs.Item.SCRAP:
					draw_circle(ip, 2.0, Color(0.7, 0.7, 0.7))
				Defs.Item.FLARE:
					draw_circle(ip, 5.0, Color(1.0, 0.2, 0.1))
					_txt(ip + Vector2(0, -7), "FLARE", Color(1, 0.4, 0.3), 10)
	else:
		# killers: vague hot zones and recent noises
		for hz in mt.hotzones:
			draw_circle(w2s(hz["pos"]), hz["r"] / Defs.TILE * cell, Color(1.0, 0.25, 0.15, 0.12))
		for n in mt.noises:
			if is_instance_valid(n["src"]) and n["src"] is Killer:
				continue
			var age: float = mt.time - n["t"]
			draw_arc(w2s(n["pos"]), 4.0 + age * 6.0, 0, TAU, 16, Color(1, 0.3, 0.2, clampf(1.0 - age / 4.0, 0.0, 1.0)), 2.0)
	# actors
	for a in mt.all_actors():
		var ap := w2s(a.pos)
		if a is Survivor:
			var s := a as Survivor
			var visible_to_me := spectating or (as_survivor and (s == viewer or s.duo == (viewer as Survivor).duo)) or (not as_survivor and mt.time < s.revealed_until)
			if not visible_to_me:
				continue
			draw_circle(ap, 5.0, s.duo.color if s.health != Defs.Health.DOWNED else Color(1, 0.2, 0.2))
			if s != viewer:
				_txt(ap + Vector2(0, -8), s.slot.name, s.duo.color, 11)
		else:
			var k := a as Killer
			var show_k := spectating or not as_survivor
			if not show_k:
				continue
			draw_circle(ap, 5.0 if k.is_main() else 3.5, Color(1.0, 0.2, 0.15) if k.is_main() else Color(1.0, 0.55, 0.2))
	# me
	if viewer != null and is_instance_valid(viewer):
		var vp := w2s(viewer.pos)
		var f := viewer.forward2()
		var r := Vector2(-f.y, f.x)
		draw_colored_polygon(PackedVector2Array([vp + f * 11, vp - f * 6 + r * 6, vp - f * 6 - r * 6]), Color(1, 1, 1))
	# legend
	var lg := "Hold Tab: map   ·   "
	if as_survivor:
		lg += "Parts spawn: Cable — town · Fuel — mine entrances · Spark plug — old vehicles · Circuit — flooded lab · Power cell — deep mines · Dish — watchtower & cliffs   ·   yellow = squeeze gaps"
	elif viewer is Killer:
		lg += "Red haze: knockdown-item hot zones (they shift) · rings: recent noises · squares: bases you know about"
	_txt(Vector2(size.x * 0.5, size.y - 18), lg, Color(0.9, 0.85, 0.75), 13)

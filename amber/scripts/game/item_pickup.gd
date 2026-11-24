class_name ItemPickup
extends Node3D
## Something lying on the ground: a radio part, cash, scrap or a knockdown item.

var kind := Defs.Item.CASH
var part := -1
var amount := 0
var pos := Vector2.ZERO
var taken := false
var base_y := 0.0
var label: Label3D
var _t := 0.0


func setup(mt: Match, k: int, p: int, amt: int, at: Vector2) -> void:
	kind = k
	part = p
	amount = amt
	pos = at
	base_y = mt.m.height_at(at)
	if mt.m.t(MapData.tile_of(at).x, MapData.tile_of(at).y) == Defs.T.WATER:
		base_y -= 0.3
	position = Vector3(at.x, base_y, at.y)
	_t = randf() * TAU
	if mt.visuals:
		var slot := "cash"
		match k:
			Defs.Item.PART: slot = ["part_cable", "part_fuel", "part_spark", "part_circuit", "part_cell", "part_dish"][p]
			Defs.Item.SCRAP: slot = "scrap"
			Defs.Item.FLARE: slot = "flare_gun"
		var n := Models.make(slot)
		n.name = "Model"
		add_child(n)
		label = Label3D.new()
		label.text = title()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 36
		label.pixel_size = 0.0035
		label.outline_size = 8
		label.position = Vector3(0, 0.75, 0)
		label.modulate = Color(1, 0.9, 0.7)
		label.visible = false
		add_child(label)
		if k == Defs.Item.PART or k == Defs.Item.FLARE:
			var glow := OmniLight3D.new()
			glow.light_color = Defs.PART_COLORS[p] if k == Defs.Item.PART else Color(1, 0.3, 0.2)
			glow.omni_range = 1.6
			glow.light_energy = 0.6
			glow.position = Vector3(0, 0.4, 0)
			add_child(glow)


func title() -> String:
	match kind:
		Defs.Item.PART: return Defs.PART_NAMES[part]
		Defs.Item.CASH: return "$%d scrip" % amount
		Defs.Item.SCRAP: return "Scrap x%d" % amount
		Defs.Item.FLARE: return "Flare gun"
	return "?"


func _process(delta: float) -> void:
	_t += delta
	var n := get_node_or_null("Model") as Node3D
	if n:
		n.rotation.y = _t * 0.6
		n.position.y = 0.05 + sin(_t * 2.0) * 0.03

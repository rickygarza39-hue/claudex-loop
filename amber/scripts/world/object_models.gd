class_name ObjectModels
extends RefCounted
## Placeholder builders for props, items, the radio station, the helicopter and
## base structures. Replace any of them with a Forge export (see Models).

static func build(slot: String, root: Node3D, o: Dictionary) -> void:
	match slot:
		"part_cable": _cable(root)
		"part_fuel": _fuel(root)
		"part_spark": _spark(root)
		"part_circuit": _circuit(root)
		"part_cell": _cell(root)
		"part_dish": _dish(root, 0.32)
		"cash": _cash(root)
		"scrap": _scrap(root)
		"flare_gun": _flare(root)
		"trap_snare": _snare(root)
		"trap_flash": _flash(root)
		"shop_terminal": _terminal(root)
		"nest": _nest(root)
		"station_base": _station_base(root)
		"station_antenna": _antenna(root)
		"station_generator": _generator(root)
		"station_transmitter": _transmitter(root)
		"helicopter": _helicopter(root)
		"build_wall": _wall(root, o)
		"build_door": _door(root, o)
		"build_barricade": _barricade(root)
		"build_alarm": _alarm(root)
		"build_floodlight": _floodlight(root)
		"build_decoy": _decoy(root)
		"build_locker": _locker(root)
		"build_hatch": _hatch(root)
		"drop_ledge": _drop_ledge(root)
		_:
			Models.box(root, Vector3(0.5, 0.5, 0.5), Mats.flat(Color(1, 0, 1)), Vector3(0, 0.25, 0))


static func _glow(c: Color, e: float = 1.2) -> StandardMaterial3D:
	return Mats.flat(c, e, 0.5)


static func _cable(r: Node3D) -> void:
	var wood := Mats.get_mat("crate")
	Models.cyl(r, 0.28, 0.28, 0.06, wood, Vector3(0, 0.03, 0), Vector3.ZERO, 14)
	Models.cyl(r, 0.28, 0.28, 0.06, wood, Vector3(0, 0.45, 0), Vector3.ZERO, 14)
	Models.cyl(r, 0.2, 0.2, 0.4, Mats.flat(Color(0.75, 0.42, 0.15), 0.25, 0.4, 0.7), Vector3(0, 0.24, 0), Vector3.ZERO, 14)


static func _fuel(r: Node3D) -> void:
	Models.box(r, Vector3(0.3, 0.42, 0.18), Mats.flat(Color(0.7, 0.1, 0.08), 0.15, 0.5, 0.3), Vector3(0, 0.21, 0))
	Models.box(r, Vector3(0.16, 0.06, 0.04), Mats.flat(Color(0.15, 0.15, 0.15)), Vector3(0, 0.46, 0))
	Models.cyl(r, 0.03, 0.03, 0.1, Mats.flat(Color(0.8, 0.7, 0.2)), Vector3(0.1, 0.47, 0))


static func _spark(r: Node3D) -> void:
	Models.box(r, Vector3(0.32, 0.22, 0.2), Mats.flat(Color(0.12, 0.12, 0.13), 0.0, 0.5), Vector3(0, 0.11, 0))
	Models.cyl(r, 0.03, 0.03, 0.06, Mats.flat(Color(0.8, 0.2, 0.15), 0.5), Vector3(-0.09, 0.25, 0))
	Models.cyl(r, 0.03, 0.03, 0.06, Mats.flat(Color(0.7, 0.7, 0.75), 0.5), Vector3(0.09, 0.25, 0))


static func _circuit(r: Node3D) -> void:
	Models.box(r, Vector3(0.36, 0.03, 0.26), _glow(Color(0.1, 0.55, 0.25), 0.4), Vector3(0, 0.02, 0))
	for k in 4:
		Models.box(r, Vector3(0.06, 0.03, 0.06), Mats.flat(Color(0.1, 0.1, 0.1)), Vector3(-0.12 + k * 0.08, 0.05, 0.05))
	Models.box(r, Vector3(0.05, 0.02, 0.05), _glow(Color(0.2, 1.0, 0.4), 2.0), Vector3(0.12, 0.05, -0.07))


static func _cell(r: Node3D) -> void:
	Models.cyl(r, 0.12, 0.12, 0.42, Mats.flat(Color(0.2, 0.22, 0.26), 0.0, 0.4, 0.7), Vector3(0, 0.21, 0))
	Models.cyl(r, 0.125, 0.125, 0.12, _glow(Color(0.3, 0.6, 1.0), 2.5), Vector3(0, 0.24, 0))


static func _dish(r: Node3D, s: float) -> void:
	var metal := Mats.flat(Color(0.75, 0.76, 0.78), 0.1, 0.35, 0.6)
	var d := Models.cyl(r, s, s * 0.25, s * 0.35, metal, Vector3(0, s * 0.6, 0), Vector3(-0.5, 0, 0), 16)
	d.name = "Dish"
	Models.cyl(r, 0.02, 0.02, s * 0.8, metal, Vector3(0, s * 0.75, -s * 0.2), Vector3(-0.5, 0, 0))


static func _cash(r: Node3D) -> void:
	Models.box(r, Vector3(0.36, 0.22, 0.26), Mats.flat(Color(0.18, 0.28, 0.2), 0.0, 0.4, 0.6), Vector3(0, 0.11, 0))
	Models.box(r, Vector3(0.22, 0.04, 0.12), _glow(Color(0.5, 0.95, 0.5), 1.0), Vector3(0, 0.24, 0))


static func _scrap(r: Node3D) -> void:
	var rust := Mats.get_mat("rust")
	Models.box(r, Vector3(0.5, 0.08, 0.3), rust, Vector3(0, 0.04, 0), Vector3(0, 0.3, 0))
	Models.box(r, Vector3(0.4, 0.06, 0.25), rust, Vector3(0.05, 0.12, 0.02), Vector3(0.2, -0.4, 0.1))
	Models.cyl(r, 0.04, 0.04, 0.5, Mats.flat(Color(0.4, 0.4, 0.42), 0.0, 0.4, 0.8), Vector3(-0.05, 0.2, 0), Vector3(0, 0, 1.2))


static func _flare(r: Node3D) -> void:
	var red := _glow(Color(0.95, 0.15, 0.08), 1.6)
	Models.box(r, Vector3(0.08, 0.18, 0.06), red, Vector3(0, 0.09, 0.05))
	Models.cyl(r, 0.05, 0.05, 0.3, red, Vector3(0, 0.2, -0.08), Vector3(PI * 0.5, 0, 0))


static func _snare(r: Node3D) -> void:
	var metal := Mats.flat(Color(0.35, 0.35, 0.37), 0.0, 0.35, 0.8)
	Models.cyl(r, 0.38, 0.38, 0.04, metal, Vector3(0, 0.02, 0), Vector3.ZERO, 16)
	for k in 8:
		var a := k * TAU / 8.0
		Models.box(r, Vector3(0.03, 0.12, 0.08), metal, Vector3(sin(a) * 0.34, 0.08, cos(a) * 0.34), Vector3(0, a, 0))


static func _flash(r: Node3D) -> void:
	Models.box(r, Vector3(0.3, 0.12, 0.3), Mats.flat(Color(0.15, 0.15, 0.17)), Vector3(0, 0.06, 0))
	Models.sphere(r, 0.1, _glow(Color(0.8, 0.9, 1.0), 1.5), Vector3(0, 0.16, 0))


static func _terminal(r: Node3D) -> void:
	var body := Mats.get_mat("terminal")
	Models.box(r, Vector3(0.9, 1.9, 0.5), body, Vector3(0, 0.95, 0))
	var screen := Models.box(r, Vector3(0.62, 0.45, 0.04), Mats.get_mat("screen_off"), Vector3(0, 1.45, -0.27))
	screen.name = "Screen"
	Models.box(r, Vector3(0.7, 0.08, 0.3), body, Vector3(0, 1.0, -0.38), Vector3(-0.35, 0, 0))
	var lamp := Models.sphere(r, 0.08, Mats.get_mat("lamp_red"), Vector3(0, 2.0, 0))
	lamp.name = "Lamp"
	Models.box(r, Vector3(0.75, 0.2, 0.05), Mats.flat(Color(0.75, 0.55, 0.15), 0.4), Vector3(0, 1.78, -0.26))


static func _drop_ledge(r: Node3D) -> void:
	## Broken railing at a cliff edge with hazard paint: survivors can jump here.
	var wood := Mats.get_mat("crate")
	var paint := Mats.flat(Color(0.95, 0.75, 0.1), 0.15)
	var dark := Mats.flat(Color(0.08, 0.08, 0.08))
	for x in [-0.85, 0.85]:
		Models.box(r, Vector3(0.12, 1.05, 0.12), wood, Vector3(x, 0.52, 0))
	# the rail snapped in the middle and hangs over the edge
	Models.box(r, Vector3(0.85, 0.08, 0.08), wood, Vector3(-0.45, 0.95, 0), Vector3(0, 0, -0.25))
	Models.box(r, Vector3(0.8, 0.08, 0.08), wood, Vector3(0.5, 0.78, -0.1), Vector3(0.3, 0, 0.55))
	# hazard stripes painted on the lip
	for i in 6:
		Models.box(r, Vector3(0.3, 0.02, 0.35), paint if i % 2 == 0 else dark, Vector3(-0.75 + i * 0.3, 0.01, -0.2))
	# a rope tied to a post, dangling down the cliff
	Models.cyl(r, 0.025, 0.025, 1.6, Mats.flat(Color(0.55, 0.45, 0.3)), Vector3(0.85, 0.2, -0.45), Vector3(0.35, 0, 0))


static func _nest(r: Node3D) -> void:
	var amber := Mats.get_mat("amber")
	var dim := Mats.get_mat("amber_dim")
	Models.sphere(r, 1.0, dim, Vector3(0, 0.6, 0), Vector3(1.6, 0.7, 1.6), 16)
	var heart := Models.sphere(r, 0.55, amber, Vector3(0, 1.3, 0), Vector3(1.0, 1.3, 1.0), 14)
	heart.name = "Heart"
	for k in 9:
		var a := k * TAU / 9.0
		Models.box(r, Vector3(0.18, 1.6, 0.18), amber, Vector3(sin(a) * 1.4, 0.7, cos(a) * 1.4), Vector3(sin(a) * 0.5, a, cos(a) * 0.5))


static func _station_base(r: Node3D) -> void:
	var wood := Mats.get_mat("crate")
	Models.box(r, Vector3(1.4, 0.08, 0.8), wood, Vector3(0, 0.85, 0))
	for x in [-0.6, 0.6]:
		for z in [-0.32, 0.32]:
			Models.box(r, Vector3(0.08, 0.85, 0.08), wood, Vector3(x, 0.42, z))
	Models.box(r, Vector3(0.5, 0.3, 0.35), Mats.flat(Color(0.25, 0.27, 0.22), 0.0, 0.6, 0.4), Vector3(-0.25, 1.04, 0))
	Models.box(r, Vector3(0.12, 0.05, 0.02), _glow(Color(1.0, 0.3, 0.2), 2.0), Vector3(-0.3, 1.12, -0.18))


static func _antenna(r: Node3D) -> void:
	var metal := Mats.flat(Color(0.55, 0.55, 0.57), 0.0, 0.4, 0.7)
	for k in 3:
		var a := k * TAU / 3.0
		Models.cyl(r, 0.03, 0.03, 6.1, metal, Vector3(sin(a) * 0.25, 3.0, cos(a) * 0.25), Vector3(sin(a) * 0.04, 0, -cos(a) * 0.04))
	for h in [1.5, 3.0, 4.5]:
		Models.cyl(r, 0.3, 0.3, 0.04, metal, Vector3(0, h, 0), Vector3.ZERO, 3)
	var tip := Models.sphere(r, 0.09, Mats.get_mat("lamp_red"), Vector3(0, 6.1, 0))
	tip.name = "Tip"
	for k in 3:
		var a := k * TAU / 3.0 + 0.5
		Models.cyl(r, 0.008, 0.008, 4.6, Mats.get_mat("cable"), Vector3(sin(a) * 1.3, 2.2, cos(a) * 1.3), Vector3(cos(a) * 0.55, 0, -sin(a) * 0.55))


static func _generator(r: Node3D) -> void:
	var body := Mats.flat(Color(0.55, 0.45, 0.12), 0.0, 0.6, 0.4)
	Models.box(r, Vector3(1.1, 0.75, 0.7), body, Vector3(0, 0.55, 0))
	Models.box(r, Vector3(1.2, 0.18, 0.8), Mats.flat(Color(0.15, 0.15, 0.15)), Vector3(0, 0.09, 0))
	Models.cyl(r, 0.08, 0.08, 0.5, Mats.flat(Color(0.2, 0.2, 0.2)), Vector3(0.4, 1.1, 0.2))
	var light := Models.sphere(r, 0.05, _glow(Color(0.2, 1.0, 0.3), 3.0), Vector3(-0.4, 0.95, -0.36))
	light.name = "Running"


static func _transmitter(r: Node3D) -> void:
	var metal := Mats.flat(Color(0.3, 0.32, 0.35), 0.0, 0.4, 0.6)
	Models.box(r, Vector3(0.8, 1.2, 0.6), metal, Vector3(0, 0.6, 0))
	for k in 3:
		Models.box(r, Vector3(0.1, 0.05, 0.02), _glow(Color(0.3, 1.0, 0.6) if k < 2 else Color(1.0, 0.6, 0.2), 2.5), Vector3(-0.2 + k * 0.2, 1.0, -0.31))
	var dish := Node3D.new()
	dish.position = Vector3(0, 1.2, 0)
	r.add_child(dish)
	_dish(dish, 0.6)


static func _helicopter(r: Node3D) -> void:
	var body := Mats.flat(Color(0.22, 0.26, 0.2), 0.0, 0.55, 0.4)
	var dark := Mats.flat(Color(0.06, 0.06, 0.06), 0.0, 0.5, 0.5)
	var glass := Mats.flat(Color(0.12, 0.16, 0.2), 0.0, 0.1, 0.4)
	Models.capsule(r, 1.15, 5.0, body, Vector3(0, 1.6, 0), Vector3(PI * 0.5, 0, 0))
	Models.sphere(r, 1.05, glass, Vector3(0, 1.75, -2.2), Vector3(1.0, 0.85, 0.9))
	Models.box(r, Vector3(0.35, 0.45, 5.0), body, Vector3(0, 2.0, 4.6))
	Models.box(r, Vector3(0.1, 1.3, 0.6), body, Vector3(0, 2.6, 7.0))
	for x in [-0.9, 0.9]:
		Models.box(r, Vector3(0.1, 0.1, 3.4), dark, Vector3(x, 0.08, 0))
		Models.box(r, Vector3(0.08, 0.55, 0.08), dark, Vector3(x, 0.35, -0.8))
		Models.box(r, Vector3(0.08, 0.55, 0.08), dark, Vector3(x, 0.35, 0.9))
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	rotor.position = Vector3(0, 3.05, 0)
	r.add_child(rotor)
	Models.cyl(rotor, 0.12, 0.12, 0.35, dark, Vector3(0, -0.15, 0))
	for k in 4:
		Models.box(rotor, Vector3(0.28, 0.04, 5.2), dark, Vector3(sin(k * PI * 0.5) * 2.6, 0, cos(k * PI * 0.5) * 2.6), Vector3(0, k * PI * 0.5, 0))
	var tail := Node3D.new()
	tail.name = "TailRotor"
	tail.position = Vector3(0.25, 2.6, 7.0)
	r.add_child(tail)
	Models.box(tail, Vector3(0.04, 1.4, 0.15), dark, Vector3.ZERO)
	var spot := Models.sphere(r, 0.14, Mats.get_mat("lamp"), Vector3(0, 0.6, -2.4))
	spot.name = "Spot"
	var beacon := Models.sphere(r, 0.1, Mats.get_mat("lamp_red"), Vector3(0, 2.9, 4.0))
	beacon.name = "Beacon"


static func _wall(r: Node3D, o: Dictionary) -> void:
	var mat: Material = Mats.get_mat("metal") if o.get("metal", false) else Mats.get_mat("boards")
	Models.box(r, Vector3(2.0, 2.8, 0.35), mat, Vector3(0, 1.4, 0))
	for x in [-0.95, 0.95]:
		Models.box(r, Vector3(0.15, 3.0, 0.45), Mats.get_mat("plank"), Vector3(x, 1.5, 0))
	if o.get("spiked", false):
		var sp := Mats.flat(Color(0.5, 0.5, 0.52), 0.0, 0.3, 0.9)
		for k in 6:
			for side in [-1, 1]:
				Models.cyl(r, 0.0, 0.05, 0.45, sp, Vector3(-0.75 + k * 0.3, 0.6 + (k % 2) * 0.9, 0.35 * side), Vector3(PI * 0.5 * side, 0, 0), 5)


static func _door(r: Node3D, o: Dictionary) -> void:
	var plank := Mats.get_mat("plank")
	for x in [-0.95, 0.95]:
		Models.box(r, Vector3(0.18, 3.0, 0.4), plank, Vector3(x, 1.5, 0))
	Models.box(r, Vector3(2.0, 0.3, 0.4), plank, Vector3(0, 2.85, 0))
	var leaf := Node3D.new()
	leaf.name = "Leaf"
	leaf.position = Vector3(-0.85, 0, 0)
	r.add_child(leaf)
	Models.box(leaf, Vector3(1.7, 2.6, 0.12), Mats.get_mat("metal") if o.get("metal", false) else Mats.get_mat("boards"), Vector3(0.85, 1.3, 0))


static func _barricade(r: Node3D) -> void:
	var b := Mats.get_mat("boards")
	Models.box(r, Vector3(1.9, 0.3, 0.12), b, Vector3(0, 0.5, 0), Vector3(0, 0, 0.25))
	Models.box(r, Vector3(1.9, 0.3, 0.12), b, Vector3(0, 0.6, 0), Vector3(0, 0, -0.25))
	Models.box(r, Vector3(1.9, 0.3, 0.12), b, Vector3(0, 1.15, 0.05))
	Models.box(r, Vector3(0.12, 1.4, 0.12), Mats.get_mat("plank"), Vector3(-0.8, 0.7, 0))
	Models.box(r, Vector3(0.12, 1.4, 0.12), Mats.get_mat("plank"), Vector3(0.8, 0.7, 0))


static func _alarm(r: Node3D) -> void:
	Models.cyl(r, 0.04, 0.05, 1.1, Mats.flat(Color(0.2, 0.2, 0.2)), Vector3(0, 0.55, 0))
	Models.cyl(r, 0.14, 0.1, 0.18, Mats.flat(Color(0.8, 0.7, 0.15), 0.2), Vector3(0, 1.15, 0))
	var l := Models.sphere(r, 0.07, Mats.get_mat("lamp_red"), Vector3(0, 1.28, 0))
	l.name = "Lamp"


static func _floodlight(r: Node3D) -> void:
	var metal := Mats.flat(Color(0.3, 0.3, 0.32), 0.0, 0.4, 0.7)
	for k in 3:
		var a := k * TAU / 3.0
		Models.cyl(r, 0.03, 0.03, 2.9, metal, Vector3(sin(a) * 0.3, 1.4, cos(a) * 0.3), Vector3(cos(a) * 0.1, 0, -sin(a) * 0.1))
	Models.box(r, Vector3(0.7, 0.45, 0.25), metal, Vector3(0, 2.9, 0), Vector3(0.4, 0, 0))
	var lens := Models.box(r, Vector3(0.6, 0.35, 0.05), Mats.get_mat("lamp"), Vector3(0, 2.85, -0.14), Vector3(0.4, 0, 0))
	lens.name = "Lens"


static func _decoy(r: Node3D) -> void:
	Models.box(r, Vector3(0.35, 0.3, 0.25), Mats.flat(Color(0.35, 0.3, 0.2)), Vector3(0, 0.15, 0))
	Models.cyl(r, 0.1, 0.16, 0.2, Mats.flat(Color(0.15, 0.15, 0.15)), Vector3(0, 0.38, 0))
	var l := Models.sphere(r, 0.04, _glow(Color(0.3, 0.9, 1.0), 2.0), Vector3(0.12, 0.32, -0.13))
	l.name = "Lamp"


static func _locker(r: Node3D) -> void:
	var metal := Mats.get_mat("metal")
	Models.box(r, Vector3(0.9, 2.0, 0.7), metal, Vector3(0, 1.0, 0))
	for k in 4:
		Models.box(r, Vector3(0.5, 0.03, 0.02), Mats.flat(Color(0.05, 0.05, 0.05)), Vector3(0, 1.55 + k * 0.06, -0.36))


static func _hatch(r: Node3D) -> void:
	Models.box(r, Vector3(1.0, 1.2, 0.15), Mats.get_mat("boards"), Vector3(0, 0.6, 0))
	Models.box(r, Vector3(0.1, 0.1, 0.1), Mats.flat(Color(0.5, 0.45, 0.2), 0.0, 0.4, 0.8), Vector3(0.35, 0.6, -0.1))

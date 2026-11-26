class_name CharacterModels
extends RefCounted
## Built-in character models: jointed bipeds (hips, knees, ankles, shoulders,
## elbows, wrists, neck) dressed per role and per killer. They are placeholders in
## the sense that a Forge export named after the slot replaces them (see Models),
## but they are animated procedurally through the joints named here:
##   Hips > LegL/LegR > ShinL/ShinR > FootL/FootR
##   Hips > Torso > Neck > Head,  Torso > ArmL/ArmR > ForearmL/ForearmR > HandL/HandR



static func _m(c: Color, rough: float = 0.85, metal: float = 0.0, emit: float = 0.0) -> StandardMaterial3D:
	return Mats.flat(c, emit, rough, metal)


## Builds the skeleton and body. p holds proportions and materials. Returns the joints.
static func biped(root: Node3D, p: Dictionary) -> Dictionary:
	var j := {}
	var thigh: float = p.get("thigh", 0.44)
	var shin: float = p.get("shin", 0.42)
	var foot_h: float = p.get("foot_h", 0.07)
	var hip_w: float = p.get("hip_w", 0.1)
	var torso_h: float = p.get("torso_h", 0.52)
	var chest_w: float = p.get("chest_w", 0.4)
	var chest_d: float = p.get("chest_d", 0.22)
	var waist_w: float = p.get("waist_w", 0.32)
	var shoulder_w: float = p.get("shoulder_w", 0.24)
	var upper: float = p.get("upper_arm", 0.3)
	var fore: float = p.get("forearm", 0.27)
	var neck_len: float = p.get("neck", 0.08)
	var head_r: float = p.get("head_r", 0.115)
	var leg_r: float = p.get("leg_r", 0.07)
	var arm_r: float = p.get("arm_r", 0.05)
	var top: Material = p["top"]
	var bottom: Material = p["bottom"]
	var boots: Material = p["boots"]
	var skin: Material = p["skin"]
	var hand_mat: Material = p.get("hands", skin)
	var hips := Models.pivot(root, "Hips", Vector3(0, thigh + shin + foot_h, 0))
	j["Hips"] = hips
	Models.box(hips, Vector3(waist_w, 0.16, chest_d * 0.9), bottom, Vector3(0, 0.02, 0))
	for side in [-1, 1]:
		var sfx := "L" if side < 0 else "R"
		var leg := Models.pivot(hips, "Leg" + sfx, Vector3(hip_w * side, -0.03, 0))
		Models.capsule(leg, leg_r * 1.15, thigh + leg_r, bottom, Vector3(0, -thigh * 0.5, 0))
		var sh := Models.pivot(leg, "Shin" + sfx, Vector3(0, -thigh, 0))
		Models.capsule(sh, leg_r, shin + leg_r * 0.6, bottom, Vector3(0, -shin * 0.5, 0))
		var ft := Models.pivot(sh, "Foot" + sfx, Vector3(0, -shin, 0))
		Models.box(ft, Vector3(leg_r * 1.9, foot_h + 0.02, leg_r * 3.6), boots, Vector3(0, -foot_h * 0.5, -leg_r * 0.7))
		Models.box(ft, Vector3(leg_r * 2.0, 0.12, leg_r * 2.0), boots, Vector3(0, 0.02, 0))  # boot shaft
		j["Leg" + sfx] = leg
		j["Shin" + sfx] = sh
		j["Foot" + sfx] = ft
	var torso := Models.pivot(hips, "Torso", Vector3(0, 0.06, 0))
	j["Torso"] = torso
	# abdomen + chest, wider at the shoulders
	Models.box(torso, Vector3(waist_w * 0.95, torso_h * 0.45, chest_d * 0.85), top, Vector3(0, torso_h * 0.22, 0))
	Models.box(torso, Vector3(chest_w, torso_h * 0.58, chest_d), top, Vector3(0, torso_h * 0.68, 0))
	var neck := Models.pivot(torso, "Neck", Vector3(0, torso_h, 0))
	j["Neck"] = neck
	Models.cyl(neck, head_r * 0.42, head_r * 0.5, neck_len + 0.04, skin, Vector3(0, neck_len * 0.5, 0))
	var head := Models.pivot(neck, "Head", Vector3(0, neck_len + head_r * 0.9, 0))
	j["Head"] = head
	for side in [-1, 1]:
		var sfx2 := "L" if side < 0 else "R"
		var arm := Models.pivot(torso, "Arm" + sfx2, Vector3((shoulder_w) * side, torso_h - 0.05, 0))
		Models.sphere(arm, arm_r * 1.35, top, Vector3.ZERO)
		Models.capsule(arm, arm_r * 1.1, upper + arm_r, top, Vector3(0, -upper * 0.5, 0))
		var fa := Models.pivot(arm, "Forearm" + sfx2, Vector3(0, -upper, 0))
		Models.capsule(fa, arm_r, fore + arm_r * 0.6, p.get("sleeve", top), Vector3(0, -fore * 0.5, 0))
		var hand := Models.pivot(fa, "Hand" + sfx2, Vector3(0, -fore, 0))
		Models.box(hand, Vector3(arm_r * 1.5, arm_r * 2.2, arm_r * 1.0), hand_mat, Vector3(0, -arm_r * 1.0, 0))
		j["Arm" + sfx2] = arm
		j["Forearm" + sfx2] = fa
		j["Hand" + sfx2] = hand
	return j


static func _face(head: Node3D, head_r: float, skin: Material, eye: Material) -> void:
	Models.sphere(head, head_r, skin, Vector3.ZERO, Vector3(0.92, 1.08, 1.0))
	Models.box(head, Vector3(head_r * 0.22, head_r * 0.35, head_r * 0.3), skin, Vector3(0, -head_r * 0.1, -head_r * 0.95))  # nose
	for side in [-1, 1]:
		Models.box(head, Vector3(head_r * 0.22, head_r * 0.12, 0.02), eye, Vector3(head_r * 0.38 * side, head_r * 0.12, -head_r * 0.9))
		Models.box(head, Vector3(head_r * 0.32, head_r * 0.07, 0.03), _m(Color(0.1, 0.07, 0.05)), Vector3(head_r * 0.38 * side, head_r * 0.3, -head_r * 0.92))
		Models.sphere(head, head_r * 0.2, skin, Vector3(head_r * 0.95 * side, 0, 0), Vector3(0.5, 1.0, 0.8))  # ears


# ------------------------------------------------------------------------------
# Survivors

static func survivor(root: Node3D, o: Dictionary) -> void:
	var role: int = o.get("role", -1)
	var jacket: Color = o.get("color", Color(0.5, 0.45, 0.35))
	var skin_tones := [Color(0.78, 0.6, 0.47), Color(0.55, 0.38, 0.27), Color(0.86, 0.7, 0.58), Color(0.42, 0.29, 0.2)]
	var skin := _m(skin_tones[int(o.get("variant", 0)) % skin_tones.size()], 0.7)
	var top := _m(jacket, 0.9)
	var pants := _m(Color(0.15, 0.16, 0.2) if role != Defs.Role.TRAPPER else Color(0.25, 0.22, 0.15), 0.95)
	var boots := _m(Color(0.12, 0.08, 0.06), 0.6)
	var j := biped(root, {"top": top, "bottom": pants, "boots": boots, "skin": skin, "hands": skin})
	var torso: Node3D = j["Torso"]
	var head: Node3D = j["Head"]
	_face(head, 0.115, skin, _m(Color(0.05, 0.05, 0.06), 0.3))
	var dark := _m(jacket.darkened(0.45))
	# jacket details: collar, zip, pockets, belt
	Models.box(torso, Vector3(0.3, 0.07, 0.2), dark, Vector3(0, 0.53, 0.01))
	Models.box(torso, Vector3(0.025, 0.42, 0.01), _m(Color(0.6, 0.6, 0.62), 0.3, 0.8), Vector3(0, 0.3, -0.115))
	for side in [-1, 1]:
		Models.box(torso, Vector3(0.11, 0.09, 0.03), dark, Vector3(0.11 * side, 0.2, -0.12))
	Models.box(j["Hips"], Vector3(0.34, 0.05, 0.22), _m(Color(0.2, 0.13, 0.08), 0.6), Vector3(0, 0.08, 0))
	# backpack with straps and a bedroll
	Models.box(torso, Vector3(0.3, 0.36, 0.14), dark, Vector3(0, 0.33, 0.17))
	Models.cyl(torso, 0.07, 0.07, 0.32, _m(Color(0.3, 0.32, 0.22)), Vector3(0, 0.56, 0.2), Vector3(0, 0, PI * 0.5))
	for side in [-1, 1]:
		Models.box(torso, Vector3(0.04, 0.4, 0.24), dark, Vector3(0.12 * side, 0.36, 0.0))
	# hair
	var hair := _m([Color(0.12, 0.09, 0.07), Color(0.35, 0.22, 0.1), Color(0.05, 0.05, 0.05), Color(0.5, 0.42, 0.3)][int(o.get("variant", 0)) % 4], 0.9)
	Models.sphere(head, 0.122, hair, Vector3(0, 0.035, 0.02), Vector3(1.0, 0.78, 1.02))
	# flashlight in the right hand
	Models.cyl(j["HandR"], 0.028, 0.034, 0.2, _m(Color(0.15, 0.15, 0.15), 0.4, 0.6), Vector3(0, -0.06, -0.08), Vector3(PI * 0.5, 0, 0))
	Models.sphere(j["HandR"], 0.03, Mats.flat(Color(1.0, 0.95, 0.8), 1.5), Vector3(0, -0.06, -0.19))
	match role:
		Defs.Role.ENGINEER:
			# hard hat, goggles and a tool belt
			var hat := _m(Color(0.95, 0.72, 0.1), 0.5)
			Models.sphere(head, 0.135, hat, Vector3(0, 0.06, 0), Vector3(1.0, 0.62, 1.05))
			Models.cyl(head, 0.17, 0.17, 0.02, hat, Vector3(0, 0.04, -0.01))
			Models.box(head, Vector3(0.2, 0.05, 0.03), _m(Color(0.2, 0.4, 0.45), 0.2, 0.5), Vector3(0, 0.09, -0.115))
			for k in 3:
				Models.box(j["Hips"], Vector3(0.05, 0.12, 0.04), _m(Color(0.4, 0.4, 0.42), 0.4, 0.7), Vector3(-0.12 + k * 0.08, 0.0, -0.12))
		Defs.Role.MEDIC:
			# red cross armband, med satchel, ponytail
			Models.box(j["ArmL"], Vector3(0.115, 0.07, 0.115), _m(Color(0.95, 0.95, 0.95)), Vector3(0, -0.1, 0))
			Models.box(j["ArmL"], Vector3(0.05, 0.05, 0.12), _m(Color(0.85, 0.1, 0.1)), Vector3(0, -0.1, 0))
			Models.box(torso, Vector3(0.22, 0.18, 0.1), _m(Color(0.85, 0.85, 0.82)), Vector3(-0.22, 0.12, 0.0), Vector3(0, 0, 0.2))
			Models.box(torso, Vector3(0.08, 0.025, 0.11), _m(Color(0.85, 0.1, 0.1)), Vector3(-0.22, 0.13, 0.0))
			Models.capsule(head, 0.035, 0.18, hair, Vector3(0, -0.06, 0.13), Vector3(0.4, 0, 0))
		Defs.Role.TRAPPER:
			# fur cap with flaps, rope coil, vest
			var fur := _m(Color(0.35, 0.25, 0.15), 1.0)
			Models.sphere(head, 0.13, fur, Vector3(0, 0.07, 0), Vector3(1.05, 0.6, 1.05))
			for side in [-1, 1]:
				Models.box(head, Vector3(0.03, 0.1, 0.08), fur, Vector3(0.12 * side, -0.02, 0.0))
			Models.cyl(torso, 0.13, 0.13, 0.05, _m(Color(0.6, 0.5, 0.32)), Vector3(0.12, 0.42, -0.05), Vector3(0.6, 0, 0.9))
			Models.box(torso, Vector3(0.42, 0.3, 0.235), _m(Color(0.3, 0.35, 0.2)), Vector3(0, 0.36, 0))


# ------------------------------------------------------------------------------
# Killers

static func _claws(hand: Node3D, n: int, length: float, mat: Material) -> void:
	for k in n:
		Models.box(hand, Vector3(0.018, 0.018, length), mat, Vector3((k - (n - 1) * 0.5) * 0.035, -0.08, -length * 0.4), Vector3(0.9, 0, 0))


static func _amber_veins(parent: Node3D, count: int, spread: Vector3, center: Vector3, size: float) -> void:
	var amber := Mats.get_mat("amber")
	for i in count:
		var p := center + Vector3(sin(i * 2.1) * spread.x, cos(i * 1.7) * spread.y, sin(i * 3.3) * spread.z)
		Models.box(parent, Vector3(size, size * 2.5, size), amber, p, Vector3(i * 0.7, i * 1.3, i * 0.4))


## The Tracker: gaunt and hunched, a ragged coat, a respirator mask with a glowing slit, long claws.
static func tracker(root: Node3D, _o: Dictionary) -> void:
	var skin := _m(Color(0.22, 0.19, 0.17), 0.75)
	var coat := _m(Color(0.1, 0.09, 0.08), 0.95)
	var j := biped(root, {"top": coat, "bottom": coat, "boots": _m(Color(0.06, 0.05, 0.05)), "skin": skin, "sleeve": skin,
		"thigh": 0.5, "shin": 0.48, "torso_h": 0.6, "chest_w": 0.36, "waist_w": 0.26, "shoulder_w": 0.22, "upper_arm": 0.4, "forearm": 0.4,
		"neck": 0.12, "head_r": 0.13, "leg_r": 0.06, "arm_r": 0.045})
	(j["Torso"] as Node3D).rotation.x = -0.45
	(j["Torso"] as Node3D).set_meta("rest_rx", -0.45)
	var head: Node3D = j["Head"]
	Models.sphere(head, 0.13, skin, Vector3.ZERO, Vector3(0.85, 1.05, 1.2))
	Models.box(head, Vector3(0.2, 0.14, 0.12), _m(Color(0.12, 0.12, 0.12), 0.4, 0.6), Vector3(0, -0.05, -0.13))  # respirator
	Models.cyl(head, 0.035, 0.035, 0.06, _m(Color(0.2, 0.2, 0.2), 0.4, 0.6), Vector3(0, -0.07, -0.2), Vector3(PI * 0.5, 0, 0))
	Models.box(head, Vector3(0.22, 0.03, 0.05), Mats.get_mat("amber"), Vector3(0, 0.03, -0.15))  # glowing slit
	# ragged coat tails hanging from the waist
	for k in 7:
		var a := (k - 3) * 0.06
		Models.box(j["Hips"], Vector3(0.07, 0.5 + (k % 3) * 0.08, 0.02), coat, Vector3(a, -0.25, 0.12 + absf(a) * 0.3), Vector3(0.12, 0, 0))
	# spine ridge
	for k in 5:
		Models.box(j["Torso"], Vector3(0.04, 0.05, 0.06), skin, Vector3(0, 0.12 + k * 0.1, 0.13))
	_amber_veins(j["Torso"], 6, Vector3(0.12, 0.25, 0.08), Vector3(0, 0.4, -0.1), 0.035)
	var claw := _m(Color(0.75, 0.72, 0.62), 0.35, 0.4)
	_claws(j["HandL"], 3, 0.26, claw)
	_claws(j["HandR"], 3, 0.26, claw)


## The Brute: a wall of muscle in scrap-metal plates, an iron mask, chains and huge fists.
static func brute(root: Node3D, _o: Dictionary) -> void:
	var skin := _m(Color(0.3, 0.22, 0.18), 0.7)
	var apron := _m(Color(0.2, 0.14, 0.1), 0.8)
	var metal := _m(Color(0.32, 0.3, 0.28), 0.5, 0.75)
	var j := biped(root, {"top": skin, "bottom": apron, "boots": _m(Color(0.08, 0.07, 0.06)), "skin": skin,
		"thigh": 0.52, "shin": 0.48, "foot_h": 0.1, "hip_w": 0.24, "torso_h": 0.9, "chest_w": 1.05, "chest_d": 0.62, "waist_w": 0.7,
		"shoulder_w": 0.62, "upper_arm": 0.5, "forearm": 0.5, "neck": 0.06, "head_r": 0.16, "leg_r": 0.16, "arm_r": 0.15})
	(j["Torso"] as Node3D).rotation.x = -0.25
	(j["Torso"] as Node3D).set_meta("rest_rx", -0.25)
	var torso: Node3D = j["Torso"]
	var head: Node3D = j["Head"]
	Models.sphere(head, 0.17, skin, Vector3.ZERO, Vector3(1.0, 0.9, 1.0))
	Models.box(head, Vector3(0.3, 0.26, 0.08), metal, Vector3(0, 0.0, -0.15))  # iron mask
	for side in [-1, 1]:
		Models.box(head, Vector3(0.05, 0.03, 0.02), Mats.get_mat("amber"), Vector3(0.07 * side, 0.04, -0.2))
	# hunched hump, shoulder plates, chains, apron
	Models.sphere(torso, 0.42, skin, Vector3(0, 0.82, 0.2), Vector3(1.5, 0.8, 1.0))
	for side in [-1, 1]:
		Models.box(j["Arm" + ("L" if side < 0 else "R")], Vector3(0.42, 0.12, 0.42), metal, Vector3(0.05 * side, 0.12, 0), Vector3(0, 0, 0.35 * side))
	for k in 6:
		Models.box(torso, Vector3(0.1, 0.05, 0.06), metal, Vector3(-0.45 + k * 0.18, 0.55 - k * 0.07, -0.33), Vector3(0, 0, 0.5))
	Models.box(j["Hips"], Vector3(0.75, 0.8, 0.05), apron, Vector3(0, -0.35, -0.34))
	_amber_veins(torso, 10, Vector3(0.4, 0.3, 0.1), Vector3(0, 0.6, -0.32), 0.07)
	for h in ["HandL", "HandR"]:
		Models.sphere(j[h], 0.2, skin, Vector3(0, -0.12, 0), Vector3(1.0, 0.9, 1.1))


## The Lurker: very tall and thin, a long neck, a split jaw with the tongue hanging out, ribs showing.
static func lurker(root: Node3D, _o: Dictionary) -> void:
	var skin := _m(Color(0.45, 0.42, 0.38), 0.6)
	var dark := _m(Color(0.22, 0.2, 0.19), 0.8)
	var j := biped(root, {"top": skin, "bottom": dark, "boots": dark, "skin": skin,
		"thigh": 0.56, "shin": 0.56, "foot_h": 0.05, "hip_w": 0.09, "torso_h": 0.62, "chest_w": 0.3, "chest_d": 0.18, "waist_w": 0.18,
		"shoulder_w": 0.17, "upper_arm": 0.46, "forearm": 0.46, "neck": 0.38, "head_r": 0.13, "leg_r": 0.045, "arm_r": 0.035})
	(j["Neck"] as Node3D).rotation.x = -0.6
	(j["Neck"] as Node3D).set_meta("rest_rx", -0.6)
	(j["Torso"] as Node3D).rotation.x = -0.15
	(j["Torso"] as Node3D).set_meta("rest_rx", -0.15)
	var head: Node3D = j["Head"]
	Models.sphere(head, 0.13, skin, Vector3.ZERO, Vector3(0.85, 0.8, 1.35))
	# split jaw and hanging tongue
	Models.box(head, Vector3(0.15, 0.04, 0.16), _m(Color(0.45, 0.05, 0.05), 0.5, 0.0, 0.6), Vector3(0, -0.06, -0.12))
	Models.box(head, Vector3(0.12, 0.03, 0.14), skin, Vector3(0, -0.1, -0.12), Vector3(0.35, 0, 0))
	Models.capsule(head, 0.025, 0.35, _m(Color(0.6, 0.12, 0.15), 0.4), Vector3(0, -0.22, -0.2), Vector3(0.3, 0, 0))
	for side in [-1, 1]:
		Models.sphere(head, 0.025, Mats.get_mat("amber"), Vector3(0.06 * side, 0.03, -0.14))
	# ribs
	for k in 5:
		Models.box(j["Torso"], Vector3(0.31, 0.02, 0.19), dark, Vector3(0, 0.3 + k * 0.06, -0.005))
	_amber_veins(j["Torso"], 4, Vector3(0.08, 0.2, 0.06), Vector3(0, 0.35, -0.08), 0.03)
	var claw := _m(Color(0.7, 0.68, 0.6), 0.35, 0.3)
	_claws(j["HandL"], 4, 0.14, claw)
	_claws(j["HandR"], 4, 0.14, claw)


## An elite: a caught survivor, clothes torn, amber growths, eyes glowing.
static func elite(root: Node3D, o: Dictionary) -> void:
	survivor(root, {"color": (o.get("color", Color(0.3, 0.25, 0.2)) as Color).darkened(0.45), "role": -1, "variant": o.get("variant", 0)})
	var torso := root.get_node("Hips/Torso") as Node3D
	torso.rotation.x = -0.25
	torso.set_meta("rest_rx", -0.25)
	_amber_veins(torso, 8, Vector3(0.16, 0.25, 0.12), Vector3(0, 0.35, 0.0), 0.05)
	var head := root.get_node("Hips/Torso/Neck/Head") as Node3D
	for side in [-1, 1]:
		Models.box(head, Vector3(0.035, 0.025, 0.02), Mats.get_mat("amber"), Vector3(0.044 * side, 0.015, -0.11))
	Models.box(head, Vector3(0.06, 0.12, 0.06), Mats.get_mat("amber"), Vector3(0.07, 0.07, 0.03), Vector3(0.3, 0, 0.6))


## A swarm husk: grey, stooped, overgrown.
static func husk(root: Node3D, o: Dictionary) -> void:
	survivor(root, {"color": Color(0.22, 0.2, 0.17), "role": -1, "variant": 3})
	var torso := root.get_node("Hips/Torso") as Node3D
	torso.rotation.x = -0.5
	torso.set_meta("rest_rx", -0.5)
	_amber_veins(torso, 6, Vector3(0.15, 0.2, 0.1), Vector3(0, 0.35, 0.05), 0.06)
	root.scale = Vector3.ONE * 0.92

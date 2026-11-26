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
	Models.sphere(hips, 0.5, bottom, Vector3(0, 0.02, 0), Vector3(waist_w * 1.05, 0.24, chest_d * 0.95), 16)
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
	Models.sphere(torso, 0.5, top, Vector3(0, torso_h * 0.25, 0), Vector3(waist_w * 1.0, torso_h * 0.6, chest_d * 0.9), 16)
	Models.sphere(torso, 0.5, top, Vector3(0, torso_h * 0.66, 0), Vector3(chest_w, torso_h * 0.66, chest_d), 16)
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
	var skin := Mats.organic(skin_tones[int(o.get("variant", 0)) % skin_tones.size()], 0.6, 1.5, 0.12, 0.12)
	var top := Mats.organic(jacket, 0.92, 3.0, 0.3, 0.2)
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
	## Thin glowing infection lines under the skin (not blobs).
	var amber := Mats.flat(Color(0.75, 0.28, 0.03), 0.55, 0.6)
	for i in count / 2:
		var p := center + Vector3(sin(i * 2.1) * spread.x, cos(i * 1.7) * spread.y, sin(i * 3.3) * spread.z)
		Models.box(parent, Vector3(size * 0.35, size * 3.5, size * 0.35), amber, p, Vector3(i * 0.7, i * 1.3, i * 0.4))


# ---- horror kit -----------------------------------------------------------------

static func _wet(c: Color) -> StandardMaterial3D:
	## Slick, sweating skin with pores and blotches: torches and lanterns glint off it.
	return Mats.organic(c, 0.35, 5.0, 0.11, 0.35)


static func _blood() -> StandardMaterial3D:
	return Mats.organic(Color(0.2, 0.012, 0.01), 0.25, 2.0, 0.2, 0.5)


static func _bone() -> StandardMaterial3D:
	return _m(Color(0.72, 0.66, 0.52), 0.55)


static func _teeth(parent: Node3D, count: int, width: float, at: Vector3, length: float, down: bool) -> void:
	var bone := _bone()
	for k in count:
		var x := -width * 0.5 + width * (float(k) + 0.5) / count
		var l := length * (0.7 + 0.3 * float((k * 7) % 3) / 2.0)
		Models.box(parent, Vector3(width / count * 0.55, l, 0.012), bone, at + Vector3(x, (-l if down else l) * 0.5, 0), Vector3(0, 0, (k % 2 - 0.5) * 0.25))


static func _splatter(parent: Node3D, count: int, center: Vector3, spread: Vector3, size: float) -> void:
	var b := _blood()
	for i in count:
		var p := center + Vector3(sin(i * 3.7) * spread.x, cos(i * 2.3) * spread.y, sin(i * 1.9) * spread.z)
		# stains, not flakes: thin, lying flat on the surface, smeared downwards
		Models.box(parent, Vector3(size * (1.2 + float(i % 3) * 0.6), size * (2.0 + float(i % 2) * 2.0), 0.006), b, p, Vector3(0, 0, (float(i % 5) - 2.0) * 0.15))


static func _stitches(parent: Node3D, from: Vector3, to: Vector3, n: int) -> void:
	var thread := _m(Color(0.08, 0.06, 0.05), 0.9)
	for k in n:
		var p := from.lerp(to, (float(k) + 0.5) / n)
		Models.box(parent, Vector3(0.008, 0.008, 0.05), thread, p, Vector3(0, 0.6, 0.0))
	Models.box(parent, Vector3(0.006, 0.006, from.distance_to(to)), _blood(), (from + to) * 0.5, Vector3(0, atan2(to.x - from.x, to.z - from.z), 0))


static func _eyes(head: Node3D, pts: Array, r: float, col: Color = Color(1.0, 0.55, 0.1)) -> void:
	var glow := Mats.flat(col, 3.0, 0.3)
	for pt in pts:
		Models.sphere(head, r, glow, pt)
	var lamp := OmniLight3D.new()
	lamp.light_color = col
	lamp.light_energy = 0.35
	lamp.omni_range = 1.6
	lamp.position = (pts[0] as Vector3) + Vector3(0, 0, -0.05)
	head.add_child(lamp)


## The Tracker: a skinned, starved thing with backward-bent legs, a face of stitched-on
## skin over a respirator, six burning eyes and fingers that end in long hooked blades.
static func tracker(root: Node3D, _o: Dictionary) -> void:
	var skin := _wet(Color(0.2, 0.17, 0.16))
	var raw := _wet(Color(0.36, 0.12, 0.1))
	var coat := _m(Color(0.06, 0.055, 0.05), 0.95)
	var j := biped(root, {"top": raw, "bottom": coat, "boots": skin, "skin": skin, "sleeve": skin, "hands": skin,
		"thigh": 0.52, "shin": 0.56, "torso_h": 0.62, "chest_w": 0.32, "waist_w": 0.2, "chest_d": 0.2, "shoulder_w": 0.2,
		"upper_arm": 0.46, "forearm": 0.48, "neck": 0.16, "head_r": 0.13, "leg_r": 0.052, "arm_r": 0.038})
	var torso: Node3D = j["Torso"]
	torso.rotation.x = -0.6
	# digitigrade legs: knees bent backwards at rest
	for sd in ["L", "R"]:
		(j["Shin" + sd] as Node3D).rotation.x = 0.55
		(j["Leg" + sd] as Node3D).rotation.x = -0.35
		(j["Foot" + sd] as Node3D).rotation.x = -0.2
	(j["Neck"] as Node3D).rotation.x = 0.5          # head thrust forward and up
	var head: Node3D = j["Head"]
	Models.sphere(head, 0.13, skin, Vector3.ZERO, Vector3(0.8, 1.15, 1.1))
	# a mask of someone else's face, stitched on, sagging
	Models.box(head, Vector3(0.2, 0.22, 0.03), _m(Color(0.62, 0.5, 0.42), 0.6), Vector3(0, 0.0, -0.125), Vector3(0.1, 0, 0.06))
	_stitches(head, Vector3(-0.1, 0.11, -0.14), Vector3(0.1, 0.1, -0.14), 7)
	_stitches(head, Vector3(-0.1, -0.11, -0.14), Vector3(0.1, -0.1, -0.14), 7)
	Models.box(head, Vector3(0.12, 0.1, 0.1), _m(Color(0.1, 0.1, 0.1), 0.4, 0.6), Vector3(0, -0.08, -0.17))  # respirator
	for sd2 in [-1, 1]:
		Models.cyl(head, 0.02, 0.02, 0.3, _m(Color(0.12, 0.1, 0.1), 0.5, 0.4), Vector3(0.07 * sd2, -0.15, 0.0), Vector3(0.9, 0, 0.3 * sd2))
	_eyes(head, [Vector3(-0.05, 0.05, -0.15), Vector3(0.05, 0.05, -0.15), Vector3(-0.035, 0.09, -0.145), Vector3(0.035, 0.09, -0.145), Vector3(-0.07, 0.0, -0.14), Vector3(0.07, 0.0, -0.14)], 0.012)
	# exposed spine and ribs through torn skin
	var bone := _bone()
	for k in 8:
		Models.box(torso, Vector3(0.05, 0.04, 0.07), bone, Vector3(0, 0.08 + k * 0.07, 0.11))
	for k in 4:
		for sd3 in [-1, 1]:
			Models.box(torso, Vector3(0.16, 0.022, 0.03), bone, Vector3(0.08 * sd3, 0.25 + k * 0.08, -0.1), Vector3(0, 0, -0.35 * sd3))
	_splatter(torso, 4, Vector3(0, 0.3, -0.11), Vector3(0.1, 0.2, 0.02), 0.03)
	# coat in rags, hanging off the shoulders and hips
	for k in 9:
		var a := (k - 4) * 0.045
		Models.box(j["Hips"], Vector3(0.06, 0.45 + (k % 3) * 0.14, 0.015), coat, Vector3(a, -0.25, 0.1 + absf(a) * 0.4), Vector3(0.18, 0, 0.05 * (k % 3 - 1)))
	_amber_veins(torso, 8, Vector3(0.1, 0.25, 0.05), Vector3(0, 0.35, -0.1), 0.03)
	# hooked finger-blades, longer than a forearm
	var blade := _m(Color(0.55, 0.52, 0.48), 0.25, 0.85)
	for h in ["HandL", "HandR"]:
		for k in 4:
			var bl := Models.pivot(j[h], "Blade%d" % k, Vector3((k - 1.5) * 0.026, -0.07, 0))
			Models.box(bl, Vector3(0.012, 0.5, 0.025), blade, Vector3(0, -0.25, -0.04), Vector3(0.25, 0, 0))
			Models.box(bl, Vector3(0.012, 0.1, 0.025), blade, Vector3(0, -0.52, -0.12), Vector3(1.3, 0, 0))
			Models.box(bl, Vector3(0.014, 0.08, 0.03), _blood(), Vector3(0, -0.45, -0.08), Vector3(0.5, 0, 0))
	for nm in ["Torso", "Neck", "LegL", "LegR", "ShinL", "ShinR", "FootL", "FootR"]:
		if j.has(nm):
			(j[nm] as Node3D).set_meta("rest_override", true)


## The Brute: a bloated slaughterhouse giant, skin stretched over meat, a face sewn shut
## behind a welded cage, bone spikes out of the back, a butcher's apron soaked through,
## a meat hook on a chain and a cleaver the size of a door.
static func brute(root: Node3D, _o: Dictionary) -> void:
	var skin := _wet(Color(0.42, 0.3, 0.27))
	var meat := _wet(Color(0.45, 0.1, 0.09))
	var apron := _m(Color(0.22, 0.17, 0.12), 0.45)
	var metal := _m(Color(0.3, 0.27, 0.24), 0.45, 0.8)
	var j := biped(root, {"top": skin, "bottom": apron, "boots": _m(Color(0.07, 0.06, 0.05)), "skin": skin,
		"thigh": 0.52, "shin": 0.48, "foot_h": 0.1, "hip_w": 0.25, "torso_h": 0.9, "chest_w": 1.0, "chest_d": 0.7, "waist_w": 0.85,
		"shoulder_w": 0.6, "upper_arm": 0.52, "forearm": 0.52, "neck": 0.12, "head_r": 0.15, "leg_r": 0.17, "arm_r": 0.15})
	var torso: Node3D = j["Torso"]
	torso.rotation.x = -0.3
	(j["Neck"] as Node3D).position += Vector3(0, -0.02, -0.22)   # head jutting forward from the hump
	# a sagging gut and a hump of raw meat on the shoulders
	Models.sphere(torso, 0.5, skin, Vector3(0, 0.28, -0.2), Vector3(0.95, 0.65, 0.7))
	Models.sphere(torso, 0.45, meat, Vector3(0, 0.78, 0.38), Vector3(1.4, 0.55, 0.8))
	_stitches(torso, Vector3(-0.3, 0.55, -0.62), Vector3(0.25, 0.05, -0.66), 10)
	_splatter(torso, 4, Vector3(0, 0.35, -0.5), Vector3(0.25, 0.2, 0.02), 0.05)
	# bone spikes out of the back
	var bone := _bone()
	for k in 6:
		Models.cyl(torso, 0.0, 0.05, 0.4 + (k % 3) * 0.12, bone, Vector3(-0.35 + k * 0.14, 0.95 + (k % 2) * 0.08, 0.42), Vector3(-0.6, 0, (k - 2.5) * 0.15))
	var head: Node3D = j["Head"]
	Models.sphere(head, 0.15, skin, Vector3.ZERO, Vector3(1.0, 0.95, 1.0))
	# mouth and eyes sewn shut, one eye torn open and burning
	_stitches(head, Vector3(-0.07, -0.06, -0.15), Vector3(0.07, -0.06, -0.15), 6)
	_stitches(head, Vector3(-0.09, 0.04, -0.14), Vector3(-0.02, 0.04, -0.145), 3)
	_eyes(head, [Vector3(0.05, 0.04, -0.145)], 0.02, Color(1.0, 0.3, 0.05))
	# welded cage over the face
	for k in 5:
		Models.box(head, Vector3(0.015, 0.3, 0.015), metal, Vector3(-0.1 + k * 0.05, 0.0, -0.18))
	for k in 3:
		Models.box(head, Vector3(0.24, 0.015, 0.015), metal, Vector3(0, -0.1 + k * 0.1, -0.18))
	# blood-soaked butcher's apron
	Models.box(j["Hips"], Vector3(0.85, 0.85, 0.04), apron, Vector3(0, -0.38, -0.44))
	_splatter(j["Hips"], 5, Vector3(0, -0.4, -0.47), Vector3(0.3, 0.3, 0.01), 0.06)
	# a cleaver in the right hand, a meat hook dangling from the left
	var cleaver := Models.pivot(j["HandR"], "Cleaver", Vector3(0, -0.15, 0))
	Models.box(cleaver, Vector3(0.05, 0.05, 0.35), _m(Color(0.2, 0.14, 0.1), 0.7), Vector3(0, 0, 0))
	Models.box(cleaver, Vector3(0.025, 0.42, 0.62), metal, Vector3(0, -0.12, -0.45))
	Models.box(cleaver, Vector3(0.028, 0.25, 0.3), _blood(), Vector3(0, -0.2, -0.55))
	for k in 5:
		Models.box(j["HandL"], Vector3(0.05, 0.08, 0.03), metal, Vector3(0, -0.2 - k * 0.08, 0), Vector3(0, k * 1.2, 0))
	Models.cyl(j["HandL"], 0.02, 0.02, 0.28, metal, Vector3(0, -0.72, -0.08), Vector3(0.9, 0, 0))
	Models.box(j["HandL"], Vector3(0.05, 0.05, 0.03), _blood(), Vector3(0, -0.8, -0.18))
	for h in ["HandL", "HandR"]:
		Models.sphere(j[h], 0.17, skin, Vector3(0, -0.1, 0), Vector3(1.0, 0.9, 1.1))
	_amber_veins(torso, 10, Vector3(0.4, 0.3, 0.06), Vector3(0, 0.6, -0.62), 0.06)


## The Lurker: a skeleton wrapped in grey skin, twice too tall, joints bending the wrong way,
## a jaw that unhinges down to its chest full of needle teeth, the tongue hanging out wet.
static func lurker(root: Node3D, _o: Dictionary) -> void:
	var skin := _wet(Color(0.4, 0.4, 0.37))
	var dark := _wet(Color(0.16, 0.15, 0.15))
	var gum := _wet(Color(0.35, 0.05, 0.07))
	var j := biped(root, {"top": skin, "bottom": dark, "boots": dark, "skin": skin,
		"thigh": 0.6, "shin": 0.62, "foot_h": 0.05, "hip_w": 0.08, "torso_h": 0.66, "chest_w": 0.26, "chest_d": 0.16, "waist_w": 0.14,
		"shoulder_w": 0.16, "upper_arm": 0.56, "forearm": 0.58, "neck": 0.44, "head_r": 0.12, "leg_r": 0.038, "arm_r": 0.03})
	(j["Neck"] as Node3D).rotation.x = -0.75
	(j["Torso"] as Node3D).rotation.x = -0.25
	var head: Node3D = j["Head"]
	Models.sphere(head, 0.12, skin, Vector3(0, 0.03, 0.02), Vector3(0.8, 0.8, 1.3))
	# unhinged lower jaw hanging down to the chest
	var jaw := Models.pivot(head, "Jaw", Vector3(0, -0.04, -0.02))
	jaw.rotation.x = 0.9
	Models.box(jaw, Vector3(0.13, 0.03, 0.24), skin, Vector3(0, -0.02, -0.12))
	Models.box(jaw, Vector3(0.11, 0.03, 0.2), gum, Vector3(0, 0.005, -0.12))
	_teeth(jaw, 9, 0.11, Vector3(0, 0.01, -0.2), 0.05, false)
	Models.box(head, Vector3(0.11, 0.02, 0.18), gum, Vector3(0, -0.04, -0.12))
	_teeth(head, 11, 0.11, Vector3(0, -0.045, -0.2), 0.06, true)
	# the tongue: long, wet, dripping
	var tongue := _m(Color(0.55, 0.08, 0.12), 0.15)
	Models.capsule(jaw, 0.022, 0.5, tongue, Vector3(0, -0.2, -0.22), Vector3(0.3, 0, 0))
	for k in 3:
		Models.box(jaw, Vector3(0.012, 0.08 + k * 0.05, 0.012), tongue, Vector3((k - 1) * 0.02, -0.45 - k * 0.04, -0.2))
	# no eyes: pits that glow from inside
	_eyes(head, [Vector3(-0.04, 0.06, -0.12), Vector3(0.04, 0.06, -0.12)], 0.016, Color(0.9, 0.2, 0.1))
	# ribs and spine pressing through the skin
	var bone := _bone()
	for k in 7:
		Models.box(j["Torso"], Vector3(0.28, 0.018, 0.17), dark, Vector3(0, 0.22 + k * 0.055, -0.005))
	for k in 9:
		Models.box(j["Torso"], Vector3(0.035, 0.035, 0.05), bone, Vector3(0, 0.05 + k * 0.07, 0.09))
	# elbows and knees: bone spurs
	for nm in ["ForearmL", "ForearmR", "ShinL", "ShinR"]:
		Models.cyl(j[nm], 0.0, 0.025, 0.12, bone, Vector3(0, 0.0, 0.05), Vector3(-1.3, 0, 0))
	_splatter(j["Torso"], 6, Vector3(0, 0.3, -0.09), Vector3(0.08, 0.2, 0.01), 0.03)
	_amber_veins(j["Torso"], 5, Vector3(0.06, 0.2, 0.04), Vector3(0, 0.35, -0.08), 0.025)
	# too-long fingers
	var claw := _m(Color(0.25, 0.22, 0.2), 0.3)
	for h in ["HandL", "HandR"]:
		for k in 4:
			Models.box(j[h], Vector3(0.012, 0.3, 0.012), claw, Vector3((k - 1.5) * 0.022, -0.2, -0.02), Vector3(0.15, 0, (k - 1.5) * 0.08))


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

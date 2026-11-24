class_name Mats
extends RefCounted
## Procedural textures and materials, generated once at startup.
## No external art is needed; Forge-made models can replace meshes (see Models).

static var _cache := {}


static func get_mat(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	var m := _make(key)
	_cache[key] = m
	return m


static func _tri(mat: StandardMaterial3D, scale: float) -> void:
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * scale
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


static func _noise_tex(freq: float, colors: Array, kind: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH, octaves: int = 4, size: int = 256, normal: bool = false, bump: float = 6.0) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = kind
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = int(freq * 1000.0) + colors.size()
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	else:
		var g := Gradient.new()
		var offs := PackedFloat32Array()
		var cols := PackedColorArray()
		for i in colors.size():
			offs.append(float(i) / maxf(1.0, colors.size() - 1.0))
			cols.append(colors[i])
		g.offsets = offs
		g.colors = cols
		t.color_ramp = g
	return t


static func _img_tex(img: Image, normal_strength: float = 0.0) -> Array:
	var albedo := img.duplicate() as Image
	albedo.generate_mipmaps()
	var at := ImageTexture.create_from_image(albedo)
	var nt: ImageTexture = null
	if normal_strength > 0.0:
		var bump := img.duplicate() as Image
		bump.convert(Image.FORMAT_RGBA8)
		bump.bump_map_to_normal_map(normal_strength)
		bump.generate_mipmaps()
		nt = ImageTexture.create_from_image(bump)
	return [at, nt]


static func _hash(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10000) / 10000.0


static func _planks(base: Color, size: int = 128, plank_h: int = 16, seed_v: int = 1, vertical: bool = false) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.05
	for y in size:
		var row := y / plank_h
		var tint := 0.82 + _hash(row, 3, seed_v) * 0.3
		var offs := int(_hash(row, 9, seed_v) * size)
		for x in size:
			var gx := x if not vertical else y
			var gy := y if not vertical else x
			row = gy / plank_h
			tint = 0.82 + _hash(row, 3, seed_v) * 0.3
			offs = int(_hash(row, 9, seed_v) * size)
			var grain := n.get_noise_2d(float((gx + offs) % size) * 0.25, float(gy) * 3.0)
			var c := base * (tint + grain * 0.12)
			if gy % plank_h == 0 or gy % plank_h == plank_h - 1:
				c = c * 0.45
			if (gx + offs) % size == 0 or (gx + offs) % size == 1:
				c = c * 0.5
			if (gx + offs) % (size / 2) == 6 and gy % plank_h == plank_h / 2:
				c = Color(0.15, 0.13, 0.12)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


static func _tiles(base: Color, grout: Color, cells: int, size: int = 128, grime: float = 0.25, seed_v: int = 2) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.03
	var cs := size / cells
	for y in size:
		for x in size:
			var gn := n.get_noise_2d(x, y)
			var c := base * (0.92 + _hash(x / cs, y / cs, seed_v) * 0.12)
			c = c.lerp(Color(0.25, 0.22, 0.15), clampf(gn * grime + grime * 0.4, 0.0, 0.8))
			if x % cs < 2 or y % cs < 2:
				c = grout
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


static func _metal(base: Color, rust: float, size: int = 128, panel: int = 64, seed_v: int = 3, stripes: bool = false) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.045
	n.fractal_octaves = 5
	for y in size:
		for x in size:
			var r := n.get_noise_2d(x, y)
			var c := base * (0.9 + r * 0.15)
			if stripes and y < 18:
				c = Color(0.85, 0.65, 0.1) if ((x + y) / 12) % 2 == 0 else Color(0.08, 0.08, 0.08)
			c = c.lerp(Color(0.45, 0.22, 0.08), clampf((r + 0.15) * rust * 2.0, 0.0, 0.85))
			if x % panel < 2 or y % panel < 2:
				c = c * 0.55
			var px := x % panel
			var py := y % panel
			if (px == 6 or px == panel - 6) and (py == 6 or py == panel - 6):
				c = c * 0.4
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


static func _make(key: String) -> Material:
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	match key:
		"dirt":
			m.albedo_texture = _noise_tex(0.02, [Color(0.17, 0.14, 0.1), Color(0.27, 0.22, 0.16), Color(0.33, 0.28, 0.2)])
			m.normal_enabled = true
			m.normal_texture = _noise_tex(0.04, [], FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4, 256, true, 4.0)
			_tri(m, 0.18)
		"mud":
			m.albedo_texture = _noise_tex(0.018, [Color(0.07, 0.08, 0.05), Color(0.15, 0.15, 0.09), Color(0.2, 0.19, 0.12)])
			m.roughness = 0.55
			_tri(m, 0.15)
		"grass":
			m.albedo_texture = _noise_tex(0.03, [Color(0.06, 0.09, 0.04), Color(0.13, 0.17, 0.07), Color(0.2, 0.2, 0.1)])
			m.normal_enabled = true
			m.normal_texture = _noise_tex(0.08, [], FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3, 256, true, 3.0)
			_tri(m, 0.2)
		"plateau":
			m.albedo_texture = _noise_tex(0.025, [Color(0.14, 0.14, 0.11), Color(0.22, 0.23, 0.16), Color(0.3, 0.28, 0.22)])
			_tri(m, 0.18)
		"rock":
			m.albedo_texture = _noise_tex(0.035, [Color(0.12, 0.11, 0.1), Color(0.24, 0.22, 0.2), Color(0.36, 0.33, 0.29)], FastNoiseLite.TYPE_CELLULAR, 3)
			m.normal_enabled = true
			m.normal_texture = _noise_tex(0.035, [], FastNoiseLite.TYPE_CELLULAR, 3, 256, true, 9.0)
			_tri(m, 0.22)
		"minefloor":
			m.albedo_texture = _noise_tex(0.04, [Color(0.1, 0.09, 0.08), Color(0.18, 0.16, 0.13), Color(0.24, 0.21, 0.17)])
			m.normal_enabled = true
			m.normal_texture = _noise_tex(0.06, [], FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4, 256, true, 5.0)
			_tri(m, 0.25)
		"cliff":
			m.albedo_texture = _noise_tex(0.02, [Color(0.1, 0.1, 0.1), Color(0.2, 0.19, 0.18), Color(0.3, 0.29, 0.27)], FastNoiseLite.TYPE_CELLULAR, 4)
			m.normal_enabled = true
			m.normal_texture = _noise_tex(0.02, [], FastNoiseLite.TYPE_CELLULAR, 4, 256, true, 12.0)
			_tri(m, 0.12)
		"ceiling":
			m.albedo_texture = _noise_tex(0.05, [Color(0.06, 0.055, 0.05), Color(0.12, 0.11, 0.1)], FastNoiseLite.TYPE_CELLULAR, 2)
			_tri(m, 0.25)
		"wood":
			var r := _img_tex(_planks(Color(0.36, 0.26, 0.17), 128, 16, 11), 3.0)
			m.albedo_texture = r[0]
			m.normal_enabled = true
			m.normal_texture = r[1]
			_tri(m, 0.5)
		"plank":
			var r2 := _img_tex(_planks(Color(0.3, 0.22, 0.14), 128, 21, 23), 2.0)
			m.albedo_texture = r2[0]
			m.normal_enabled = true
			m.normal_texture = r2[1]
			_tri(m, 0.45)
		"boards":
			var r3 := _img_tex(_planks(Color(0.5, 0.4, 0.28), 128, 24, 5, true), 4.0)
			m.albedo_texture = r3[0]
			m.normal_enabled = true
			m.normal_texture = r3[1]
			_tri(m, 0.5)
		"roof":
			var r4 := _img_tex(_planks(Color(0.16, 0.14, 0.13), 128, 10, 41), 2.0)
			m.albedo_texture = r4[0]
			_tri(m, 0.6)
		"lab_wall":
			var r5 := _img_tex(_tiles(Color(0.62, 0.66, 0.64), Color(0.3, 0.32, 0.31), 2, 128, 0.5, 7), 1.5)
			m.albedo_texture = r5[0]
			m.normal_enabled = true
			m.normal_texture = r5[1]
			m.roughness = 0.6
			_tri(m, 0.5)
		"lab_floor":
			var r6 := _img_tex(_tiles(Color(0.38, 0.4, 0.39), Color(0.16, 0.17, 0.16), 4, 128, 0.55, 8), 1.5)
			m.albedo_texture = r6[0]
			m.roughness = 0.45
			_tri(m, 0.5)
		"metal":
			var r7 := _img_tex(_metal(Color(0.32, 0.33, 0.34), 0.5, 128, 64, 4), 2.0)
			m.albedo_texture = r7[0]
			m.normal_enabled = true
			m.normal_texture = r7[1]
			m.metallic = 0.5
			m.roughness = 0.65
			_tri(m, 0.5)
		"quarantine":
			var r8 := _img_tex(_metal(Color(0.42, 0.43, 0.4), 0.35, 128, 64, 9, true), 2.0)
			m.albedo_texture = r8[0]
			m.normal_enabled = true
			m.normal_texture = r8[1]
			m.metallic = 0.4
			m.roughness = 0.6
			_tri(m, 0.5)
		"rust":
			var r9 := _img_tex(_metal(Color(0.3, 0.2, 0.15), 0.9, 128, 128, 12), 2.0)
			m.albedo_texture = r9[0]
			m.metallic = 0.3
			_tri(m, 0.6)
		"crate":
			var r10 := _img_tex(_planks(Color(0.45, 0.34, 0.2), 128, 32, 17), 3.0)
			m.albedo_texture = r10[0]
			_tri(m, 1.0)
		"bark":
			m.albedo_texture = _noise_tex(0.08, [Color(0.07, 0.06, 0.05), Color(0.16, 0.13, 0.1)], FastNoiseLite.TYPE_CELLULAR, 2)
			_tri(m, 0.7)
		"foliage":
			m.albedo_color = Color(0.09, 0.12, 0.07)
			m.roughness = 1.0
		"water":
			m.albedo_color = Color(0.09, 0.13, 0.1, 0.86)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic = 0.1
			m.metallic_specular = 0.9
		"amber":
			m.albedo_color = Color(1.0, 0.55, 0.1)
			m.emission_enabled = true
			m.emission = Defs.AMBER
			m.emission_energy_multiplier = 1.5
			m.roughness = 0.25
		"amber_dim":
			m.albedo_color = Color(0.7, 0.35, 0.08)
			m.emission_enabled = true
			m.emission = Color(0.9, 0.45, 0.08)
			m.emission_energy_multiplier = 0.8
		"lamp":
			m.albedo_color = Color(1.0, 0.85, 0.55)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.75, 0.4)
			m.emission_energy_multiplier = 3.0
		"lamp_red":
			m.albedo_color = Color(1.0, 0.2, 0.15)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.1, 0.05)
			m.emission_energy_multiplier = 3.0
		"pit":
			m.albedo_color = Color(0.01, 0.01, 0.01)
		"terminal":
			m.albedo_color = Color(0.2, 0.22, 0.24)
			m.metallic = 0.6
			m.roughness = 0.4
		"screen_off":
			m.albedo_color = Color(0.05, 0.07, 0.06)
			m.emission_enabled = true
			m.emission = Color(0.1, 0.25, 0.15)
			m.emission_energy_multiplier = 0.4
		"screen_on":
			m.albedo_color = Color(0.2, 1.0, 0.5)
			m.emission_enabled = true
			m.emission = Color(0.2, 1.0, 0.45)
			m.emission_energy_multiplier = 2.5
		"cable":
			m.albedo_color = Color(0.05, 0.05, 0.05)
		_:
			m.albedo_color = Color(1, 0, 1)
	return m


static func flat(color: Color, emission: float = 0.0, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var key := "flat_%s_%.2f_%.2f_%.2f" % [color.to_html(), emission, rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_cache[key] = m
	return m


static func floor_key(st: int) -> String:
	match st:
		Defs.S.DIRT: return "dirt"
		Defs.S.MUD: return "mud"
		Defs.S.GRASS: return "grass"
		Defs.S.PLATEAU: return "plateau"
		Defs.S.MINEFLOOR, Defs.S.ROCK: return "minefloor"
		Defs.S.LABFLOOR, Defs.S.LAB: return "lab_floor"
		Defs.S.PLANK, Defs.S.WOOD, Defs.S.BRIDGE: return "plank"
		Defs.S.METAL, Defs.S.QUARANTINE: return "metal"
	return "dirt"


static func wall_key(st: int) -> String:
	match st:
		Defs.S.WOOD, Defs.S.PLANK: return "wood"
		Defs.S.ROCK: return "rock"
		Defs.S.LAB: return "lab_wall"
		Defs.S.CLIFF: return "cliff"
		Defs.S.QUARANTINE: return "quarantine"
		Defs.S.METAL: return "metal"
	return "rock"

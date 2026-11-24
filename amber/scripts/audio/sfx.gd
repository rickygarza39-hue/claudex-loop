class_name Sfx
extends Node
## Procedurally synthesised sound effects (no audio files needed). World noises
## from the match are played positionally; heartbeat and UI sounds are 2D.

const RATE := 22050

static var bank := {}

var pool3d: Array = []
var pool2d: Array = []
var _i3 := 0
var _i2 := 0
var wind: AudioStreamPlayer
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	if bank.is_empty():
		_build_bank()
	for i in 20:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 70.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		pool3d.append(p)
	for i in 8:
		var q := AudioStreamPlayer.new()
		add_child(q)
		pool2d.append(q)
	wind = AudioStreamPlayer.new()
	wind.stream = bank["wind"]
	wind.volume_db = -14.0
	add_child(wind)
	wind.play()


func play3d(name: String, pos: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	if not bank.has(name):
		return
	var p: AudioStreamPlayer3D = pool3d[_i3]
	_i3 = (_i3 + 1) % pool3d.size()
	p.stream = bank[name]
	p.global_position = pos
	p.volume_db = db
	p.pitch_scale = pitch * rng.randf_range(0.94, 1.06)
	p.play()


func play2d(name: String, db: float = 0.0, pitch: float = 1.0) -> void:
	if not bank.has(name):
		return
	var p: AudioStreamPlayer = pool2d[_i2]
	_i2 = (_i2 + 1) % pool2d.size()
	p.stream = bank[name]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func loop3d(parent: Node3D, name: String, db: float = 0.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = bank[name]
	p.volume_db = db
	p.unit_size = 10.0
	p.max_distance = 160.0
	p.autoplay = true
	parent.add_child(p)
	return p


## Called by Match.make_noise for world events.
func on_noise(kind: String, at: Vector3) -> void:
	match kind:
		"steps": play3d("step", at, -10.0)
		"build": play3d("hammer", at, -4.0)
		"lock": play3d("lock", at, -8.0)
		"steal": play3d("rummage", at, -6.0)
		"smash", "collapse": play3d("smash", at, 2.0)
		"scream": play3d("scream", at, -2.0)
		"flare": play3d("flare", at, 4.0)
		"alarm": play3d("alarm", at, 0.0)
		"decoy": play3d("decoy", at, -4.0)
		"roar": play3d("roar", at, 4.0)
		"trap", "clang", "seal": play3d("clang", at, 0.0)
		"swing": play3d("swing", at, -4.0)
		"door": play3d("door", at, -2.0)
		"terminal": play3d("beep", at, -2.0)
		"generator": play3d("gen_start", at, -2.0)
		"nest": play2d("drone", -6.0)
		"pant": play3d("pant", at, -6.0)
		"lockdown": play3d("lockdown", at, 2.0)
		"thud": play3d("thud", at, 0.0)


# ------------------------------------------------------------------------------
# Synthesis

static func _wav(s: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


static func _lp(s: PackedFloat32Array, a: float) -> PackedFloat32Array:
	var y := 0.0
	for i in s.size():
		y += a * (s[i] - y)
		s[i] = y
	return s


static func _norm(s: PackedFloat32Array, peak: float = 0.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in s:
		m = maxf(m, absf(v))
	for i in s.size():
		s[i] = s[i] / m * peak
	return s


static func _build_bank() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	# heartbeat: lub-dub
	var hb := _buf(0.6)
	for i in hb.size():
		var t := float(i) / RATE
		var v := 0.0
		for st in [[0.0, 1.0], [0.24, 0.7]]:
			var tt: float = t - st[0]
			if tt >= 0.0:
				v += sin(TAU * 52.0 * tt) * exp(-tt * 22.0) * st[1]
		hb[i] = v
	bank["heart"] = _wav(_norm(hb, 0.95))
	# footstep
	var stp := _buf(0.12)
	for i in stp.size():
		var t2 := float(i) / RATE
		stp[i] = r.randf_range(-1, 1) * exp(-t2 * 40.0)
	bank["step"] = _wav(_norm(_lp(stp, 0.18), 0.6))
	# swing whoosh
	var sw := _buf(0.3)
	for i in sw.size():
		var t3 := float(i) / RATE
		sw[i] = r.randf_range(-1, 1) * sin(PI * t3 / 0.3)
	bank["swing"] = _wav(_norm(_lp(sw, 0.25), 0.6))
	# thud
	var th := _buf(0.35)
	for i in th.size():
		var t4 := float(i) / RATE
		th[i] = sin(TAU * (90.0 - t4 * 120.0) * t4) * exp(-t4 * 12.0) + r.randf_range(-0.3, 0.3) * exp(-t4 * 30.0)
	bank["thud"] = _wav(_norm(th))
	# metal clang (parry, traps)
	var cl := _buf(0.7)
	for i in cl.size():
		var t5 := float(i) / RATE
		cl[i] = (sin(TAU * 620.0 * t5) + 0.6 * sin(TAU * 1370.0 * t5) + 0.4 * sin(TAU * 2240.0 * t5)) * exp(-t5 * 7.0)
	bank["clang"] = _wav(_norm(cl, 0.7))
	# scream-ish gasp
	var sc := _buf(0.7)
	for i in sc.size():
		var t6 := float(i) / RATE
		var f := 520.0 + 90.0 * sin(TAU * 7.0 * t6) - t6 * 160.0
		var saw := fmod(t6 * f, 1.0) * 2.0 - 1.0
		sc[i] = (saw * 0.6 + r.randf_range(-0.4, 0.4)) * sin(PI * t6 / 0.7)
	bank["scream"] = _wav(_norm(_lp(sc, 0.35), 0.55))
	# flare: bang + hiss
	var fl := _buf(1.2)
	for i in fl.size():
		var t7 := float(i) / RATE
		fl[i] = r.randf_range(-1, 1) * (exp(-t7 * 25.0) + 0.25 * exp(-t7 * 2.5))
	bank["flare"] = _wav(_norm(fl))
	# hammering: three knocks
	var hm := _buf(0.8)
	for i in hm.size():
		var t8 := float(i) / RATE
		var v2 := 0.0
		for k in 3:
			var tt2 := t8 - k * 0.24
			if tt2 >= 0.0:
				v2 += (sin(TAU * 180.0 * tt2) + r.randf_range(-0.5, 0.5)) * exp(-tt2 * 35.0)
		hm[i] = v2
	bank["hammer"] = _wav(_norm(hm, 0.6))
	# lock picking clicks
	var lk := _buf(0.6)
	for i in lk.size():
		var t9 := float(i) / RATE
		var v3 := 0.0
		for k2 in 4:
			var tt3 := t9 - k2 * 0.13 - 0.02 * sin(k2 * 3.0)
			if tt3 >= 0.0:
				v3 += sin(TAU * 3100.0 * tt3) * exp(-tt3 * 180.0)
		lk[i] = v3
	bank["lock"] = _wav(_norm(lk, 0.4))
	bank["rummage"] = bank["lock"]
	# smash: crack + thud + debris
	var sm := _buf(0.9)
	for i in sm.size():
		var t10 := float(i) / RATE
		sm[i] = r.randf_range(-1, 1) * (exp(-t10 * 18.0) + 0.3 * exp(-t10 * 5.0) * (1.0 if r.randf() < 0.3 else 0.0)) + sin(TAU * 70.0 * t10) * exp(-t10 * 10.0)
	bank["smash"] = _wav(_norm(_lp(sm, 0.5)))
	# alarm
	var al := _buf(1.2)
	for i in al.size():
		var t11 := float(i) / RATE
		var f2 := 880.0 if fmod(t11, 0.3) < 0.15 else 660.0
		al[i] = (1.0 if sin(TAU * f2 * t11) > 0.0 else -1.0) * 0.5 * (1.0 if fmod(t11, 0.3) < 0.26 else 0.0)
	bank["alarm"] = _wav(_norm(al, 0.45))
	# decoy chirp
	var dc := _buf(0.5)
	for i in dc.size():
		var t12 := float(i) / RATE
		dc[i] = sin(TAU * (1200.0 + 600.0 * sin(TAU * 9.0 * t12)) * t12) * sin(PI * t12 / 0.5)
	bank["decoy"] = _wav(_norm(dc, 0.45))
	# brute roar
	var ro := _buf(1.3)
	for i in ro.size():
		var t13 := float(i) / RATE
		var f3 := 75.0 + 25.0 * sin(TAU * 1.3 * t13)
		var saw2 := fmod(t13 * f3, 1.0) * 2.0 - 1.0
		ro[i] = (saw2 + r.randf_range(-0.6, 0.6)) * sin(PI * t13 / 1.3) * (0.8 + 0.2 * sin(TAU * 13.0 * t13))
	bank["roar"] = _wav(_norm(_lp(ro, 0.2)))
	# door creak / bars
	var dr := _buf(0.6)
	for i in dr.size():
		var t14 := float(i) / RATE
		dr[i] = sin(TAU * (240.0 + 120.0 * t14) * t14 + 3.0 * sin(TAU * 31.0 * t14)) * sin(PI * t14 / 0.6)
	bank["door"] = _wav(_norm(dr, 0.5))
	# terminal beep
	var bp := _buf(0.4)
	for i in bp.size():
		var t15 := float(i) / RATE
		bp[i] = sin(TAU * 1050.0 * t15) * (1.0 if (t15 < 0.12 or (t15 > 0.2 and t15 < 0.32)) else 0.0)
	bank["beep"] = _wav(_norm(bp, 0.4))
	# pickup chime
	var ch := _buf(0.35)
	for i in ch.size():
		var t16 := float(i) / RATE
		ch[i] = sin(TAU * (880.0 if t16 < 0.12 else 1320.0) * t16) * exp(-t16 * 6.0)
	bank["pickup"] = _wav(_norm(ch, 0.4))
	# Nest drone
	var dn := _buf(3.0)
	for i in dn.size():
		var t17 := float(i) / RATE
		dn[i] = (sin(TAU * 44.0 * t17) + sin(TAU * 66.5 * t17) * 0.7 + sin(TAU * 89.0 * t17) * 0.3) * sin(PI * t17 / 3.0)
	bank["drone"] = _wav(_norm(dn, 0.8))
	# stinger (a killer has seen you)
	var sg := _buf(1.0)
	for i in sg.size():
		var t18 := float(i) / RATE
		sg[i] = (sin(TAU * 311.0 * t18) + sin(TAU * 329.6 * t18) + sin(TAU * 466.0 * t18)) * minf(t18 * 8.0, 1.0) * exp(-t18 * 2.5)
	bank["stinger"] = _wav(_norm(sg, 0.5))
	# tired panting
	var pa := _buf(1.0)
	for i in pa.size():
		var t19 := float(i) / RATE
		pa[i] = r.randf_range(-1, 1) * absf(sin(PI * t19 * 3.0))
	bank["pant"] = _wav(_norm(_lp(pa, 0.15), 0.5))
	# lockdown slam
	bank["lockdown"] = bank["smash"]
	bank["gen_start"] = bank["thud"]
	# loops: helicopter rotor, generator hum, wind
	var hl := _buf(1.0)
	var ylp := 0.0
	for i in hl.size():
		var t20 := float(i) / RATE
		ylp += 0.08 * (r.randf_range(-1, 1) - ylp)
		var chop := 0.5 + 0.5 * pow(absf(sin(PI * 11.0 * t20)), 6.0)
		hl[i] = ylp * chop * 3.0 + sin(TAU * 44.0 * t20) * 0.25
	bank["heli"] = _wav(_norm(hl, 0.8), true)
	var gn := _buf(1.0)
	for i in gn.size():
		var t21 := float(i) / RATE
		gn[i] = (sin(TAU * 60.0 * t21) + 0.5 * sin(TAU * 120.0 * t21) + 0.25 * sin(TAU * 180.0 * t21)) * (0.85 + 0.15 * sin(TAU * 7.0 * t21))
	bank["generator"] = _wav(_norm(gn, 0.5), true)
	var wd := _buf(4.0)
	var yw := 0.0
	for i in wd.size():
		var t22 := float(i) / RATE
		yw += 0.02 * (r.randf_range(-1, 1) - yw)
		wd[i] = yw * (0.6 + 0.4 * sin(TAU * 0.25 * t22))
	bank["wind"] = _wav(_norm(wd, 0.6), true)

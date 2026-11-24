extends SceneTree
## Headless all-bot matches for balancing.
## godot --headless --script res://scripts/tests/sim.gd -- --seeds=1,2,3 [--log] [--dt=0.05]

func _initialize() -> void:
	var seeds := [1]
	var verbose := false
	var dt := 0.05
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = []
			for x in a.substr(8).split(","):
				seeds.append(int(x))
		if a == "--log":
			verbose = true
		if a.begins_with("--dt="):
			dt = float(a.substr(5))
	var summary: Array = []
	for sd in seeds:
		var t0 := Time.get_ticks_msec()
		var mt := Match.new()
		mt.sim_log = verbose
		root.add_child(mt)
		mt.setup({"seed": sd, "spectate": true, "card": sd % 4}, false)
		var steps := 0
		var trace := OS.get_cmdline_user_args().has("--trace")
		var next_trace := 30.0
		while not mt.over and steps < 200000:
			mt.step(dt)
			steps += 1
			if trace and mt.time >= next_trace:
				next_trace += 60.0
				print("-- t=%s" % Match.fmt_time(mt.time))
				for sv in mt.survivors:
					var ai = mt.brains.get(sv)
					print("   %-6s %-7s %-8s goal=%-10s hold=%-8s pos=%s parts=%s money=%d base=%s" % [sv.slot.name, sv.duo.name, Defs.HEALTH_NAMES[sv.health], ai.goal if ai else "-", ai.hold_id if ai else "-", str(MapData.tile_of(sv.pos)), str(sv.parts), sv.duo.money, ("stage%d st%s" % [sv.duo.base.stage, str(sv.duo.base.storage)]) if sv.duo.base else "none"])
				for c in mt.cells:
					var dd = c.get("duo")
					var ds := []
					for sl in dd.members:
						if sl.actor:
							ds.append("%.2f ch=%s wi=%s" % [sl.actor.pos.distance_to(MapData.center_of(c["door"])), sl.actor.channel.get("id", "-"), str(sl.actor.want_interact)])
					print("   cell %s open=%s worse=%s progress=%.1f door=%s  %s" % [dd.name, str(c["open"]), str(c["worse"]), c["progress"], str(c["door"]), str(ds)])
				for k in mt.killers:
					var kai = mt.brains.get(k)
					print("   %-14s state=%-10s pos=%s" % [k.slot.name, kai.state if kai else "-", str(MapData.tile_of(k.pos))])
		var ms := Time.get_ticks_msec() - t0
		var r: Dictionary = mt.result
		print("\n=== seed %d: %s  match time %s  escaped %d / caught %d  (%d ms real, %d steps)" % [sd, r.get("reason", "?"), Match.fmt_time(mt.time), r.get("escaped", 0), r.get("caught", 0), ms, steps])
		for line in mt.log_lines:
			print("   ", line)
		var stages := []
		for d in mt.duos:
			stages.append("%s:%d$%d" % [d.name, d.base.stage if d.base else -1, d.money])
		print("   final stages: ", " ".join(stages), "   nest fired: ", mt.nest.fired)
		summary.append([sd, mt.time, r.get("escaped", 0), r.get("caught", 0)])
		mt.queue_free()
	print("\nSUMMARY")
	var tot_e := 0
	var tot_t := 0.0
	for row in summary:
		print("  seed %d  %s  escaped %d  caught %d" % [row[0], Match.fmt_time(row[1]), row[2], row[3]])
		tot_e += row[2]
		tot_t += row[1]
	print("  avg escaped %.1f / 10, avg length %s" % [float(tot_e) / summary.size(), Match.fmt_time(tot_t / summary.size())])
	quit()

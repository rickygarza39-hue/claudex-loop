extends SceneTree
## godot --headless --script res://scripts/tests/mapgen_test.gd -- --seeds=1,2,3 [--ascii]

func _init() -> void:
	var seeds := [1, 2, 3, 4, 5, 6, 7, 8]
	var ascii := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = []
			for s in a.substr(8).split(","):
				seeds.append(int(s))
		if a == "--ascii":
			ascii = true
	for s in seeds:
		var t0 := Time.get_ticks_msec()
		var gen := MapGen.new()
		var m := gen.generate(s)
		var ms := Time.get_ticks_msec() - t0
		var counts := {}
		for it in m.items:
			var k: String = Defs.PART_NAMES[it["part"]] if it["kind"] == Defs.Item.PART else ["part", "cash", "scrap", "flare"][it["kind"]]
			counts[k] = counts.get(k, 0) + 1
		var gaps := 0
		for i in m.tiles.size():
			if m.tiles[i] == Defs.T.GAP:
				gaps += 1
		var worse := 0
		for c in m.cells:
			if c["worse"]:
				worse += 1
		print("seed %d: %d ms, macro=%s cells=%d (worse %d) terminals=%d entrances=%d gaps=%d lights=%d amber=%d items=%s" % [
			s, ms, str(m.macro), m.cells.size(), worse, m.terminals.size(), m.mine_entrances.size(), gaps, m.lights.size(), m.amber.size(), str(counts)])
		# reachability check: every item and cell door must be reachable for survivors from the nest
		var reach := _reach(m, m.nest, true)
		var bad := 0
		for it in m.items:
			if not reach.has(it["tile"]):
				bad += 1
		var bad_cells := 0
		for c in m.cells:
			var outside: Vector2i = c["door"] + c["dir"]
			if not reach.has(outside):
				bad_cells += 1
		var bad_terms := 0
		for tp in m.terminals:
			if not reach.has(tp):
				bad_terms += 1
		print("   unreachable: items=%d cells=%d terminals=%d   reachable tiles=%d" % [bad, bad_cells, bad_terms, reach.size()])
		if ascii:
			print(m.to_ascii())
	quit()


func _reach(m: MapData, start: Vector2i, survivor: bool) -> Dictionary:
	var seen := {start: true}
	var q := [start]
	var head := 0
	while head < q.size():
		var p: Vector2i = q[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var o: Vector2i = p + d
			if seen.has(o) or not m.walkable(o.x, o.y, survivor):
				continue
			var ha := m.height_at((MapData.center_of(p) + MapData.center_of(o)) * 0.5 + (MapData.center_of(p) - MapData.center_of(o)) * 0.01)
			var hb := m.height_at((MapData.center_of(p) + MapData.center_of(o)) * 0.5 + (MapData.center_of(o) - MapData.center_of(p)) * 0.01)
			if absf(ha - hb) > 0.7:
				continue
			seen[o] = true
			q.append(o)
	return seen

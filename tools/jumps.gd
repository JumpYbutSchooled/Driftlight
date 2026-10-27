extends SceneTree
## Jump counts from The Core (and from the nearest Core node) to each region, over the stargate network.
## godot --headless --path <project> --script res://tools/jumps.gd

var _f := 0


func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	var G = get_root().get_node("Game")
	var n: int = G.systems.size()
	# multi-source BFS from every Core-category system (the one Core, or the Core nodes)
	var cores := []
	for s in G.systems:
		if s.cat == G.CAT_BLUE:
			cores.append(s.id)
	var dist := {}
	var queue := []
	for c in cores:
		dist[c] = 0
		queue.append(c)
	var i := 0
	while i < queue.size():
		var u: int = queue[i]
		i += 1
		for v in G.systems[u].links:
			if not dist.has(v):
				dist[v] = dist[u] + 1
				queue.append(v)
	print("JUMPS %d Core systems %s; %d systems reachable of %d" % [cores.size(), str(cores.slice(0, 12)), dist.size(), n])
	var by_region := {}
	for s in G.systems:
		by_region[s.region] = by_region.get(s.region, []) + [dist.get(s.id, 999)]
	for r in G.REGIONS.size():
		var a: Array = by_region.get(r, [])
		if a.is_empty():
			continue
		a.sort()
		print("JUMPS %-16s %3d systems: nearest %2d jumps, median %2d, farthest %2d" % [G.REGIONS[r].name, a.size(), a[0], a[a.size() / 2], a[-1]])
	var all := dist.values()
	all.sort()
	print("JUMPS everywhere: median %d, 90%% within %d, farthest %d" % [all[all.size() / 2], all[int(all.size() * 0.9)], all[-1]])
	# how many jumps from the one Core (system 0) alone, for comparison
	var d0 := {0: 0}
	var q0 := [0]
	var j := 0
	while j < q0.size():
		var u: int = q0[j]
		j += 1
		for v in G.systems[u].links:
			if not d0.has(v):
				d0[v] = d0[u] + 1
				q0.append(v)
	var amber := 999
	for s in G.systems:
		if G.REGIONS[s.region].name == "Amber Expanse":
			amber = mini(amber, d0.get(s.id, 999))
	print("JUMPS from system 0 alone: Amber Expanse nearest %d, farthest overall %d" % [amber, d0.values().max()])
	quit()
	return true

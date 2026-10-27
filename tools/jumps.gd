extends SceneTree
## Jump counts to each region over the stargate network, from the original Core-ring systems (the same measure
## before and after the Core nodes were added) and from the nearest Core station (The Core or a Core node).
## godot --headless --path <project> --script res://tools/jumps.gd

var _f := 0


func bfs(G, sources: Array) -> Dictionary:
	var dist := {}
	var queue := []
	for c in sources:
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
	return dist


func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	var G = get_root().get_node("Game")
	var ring := []
	var stations := [0]
	for s in G.systems:
		if s.cat == G.CAT_BLUE and not s.get("core_node", false):
			ring.append(s.id)
		if s.get("core_node", false):
			stations.append(s.id)
	var d_ring := bfs(G, ring)
	var d_st := bfs(G, stations)
	print("JUMPS %d Core nodes (%d original Core systems)" % [G.core_nodes.size(), ring.size()])
	print("JUMPS %-16s  %s   |  %s" % ["", "from the original Core ring: nearest / median / farthest", "from the nearest Core station: median / farthest"])
	for r in G.REGIONS.size():
		var a := []
		var b := []
		for s in G.systems:
			if s.region == r and not s.get("core_node", false):
				a.append(d_ring.get(s.id, 999))
				b.append(d_st.get(s.id, 999))
		if a.is_empty():
			continue
		a.sort()
		b.sort()
		print("JUMPS %-16s  %2d / %2d / %2d  (%3d systems)   |  %2d / %2d" % [G.REGIONS[r].name, a[0], a[a.size() / 2], a[-1], a.size(), b[b.size() / 2], b[-1]])
	var d0 := bfs(G, [0])
	var amber := 999
	for s in G.systems:
		if G.REGIONS[s.region].name == "Amber Expanse":
			amber = mini(amber, d0.get(s.id, 999))
	print("JUMPS from The Core alone: Amber Expanse nearest %d, farthest anywhere %d" % [amber, d0.values().max()])
	quit()
	return true

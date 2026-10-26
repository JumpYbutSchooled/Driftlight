extends CenterContainer
## Inventory (I / Tab): cargo, ship & gear, missions, the notebook, the guide (with a build planner), stats and
## achievements.

const UI = preload("res://scripts/ui/ui.gd")
const TABS := [["cargo", "Cargo", "cargo"], ["ship", "Ship", "ship"], ["missions", "Missions", "mission"],
	["notebook", "Notebook", "planet"], ["guide", "Guide", "star"], ["stats", "Stats", "radar"], ["achievements", "Awards", "star"]]
const STAT_NAMES := [["ore", "Ore collected"], ["refined", "Materials refined"], ["pristine", "Pristine ore collected"],
	["regional", "Regional ore collected"], ["kills", "Pirates destroyed"], ["captains", "Pirate Captains destroyed"],
	["sentinels", "Sentinels destroyed"], ["systems", "Systems visited"], ["regions", "Regions visited"], ["jumps", "Stargate jumps"],
	["wild", "Wild system arrivals"], ["scans", "Planets scanned"], ["anomalies", "Anomalies found"], ["wormholes", "Wormholes traversed"],
	["relics", "Relics decoded"], ["salvaged", "Wrecks salvaged"], ["offerings", "Obelisk offerings"], ["missions", "Missions completed"],
	["ships_built", "Ships built"], ["earned", "Credits earned"], ["deaths", "Ships lost"]]

var main
var tab := "cargo"
var note_tag := ""  # notebook filter: a tag, or "" for everything
var note_ore := ""  # ...or places holding this ore
var goal := []  # the Guide planner's pick: [kind, id]
var _tabs: HBoxContainer
var _side: RichTextLabel
var _content: VBoxContainer
var _scroll: ScrollContainer
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1480, 860)
	add_child(panel)
	_panel = panel
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(UI.heading("INVENTORY", 24))
	tv.add_child(UI.lbl("I, Tab or Esc to close.   H opens the Guide.", 16, UI.MUTED))
	var close := UI.btn("Close", func(): main.close_inventory())
	close.custom_minimum_size = Vector2(150, 52)
	close.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	var sidep := PanelContainer.new()
	sidep.custom_minimum_size = Vector2(320, 0)
	sidep.add_theme_stylebox_override("panel", UI.frame("inset", 16))
	body.add_child(sidep)
	_side = RichTextLabel.new()
	_side.bbcode_enabled = true
	_side.size_flags_vertical = SIZE_EXPAND_FILL
	sidep.add_child(_side)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	right.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)
	Game.changed.connect(_on_changed)


func _on_changed() -> void:
	if visible:
		_rebuild()


func open(which := "") -> void:
	if which != "":
		tab = which
		_scroll.scroll_vertical = 0
	_rebuild()
	show()
	UI.pop_in(_panel)


func _set_tab(t: String) -> void:
	tab = t
	_scroll.scroll_vertical = 0
	_rebuild()


func _rebuild() -> void:
	for box in [_tabs, _content]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	for t in TABS:
		var b := UI.btn(t[1], _set_tab.bind(t[0]), t[2], UI.GOLD if tab == t[0] else UI.TEXT)
		b.toggle_mode = true
		b.button_pressed = tab == t[0]
		b.custom_minimum_size = Vector2(150, 46)
		_tabs.add_child(b)
	match tab:
		"cargo": _build_cargo()
		"ship": _build_ship()
		"missions": _build_missions()
		"notebook": _build_notebook()
		"guide": _build_guide()
		"stats": _build_stats()
		"achievements": _build_achievements()
	_side.text = _side_text()


func _side_text() -> String:
	var head := "[font_size=19][color=%s][b]%s[/b][/color][/font_size]\n" % [UI.hex(UI.HEAD), "%s"]
	var s := head % "WALLET"
	s += "[color=#ffd24a]%d credits[/color]\n\n" % Game.credits
	s += head % "MATERIALS"
	for o in Game.ORE_ORDER:
		var n := Game.carried(o)
		var st := Game.stored(o)
		if n > 0 or st > 0 or not Game.ORES[o].has("region"):
			s += "[color=%s]%s[/color]  %s%s\n" % [UI.hex(Game.ORES[o].color), Game.ORES[o].name, str(n) if n > 0 else "[color=#4c5672]0[/color]",
				"  [color=#8590a0](+%d stored)[/color]" % st if st > 0 else ""]
	s += "\n" + head % "SPICES"
	for id in Game.SPICE_ORDER:
		s += "[color=%s]%s[/color]  %d\n" % [UI.hex(Game.SPICES[id].color), Game.SPICES[id].name, Game.have(id)]
	s += "\n" + head % "SUPPLIES"
	s += "Probes  %d\n" % Game.probes
	if Game.portals > 0:
		s += "[color=#e080ff]Portable wormholes  %d[/color]\n" % Game.portals
	s += "\n[color=%s]Playtime %s[/color]" % [UI.hex(UI.MUTED), _time(Game.playtime)]
	return s


func _time(t: float) -> String:
	var m := int(t / 60.0)
	return "%dh %02dm" % [floori(m / 60.0), m % 60]


func _section(text: String, icon := "") -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	if icon != "":
		h.add_child(UI.icon_rect(icon, UI.HEAD, 3))
	h.add_child(UI.heading(text, 14))
	_content.add_child(h)


func _note(text: String, color := UI.MUTED) -> void:
	_content.add_child(UI.rich("[color=%s]%s[/color]" % [UI.hex(color), text], 980.0))


func _add(c: Dictionary, buttons := []) -> void:
	for b in buttons:
		var btn := UI.btn(b[0], b[1])
		btn.custom_minimum_size = Vector2(130, 44)
		btn.size_flags_vertical = SIZE_SHRINK_CENTER
		if b.size() > 2:
			btn.disabled = not b[2]
		c.box.add_child(btn)
	_content.add_child(c.root)


func _build_cargo() -> void:
	var st := Game.stats_ship()
	_section("CARGO HOLD   %d / %d" % [Game.cargo_used(), st.cargo], "cargo")
	if Game.cargo.is_empty():
		_note("Empty. Shoot ore veins and collect the chunks (fly into them, let the tractor pull them in, or press O).")
	else:
		_note("Jettisoned cargo is thrown out behind the ship as loose ore - you can scoop it up again.")
	var keys := Game.cargo.keys()
	keys.sort()
	for key in keys:
		var parts: PackedStringArray = key.split(":")
		var q := int(parts[1])
		var n: int = Game.cargo[key]
		var ore: Dictionary = Game.ORES[parts[0]]
		_add(UI.card("ore", ore.color, "%s   x%d" % [Game.ore_label(parts[0], q), n],
			"Refines into %d %s.  %s" % [n * Game.Q_YIELD[q], ore.name, ore.desc], Game.Q_COLORS[q]),
			[["Jettison", Game.jettison.bind(key), main.mode == "inventory"]])
	if st.refine > 0.0:
		_note("Your Portable Refinery smelts %d ore a minute straight out of the hold, best quality first." % roundi(st.refine),
			Color("ff9a3d"))


func _build_ship() -> void:
	var st := Game.stats_ship()
	var s: Dictionary = Game.SHIPS[Game.ship_id]
	_section("SHIP", "ship")
	var line := "%s\nHull %d   Shield %d   Speed %d   Turn %.1f rad/s\nCargo %d   Energy %d   Gun slots %d   Module slots %d   Tractor %d m" % [
		s.desc, st.hull, st.shield, st.speed, st.turn, st.cargo, st.energy, st.guns, st.slots, roundi(main.player.tractor_range())]
	if st.jump > 0.0:
		line += "   Jump drive reach %d" % roundi(st.jump)
	_add(UI.card("ship", s.colors[1], "%s  (%s, tier %d)" % [s.name, s["class"], s.tier], line, Color("9fd3ff")))
	_section("GUN SLOTS   %d" % st.guns, "weapon")
	var counts := {}
	for id in Game.loadout():
		counts[id] = counts.get(id, 0) + 1
	for id in counts:
		var w: Dictionary = Game.WEAPONS[id]
		_add(UI.card("weapon", w.color, "%s  x%d" % [w.name, counts[id]], "Each: damage %.0f   %.1f shots/s   mining %.1f%s" % [
			w.damage * st.damage, w.rate * st.fire, w.mining * st.mining, "   (beam)" if w.get("beam", false) else ""], w.color))
	_section("MODULES   %d / %d" % [Game.modules_equipped.size(), st.slots], "module")
	if Game.modules_equipped.is_empty():
		_note("No modules installed. Build them at a station Fabricator, then fit them here or with L.")
	for id in Game.modules_equipped:
		_add(UI.module_card(id))
	for id in Game.MODULE_ORDER:
		if Game.module_stock.get(id, 0) + Game.storage.modules.get(id, 0) > 0:
			_add(UI.module_card(id, "%s   %d carried, %d in station storage" % [Game.MODULES[id].name, Game.module_stock.get(id, 0),
				Game.storage.modules.get(id, 0)]))
	_section("HANGAR   %d / %d ships" % [Game.owned_ships.size(), Game.SHIPS.size()], "station")
	var ships := ", ".join(Game.owned_ships.map(func(id): return Game.SHIPS[id].name))
	var spare := []
	for id in Game.WEAPON_ORDER:
		var nw: int = Game.weapon_stock.get(id, 0) + Game.storage.weapons.get(id, 0)
		if nw > 0:
			spare.append("%s x%d" % [Game.WEAPONS[id].name, nw])
	var guns := ", ".join(spare) if not spare.is_empty() else "none - build weapons at a station"
	_add(UI.card("", Color.WHITE, "Owned ships", ships))
	_add(UI.card("", Color.WHITE, "Spare weapons (carried and in station storage)", guns))
	if not Game.blessings.is_empty():
		_section("BLESSINGS", "obelisk")
		for b in Game.blessings:
			_add(UI.card("obelisk", Color("e080ff"), b.capitalize(), "%d seconds left" % ceili(Game.blessings[b]), Color("e080ff")))


func _build_missions() -> void:
	_section("ACTIVE MISSIONS   %d / %d" % [Game.missions.size(), Game.MAX_MISSIONS], "mission")
	if Game.missions.is_empty():
		_note("No missions. Station mission boards offer bounties, courier runs, surveys, supply orders and expeditions.")
	for i in Game.missions.size():
		var m: Dictionary = Game.missions[i]
		var prog := "%d / %d" % [m.have, m.need]
		if m.type == "deliver":
			prog = "%d / %d %s in storage" % [mini(Game.have(m.ore), m.need), m.need, Game.ORES[m.ore].name]
		var buttons := [["Abandon", Game.abandon_mission.bind(i)]]
		if m.sys >= 0:
			buttons.push_front(["Route", _route.bind(m.sys)])
		_add(UI.card("mission", UI.GOOD, m.title, "%s\nProgress %s   Reward [color=#ffd24a]%d credits[/color]" % [m.desc,
			prog, m.reward], UI.GOOD), buttons)


func _route(sys_id: int) -> void:
	Game.clear_route()
	Game.route_target = sys_id
	Game.say("Route set to %s: %d jumps. T to auto-travel." % [Game.systems[sys_id].name, Game.route_path().size()], UI.GOLD)


func _add_stop(sys_id: int) -> void:
	Game.add_stop(sys_id)
	Game.say("Stop added: %s." % Game.systems[sys_id].name, UI.GOLD)


# ---------------------------------------------------------------- notebook

func _set_note_filter(tag: String, ore: String) -> void:
	note_tag = tag
	note_ore = ore
	_scroll.scroll_vertical = 0
	_rebuild()


func _build_notebook() -> void:
	_section("NOTEBOOK   %d places" % Game.notebook.size(), "planet")
	_note("Everywhere you've been or scanned is written down here: stations, refineries, ore fields, anomalies and more. Nearest first.")
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 6)
	var all := UI.btn("Everything", _set_note_filter.bind("", ""))
	all.toggle_mode = true
	all.button_pressed = note_tag == "" and note_ore == ""
	bar.add_child(all)
	for nt in Game.NOTE_TAGS:
		var b := UI.btn(nt[1], _set_note_filter.bind(nt[0], ""), nt[2], nt[3])
		b.toggle_mode = true
		b.button_pressed = note_tag == nt[0]
		bar.add_child(b)
	var ores := OptionButton.new()
	ores.focus_mode = FOCUS_NONE
	ores.add_item("Places with ore...")
	var ids := [""]
	for o in Game.ORE_ORDER:
		ores.add_item(Game.ORES[o].name)
		ids.append(o)
	ores.selected = maxi(0, ids.find(note_ore))
	ores.item_selected.connect(func(i): _set_note_filter("", ids[i]))
	bar.add_child(ores)
	_content.add_child(bar)
	var rows := Game.notes_with(note_tag, note_ore)
	if rows.is_empty():
		_note("Nothing noted yet." if Game.notebook.is_empty() else "Nothing like that noted yet.")
	for r in rows.slice(0, 80):
		_content.add_child(_note_row(r))
	if rows.size() > 80:
		_note("...and %d more further away." % (rows.size() - 80))


func _note_row(r: Dictionary) -> Control:
	var e: Dictionary = Game.notebook[r.key]
	var sys: Dictionary = Game.systems[r.sys]
	var l: Dictionary = sys.locs[r.loc]
	var bits := []
	for nt in Game.NOTE_TAGS:
		if e.tags.has(nt[0]):
			bits.append("[color=%s]%s[/color]" % [UI.hex(nt[3]), nt[1]])
	for o in e.ores:
		bits.append("[color=%s]%s[/color]" % [UI.hex(Game.ORES[o].color), Game.ORES[o].name])
	var here: bool = r.sys == Game.current_system
	var where := "%s  -  %s, %s space  -  %s" % [sys.name, Game.REGIONS[sys.region].name, Game.CAT_NAMES[sys.cat],
		"here" if here else ("%d jumps" % r.jumps if r.jumps < 99 else "far away")]
	var c := UI.card("station" if e.tags.has("station") else ("anomaly" if e.tags.has("anomaly") else "planet"),
		Game.CAT_COLORS[sys.cat], l.name, "%s\n%s" % [where, "   ".join(bits)], UI.TEXT)
	for b in [["Route", _route.bind(r.sys), not here], ["Add stop", _add_stop.bind(r.sys), not here]]:
		var btn := UI.btn(b[0], b[1])
		btn.custom_minimum_size = Vector2(120, 42)
		btn.size_flags_vertical = SIZE_SHRINK_CENTER
		btn.disabled = not b[2]
		c.box.add_child(btn)
	return c.root


# ---------------------------------------------------------------- guide

## The next ship up the ladder you don't own yet (the planner's default).
func _next_ship() -> String:
	for id in Game.SHIP_ORDER:
		if not Game.owned_ships.has(id) and Game.SHIPS[id].tier > 0:
			return id
	return Game.SHIP_ORDER[-1]


func _build_guide() -> void:
	if goal.is_empty():
		goal = Game.pinned[0] if not Game.pinned.is_empty() else ["ship", _next_ship()]
	_section("PLANNER", "star")
	_note("Pick something to build: the planner shows what it takes, what you're missing, and where to find it.")
	var pick := OptionButton.new()
	pick.focus_mode = FOCUS_NONE
	pick.custom_minimum_size = Vector2(700, 44)
	var items := []
	pick.add_separator("Ships")
	items.append([])
	for id in Game.SHIP_ORDER:
		if Game.SHIPS[id].tier == 0:
			continue
		var s: Dictionary = Game.SHIPS[id]
		pick.add_item("Tier %d  %s  (%s)%s" % [s.tier, s.name, s["class"], "  - owned" if Game.owned_ships.has(id) else ""])
		items.append(["ship", id])
	pick.add_separator("Weapons")
	items.append([])
	for id in Game.WEAPON_ORDER:
		if id == Game.BLASTER:
			continue
		pick.add_item(Game.WEAPONS[id].name)
		items.append(["weapon", id])
	pick.add_separator("Modules")
	items.append([])
	for id in Game.MODULE_ORDER:
		pick.add_item("%s  (%s)" % [Game.MODULES[id].name, Game.MODULE_CATS[Game.MODULES[id].cat].name])
		items.append(["module", id])
	for i in items.size():
		if items[i] == goal:
			pick.selected = i
	pick.item_selected.connect(_pick_goal.bind(items))
	_content.add_child(pick)
	_plan(goal)
	_content.add_child(HSeparator.new())
	_content.add_child(UI.rich(UI.GUIDE, 1000.0))


func _pick_goal(i: int, items: Array) -> void:
	goal = items[i]
	_rebuild()


func _plan(g: Array) -> void:
	var kind: String = g[0]
	var id: String = g[1]
	var cost := Game.build_cost(kind, id)
	var title := Game.pin_name(g)
	var ok := Game.can_afford(cost)
	var c := UI.card(kind if kind != "module" else Game.module_icon(id), UI.GOLD, title,
		UI.cost_text(cost) + ("\n[color=%s]You have everything: build it at any station's Fabricator.[/color]" % UI.hex(UI.GOOD) if ok else ""),
		UI.GOLD)
	var pin := UI.btn("Unpin" if Game.is_pinned(kind, id) else "Pin to HUD", func(): Game.toggle_pin(kind, id))
	pin.custom_minimum_size = Vector2(150, 44)
	pin.size_flags_vertical = SIZE_SHRINK_CENTER
	c.box.add_child(pin)
	_content.add_child(c.root)
	for k in cost:
		if Game.have(k) >= cost[k]:
			continue
		if k.begins_with("w:") or k.begins_with("m:"):
			_note("Needs a [color=%s]%s[/color] first - build that one at a Fabricator." % [UI.hex(Game.item_color(k)), Game.item_name(k)], UI.TEXT)
			continue
		if not Game.ORES.has(k):
			_note("[color=%s]%s[/color]: spice stands sell it." % [UI.hex(Game.item_color(k)), Game.item_name(k)], UI.TEXT)
			continue
		var short: int = cost[k] - Game.have(k)
		var places := Game.notes_with("", k).slice(0, 3)
		var row := UI.card("ore", Game.ORES[k].color, "%s  -  %d more refined" % [Game.ORES[k].name, short],
			"Found: %s.%s" % [Game.ore_where(k), "" if places.is_empty() else "  Noted at:"], Game.ORES[k].color)
		_content.add_child(row.root)
		for pl in places:
			_content.add_child(_note_row(pl))
	var refs := Game.notes_with("refinery").slice(0, 2)
	if not ok and not refs.is_empty():
		_note("Nearest refineries you know of:", UI.TEXT)
		for r in refs:
			_content.add_child(_note_row(r))


# ---------------------------------------------------------------- stats & achievements

func _build_stats() -> void:
	_section("PILOT RECORD", "radar")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	for s in STAT_NAMES:
		grid.add_child(UI.lbl(s[1], 19, UI.MUTED))
		grid.add_child(UI.lbl(str(Game.stat(s[0])), 19, UI.TEXT))
	var found := 0
	for a in Game.anomalies:
		if Game.systems[a.sys].locs[a.loc].found:
			found += 1
	var visited := Game.systems.filter(func(s): return s.visited).size()
	for pair in [["Galaxy explored", "%d / %d systems" % [visited, Game.systems.size()]],
			["Anomalies known", "%d / %d" % [found, Game.anomalies.size()]], ["Ships owned", "%d / %d" % [Game.owned_ships.size(),
			Game.SHIPS.size()]], ["Regional ores found", "%d / 9" % Game.regional_seen.size()], ["Playtime", _time(Game.playtime)]]:
		grid.add_child(UI.lbl(pair[0], 19, UI.MUTED))
		grid.add_child(UI.lbl(pair[1], 19, UI.GOLD))
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.frame("card", 20))
	box.add_child(grid)
	_content.add_child(box)


func _build_achievements() -> void:
	_section("ACHIEVEMENTS   %d / %d" % [Game.unlocked.size(), Game.ACHIEVEMENTS.size()], "star")
	for a in Game.ACHIEVEMENTS:
		var got: bool = Game.unlocked.has(a[0])
		var prog := "" if got else "   (%d / %d)" % [mini(Game.stat(a[3]), a[4]), a[4]]
		_add(UI.card("star", UI.GOLD if got else Color("3a4560"), a[1], a[2] + prog, UI.GOLD if got else UI.MUTED))

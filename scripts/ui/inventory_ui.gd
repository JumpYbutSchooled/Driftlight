extends CenterContainer
## Inventory (I / Tab): cargo, ship & gear, missions, stats and achievements.

const UI = preload("res://scripts/ui/ui.gd")
const TABS := [["cargo", "Cargo", "cargo"], ["ship", "Ship", "ship"], ["missions", "Missions", "mission"],
	["stats", "Stats", "radar"], ["achievements", "Achievements", "star"]]
const STAT_NAMES := [["ore", "Ore collected"], ["refined", "Materials refined"], ["pristine", "Pristine ore collected"],
	["kills", "Pirates destroyed"], ["captains", "Pirate Captains destroyed"], ["sentinels", "Sentinels destroyed"],
	["systems", "Systems visited"], ["jumps", "Stargate jumps"], ["wild", "Wild system arrivals"],
	["scans", "Planets scanned"], ["anomalies", "Anomalies found"], ["wormholes", "Wormholes traversed"],
	["salvaged", "Wrecks salvaged"], ["offerings", "Obelisk offerings"], ["missions", "Missions completed"],
	["ships_built", "Ships built"], ["earned", "Credits earned"], ["deaths", "Ships lost"]]

var main
var tab := "cargo"
var _tabs: HBoxContainer
var _side: RichTextLabel
var _content: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1480, 860)
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(UI.heading("INVENTORY", 24))
	tv.add_child(UI.lbl("Press I, Tab or Esc to close. Refined materials can be spent at any station.", 16, UI.MUTED))
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


func open() -> void:
	_rebuild()
	show()


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
		b.custom_minimum_size = Vector2(170, 46)
		_tabs.add_child(b)
	match tab:
		"cargo": _build_cargo()
		"ship": _build_ship()
		"missions": _build_missions()
		"stats": _build_stats()
		"achievements": _build_achievements()
	_side.text = _side_text()


func _side_text() -> String:
	var head := "[font_size=19][color=%s][b]%s[/b][/color][/font_size]\n" % [UI.hex(UI.HEAD), "%s"]
	var s := head % "WALLET"
	s += "[color=#ffd24a]%d credits[/color]\n\n" % Game.credits
	s += head % "MATERIALS"
	for o in Game.ORE_ORDER:
		var n := Game.have(o)
		s += "[color=%s]%s[/color]  %s\n" % [UI.hex(Game.ORES[o].color), Game.ORES[o].name, str(n) if n > 0 else "[color=#4c5672]0[/color]"]
	s += "\n" + head % "SPICES"
	for id in Game.SPICE_ORDER:
		s += "[color=%s]%s[/color]  %d\n" % [UI.hex(Game.SPICES[id].color), Game.SPICES[id].name, Game.have(id)]
	s += "\n" + head % "SUPPLIES"
	s += "Probes  %d\n" % Game.probes
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


func _add(c: Dictionary, buttons := []) -> void:
	for b in buttons:
		var btn := UI.btn(b[0], b[1])
		btn.custom_minimum_size = Vector2(140, 44)
		btn.size_flags_vertical = SIZE_SHRINK_CENTER
		c.box.add_child(btn)
	_content.add_child(c.root)


func _build_cargo() -> void:
	var st := Game.stats_ship()
	_section("CARGO HOLD   %d / %d" % [Game.cargo_used(), st.cargo], "cargo")
	if Game.cargo.is_empty():
		_content.add_child(UI.rich("[color=%s]Empty. Shoot ore rocks and fly into the pieces to collect them.[/color]" % UI.hex(UI.MUTED), 800))
	var keys := Game.cargo.keys()
	keys.sort()
	for key in keys:
		var parts: PackedStringArray = key.split(":")
		var q := int(parts[1])
		var n: int = Game.cargo[key]
		var ore: Dictionary = Game.ORES[parts[0]]
		_add(UI.card("ore", ore.color, "%s   x%d" % [Game.ore_label(parts[0], q), n],
			"Refines into %d %s.  %s" % [n * Game.Q_YIELD[q], ore.name, ore.desc], Game.Q_COLORS[q]),
			[["Jettison", Game.jettison.bind(key)]])


func _build_ship() -> void:
	var st := Game.stats_ship()
	var s: Dictionary = Game.SHIPS[Game.ship_id]
	_section("SHIP", "ship")
	var line := "%s\nHull %d   Shield %d   Speed %d   Turn %.1f rad/s\nCargo %d   Energy %d   Gun slots %d   Module slots %d" % [s.desc,
		st.hull, st.shield, st.speed, st.turn, st.cargo, st.energy, st.guns, st.slots]
	_add(UI.card("ship", s.colors[1], "%s  (%s)" % [s.name, s["class"]], line, Color("9fd3ff")))
	_section("GUN SLOTS   %d" % st.guns, "weapon")
	var counts := {}
	for id in Game.loadout():
		counts[id] = counts.get(id, 0) + 1
	for id in counts:
		var w: Dictionary = Game.WEAPONS[id]
		_add(UI.card("weapon", w.color, "%s  x%d" % [w.name, counts[id]], "Each: damage %.0f   %.1f shots/s   mining %.1f" % [
			w.damage * st.damage, w.rate * st.fire, w.mining * st.mining], w.color))
	_section("MODULES   %d / %d" % [Game.modules_equipped.size(), st.slots], "module")
	if Game.modules_equipped.is_empty():
		_content.add_child(UI.rich("[color=%s]No modules installed. Build them at a station Fabricator.[/color]" % UI.hex(UI.MUTED), 800))
	for id in Game.modules_equipped:
		_add(UI.card("module", UI.GOOD, Game.MODULES[id].name, Game.MODULES[id].desc, Color("c9b6ff")))
	for id in Game.MODULE_ORDER:
		if Game.module_stock.get(id, 0) > 0:
			_add(UI.card("module", UI.MUTED, "%s  x%d  (in storage)" % [Game.MODULES[id].name, Game.module_stock[id]],
				Game.MODULES[id].desc, UI.MUTED))
	_section("HANGAR", "station")
	var ships := ", ".join(Game.owned_ships.map(func(id): return Game.SHIPS[id].name))
	var spare := []
	for id in Game.WEAPON_ORDER:
		if Game.weapon_stock.get(id, 0) > 0:
			spare.append("%s x%d" % [Game.WEAPONS[id].name, Game.weapon_stock[id]])
	var guns := ", ".join(spare) if not spare.is_empty() else "none - mount weapons from the Hangar"
	_add(UI.card("", Color.WHITE, "Owned ships", ships))
	_add(UI.card("", Color.WHITE, "Spare weapons in storage", guns))
	if not Game.blessings.is_empty():
		_section("BLESSINGS", "obelisk")
		for b in Game.blessings:
			_add(UI.card("obelisk", Color("e080ff"), b.capitalize(), "%d seconds left" % ceili(Game.blessings[b]), Color("e080ff")))


func _build_missions() -> void:
	_section("ACTIVE MISSIONS   %d / %d" % [Game.missions.size(), Game.MAX_MISSIONS], "mission")
	if Game.missions.is_empty():
		_content.add_child(UI.rich("[color=%s]No missions. Station mission boards offer bounties, courier runs, surveys and supply orders.[/color]" % UI.hex(UI.MUTED), 900))
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
	Game.route_target = sys_id
	Game.say("Route set to %s." % Game.systems[sys_id].name, UI.GOLD)


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
			["Anomalies known", "%d / %d" % [found, Game.anomalies.size()]], ["Playtime", _time(Game.playtime)]]:
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

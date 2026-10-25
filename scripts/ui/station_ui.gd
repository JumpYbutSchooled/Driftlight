extends CenterContainer
## Station window (refinery / market / fabricator / hangar / missions), plus the spice stand and obelisk windows.

const UI = preload("res://scripts/ui/ui.gd")
const TABS := [["refinery", "Refinery", "flame"], ["market", "Market", "credits"], ["fabricator", "Fabricator", "wrench"],
	["hangar", "Hangar", "ship"], ["missions", "Missions", "mission"]]
const FAB_TABS := [["ships", "Ships", "ship"], ["weapons", "Weapons", "weapon"], ["modules", "Modules", "module"],
	["supplies", "Supplies", "probe"]]
const MARKET_TABS := [["sell", "Sell", "credits"], ["supplies", "Supplies", "probe"], ["ships", "Ships", "ship"],
	["weapons", "Weapons", "weapon"], ["modules", "Modules", "module"]]

var main
var mode := "station"  # station, spice, obelisk
var loc := {}
var loc_index := 0
var tab := "refinery"
var fab_tab := "ships"
var market_tab := "sell"
var weapon_base := "mining_lasers"  # which weapon's five marks the weapon lists show
var module_cat := ""  # which kind of module the module lists show ("" all)
var _panel: PanelContainer
var _title: Label
var _sub: Label
var _side: RichTextLabel
var _tabs: HBoxContainer
var _content: VBoxContainer
var _scroll: ScrollContainer
var _close: Button
var _result := ""
var _furnace_key := ""
var _smelt_label: Label
var _smelt_bar: ProgressBar
var _queue_label: RichTextLabel
var _out_label: RichTextLabel
var _collect_btn: Button


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
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(tv)
	_title = UI.heading("", 24)
	tv.add_child(_title)
	_sub = UI.lbl("", 16, UI.MUTED)
	tv.add_child(_sub)
	_close = UI.btn("Undock", func(): main.close_panel(), "gate")
	_close.custom_minimum_size = Vector2(190, 52)
	_close.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(_close)

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


func open(kind: String, l: Dictionary) -> void:
	mode = kind
	loc = l
	loc_index = Game.systems[Game.current_system].locs.find(l)
	_result = ""
	if kind == "station":
		tab = "refinery" if l.refinery else "market"
	_close.text = "Undock" if kind == "station" else "Leave"
	_scroll.scroll_vertical = 0
	_rebuild()
	show()
	UI.pop_in(_panel)


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _process(_delta: float) -> void:
	if visible and mode == "station" and tab == "refinery":
		_update_furnace()


func _rebuild() -> void:
	_clear(_tabs)
	_clear(_content)
	_smelt_bar = null
	var sys: Dictionary = Game.systems[Game.current_system]
	_tabs.visible = mode == "station"
	match mode:
		"station":
			_title.text = loc.name.to_upper()
			_sub.text = "%s  -  %s System  -  %s" % [sys.name, Game.CAT_NAMES[sys.cat],
				"Refinery on site" if loc.refinery else "No refinery here"]
			for t in TABS:
				if t[0] == "refinery" and not loc.refinery:
					continue
				_tabs.add_child(_tab_button(t, tab, _set_tab))
			match tab:
				"refinery": _build_refinery()
				"market": _build_market(sys)
				"fabricator": _build_fabricator()
				"hangar": _build_hangar()
				"missions": _build_missions()
		"spice":
			_build_spice(sys)
		"obelisk":
			_build_obelisk(sys)
	_side.text = _side_text()


func _tab_button(t: Array, current: String, cb: Callable) -> Button:
	var b := UI.btn(t[1], cb.bind(t[0]), t[2], UI.GOLD if current == t[0] else UI.TEXT)
	b.toggle_mode = true
	b.button_pressed = current == t[0]
	b.custom_minimum_size = Vector2(170, 46)
	return b


func _set_tab(t: String) -> void:
	tab = t
	_result = ""
	_scroll.scroll_vertical = 0
	_rebuild()


func _set_fab_tab(t: String) -> void:
	fab_tab = t
	_scroll.scroll_vertical = 0
	_rebuild()


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
	s += "\n" + head % ("CARGO  %d / %d" % [Game.cargo_used(), Game.stats_ship().cargo])
	if Game.cargo.is_empty():
		s += "[color=#4c5672]empty[/color]\n"
	for key in Game.cargo:
		var parts: PackedStringArray = key.split(":")
		var q := int(parts[1])
		s += "[color=%s]%s[/color] [color=%s]%s[/color] x%d\n" % [UI.hex(Game.ORES[parts[0]].color),
			Game.ORES[parts[0]].name, UI.hex(Game.Q_COLORS[q]), Game.q_tag(q, true), Game.cargo[key]]
	s += "\nProbes  %d" % Game.probes
	if Game.portals > 0:
		s += "\n[color=#e080ff]Portable wormholes  %d[/color]" % Game.portals
	return s


func _section(text: String, icon := "") -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	if icon != "":
		h.add_child(UI.icon_rect(icon, UI.HEAD, 3))
	h.add_child(UI.heading(text, 14))
	_content.add_child(h)


func _note(text: String, color := UI.MUTED) -> void:
	var l := UI.rich("[color=%s]%s[/color]" % [UI.hex(color), text], 900.0)
	_content.add_child(l)


## A card with an optional cost line and buttons ([text, callable, enabled]).
func _row(icon: String, icon_color: Color, title: String, desc: String, cost, buttons: Array, title_color := UI.TEXT) -> void:
	var c := UI.card(icon, icon_color, title, desc, title_color)
	if cost != null:
		c.text.add_child(UI.rich(UI.cost_text(cost), 700.0))
	for b in buttons:
		var btn := UI.btn(b[0], b[1])
		btn.disabled = not b[2]
		btn.custom_minimum_size = Vector2(150, 46)
		btn.size_flags_vertical = SIZE_SHRINK_CENTER
		c.box.add_child(btn)
	_content.add_child(c.root)


# ---------------------------------------------------------------- refinery

func _build_refinery() -> void:
	_furnace_key = "%d:%d" % [Game.current_system, loc_index]
	Game.refinery(_furnace_key, loc.name)
	_section("FURNACE", "flame")
	_note("Load raw ore and the furnace smelts it one piece at a time: about 1 second for Inferior up to 4 for Pristine, a little longer for rarer ores. It keeps going while you fly off (even with the game closed), and finished materials are collected automatically the next time you dock here.   Yield per piece:  [color=#8d8d8d]Inferior 1[/color]   [color=#f0f0f0]Normal 3[/color]   [color=#ffd24a]Superior 5[/color]   [color=#74f7ff]Pristine 25[/color]")
	var card := UI.card("flame", Color("ff9a3d"), "Smelting", "", Color("ff9a3d"))
	_smelt_label = UI.lbl("", 18)
	card.text.add_child(_smelt_label)
	_smelt_bar = ProgressBar.new()
	_smelt_bar.show_percentage = false
	_smelt_bar.max_value = 1.0
	_smelt_bar.custom_minimum_size = Vector2(640, 24)
	card.text.add_child(_smelt_bar)
	_queue_label = UI.rich("", 700.0)
	card.text.add_child(_queue_label)
	_content.add_child(card.root)

	var out := UI.card("cargo", UI.GOOD, "Finished materials", "", UI.GOOD)
	_out_label = UI.rich("", 640.0)
	out.text.add_child(_out_label)
	_collect_btn = UI.btn("Collect", _collect)
	_collect_btn.custom_minimum_size = Vector2(150, 46)
	_collect_btn.size_flags_vertical = SIZE_SHRINK_CENTER
	out.box.add_child(_collect_btn)
	_content.add_child(out.root)

	_section("LOAD ORE FROM YOUR HOLD", "cargo")
	if Game.cargo.is_empty():
		_note("Your cargo hold is empty. Go shoot some rocks!")
	else:
		var total := 0.0
		var keys := Game.cargo.keys()
		keys.sort()
		for key in keys:
			var parts: PackedStringArray = key.split(":")
			total += Game.refine_time(parts[0], int(parts[1])) * Game.cargo[key]
		_row("flame", UI.HEAD, "Everything in your hold", "%d ore, about %s to smelt" % [Game.cargo_used(), _clock(total)], null,
			[["Load All", _load_all, true]], UI.HEAD)
		for key in keys:
			var parts: PackedStringArray = key.split(":")
			var q := int(parts[1])
			var n: int = Game.cargo[key]
			var ore: Dictionary = Game.ORES[parts[0]]
			_row("ore", ore.color, "%s   x%d" % [Game.ore_label(parts[0], q), n],
				"Smelts into [color=%s]%d %s[/color] in %s." % [UI.hex(ore.color), n * Game.Q_YIELD[q], ore.name,
				_clock(Game.refine_time(parts[0], q) * n)], null, [["Load", _load.bind(key), true]], Game.Q_COLORS[q])
	_update_furnace()


## Refreshes the live parts of the furnace tab every frame without rebuilding it.
func _update_furnace() -> void:
	if _smelt_bar == null or not is_instance_valid(_smelt_bar):
		return
	var r := Game.refinery(_furnace_key)
	if r.queue.is_empty():
		_smelt_label.text = "Idle. Load some ore below."
		_smelt_bar.value = 0.0
		_queue_label.text = ""
	else:
		var cur: Array = r.queue[0]
		var ore: Dictionary = Game.ORES[cur[0]]
		_smelt_label.text = "%s  >  %d %s per piece" % [Game.ore_label(cur[0], cur[1]), Game.Q_YIELD[cur[1]], ore.name]
		_smelt_bar.value = r.progress / Game.refine_time(cur[0], cur[1])
		var lines := []
		var left := 0
		for item in r.queue:
			left += item[2]
			var tag := Game.q_tag(item[1])
			lines.append("[color=%s]%s[/color] [color=%s]%s[/color] x%d" % [UI.hex(Game.ORES[item[0]].color),
				Game.ORES[item[0]].name, UI.hex(Game.Q_COLORS[item[1]]), ("(%s)" % tag) if tag != "" else "", item[2]])
		_queue_label.text = "[color=%s]Queue: %d pieces, %s left[/color]\n%s" % [UI.hex(UI.MUTED), left,
			_clock(Game.refinery_seconds_left(r)), "   ".join(lines)]
	if r.output.is_empty():
		_out_label.text = "[color=%s]Nothing finished yet.[/color]" % UI.hex(UI.MUTED)
	else:
		var parts := []
		for id in r.output:
			parts.append("[color=%s]%d %s[/color]" % [UI.hex(Game.ORES[id].color), r.output[id], Game.ORES[id].name])
		_out_label.text = "   ".join(parts)
	_collect_btn.disabled = r.output.is_empty()


func _clock(t: float) -> String:
	var secs := ceili(t)
	return "%d:%02d" % [floori(secs / 60.0), secs % 60]


func _load(cargo_key: String) -> void:
	Game.load_ore(_furnace_key, loc.name, cargo_key)
	Sfx.play("dock", -10.0, 1.4)


func _load_all() -> void:
	Game.load_all(_furnace_key, loc.name)
	Sfx.play("dock", -10.0, 1.4)


func _collect() -> void:
	var got := Game.collect(_furnace_key)
	var parts := []
	for id in got:
		parts.append("%d %s" % [got[id], Game.ORES[id].name])
	if not parts.is_empty():
		Sfx.play("refine", -4.0)
		Game.say("Collected: " + ", ".join(parts), UI.GOOD)

# ---------------------------------------------------------------- market

func _set_market_tab(t: String) -> void:
	market_tab = t
	_scroll.scroll_vertical = 0
	_rebuild()


func _build_market(sys: Dictionary) -> void:
	var cat: int = sys.cat
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	for t in MARKET_TABS:
		bar.add_child(_tab_button(t, market_tab, _set_market_tab))
	_content.add_child(bar)
	match market_tab:
		"sell":
			_section("SELL MATERIALS", "credits")
			_note("Prices are higher the further you are from the core. This is a %s System market (x%.2f)." % [Game.CAT_NAMES[cat], Game.CAT_PRICE[cat]])
			var any := false
			for o in Game.ORE_ORDER:
				var n := Game.have(o)
				if n <= 0:
					continue
				any = true
				var price := Game.sell_price(o, cat)
				_row("ore", Game.ORES[o].color, "%s   x%d" % [Game.ORES[o].name, n],
					"%d credits each  -  [color=#ffd24a]%d credits[/color] for all" % [price, price * n], null,
					[["Sell 10", Game.sell.bind(o, 10, cat), true], ["Sell All", Game.sell.bind(o, n, cat), true]], Game.ORES[o].color)
			if not any:
				_note("You have no refined materials to sell. Smelt some ore first.")
			else:
				_row("credits", UI.GOLD, "Sell everything", "Every refined material you have, at this market's prices.", null,
					[["Sell All", _sell_all.bind(cat), true]], UI.GOLD)
			if Game.portals > 0:
				_row("anomaly", Color("e080ff"), "Portable wormhole   x%d" % Game.portals,
					"Collectors pay [color=#ffd24a]%d credits[/color] for one. Or keep it: from the galaxy map it takes you anywhere." % Game.WORMHOLE_PRICE,
					null, [["Sell one", _sell_portal, true]], Color("e080ff"))
		"supplies":
			_section("SUPPLIES", "cargo")
			_row("probe", Color("9fd3ff"), "Probe", "Ready-made probe.  %d credits each." % Game.PROBE_PRICE, null,
				[["Buy 1", _buy.bind("probe", 1), Game.credits >= Game.PROBE_PRICE],
				["Buy 5", _buy.bind("probe", 5), Game.credits >= Game.PROBE_PRICE * 5]])
			for o in Game.ORE_ORDER.slice(0, 2 + cat * 2):
				var p := Game.buy_price(o)
				_row("ore", Game.ORES[o].color, Game.ORES[o].name, "%d credits each." % p, null,
					[["Buy 10", _buy.bind(o, 10), Game.credits >= p * 10], ["Buy 50", _buy.bind(o, 50), Game.credits >= p * 50]],
					Game.ORES[o].color)
		"ships":
			_buy_note()
			var tier := -1
			for id in Game.SHIP_ORDER:
				if id == "wren":
					continue
				var s: Dictionary = Game.SHIPS[id]
				if s.tier != tier:
					tier = s.tier
					_section("TIER %d" % tier, "ship")
				_buy_row("ship", id, "ship", s.colors[1], "%s  (%s)" % [s.name, s["class"]],
					"%s\n%s" % [s.desc, _ship_line(s)], Game.owned_ships.has(id), Color("9fd3ff"))
		"weapons":
			_buy_note()
			_weapon_bar()
			for id in Game.WEAPON_ORDER:
				var w: Dictionary = Game.WEAPONS[id]
				if w.base != weapon_base or id == Game.BLASTER:
					continue
				_buy_row("weapon", id, "weapon", w.color, "%s   (have %d)" % [w.name, Game.weapon_count(id)],
					"%s\n%s\nOne purchase arms one gun slot." % [w.desc, _weapon_line(w)], false, w.color)
		"modules":
			_buy_note()
			_module_bar()
			for id in Game.MODULE_ORDER:
				var m: Dictionary = Game.MODULES[id]
				if module_cat != "" and m.cat != module_cat:
					continue
				var have: int = Game.module_stock.get(id, 0) + Game.modules_equipped.count(id)
				var col := Game.module_color(id)
				_buy_row("module", id, Game.module_icon(id), col, "%s   (have %d)" % [m.name, have],
					"[color=%s]%s[/color]   %s" % [UI.hex(col), Game.MODULE_CATS[m.cat].name.to_upper(), m.desc], false,
					col.lerp(UI.TEXT, 0.35))


func _buy_note() -> void:
	_note("Don't want to gather the materials? Buy it ready-made instead. It costs a lot more than building it in the Fabricator, which only ever needs materials.   You have [color=#ffd24a]%d credits[/color]." % Game.credits)


## A market listing: credit price, plus what it would cost to build yourself for comparison.
func _buy_row(kind: String, id: String, icon: String, icon_color: Color, title: String, desc: String, owned: bool, title_color: Color) -> void:
	var price := Game.market_price(kind, id)
	var c := UI.card(icon, icon_color, title, desc, title_color)
	if not owned:
		var afford := Game.credits >= price
		c.text.add_child(UI.rich("[color=#ffd24a]%d credits[/color]   [color=%s]or build it from: %s[/color]" % [price,
			UI.hex(UI.MUTED), UI.cost_text(Game.build_cost(kind, id))], 760.0))
		var btn := UI.btn("Buy", _buy_ready.bind(kind, id, title), "credits", UI.GOLD)
		btn.disabled = not afford
		btn.custom_minimum_size = Vector2(150, 46)
		btn.size_flags_vertical = SIZE_SHRINK_CENTER
		c.box.add_child(btn)
	else:
		var btn := UI.btn("Owned", func(): pass)
		btn.disabled = true
		btn.custom_minimum_size = Vector2(150, 46)
		btn.size_flags_vertical = SIZE_SHRINK_CENTER
		c.box.add_child(btn)
	_content.add_child(c.root)


func _sell_all(cat: int) -> void:
	for o in Game.ORE_ORDER:
		if Game.have(o) > 0:
			Game.sell(o, Game.have(o), cat)


func _sell_portal() -> void:
	Game.sell_portal()


## A line of the ship's numbers.
func _ship_line(s: Dictionary) -> String:
	var t := "Hull %d   Shield %d   Speed %d   Turn %.1f   Cargo %d   Gun slots %d   Module slots %d" % [s.hull, s.shield, s.speed,
		s.turn, s.cargo, s.guns, s.modules]
	if s.get("jump", 0) > 0:
		t += "   [color=#c080ff]Jump drive %d[/color]" % s.jump
	if s.get("refinery", false):
		t += "   [color=#ff9a3d]Refinery-capable[/color]"
	return t


## Buttons to pick which weapon's marks to list (one per weapon, in its colour).
func _weapon_bar() -> void:
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 6)
	for id in Game.WEAPON_BASE_ORDER:
		var w: Dictionary = Game.WEAPON_BASE[id]
		var b := UI.btn(w.name, _pick_base.bind(id), "weapon", w.color)
		b.toggle_mode = true
		b.button_pressed = id == weapon_base
		bar.add_child(b)
	_content.add_child(bar)


## Buttons to narrow the module lists to one kind (each in its kind's colour and icon).
func _module_bar() -> void:
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 6)
	var all := UI.btn("All", _pick_cat.bind(""), "module")
	all.toggle_mode = true
	all.button_pressed = module_cat == ""
	bar.add_child(all)
	for c in Game.MODULE_CATS:
		var mc: Dictionary = Game.MODULE_CATS[c]
		var b := UI.btn(mc.name, _pick_cat.bind(c), mc.icon, mc.color)
		b.toggle_mode = true
		b.button_pressed = module_cat == c
		bar.add_child(b)
	_content.add_child(bar)


func _pick_base(id: String) -> void:
	weapon_base = id
	_rebuild()


func _pick_cat(c: String) -> void:
	module_cat = c
	_rebuild()


func _pin_btn(kind: String, id: String) -> Array:
	return ["Unpin" if Game.is_pinned(kind, id) else "Pin", Game.toggle_pin.bind(kind, id), true]


func _buy_ready(kind: String, id: String, label: String) -> void:
	if Game.buy_ready_made(kind, id):
		Sfx.play("refine", -4.0)
		Game.say("Bought %s." % label.split("  (")[0], UI.GOLD)

func _buy(id: String, n: int) -> void:
	if Game.buy(id, n):
		Sfx.play("pickup", -6.0)


# ---------------------------------------------------------------- fabricator

func _build_fabricator() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	for t in FAB_TABS:
		bar.add_child(_tab_button(t, fab_tab, _set_fab_tab))
	_content.add_child(bar)
	match fab_tab:
		"ships":
			_note("Over fifty ships in ten tiers. From tier 3 on they need ores from the regions further out (the Guide, H, says where).")
			var tier := -1
			for id in Game.SHIP_ORDER:
				if id == "wren":
					continue
				var s: Dictionary = Game.SHIPS[id]
				if s.tier != tier:
					tier = s.tier
					_section("TIER %d%s" % [tier, "  -  CAPITAL SHIPS (too big for docking bays: they tether, and jump)" if tier == 9 else ""], "ship")
				var owned: bool = Game.owned_ships.has(id)
				_row("ship", s.colors[1], "%s  (%s)" % [s.name, s["class"]], "%s\n%s" % [s.desc, _ship_line(s)],
					null if owned else Game.build_cost("ship", id),
					[["Owned" if owned else "Build", _do_build.bind("ship", id, s.name, 1), not owned and Game.can_afford(Game.build_cost("ship", id))],
					_pin_btn("ship", id)], Color("9fd3ff"))
		"weapons":
			_weapon_bar()
			for id in Game.WEAPON_ORDER:
				var w: Dictionary = Game.WEAPONS[id]
				if w.base != weapon_base or id == Game.BLASTER:
					continue
				_row("weapon", w.color, "%s   (have %d)" % [w.name, Game.weapon_count(id)],
					"%s\n%s\nOne build arms one gun slot." % [w.desc, _weapon_line(w)], Game.build_cost("weapon", id),
					[["Build", _do_build.bind("weapon", id, w.name, 1), Game.can_afford(Game.build_cost("weapon", id))],
					_pin_btn("weapon", id)], w.color)
		"modules":
			_module_bar()
			for id in Game.MODULE_ORDER:
				var m: Dictionary = Game.MODULES[id]
				if module_cat != "" and m.cat != module_cat:
					continue
				var have: int = Game.module_stock.get(id, 0) + Game.modules_equipped.count(id)
				var col := Game.module_color(id)
				_row(Game.module_icon(id), col, "%s   (have %d)" % [m.name, have],
					"[color=%s]%s[/color]   %s" % [UI.hex(col), Game.MODULE_CATS[m.cat].name.to_upper(), m.desc], Game.build_cost("module", id),
					[["Build", _do_build.bind("module", id, m.name, 1), Game.can_afford(Game.build_cost("module", id))],
					_pin_btn("module", id)], col.lerp(UI.TEXT, 0.35))
		"supplies":
			var five := {}
			for k in Game.PROBE_COST:
				five[k] = Game.PROBE_COST[k] * 5
			_row("probe", Color("9fd3ff"), "Probe", "Launch from the system map (N). Scans planets and hunts anomalies.",
				Game.PROBE_COST, [["Build 1", _do_build.bind("probe", "", "a probe", 1), Game.can_afford(Game.PROBE_COST)],
				["Build 5", _do_build.bind("probe", "", "probes", 5), Game.can_afford(five)]], Color("9fd3ff"))


func _weapon_line(w: Dictionary) -> String:
	var t := "Damage %.0f   %.1f/s   Mining %.1f" % [w.damage, w.rate, w.mining]
	if w.get("pellets", 1) > 1:
		t += "   %d pellets" % w.pellets
	if w.get("pierce", 0) > 0:
		t += "   Pierces %d" % w.pierce
	if w.get("homing", 0.0) > 0.0:
		t += "   Homing"
	if w.get("slow", 0.0) > 0.0:
		t += "   Freezes"
	return t


func _do_build(kind: String, id: String, label: String, times: int) -> void:
	var built := 0
	for i in times:
		if Game.build(kind, id):
			built += 1
	if built > 0:
		Sfx.play("refine", -4.0)
		Game.say("Built %s%s." % [label, "" if built == 1 else " x%d" % built], UI.GOOD)


# ---------------------------------------------------------------- hangar

func _build_hangar() -> void:
	var st := Game.stats_ship()
	var cur: Dictionary = Game.SHIPS[Game.ship_id]
	_section("CURRENT SHIP", "ship")
	_row("ship", cur.colors[1], "%s  (%s)" % [cur.name, cur["class"]],
		"Hull %d   Shield %d   Speed %d   Turn %.1f   Cargo %d   Energy %d   Gun slots %d   Modules %d / %d" % [st.hull,
		st.shield, st.speed, st.turn, st.cargo, st.energy, st.guns, Game.modules_equipped.size(), st.slots], null, [], Color("9fd3ff"))

	_section("GUN SLOTS  (%d)" % st.guns, "weapon")
	_note("Each slot is one gun pod. Empty slots use the free Blaster. Weapons you build or buy go into storage until you mount them here.")
	var lo := Game.loadout()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	for i in lo.size():
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", UI.frame("card", 10))
		cell.size_flags_horizontal = SIZE_EXPAND_FILL
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		cell.add_child(h)
		var w: Dictionary = Game.WEAPONS[lo[i]]
		h.add_child(UI.icon_rect("weapon", w.color, 3))
		var label := UI.lbl("%s %d" % ["Left" if i % 2 == 0 else "Right", (i >> 1) + 1], 17, UI.MUTED)
		label.custom_minimum_size = Vector2(76, 0)
		h.add_child(label)
		var pick := OptionButton.new()
		pick.focus_mode = FOCUS_NONE
		pick.size_flags_horizontal = SIZE_EXPAND_FILL
		pick.add_theme_font_override("font", UI.bold)
		var ids := []
		for id in Game.WEAPON_ORDER:
			var spare: int = Game.weapon_stock.get(id, 0)
			if id == Game.BLASTER or id == lo[i] or spare > 0:
				var extra := "" if id == Game.BLASTER or id == lo[i] else "  (%d spare)" % spare
				pick.add_item(Game.WEAPONS[id].name + extra)
				ids.append(id)
		pick.selected = ids.find(lo[i])
		pick.item_selected.connect(_pick_weapon.bind(i, ids))
		h.add_child(pick)
		grid.add_child(cell)
	_content.add_child(grid)
	var fills := []
	for id in Game.WEAPON_ORDER:
		if id != Game.BLASTER and Game.weapon_stock.get(id, 0) > 0:
			fills.append(id)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	var reset := UI.btn("All Blasters", Game.mount_all.bind(Game.BLASTER), "weapon")
	reset.custom_minimum_size = Vector2(0, 44)
	bar.add_child(reset)
	for id in fills.slice(0, 4):
		var b := UI.btn("Fill with %s" % Game.WEAPONS[id].name, Game.mount_all.bind(id), "weapon", Game.WEAPONS[id].color)
		b.custom_minimum_size = Vector2(0, 44)
		bar.add_child(b)
	_content.add_child(bar)

	_section("YOUR SHIPS", "ship")
	for id in Game.owned_ships:
		var s: Dictionary = Game.SHIPS[id]
		var here: bool = id == Game.ship_id
		_row("ship", s.colors[1], "%s  (%s)   %d gun slots" % [s.name, s["class"], s.guns], s.desc, null,
			[["Flying" if here else "Board", Game.board_ship.bind(id), not here]], Color("9fd3ff"))
	_section("MODULES  (%d / %d slots)" % [Game.modules_equipped.size(), st.slots], "module")
	for i in Game.modules_equipped.size():
		var mid: String = Game.modules_equipped[i]
		var m: Dictionary = Game.MODULES[mid]
		_row(Game.module_icon(mid), Game.module_color(mid), m.name + "   [installed]", m.desc, null,
			[["Remove", Game.unequip_module.bind(i), true]], Game.module_color(mid).lerp(UI.TEXT, 0.35))
	for id in Game.MODULE_ORDER:
		var n: int = Game.module_stock.get(id, 0)
		if n > 0:
			var m: Dictionary = Game.MODULES[id]
			_row(Game.module_icon(id), Game.module_color(id), "%s  x%d" % [m.name, n], m.desc, null,
				[["Install", Game.equip_module.bind(id), Game.modules_equipped.size() < st.slots and Game.module_fits(id)]],
				Game.module_color(id).lerp(UI.TEXT, 0.35))
	if Game.modules_equipped.is_empty() and Game.module_stock.values().all(func(v): return v <= 0):
		_note("No modules yet. Build some in the Fabricator, or find them in wrecks.")


func _pick_weapon(index: int, slot: int, ids: Array) -> void:
	Game.mount(slot, ids[index])

# ---------------------------------------------------------------- missions

func _build_missions() -> void:
	_section("ACTIVE MISSIONS  (%d / %d)" % [Game.missions.size(), Game.MAX_MISSIONS], "mission")
	if Game.missions.is_empty():
		_note("No active missions. Take one from the board below.")
	for i in Game.missions.size():
		var m: Dictionary = Game.missions[i]
		var buttons := []
		if m.type == "deliver":
			buttons.append(["Turn in", Game.turn_in.bind(i), Game.have(m.ore) >= m.need])
		if m.sys >= 0:
			buttons.append(["Route", _route_to.bind(m.sys), m.sys != Game.current_system])
		buttons.append(["Abandon", Game.abandon_mission.bind(i), true])
		_row("mission", UI.GOOD, m.title, "%s\nProgress %s   Reward [color=#ffd24a]%d credits[/color]" % [m.desc,
			_progress(m), m.reward], null, buttons, UI.GOOD)
	_section("MISSION BOARD", "mission")
	var board := Game.board(Game.current_system, loc_index)
	for i in board.size():
		var m: Dictionary = board[i]
		_row(_mission_icon(m.type), UI.HEAD, m.title, "%s\nReward [color=#ffd24a]%d credits[/color]" % [m.desc, m.reward], null,
			[["Accept", Game.accept_mission.bind(Game.current_system, loc_index, i), Game.missions.size() < Game.MAX_MISSIONS]])


func _progress(m: Dictionary) -> String:
	if m.type == "deliver":
		return "%d / %d %s in storage" % [mini(Game.have(m.ore), m.need), m.need, Game.ORES[m.ore].name]
	return "%d / %d" % [m.have, m.need]


func _mission_icon(type: String) -> String:
	return {"bounty": "skull", "explore": "gate", "survey": "probe", "deliver": "cargo", "anomaly": "anomaly"}.get(type, "mission")


func _route_to(sys_id: int) -> void:
	Game.route_target = sys_id
	Game.say("Route set to %s." % Game.systems[sys_id].name, UI.GOLD)


# ---------------------------------------------------------------- spice stand / obelisk

func _build_spice(sys: Dictionary) -> void:
	_title.text = "SPICE STAND"
	_sub.text = "A little floating market at %s. Spices can be offered at obelisks or used to build rare gear." % loc.name
	_section("FOR SALE", "spice")
	for id in Game.spice_stock(loc, sys):
		var sp: Dictionary = Game.SPICES[id]
		_row("spice", sp.color, "%s   (you have %d)" % [sp.name, Game.have(id)], sp.desc, sp.price,
			[["Buy", _buy_spice.bind(id), Game.can_afford(sp.price)]], sp.color)


func _buy_spice(id: String) -> void:
	if Game.buy_spice(id):
		Game.say("Bought %s." % Game.SPICES[id].name, Game.SPICES[id].color)


func _build_obelisk(sys: Dictionary) -> void:
	_title.text = "OFFERING OBELISK"
	_sub.text = "It hums softly in the dark. Offer a spice and something may answer."
	_section("OFFER A SPICE", "obelisk")
	_note("Rarer spices bring longer blessings and bigger gifts. The obelisk might grant Plenty (double ore), Aegis (+50% shield), Swiftness (+20% speed), Fury (+30% damage), a gift of materials, or reveal this system's secrets.")
	if _result != "":
		_note(_result, Color("e080ff"))
	var any := false
	for id in Game.SPICE_ORDER:
		var n := Game.have(id)
		if n <= 0:
			continue
		any = true
		var sp: Dictionary = Game.SPICES[id]
		_row("spice", sp.color, "%s  x%d" % [sp.name, n], sp.desc, null, [["Offer", _offer.bind(id, sys), true]], sp.color)
	if not any:
		_note("You have no spices to offer. Spice stands sell them.", UI.BAD)


func _offer(id: String, sys: Dictionary) -> void:
	_result = Game.make_offering(id, sys)
	Sfx.play("found")
	Game.say(_result, Color("e080ff"))
	_rebuild()

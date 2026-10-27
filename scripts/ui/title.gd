extends Control
## Title screen: the logo over the live station, with Continue / New Game / Guide / Quit, and a choice of save:
## your pilot, or the Sandbox (everything free, anyone can play it).

const UI = preload("res://scripts/ui/ui.gd")
const LOGO = preload("res://icon.svg")
const CONTROLS := """[font_size=20][color=#ffe7a3][b]CONTROLS[/b][/color][/font_size]

[color=#9fd3ff]Flying[/color]   Your ship is heavy: it takes a few seconds to build up speed and to slow down again, and turns carry momentum.  W / S pitch the nose: W dips it and S lifts it, like a flight stick (swap them in the ESC menu; the Up / Down arrows also lift and dip it).  Q / E turn, A / D roll.  R / F raise and lower the throttle.  Hold X to brake.  Hold SHIFT to boost while you have energy.  The mouse swings the camera round your ship without steering it, the mouse wheel zooms it in and out, and a middle-click puts it back behind you.
[color=#9fd3ff]Shooting and mining[/color]   Your guns are turrets that swivel toward whatever the crosshair is on; click to fire. A turret only fires with a clear shot: the pips under the crosshair show which are ready. Mining Lasers fire a steady beam: click a rock and they lock on and keep cutting ore straight into your hold; click again to stop. V sends out a survey pulse that shows what ore is in the rocks around you. Your tractor beam pulls in loose ore near the ship, and O flies you round collecting every loose piece in reach.
[color=#9fd3ff]Getting around[/color]   The overview (top right) lists everything nearby: right-click whatever's under the crosshair to select it, or press C to free the cursor and click a row (C or ESC gives the mouse back). Then 1 approaches it, 2 orbits it, 3 warps to it, 5 cruises there and G uses it. While the autopilot flies, R / F set how hard it pushes, and steering or X takes the controls back. Hold SPACE for the quick warp menu. M opens the galaxy map: click a system to plot a route, shift-click to add stops, right-click to clear it, then press T and the autopilot flies the whole route - warps, stargates and all. N opens the system map, where probes scan planets and hunt anomalies. X or ESC cancels a warp while it charges.
[color=#9fd3ff]Docking[/color]   Fly into a station's docking bay and onto the pad, or press G near it and the autopilot lines up and takes you in. Docked, the maps and your inventory open over the station, and station storage keeps your things safe. Undocking fires you out of the bay. Stargates are railguns: fly into the mouth (or press G near one) and the gate fires you to the next system.
[color=#9fd3ff]Menus[/color]   I or TAB inventory (cargo, ship, missions, notebook, guide, stats and awards), L ship fitting, H the guide, F1 photo mode (T pauses or resumes time in it), F3 flight data, F11 fullscreen, ESC pause and settings. In the Sandbox, F8 opens the sandbox tools. The game saves itself."""

var main
var _buttons: VBoxContainer
var _continue: Button
var _slots: HBoxContainer  # pilot / sandbox save picker
var _slot_btns := {}
var _gated := []  # the buttons that join a game: off while an update is downloading or installing
var _save_code: Button  # (shown when there's a save to make a code from)
var _help: PanelContainer
var _help_text: RichTextLabel
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.offset_top = 330
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	center.add_child(_buttons)
	_slots = HBoxContainer.new()
	_slots.add_theme_constant_override("separation", 10)
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	for s in ["pilot", "sandbox"]:
		var b := UI.btn("Pilot" if s == "pilot" else "Sandbox", _pick_slot.bind(s))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(165, 40)
		b.tooltip_text = "Your career" if s == "pilot" else "Everything free, every tool - its own save, separate from your pilot"
		_slots.add_child(b)
		_slot_btns[s] = b
		_gated.append(b)
	_buttons.add_child(_slots)
	_continue = _menu_button("Continue", func(): main.continue_game(), "gate")
	_gated.append(_continue)
	_gated.append(_menu_button("New Game", _new_game, "ship"))
	_menu_button("Guide", _show_help.bind(UI.GUIDE), "star")
	_menu_button("Controls", _show_help.bind(CONTROLS), "mission")
	_save_code = _menu_button("Save Code", func(): main.code_panel.open_export(), "cargo")
	_gated.append(_menu_button("Load Code", func(): main.code_panel.open_import(_after_code), "cargo"))
	_menu_button("Quit", func(): get_tree().quit(), "skull")

	var hc := CenterContainer.new()
	hc.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	hc.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(hc)
	_help = PanelContainer.new()
	_help.visible = false
	_help.custom_minimum_size = Vector2(1100, 0)
	hc.add_child(_help)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 14)
	_help.add_child(hv)
	_help_text = UI.rich("", 1060.0)
	_help_text.add_theme_font_size_override("normal_font_size", 19)
	hv.add_child(_help_text)
	var close := UI.btn("Got it", func(): _help.hide())
	close.custom_minimum_size = Vector2(200, 48)
	close.size_flags_horizontal = SIZE_SHRINK_CENTER
	hv.add_child(close)


func _menu_button(text: String, cb: Callable, _icon: String) -> Button:
	var b := UI.btn(text, cb)
	b.custom_minimum_size = Vector2(340, 50)
	b.add_theme_font_size_override("font_size", 22)
	_buttons.add_child(b)
	return b


func _show_help(text: String) -> void:
	if _help.visible and _help_text.text == text:
		_help.hide()
		return
	_help_text.text = text
	_help.show()
	UI.pop_in(_help)


func open() -> void:
	Game.migrate_saves()  # (v4 started everyone over: older saves are set aside)
	_pick_slot(Game.save_slot)
	_help.hide()
	show()
	main.updater.check()  # (every time you come back to the title: is there a newer version?)


## Pick the pilot or sandbox save: Continue and New Game then act on that slot.
func _pick_slot(s: String) -> void:
	Game.use_slot(s)
	for k in _slot_btns:
		_slot_btns[k].set_pressed_no_signal(k == Game.save_slot)
	_continue.visible = Game.has_save()
	_save_code.visible = _continue.visible


## A save code was loaded: Continue (and Save Code) show up if they hadn't.
func _after_code() -> void:
	Game.migrate_saves()
	_continue.visible = Game.has_save()
	_save_code.visible = _continue.visible


func _new_game() -> void:
	if Game.has_save():
		main.ask("Start a new game?\n\nYour current save (ship, materials, credits and discoveries) will be overwritten.",
			"Start over", main.start_new_game)
	else:
		main.start_new_game()


func _process(delta: float) -> void:
	_t += delta
	var updating: bool = main.updater.blocking()
	for b in _gated:
		b.disabled = updating
	queue_redraw()


func _draw() -> void:
	var vs := size
	# a faint darkening so the name reads over the station
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.0, 0.0, 0.25))
	var y := vs.y * 0.3
	var glow := 0.85 + 0.15 * sin(_t * 0.8)
	var ls := 132.0
	draw_texture_rect(LOGO, Rect2(Vector2(vs.x / 2.0 - ls / 2.0, y - 80.0 - ls), Vector2(ls, ls)), false, Color(1, 1, 1, 0.95))
	draw_string(UI.title, Vector2(0, y), "D R I F T L I G H T", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 72, Color(0.88, 0.92, 0.96, glow))
	# a streak of light drifting across under the name
	var sx := fposmod(_t * 0.12, 1.4) - 0.2
	draw_line(Vector2(vs.x / 2.0 - 260.0, y + 26.0), Vector2(vs.x / 2.0 + 260.0, y + 26.0), UI.LINE, 1.0)
	var hx := vs.x / 2.0 - 260.0 + 520.0 * clampf(sx, 0.0, 1.0)
	draw_line(Vector2(maxf(vs.x / 2.0 - 260.0, hx - 60.0), y + 26.0), Vector2(hx, y + 26.0), Color(0.6, 0.95, 1.0, 0.6), 2.0)
	draw_string(UI.body, Vector2(0, y + 60), "mine   -   explore   -   survive the Wild", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 22, UI.MUTED)
	if Game.sandbox:
		draw_string(UI.body, Vector2(0, y + 92), "SANDBOX   -   everything free, jump anywhere, god mode, spawn tools (F8)", HORIZONTAL_ALIGNMENT_CENTER,
			vs.x, 18, UI.GOLD)
	elif Game.reset_note:
		draw_string(UI.body, Vector2(0, y + 92), "Version 8 started everyone over - your old save was kept in the backups folder.",
			HORIZONTAL_ALIGNMENT_CENTER, vs.x, 17, UI.GOLD)
	var upd: String = main.updater.status
	if main.updater.blocking():
		# an update is coming in: nobody joins a game until it's installed (the game restarts by itself)
		var bw := 560.0
		var by := vs.y * 0.3 + 128.0
		var frac: float = main.updater.progress if main.updater.state == "downloading" else 1.0
		draw_string(UI.title, Vector2(0, by), "UPDATING TO v%d" % main.updater.version, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 22, UI.GOLD)
		draw_rect(Rect2((vs.x - bw) / 2.0, by + 14.0, bw, 4.0), Color(1, 1, 1, 0.12))
		draw_rect(Rect2((vs.x - bw) / 2.0, by + 14.0, bw * frac, 4.0), UI.GOLD)
		draw_string(UI.body, Vector2(0, by + 44.0), upd if upd != "" else "installing...", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 17, Color(UI.TEXT, 0.85))
		draw_string(UI.body, Vector2(0, by + 68.0), "Driftlight restarts by itself when it's done.", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 15, UI.MUTED)
	draw_string(UI.body, Vector2(30, vs.y - 26), "v%d" % Game.VERSION + ("   -   " + upd if upd != "" else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(UI.MUTED, 0.6))
	var foot := "1,000 systems in 10 regions  -  %d ships  -  %d weapons  -  %d modules  -  %d achievements" % [Game.SHIPS.size(),
		Game.WEAPONS.size(), Game.MODULES.size(), Game.ACHIEVEMENTS.size()]
	draw_string(UI.body, Vector2(0, vs.y - 50), foot, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 16, Color(UI.MUTED, 0.7))
	draw_string(UI.body, Vector2(0, vs.y - 26), "Font: Barlow Semi Condensed (SIL Open Font License)",
		HORIZONTAL_ALIGNMENT_CENTER, vs.x, 13, Color(UI.MUTED, 0.45))

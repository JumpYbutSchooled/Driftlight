extends Control
## Title screen: animated logo over the live starfield, with Continue / New Game / How to Play / Quit.

const UI = preload("res://scripts/ui/ui.gd")
const HELP := """[font_size=20][color=#ffe7a3][b]HOW TO PLAY[/b][/color][/font_size]

[color=#9fd3ff]Flying[/color]   The keys fly the ship: A / D turn, R / F pitch the nose up and down, Q / E roll.  W / S raise and lower the throttle (it stays where you leave it, and stops at 0 before reverse).  Hold X to brake.  SHIFT boosts while you have energy.  The mouse swings the camera round your ship without steering it; middle-click puts it back behind you.  Prefer holding W to thrust? Switch it in the ESC menu.
[color=#9fd3ff]Shooting[/color]   Your guns are turrets that swivel on their own toward whatever the crosshair in the middle of the screen is on; click to fire. Each turret can only fire once it's pointing at the target with a clear shot: the pips under the crosshair show which are ready, and one whose shot would pass through your own hull stays quiet, so turn the ship to bring more turrets to bear.
[color=#9fd3ff]Space is big[/color]   Things at one place are kilometres apart. The OVERVIEW (top right) lists everything nearby: press C to free the cursor and click a row to select it, or right-click whatever's under the crosshair (holding ALT frees the cursor for a moment too). Then 1 approaches it, 2 orbits it, 3 warps you across to it and G docks / jumps / uses it. Mouse wheel zooms the camera right out.
[color=#9fd3ff]Mining[/color]   Ore fields are full of huge veins. Press V to survey them and see what's inside. Shoot a vein and chunks of ore break off the side you hit; they stay where they stop, so fly into them to collect them. Rarer ores are harder to break. Load ore into a station furnace; it smelts piece by piece over time, even while you're away.
[color=#9fd3ff]Travel[/color]   Hold SPACE for the quick warp menu, move the mouse up/down to pick a destination and let go of SPACE to warp (or pick Cancel). Your ship turns to face it, charges the drive, then flies the warp tunnel. ESC or X cancels until the jump starts. F11 toggles fullscreen. Stargates lead to other systems. M opens the galaxy map (click a system to plot a route). N opens the system map, where you launch probes to scan planets and hunt anomalies.
[color=#9fd3ff]Danger[/color]   [color=#4aa8ff]Core[/color] systems are safe. [color=#4cd964]Secure[/color] ones have a few pirates. [color=#ff5050]Unsecure[/color] ones have no stations. [color=#b366ff]Wild[/color] space - the biggest part of the galaxy - is crawling with pirates, but hides anomalies full of Pristine ore and wormholes.
[color=#9fd3ff]Photo mode[/color]   F1 hides the interface and freezes everything so you can fly a free camera around (WASD, mouse, E/Q up and down, SHIFT fast, wheel zoom). P saves a picture to your screenshots folder.
[color=#9fd3ff]Everything else[/color]   G interacts (dock, salvage wrecks, spice stands, obelisks). I opens your inventory. ESC pauses. The game saves itself."""

var main
var _buttons: VBoxContainer
var _continue: Button
var _slots: HBoxContainer  # pilot / admin save picker (only on the admin device)
var _slot_btns := {}
var _restart: Button
var _help: PanelContainer
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.offset_top = 300
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	center.add_child(_buttons)
	_slots = HBoxContainer.new()
	_slots.add_theme_constant_override("separation", 10)
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	for s in ["pilot", "admin"]:
		var b := UI.btn("Pilot save" if s == "pilot" else "Admin save", _pick_slot.bind(s))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(165, 40)
		_slots.add_child(b)
		_slot_btns[s] = b
	_buttons.add_child(_slots)
	_restart = _menu_button("Restart to update", func(): main.updater.restart(), "")
	_restart.visible = false
	_continue = _menu_button("Continue", func(): main.continue_game(), "gate")
	_menu_button("New Game", _new_game, "ship")
	_menu_button("How to Play", func(): _help.visible = not _help.visible, "mission")
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
	var r := UI.rich(HELP, 1060.0)
	r.add_theme_font_size_override("normal_font_size", 19)
	hv.add_child(r)
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


func open() -> void:
	_slots.visible = Game.admin_allowed()
	_pick_slot(Game.save_slot)
	_help.hide()
	show()


## Pick the pilot or admin save: Continue and New Game then act on that slot.
func _pick_slot(s: String) -> void:
	Game.use_slot(s)
	for k in _slot_btns:
		_slot_btns[k].set_pressed_no_signal(k == Game.save_slot)
	_continue.visible = Game.has_save()


func _new_game() -> void:
	if Game.has_save():
		main.ask("Start a new game?\n\nYour current save (ship, materials, credits and discoveries) will be overwritten.",
			"Start over", main.start_new_game)
	else:
		main.start_new_game()


func _process(delta: float) -> void:
	_t += delta
	_restart.visible = main.updater.ready_version > 0
	queue_redraw()


func _draw() -> void:
	var vs := size
	# a faint darkening so the name reads over the station
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.0, 0.0, 0.25))
	var logo := "D R I F T L I G H T"
	var y := vs.y * 0.3
	var glow := 0.85 + 0.15 * sin(_t * 0.8)
	draw_string(UI.title, Vector2(0, y), logo, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 72, Color(0.88, 0.92, 0.96, glow))
	draw_line(Vector2(vs.x / 2.0 - 260.0, y + 26.0), Vector2(vs.x / 2.0 + 260.0, y + 26.0), UI.LINE, 1.0)
	draw_string(UI.body, Vector2(0, y + 60), "mine   -   explore   -   survive the Wild", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 22, UI.MUTED)
	if Game.admin:
		draw_string(UI.body, Vector2(0, y + 92), "ADMIN SAVE   -   everything free, jump anywhere, god mode (F8)", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 18, UI.GOLD)
	var upd: String = main.updater.status
	draw_string(UI.body, Vector2(30, vs.y - 26), "v%d" % Game.VERSION + ("   -   " + upd if upd != "" else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(UI.MUTED, 0.6))
	var foot := "1,000 systems  -  13 ships  -  11 weapons  -  18 modules  -  %d achievements" % Game.ACHIEVEMENTS.size()
	draw_string(UI.body, Vector2(0, vs.y - 50), foot, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 16, Color(UI.MUTED, 0.7))
	draw_string(UI.body, Vector2(0, vs.y - 26), "Font: Barlow Semi Condensed (SIL Open Font License)",
		HORIZONTAL_ALIGNMENT_CENTER, vs.x, 13, Color(UI.MUTED, 0.45))

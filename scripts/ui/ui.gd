extends RefCounted
## Fonts, the minimal see-through theme, vector glyphs and small helpers for building UI in code.

const BODY_FONT := "res://fonts/BarlowSemiCondensed-Medium.ttf"
const BOLD_FONT := "res://fonts/BarlowSemiCondensed-SemiBold.ttf"
const TITLE_FONT := "res://fonts/BarlowSemiCondensed-Bold.ttf"
const TEXT := Color("dde4ec")
const MUTED := Color("8590a0")
const GOLD := Color("e8c66a")
const HEAD := Color("e9e2cc")
const GOOD := Color("8ee0a0")
const BAD := Color("ee7a6c")
const LINE := Color(0.75, 0.85, 0.95, 0.16)  # hairline rules and borders

static var body: Font
static var bold: Font
static var title: Font


## Load the fonts once and make them the default everywhere (including draw_string via ThemeDB). Titles
## use the bold weight with wide letter spacing.
static func setup_fonts() -> void:
	if body:
		return
	body = _smooth(load(BODY_FONT))
	bold = _smooth(load(BOLD_FONT))
	var t := FontVariation.new()
	t.base_font = _smooth(load(TITLE_FONT))
	t.spacing_glyph = 3
	title = t
	ThemeDB.fallback_font = body
	ThemeDB.fallback_font_size = 18


static func _smooth(f: FontFile) -> FontFile:
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.generate_mipmaps = true
	return f


## A minimal box: a faint see-through fill and a hairline border. kind: panel, card, inset, button, hover,
## pressed, disabled, danger, chip
static func frame(kind: String, pad := 12) -> StyleBoxFlat:
	var c: Array = {  # fill, border
		"panel": [Color(0.012, 0.016, 0.02, 0.62), LINE],
		"card": [Color(1, 1, 1, 0.035), Color(0.75, 0.85, 0.95, 0.08)],
		"inset": [Color(0, 0, 0, 0.35), Color(0.75, 0.85, 0.95, 0.06)],
		"button": [Color(1, 1, 1, 0.045), Color(0.75, 0.85, 0.95, 0.2)],
		"hover": [Color(1, 1, 1, 0.1), Color(0.8, 0.9, 1.0, 0.5)],
		"pressed": [Color(0.91, 0.78, 0.42, 0.14), Color(0.91, 0.78, 0.42, 0.7)],
		"disabled": [Color(1, 1, 1, 0.02), Color(0.75, 0.85, 0.95, 0.06)],
		"danger": [Color(0.3, 0.05, 0.04, 0.4), Color(0.93, 0.48, 0.42, 0.55)],
		"chip": [Color(0.0, 0.0, 0.0, 0.4), Color(0, 0, 0, 0)],
	}[kind]
	var s := StyleBoxFlat.new()
	s.bg_color = c[0]
	s.border_color = c[1]
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.anti_aliasing = true
	s.set_content_margin_all(pad)
	return s


## A small vector symbol for a kind of thing (overview, markers, radar): minimal, no pixel art.
static func glyph(ci: CanvasItem, kind: String, c: Vector2, r: float, color: Color) -> void:
	match kind:
		"station":
			ci.draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), color, false, 1.5)
			ci.draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), color)
		"gate":
			ci.draw_arc(c, r, 0.0, TAU, 20, color, 1.5, true)
			ci.draw_line(c - Vector2(0, r * 0.55), c + Vector2(0, r * 0.55), color, 1.5)
		"ore":
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
				c + Vector2(0, -r)]), color, 1.5, true)
		"ship", "npc":
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, r * 0.75), c + Vector2(-r * 0.8, r * 0.75),
				c + Vector2(0, -r)]), color, 1.5, true)
		"skull", "pirate":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, r), c + Vector2(r * 0.9, -r * 0.7), c + Vector2(-r * 0.9, -r * 0.7)]),
				color)
		"cargo":
			ci.draw_rect(Rect2(c - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), color)
		"wreck":
			ci.draw_line(c - Vector2(r, r) * 0.8, c + Vector2(r, r) * 0.8, color, 1.5)
			ci.draw_line(c + Vector2(r, -r) * 0.8, c + Vector2(-r, r) * 0.8, color, 1.5)
		"obelisk":
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -r * 1.2), c + Vector2(r * 0.45, 0), c + Vector2(0, r * 1.2),
				c + Vector2(-r * 0.45, 0), c + Vector2(0, -r * 1.2)]), color, 1.5, true)
		"anomaly":
			ci.draw_arc(c, r, 0.0, TAU, 20, color, 1.5, true)
			ci.draw_circle(c, r * 0.35, color)
		_:
			ci.draw_circle(c, r * 0.45, color)

static func make_theme() -> Theme:
	setup_fonts()
	var t := Theme.new()
	t.default_font = body
	t.default_font_size = 18
	t.set_stylebox("panel", "PanelContainer", frame("panel", 18))
	t.set_stylebox("panel", "Panel", frame("panel", 18))
	t.set_stylebox("normal", "Button", frame("button", 10))
	t.set_stylebox("hover", "Button", frame("hover", 10))
	t.set_stylebox("pressed", "Button", frame("pressed", 10))
	t.set_stylebox("hover_pressed", "Button", frame("pressed", 10))
	t.set_stylebox("disabled", "Button", frame("disabled", 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", bold)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_hover_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color("4a525e"))
	t.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_constant("h_separation", "Button", 10)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("bold_font", "RichTextLabel", bold)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TooltipPanel", frame("chip", 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	# chunky pixel sliders and scrollbars
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.75, 0.85, 0.95, 0.35)
	grab.set_content_margin_all(4)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.3)
	track.border_color = LINE
	track.set_border_width_all(1)
	track.set_content_margin_all(4)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", _flat(Color(0.75, 0.85, 0.95, 0.35)))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(Color(0.85, 0.92, 1.0, 0.6)))
	t.set_icon("grabber", "HSlider", Pix.icon("module", Color("8cb8ff"), 2))
	t.set_icon("grabber_highlight", "HSlider", Pix.icon("module", GOLD, 2))
	t.set_stylebox("background", "ProgressBar", frame("inset", 4))
	t.set_stylebox("fill", "ProgressBar", _flat(Color("ff9a3d")))
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", _flat(Color(0.85, 0.92, 1.0, 0.6)))
	t.set_stylebox("grabber_pressed", "VScrollBar", _flat(GOLD))
	return t


static func _flat(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_content_margin_all(4)
	return s


static func btn(text: String, cb: Callable, icon := "", icon_color := TEXT) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # so SPACE never presses a button
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if icon != "":
		b.icon = Pix.icon(icon, icon_color, 2)
	b.mouse_entered.connect(Sfx.play.bind("hover", -16.0, 1.0))
	b.pressed.connect(Sfx.play.bind("click", -10.0, 1.0))
	b.pressed.connect(cb)
	return b


static func lbl(text: String, size := 18, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A heading in the blocky title font.
static func heading(text: String, size := 16, color := HEAD) -> Label:
	var l := lbl(text, size, color)
	l.add_theme_font_override("font", title)
	return l


static func rich(text: String, width := 0.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	if width > 0.0:
		r.custom_minimum_size = Vector2(width, 0)
	return r


static func icon_rect(icon: String, color: Color, scale := 3) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Pix.icon(icon, color, scale)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


## A card row: icon, title, description lines, and an optional button on the right.
static func card(icon: String, icon_color: Color, title_text: String, body_text: String, title_color := TEXT) -> Dictionary:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", frame("card", 12))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	if icon != "":
		h.add_child(icon_rect(icon, icon_color, 4))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var tl := lbl(title_text, 20, title_color)
	tl.add_theme_font_override("font", bold)
	v.add_child(tl)
	if body_text != "":
		v.add_child(rich("[color=%s]%s[/color]" % [hex(MUTED), body_text], 560.0))
	return {"root": row, "box": h, "text": v}


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


## Colourful "Corrite 12/40" cost text.
static func cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "[color=%s]Free[/color]" % hex(GOOD)
	var parts := []
	for id in cost:
		var ok: bool = Game.have(id) >= cost[id]
		parts.append("[color=%s]%s[/color] [color=%s]%d/%d[/color]" % [hex(Game.item_color(id)), Game.item_name(id),
			hex(GOOD) if ok else hex(BAD), Game.have(id), cost[id]])
	return "   ".join(parts)


## A distance for the HUD: metres up close, kilometres further out.
static func dist(d: float) -> String:
	if d < 1000.0:
		return "%d m" % roundi(d)
	if d < 100000.0:
		return "%.1f km" % (d / 1000.0)
	return "%d km" % roundi(d / 1000.0)

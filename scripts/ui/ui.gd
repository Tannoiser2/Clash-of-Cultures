class_name UI
extends RefCounted
## Stile grafico di Clash of Cultures: pergamena, pietra scura e bronzo, oro antico e terracotta.
## Titoli in Cinzel (le maiuscole lapidarie romane delle carte), testo in Alegreya Sans.

const INK := Color("#2a1b10")
const INK2 := Color("#5f4329")
const PARCH := Color("#f1e3c4")
const LIGHT := Color("#f6ead0")
const GOLD := Color("#d8a84e")
const GOLD_DARK := Color("#9c7230")
const BRONZE := Color("#7a4f28")
const TERRA := Color("#a8442a")
const DARK := Color("#1b130d")
const OLIVE := Color("#6b7a3a")
const RED := Color("#b3261e")
const GREEN := Color("#3f7d3a")
const SEA := Color("#2a6f86")
const FOOD := Color("#7da23a")
const WOOD := Color("#a65a2f")
const ORE := Color("#8d8f94")
const IDEA := Color("#8a4fc7")
const GOLDC := Color("#e3b23c")
const MOODC := Color("#d8b83a")
const CULT := Color("#4d78c9")

static var _tex := {}
static var font_title: Font
static var font_deco: Font
static var font_body: Font
static var font_bold: Font
static var font_italic: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	font_title = load("res://assets/fonts/Cinzel-Bold.woff2")
	font_deco = load("res://assets/fonts/CinzelDecorative-Black.woff2")
	font_body = load("res://assets/fonts/AlegreyaSans-Medium.ttf")
	font_bold = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
	font_italic = load("res://assets/fonts/AlegreyaSans-BoldItalic.ttf")


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


static func res_color(r: String) -> Color:
	return {"food": FOOD, "wood": WOOD, "ore": ORE, "idea": IDEA, "gold": GOLDC, "mood": MOODC, "culture": CULT}.get(r, INK)


static func pcol(p: int) -> Color:
	if p == -2:
		return Color(0.09, 0.09, 0.1)    # pirati
	if p < 0:
		return CocData.BARB_COLOR
	return CocData.COLORS[p]["col"]


static func stone(alpha := 0.93, border := GOLD_DARK, bw := 2, radius := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.11, 0.08, 0.055, alpha)
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	s.set_content_margin_all(12)
	return s


static func paper(margin := 18.0, dark := false) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex("res://assets/ui/parchment_dark.jpg" if dark else "res://assets/ui/parchment.jpg")
	s.set_content_margin_all(margin)
	s.modulate_color = Color(1, 1, 1, 1)
	return s


static func flat(bg: Color, border: Color, bw := 1, radius := 6, margin := 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


static func label(text: String, size := 20, col := INK, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", font if font != null else font_body)
	return l


static func title(text: String, size := 34, col := GOLD) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func rich(size := 18, col := LIGHT) -> RichTextLabel:
	init_fonts()
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_override("normal_font", font_body)
	r.add_theme_font_override("bold_font", font_bold)
	r.add_theme_font_override("italics_font", font_italic)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_color_override("default_color", col)
	return r


static func button(text: String, w := 180.0, h := 46.0, size := 18) -> Button:
	init_fonts()
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_override("font", font_title)
	b.add_theme_font_size_override("font_size", size)
	_skin(b, Color("#5a3a1e"), Color("#7a5228"), GOLD_DARK)
	return b


static func _skin(b: Button, base: Color, hover: Color, border: Color) -> Button:
	var n := flat(base, border, 2, 6, 6)
	var hv := flat(hover, GOLD, 2, 6, 6)
	var pr := flat(base.darkened(0.25), GOLD, 2, 6, 6)
	var ds := flat(Color(0.2, 0.16, 0.12, 0.8), Color(0.35, 0.3, 0.25), 1, 6, 6)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("focus", hv)
	b.add_theme_stylebox_override("disabled", ds)
	b.add_theme_color_override("font_color", LIGHT)
	b.add_theme_color_override("font_hover_color", Color("#fff6dc"))
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.55, 0.48))
	return b


static func primary(b: Button) -> Button:
	return _skin(b, Color("#8d3a22"), Color("#b04d2c"), GOLD)


static func gold(b: Button) -> Button:
	b.add_theme_color_override("font_color", DARK)
	b.add_theme_color_override("font_hover_color", DARK)
	return _skin(b, Color("#c99a43"), Color("#e2b65a"), Color("#fff0c0"))


static func make_theme() -> Theme:
	init_fonts()
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 18
	t.set_color("font_color", "Label", LIGHT)
	t.set_stylebox("panel", "PanelContainer", stone())
	t.set_stylebox("panel", "TooltipPanel", flat(Color("#21170f"), GOLD, 1, 4, 8))
	t.set_color("font_color", "TooltipLabel", LIGHT)
	t.set_font_size("font_size", "TooltipLabel", 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.85, 0.66, 0.3, 0.6)
	sb.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0, 0, 0, 0.2)
	t.set_stylebox("scroll", "VScrollBar", sb2)
	var le := flat(Color("#f5e8cc"), GOLD_DARK, 2, 6, 8)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", flat(Color("#fff3da"), GOLD, 2, 6, 8))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK2)
	t.set_color("font_color", "CheckBox", LIGHT)
	t.set_color("font_hover_color", "CheckBox", GOLD)
	t.set_color("font_pressed_color", "CheckBox", LIGHT)
	return t


## Piccola pastiglia colorata con un numero (risorse).
static func chip(r: String, v, size := 17) -> PanelContainer:
	var pc := PanelContainer.new()
	var col := res_color(r)
	pc.add_theme_stylebox_override("panel", flat(col.darkened(0.45), col, 1, 10, 3))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	pc.add_child(hb)
	var ic := label(CocData.RES_ICON.get(r, "•"), size - 2, Color.WHITE)
	hb.add_child(ic)
	hb.add_child(label(str(v), size, Color.WHITE, font_bold))
	pc.tooltip_text = CocData.RES_NAME.get(r, r)
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	return pc


static func card_tex(id: String) -> Texture2D:
	return tex(CocData.card_image(id))

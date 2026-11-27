extends SceneTree
## Builds the UI theme of doc/design/visual-style.md section 5 and its fonts. The TTF sources in
## assets/fonts/ are hidden from the importer (.gdignore) and saved here as FontFile resources, so the
## project theme loads on a fresh checkout before anything is imported.
## Usage: godot --headless --path client/godot -s tools/build_theme.gd

const FONT_SOURCES := "res://assets/fonts/"
const FONT_OUTPUT := "res://theme/fonts/"
const THEME_PATH := "res://theme/main_theme.tres"

const Palette := preload("res://scripts/palette.gd")

var theme := Theme.new()
var regular: FontFile
var bold: FontFile
var bitter_bold: FontFile
var bitter_semibold: FontFile


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FONT_OUTPUT))
	regular = _build_font("AtkinsonHyperlegible-Regular", false)
	bold = _build_font("AtkinsonHyperlegible-Bold", false)
	# Board numerals are drawn at many sizes as the board scales, so the board font is MSDF.
	bitter_bold = _build_font("Bitter-Bold", true)
	bitter_semibold = _build_font("Bitter-SemiBold", false)
	theme.default_font = regular
	theme.default_font_size = 20
	_panels()
	_buttons()
	_inputs()
	_sliders()
	_labels()
	_variations()
	var error := ResourceSaver.save(theme, THEME_PATH)
	print("saved %s (%d)" % [THEME_PATH, error])
	quit(error)


func _build_font(font_name: String, distance_field: bool) -> FontFile:
	var font := FontFile.new()
	font.data = FileAccess.get_file_as_bytes(FONT_SOURCES + font_name + ".ttf")
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.hinting = TextServer.HINTING_LIGHT
	font.generate_mipmaps = false
	font.multichannel_signed_distance_field = distance_field
	var path := FONT_OUTPUT + font_name + ".res"
	var error := ResourceSaver.save(font, path, ResourceSaver.FLAG_COMPRESS)
	print("saved %s (%d)" % [path, error])
	# Loading back gives the theme a reference to the saved file instead of an embedded copy.
	return load(path) as FontFile


func _style_box(bg: Color, border: Color, border_width: int, radius: int, margins: Array, shadow_size := 0,
		shadow_offset := Vector2.ZERO, shadow_alpha := 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.corner_detail = 6
	style.anti_aliasing = true
	style.content_margin_left = margins[0]
	style.content_margin_top = margins[1]
	style.content_margin_right = margins[2]
	style.content_margin_bottom = margins[3]
	style.shadow_size = shadow_size
	style.shadow_offset = shadow_offset
	style.shadow_color = Color(Color.BLACK, shadow_alpha)
	return style


func _panels() -> void:
	var panel := _style_box(Palette.PARCHMENT, Palette.BORDER, 2, 10, [16, 14, 16, 14], 8, Vector2(0, 4), 0.35)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var popup := _style_box(Palette.PARCHMENT, Palette.BORDER, 2, 12, [20, 18, 20, 18], 16, Vector2(0, 8), 0.45)
	theme.set_stylebox("panel", "PopupPanel", popup)
	theme.set_stylebox("panel", "AcceptDialog", popup)
	theme.set_stylebox("panel", "PopupMenu", _style_box(Palette.PARCHMENT, Palette.BORDER, 2, 8, [6, 6, 6, 6], 8, Vector2(0, 4), 0.35))
	theme.set_stylebox("hover", "PopupMenu", _style_box(Palette.PARCHMENT_DEEP, Palette.PARCHMENT_DEEP, 0, 6, [8, 4, 8, 4]))
	for color_name in ["font_color", "font_hover_color", "font_accelerator_color"]:
		theme.set_color(color_name, "PopupMenu", Palette.INK)
	theme.set_color("font_disabled_color", "PopupMenu", Palette.DISABLED_TEXT)
	theme.set_stylebox("panel", "TooltipPanel", _style_box(Palette.INK, Palette.INK, 0, 6, [10, 6, 10, 6], 4, Vector2(0, 2), 0.4))
	theme.set_color("font_color", "TooltipLabel", Palette.CREAM)
	theme.set_font_size("font_size", "TooltipLabel", 16)
	theme.set_stylebox("panel", "ItemList", _style_box(Palette.CARD_STOCK, Palette.BORDER, 1, 8, [6, 6, 6, 6]))
	theme.set_stylebox("panel", "Tree", _style_box(Palette.CARD_STOCK, Palette.BORDER, 1, 8, [6, 6, 6, 6]))
	theme.set_stylebox("focus", "ItemList", _style_box(Palette.CLEAR, Palette.FOCUS_ON_LIGHT, 2, 8, [6, 6, 6, 6]))
	var selected := _style_box(Palette.PARCHMENT_DEEP, Palette.BORDER, 1, 6, [4, 2, 4, 2])
	theme.set_stylebox("selected", "ItemList", selected)
	theme.set_stylebox("selected_focus", "ItemList", selected)
	theme.set_stylebox("hovered", "ItemList", _style_box(Palette.PARCHMENT, Palette.PARCHMENT, 0, 6, [4, 2, 4, 2]))
	for color_name in ["font_color", "font_hovered_color", "font_selected_color"]:
		theme.set_color(color_name, "ItemList", Palette.INK)
	theme.set_color("guide_color", "ItemList", Palette.RULE_FAINT)
	theme.set_color("font_color", "Tree", Palette.INK)
	theme.set_stylebox("background", "ProgressBar", _style_box(Palette.DISABLED_FILL, Palette.DISABLED_FILL, 0, 6, [0, 0, 0, 0]))
	theme.set_stylebox("fill", "ProgressBar", _style_box(Palette.ACCENT, Palette.ACCENT, 0, 6, [0, 0, 0, 0]))
	theme.set_color("font_color", "ProgressBar", Palette.INK)
	for separator in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = Palette.RULE
		line.thickness = 1
		line.vertical = separator == "VSeparator"
		theme.set_stylebox("separator", separator, line)


func _button_states(type_name: String, normal: Color, hover: Color, pressed: Color, border: Color,
		hover_border: Color) -> void:
	var border_width := 0 if border.a == 0.0 else 1
	theme.set_stylebox("normal", type_name, _style_box(normal, border, border_width, 8, [16, 8, 16, 8], 2, Vector2(0, 2), 0.3))
	theme.set_stylebox("hover", type_name, _style_box(hover, hover_border, border_width, 8, [16, 8, 16, 8], 3, Vector2(0, 2), 0.3))
	# Pressed: no shadow and the content shifted one pixel down, as if pushed into the table.
	theme.set_stylebox("pressed", type_name, _style_box(pressed, hover_border, border_width, 8, [16, 9, 16, 7]))
	theme.set_stylebox("hover_pressed", type_name, _style_box(pressed, hover_border, border_width, 8, [16, 9, 16, 7]))


func _buttons() -> void:
	_button_states("Button", Palette.BUTTON, Palette.BUTTON_HOVER, Palette.BUTTON_PRESSED, Palette.BORDER, Palette.BUTTON_HOVER_BORDER)
	theme.set_stylebox("disabled", "Button", _style_box(Palette.DISABLED_FILL, Palette.DISABLED_BORDER, 1, 8, [16, 8, 16, 8]))
	var focus := _style_box(Palette.CLEAR, Palette.FOCUS_ON_LIGHT, 2, 10, [0, 0, 0, 0])
	focus.set_expand_margin_all(3)
	theme.set_stylebox("focus", "Button", focus)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(color_name, "Button", Palette.INK)
	theme.set_color("font_disabled_color", "Button", Palette.DISABLED_TEXT)
	theme.set_constant("h_separation", "Button", 8)
	theme.set_font("font", "Button", bold)
	# A check box is a Button subclass; it keeps a flat look instead of inheriting the button plate.
	var flat := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		theme.set_stylebox(state, "CheckBox", flat)
		theme.set_stylebox(state, "CheckButton", flat)


func _inputs() -> void:
	theme.set_stylebox("normal", "LineEdit", _style_box(Palette.CARD_STOCK, Palette.BORDER, 1, 6, [10, 6, 10, 6]))
	theme.set_stylebox("focus", "LineEdit", _style_box(Palette.CLEAR, Palette.FOCUS_ON_LIGHT, 2, 6, [10, 6, 10, 6]))
	theme.set_stylebox("read_only", "LineEdit", _style_box(Palette.PARCHMENT_DEEP, Palette.BORDER, 1, 6, [10, 6, 10, 6]))
	theme.set_color("font_color", "LineEdit", Palette.INK)
	theme.set_color("font_uneditable_color", "LineEdit", Palette.INK_MUTED)
	theme.set_color("font_placeholder_color", "LineEdit", Palette.INK_MUTED)
	theme.set_color("caret_color", "LineEdit", Palette.INK)
	theme.set_color("selection_color", "LineEdit", Palette.ACCENT_SELECTION)
	theme.set_color("font_selected_color", "LineEdit", Palette.INK)


## Horizontal sliders (volumes): a dark track, an accent fill up to the value and a round knob 28 units wide.
func _sliders() -> void:
	theme.set_stylebox("slider", "HSlider", _style_box(Palette.INK_MUTED, Palette.INK, 1, 5, [0, 4, 0, 4]))
	theme.set_stylebox("grabber_area", "HSlider", _style_box(Palette.ACCENT, Palette.ACCENT, 0, 5, [0, 4, 0, 4]))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _style_box(Palette.ACCENT_HOVER, Palette.ACCENT_HOVER, 0, 5, [0, 4, 0, 4]))
	theme.set_icon("grabber", "HSlider", _knob(Palette.ACCENT))
	theme.set_icon("grabber_highlight", "HSlider", _knob(Palette.ACCENT_HOVER))
	theme.set_icon("grabber_disabled", "HSlider", _knob(Palette.DISABLED_TEXT))
	theme.set_constant("center_grabber", "HSlider", 0)
	theme.set_constant("grabber_offset", "HSlider", 0)


## A round knob with a cream ring, drawn as a radial gradient so the theme needs no image file.
func _knob(fill: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([fill, fill, Palette.CREAM, Palette.CREAM, Palette.CLEAR])
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 0.64, 0.92, 0.96])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 28
	texture.height = 28
	return texture


func _labels() -> void:
	theme.set_color("font_color", "Label", Palette.INK)
	theme.set_color("default_color", "RichTextLabel", Palette.INK)
	theme.set_font("normal_font", "RichTextLabel", regular)
	theme.set_font_size("normal_font_size", "RichTextLabel", 18)
	theme.set_constant("line_spacing", "Label", 2)


func _variations() -> void:
	_variation("AccentButton", "Button")
	_button_states("AccentButton", Palette.ACCENT, Palette.ACCENT_HOVER, Palette.ACCENT_PRESSED, Palette.CLEAR, Palette.CLEAR)
	_white_text("AccentButton")
	_variation("DangerButton", "Button")
	_button_states("DangerButton", Palette.DANGER, Palette.DANGER_HOVER, Palette.DANGER_PRESSED, Palette.CLEAR, Palette.CLEAR)
	_white_text("DangerButton")
	_variation("GhostButton", "Button")
	var clear := Palette.CLEAR
	theme.set_stylebox("normal", "GhostButton", _style_box(clear, clear, 0, 8, [12, 8, 12, 8]))
	theme.set_stylebox("hover", "GhostButton", _style_box(Palette.GHOST_HOVER, clear, 0, 8, [12, 8, 12, 8]))
	theme.set_stylebox("pressed", "GhostButton", _style_box(Palette.GHOST_PRESSED, clear, 0, 8, [12, 9, 12, 7]))
	theme.set_stylebox("hover_pressed", "GhostButton", _style_box(Palette.GHOST_PRESSED, clear, 0, 8, [12, 9, 12, 7]))
	theme.set_stylebox("disabled", "GhostButton", _style_box(clear, clear, 0, 8, [12, 8, 12, 8]))
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(color_name, "GhostButton", Palette.CREAM)
	theme.set_color("font_disabled_color", "GhostButton", Palette.CREAM_DISABLED)
	var focus_dark := _style_box(clear, Palette.FOCUS_ON_DARK, 2, 10, [0, 0, 0, 0])
	focus_dark.set_expand_margin_all(3)
	theme.set_stylebox("focus", "GhostButton", focus_dark)

	_variation("TablePanel", "PanelContainer")
	theme.set_stylebox("panel", "TablePanel", _style_box(Palette.TABLE_PANEL, Palette.TABLE_PANEL_BORDER, 1, 10, [16, 14, 16, 14]))
	_variation("SeatPanel", "PanelContainer")
	var seat := _style_box(Palette.PARCHMENT, Palette.BORDER, 2, 10, [16, 14, 16, 14], 8, Vector2(0, 4), 0.35)
	seat.border_width_left = 6
	theme.set_stylebox("panel", "SeatPanel", seat)
	_variation("SeatPanelCurrent", "PanelContainer")
	var current := seat.duplicate() as StyleBoxFlat
	current.border_color = Palette.FOCUS_ON_DARK
	current.set_border_width_all(2)
	current.border_width_left = 6
	current.set_expand_margin_all(2)
	theme.set_stylebox("panel", "SeatPanelCurrent", current)
	_variation("Toast", "PanelContainer")
	theme.set_stylebox("panel", "Toast", _style_box(Color(Palette.INK, 0.94), clear, 0, 10, [16, 12, 16, 12], 10, Vector2(0, 4), 0.5))
	_variation("ErrorToast", "PanelContainer")
	var error_toast := _style_box(Color(Palette.INK, 0.94), Palette.DANGER, 0, 10, [16, 12, 16, 12], 10, Vector2(0, 4), 0.5)
	error_toast.border_width_left = 4
	theme.set_stylebox("panel", "ErrorToast", error_toast)

	_label_variation("TitleLabel", bitter_bold, 40, Palette.INK)
	_label_variation("TitleLabelDark", bitter_bold, 40, Palette.CREAM)
	_label_variation("HeadingLabel", bitter_semibold, 28, Palette.INK)
	_label_variation("HeadingLabelDark", bitter_semibold, 28, Palette.CREAM)
	_label_variation("SubheadingLabel", bitter_semibold, 22, Palette.INK)
	_label_variation("SubheadingLabelDark", bitter_semibold, 22, Palette.CREAM)
	_label_variation("CountLabel", bold, 20, Palette.INK)
	_label_variation("SmallLabel", regular, 16, Palette.INK)
	_label_variation("MutedLabel", regular, 20, Palette.INK_MUTED)
	_label_variation("CreamLabel", regular, 20, Palette.CREAM)
	_label_variation("CreamCountLabel", bold, 20, Palette.CREAM)
	_label_variation("DangerLabel", bold, 20, Palette.DANGER)
	_label_variation("CreamMutedLabel", regular, 20, Palette.CREAM_MUTED)
	_label_variation("DangerLabelDark", bold, 28, Palette.DANGER_ON_DARK)
	_label_variation("CardLabel", bold, 18, Palette.INK)
	_label_variation("CardLabelLight", bold, 18, Palette.CREAM)
	_label_variation("CardCount", bold, 28, Palette.INK)
	_label_variation("CardCountLight", bold, 28, Palette.CREAM)
	_hud_panels()
	_dev_card_button()
	_resource_cards()
	_build_button()


## Panels of the game screen: dark bars on the table, dice, trade card and dialogs.
func _hud_panels() -> void:
	for bar in [["TopBarPanel", [12, 4, 12, 4]], ["BottomBarPanel", [12, 8, 12, 8]]]:
		_variation(bar[0], "PanelContainer")
		theme.set_stylebox("panel", bar[0], _style_box(Palette.TABLE_PANEL, Palette.TABLE_PANEL_BORDER, 1, 0, bar[1]))
	_variation("DieFace", "PanelContainer")
	theme.set_stylebox("panel", "DieFace", _style_box(Palette.CARD_STOCK, Palette.INK, 2, 10, [4, 4, 4, 4], 4, Vector2(0, 2), 0.3))
	_variation("TradeCard", "PanelContainer")
	var trade := _style_box(Palette.PARCHMENT, Palette.FOCUS_ON_DARK, 3, 10, [16, 12, 16, 12], 12, Vector2(0, 4), 0.4)
	theme.set_stylebox("panel", "TradeCard", trade)
	_variation("DialogPanel", "PanelContainer")
	theme.set_stylebox("panel", "DialogPanel", _style_box(Palette.PARCHMENT, Palette.BORDER, 2, 12, [20, 18, 20, 18], 16, Vector2(0, 8), 0.45))
	_variation("PlayerPanelCompact", "PanelContainer")
	var compact := _style_box(Palette.PARCHMENT, Palette.BORDER, 2, 10, [12, 6, 12, 6], 8, Vector2(0, 4), 0.35)
	compact.border_width_left = 6
	theme.set_stylebox("panel", "PlayerPanelCompact", compact)
	_variation("PlayerPanelCompactCurrent", "PanelContainer")
	var compact_current := compact.duplicate() as StyleBoxFlat
	compact_current.border_color = Palette.FOCUS_ON_DARK
	compact_current.set_border_width_all(2)
	compact_current.border_width_left = 6
	theme.set_stylebox("panel", "PlayerPanelCompactCurrent", compact_current)


## One card style per resource: the terrain colour with the card border.
func _resource_cards() -> void:
	for resource: String in Palette.RESOURCE_COLORS:
		var name := "ResourceCard" + resource
		_variation(name, "PanelContainer")
		theme.set_stylebox("panel", name, _style_box(Palette.RESOURCE_COLORS[resource], Palette.BORDER, 2, 8, [4, 4, 4, 4], 3, Vector2(0, 2), 0.3))


## The development card buttons of the bottom bar: a Button with narrow side margins, so a card name fits on a
## line in a button barely wider than the name.
func _dev_card_button() -> void:
	_variation("DevCardButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var plate := theme.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		plate.content_margin_left = 6
		plate.content_margin_right = 6
		theme.set_stylebox(state, "DevCardButton", plate)


## A toggle button that reads as armed when pressed (build mode).
func _build_button() -> void:
	_variation("BuildButton", "Button")
	_button_states("BuildButton", Palette.BUTTON, Palette.BUTTON_HOVER, Palette.ACCENT, Palette.BORDER, Palette.BUTTON_HOVER_BORDER)
	theme.set_stylebox("disabled", "BuildButton", _style_box(Palette.DISABLED_FILL, Palette.DISABLED_BORDER, 1, 8, [16, 8, 16, 8]))
	for color_name in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(color_name, "BuildButton", Palette.INK)
	for color_name in ["font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(color_name, "BuildButton", Color.WHITE)
	theme.set_color("font_disabled_color", "BuildButton", Palette.DISABLED_TEXT)


func _variation(name: String, base: String) -> void:
	theme.set_type_variation(name, base)


func _white_text(type_name: String) -> void:
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(color_name, type_name, Color.WHITE)
	theme.set_color("font_disabled_color", type_name, Palette.DISABLED_TEXT)
	theme.set_stylebox("disabled", type_name, _style_box(Palette.DISABLED_FILL, Palette.DISABLED_BORDER, 1, 8, [16, 8, 16, 8]))


func _label_variation(name: String, font: Font, size: int, color: Color) -> void:
	_variation(name, "Label")
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)

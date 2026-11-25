extends SceneTree
## Builds the UI theme of doc/design/visual-style.md section 5 and its fonts. The TTF sources in
## assets/fonts/ are hidden from the importer (.gdignore) and saved here as FontFile resources, so the
## project theme loads on a fresh checkout before anything is imported.
## Usage: godot --headless --path client/godot -s tools/build_theme.gd

const FONT_SOURCES := "res://assets/fonts/"
const FONT_OUTPUT := "res://theme/fonts/"
const THEME_PATH := "res://theme/main_theme.tres"

const PARCHMENT := Color("#F2E8D2")
const CARD_STOCK := Color("#FBF5E6")
const INK := Color("#2E241C")
const INK_MUTED := Color("#6B5A45")
const CREAM := Color("#F3EADB")
const BORDER := Color("#8A6A44")
const BUTTON := Color("#E2D3B2")
const FOCUS_LIGHT := Color("#8C5A0E")

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
	style.shadow_color = Color(0, 0, 0, shadow_alpha)
	return style


func _panels() -> void:
	var panel := _style_box(PARCHMENT, BORDER, 2, 10, [16, 14, 16, 14], 8, Vector2(0, 4), 0.35)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var popup := _style_box(PARCHMENT, BORDER, 2, 12, [20, 18, 20, 18], 16, Vector2(0, 8), 0.45)
	theme.set_stylebox("panel", "PopupPanel", popup)
	theme.set_stylebox("panel", "AcceptDialog", popup)
	theme.set_stylebox("panel", "PopupMenu", _style_box(PARCHMENT, BORDER, 2, 8, [6, 6, 6, 6], 8, Vector2(0, 4), 0.35))
	theme.set_stylebox("hover", "PopupMenu", _style_box(Color("#E6D8BA"), Color("#E6D8BA"), 0, 6, [8, 4, 8, 4]))
	for color_name in ["font_color", "font_hover_color", "font_accelerator_color"]:
		theme.set_color(color_name, "PopupMenu", INK)
	theme.set_color("font_disabled_color", "PopupMenu", Color("#7A6E5E"))
	theme.set_stylebox("panel", "TooltipPanel", _style_box(INK, INK, 0, 6, [10, 6, 10, 6], 4, Vector2(0, 2), 0.4))
	theme.set_color("font_color", "TooltipLabel", CREAM)
	theme.set_font_size("font_size", "TooltipLabel", 16)
	theme.set_stylebox("panel", "ItemList", _style_box(CARD_STOCK, BORDER, 1, 8, [6, 6, 6, 6]))
	theme.set_stylebox("panel", "Tree", _style_box(CARD_STOCK, BORDER, 1, 8, [6, 6, 6, 6]))
	theme.set_stylebox("focus", "ItemList", _style_box(Color(0, 0, 0, 0), FOCUS_LIGHT, 2, 8, [6, 6, 6, 6]))
	var selected := _style_box(Color("#E6D8BA"), BORDER, 1, 6, [4, 2, 4, 2])
	theme.set_stylebox("selected", "ItemList", selected)
	theme.set_stylebox("selected_focus", "ItemList", selected)
	theme.set_stylebox("hovered", "ItemList", _style_box(Color("#F2E8D2"), Color("#F2E8D2"), 0, 6, [4, 2, 4, 2]))
	for color_name in ["font_color", "font_hovered_color", "font_selected_color"]:
		theme.set_color(color_name, "ItemList", INK)
	theme.set_color("guide_color", "ItemList", Color("#C9B48E66"))
	theme.set_color("font_color", "Tree", INK)
	theme.set_stylebox("background", "ProgressBar", _style_box(Color("#D9CDB5"), Color("#D9CDB5"), 0, 6, [0, 0, 0, 0]))
	theme.set_stylebox("fill", "ProgressBar", _style_box(Color("#1E6B63"), Color("#1E6B63"), 0, 6, [0, 0, 0, 0]))
	theme.set_color("font_color", "ProgressBar", INK)
	for separator in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = Color("#C9B48E")
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
	_button_states("Button", BUTTON, Color("#EADDBE"), Color("#D3C29C"), BORDER, Color("#6E5233"))
	theme.set_stylebox("disabled", "Button", _style_box(Color("#D9CDB5"), Color("#C2B597"), 1, 8, [16, 8, 16, 8]))
	var focus := _style_box(Color(0, 0, 0, 0), FOCUS_LIGHT, 2, 10, [0, 0, 0, 0])
	focus.set_expand_margin_all(3)
	theme.set_stylebox("focus", "Button", focus)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(color_name, "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color("#7A6E5E"))
	theme.set_constant("h_separation", "Button", 8)
	theme.set_font("font", "Button", bold)
	# A check box is a Button subclass; it keeps a flat look instead of inheriting the button plate.
	var flat := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		theme.set_stylebox(state, "CheckBox", flat)
		theme.set_stylebox(state, "CheckButton", flat)


func _inputs() -> void:
	theme.set_stylebox("normal", "LineEdit", _style_box(CARD_STOCK, BORDER, 1, 6, [10, 6, 10, 6]))
	theme.set_stylebox("focus", "LineEdit", _style_box(Color(0, 0, 0, 0), FOCUS_LIGHT, 2, 6, [10, 6, 10, 6]))
	theme.set_stylebox("read_only", "LineEdit", _style_box(Color("#E6D8BA"), BORDER, 1, 6, [10, 6, 10, 6]))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_uneditable_color", "LineEdit", INK_MUTED)
	theme.set_color("font_placeholder_color", "LineEdit", INK_MUTED)
	theme.set_color("caret_color", "LineEdit", INK)
	theme.set_color("selection_color", "LineEdit", Color("#1E6B6366"))
	theme.set_color("font_selected_color", "LineEdit", INK)


func _labels() -> void:
	theme.set_color("font_color", "Label", INK)
	theme.set_constant("line_spacing", "Label", 2)


func _variations() -> void:
	_variation("AccentButton", "Button")
	_button_states("AccentButton", Color("#1E6B63"), Color("#26807A"), Color("#15524C"), Color(0, 0, 0, 0), Color(0, 0, 0, 0))
	_white_text("AccentButton")
	_variation("DangerButton", "Button")
	_button_states("DangerButton", Color("#A3332A"), Color("#B8443A"), Color("#86271F"), Color(0, 0, 0, 0), Color(0, 0, 0, 0))
	_white_text("DangerButton")
	_variation("GhostButton", "Button")
	var clear := Color(0, 0, 0, 0)
	theme.set_stylebox("normal", "GhostButton", _style_box(clear, clear, 0, 8, [12, 8, 12, 8]))
	theme.set_stylebox("hover", "GhostButton", _style_box(Color("#FFFFFF1A"), clear, 0, 8, [12, 8, 12, 8]))
	theme.set_stylebox("pressed", "GhostButton", _style_box(Color("#FFFFFF26"), clear, 0, 8, [12, 9, 12, 7]))
	theme.set_stylebox("hover_pressed", "GhostButton", _style_box(Color("#FFFFFF26"), clear, 0, 8, [12, 9, 12, 7]))
	theme.set_stylebox("disabled", "GhostButton", _style_box(clear, clear, 0, 8, [12, 8, 12, 8]))
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(color_name, "GhostButton", CREAM)
	theme.set_color("font_disabled_color", "GhostButton", Color("#BFAE9599"))
	var focus_dark := _style_box(clear, Color("#E8A93A"), 2, 10, [0, 0, 0, 0])
	focus_dark.set_expand_margin_all(3)
	theme.set_stylebox("focus", "GhostButton", focus_dark)

	_variation("TablePanel", "PanelContainer")
	theme.set_stylebox("panel", "TablePanel", _style_box(Color("#3A2C23"), Color("#4E3B2E"), 1, 10, [16, 14, 16, 14]))
	_variation("SeatPanel", "PanelContainer")
	var seat := _style_box(PARCHMENT, BORDER, 2, 10, [16, 14, 16, 14], 8, Vector2(0, 4), 0.35)
	seat.border_width_left = 6
	theme.set_stylebox("panel", "SeatPanel", seat)
	_variation("SeatPanelCurrent", "PanelContainer")
	var current := seat.duplicate() as StyleBoxFlat
	current.border_color = Color("#E8A93A")
	current.set_border_width_all(2)
	current.border_width_left = 6
	current.set_expand_margin_all(2)
	theme.set_stylebox("panel", "SeatPanelCurrent", current)
	_variation("Toast", "PanelContainer")
	theme.set_stylebox("panel", "Toast", _style_box(Color(INK, 0.94), clear, 0, 10, [16, 12, 16, 12], 10, Vector2(0, 4), 0.5))
	_variation("ErrorToast", "PanelContainer")
	var error_toast := _style_box(Color(INK, 0.94), Color("#A3332A"), 0, 10, [16, 12, 16, 12], 10, Vector2(0, 4), 0.5)
	error_toast.border_width_left = 4
	theme.set_stylebox("panel", "ErrorToast", error_toast)

	_label_variation("TitleLabel", bitter_bold, 40, INK)
	_label_variation("TitleLabelDark", bitter_bold, 40, CREAM)
	_label_variation("HeadingLabel", bitter_semibold, 28, INK)
	_label_variation("HeadingLabelDark", bitter_semibold, 28, CREAM)
	_label_variation("SubheadingLabel", bitter_semibold, 22, INK)
	_label_variation("SubheadingLabelDark", bitter_semibold, 22, CREAM)
	_label_variation("CountLabel", bold, 20, INK)
	_label_variation("SmallLabel", regular, 16, INK)
	_label_variation("MutedLabel", regular, 20, INK_MUTED)
	_label_variation("CreamLabel", regular, 20, CREAM)


func _variation(name: String, base: String) -> void:
	theme.set_type_variation(name, base)


func _white_text(type_name: String) -> void:
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(color_name, type_name, Color.WHITE)
	theme.set_color("font_disabled_color", type_name, Color("#7A6E5E"))
	theme.set_stylebox("disabled", type_name, _style_box(Color("#D9CDB5"), Color("#C2B597"), 1, 8, [16, 8, 16, 8]))


func _label_variation(name: String, font: Font, size: int, color: Color) -> void:
	_variation(name, "Label")
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)

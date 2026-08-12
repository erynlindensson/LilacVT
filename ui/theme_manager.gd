extends Node
## Runtime UI palette applicator. Base structure stays in ui/ui_theme.tres (Classic colors);
## apply_palette() remaps those Classic token colors to the active palette.

signal palette_changed(palette_id: String)

const BASE_THEME := preload("res://ui/ui_theme.tres")
const DEFAULT_PALETTE := "lilac"
const SETTINGS_PATH := "user://settings.json"

## Classic source tokens as stored in ui_theme.tres (and matching hardcoded UI).
const CLASSIC := {
	"ink": Color(0.298039, 0.282353, 0.239216, 1.0),
	"panel": Color(0.811765, 0.788235, 0.698039, 1.0),
	"panel_mid": Color(0.788235, 0.764706, 0.670588, 1.0),
	"hover": Color(0.67451, 0.654902, 0.580392, 1.0),
	"cream": Color(0.847059, 0.823529, 0.729412, 1.0),
	"subpanel": Color(0.840136, 0.819162, 0.738451, 1.0),
	"muted": Color(0.690196, 0.670588, 0.592157, 1.0),
	"panel_dark": Color(0.756863, 0.737255, 0.658824, 1.0),
	## Mid shade used by InsetPanelContainer (not in the main token table).
	"shade": Color(0.526552, 0.506823, 0.428542, 1.0),
}

const PALETTES := {
	"lilac": {
		"name": "Lilac",
		"ink": Color(0.239, 0.208, 0.314, 1.0), # #3D3550
		"panel": Color(0.851, 0.816, 0.910, 1.0), # #D9D0E8
		"panel_mid": Color(0.804, 0.769, 0.871, 1.0), # #CDC4DE
		"hover": Color(0.710, 0.659, 0.788, 1.0), # #B5A8C9
		"cream": Color(0.910, 0.886, 0.949, 1.0), # #E8E2F2
		"subpanel": Color(0.886, 0.859, 0.937, 1.0), # #E2DBEF
		"muted": Color(0.620, 0.573, 0.710, 1.0),
		"panel_dark": Color(0.765, 0.722, 0.847, 1.0),
		"shade": Color(0.455, 0.400, 0.560, 1.0),
	},
	"classic": {
		"name": "Classic",
		"ink": CLASSIC.ink,
		"panel": CLASSIC.panel,
		"panel_mid": CLASSIC.panel_mid,
		"hover": CLASSIC.hover,
		"cream": CLASSIC.cream,
		"subpanel": CLASSIC.subpanel,
		"muted": CLASSIC.muted,
		"panel_dark": CLASSIC.panel_dark,
		"shade": CLASSIC.shade,
	},
	"rose": {
		"name": "Rose",
		"ink": Color(0.314, 0.196, 0.227, 1.0),
		"panel": Color(0.925, 0.835, 0.855, 1.0),
		"panel_mid": Color(0.886, 0.773, 0.800, 1.0),
		"hover": Color(0.780, 0.620, 0.655, 1.0),
		"cream": Color(0.961, 0.910, 0.922, 1.0),
		"subpanel": Color(0.941, 0.878, 0.894, 1.0),
		"muted": Color(0.710, 0.545, 0.580, 1.0),
		"panel_dark": Color(0.855, 0.745, 0.773, 1.0),
		"shade": Color(0.560, 0.365, 0.400, 1.0),
	},
	"slate": {
		"name": "Slate",
		"ink": Color(0.180, 0.200, 0.227, 1.0),
		"panel": Color(0.780, 0.804, 0.835, 1.0),
		"panel_mid": Color(0.710, 0.741, 0.780, 1.0),
		"hover": Color(0.545, 0.588, 0.643, 1.0),
		"cream": Color(0.870, 0.886, 0.910, 1.0),
		"subpanel": Color(0.835, 0.855, 0.886, 1.0),
		"muted": Color(0.475, 0.522, 0.580, 1.0),
		"panel_dark": Color(0.655, 0.690, 0.741, 1.0),
		"shade": Color(0.365, 0.400, 0.455, 1.0),
	},
}

const PALETTE_ORDER: PackedStringArray = ["lilac", "classic", "rose", "slate"]

var active_palette_id: String = DEFAULT_PALETTE
var ink: Color = CLASSIC.ink
var hover: Color = CLASSIC.hover
var _active_theme: Theme
## HSV filter derived from Classic panel → active panel (applied to leftover beige-family colors).
var _hue_shift: float = 0.0
var _sat_scale: float = 1.0
var _val_scale: float = 1.0
var _classic_hue: float = CLASSIC.panel.h
var _color_mapping: Dictionary = {}

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	var saved := _read_saved_palette_id()
	apply_palette(saved)

func _on_node_added(node: Node) -> void:
	# Groups are available after the node enters the tree.
	# Use untyped deferred arg — typed Node + call_deferred can fail in this engine build.
	call_deferred("_refresh_node", node)

func _refresh_node(node: Variant) -> void:
	if typeof(node) != TYPE_OBJECT or not is_instance_valid(node):
		return
	var n := node as Node
	if n == null or not n.is_inside_tree():
		return
	if n is Window and _active_theme != null:
		(n as Window).theme = _active_theme
	if n.is_in_group("theme:ink") and n is CanvasItem:
		(n as CanvasItem).modulate = ink
	elif n.is_in_group("theme:muted_label") and n is Label:
		var c := ink
		c.a = 0.53
		(n as Label).add_theme_color_override("font_color", c)
	elif n.is_in_group("theme:hud_gradient"):
		_update_hud_gradient(n)

func get_palette_ids() -> PackedStringArray:
	return PALETTE_ORDER

func get_palette_display_name(palette_id: String) -> String:
	return String(PALETTES.get(palette_id, {}).get("name", palette_id.capitalize()))

func apply_palette(palette_id: String) -> void:
	if not PALETTES.has(palette_id):
		palette_id = DEFAULT_PALETTE
	active_palette_id = palette_id
	var dest: Dictionary = PALETTES[palette_id]
	ink = dest.ink
	hover = dest.hover
	_configure_hue_filter(dest)

	_color_mapping = _build_mapping(dest)
	# Reload Classic from disk every time. ThemeDB project theme shares the cached
	# ui_theme.tres resource; installing a palette mutates it, so preload/duplicate
	# of that cache is not a safe Classic source after the first apply.
	var theme := _load_classic_theme()
	_recolor_theme(theme, _color_mapping)
	_active_theme = theme
	_apply_theme_to_tree(theme)
	_apply_hardcoded_ui()
	palette_changed.emit(active_palette_id)

func _load_classic_theme() -> Theme:
	var loaded := ResourceLoader.load(
		"res://ui/ui_theme.tres",
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as Theme
	if loaded != null:
		return loaded
	return BASE_THEME.duplicate(true)

func _configure_hue_filter(dest: Dictionary) -> void:
	var src_panel: Color = CLASSIC.panel
	var dst_panel: Color = dest.panel
	_classic_hue = src_panel.h
	_hue_shift = dst_panel.h - src_panel.h
	_sat_scale = dst_panel.s / maxf(src_panel.s, 0.001)
	_val_scale = dst_panel.v / maxf(src_panel.v, 0.001)

func _apply_theme_to_tree(theme: Theme) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	# Most Controls resolve ThemeDB.get_project_theme() (gui/theme/custom), not Window.theme.
	# Popups looked lilac because they are Windows that received our remapped theme; panels
	# stayed Classic because the project theme was never updated.
	_install_into_project_theme(theme)
	tree.root.theme = null
	tree.root.theme = theme
	for node in tree.root.find_children("*", "Window", true, false):
		var win := node as Window
		win.theme = null
		win.theme = theme
	for control in tree.root.find_children("*", "Control", true, false):
		(control as Control).notification(Control.NOTIFICATION_THEME_CHANGED)
		(control as Control).queue_redraw()

func _install_into_project_theme(src: Theme) -> void:
	var project := ThemeDB.get_project_theme()
	if project == null or src == null:
		return
	for type_name in src.get_type_list():
		var base := src.get_type_variation_base(type_name)
		if base != StringName():
			project.set_type_variation(type_name, base)
		for color_name in src.get_color_list(type_name):
			project.set_color(color_name, type_name, src.get_color(color_name, type_name))
		for constant_name in src.get_constant_list(type_name):
			project.set_constant(constant_name, type_name, src.get_constant(constant_name, type_name))
		for font_name in src.get_font_list(type_name):
			project.set_font(font_name, type_name, src.get_font(font_name, type_name))
		for font_size_name in src.get_font_size_list(type_name):
			project.set_font_size(font_size_name, type_name, src.get_font_size(font_size_name, type_name))
		for icon_name in src.get_icon_list(type_name):
			project.set_icon(icon_name, type_name, src.get_icon(icon_name, type_name))
		for style_name in src.get_stylebox_list(type_name):
			project.set_stylebox(style_name, type_name, src.get_stylebox(style_name, type_name))

func _build_mapping(dest: Dictionary) -> Dictionary:
	var mapping: Dictionary = {}
	for key in CLASSIC.keys():
		mapping[CLASSIC[key]] = dest[key]
	return mapping

func _map_color(c: Color, mapping: Dictionary) -> Color:
	# Preserve fully transparent black shadows/etc.
	if c.a <= 0.001 and c.r <= 0.001 and c.g <= 0.001 and c.b <= 0.001:
		return c
	for src in mapping.keys():
		var s: Color = src
		if absf(c.r - s.r) < 0.02 and absf(c.g - s.g) < 0.02 and absf(c.b - s.b) < 0.02:
			var d: Color = mapping[src]
			return Color(d.r, d.g, d.b, c.a)
	# Hue filter: shift leftover Classic beige-family colors (anti-aliased edges, midtones).
	if _is_classic_family(c):
		return _apply_hue_filter(c)
	return c

func _is_classic_family(c: Color) -> bool:
	if c.a < 0.01:
		return false
	var max_c := maxf(c.r, maxf(c.g, c.b))
	var min_c := minf(c.r, minf(c.g, c.b))
	if max_c < 0.04 or min_c > 0.98:
		return false
	# Near-neutral / gray — leave alone (true grays, pure white multipliers).
	if c.s < 0.02:
		return false
	var hue_dist := absf(c.h - _classic_hue)
	hue_dist = minf(hue_dist, 1.0 - hue_dist)
	# Classic UI is a warm low-sat beige family.
	if hue_dist <= 0.14 and c.s <= 0.5:
		return true
	# Warm neutrals where R ≥ G ≥ B (beige bias) even if hue wraps oddly at low sat.
	if c.r + 0.01 >= c.g and c.g + 0.01 >= c.b and c.s <= 0.35 and c.v > 0.2 and c.v < 0.97:
		return true
	return false

func _apply_hue_filter(c: Color) -> Color:
	return Color.from_hsv(
		fposmod(c.h + _hue_shift, 1.0),
		clampf(c.s * _sat_scale, 0.0, 1.0),
		clampf(c.v * _val_scale, 0.0, 1.0),
		c.a
	)
func _recolor_theme(theme: Theme, mapping: Dictionary) -> void:
	for type_name in theme.get_type_list():
		for color_name in theme.get_color_list(type_name):
			var c := theme.get_color(color_name, type_name)
			theme.set_color(color_name, type_name, _map_color(c, mapping))
		for style_name in theme.get_stylebox_list(type_name):
			var sb := theme.get_stylebox(style_name, type_name)
			var recolored := _recolor_stylebox(sb, mapping)
			if recolored != null:
				theme.set_stylebox(style_name, type_name, recolored)
		for icon_name in theme.get_icon_list(type_name):
			var icon := theme.get_icon(icon_name, type_name)
			var recolored_icon := _recolor_texture(icon, mapping)
			if recolored_icon != null:
				theme.set_icon(icon_name, type_name, recolored_icon)

func _recolor_stylebox(sb: StyleBox, mapping: Dictionary) -> StyleBox:
	if sb == null:
		return null
	if sb is StyleBoxFlat:
		var flat: StyleBoxFlat = sb.duplicate()
		flat.bg_color = _map_color(flat.bg_color, mapping)
		flat.border_color = _map_color(flat.border_color, mapping)
		flat.shadow_color = _map_color(flat.shadow_color, mapping)
		return flat
	if sb is PaddedStylebox:
		var padded: PaddedStylebox = sb.duplicate()
		if padded.stylebox != null:
			padded.stylebox = _recolor_stylebox(padded.stylebox, mapping)
		return padded
	return sb.duplicate()

func _recolor_texture(tex: Texture2D, mapping: Dictionary) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	var changed := false
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a < 0.01:
				continue
			var mapped := _map_color(c, mapping)
			if mapped != c:
				img.set_pixel(x, y, mapped)
				changed = true
	if not changed:
		return tex
	return ImageTexture.create_from_image(img)

func _apply_hardcoded_ui() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("theme:ink"):
		if n is CanvasItem:
			(n as CanvasItem).modulate = ink
	for n in tree.get_nodes_in_group("theme:muted_label"):
		if n is Label:
			var c := ink
			c.a = 0.53
			(n as Label).add_theme_color_override("font_color", c)
	for n in tree.get_nodes_in_group("theme:hud_gradient"):
		_update_hud_gradient(n)

func _update_hud_gradient(node: Node) -> void:
	# Expect a TextureRect (or similar) whose texture is GradientTexture2D.
	var tex: Texture2D = null
	if node is TextureRect:
		tex = (node as TextureRect).texture
	elif node.has_method("get") and node.get("texture") is Texture2D:
		tex = node.get("texture")
	if tex is GradientTexture2D:
		var gt: GradientTexture2D = tex
		if gt.gradient != null:
			gt.gradient.set_color(0, ink)
			gt.gradient.set_color(1, hover)

func _read_saved_palette_id() -> String:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return DEFAULT_PALETTE
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return DEFAULT_PALETTE
	var text := f.get_as_text()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return DEFAULT_PALETTE
	var ui: Variant = data.get("ui", {})
	if typeof(ui) != TYPE_DICTIONARY:
		return DEFAULT_PALETTE
	var id := String(ui.get("palette", DEFAULT_PALETTE))
	if PALETTES.has(id):
		return id
	return DEFAULT_PALETTE

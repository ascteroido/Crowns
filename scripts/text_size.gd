class_name TextSize
## The text size setting. Every font size is set through set_font(), which
## remembers the unscaled size so rescale() can resize text already on screen.

## Setting names in picker order, and how much each scales text.
const NAMES := ["small", "normal", "large", "larger"]
const FACTORS := {"small": 0.85, "normal": 1.0, "large": 1.15, "larger": 1.3}
## Godot's font size for controls that don't set one.
const DEFAULT_SIZE := 16

static var factor := 1.0


## Sets `control`'s font size to `base` scaled by the setting.
static func set_font(control: Control, base: int) -> void:
	control.set_meta(&"base_font_size", base)
	control.add_theme_font_size_override("font_size", scaled(base))


static func scaled(base: float) -> int:
	return maxi(1, roundi(base * factor))


## Picks the setting `name` ("normal" if unknown) and resizes the text under
## `root`, including the default size in `theme`.
static func apply(name: String, root: Node, theme: Theme) -> void:
	factor = FACTORS.get(name, 1.0)
	theme.default_font_size = scaled(DEFAULT_SIZE)
	_rescale(root)


static func _rescale(node: Node) -> void:
	if node.has_meta(&"base_font_size"):
		(node as Control).add_theme_font_size_override("font_size", scaled(node.get_meta(&"base_font_size")))
	elif node is Control:
		(node as Control).update_minimum_size()
	for child in node.get_children(true):
		_rescale(child)

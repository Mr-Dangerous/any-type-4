extends Area2D

class_name Star

var star_size: float = 1.0
var star_color: Color = Color.WHITE
var brightness: float = 1.0
var is_selected: bool = false
var is_in_constellation: bool = false

signal star_clicked(star: Star)

func _ready():
	queue_redraw()
	input_event.connect(_on_input_event)

func setup(size: float, color: Color, bright: float):
	star_size = size
	star_color = color
	brightness = bright
	queue_redraw()

func _draw():
	# Draw outer glow
	var glow_color = star_color
	glow_color.a = 0.3 * brightness
	draw_circle(Vector2.ZERO, star_size * 3, glow_color)

	# Draw main star
	draw_circle(Vector2.ZERO, star_size, star_color)

	# Draw bright center
	var center_color = Color.WHITE
	center_color.a = brightness
	draw_circle(Vector2.ZERO, star_size * 0.5, center_color)

	# If selected, draw selection ring
	if is_selected:
		draw_arc(Vector2.ZERO, star_size * 4, 0, TAU, 32, Color.YELLOW, 2.0)

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			star_clicked.emit(self)

func set_selected(selected: bool):
	is_selected = selected
	queue_redraw()

func get_collision_radius() -> float:
	return star_size * 4

extends Node2D

# Star generation settings
const NUM_STARS = 150
const STAR_COLORS = [
	Color.WHITE,
	Color(0.8, 0.9, 1.0),  # Light blue
	Color(1.0, 0.9, 0.7),  # Yellow
	Color(1.0, 0.8, 0.6),  # Orange
	Color(0.9, 0.9, 1.0),  # Pale blue
]

# Constellation data
var constellations: Array[Dictionary] = []
var current_constellation: Array[Star] = []
var is_drawing: bool = false

# Stars
var stars: Array[Star] = []

@onready var star_container: Node2D = $StarContainer
@onready var constellation_layer: Node2D = $ConstellationLayer
@onready var temp_line_layer: Node2D = $TempLineLayer
@onready var instruction_label: Label = $UI/InstructionLabel
@onready var save_button: Button = $UI/SaveButton
@onready var clear_button: Button = $UI/ClearButton
@onready var to_combat_button: Button = $UI/ToCombatButton
@onready var refresh_button: Button = $UI/RefreshButton

func _ready():
	# Check if we have saved starmap data
	if GameData.has_starmap_data:
		load_starfield()
	else:
		generate_starfield()

	save_button.pressed.connect(_on_save_constellation)
	clear_button.pressed.connect(_on_clear_current)
	to_combat_button.pressed.connect(_on_to_combat)
	refresh_button.pressed.connect(_on_refresh_starmap)

	# Connect temp line drawing
	temp_line_layer.draw.connect(_on_temp_line_draw)

	update_ui()

func generate_starfield():
	var viewport_size = get_viewport_rect().size
	var star_data_to_save: Array[Dictionary] = []

	for i in range(NUM_STARS):
		# Random position
		var pos = Vector2(
			randf() * viewport_size.x,
			randf() * viewport_size.y
		)

		# Random size (biased toward smaller stars, with some large bright ones)
		var size_roll = randf()
		var size = 2.0 if size_roll < 0.7 else (4.0 if size_roll < 0.9 else 6.0)

		# Random color
		var color = STAR_COLORS[randi() % STAR_COLORS.size()]

		# Brightness correlates with size
		var brightness = size / 6.0

		# Save star data
		star_data_to_save.append({
			"position": pos,
			"size": size,
			"color": color,
			"brightness": brightness
		})

		# Create star instance
		create_star(pos, size, color, brightness)

	# Save to GameData
	GameData.save_starmap(star_data_to_save, [])

func create_star(pos: Vector2, size: float, color: Color, brightness: float):
	var star = Star.new()
	star_container.add_child(star)
	star.position = pos
	star.setup(size, color, brightness)
	star.star_clicked.connect(_on_star_clicked)

	# Add collision shape programmatically
	var collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = size * 4
	collision_shape.shape = circle
	star.add_child(collision_shape)

	stars.append(star)

func load_starfield():
	# Load stars from GameData
	for star_data in GameData.star_data:
		create_star(
			star_data["position"],
			star_data["size"],
			star_data["color"],
			star_data["brightness"]
		)

	# Load and draw constellations
	for constellation_data in GameData.constellation_data:
		# Mark stars as in constellation
		for line_data in constellation_data["lines"]:
			# Find stars at these positions and mark them
			for star in stars:
				if star.position.distance_to(line_data["start"]) < 1 or \
				   star.position.distance_to(line_data["end"]) < 1:
					star.is_in_constellation = true

		# Draw the constellation
		draw_constellation(constellation_data)
		constellations.append(constellation_data)

func _on_refresh_starmap():
	# Clear existing stars
	for star in stars:
		star.queue_free()
	stars.clear()

	# Clear constellation visuals
	for child in constellation_layer.get_children():
		child.queue_free()
	constellations.clear()

	# Clear GameData
	GameData.clear_starmap()

	# Generate new starfield
	generate_starfield()

	# Reset UI
	current_constellation.clear()
	is_drawing = false
	temp_line_layer.queue_redraw()
	update_ui()

func _on_star_clicked(star: Star):
	if star.is_in_constellation:
		return  # Can't use stars already in constellations

	if not is_drawing:
		# Start new constellation
		is_drawing = true
		current_constellation.append(star)
		star.set_selected(true)
	else:
		# Add to current constellation
		if star in current_constellation:
			return  # Can't click the same star twice

		# Check if this line would cross existing constellations
		var new_line_start = current_constellation.back().position
		var new_line_end = star.position

		if would_cross_constellations(new_line_start, new_line_end):
			print("Cannot cross existing constellations!")
			return

		current_constellation.append(star)
		star.set_selected(true)
		redraw_temp_constellation()

	update_ui()

func _on_save_constellation():
	if current_constellation.size() < 2:
		print("Need at least 2 stars to make a constellation!")
		return

	# Save constellation
	var constellation_data = {
		"stars": current_constellation.duplicate(),
		"lines": []
	}

	# Build line data
	for i in range(current_constellation.size() - 1):
		constellation_data["lines"].append({
			"start": current_constellation[i].position,
			"end": current_constellation[i + 1].position
		})

	constellations.append(constellation_data)

	# Mark stars as used
	for star in current_constellation:
		star.is_in_constellation = true
		star.set_selected(false)

	# Draw permanent constellation
	draw_constellation(constellation_data)

	# Reset current constellation
	current_constellation.clear()
	is_drawing = false
	temp_line_layer.queue_redraw()

	# Save to GameData
	GameData.save_starmap(GameData.star_data, constellations)

	update_ui()
	print("Constellation saved! Total: ", constellations.size())

func _on_clear_current():
	for star in current_constellation:
		star.set_selected(false)

	current_constellation.clear()
	is_drawing = false
	temp_line_layer.queue_redraw()
	update_ui()

func _on_to_combat():
	get_tree().change_scene_to_file("res://scenes/Combat.tscn")

func redraw_temp_constellation():
	temp_line_layer.queue_redraw()

func _draw():
	pass

func draw_constellation(constellation_data: Dictionary):
	var line_node = Node2D.new()
	constellation_layer.add_child(line_node)

	line_node.draw.connect(func():
		for line_data in constellation_data["lines"]:
			line_node.draw_line(
				line_data["start"],
				line_data["end"],
				Color(0.5, 0.7, 1.0, 0.8),
				2.0
			)
	)
	line_node.queue_redraw()

func would_cross_constellations(new_start: Vector2, new_end: Vector2) -> bool:
	for constellation in constellations:
		for line_data in constellation["lines"]:
			if lines_intersect(new_start, new_end, line_data["start"], line_data["end"]):
				return true
	return false

func lines_intersect(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	# Check if line segments (p1,p2) and (p3,p4) intersect
	var d1 = direction(p3, p4, p1)
	var d2 = direction(p3, p4, p2)
	var d3 = direction(p1, p2, p3)
	var d4 = direction(p1, p2, p4)

	if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and \
	   ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)):
		return true

	return false

func direction(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p3.x - p1.x) * (p2.y - p1.y) - (p2.x - p1.x) * (p3.y - p1.y)

func update_ui():
	if is_drawing:
		instruction_label.text = "Click stars to connect them. " + str(current_constellation.size()) + " stars selected."
	else:
		instruction_label.text = "Click a star to start a constellation. Constellations: " + str(constellations.size())

	save_button.disabled = current_constellation.size() < 2
	clear_button.disabled = current_constellation.is_empty()

# Draw temp constellation lines
func _process(_delta):
	temp_line_layer.queue_redraw()

func _on_temp_line_draw():
	if current_constellation.size() < 2:
		return

	for i in range(current_constellation.size() - 1):
		temp_line_layer.draw_line(
			current_constellation[i].position,
			current_constellation[i + 1].position,
			Color.YELLOW,
			2.0
		)

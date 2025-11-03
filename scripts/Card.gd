extends Control

class_name Card

# Card data
var card_name: String = ""
var cost: int = 0
var description: String = ""
var card_type: String = "" # "strike" or "defend"
var armor: int = 0
var shield: int = 0
var is_deployed: bool = false
var card_instance_id: String = ""  # Unique ID for this card instance
var deployed_instance_id: String = ""  # ID of the deployed ship (e.g., "scout_alpha")
var ship_position: String = ""  # Position name (Alpha, Bravo, etc.)
var source_ship_id: String = ""  # ID of the ship that created this attack card

# UI nodes
@onready var panel: Panel = $Panel
@onready var name_label: Label = $Panel/MarginContainer/VBoxContainer/NameLabel
@onready var cost_label: Label = $Panel/MarginContainer/VBoxContainer/TopBar/CostLabel
@onready var artwork_area: ColorRect = $Panel/MarginContainer/VBoxContainer/ArtworkArea
@onready var description_label: Label = $Panel/MarginContainer/VBoxContainer/DescriptionLabel
@onready var deployed_indicator: Label = null  # Will be created dynamically
@onready var stats_label: Label = null  # Will be created dynamically

# Card state
var is_dragging: bool = false
var original_position: Vector2
var can_play: bool = true
var original_panel_style: StyleBox = null
var is_in_play_area: bool = false

signal card_played(card: Card)

func _ready():
	create_deployed_indicator()
	create_stats_label()
	update_card_display()
	# Store original panel style
	if panel and panel.get_theme_stylebox("panel"):
		original_panel_style = panel.get_theme_stylebox("panel").duplicate()

func create_deployed_indicator():
	# Create a label for the blue diamond indicator
	deployed_indicator = Label.new()
	deployed_indicator.text = "◆"  # Diamond character
	deployed_indicator.add_theme_color_override("font_color", Color(0.2, 0.5, 1.0))  # Blue color
	deployed_indicator.add_theme_font_size_override("font_size", 32)
	deployed_indicator.visible = false
	deployed_indicator.z_index = 10

	# Position it in the top right corner
	deployed_indicator.position = Vector2(85, 5)
	add_child(deployed_indicator)

func create_stats_label():
	# Create a label for armor and shield stats
	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 11)
	stats_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	stats_label.visible = false
	stats_label.z_index = 10

	# Position it at the bottom of the card
	stats_label.position = Vector2(10, 155)
	add_child(stats_label)

func setup(card_data: Dictionary, instance_id: String = ""):
	card_name = card_data.get("name", "")
	cost = card_data.get("cost", 0)
	description = card_data.get("description", "")
	card_type = card_data.get("type", "")
	armor = card_data.get("armor", 0)
	shield = card_data.get("shield", 0)
	card_instance_id = instance_id
	source_ship_id = card_data.get("source_ship_id", "")  # For attack cards
	# is_deployed will be set separately when deployment happens
	if is_node_ready():
		update_card_display()

func update_card_display():
	if name_label:
		# Show position in name if deployed
		if is_deployed and ship_position != "":
			# Replace (deployed) in card name with position
			var display_name = card_name.replace("(deployed)", ship_position)
			name_label.text = display_name
		else:
			name_label.text = card_name

		# Dynamically resize font to fit
		resize_name_to_fit()

	if cost_label:
		cost_label.text = str(cost)
	if description_label:
		# Replace (deployed) with position name in description
		var display_description = description
		if is_deployed and ship_position != "":
			display_description = description.replace("(deployed)", ship_position)
		description_label.text = display_description

	# Show deployed indicator if ship is deployed
	if deployed_indicator:
		deployed_indicator.visible = is_deployed

	# Show armor/shield stats for ship cards in health bar format (Total/Armor)
	if stats_label:
		var is_ship = card_type in ["scout", "corvette", "interceptor", "fighter"]
		if is_ship and (armor > 0 or shield > 0):
			var total_health = armor + shield
			stats_label.text = "%d/%d" % [total_health, armor]
			stats_label.visible = true
		else:
			stats_label.visible = false

func resize_name_to_fit():
	if not name_label:
		return

	# Available width is card width (120) minus margins (8*2) = 104 pixels
	var available_width = 104.0
	var max_font_size = 16
	var min_font_size = 10

	# Start with max font size and reduce if needed
	var font_size = max_font_size
	var current_font = name_label.get_theme_font("font")

	# Measure text width with current font size
	while font_size >= min_font_size:
		name_label.add_theme_font_size_override("font_size", font_size)

		# Use font to measure text width
		if current_font:
			var text_width = current_font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if text_width <= available_width:
				break

		font_size -= 1

	# Apply the final font size
	name_label.add_theme_font_size_override("font_size", font_size)

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				original_position = global_position
			else:
				is_dragging = false
				is_in_play_area = false
				reset_drag_visual()

				# Check if dropped in enemy area (upper portion of screen)
				var viewport_height = get_viewport_rect().size.y
				if can_play and global_position.y < viewport_height * 0.5:
					card_played.emit(self)
				else:
					# Smoothly slide back to original position
					var tween = create_tween()
					tween.set_trans(Tween.TRANS_QUAD)
					tween.set_ease(Tween.EASE_OUT)
					tween.tween_property(self, "global_position", original_position, 0.25)

func _process(_delta):
	if is_dragging:
		global_position = get_global_mouse_position() - size / 2

		# Check if card is in play area (upper half of screen)
		var viewport_height = get_viewport_rect().size.y
		var in_play_area = global_position.y < viewport_height * 0.5

		# Update border if play area status changed
		if in_play_area != is_in_play_area:
			is_in_play_area = in_play_area
			update_drag_visual()

func update_drag_visual():
	if not panel:
		return

	if is_in_play_area:
		# Create red border style
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.2)  # Dark background
		style.border_width_left = 3
		style.border_width_right = 3
		style.border_width_top = 3
		style.border_width_bottom = 3
		style.border_color = Color(1.0, 0.2, 0.2)  # Red border
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		panel.add_theme_stylebox_override("panel", style)
	else:
		reset_drag_visual()

func reset_drag_visual():
	if panel:
		panel.remove_theme_stylebox_override("panel")

func disable():
	can_play = false
	modulate = Color(0.5, 0.5, 0.5, 0.7)

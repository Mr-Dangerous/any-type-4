extends Control

## Card Display and Drag-Drop Component
## Displays card data and handles drag-and-drop for playing cards

# Card data
var card_data: Dictionary = {}
var is_being_dragged: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO
var original_parent: Node = null
var original_index: int = -1

# Visual components (will be set in _ready or lazily)
var name_label: Label = null
var artwork_texture: TextureRect = null
var description_label: Label = null

# Drag settings
const DRAG_SCALE: float = 1.25
const NORMAL_Z_INDEX: int = 0
const DRAG_Z_INDEX: int = 100

# Display mode
enum DisplayMode { SHORT, FULL }
var current_display_mode: DisplayMode = DisplayMode.SHORT

# Hover detection for popup
var hover_timer: Timer = null
const HOVER_TIME_THRESHOLD: float = 0.5  # 0.5 seconds for long hover
var is_mouse_over: bool = false
var hover_popup: Control = null

signal card_drag_started(card: Control)
signal card_drag_ended(card: Control, dropped_position: Vector2)
signal card_played(card: Control, target)

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Get node references
	name_label = $Content/VBox/NameLabel
	artwork_texture = $Content/VBox/ArtworkContainer/ArtworkTexture
	description_label = $Content/VBox/DescriptionContainer/DescriptionLabel

	# Setup hover timer
	hover_timer = Timer.new()
	hover_timer.wait_time = HOVER_TIME_THRESHOLD
	hover_timer.one_shot = true
	hover_timer.timeout.connect(_on_hover_timeout)
	add_child(hover_timer)

	# Connect mouse enter/exit signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# If card data was set before _ready, update visuals now
	if not card_data.is_empty():
		update_visuals()

func setup(data: Dictionary):
	"""Initialize card with data from card database"""
	card_data = data
	
	# Only update visuals if the node is ready
	if is_node_ready():
		update_visuals()

func update_visuals():
	"""Update visual elements based on card data"""
	if card_data.is_empty():
		return

	# Always load and show artwork
	if artwork_texture:
		artwork_texture.visible = true
		var sprite_path = card_data.get("sprite_path", "")
		if sprite_path != "":
			var texture = load(sprite_path)
			if texture:
				artwork_texture.texture = texture

	if current_display_mode == DisplayMode.SHORT:
		# Short mode: show artwork and short description
		if name_label:
			name_label.visible = false

		if description_label:
			description_label.text = card_data.get("card_short_description", "")
			description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		# Full mode: show all details
		if name_label:
			name_label.visible = true
			name_label.text = card_data.get("card_name", "Unknown")

		if description_label:
			description_label.text = card_data.get("card_rules_description", "")
			description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			description_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

func _input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# Mouse released anywhere - end drag if dragging
			if is_being_dragged:
				end_drag()
				get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Check if cards are playable before allowing drag
			if CardHandManager.cards_playable:
				# Start dragging
				start_drag(event.position)
				get_viewport().set_input_as_handled()

func _process(_delta):
	if is_being_dragged:
		# Update drag position every frame while dragging
		update_drag_position()

func start_drag(click_position: Vector2):
	"""Start dragging the card"""
	if is_being_dragged:
		return

	is_being_dragged = true
	# Hide any hover popup when dragging starts
	hover_timer.stop()
	hide_hover_popup()

	# Offset card below cursor for better visibility (50 pixels down)
	drag_offset = Vector2(size.x / 2, -50)
	original_position = global_position
	original_parent = get_parent()
	original_index = get_index()

	# Visual feedback
	scale = Vector2(DRAG_SCALE, DRAG_SCALE)
	z_index = DRAG_Z_INDEX
	modulate.a = 0.7  # Semi-transparent during drag

	# Reparent to root for free movement
	var canvas_layer = get_canvas_layer_root()
	if canvas_layer:
		var temp_global_pos = global_position
		get_parent().remove_child(self)
		canvas_layer.add_child(self)
		global_position = temp_global_pos

	card_drag_started.emit(self)

func update_drag_position():
	"""Update card position while dragging"""
	if not is_being_dragged:
		return
	
	var mouse_pos = get_global_mouse_position()
	# Position card centered horizontally under cursor, offset down for visibility
	global_position = mouse_pos - drag_offset

func end_drag():
	"""End dragging and check for valid drop"""
	if not is_being_dragged:
		return
	
	is_being_dragged = false
	
	# Reset visual state
	scale = Vector2.ONE
	z_index = NORMAL_Z_INDEX
	modulate.a = 1.0  # Restore full opacity
	
	# Use mouse position for targeting (more accurate than card center)
	var drop_position = get_global_mouse_position()
	card_drag_ended.emit(self, drop_position)
	
	# Note: The CardHandManager will handle target detection and card return

func return_to_hand():
	"""Animate card returning to original position in hand"""
	if original_parent == null:
		queue_free()
		return
	
	# Ensure visual state is reset
	modulate.a = 1.0
	scale = Vector2.ONE
	z_index = NORMAL_Z_INDEX
	
	# Create tween for smooth return
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Reparent back to hand
	var temp_global_pos = global_position
	get_parent().remove_child(self)
	original_parent.add_child(self)
	original_parent.move_child(self, original_index)
	global_position = temp_global_pos
	
	# Animate back to original position
	tween.tween_property(self, "global_position", original_position, 0.3)

func play_card_animation(target_position: Vector2):
	"""Animate card being played"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Move to target and fade out
	tween.parallel().tween_property(self, "global_position", target_position, 0.3)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.3)
	
	await tween.finished
	queue_free()

func get_canvas_layer_root() -> Node:
	"""Get the root CanvasLayer for dragging"""
	var canvas_layer = get_parent()
	while canvas_layer and not canvas_layer is CanvasLayer:
		canvas_layer = canvas_layer.get_parent()
	return canvas_layer if canvas_layer else get_tree().root

func get_target_type() -> String:
	"""Get the target type required for this card"""
	return card_data.get("target_type", "")

func get_card_name() -> String:
	"""Get the card name"""
	return card_data.get("card_name", "")

func get_card_function() -> String:
	"""Get the function name to execute when card is played"""
	return card_data.get("card_function", "")

func _on_mouse_entered():
	"""Called when mouse enters the card"""
	if not is_being_dragged and current_display_mode == DisplayMode.SHORT:
		is_mouse_over = true
		hover_timer.start()

func _on_mouse_exited():
	"""Called when mouse exits the card"""
	is_mouse_over = false
	hover_timer.stop()
	hide_hover_popup()

func _on_hover_timeout():
	"""Called after hovering for HOVER_TIME_THRESHOLD seconds"""
	if is_mouse_over and not is_being_dragged:
		show_hover_popup()

func show_hover_popup():
	"""Display a larger version of the card above the mouse"""
	if hover_popup:
		return  # Already showing

	# Create a new card instance for the popup
	var popup_card = card_scene.instantiate() if card_scene else null
	if not popup_card:
		return

	# Setup popup card with same data but in FULL display mode
	popup_card.card_data = card_data.duplicate()
	popup_card.current_display_mode = DisplayMode.FULL
	popup_card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't intercept mouse

	# Make popup larger by setting custom size (no scaling to avoid fuzzy text)
	popup_card.custom_minimum_size = Vector2(160, 240)
	popup_card.size = Vector2(160, 240)
	popup_card.z_index = 1000  # Very high to appear above everything

	# Add to root canvas layer
	var canvas_layer = get_canvas_layer_root()
	if canvas_layer:
		canvas_layer.add_child(popup_card)

		# Adjust font sizes and spacing for popup
		var name_lbl = popup_card.get_node_or_null("Content/VBox/NameLabel")
		if name_lbl:
			name_lbl.add_theme_font_size_override("font_size", 12)

		var desc_lbl = popup_card.get_node_or_null("Content/VBox/DescriptionContainer/DescriptionLabel")
		if desc_lbl:
			desc_lbl.add_theme_font_size_override("font_size", 9)

		var vbox = popup_card.get_node_or_null("Content/VBox")
		if vbox:
			vbox.add_theme_constant_override("separation", 2)

		# Position above the mouse cursor
		var mouse_pos = get_global_mouse_position()
		var popup_size = popup_card.size
		# Position centered horizontally, above cursor
		popup_card.global_position = mouse_pos - Vector2(popup_size.x / 2, popup_size.y + 20)

		hover_popup = popup_card
		popup_card.update_visuals()

func hide_hover_popup():
	"""Hide and remove the hover popup"""
	if hover_popup:
		hover_popup.queue_free()
		hover_popup = null

var card_scene: PackedScene = preload("res://scenes/Card.tscn")

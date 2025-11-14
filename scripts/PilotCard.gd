extends Control

## PilotCard - Draggable pilot card for barracks
## Based on Card.gd drag-drop pattern

signal drag_started(pilot_card)
signal drag_ended(pilot_card)
signal dropped_on_ship(pilot_card, ship_index)

# Pilot data
var pilot_data: Dictionary = {}
var call_sign: String = ""

# Drag state
var is_being_dragged: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO
var original_parent: Node = null
var original_index: int = -1
var placeholder: Control = null  # Placeholder to keep spot in grid (legacy system)
var drag_visual_copy: Control = null  # Visual copy for dragging (new system)

# Drag behavior configuration
## USE_VISUAL_COPY_DRAG: Controls drag-and-drop behavior
## - true: Creates a visual copy that follows cursor, original stays invisible in place
##         This reserves the slot automatically and provides cleaner visual feedback
##         Recommended for pilot and upgrade cards
## - false: Uses placeholder system where original card is reparented during drag
##          Placeholder maintains grid position, original animates back on invalid drop
##          Legacy behavior, kept for backwards compatibility
const USE_VISUAL_COPY_DRAG: bool = true

# Visual settings
const DRAG_SCALE = Vector2(1.15, 1.15)
const NORMAL_SCALE = Vector2(1.0, 1.0)
const DRAG_Z_INDEX = 100
const NORMAL_Z_INDEX = 0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP

func initialize(pilot_dict: Dictionary):
	"""Initialize the pilot card with data"""
	pilot_data = pilot_dict
	call_sign = pilot_data.get("call_sign", "Unknown")

	# Get UI references
	var portrait: TextureRect = get_node("Portrait")
	var callsign_label: Label = get_node("CallSignLabel")

	# Load portrait
	var portrait_path = pilot_data.get("portrait_path", "")
	if portrait_path != "":
		var texture = load(portrait_path)
		if texture:
			portrait.texture = texture
		else:
			push_warning("PilotCard: Could not load portrait: " + portrait_path)

	# Set call sign label
	callsign_label.text = call_sign

	# Set tooltip with pilot info
	var first_name = pilot_data.get("first_name", "")
	var last_name = pilot_data.get("last_name", "")
	var passive_ability = pilot_data.get("passive_ability", "")
	var ability_effect = pilot_data.get("ability_effect", "")
	var rarity = pilot_data.get("rarity", "")

	var tooltip_parts: Array[String] = []
	if first_name != "" or last_name != "":
		tooltip_parts.append("%s %s" % [first_name, last_name])
	if call_sign != "":
		tooltip_parts.append("Call Sign: %s" % call_sign)
	if rarity != "":
		tooltip_parts.append("Rarity: %s" % rarity)
	if passive_ability != "":
		tooltip_parts.append("\n%s" % passive_ability)
	if ability_effect != "":
		tooltip_parts.append("%s" % ability_effect)

	tooltip_text = "\n".join(tooltip_parts)

func _gui_input(event: InputEvent):
	"""Handle mouse input for dragging"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			start_drag()
			get_viewport().set_input_as_handled()

func _input(event: InputEvent):
	"""Handle global mouse release"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if is_being_dragged:
				end_drag()

func _process(_delta):
	"""Update position while dragging"""
	if is_being_dragged:
		update_drag_position()

func start_drag():
	"""Start dragging the pilot card"""
	if is_being_dragged:
		return

	is_being_dragged = true

	# Store original state
	original_position = global_position
	original_parent = get_parent()
	original_index = get_index()
	drag_offset = Vector2(size.x / 2, size.y / 2)

	if USE_VISUAL_COPY_DRAG:
		# NEW SYSTEM: Visual copy drag
		# Original stays invisible in place, copy follows cursor

		# Create visual copy
		drag_visual_copy = duplicate(0)  # Duplicate without children signals
		drag_visual_copy.scale = DRAG_SCALE
		drag_visual_copy.z_index = DRAG_Z_INDEX
		drag_visual_copy.modulate.a = 0.8

		# Add copy to canvas layer for free movement
		var canvas_layer = get_canvas_layer_root()
		if canvas_layer:
			canvas_layer.add_child(drag_visual_copy)
			drag_visual_copy.global_position = global_position

		# Make original invisible but keep it in place
		modulate.a = 0.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE  # Prevent clicks on invisible original
	else:
		# LEGACY SYSTEM: Placeholder drag
		# Original is reparented and moves, placeholder keeps slot

		# Create invisible placeholder to keep spot in grid
		placeholder = Control.new()
		placeholder.custom_minimum_size = custom_minimum_size
		placeholder.visible = false

		# Insert placeholder at current position
		original_parent.add_child(placeholder)
		original_parent.move_child(placeholder, original_index)

		# Visual feedback
		scale = DRAG_SCALE
		z_index = DRAG_Z_INDEX
		modulate.a = 0.8

		# Reparent to move freely
		var canvas_layer = get_canvas_layer_root()
		if canvas_layer:
			var old_global_pos = global_position
			original_parent.remove_child(self)
			canvas_layer.add_child(self)
			global_position = old_global_pos

	drag_started.emit(self)

func update_drag_position():
	"""Update position to follow mouse"""
	var mouse_pos = get_viewport().get_mouse_position()

	if USE_VISUAL_COPY_DRAG and drag_visual_copy:
		# Move the visual copy
		drag_visual_copy.global_position = mouse_pos - drag_offset
	else:
		# Move the original card (legacy system)
		global_position = mouse_pos - drag_offset

func end_drag():
	"""End dragging and check for valid drop"""
	if not is_being_dragged:
		return

	is_being_dragged = false

	# Check if dropped on a valid ship slot by getting it from Hangar
	var hangar = get_hangar()
	var dropped_ship_index = -1
	if hangar:
		dropped_ship_index = hangar.drop_target_ship_index

	if dropped_ship_index >= 0:
		# Valid drop on ship
		if USE_VISUAL_COPY_DRAG:
			# Clean up visual copy
			if drag_visual_copy:
				drag_visual_copy.queue_free()
				drag_visual_copy = null
		else:
			# Clean up placeholder
			if placeholder:
				placeholder.queue_free()
				placeholder = null

		dropped_on_ship.emit(self, dropped_ship_index)
		hangar.assign_pilot_to_ship(call_sign, dropped_ship_index)
		# Card will be removed by Hangar refresh
		queue_free()
	else:
		# Invalid drop - return to original position
		return_to_barracks()

	drag_ended.emit(self)

func get_hangar():
	"""Get reference to Hangar scene"""
	var node = get_tree().current_scene
	if node and node.name == "Hangar":
		return node
	return null

func return_to_barracks():
	"""Smoothly return to original position in barracks"""
	if USE_VISUAL_COPY_DRAG:
		# NEW SYSTEM: Animate visual copy back, then restore original
		if drag_visual_copy:
			# Animate visual copy back to original position
			var tween = create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(drag_visual_copy, "global_position", global_position, 0.3)
			tween.parallel().tween_property(drag_visual_copy, "modulate:a", 0.0, 0.3)

			# When animation completes, clean up visual copy and restore original
			tween.tween_callback(func():
				if drag_visual_copy:
					drag_visual_copy.queue_free()
					drag_visual_copy = null
				# Restore original visibility
				modulate.a = 1.0
				mouse_filter = Control.MOUSE_FILTER_STOP
			)
		else:
			# No visual copy somehow, just restore original
			modulate.a = 1.0
			mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		# LEGACY SYSTEM: Reparent original back and animate
		# Restore visual state immediately
		scale = NORMAL_SCALE
		z_index = NORMAL_Z_INDEX
		modulate.a = 1.0

		# Reparent back to original parent
		if original_parent and placeholder:
			var canvas_layer = get_parent()
			var placeholder_index = placeholder.get_index()

			# Remove from canvas
			canvas_layer.remove_child(self)

			# Add back to grid at placeholder position
			original_parent.add_child(self)
			original_parent.move_child(self, placeholder_index)

			# Remove placeholder
			placeholder.queue_free()
			placeholder = null

			# Animate back to position
			var tween = create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(self, "position", Vector2.ZERO, 0.3)

func assign_to_ship():
	"""Called when successfully assigned to a ship"""
	# Restore visual state
	scale = NORMAL_SCALE
	z_index = NORMAL_Z_INDEX
	modulate.a = 1.0

func get_canvas_layer_root() -> CanvasLayer:
	"""Find the CanvasLayer in the scene tree"""
	var node = get_parent()
	while node:
		if node is CanvasLayer:
			return node
		node = node.get_parent()

	# Fallback: find any CanvasLayer in scene
	var root = get_tree().root
	for child in root.get_children():
		var canvas = find_canvas_layer(child)
		if canvas:
			return canvas

	return null

func find_canvas_layer(node: Node) -> CanvasLayer:
	"""Recursively find CanvasLayer"""
	if node is CanvasLayer:
		return node

	for child in node.get_children():
		var result = find_canvas_layer(child)
		if result:
			return result

	return null

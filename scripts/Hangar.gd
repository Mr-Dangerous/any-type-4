extends Node2D

## Hangar Scene
## Displays player ships from starting_ships.csv with pagination
## Displays pilots from starting_pilots.csv in barracks
## Handles pilot assignment via drag-and-drop

# UI References - Ships
@onready var ship_grid = $UI/ShipPanel/ScrollContainer/ShipGrid
@onready var next_page_button = $UI/ShipPanel/NextPageButton
@onready var prev_page_button = $UI/ShipPanel/PrevPageButton
@onready var page_label = $UI/ShipPanel/PageLabel

# UI References - Barracks
@onready var pilot_grid = $UI/BarracksPanel/ScrollContainer/PilotGrid
@onready var next_pilot_page_button = $UI/BarracksPanel/NextPilotPageButton
@onready var prev_pilot_page_button = $UI/BarracksPanel/PrevPilotPageButton
@onready var pilot_page_label = $UI/BarracksPanel/PilotPageLabel

# UI References - General
@onready var back_button = $UI/BackButton

# Ship data
var ship_ids: Array[String] = []
var ship_current_page: int = 0
var ships_per_page: int = 12
var ship_total_pages: int = 0
var ship_containers: Array[Control] = []  # References to ship container nodes
var ship_pilot_slots: Array = []  # References to pilot slot containers for each ship

# Pilot data
var pilot_call_signs: Array[String] = []
var available_pilots: Array[String] = []  # Pilots not yet assigned
var pilot_current_page: int = 0
var pilots_per_page: int = 8
var pilot_total_pages: int = 0
var pilot_cards: Array = []  # References to pilot card nodes
var assigned_pilots: Dictionary = {}  # ship_index -> call_sign

# Currently dragging pilot
var dragging_pilot: Control = null
var drop_target_ship_index: int = -1

# Ship display configuration
const SHIP_BOX_SIZE = 96
const SLOT_SIZE = 20
const SLOT_PADDING = 4
const PILOT_SLOT_COLOR = Color(1.0, 1.0, 0.0, 1.0)  # Yellow
const PILOT_SLOT_HIGHLIGHT = Color(1.0, 1.0, 0.5, 1.0)  # Bright yellow
const UPGRADE_SLOT_COLOR = Color(0.0, 0.0, 0.5, 1.0)  # Dark blue

# Preload pilot card scene
const PilotCardScene = preload("res://scenes/PilotCard.tscn")

func _ready():
	print("Hangar: Initializing...")

	# Connect ship buttons
	back_button.pressed.connect(_on_back_button_pressed)
	next_page_button.pressed.connect(_on_next_page_pressed)
	prev_page_button.pressed.connect(_on_prev_page_pressed)

	# Connect pilot buttons
	next_pilot_page_button.pressed.connect(_on_next_pilot_page_pressed)
	prev_pilot_page_button.pressed.connect(_on_prev_pilot_page_pressed)

	# Load and display ships
	load_ships()
	update_ship_page_display()

	# Load and display pilots
	load_pilots()
	update_pilot_page_display()

func load_ships():
	"""Load starting ships from CSV"""
	ship_ids = DataManager.load_starting_ships()

	if ship_ids.is_empty():
		push_warning("Hangar: No starting ships found")
		return

	# Calculate total pages
	ship_total_pages = ceili(float(ship_ids.size()) / float(ships_per_page))
	print("Hangar: Loaded ", ship_ids.size(), " ships across ", ship_total_pages, " pages")

func load_pilots():
	"""Load starting pilots from CSV"""
	pilot_call_signs = DataManager.load_starting_pilots()
	available_pilots = pilot_call_signs.duplicate()

	if pilot_call_signs.is_empty():
		push_warning("Hangar: No starting pilots found")
		return

	# Calculate total pages
	pilot_total_pages = ceili(float(pilot_call_signs.size()) / float(pilots_per_page))
	print("Hangar: Loaded ", pilot_call_signs.size(), " pilots across ", pilot_total_pages, " pages")

# ============================================================================
# SHIP DISPLAY
# ============================================================================

func update_ship_page_display():
	"""Update the ship grid for the current page"""
	# Clear existing ship displays
	for child in ship_grid.get_children():
		child.queue_free()
	ship_containers.clear()
	ship_pilot_slots.clear()

	# Calculate ship range for current page
	var start_index = ship_current_page * ships_per_page
	var end_index = min(start_index + ships_per_page, ship_ids.size())

	# Create ship displays for current page
	for i in range(start_index, end_index):
		var ship_id = ship_ids[i]
		var ship_data = DataManager.get_ship_data(ship_id)

		if ship_data.is_empty():
			push_warning("Hangar: Ship data not found for: " + ship_id)
			continue

		create_ship_display(ship_data, i)

	# Update navigation buttons
	update_ship_navigation_buttons()

func create_ship_display(ship_data: Dictionary, ship_index: int):
	"""Create a complete ship display with sprite, pilot slot, and upgrade slots"""
	# Container for entire ship display (vertical layout)
	var ship_container = VBoxContainer.new()
	ship_container.custom_minimum_size = Vector2(SHIP_BOX_SIZE, SHIP_BOX_SIZE + SLOT_SIZE + 10)
	ship_container.set_meta("ship_index", ship_index)  # Store ship index for drop detection
	ship_container.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow mouse events

	# Track this container
	ship_containers.append(ship_container)

	# Ship sprite box
	var ship_sprite = TextureRect.new()
	ship_sprite.custom_minimum_size = Vector2(SHIP_BOX_SIZE, SHIP_BOX_SIZE)
	ship_sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	ship_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Load ship sprite
	var sprite_path = ship_data.get("sprite_path", "")
	if sprite_path != "":
		var texture = load(sprite_path)
		if texture:
			ship_sprite.texture = texture
		else:
			push_warning("Hangar: Could not load sprite: " + sprite_path)

	# Background for ship sprite (dark background)
	var sprite_bg = ColorRect.new()
	sprite_bg.color = Color(0.2, 0.2, 0.25, 1.0)
	sprite_bg.custom_minimum_size = Vector2(SHIP_BOX_SIZE, SHIP_BOX_SIZE)
	ship_sprite.add_child(sprite_bg)
	sprite_bg.show_behind_parent = true

	ship_container.add_child(ship_sprite)

	# Spacer between ship and slots
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 5)
	ship_container.add_child(spacer)

	# Slot container (horizontal layout for pilot + upgrade slots)
	var slot_container = HBoxContainer.new()
	slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_container.add_theme_constant_override("separation", SLOT_PADDING)

	# Pilot slot (yellow background with portrait on top)
	var pilot_slot_container = Control.new()
	pilot_slot_container.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

	# Yellow background
	var pilot_slot_bg = ColorRect.new()
	pilot_slot_bg.color = PILOT_SLOT_COLOR
	pilot_slot_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pilot_slot_container.add_child(pilot_slot_bg)

	slot_container.add_child(pilot_slot_container)

	# Store reference to this pilot slot
	ship_pilot_slots.append(pilot_slot_container)

	# Check if pilot is assigned and display portrait
	if assigned_pilots.has(ship_index):
		var call_sign = assigned_pilots[ship_index]
		var pilot_data = DataManager.get_pilot_data(call_sign)
		if not pilot_data.is_empty():
			# Add pilot portrait on top of yellow square
			var portrait = TextureRect.new()
			portrait.name = "PilotPortrait"
			portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
			portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.mouse_filter = Control.MOUSE_FILTER_STOP  # Enable mouse events for tooltip

			# Load portrait texture
			var portrait_path = pilot_data.get("portrait_path", "")
			if portrait_path != "":
				var texture = load(portrait_path)
				if texture:
					portrait.texture = texture

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

			portrait.tooltip_text = "\n".join(tooltip_parts)

			pilot_slot_container.add_child(portrait)

	# Upgrade slots (dark blue, based on ship's upgrade_slots value)
	var upgrade_slots_count = ship_data.get("upgrade_slots", 0)
	for i in range(3):  # Always create 3 slots, but hide some based on count
		var upgrade_slot = ColorRect.new()
		upgrade_slot.color = UPGRADE_SLOT_COLOR
		upgrade_slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

		# Hide slots beyond the ship's upgrade_slots count
		if i >= upgrade_slots_count:
			upgrade_slot.modulate.a = 0.3  # Make it semi-transparent/dimmed

		slot_container.add_child(upgrade_slot)

	ship_container.add_child(slot_container)

	# Add to grid
	ship_grid.add_child(ship_container)

func update_ship_navigation_buttons():
	"""Update the visibility and state of ship navigation buttons"""
	# Update page label
	page_label.text = "Page %d / %d" % [ship_current_page + 1, ship_total_pages]

	# Show/hide prev button
	prev_page_button.visible = ship_current_page > 0

	# Show/hide next button
	next_page_button.visible = ship_current_page < ship_total_pages - 1

func update_pilot_slot_visual(ship_index: int):
	"""Update the visual display of a pilot slot to show assigned pilot"""
	# Find the slot index relative to current page
	var start_index = ship_current_page * ships_per_page
	var slot_index = ship_index - start_index

	# Check if this ship is on the current page
	if slot_index < 0 or slot_index >= ship_pilot_slots.size():
		return

	var pilot_slot = ship_pilot_slots[slot_index]
	var call_sign = assigned_pilots.get(ship_index, "")

	if call_sign == "":
		return

	# Get pilot data
	var pilot_data = DataManager.get_pilot_data(call_sign)
	if pilot_data.is_empty():
		return

	# Remove any existing portrait
	for child in pilot_slot.get_children():
		if child.name == "PilotPortrait":
			child.queue_free()

	# Add pilot portrait on top of yellow square
	var portrait = TextureRect.new()
	portrait.name = "PilotPortrait"
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Load portrait texture
	var portrait_path = pilot_data.get("portrait_path", "")
	if portrait_path != "":
		var texture = load(portrait_path)
		if texture:
			portrait.texture = texture

	pilot_slot.add_child(portrait)

# ============================================================================
# PILOT DISPLAY
# ============================================================================

func update_pilot_page_display():
	"""Update the pilot grid for the current page"""
	# Clear existing pilot displays
	for child in pilot_grid.get_children():
		child.queue_free()
	pilot_cards.clear()

	# Calculate pilot range for current page
	var start_index = pilot_current_page * pilots_per_page
	var end_index = min(start_index + pilots_per_page, available_pilots.size())

	# Create pilot card displays for current page
	for i in range(start_index, end_index):
		var call_sign = available_pilots[i]
		var pilot_data = DataManager.get_pilot_data(call_sign)

		if pilot_data.is_empty():
			push_warning("Hangar: Pilot data not found for: " + call_sign)
			continue

		create_pilot_card(pilot_data)

	# Update navigation buttons
	update_pilot_navigation_buttons()

func create_pilot_card(pilot_data: Dictionary):
	"""Create a pilot card instance"""
	var pilot_card = PilotCardScene.instantiate()
	pilot_card.initialize(pilot_data)

	# Connect signals
	pilot_card.drag_started.connect(_on_pilot_drag_started)
	pilot_card.drag_ended.connect(_on_pilot_drag_ended)
	pilot_card.dropped_on_ship.connect(_on_pilot_dropped_on_ship)

	# Add to grid
	pilot_grid.add_child(pilot_card)
	pilot_cards.append(pilot_card)

func update_pilot_navigation_buttons():
	"""Update the visibility and state of pilot navigation buttons"""
	# Update page label
	pilot_page_label.text = "Page %d / %d" % [pilot_current_page + 1, pilot_total_pages]

	# Show/hide prev button
	prev_pilot_page_button.visible = pilot_current_page > 0

	# Show/hide next button
	next_pilot_page_button.visible = pilot_current_page < pilot_total_pages - 1

# ============================================================================
# DRAG AND DROP
# ============================================================================

func _on_pilot_drag_started(pilot_card):
	"""Handle pilot drag start"""
	dragging_pilot = pilot_card
	print("Hangar: Started dragging pilot: ", pilot_card.call_sign)

func _on_pilot_drag_ended(pilot_card):
	"""Handle pilot drag end"""
	dragging_pilot = null
	drop_target_ship_index = -1

func _on_pilot_dropped_on_ship(pilot_card, ship_index):
	"""Handle pilot dropped on ship - called from PilotCard"""
	# This will be handled by _process checking for drop zones
	pass

func _process(_delta):
	"""Check for drop targets while dragging"""
	if dragging_pilot:
		check_drop_targets()

func check_drop_targets():
	"""Check if dragging pilot is over a valid ship slot"""
	var mouse_pos = get_viewport().get_mouse_position()
	var new_target = -1

	# Check each ship container
	for i in range(ship_containers.size()):
		var container = ship_containers[i]
		var rect = Rect2(container.global_position, container.size)

		if rect.has_point(mouse_pos):
			new_target = container.get_meta("ship_index")
			break

	# Update highlight if target changed
	if new_target != drop_target_ship_index:
		drop_target_ship_index = new_target
		update_drop_highlights()

func update_drop_highlights():
	"""Highlight valid drop targets"""
	# For now, we'll implement visual feedback later
	# This would highlight the pilot slot of the target ship
	pass

func assign_pilot_to_ship(pilot_call_sign: String, ship_index: int):
	"""Assign a pilot to a ship"""
	print("Hangar: Assigning pilot ", pilot_call_sign, " to ship ", ship_index)

	# Remove from available pilots
	available_pilots.erase(pilot_call_sign)

	# Store assignment
	assigned_pilots[ship_index] = pilot_call_sign

	# Refresh displays
	update_pilot_page_display()
	update_ship_page_display()

# ============================================================================
# BUTTON HANDLERS
# ============================================================================

func _on_back_button_pressed():
	"""Return to StarMap"""
	print("Hangar: Returning to StarMap")
	get_tree().change_scene_to_file("res://scenes/StarMap.tscn")

func _on_next_page_pressed():
	"""Go to next ship page"""
	if ship_current_page < ship_total_pages - 1:
		ship_current_page += 1
		print("Hangar: Moving to ship page ", ship_current_page + 1)
		update_ship_page_display()

func _on_prev_page_pressed():
	"""Go to previous ship page"""
	if ship_current_page > 0:
		ship_current_page -= 1
		print("Hangar: Moving to ship page ", ship_current_page + 1)
		update_ship_page_display()

func _on_next_pilot_page_pressed():
	"""Go to next pilot page"""
	if pilot_current_page < pilot_total_pages - 1:
		pilot_current_page += 1
		print("Hangar: Moving to pilot page ", pilot_current_page + 1)
		update_pilot_page_display()

func _on_prev_pilot_page_pressed():
	"""Go to previous pilot page"""
	if pilot_current_page > 0:
		pilot_current_page -= 1
		print("Hangar: Moving to pilot page ", pilot_current_page + 1)
		update_pilot_page_display()

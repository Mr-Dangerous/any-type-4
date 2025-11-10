extends Node

## CardHandManager Singleton
## Manages deck, hand, and discard pile for the card system
## Handles drawing cards, playing cards, and hand UI

# Card piles
var draw_pile: Array[String] = []  # Array of card names
var hand: Array = []  # Array of Card nodes
var discard_pile: Array[String] = []  # Array of card names

# Hand UI
var hand_container: HBoxContainer = null
var hand_canvas_layer: CanvasLayer = null
var card_scene: PackedScene = preload("res://scenes/Card.tscn")

# Hand settings
const MAX_HAND_SIZE: int = 7
const HAND_Y_POSITION: int = 470
const CARD_SPACING: int = 10

# Current dragged card
var dragged_card: Control = null
var highlighted_targets: Array = []  # Array of ship/turret dictionaries being highlighted (red)
var hovered_target: Dictionary = {}  # Currently hovered target (yellow)

# Reference to combat scene for target detection
var combat_scene: Node = null
var current_lane_index: int = -1

# Card playability (can draw always, but can only play during precombat)
var cards_playable: bool = true

signal card_drawn(card_name: String)
signal hand_updated()
signal card_played_successfully(card_name: String, target)

func _ready():
	print("CardHandManager: Initialized")

func _process(_delta):
	# Update hover highlighting during card drag
	if dragged_card:
		update_hover_highlight()

func initialize_deck():
	"""Load and shuffle the starting deck"""
	print("CardHandManager: Initializing deck...")
	
	# Load starting deck from DataManager
	var deck_card_names = DataManager.load_starting_deck()
	draw_pile = deck_card_names.duplicate()
	
	# Shuffle the deck
	shuffle_deck()
	
	print("CardHandManager: Deck initialized with ", draw_pile.size(), " cards")

func shuffle_deck():
	"""Shuffle the draw pile"""
	draw_pile.shuffle()
	print("CardHandManager: Deck shuffled")

func draw_card() -> bool:
	"""Draw a card from the deck to hand"""
	# Check if hand is full
	if hand.size() >= MAX_HAND_SIZE:
		print("CardHandManager: Hand is full, cannot draw")
		return false
	
	# Check if draw pile is empty
	if draw_pile.is_empty():
		# Shuffle discard pile back into draw pile
		if discard_pile.is_empty():
			print("CardHandManager: No cards left to draw")
			return false
		
		print("CardHandManager: Draw pile empty, shuffling discard pile")
		draw_pile = discard_pile.duplicate()
		discard_pile.clear()
		shuffle_deck()
	
	# Draw the card
	var card_name = draw_pile.pop_front()
	add_card_to_hand(card_name)
	
	card_drawn.emit(card_name)
	return true

func add_card_to_hand(card_name: String):
	"""Create a card instance and add it to hand"""
	# Get card data
	var card_data = DataManager.get_card_data(card_name)
	if card_data.is_empty():
		push_error("CardHandManager: Card data not found for: " + card_name)
		return
	
	# Create card instance
	var card_instance = card_scene.instantiate()
	card_instance.setup(card_data)
	
	# Connect signals
	card_instance.card_drag_started.connect(_on_card_drag_started)
	card_instance.card_drag_ended.connect(_on_card_drag_ended)
	
	# Add to hand array
	hand.append(card_instance)
	
	# Add to UI
	if hand_container:
		hand_container.add_child(card_instance)
	
	update_hand_layout()
	hand_updated.emit()
	
	print("CardHandManager: Added card to hand: ", card_name)

func remove_card_from_hand(card: Control):
	"""Remove a card from hand (when played or discarded)"""
	var index = hand.find(card)
	if index != -1:
		hand.remove_at(index)
		hand_updated.emit()

func discard_card(card_name: String):
	"""Add a card to the discard pile"""
	discard_pile.append(card_name)
	print("CardHandManager: Discarded card: ", card_name)

func update_hand_layout():
	"""Update the visual layout of cards in hand"""
	if not hand_container:
		return
	
	# The HBoxContainer will automatically layout the cards
	# Just ensure proper spacing
	hand_container.add_theme_constant_override("separation", CARD_SPACING)

func setup_hand_ui(parent: Node):
	"""Create and setup the hand UI container"""
	print("CardHandManager: Setting up hand UI...")
	
	# Create CanvasLayer for hand
	hand_canvas_layer = CanvasLayer.new()
	hand_canvas_layer.name = "CardHandLayer"
	hand_canvas_layer.layer = 500  # High z-index to stay above game
	parent.add_child(hand_canvas_layer)
	
	# Create HBoxContainer for cards
	hand_container = HBoxContainer.new()
	hand_container.name = "HandContainer"
	hand_container.position = Vector2(60, HAND_Y_POSITION)
	hand_container.add_theme_constant_override("separation", CARD_SPACING)
	hand_canvas_layer.add_child(hand_container)
	
	print("CardHandManager: Hand UI setup complete")

func set_hand_visible(visible: bool):
	"""Show or hide the hand"""
	if hand_canvas_layer:
		hand_canvas_layer.visible = visible

func _on_card_drag_started(card: Control):
	"""Called when a card starts being dragged"""
	dragged_card = card
	print("CardHandManager: Card drag started: ", card.get_card_name())

	# Start highlighting valid targets
	highlight_valid_targets(card.get_target_type())

func update_hover_highlight():
	"""Update yellow highlight for currently hovered target during drag"""
	if not dragged_card:
		return

	# Get mouse position and convert to world space
	var screen_pos = dragged_card.get_global_mouse_position()
	var world_pos = screen_to_world_position(screen_pos)

	# Find target at current mouse position
	var target = detect_target_at_position(world_pos, dragged_card.get_target_type())

	# If hovering over a new target
	if target != null and not target.is_empty():
		# If this is a different target than before
		if hovered_target.is_empty() or hovered_target != target:
			# Clear previous hover highlight
			clear_hover_highlight()

			# Set new hover target and highlight it yellow
			hovered_target = target
			var sprite = hovered_target.get("sprite")
			if sprite:
				sprite.modulate = Color(1.5, 1.5, 0.3, 1.0)  # Yellow glow
	else:
		# Not hovering over any target - clear hover highlight
		clear_hover_highlight()

func clear_hover_highlight():
	"""Clear yellow highlight from previously hovered target"""
	if not hovered_target.is_empty():
		var sprite = hovered_target.get("sprite")
		if sprite:
			# Return to red if it's still in highlighted_targets list
			if highlighted_targets.has(hovered_target):
				sprite.modulate = Color(1.5, 0.5, 0.5, 1.0)  # Red glow
			else:
				sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal
		hovered_target = {}

func _on_card_drag_ended(card: Control, drop_position: Vector2):
	"""Called when a card is dropped"""
	dragged_card = null

	# Clear target highlights
	clear_target_highlights()

	# Transform screen position to world position (accounting for camera zoom/position)
	var world_position = screen_to_world_position(drop_position)

	# Detect target at drop position
	var target = detect_target_at_position(world_position, card.get_target_type())

	if target != null and not target.is_empty():
		# Valid target - play the card
		print("CardHandManager: Playing ", card.get_card_name(), " on target")
		play_card(card, target)
	else:
		# Invalid target - return card to hand
		print("CardHandManager: No valid target - card returned to hand")
		card.return_to_hand()

func screen_to_world_position(screen_pos: Vector2) -> Vector2:
	"""Convert screen position to world position, accounting for camera transform"""
	if not combat_scene:
		return screen_pos

	# Get camera from combat scene
	var camera = combat_scene.get_node_or_null("Camera") if combat_scene else null
	if not camera or not camera is Camera2D:
		return screen_pos

	# Transform from screen space to world space
	# Formula: world_pos = (screen_pos - viewport_center) / zoom + camera_position
	var viewport_size = combat_scene.get_viewport_rect().size
	var viewport_center = viewport_size / 2
	var camera_zoom = camera.zoom
	var camera_position = camera.position

	var world_pos = (screen_pos - viewport_center) / camera_zoom + camera_position

	return world_pos

func detect_target_at_position(position: Vector2, target_type: String):
	"""Detect valid target at the given position based on target type"""
	if not combat_scene or current_lane_index < 0:
		return null

	# Get ship manager from combat scene (for turrets only)
	var ship_manager = combat_scene.ship_manager if combat_scene else null

	# Handle multi-target types (comma-separated)
	if target_type.contains(","):
		var target_types = target_type.split(",", false)
		# Try each target type in order until we find a match
		for single_type in target_types:
			var trimmed_type = single_type.strip_edges()
			var found_target = detect_single_target_at_position(position, trimmed_type, ship_manager)
			if found_target != null and not found_target.is_empty():
				return found_target
		return null
	else:
		return detect_single_target_at_position(position, target_type, ship_manager)

func detect_single_target_at_position(position: Vector2, target_type: String, ship_manager):
	"""Detect a single target type at the given position"""
	match target_type:
		"friendly_ship":
			return find_ship_at_position(position, "player")

		"friendly_turret":
			if not ship_manager:
				return null
			return find_turret_at_position(position, "player", ship_manager)

		"enemy_ship":
			return find_ship_at_position(position, "enemy")

		"enemy_turret":
			if not ship_manager:
				return null
			return find_turret_at_position(position, "enemy", ship_manager)

		"all_friendly":
			return {"type": "all_friendly", "lane": current_lane_index}

		_:
			return null

func find_ship_at_position(position: Vector2, faction: String) -> Dictionary:
	"""Find a ship of given faction at the mouse position using grid-based detection"""
	# Ships are stored in lanes - get from combat_scene
	if not combat_scene:
		return {}

	var lanes = combat_scene.lanes if combat_scene else []
	if current_lane_index < 0 or current_lane_index >= lanes.size():
		return {}

	var lane = lanes[current_lane_index]
	var units = lane.get("units", [])

	# Convert mouse position to grid coordinates
	var grid_pos = world_pos_to_grid_pos(position, current_lane_index)

	# Check if mouse is over a valid grid cell
	if grid_pos.x < 0 or grid_pos.y < 0:
		return {}

	# Find ship at this exact grid cell
	for ship in units:
		# Ships use is_enemy (bool) instead of faction (string)
		var is_enemy = ship.get("is_enemy", false)
		var ship_faction = "enemy" if is_enemy else "player"

		if ship_faction != faction:
			continue

		var ship_row = ship.get("grid_row", -1)
		var ship_col = ship.get("grid_col", -1)

		# Check if mouse is in the same grid cell as this ship
		if ship_row >= 0 and ship_col >= 0 and grid_pos.x == ship_col and grid_pos.y == ship_row:
			return ship

	return {}

func world_pos_to_grid_pos(world_pos: Vector2, lane_index: int) -> Vector2i:
	"""Convert world position to grid coordinates for a specific lane"""
	if not combat_scene:
		return Vector2i(-1, -1)

	# Get actual lane Y position from combat scene
	var lanes = combat_scene.lanes if combat_scene else []
	if lane_index < 0 or lane_index >= lanes.size():
		return Vector2i(-1, -1)

	var lane = lanes[lane_index]
	var lane_y = lane.get("y_position", 0)

	# Grid constants (matching CombatConstants and CombatShipManager)
	var grid_x_start = 400.0  # CombatConstants.GRID_START_X
	var cell_size = 32  # CombatConstants.CELL_SIZE
	var grid_rows = 5  # CombatConstants.GRID_ROWS
	var grid_cols = 16  # CombatConstants.GRID_COLS
	var lane_height = grid_rows * cell_size

	# Calculate grid column
	var relative_x = world_pos.x - grid_x_start
	var col = int(relative_x / cell_size)

	# Calculate grid row (relative to lane top-left)
	var lane_top_y = lane_y - lane_height / 2
	var relative_y = world_pos.y - lane_top_y
	var row = int(relative_y / cell_size)

	# Validate grid bounds
	if col < 0 or col >= grid_cols or row < 0 or row >= grid_rows:
		return Vector2i(-1, -1)

	return Vector2i(col, row)

func find_turret_at_position(position: Vector2, faction: String, ship_manager) -> Dictionary:
	"""Find a turret of given faction near the position"""
	if not ship_manager:
		return {}

	# Turrets are stored differently - check turret_grid
	var turret_grid = ship_manager.turret_grid if ship_manager else []
	var detection_radius = 300.0  # Pixels - very generous for easier targeting

	for lane_row in turret_grid:
		for turret in lane_row:
			if not turret or turret.is_empty():
				continue
			
			if turret.get("faction") != faction:
				continue
			
			var turret_container = turret.get("container")
			if not turret_container:
				continue
			
			var turret_center = turret_container.global_position + turret_container.size / 2
			var distance = position.distance_to(turret_center)
			
			if distance <= detection_radius:
				return turret
	
	return {}

func play_card(card: Control, target):
	"""Play a card on a valid target"""
	var card_name = card.get_card_name()
	var card_function = card.get_card_function()

	print("CardHandManager: Playing card: ", card_name, " on target")
	print("  Target type: ", target.get("type", "unknown"))
	print("  Target current_energy BEFORE: ", target.get("current_energy", 0))

	# Execute card effect (await since some effects are coroutines)
	var success = await CardEffects.execute_card_effect(card_function, target, combat_scene)

	print("  Target current_energy AFTER: ", target.get("current_energy", 0))

	if success:
		# Remove card from hand array
		remove_card_from_hand(card)

		# Discard the card name
		discard_card(card_name)

		# Animate card to target and free it
		var target_pos = Vector2.ZERO
		if target is Dictionary and target.has("container"):
			var container = target.get("container")
			target_pos = container.global_position + container.size / 2
		else:
			target_pos = get_viewport().get_mouse_position()

		card.play_card_animation(target_pos)

		card_played_successfully.emit(card_name, target)
	else:
		# Failed to execute - return to hand
		card.return_to_hand()

func set_combat_scene(scene: Node, lane_index: int = -1):
	"""Set the current combat scene reference for target detection"""
	combat_scene = scene
	current_lane_index = lane_index
	print("CardHandManager: Combat scene set, lane: ", lane_index)

func set_cards_playable(playable: bool):
	"""Set whether cards can be played (drawn cards are always allowed)"""
	cards_playable = playable
	print("CardHandManager: Cards playable: ", playable)

func clear_hand():
	"""Clear all cards from hand (for turn reset)"""
	for card in hand:
		if is_instance_valid(card):
			card.queue_free()
	hand.clear()
	hand_updated.emit()

func get_hand_size() -> int:
	"""Get current number of cards in hand"""
	return hand.size()

func get_draw_pile_size() -> int:
	"""Get number of cards in draw pile"""
	return draw_pile.size()

func get_discard_pile_size() -> int:
	"""Get number of cards in discard pile"""
	return discard_pile.size()

func highlight_valid_targets(target_type: String):
	"""Highlight all valid targets for the given target type"""
	clear_target_highlights()

	if not combat_scene or current_lane_index < 0:
		return

	var ship_manager = combat_scene.ship_manager if combat_scene else null

	# Handle multi-target types (comma-separated)
	if target_type.contains(","):
		var target_types = target_type.split(",", false)
		# Highlight all target types
		for single_type in target_types:
			var trimmed_type = single_type.strip_edges()
			highlight_single_target_type(trimmed_type, ship_manager)
	else:
		highlight_single_target_type(target_type, ship_manager)

func highlight_single_target_type(target_type: String, ship_manager):
	"""Highlight all valid targets for a single target type"""
	match target_type:
		"friendly_ship":
			# Highlight all friendly ships in current lane
			highlight_ships_by_faction("player", ship_manager)

		"friendly_turret":
			# Highlight all friendly turrets in current lane
			if ship_manager:
				highlight_turrets_by_faction("player", ship_manager)

		"enemy_ship":
			# Highlight all enemy ships in current lane
			highlight_ships_by_faction("enemy", ship_manager)

		"enemy_turret":
			# Highlight all enemy turrets
			if ship_manager:
				highlight_turrets_by_faction("enemy", ship_manager)

		"all_friendly":
			# Highlight all friendly ships
			highlight_ships_by_faction("player", ship_manager)

func highlight_ships_by_faction(faction: String, ship_manager):
	"""Highlight all ships of given faction in current lane"""
	# Ships are stored in lanes - get from combat_scene
	if not combat_scene:
		return
	
	var lanes = combat_scene.lanes if combat_scene else []
	if current_lane_index < 0 or current_lane_index >= lanes.size():
		return
	
	var lane = lanes[current_lane_index]
	var units = lane.get("units", [])
	
	for ship in units:
		# Ships use is_enemy (bool) instead of faction (string)
		var is_enemy = ship.get("is_enemy", false)
		var ship_faction = "enemy" if is_enemy else "player"
		
		if ship_faction != faction:
			continue
		
		var sprite = ship.get("sprite")
		if sprite:
			# Add red modulation for glow effect
			sprite.modulate = Color(1.5, 0.5, 0.5, 1.0)  # Reddish glow
			highlighted_targets.append(ship)

func highlight_turrets_by_faction(faction: String, ship_manager):
	"""Highlight all turrets of given faction"""
	if not ship_manager:
		return

	var turret_grid = ship_manager.turret_grid if ship_manager else []

	for lane_row in turret_grid:
		for turret in lane_row:
			if not turret or turret.is_empty():
				continue

			if turret.get("faction") != faction:
				continue

			var sprite = turret.get("sprite")
			if sprite:
				# Add red modulation for glow effect
				sprite.modulate = Color(1.5, 0.5, 0.5, 1.0)  # Reddish glow
				highlighted_targets.append(turret)

func clear_target_highlights():
	"""Remove highlights from all targets"""
	# Clear hover highlight first
	clear_hover_highlight()

	# Clear all red highlights
	for target in highlighted_targets:
		var sprite = target.get("sprite")
		if sprite:
			# Reset to normal color
			sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

	highlighted_targets.clear()

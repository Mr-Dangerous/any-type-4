extends Node2D

## Combat_3 Main Scene
## Grid-based combat system (20 rows × 25 columns)

# Phase enum
enum Phase {
	DEPLOY,          # Initial ship deployment
	PRE_TACTICAL,    # Enemy spawn, pre-tactical abilities
	TACTICAL,        # Player draws cards, plays cards, moves ships
	PRE_COMBAT,      # Ability queue resolves
	COMBAT,          # 20-second auto-combat
	CLEANUP          # Discard cards, clear effects
}

# Current phase
var current_phase: Phase = Phase.DEPLOY

# Grid visualization
var show_grid: bool = true
var grid_overlay: Node2D = null

# All units on battlefield
var all_units: Array = []  # Array of ship dictionaries
var player_center_row: int = 10  # Row where first player ship spawned (center of deployment)
var active_scenario_width: int = 25  # Active battlefield width (from scenario)

# Camera control
const HAND_UI_HEIGHT: int = 175  # Bottom margin for card hand UI
const EDGE_SCROLL_MARGIN: int = 50  # Distance from edge to trigger scrolling
const EDGE_SCROLL_SPEED: float = 400.0  # Pixels per second
var camera_bounds_min: Vector2 = Vector2.ZERO
var camera_bounds_max: Vector2 = Vector2.ZERO
var camera_locked: bool = true  # Lock camera during deployment

# References
@onready var camera: Camera2D = $Camera
@onready var unit_container: Node2D = $UnitContainer

func _ready():
	print("Combat_3: Initializing...")

	# Initialize grid manager
	CombatGridManager.initialize_grid()
	print("Combat_3: Grid manager ready (%d×%d)" % [CombatGridManager.GRID_ROWS, CombatGridManager.GRID_COLS])

	# Create grid overlay
	create_grid_overlay()

	# Set camera to show 10-12 rows with edge scrolling
	setup_camera()

	# Start in deploy phase
	current_phase = Phase.DEPLOY
	print("Combat_3: Phase = DEPLOY")

	# Actually trigger the deploy phase
	handle_deploy_phase()

func _process(delta):
	"""Handle edge scrolling"""
	handle_edge_scrolling(delta)

func _input(event):
	"""Handle input"""
	if event.is_action_pressed("ui_cancel"):
		# Return to hangar
		get_tree().change_scene_to_file("res://scenes/Hangar.tscn")

	# Toggle grid visualization with 'G' key
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		show_grid = !show_grid
		if grid_overlay:
			grid_overlay.visible = show_grid
		print("Combat_3: Grid overlay = ", show_grid)

	# Snap camera to show most ships with Spacebar
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		snap_camera_to_ships()
		print("Combat_3: Camera snapped to ships")

func setup_camera():
	"""Setup camera with standard zoom to show ~10 rows (72px cells)"""
	var viewport_size = get_viewport_rect().size

	# Use standard zoom (1.0) - with 72px cells, viewport should show ~10 rows
	# Account for hand UI at bottom
	var visible_height = viewport_size.y - HAND_UI_HEIGHT
	camera.zoom = Vector2(1.0, 1.0)

	# Position camera at leftmost edge, centered on middle rows (row 10)
	var center_row = 10  # Middle of 20 rows (0-19)
	var start_col = 0

	# Calculate world position for center of view
	var center_world_y = CombatGridManager.grid_to_world(center_row, 0).y
	var center_world_x = CombatGridManager.grid_to_world(0, start_col).x + (viewport_size.x / 2)

	# Offset camera down slightly to account for hand UI margin
	var hand_offset = HAND_UI_HEIGHT / 2
	camera.position = Vector2(center_world_x, center_world_y - hand_offset)

	# Calculate camera bounds (using active scenario width)
	var battlefield_width = active_scenario_width * CombatGridManager.CELL_SIZE
	var battlefield_height = CombatGridManager.GRID_ROWS * CombatGridManager.CELL_SIZE

	# Min: leftmost position (starting position)
	camera_bounds_min.x = camera.position.x
	camera_bounds_min.y = CombatGridManager.grid_origin.y + (visible_height / 2)

	# Max: can scroll right to active scenario width, and scroll vertically
	camera_bounds_max.x = CombatGridManager.grid_origin.x + battlefield_width - (viewport_size.x / 2)
	camera_bounds_max.y = CombatGridManager.grid_origin.y + battlefield_height - (visible_height / 2)

	# Calculate approximate rows visible
	var rows_visible = int(visible_height / CombatGridManager.CELL_SIZE)

	print("Combat_3: Camera zoom = ", camera.zoom, " (showing ~", rows_visible, " rows)")
	print("Combat_3: Camera position = ", camera.position)
	print("Combat_3: Camera bounds X: ", camera_bounds_min.x, " to ", camera_bounds_max.x)
	print("Combat_3: Camera bounds Y: ", camera_bounds_min.y, " to ", camera_bounds_max.y)
	print("Combat_3: Viewport size = ", viewport_size, ", Visible height = ", visible_height)
	print("Combat_3: Cell size = ", CombatGridManager.CELL_SIZE, "px")

func handle_edge_scrolling(delta: float):
	"""Handle camera edge scrolling based on mouse position"""
	# Skip if camera is locked
	if camera_locked:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport_rect().size
	var scroll_vector = Vector2.ZERO

	# Check if there are units in the scroll direction
	var has_units_above = has_units_in_direction(Vector2(0, -1))
	var has_units_below = has_units_in_direction(Vector2(0, 1))
	var has_units_left = has_units_in_direction(Vector2(-1, 0))
	var has_units_right = has_units_in_direction(Vector2(1, 0))

	# Check top edge (only if units exist above)
	if mouse_pos.y < EDGE_SCROLL_MARGIN and has_units_above:
		scroll_vector.y = -1

	# Check bottom edge (only if units exist below)
	if mouse_pos.y > viewport_size.y - EDGE_SCROLL_MARGIN and has_units_below:
		scroll_vector.y = 1

	# Check left edge (only if units exist to the left)
	if mouse_pos.x < EDGE_SCROLL_MARGIN and has_units_left:
		scroll_vector.x = -1

	# Check right edge (only if units exist to the right)
	if mouse_pos.x > viewport_size.x - EDGE_SCROLL_MARGIN and has_units_right:
		scroll_vector.x = 1

	# Apply scrolling if there's any movement
	if scroll_vector.length() > 0:
		var scroll_amount = scroll_vector.normalized() * EDGE_SCROLL_SPEED * delta
		var new_camera_pos = camera.position + scroll_amount

		# Clamp to camera bounds
		new_camera_pos.x = clamp(new_camera_pos.x, camera_bounds_min.x, camera_bounds_max.x)
		new_camera_pos.y = clamp(new_camera_pos.y, camera_bounds_min.y, camera_bounds_max.y)

		camera.position = new_camera_pos

func has_units_in_direction(direction: Vector2) -> bool:
	"""Check if there are units in the given direction from current camera view"""
	if all_units.is_empty():
		return false

	# Get current camera view bounds in world coordinates
	var viewport_size = get_viewport_rect().size
	var camera_zoom = camera.zoom.x
	var view_half_width = (viewport_size.x / camera_zoom) / 2
	var view_half_height = (viewport_size.y / camera_zoom) / 2

	var view_min = camera.position - Vector2(view_half_width, view_half_height)
	var view_max = camera.position + Vector2(view_half_width, view_half_height)

	# Check each unit
	for unit in all_units:
		var unit_pos = unit["container"].position

		# Check if unit is in the scroll direction
		if direction.x < 0:  # Left
			if unit_pos.x < view_min.x:
				return true
		elif direction.x > 0:  # Right
			if unit_pos.x > view_max.x:
				return true

		if direction.y < 0:  # Up
			if unit_pos.y < view_min.y:
				return true
		elif direction.y > 0:  # Down
			if unit_pos.y > view_max.y:
				return true

	return false

func snap_camera_to_ships():
	"""Snap camera and zoom to fit all deployed ships"""
	if all_units.is_empty():
		print("Combat_3: No ships to snap to")
		return

	# Find bounding box of all ships
	var min_row = 999
	var max_row = -1
	var min_col = 999
	var max_col = -1

	for unit in all_units:
		var grid_pos = unit.get("grid_pos", Vector2i(-1, -1))
		if grid_pos.x >= 0 and grid_pos.y >= 0:
			min_row = mini(min_row, grid_pos.x)
			max_row = maxi(max_row, grid_pos.x)
			min_col = mini(min_col, grid_pos.y)
			max_col = maxi(max_col, grid_pos.y)

	# Calculate bounding box size in cells
	var row_span = max_row - min_row + 1
	var col_span = max_col - min_col + 1

	# Add padding (2 cells on each side)
	var padding_cells = 2
	row_span += padding_cells * 2
	col_span += padding_cells * 2

	# Calculate required size in pixels
	var required_width = col_span * CombatGridManager.CELL_SIZE
	var required_height = row_span * CombatGridManager.CELL_SIZE

	# Calculate zoom to fit ships in viewport
	var viewport_size = get_viewport_rect().size
	var visible_height = viewport_size.y - HAND_UI_HEIGHT

	var zoom_x = viewport_size.x / required_width
	var zoom_y = visible_height / required_height
	var target_zoom = min(zoom_x, zoom_y)

	# Clamp zoom (don't zoom in too much or out too much)
	target_zoom = clamp(target_zoom, 0.4, 1.5)

	# Calculate center of all ships
	var center_row = (min_row + max_row) / 2.0
	var center_col = (min_col + max_col) / 2.0
	var center_world = CombatGridManager.grid_to_world(int(center_row), int(center_col))

	# Account for hand UI margin
	var hand_offset = HAND_UI_HEIGHT / (2 * target_zoom)
	var target_pos = Vector2(center_world.x, center_world.y - hand_offset)

	# Animate camera transition
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(camera, "position", target_pos, 0.8)
	tween.parallel().tween_property(camera, "zoom", Vector2(target_zoom, target_zoom), 0.8)

	print("Combat_3: Ships span rows ", min_row, "-", max_row, ", cols ", min_col, "-", max_col)
	print("Combat_3: Camera zoom = ", target_zoom, " position = ", target_pos)

func create_grid_overlay():
	"""Create visual grid overlay"""
	grid_overlay = Node2D.new()
	grid_overlay.name = "GridOverlay"
	grid_overlay.z_index = -10
	add_child(grid_overlay)

	# Draw grid in _draw()
	grid_overlay.draw.connect(_draw_grid)
	grid_overlay.queue_redraw()

func _draw_grid():
	"""Draw grid lines and zone colors"""
	if not grid_overlay:
		return

	# Use active scenario width instead of full grid
	var active_cols = active_scenario_width
	var grid_width = active_cols * CombatGridManager.CELL_SIZE
	var grid_height = CombatGridManager.GRID_ROWS * CombatGridManager.CELL_SIZE

	# Draw zone backgrounds
	# Column 0: Yellow (turrets)
	var turret_rect = Rect2(
		CombatGridManager.grid_origin,
		Vector2(CombatGridManager.CELL_SIZE, grid_height)
	)
	grid_overlay.draw_rect(turret_rect, Color(1.0, 1.0, 0.0, 0.1))  # Light yellow

	# Columns 1-5: Blue (player deployment)
	var player_rect = Rect2(
		CombatGridManager.grid_origin + Vector2(CombatGridManager.CELL_SIZE, 0),
		Vector2(CombatGridManager.CELL_SIZE * 5, grid_height)
	)
	grid_overlay.draw_rect(player_rect, Color(0.0, 0.5, 1.0, 0.1))  # Light blue

	# Enemy deployment zone: Red (last 5 columns of active area)
	if active_cols > 5:
		var enemy_start_col = max(active_cols - 5, 6)  # Don't overlap with player zone
		var enemy_width = active_cols - enemy_start_col
		var enemy_rect = Rect2(
			CombatGridManager.grid_origin + Vector2(CombatGridManager.CELL_SIZE * enemy_start_col, 0),
			Vector2(CombatGridManager.CELL_SIZE * enemy_width, grid_height)
		)
		grid_overlay.draw_rect(enemy_rect, Color(1.0, 0.0, 0.0, 0.1))  # Light red

	# Draw vertical grid lines (only for active columns)
	for col in range(active_cols + 1):
		var x = CombatGridManager.grid_origin.x + col * CombatGridManager.CELL_SIZE
		var start = Vector2(x, CombatGridManager.grid_origin.y)
		var end = Vector2(x, CombatGridManager.grid_origin.y + grid_height)

		# Thicker lines for zone boundaries
		var line_width = 2.0
		var line_color = Color(0.5, 0.5, 0.5, 0.5)

		# Boundary columns: 0, 1, 6, enemy_start, active_cols
		var enemy_start_col = max(active_cols - 5, 6)
		if col == 0 or col == 1 or col == 6 or col == enemy_start_col or col == active_cols:
			line_width = 3.0
			line_color = Color(0.8, 0.8, 0.8, 0.8)

		grid_overlay.draw_line(start, end, line_color, line_width, true)

	# Draw horizontal grid lines
	for row in range(CombatGridManager.GRID_ROWS + 1):
		var y = CombatGridManager.grid_origin.y + row * CombatGridManager.CELL_SIZE
		var start = Vector2(CombatGridManager.grid_origin.x, y)
		var end = Vector2(CombatGridManager.grid_origin.x + grid_width, y)

		grid_overlay.draw_line(start, end, Color(0.5, 0.5, 0.5, 0.5), 2.0, true)  # Increased width and added antialiasing

	# Draw cell coordinates (every 5th cell for readability)
	for row in range(0, CombatGridManager.GRID_ROWS, 5):
		for col in range(0, CombatGridManager.GRID_COLS, 5):
			var cell_pos = CombatGridManager.grid_to_world(row, col)
			var label_text = "(%d,%d)" % [row, col]

			# Draw text (simplified - in full version use Label nodes)
			grid_overlay.draw_string(
				ThemeDB.fallback_font,
				cell_pos - Vector2(15, -5),
				label_text,
				HORIZONTAL_ALIGNMENT_CENTER,
				-1,
				10,
				Color(0.7, 0.7, 0.7, 0.5)
			)

# ============================================================================
# SHIP DEPLOYMENT
# ============================================================================

func deploy_initial_player_ships():
	"""Deploy player ships from Hangar data"""
	print("Combat_3: Deploying player ships from Hangar...")

	var ships_to_deploy = GameData.hangar_ships
	print("Combat_3: Found ", ships_to_deploy.size(), " ships with pilots")

	if ships_to_deploy.is_empty():
		print("Combat_3: WARNING - No ships to deploy!")
		print("Combat_3: GameData.hangar_ships is empty - did you assign pilots in Hangar?")
		return

	# Debug: print ship data
	for i in range(ships_to_deploy.size()):
		var ship = ships_to_deploy[i]
		print("Combat_3: Ship ", i, ": ", ship.get("type", "unknown"), " (speed: ", ship.get("movement_speed", 0), ")")

	# Track which rows are used per column
	var column_row_counters = {}  # column -> next_row_index

	for ship_data in ships_to_deploy:
		var movement_speed = ship_data.get("movement_speed", 2)
		var deployment_column = movement_speed  # Column = movement speed

		# Get deployment row (spiral from center)
		if not column_row_counters.has(deployment_column):
			column_row_counters[deployment_column] = 0

		var row_index = column_row_counters[deployment_column]
		var deployment_row = calculate_deployment_row(row_index)

		# Check if cell is available
		while CombatGridManager.is_cell_occupied(deployment_row, deployment_column):
			row_index += 1
			deployment_row = calculate_deployment_row(row_index)

			# Safety check - don't go beyond grid
			if deployment_row < 0 or deployment_row >= CombatGridManager.GRID_ROWS:
				print("Combat_3: ERROR - No available deployment cells!")
				return

		column_row_counters[deployment_column] = row_index + 1

		# Deploy the ship
		spawn_player_ship(ship_data, deployment_row, deployment_column)

	print("Combat_3: Deployed ", ships_to_deploy.size(), " player ships")

func calculate_deployment_row(index: int) -> int:
	"""Calculate row based on spiral pattern from center (row 10)"""
	# Spiral pattern: 10, 9, 11, 8, 12, 7, 13, 6, 14, 5, 15, 4, 16, 3, 17, 2, 18, 1, 19, 0
	var center = 10

	if index == 0:
		return center

	# Alternating above/below center
	var offset = (index + 1) / 2
	if index % 2 == 1:  # Odd index = above center
		return center - offset
	else:  # Even index = below center
		return center + offset

func spawn_player_ship(ship_data: Dictionary, row: int, col: int):
	"""Spawn a player ship at the specified grid position"""
	var ship_id = ship_data.get("type", "unknown")
	print("Combat_3: Spawning ", ship_id, " at (", row, ", ", col, ")")

	# Create ship container
	var container = Node2D.new()
	container.name = "Ship_" + ship_id + "_" + str(all_units.size())
	unit_container.add_child(container)

	# Create ship sprite (using Sprite2D for proper Node2D positioning)
	var sprite = Sprite2D.new()
	var sprite_path = ship_data.get("sprite_path", "")
	if sprite_path != "":
		sprite.texture = load(sprite_path)

	var ship_size = ship_data.get("size", 36)

	# Center the sprite on the container (Sprite2D is centered by default)
	sprite.centered = true
	sprite.position = Vector2.ZERO  # Centered on container

	# Scale sprite to fit ship_size if needed
	if sprite.texture:
		var tex_size = sprite.texture.get_size()
		var scale_factor = ship_size / max(tex_size.x, tex_size.y)
		sprite.scale = Vector2(scale_factor, scale_factor)

	sprite.rotation = 0  # Facing right

	container.add_child(sprite)

	# Create ship data dictionary
	var unit_dict = {
		"ship_id": ship_id,
		"faction": "player",
		"grid_pos": Vector2i(row, col),
		"container": container,
		"sprite": sprite,
		"current_armor": ship_data.get("armor", 100),
		"current_shield": ship_data.get("shield", 0),
		"current_energy": ship_data.get("starting_energy", 0),
		"max_armor": ship_data.get("armor", 100),
		"max_shield": ship_data.get("shield", 0),
		"max_energy": ship_data.get("energy", 100),
		"size": ship_size,
		"movement_speed": ship_data.get("movement_speed", 2),
		"assigned_pilot": ship_data.get("assigned_pilot", {}),
		"ability_queue": [],
		"status_effects": [],
		"temporary_modifiers": {},
		"has_moved_this_turn": false
	}

	# Add to units array
	all_units.append(unit_dict)

	# Occupy grid cell
	CombatGridManager.occupy_cell(row, col, unit_dict)

	# Animate deployment
	animate_ship_deployment(unit_dict, row, col)

func animate_ship_deployment(unit: Dictionary, target_row: int, target_col: int):
	"""Animate ship flying in from bottom-left to grid position"""
	var container = unit["container"]
	var viewport_height = get_viewport_rect().size.y

	# Start position: bottom-left off-screen
	var start_pos = Vector2(-50, viewport_height + 50)
	container.position = start_pos

	# Target position: grid cell center
	var target_pos = CombatGridManager.grid_to_world(target_row, target_col)

	# Calculate intermediate waypoint (fly up first, then right)
	var waypoint_y = CombatGridManager.grid_to_world(target_row - 1, 0).y if target_row > 0 else target_pos.y
	var waypoint_up = Vector2(start_pos.x, waypoint_y)
	var waypoint_right = Vector2(target_pos.x, waypoint_y)

	# Create tween for animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Phase 1: Fly straight up
	tween.tween_property(container, "position", waypoint_up, 0.8)

	# Phase 2: Turn right (rotate sprite)
	tween.parallel().tween_property(unit["sprite"], "rotation", 0, 0.2).set_delay(0.6)

	# Phase 3: Fly right to column
	tween.tween_property(container, "position", waypoint_right, 0.5)

	# Phase 4: Settle into final position
	tween.tween_property(container, "position", target_pos, 0.3)

	print("Combat_3: Animating ship from ", start_pos, " to ", target_pos)

# ============================================================================
# ENEMY DEPLOYMENT
# ============================================================================

func spawn_enemy_wave(wave_name: String):
	"""Spawn all enemies for a given wave"""
	print("Combat_3: Spawning enemy wave '", wave_name, "'")

	# Get enemy list from wave manager
	var enemies = CombatWaveManager.get_current_wave_enemies()
	if enemies.is_empty():
		print("Combat_3: WARNING - No enemies in wave '", wave_name, "'")
		return

	# Get scenario parameters
	var scenario_width = CombatWaveManager.get_scenario_width()
	var wave_width = CombatWaveManager.get_wave_width()
	print("Combat_3: Found ", enemies.size(), " enemies to spawn (scenario_width: ", scenario_width, ", wave_width: ", wave_width, ")")

	for enemy_id in enemies:
		# Get ship data from database
		if not DataManager.ships.has(enemy_id):
			push_error("Combat_3: Enemy ship_id not found in database: " + enemy_id)
			continue

		var ship_data = DataManager.ships[enemy_id]

		# Calculate deployment column (scenario_width - movement_speed)
		var movement_speed = ship_data.get("movement_speed", 2)
		var deployment_column = scenario_width - movement_speed

		# Calculate deployment row (limited by wave_width)
		var deployment_row = calculate_enemy_deployment_row(wave_width, player_center_row)

		# Collision check - retry up to 10 times
		var max_attempts = 10
		var attempts = 0
		while CombatGridManager.is_cell_occupied(deployment_row, deployment_column) and attempts < max_attempts:
			deployment_row = calculate_enemy_deployment_row(wave_width, player_center_row)
			attempts += 1

		if attempts >= max_attempts:
			push_warning("Combat_3: Could not find available cell for enemy " + enemy_id)
			continue

		# Spawn the enemy
		spawn_enemy_ship(ship_data, deployment_row, deployment_column)

	print("Combat_3: Spawned ", enemies.size(), " enemies")

func calculate_enemy_deployment_row(wave_width: int, center_row: int) -> int:
	"""Calculate deployment row limited by wave_width, centered on player deployment"""
	# Calculate row range: center ± (wave_width // 2)
	var half_width = wave_width / 2
	var min_row = center_row - half_width
	var max_row = center_row + half_width

	# Clamp to grid bounds
	min_row = maxi(0, min_row)
	max_row = mini(CombatGridManager.GRID_ROWS - 1, max_row)

	# Prefer center rows, but allow full range if needed
	# Weight distribution: center rows get higher weight
	var weights = []
	for row in range(min_row, max_row + 1):
		var distance = abs(row - center_row)
		var weight = 0.0

		if distance == 0:
			weight = 30.0  # Highest weight for center
		elif distance == 1:
			weight = 20.0
		elif distance == 2:
			weight = 15.0
		else:
			weight = 10.0  # Lower weight for edges

		weights.append(weight)

	# Select random row based on weights
	var total_weight = 0.0
	for w in weights:
		total_weight += w

	var random_value = randf() * total_weight
	var cumulative = 0.0

	for i in range(weights.size()):
		cumulative += weights[i]
		if random_value <= cumulative:
			return min_row + i

	return center_row  # Fallback to center

func spawn_enemy_ship(ship_data: Dictionary, row: int, col: int):
	"""Spawn an enemy ship at the specified grid position"""
	var ship_id = ship_data.get("ship_id", "unknown")
	print("Combat_3: Spawning enemy ", ship_id, " at (", row, ", ", col, ")")

	# Create ship container
	var container = Node2D.new()
	container.name = "Enemy_" + ship_id + "_" + str(all_units.size())
	unit_container.add_child(container)

	# Create ship sprite
	var sprite = Sprite2D.new()
	var sprite_path = ship_data.get("sprite_path", "")
	if sprite_path != "":
		sprite.texture = load(sprite_path)

	var ship_size = ship_data.get("size", 36)

	# Center sprite on container
	sprite.centered = true
	sprite.position = Vector2.ZERO

	# Scale sprite to fit ship_size
	if sprite.texture:
		var tex_size = sprite.texture.get_size()
		var scale_factor = ship_size / max(tex_size.x, tex_size.y)
		sprite.scale = Vector2(scale_factor, scale_factor)

	sprite.rotation = PI  # Face left (toward player)

	container.add_child(sprite)

	# Create enemy unit dictionary
	var unit_dict = {
		"ship_id": ship_id,
		"faction": "enemy",
		"grid_pos": Vector2i(row, col),
		"container": container,
		"sprite": sprite,
		"current_armor": ship_data.get("armor", 100),
		"current_shield": ship_data.get("shield", 0),
		"current_energy": ship_data.get("starting_energy", 0),
		"max_armor": ship_data.get("armor", 100),
		"max_shield": ship_data.get("shield", 0),
		"max_energy": ship_data.get("energy", 100),
		"size": ship_size,
		"movement_speed": ship_data.get("movement_speed", 2),
		"ability_queue": [],
		"status_effects": [],
		"temporary_modifiers": {},
		"has_moved_this_turn": false
	}

	# Add to units array
	all_units.append(unit_dict)

	# Occupy grid cell
	CombatGridManager.occupy_cell(row, col, unit_dict)

	# Animate deployment from right
	animate_enemy_deployment(unit_dict, row, col)

func animate_enemy_deployment(unit: Dictionary, target_row: int, target_col: int):
	"""Animate enemy ship flying in from right to grid position"""
	var container = unit["container"]
	var viewport_width = get_viewport_rect().size.x

	# Start position: off-screen right, aligned with target row
	var target_pos = CombatGridManager.grid_to_world(target_row, target_col)
	var start_pos = Vector2(viewport_width + 100, target_pos.y)
	container.position = start_pos

	# Create tween for animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Fly straight left to deployment column
	tween.tween_property(container, "position", target_pos, 0.8)

	print("Combat_3: Animating enemy from ", start_pos, " to ", target_pos)

# ============================================================================
# PHASE MANAGEMENT (Stub for now)
# ============================================================================

func transition_to_phase(new_phase: Phase):
	"""Transition to a new game phase"""
	print("Combat_3: Phase transition: %s → %s" % [Phase.keys()[current_phase], Phase.keys()[new_phase]])
	current_phase = new_phase

	match new_phase:
		Phase.DEPLOY:
			handle_deploy_phase()
		Phase.PRE_TACTICAL:
			handle_pre_tactical_phase()
		Phase.TACTICAL:
			handle_tactical_phase()
		Phase.PRE_COMBAT:
			handle_pre_combat_phase()
		Phase.COMBAT:
			handle_combat_phase()
		Phase.CLEANUP:
			handle_cleanup_phase()

func handle_deploy_phase():
	"""Handle initial deployment phase"""
	print("Combat_3: Deploy phase - Ready for ship deployment")

	# Deploy player ships from Hangar
	deploy_initial_player_ships()

	# Wait for player ship animations to complete
	await get_tree().create_timer(2.0).timeout

	# Load scenario to get scenario_width
	CombatWaveManager.load_scenario("test_scenario")
	var scenario_width = CombatWaveManager.get_scenario_width()
	active_scenario_width = scenario_width  # Update active width for grid/camera

	# Redraw grid with new active width
	if grid_overlay:
		grid_overlay.queue_redraw()

	# Pan camera to enemy deployment area (calculated from scenario_width)
	# Enemy column range: scenario_width - 3 to scenario_width - 1 (for movement speeds 3,2,1)
	var enemy_column_center = scenario_width - 2  # Middle of enemy deployment zone
	var enemy_view_pos = CombatGridManager.grid_to_world(10, enemy_column_center)
	var viewport_size = get_viewport_rect().size
	var hand_offset = HAND_UI_HEIGHT / 2
	var enemy_camera_pos = Vector2(enemy_view_pos.x, enemy_view_pos.y - hand_offset)

	# Animate camera to enemy area
	var camera_tween = create_tween()
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)
	camera_tween.tween_property(camera, "position", enemy_camera_pos, 1.0)
	await camera_tween.finished

	# Spawn first enemy wave (scenario already loaded above)
	var wave_name = "easy_wave_1"  # First wave from test_scenario
	spawn_enemy_wave(wave_name)

	# Wait for enemy animations to complete
	await get_tree().create_timer(1.5).timeout

	# Zoom out to fit all ships in view
	snap_camera_to_ships()

	# Wait for zoom animation to complete
	await get_tree().create_timer(1.0).timeout

	# Unlock camera for player control
	camera_locked = false
	print("Combat_3: Deployment complete - Camera unlocked")

func handle_pre_tactical_phase():
	"""Handle pre-tactical phase"""
	print("Combat_3: Pre-tactical phase")
	# TODO: Spawn enemies
	# TODO: Camera pan
	# TODO: Pre-tactical abilities

func handle_tactical_phase():
	"""Handle tactical phase"""
	print("Combat_3: Tactical phase")
	# TODO: Draw 3 cards
	# TODO: Enable card playing
	# TODO: Enable ship movement

func handle_pre_combat_phase():
	"""Handle pre-combat phase"""
	print("Combat_3: Pre-combat phase")
	# TODO: Resolve ability queue with cinematics

func handle_combat_phase():
	"""Handle 20-second combat phase"""
	print("Combat_3: Combat phase (20s)")
	# TODO: Auto-attack
	# TODO: Forward movement
	# TODO: Ship abilities

func handle_cleanup_phase():
	"""Handle cleanup phase"""
	print("Combat_3: Cleanup phase")
	# TODO: Discard cards
	# TODO: Clear temporary effects
	# TODO: Reset flags

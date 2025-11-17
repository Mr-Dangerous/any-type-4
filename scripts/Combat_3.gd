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
var first_pre_tactical: bool = true  # Track if this is the first pre-tactical phase (no wave spawn)

# Grid visualization
var show_grid: bool = true
var grid_overlay: Node2D = null
var current_mouse_grid_pos: Vector2i = Vector2i(-1, -1)  # Track mouse position in grid coords

# All units on battlefield
var all_units: Array = []  # Array of ship dictionaries
var player_center_row: int = 10  # Row where first player ship spawned (center of deployment)
var active_scenario_width: int = 25  # Active battlefield width (from scenario)

# Damage sponge pools (collective armor for each faction)
var player_sponge_pool: Dictionary = {"collective_armor": 3000, "max_armor": 3000}
var enemy_sponge_pool: Dictionary = {"collective_armor": 3000, "max_armor": 3000}
var player_sponges: Array = []
var enemy_sponges: Array = []

# Camera control
const HAND_UI_HEIGHT: int = 175  # Bottom margin for card hand UI
const EDGE_SCROLL_MARGIN: int = 50  # Distance from edge to trigger scrolling
const EDGE_SCROLL_SPEED: float = 400.0  # Pixels per second
var camera_bounds_min: Vector2 = Vector2.ZERO
var camera_bounds_max: Vector2 = Vector2.ZERO
var camera_locked: bool = true  # Lock camera during deployment

# Combat systems (no type annotations - classes don't have class_name declarations)
var projectile_manager = null
var targeting_system = null
var weapon_system = null
var status_manager = null
var health_system = null
var combo_system = null

# Combat state
var combat_active: bool = false  # Combat loop running flag
var combat_time_remaining: float = 20.0  # Combat duration countdown
var ability_cinematic_active: bool = false  # Pause flag for ability zoom

# Tactical movement drag state
var is_dragging: bool = false
var dragging_unit: Dictionary = {}
var drag_start_grid: Vector2i = Vector2i(-1, -1)
var drag_ghost: Sprite2D = null
var valid_move_cells: Array = []  # Array of Vector2i
var range_highlights: Array = []  # Array of ColorRect nodes

# References
@onready var camera: Camera2D = $Camera
@onready var unit_container: Node2D = $UnitContainer
@onready var phase_label: Label = $UILayer/PhaseLabel
@onready var end_turn_button: Button = $UILayer/EndTurnButton
@onready var wave_incoming_label: Label = $NotificationLayer/WaveIncomingLabel
@onready var countdown_label: Label = $NotificationLayer/CountdownLabel
@onready var combat_timer_container: Control = $UILayer/CombatTimerContainer
@onready var combat_timer_bar: ColorRect = $UILayer/CombatTimerContainer/TimerBar
@onready var combat_timer_label: Label = $UILayer/CombatTimerContainer/TimerLabel

func _ready():
	print("Combat_3: Initializing...")

	# Initialize grid manager
	CombatGridManager.initialize_grid()
	print("Combat_3: Grid manager ready (%d×%d)" % [CombatGridManager.GRID_ROWS, CombatGridManager.GRID_COLS])

	# Create grid overlay
	create_grid_overlay()

	# Set camera to show 10-12 rows with edge scrolling
	setup_camera()

	# Initialize CardHandManager
	CardHandManager.setup_hand_ui(self)
	CardHandManager.initialize_deck()
	CardHandManager.set_hand_visible(false)
	CardHandManager.set_cards_playable(false)
	print("Combat_3: CardHandManager initialized")

	# Initialize combat systems (using load since classes don't have class_name)
	var CombatWeaponsScript = load("res://scripts/CombatWeapons.gd")
	weapon_system = CombatWeaponsScript.new()
	weapon_system.name = "WeaponSystem"
	add_child(weapon_system)

	var CombatHealthSystemScript = load("res://scripts/CombatHealthSystem.gd")
	health_system = CombatHealthSystemScript.new(self)  # Pass combat manager reference
	health_system.name = "HealthSystem"
	add_child(health_system)

	# Set up weapon_system references (must be done after both are created)
	weapon_system.set_combat_manager(self)
	weapon_system.set_health_system(health_system)

	var CombatComboSystemScript = load("res://scripts/CombatComboSystem.gd")
	combo_system = CombatComboSystemScript.new()
	combo_system.name = "ComboSystem"
	add_child(combo_system)

	# These have class_name declarations
	projectile_manager = CombatProjectileManager.new()
	projectile_manager.name = "ProjectileManager"
	add_child(projectile_manager)
	projectile_manager.initialize(self, null)  # Initialize with Combat_3 as parent scene
	projectile_manager.health_system = health_system  # Set health system reference

	targeting_system = CombatTargetingSystem.new()
	targeting_system.name = "TargetingSystem"
	add_child(targeting_system)

	status_manager = CombatStatusEffectManager.new()
	status_manager.name = "StatusManager"
	add_child(status_manager)

	print("Combat_3: Combat systems initialized")

	# Connect End Turn button
	end_turn_button.pressed.connect(_on_end_turn_pressed)

	# Start in deploy phase
	current_phase = Phase.DEPLOY
	print("Combat_3: Phase = DEPLOY")

	# Actually trigger the deploy phase
	handle_deploy_phase()

func _process(delta):
	"""Handle edge scrolling, mouse tracking, and combat loop"""
	handle_edge_scrolling(delta)

	# Track mouse position for hover reveal effect (only during movement/deployment phases)
	if show_grid and (current_phase == Phase.DEPLOY or current_phase == Phase.TACTICAL):
		var mouse_world_pos = get_global_mouse_position()
		var new_grid_pos = CombatGridManager.world_to_grid(mouse_world_pos)

		# If mouse moved to different grid cell, redraw
		if new_grid_pos != current_mouse_grid_pos:
			current_mouse_grid_pos = new_grid_pos
			if grid_overlay:
				grid_overlay.queue_redraw()

	# Combat loop (runs during COMBAT phase)
	if current_phase == Phase.COMBAT and combat_active:
		# Skip if ability cinematic is active
		if ability_cinematic_active:
			return

		# Update combat timer
		combat_time_remaining -= delta

		# Update timer UI
		var time_percent = combat_time_remaining / 20.0
		combat_timer_bar.size.x = 600 * time_percent  # 600px = container width
		combat_timer_label.text = "%.1fs" % max(0.0, combat_time_remaining)

		# Process each alive unit
		for unit in all_units:
			if not is_unit_alive(unit):
				continue

			# Skip sponges - they don't move or attack
			if unit.get("is_sponge", false):
				continue

			# 1. Validate target (reassign if dead/invalid)
			validate_and_update_target(unit)

			# 2. Calculate distance to target
			update_target_distance(unit)

			# 3. Movement logic (faction-specific)
			var should_move = false
			if unit["faction"] == "enemy":
				# Enemies move forward if no target OR target out of range
				if unit["current_target"] == {} or unit["target_distance"] > unit["weapon_range"]:
					should_move = true
			else:
				# Players move if they have a target out of range OR should advance without target
				if unit["current_target"] != {} and unit["target_distance"] > unit["weapon_range"]:
					should_move = true
				elif should_player_advance_without_target(unit):
					should_move = true

			if should_move:
				move_unit_forward(unit, delta)
			else:
				# Ship is idle - slowly drift to center of logical grid position
				drift_to_grid_center(unit, delta)

			# 4. Update attack timer if target in range
			if unit["current_target"] != {} and unit["target_distance"] <= unit["weapon_range"]:
				update_attack_timer(unit, delta)

			# 5. Check for ability cast
			check_and_cast_ability(unit)

		# Check for combat end
		if combat_time_remaining <= 0 or check_victory_defeat():
			end_combat_phase()

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

	# Tactical movement (only during TACTICAL phase)
	if current_phase == Phase.TACTICAL:
		# Left mouse button pressed - start dragging
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not is_dragging:
				var clicked_unit = find_unit_at_mouse()
				if not clicked_unit.is_empty():
					# Start dragging
					is_dragging = true
					dragging_unit = clicked_unit
					drag_start_grid = clicked_unit.get("grid_pos", Vector2i(-1, -1))

					# Calculate valid move cells
					valid_move_cells = calculate_valid_move_cells(clicked_unit)

					# Show range highlights
					show_range_highlights(valid_move_cells)

					# Create ghost sprite
					create_drag_ghost(clicked_unit)

					print("Combat_3: Started dragging ", clicked_unit.get("ship_id", "unknown"))

		# Left mouse button released - execute move
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if is_dragging:
				# Get target grid position
				var mouse_pos = get_global_mouse_position()
				var target_grid = CombatGridManager.world_to_grid(mouse_pos)

				# Validate and execute move
				if validate_tactical_move(dragging_unit, target_grid):
					execute_tactical_move(dragging_unit, target_grid)
					print("Combat_3: Executed move to (%d, %d)" % [target_grid.x, target_grid.y])
				else:
					print("Combat_3: Invalid move, staying at (%d, %d)" % [drag_start_grid.x, drag_start_grid.y])

				# Cleanup
				destroy_drag_ghost()
				clear_range_highlights()
				is_dragging = false
				dragging_unit = {}
				drag_start_grid = Vector2i(-1, -1)
				valid_move_cells = []

		# Mouse motion while dragging - update ghost
		if event is InputEventMouseMotion and is_dragging:
			var mouse_pos = get_global_mouse_position()
			update_drag_ghost_position(mouse_pos)

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

func pan_camera_down_enemy_column():
	"""Pan camera to enemy column, zoom in, and pan down to show all spawning enemies"""
	print("Combat_3: Camera pan - Showing enemy spawn column")

	# Lock camera during cinematic
	camera_locked = true

	# Find rightmost occupied column (where enemies are spawning)
	var rightmost_col = -1
	for unit in all_units:
		if unit["faction"] == "enemy":
			rightmost_col = max(rightmost_col, unit["grid_pos"].y)

	if rightmost_col < 0:
		print("Combat_3: No enemies found, skipping camera pan")
		camera_locked = false
		return

	# Calculate camera position at top of enemy column
	var top_pos = CombatGridManager.grid_to_world(0, rightmost_col)
	var viewport_size = get_viewport_rect().size
	var hand_offset = HAND_UI_HEIGHT / 2
	var target_zoom = 1.2  # Zoom in slightly

	# Position camera at top of enemy column
	var start_camera_pos = Vector2(top_pos.x, top_pos.y + (viewport_size.y / (2 * target_zoom)) - hand_offset / target_zoom)

	# Transition to enemy column top (zoom in and pan)
	var tween1 = create_tween()
	tween1.set_ease(Tween.EASE_IN_OUT)
	tween1.set_trans(Tween.TRANS_CUBIC)
	tween1.parallel().tween_property(camera, "position", start_camera_pos, 1.0)
	tween1.parallel().tween_property(camera, "zoom", Vector2(target_zoom, target_zoom), 1.0)
	await tween1.finished

	# Calculate camera position at bottom of enemy column
	var bottom_pos = CombatGridManager.grid_to_world(CombatGridManager.GRID_ROWS - 1, rightmost_col)
	var end_camera_pos = Vector2(bottom_pos.x, bottom_pos.y - (viewport_size.y / (2 * target_zoom)) - hand_offset / target_zoom)

	# Pan down from top to bottom (2 seconds)
	var tween2 = create_tween()
	tween2.set_ease(Tween.EASE_IN_OUT)
	tween2.set_trans(Tween.TRANS_CUBIC)
	tween2.tween_property(camera, "position", end_camera_pos, 2.0)
	await tween2.finished

	# Return to tactical view (snap to all ships)
	snap_camera_to_ships()
	await get_tree().create_timer(0.8).timeout

	# Unlock camera
	camera_locked = false
	print("Combat_3: Camera pan complete")

func create_grid_overlay():
	"""Create visual grid overlay"""
	grid_overlay = Node2D.new()
	grid_overlay.name = "GridOverlay"
	grid_overlay.z_index = -10
	add_child(grid_overlay)

	# Draw grid in _draw()
	grid_overlay.draw.connect(_draw_grid)
	grid_overlay.queue_redraw()

func get_active_row_range() -> Dictionary:
	"""Get the range of rows that contain ships or are between topmost and bottommost ships"""
	if all_units.is_empty():
		return {"min_row": -1, "max_row": -1}

	var min_row = 999
	var max_row = -1

	# Find topmost and bottommost ships
	for unit in all_units:
		var row = unit["grid_pos"].x
		min_row = mini(min_row, row)
		max_row = maxi(max_row, row)

	return {"min_row": min_row, "max_row": max_row}

func get_active_col_range() -> Dictionary:
	"""Get the range of columns that contain ships or are between leftmost and rightmost ships"""
	if all_units.is_empty():
		return {"min_col": -1, "max_col": -1}

	var min_col = 999
	var max_col = -1

	# Find leftmost and rightmost ships
	for unit in all_units:
		var col = unit["grid_pos"].y
		min_col = mini(min_col, col)
		max_col = maxi(max_col, col)

	return {"min_col": min_col, "max_col": max_col}

func calculate_cell_fade_alpha(row: int, col: int, active_row_min: int, active_row_max: int, active_col_min: int, active_col_max: int, mouse_grid_pos: Vector2i) -> float:
	"""Calculate fade alpha for a cell based on active range (both row and column) and mouse proximity
	Returns 0.0 (invisible) to 1.0 (fully visible)
	"""
	# If no active range, fade everything
	if active_row_min < 0 or active_row_max < 0 or active_col_min < 0 or active_col_max < 0:
		return 0.0

	# Buffer zone: 1 cell beyond active range stays fully visible
	var row_buffer_min = active_row_min - 1
	var row_buffer_max = active_row_max + 1
	var col_buffer_min = active_col_min - 1
	var col_buffer_max = active_col_max + 1

	# Calculate row fade
	var row_alpha = 1.0
	if row < row_buffer_min or row > row_buffer_max:
		var row_distance = 0.0
		if row < row_buffer_min:
			row_distance = row_buffer_min - row
		else:
			row_distance = row - row_buffer_max
		row_alpha = exp(-row_distance * 0.8)

	# Calculate column fade
	var col_alpha = 1.0
	if col < col_buffer_min or col > col_buffer_max:
		var col_distance = 0.0
		if col < col_buffer_min:
			col_distance = col_buffer_min - col
		else:
			col_distance = col - col_buffer_max
		col_alpha = exp(-col_distance * 0.8)

	# Combine row and column fade (multiplicative - need both to be visible)
	var base_alpha = row_alpha * col_alpha

	# Check for hover reveal effect (only during movement/deployment phases)
	if mouse_grid_pos.x >= 0 and mouse_grid_pos.y >= 0:
		var hover_radius = 4.5
		# Calculate 2D distance from mouse position
		var row_dist = abs(row - mouse_grid_pos.x)
		var col_dist = abs(col - mouse_grid_pos.y)
		var hover_distance = sqrt(row_dist * row_dist + col_dist * col_dist)

		# Apply hover boost with smooth falloff
		if hover_distance < hover_radius:
			var hover_alpha = 1.0 - (hover_distance / hover_radius)
			hover_alpha = pow(hover_alpha, 2.0)  # Smooth curve
			base_alpha = max(base_alpha, hover_alpha)

	return clamp(base_alpha, 0.0, 1.0)

func _draw_grid():
	"""Draw grid lines and zone colors with 2D fade effect for unused cells"""
	if not grid_overlay:
		return

	# Use active scenario width instead of full grid
	var active_cols = active_scenario_width
	var grid_width = active_cols * CombatGridManager.CELL_SIZE
	var grid_height = CombatGridManager.GRID_ROWS * CombatGridManager.CELL_SIZE

	# Get active row and column ranges for fade calculation
	var row_range = get_active_row_range()
	var active_row_min = row_range["min_row"]
	var active_row_max = row_range["max_row"]

	var col_range = get_active_col_range()
	var active_col_min = col_range["min_col"]
	var active_col_max = col_range["max_col"]

	# Draw zone backgrounds cell-by-cell with 2D fade effect
	var enemy_start_col = max(active_cols - 5, 6)
	var enemy_width = active_cols - enemy_start_col

	for row in range(CombatGridManager.GRID_ROWS):
		var row_y = CombatGridManager.grid_origin.y + row * CombatGridManager.CELL_SIZE

		# Column 0: Yellow (turrets)
		var fade_alpha_turret = calculate_cell_fade_alpha(row, 0, active_row_min, active_row_max, active_col_min, active_col_max, current_mouse_grid_pos)
		if fade_alpha_turret > 0.01:
			var turret_rect = Rect2(
				Vector2(CombatGridManager.grid_origin.x, row_y),
				Vector2(CombatGridManager.CELL_SIZE, CombatGridManager.CELL_SIZE)
			)
			var turret_color = Color(1.0, 1.0, 0.0, 0.1 * fade_alpha_turret)
			grid_overlay.draw_rect(turret_rect, turret_color)

		# Columns 1-5: Blue (player deployment) - draw each cell individually
		for col in range(1, 6):
			var fade_alpha_player = calculate_cell_fade_alpha(row, col, active_row_min, active_row_max, active_col_min, active_col_max, current_mouse_grid_pos)
			if fade_alpha_player > 0.01:
				var player_rect = Rect2(
					Vector2(CombatGridManager.grid_origin.x + col * CombatGridManager.CELL_SIZE, row_y),
					Vector2(CombatGridManager.CELL_SIZE, CombatGridManager.CELL_SIZE)
				)
				var player_color = Color(0.0, 0.5, 1.0, 0.1 * fade_alpha_player)
				grid_overlay.draw_rect(player_rect, player_color)

		# Enemy deployment zone: Red (last 5 columns of active area) - draw each cell individually
		if active_cols > 5:
			for col in range(enemy_start_col, active_cols):
				var fade_alpha_enemy = calculate_cell_fade_alpha(row, col, active_row_min, active_row_max, active_col_min, active_col_max, current_mouse_grid_pos)
				if fade_alpha_enemy > 0.01:
					var enemy_rect = Rect2(
						Vector2(CombatGridManager.grid_origin.x + col * CombatGridManager.CELL_SIZE, row_y),
						Vector2(CombatGridManager.CELL_SIZE, CombatGridManager.CELL_SIZE)
					)
					var enemy_color = Color(1.0, 0.0, 0.0, 0.1 * fade_alpha_enemy)
					grid_overlay.draw_rect(enemy_rect, enemy_color)

	# Draw vertical grid lines (only for active columns) - draw per cell for proper 2D fade
	for col in range(active_cols + 1):
		var x = CombatGridManager.grid_origin.x + col * CombatGridManager.CELL_SIZE

		# Determine if this is a boundary column (thicker line) - reuse enemy_start_col from above
		var is_boundary = (col == 0 or col == 1 or col == 6 or col == enemy_start_col or col == active_cols)
		var line_width = 3.0 if is_boundary else 2.0
		var base_alpha = 0.8 if is_boundary else 0.5

		# Draw vertical line in segments for each row
		for row in range(CombatGridManager.GRID_ROWS + 1):
			var y_start = CombatGridManager.grid_origin.y + row * CombatGridManager.CELL_SIZE
			var y_end = y_start + CombatGridManager.CELL_SIZE

			# For the last iteration, just draw the final horizontal edge
			if row >= CombatGridManager.GRID_ROWS:
				break

			# Calculate fade alpha for this line segment (average of cells on left and right)
			var col_left = col - 1 if col > 0 else col
			var col_right = col if col < active_cols else col - 1

			var fade_left = calculate_cell_fade_alpha(row, col_left, active_row_min, active_row_max, active_col_min, active_col_max, current_mouse_grid_pos)
			var fade_right = calculate_cell_fade_alpha(row, col_right, active_row_min, active_row_max, active_col_min, active_col_max, current_mouse_grid_pos)
			var avg_fade = (fade_left + fade_right) / 2.0

			if avg_fade <= 0.01:
				continue

			var line_color = Color(0.8, 0.8, 0.8, base_alpha * avg_fade) if is_boundary else Color(0.5, 0.5, 0.5, base_alpha * avg_fade)
			grid_overlay.draw_line(Vector2(x, y_start), Vector2(x, y_end), line_color, line_width, true)

	# Draw horizontal grid lines with 2D fade - draw in segments per column
	for row in range(CombatGridManager.GRID_ROWS + 1):
		var y = CombatGridManager.grid_origin.y + row * CombatGridManager.CELL_SIZE

		# Draw horizontal line in segments for each column
		for col in range(active_cols + 1):
			var x_start = CombatGridManager.grid_origin.x + col * CombatGridManager.CELL_SIZE
			var x_end = x_start + CombatGridManager.CELL_SIZE

			# For the last iteration, just draw the final vertical edge
			if col >= active_cols:
				break

			# Calculate fade alpha (average of cells above and below this line)
			var row_above = row - 1 if row > 0 else row
			var row_below = row if row < CombatGridManager.GRID_ROWS else row - 1

			var fade_above = calculate_cell_fade_alpha(row_above, col, active_row_min, active_row_max, active_col_min, active_col_max, current_mouse_grid_pos)
			var fade_below = calculate_cell_fade_alpha(row_below, col, active_row_min, active_row_max, active_col_min, active_col_max, current_mouse_grid_pos)
			var avg_fade = (fade_above + fade_below) / 2.0

			if avg_fade <= 0.01:
				continue

			var line_color = Color(0.5, 0.5, 0.5, 0.5 * avg_fade)
			grid_overlay.draw_line(Vector2(x_start, y), Vector2(x_end, y), line_color, 2.0, true)

	# Draw cell coordinates (every 5th cell for readability) with 2D fade
	for row in range(0, CombatGridManager.GRID_ROWS, 5):
		for col in range(0, CombatGridManager.GRID_COLS, 5):
			# Calculate fade alpha for this specific cell
			var fade_alpha = calculate_cell_fade_alpha(row, col, active_row_min, active_row_max, active_col_min, active_col_max, current_mouse_grid_pos)

			if fade_alpha <= 0.01:
				continue

			var cell_pos = CombatGridManager.grid_to_world(row, col)
			var label_text = "(%d,%d)" % [row, col]

			# Draw text with 2D fade
			grid_overlay.draw_string(
				ThemeDB.fallback_font,
				cell_pos - Vector2(15, -5),
				label_text,
				HORIZONTAL_ALIGNMENT_CENTER,
				-1,
				10,
				Color(0.7, 0.7, 0.7, 0.5 * fade_alpha)
			)

# ============================================================================
# SHIP DEPLOYMENT
# ============================================================================

func deploy_initial_player_ships():
	"""Deploy player ships from Hangar data with staggered timing"""
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

	# First pass: collect all ship deployment data and calculate durations
	var ship_spawn_data = []
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

		# Calculate natural animation duration for this ship
		var speed = (CombatGridManager.CELL_SIZE * 7.5) / movement_speed
		var distance = 1000.0  # Fixed off-screen distance
		var duration = distance / speed

		# Store spawn data
		ship_spawn_data.append({
			"ship_data": ship_data,
			"row": deployment_row,
			"col": deployment_column,
			"duration": duration
		})

	# Second pass: spawn ships with staggered delays
	# Target: all ships arrive around 5 seconds
	var target_duration = 5.0

	for spawn_info in ship_spawn_data:
		# Calculate delay so ship arrives at target_duration
		var delay = max(0.0, target_duration - spawn_info["duration"])

		# Deploy the ship with calculated delay
		spawn_player_ship(spawn_info["ship_data"], spawn_info["row"], spawn_info["col"], delay)

	print("Combat_3: Deployed ", ship_spawn_data.size(), " player ships with staggered timing (target: ", target_duration, "s)")

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

func spawn_player_ship(ship_data: Dictionary, row: int, col: int, start_delay: float = 0.0):
	"""Spawn a player ship at the specified grid position with optional start delay"""
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
		# Weapon stats
		"num_attacks": ship_data.get("num_projectiles", 1),
		"damage": ship_data.get("damage", 10),
		"attack_speed": ship_data.get("attack_speed", 1.0),
		"weapon_range": ship_data.get("weapon_range", 3),
		"reinforced_armor": ship_data.get("reinforced_armor", 0),
		"accuracy": ship_data.get("accuracy", 100),
		"evasion": ship_data.get("evasion", 0),
		# Ability stats
		"ability_name": ship_data.get("ability", ""),
		"ability_function": ship_data.get("ability_function", ""),
		"ability_description": ship_data.get("ability_description", ""),
		# Other properties
		"ability_queue": [],
		"status_effects": [],
		"temporary_modifiers": {},
		"has_moved_this_turn": false,
		"movement_used_this_turn": 0  # Track distance moved in tactical phase
	}

	# Add to units array
	all_units.append(unit_dict)

	# Occupy grid cell
	CombatGridManager.occupy_cell(row, col, unit_dict)

	# Animate deployment with start delay
	animate_ship_deployment(unit_dict, row, col, start_delay)

func animate_ship_deployment(unit: Dictionary, target_row: int, target_col: int, start_delay: float = 0.0):
	"""Animate player ship flying in from left to grid position with optional delay"""
	var container = unit["container"]
	var movement_speed = unit.get("movement_speed", 2)

	# Start position: far off-screen left, aligned with target row
	var target_pos = CombatGridManager.grid_to_world(target_row, target_col)
	var start_pos = Vector2(target_pos.x - 1000, target_pos.y)  # Start 1000px off-screen left
	container.position = start_pos

	# Calculate animation duration based on movement speed (same as enemies)
	# Speed formula: (CELL_SIZE * 7.5) / movement_speed pixels per second
	var speed = (CombatGridManager.CELL_SIZE * 7.5) / movement_speed  # pixels per second (1.5x faster)
	var distance = start_pos.distance_to(target_pos)
	var duration = distance / speed

	# Create tween for animation with optional delay
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Fly straight right to deployment column (after delay)
	if start_delay > 0:
		tween.tween_property(container, "position", target_pos, duration).set_delay(start_delay)
		print("Combat_3: Animating player ship from ", start_pos, " to ", target_pos, " (speed: ", movement_speed, ", duration: ", "%.2f" % duration, "s, delay: ", "%.2f" % start_delay, "s)")
	else:
		tween.tween_property(container, "position", target_pos, duration)
		print("Combat_3: Animating player ship from ", start_pos, " to ", target_pos, " (speed: ", movement_speed, ", duration: ", "%.2f" % duration, "s)")

# ============================================================================
# ENEMY DEPLOYMENT
# ============================================================================

func spawn_enemy_wave(wave_name: String):
	"""Spawn all enemies for a given wave with staggered start times"""
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

	# First pass: collect all enemy data and calculate their natural durations
	var enemy_spawn_data = []
	var slowest_duration = 0.0

	for enemy_id in enemies:
		# Get ship data from database
		if not DataManager.ships.has(enemy_id):
			push_error("Combat_3: Enemy ship_id not found in database: " + enemy_id)
			continue

		var ship_data = DataManager.ships[enemy_id]

		# Calculate deployment position
		var movement_speed = ship_data.get("movement_speed", 2)
		var deployment_column = scenario_width - movement_speed
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

		# Calculate natural animation duration for this ship
		var speed = (CombatGridManager.CELL_SIZE * 7.5) / movement_speed
		var distance = 1000.0  # Fixed off-screen distance
		var duration = distance / speed

		slowest_duration = max(slowest_duration, duration)

		# Store spawn data
		enemy_spawn_data.append({
			"ship_data": ship_data,
			"row": deployment_row,
			"col": deployment_column,
			"duration": duration
		})

	# Second pass: spawn enemies with staggered delays
	# Target: all ships arrive around 5 seconds
	var target_duration = 5.0

	for spawn_info in enemy_spawn_data:
		# Calculate delay so ship arrives at target_duration
		var delay = max(0.0, target_duration - spawn_info["duration"])

		# Spawn the enemy with calculated delay
		spawn_enemy_ship(spawn_info["ship_data"], spawn_info["row"], spawn_info["col"], delay)

	print("Combat_3: Spawned ", enemy_spawn_data.size(), " enemies with staggered timing (target: ", target_duration, "s)")

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

func spawn_enemy_ship(ship_data: Dictionary, row: int, col: int, start_delay: float = 0.0):
	"""Spawn an enemy ship at the specified grid position with optional start delay"""
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
		# Weapon stats
		"num_attacks": ship_data.get("num_projectiles", 1),
		"damage": ship_data.get("damage", 10),
		"attack_speed": ship_data.get("attack_speed", 1.0),
		"weapon_range": ship_data.get("weapon_range", 3),
		"reinforced_armor": ship_data.get("reinforced_armor", 0),
		"accuracy": ship_data.get("accuracy", 100),
		"evasion": ship_data.get("evasion", 0),
		# Ability stats
		"ability_name": ship_data.get("ability", ""),
		"ability_function": ship_data.get("ability_function", ""),
		"ability_description": ship_data.get("ability_description", ""),
		# Other properties
		"ability_queue": [],
		"status_effects": [],
		"temporary_modifiers": {},
		"has_moved_this_turn": false,
		"movement_used_this_turn": 0  # Track distance moved in tactical phase
	}

	# Occupy grid cell (check if already occupied first)
	if CombatGridManager.is_cell_occupied(row, col):
		push_warning("Combat_3: Cell (%d, %d) already occupied during spawn, finding adjacent cell" % [row, col])
		# Try to find adjacent cell
		var found = false
		for offset in [1, -1, 2, -2]:
			var new_row = row + offset
			if new_row >= 0 and new_row < CombatGridManager.GRID_ROWS:
				if not CombatGridManager.is_cell_occupied(new_row, col):
					row = new_row
					unit_dict["grid_pos"] = Vector2i(row, col)
					found = true
					print("Combat_3: Moved enemy to adjacent row: ", row)
					break
		if not found:
			push_error("Combat_3: Could not find adjacent cell for enemy at (%d, %d)" % [row, col])
			# Clean up and return (don't spawn this ship)
			container.queue_free()
			return

	# Add to units array
	all_units.append(unit_dict)

	# Occupy grid cell
	CombatGridManager.occupy_cell(row, col, unit_dict)

	# Animate deployment from right with start delay
	animate_enemy_deployment(unit_dict, row, col, start_delay)

func animate_enemy_deployment(unit: Dictionary, target_row: int, target_col: int, start_delay: float = 0.0):
	"""Animate enemy ship flying in from right to grid position with optional delay"""
	var container = unit["container"]
	var movement_speed = unit.get("movement_speed", 2)

	# Start position: far off-screen right, aligned with target row
	var target_pos = CombatGridManager.grid_to_world(target_row, target_col)
	var start_pos = Vector2(target_pos.x + 1000, target_pos.y)  # Start 1000px off-screen right
	container.position = start_pos

	# Calculate animation duration based on movement speed (50% faster)
	# Speed formula: (CELL_SIZE * 7.5) / movement_speed pixels per second
	var speed = (CombatGridManager.CELL_SIZE * 7.5) / movement_speed  # pixels per second (1.5x faster)
	var distance = start_pos.distance_to(target_pos)
	var duration = distance / speed

	# Create tween for animation with optional delay
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Fly straight left to deployment column (after delay)
	if start_delay > 0:
		tween.tween_property(container, "position", target_pos, duration).set_delay(start_delay)
		print("Combat_3: Animating enemy from ", start_pos, " to ", target_pos, " (speed: ", movement_speed, ", duration: ", "%.2f" % duration, "s, delay: ", "%.2f" % start_delay, "s)")
	else:
		tween.tween_property(container, "position", target_pos, duration)
		print("Combat_3: Animating enemy from ", start_pos, " to ", target_pos, " (speed: ", movement_speed, ", duration: ", "%.2f" % duration, "s)")

# ============================================================================
# DAMAGE SPONGE SYSTEM
# ============================================================================

func spawn_damage_sponges():
	"""Spawn damage sponges for both factions in all active rows"""
	var row_range = get_active_row_range()
	var min_row = row_range["min_row"]
	var max_row = row_range["max_row"]

	# Player sponges in column 0 (leftmost, yellow turret zone)
	for row in range(min_row, max_row + 1):
		spawn_sponge("player", row, 0)

	# Enemy sponges in last column of scenario
	var enemy_col = active_scenario_width - 1
	for row in range(min_row, max_row + 1):
		spawn_sponge("enemy", row, enemy_col)

func spawn_sponge(faction: String, row: int, col: int):
	"""Spawn a single damage sponge at the specified grid position"""
	# Create Node2D container for sponge
	var container = Node2D.new()
	container.name = "Sponge_" + faction + "_" + str(row)

	# Create emoji label
	var label = Label.new()
	label.text = "🧽"
	label.add_theme_font_size_override("font_size", 36)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(48, 48)
	container.add_child(label)

	# Position at grid cell
	var world_pos = CombatGridManager.grid_to_world(row, col)
	container.position = world_pos

	# Add to scene
	unit_container.add_child(container)

	# Create sponge dictionary
	var sponge_armor_value = player_sponge_pool["collective_armor"] if faction == "player" else enemy_sponge_pool["collective_armor"]
	var sponge_dict = {
		"ship_id": "sponge_" + faction + "_" + str(row),
		"type": "damage_sponge",
		"faction": faction,
		"is_sponge": true,  # Flag for detection
		"grid_pos": Vector2i(row, col),
		"container": container,
		"sprite": container,  # Point to container for projectile targeting
		"size": 48,
		"current_armor": sponge_armor_value,
		"max_armor": 3000,
		"current_shield": 0,
		"max_shield": 0,
		"current_energy": 0,
		"max_energy": 0
	}

	# Add to arrays
	all_units.append(sponge_dict)
	if faction == "player":
		player_sponges.append(sponge_dict)
	else:
		enemy_sponges.append(sponge_dict)

	# Occupy grid cell
	CombatGridManager.occupy_cell(row, col, sponge_dict)

	# Create health bar
	health_system.create_health_bar(container, 48, 0, 3000)

	print("Combat_3: Spawned ", faction, " sponge at (", row, ", ", col, ")")

func apply_sponge_damage(sponge: Dictionary, damage: int) -> Dictionary:
	"""
	Apply damage to a sponge's collective armor pool.

	This differs from normal damage in that:
	- Damage is applied to the faction's collective pool (player_sponge_pool or enemy_sponge_pool)
	- ALL sponges of that faction are updated to match the pool's current_armor
	- All sponge health bars are updated synchronously
	- If pool reaches 0, all sponges are destroyed

	Args:
		sponge: The sponge dictionary that was hit
		damage: Amount of damage to apply

	Returns:
		Dictionary: {
			"armor_damage": int - Actual damage dealt to pool
		}
	"""
	var damage_breakdown = {
		"armor_damage": 0
	}

	if sponge.is_empty() or not sponge.get("is_sponge", false):
		return damage_breakdown

	# Identify which pool to damage based on faction
	var faction = sponge.get("faction", "")
	var pool: Dictionary
	var sponges_array: Array

	if faction == "player":
		pool = player_sponge_pool
		sponges_array = player_sponges
	elif faction == "enemy":
		pool = enemy_sponge_pool
		sponges_array = enemy_sponges
	else:
		print("ERROR: Unknown sponge faction: ", faction)
		return damage_breakdown

	# Apply damage to collective pool
	var current_armor = pool.get("collective_armor", 0)
	var actual_damage = min(current_armor, damage)
	pool["collective_armor"] = max(0, current_armor - actual_damage)
	damage_breakdown["armor_damage"] = actual_damage

	print("  ", faction.to_upper(), " sponge pool damaged: -", actual_damage, " (", pool["collective_armor"], " remaining)")

	# Update ALL sponges of this faction to match the pool
	for sp in sponges_array:
		sp["current_armor"] = pool["collective_armor"]
		health_system.update_health_bar(sp)

	# Check if pool is destroyed
	if pool["collective_armor"] <= 0:
		print("  ", faction.to_upper(), " SPONGE POOL DESTROYED!")

		# Destroy all sponges of this faction
		for sp in sponges_array.duplicate():  # Duplicate to avoid modifying array during iteration
			# Remove from all_units
			all_units.erase(sp)

			# Free grid cell
			CombatGridManager.free_cell(sp["grid_pos"].x, sp["grid_pos"].y)

			# Destroy visual container
			if sp.has("container") and sp["container"] != null:
				sp["container"].queue_free()

		# Clear the sponge array
		sponges_array.clear()

	return damage_breakdown

# ============================================================================
# PHASE MANAGEMENT (Stub for now)
# ============================================================================

func transition_to_phase(new_phase: Phase):
	"""Transition to a new game phase"""
	print("Combat_3: Phase transition: %s → %s" % [Phase.keys()[current_phase], Phase.keys()[new_phase]])
	current_phase = new_phase

	# Update phase label
	if phase_label:
		match new_phase:
			Phase.DEPLOY:
				phase_label.text = "DEPLOY PHASE"
			Phase.PRE_TACTICAL:
				phase_label.text = "PRE-TACTICAL PHASE"
			Phase.TACTICAL:
				phase_label.text = "TACTICAL PHASE"
			Phase.PRE_COMBAT:
				phase_label.text = "PRE-COMBAT PHASE"
			Phase.COMBAT:
				phase_label.text = "COMBAT PHASE"
			Phase.CLEANUP:
				phase_label.text = "CLEANUP PHASE"

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

	# Wait for player ship animations to complete (~5 seconds with staggered timing)
	await get_tree().create_timer(5.0).timeout

	# Load scenario to get scenario_width
	# Use scenario from GameData (set by StarMap combat node), fallback to test_scenario
	var scenario_name = GameData.current_scenario if GameData.current_scenario != "" else "test_scenario"
	print("Combat_3: Loading scenario: ", scenario_name)
	CombatWaveManager.load_scenario(scenario_name)
	var scenario_width = CombatWaveManager.get_scenario_width()
	active_scenario_width = scenario_width  # Update active width for grid/camera

	# Update enemy sponge pool armor from scenario
	var sponge_armor = CombatWaveManager.get_damage_sponge_armor()
	enemy_sponge_pool["collective_armor"] = sponge_armor
	enemy_sponge_pool["max_armor"] = sponge_armor
	print("Combat_3: Enemy damage sponge armor set to: ", sponge_armor)

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

	# Spawn damage sponges now that all ships are deployed
	print("Combat_3: Spawning damage sponges...")
	spawn_damage_sponges()

	# Zoom out to fit all ships in view
	snap_camera_to_ships()

	# Wait for zoom animation to complete
	await get_tree().create_timer(1.0).timeout

	# Unlock camera for player control
	camera_locked = false
	print("Combat_3: Deployment complete - Camera unlocked")

	# Transition to pre-tactical phase
	transition_to_phase(Phase.PRE_TACTICAL)

func handle_pre_tactical_phase():
	"""Handle pre-tactical phase - spawn enemies, camera pan, pre-tactical abilities"""
	print("Combat_3: Pre-tactical phase")

	# A. Wave Spawning (skip if this is the first pre-tactical phase)
	if not first_pre_tactical:
		print("Combat_3: Spawning next wave...")

		# Advance to next wave
		CombatWaveManager.advance_wave()

		# Get current wave name (format: "scenario_wave_N")
		var scenario_name = CombatWaveManager.current_scenario_name
		var wave_index = CombatWaveManager.current_wave_index
		var wave_name = scenario_name + "_wave_" + str(wave_index)

		# Spawn the wave
		spawn_enemy_wave(wave_name)

		# Show "WAVE INCOMING!" with countdown timer
		wave_incoming_label.visible = true
		countdown_label.visible = true

		# Countdown from 1.5 seconds (ships will still be gliding in during camera pan)
		var countdown_time = 1.5
		var countdown_step = 0.1

		while countdown_time > 0:
			countdown_label.text = "%.1f" % countdown_time
			await get_tree().create_timer(countdown_step).timeout
			countdown_time -= countdown_step

		# Hide countdown labels
		wave_incoming_label.visible = false
		countdown_label.visible = false

		# B. Camera Pan Animation
		await pan_camera_down_enemy_column()
	else:
		print("Combat_3: First pre-tactical phase - skipping wave spawn")

		# Show "WAVE INCOMING!" for first wave too
		wave_incoming_label.visible = true
		countdown_label.visible = true

		# Countdown from 1.5 seconds (ships will still be gliding in during camera pan)
		var countdown_time = 1.5
		var countdown_step = 0.1

		while countdown_time > 0:
			countdown_label.text = "%.1f" % countdown_time
			await get_tree().create_timer(countdown_step).timeout
			countdown_time -= countdown_step

		# Hide countdown labels
		wave_incoming_label.visible = false
		countdown_label.visible = false

		# Still do camera pan to show existing enemies
		await pan_camera_down_enemy_column()
		first_pre_tactical = false  # Mark that we've done the first pre-tactical phase

	# C. Pre-Tactical Ability Stack Resolution
	print("Combat_3: Resolving pre-tactical abilities...")
	var abilities_executed = 0

	# Iterate through all units and check for pre-tactical abilities
	for unit in all_units:
		# For now, units don't have pre-tactical abilities yet
		# This will be implemented when we add cards/abilities that trigger at start of tactical phase
		# Example: if unit.has("pre_tactical_abilities") and not unit["pre_tactical_abilities"].is_empty():
		pass

	# If abilities were executed, show we're done
	if abilities_executed > 0:
		print("Combat_3: Executed ", abilities_executed, " pre-tactical abilities")
		await get_tree().create_timer(1.0).timeout

	# D. Transition to Tactical Phase
	print("Combat_3: Pre-tactical phase complete, transitioning to tactical phase...")
	await get_tree().create_timer(1.0).timeout  # Wait 1 second before transition
	transition_to_phase(Phase.TACTICAL)

func handle_tactical_phase():
	"""Handle tactical phase - draw cards, allow card playing and ship movement"""
	print("Combat_3: Tactical phase - Drawing cards and enabling play")

	# Set combat scene reference for CardHandManager
	CardHandManager.set_combat_scene(self)

	# Draw 3 cards
	for i in range(3):
		var success = CardHandManager.draw_card()
		if not success:
			print("Combat_3: Could not draw card ", i + 1, " (hand full or deck empty)")
			break

	# Enable card playing and show hand
	CardHandManager.set_cards_playable(true)
	CardHandManager.set_hand_visible(true)

	# Shift camera down in world space to make ships appear higher on screen
	# Target: center lane (row 10) should be at ~1/3 from top of visible area
	var card_compensation_offset = 175.0  # Offset when cards are visible at bottom
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(camera, "position:y", camera.position.y + card_compensation_offset, 0.3)

	# Show End Turn button
	end_turn_button.visible = true

	# TODO: Enable ship movement (drag-and-drop)
	# Now waiting for player to click "End Turn" button

func _on_end_turn_pressed():
	"""Handle End Turn button press - transition to pre-combat phase"""
	print("Combat_3: End Turn button pressed")

	# Hide End Turn button
	end_turn_button.visible = false

	# Disable card playing
	CardHandManager.set_cards_playable(false)

	# Transition to pre-combat phase
	transition_to_phase(Phase.PRE_COMBAT)

func handle_pre_combat_phase():
	"""Handle pre-combat phase - resolve ability queue"""
	print("Combat_3: Pre-combat phase")

	# TODO: Resolve ability queue with cinematics
	# Placeholder: Just clear ability queues for now
	for unit in all_units:
		unit["ability_queue"] = []

	print("Combat_3: Ability queue cleared (placeholder)")

	# Wait 1 second
	await get_tree().create_timer(1.0).timeout

	# Show "COMBAT BEGINNING!" notification
	wave_incoming_label.text = "COMBAT BEGINNING!"
	wave_incoming_label.add_theme_color_override("font_color", Color(1, 0, 0, 1))  # Red color
	wave_incoming_label.visible = true

	# Show notification for 1.5 seconds
	await get_tree().create_timer(1.5).timeout

	# Hide notification
	wave_incoming_label.visible = false
	wave_incoming_label.text = "WAVE INCOMING!"  # Reset for next time
	wave_incoming_label.add_theme_color_override("font_color", Color(1, 0.6, 0, 1))  # Reset to orange

	# Transition to combat phase
	transition_to_phase(Phase.COMBAT)

func handle_combat_phase():
	"""Handle 20-second combat phase - auto-combat with movement, attacks, and abilities"""
	print("Combat_3: Combat phase (20s)")

	# Initialize combat state
	combat_active = true
	combat_time_remaining = 20.0
	ability_cinematic_active = false

	# Show combat timer UI
	combat_timer_container.visible = true
	combat_timer_bar.size.x = 600  # Full width at start
	combat_timer_label.text = "20.0s"

	# Initialize each unit for combat
	for unit in all_units:
		# Calculate movement speed in pixels/second
		var movement_speed = unit.get("movement_speed", 2)
		unit["movement_pixels_per_second"] = (CombatGridManager.CELL_SIZE * movement_speed) / 5.0

		# Get weapon range from ship data (default 3 cells if not specified)
		unit["weapon_range"] = unit.get("weapon_range", 3)

		# Initialize attack timer (start ready to attack)
		var attack_speed = unit.get("attack_speed", 1.0)
		unit["attack_timer"] = 0.0  # Start at 0 so ships can fire immediately when in range

		# Initialize targeting
		unit["current_target"] = {}
		unit["target_distance"] = -1

		# Assign initial target
		assign_target_to_unit(unit)

		# Create health bar if not already present
		if not unit.has("health_bar_container"):
			health_system.create_health_bar(
				unit["container"],
				unit["size"],
				unit.get("max_shield", 0),
				unit.get("max_armor", 100)
			)
			unit["health_bar_container"] = true  # Mark as created

	print("Combat_3: Combat initialized - %d units ready" % all_units.size())

	# Combat loop runs in _process(delta) until combat_active = false
	# Wait for combat to complete
	while combat_active:
		await get_tree().process_frame

	print("Combat_3: Combat phase complete")
	transition_to_phase(Phase.CLEANUP)

func handle_cleanup_phase():
	"""Handle cleanup phase - clear effects and prepare for next turn"""
	print("Combat_3: Cleanup phase")

	# Clear all cards from hand (cards go to discard pile)
	CardHandManager.clear_hand()

	# Hide hand UI
	CardHandManager.set_hand_visible(false)

	# Shift camera back up in world space now that cards are hidden
	var card_compensation_offset = 80.0  # Must match the offset used in tactical phase
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(camera, "position:y", camera.position.y - card_compensation_offset, 0.3)

	# Reset movement flags for all units
	for unit in all_units:
		unit["has_moved_this_turn"] = false
		unit["movement_used_this_turn"] = 0  # Reset movement budget
		# Clear temporary modifiers
		unit["temporary_modifiers"] = {}
		# Clear ability queues (when we implement them)
		unit["ability_queue"] = []

	# TODO: Visual notification that effects were cleared

	print("Combat_3: Cleanup complete - checking victory/defeat")

	# Check if combat should end (victory/defeat)
	if enemy_sponge_pool["collective_armor"] <= 0:
		print("Combat_3: VICTORY - Enemy damage sponge destroyed!")
		await get_tree().create_timer(2.0).timeout
		GameData.player_locked = false
		GameData.current_scenario = ""
		print("Combat_3: Returning to StarMap after victory")
		get_tree().change_scene_to_file("res://scenes/StarMap.tscn")
		return

	if player_sponge_pool["collective_armor"] <= 0:
		print("Combat_3: DEFEAT - Player damage sponge destroyed!")
		await get_tree().create_timer(2.0).timeout
		GameData.player_locked = false
		GameData.current_scenario = ""
		print("Combat_3: Returning to StarMap after defeat")
		get_tree().change_scene_to_file("res://scenes/StarMap.tscn")
		return

	print("Combat_3: Both factions alive - starting next turn")

	# Wait a moment then transition to next pre-tactical phase
	await get_tree().create_timer(0.5).timeout
	transition_to_phase(Phase.PRE_TACTICAL)

# ============================================================================
# COMBAT HELPER FUNCTIONS
# ============================================================================

func find_sponge_in_row(attacker: Dictionary, target_faction: String) -> Dictionary:
	"""
	Find a damage sponge in the same row as the attacker.

	Args:
		attacker: The unit looking for a sponge target
		target_faction: The faction of sponge to find ("player" or "enemy")

	Returns:
		Dictionary: The sponge in the attacker's row, or {} if none found
	"""
	if attacker.is_empty() or not attacker.has("grid_pos"):
		return {}

	var attacker_row = attacker["grid_pos"].x

	# Search through sponges of the target faction
	var sponges_array = player_sponges if target_faction == "player" else enemy_sponges

	for sponge in sponges_array:
		# Check if sponge is in same row
		if sponge.get("grid_pos", Vector2i(-1, -1)).x == attacker_row:
			# Check if sponge is still alive (pool has armor)
			if sponge.get("current_armor", 0) > 0:
				return sponge

	return {}

func assign_target_to_unit(unit: Dictionary):
	"""Assign a target to the unit using row-locked delta targeting
	Delta targeting priority: Ship in row → Sponge in row → Idle (no mothership/boss)"""
	var unit_faction = unit.get("faction", "player")
	var target_faction = "enemy" if unit_faction == "player" else "player"
	var unit_row = unit["grid_pos"].x
	var unit_col = unit["grid_pos"].y

	# Priority 1: Find closest ship in same row
	var closest_target = {}
	var closest_distance = 999999

	for potential_target in all_units:
		# Skip if wrong faction
		if potential_target.get("faction", "") != target_faction:
			continue

		# Skip sponges in this loop (we check them later)
		if potential_target.get("is_sponge", false):
			continue

		# Skip if not alive
		if not is_unit_alive(potential_target):
			continue

		# Skip if not in same row
		if potential_target["grid_pos"].x != unit_row:
			continue

		# Calculate column distance
		var distance = abs(potential_target["grid_pos"].y - unit_col)

		if distance < closest_distance:
			closest_distance = distance
			closest_target = potential_target

	# Priority 1: Target ship in row if found
	if not closest_target.is_empty():
		unit["current_target"] = closest_target
		# Reset attack timer when new target assigned
		var attack_speed = unit.get("attack_speed", 1.0)
		unit["attack_timer"] = 1.0 / attack_speed
		print("Combat_3: Unit %s targeting ship %s" % [unit.get("ship_id", "unknown"), closest_target.get("ship_id", "unknown")])
		return

	# Priority 2: Target sponge in row if no ship found (delta targeting)
	var sponge_target = find_sponge_in_row(unit, target_faction)
	if not sponge_target.is_empty():
		unit["current_target"] = sponge_target
		# Reset attack timer when new target assigned
		var attack_speed = unit.get("attack_speed", 1.0)
		unit["attack_timer"] = 1.0 / attack_speed
		print("Combat_3: Unit %s targeting sponge in row %d" % [unit.get("ship_id", "unknown"), unit_row])
		return

	# Priority 3: No valid target - go idle (delta targeting: no mothership/boss fallback)
	unit["current_target"] = {}
	unit["target_distance"] = -1
	print("Combat_3: Unit %s has no valid target (stopping)" % unit.get("ship_id", "unknown"))

func validate_and_update_target(unit: Dictionary):
	"""Check if current target is still valid, reassign if not"""
	var current_target = unit.get("current_target", {})

	# No target assigned
	if current_target.is_empty():
		return

	# Check if target is still alive
	if not is_unit_alive(current_target):
		print("Combat_3: Target dead, reassigning for unit %s" % unit.get("ship_id", "unknown"))
		assign_target_to_unit(unit)
		return

	# Check if target is still in same row (for gamma targeting)
	if current_target["grid_pos"].x != unit["grid_pos"].x:
		print("Combat_3: Target changed rows, reassigning for unit %s" % unit.get("ship_id", "unknown"))
		assign_target_to_unit(unit)
		return

func update_target_distance(unit: Dictionary):
	"""Calculate distance to target in grid cells (column-wise)"""
	var current_target = unit.get("current_target", {})

	if current_target.is_empty():
		unit["target_distance"] = -1
		return

	# Calculate column distance (same row already verified by targeting)
	var unit_col = unit["grid_pos"].y
	var target_col = current_target["grid_pos"].y
	unit["target_distance"] = abs(target_col - unit_col)

func should_player_advance_without_target(player_unit: Dictionary) -> bool:
	"""Check if player ship should advance even without a target
	Returns true if ship has no target BUT other player ships do have targets"""
	# If this ship has a target, let normal logic handle it
	if player_unit["current_target"] != {}:
		return false

	# Check if ANY other player ship has a target
	for other_unit in all_units:
		if other_unit.get("faction", "") == "player" and is_unit_alive(other_unit):
			if other_unit != player_unit and other_unit.get("current_target", {}) != {}:
				# Another player has a target - this ship should advance
				# Check if already at weapon range from theoretical enemy position
				var weapon_range = player_unit.get("weapon_range", 3)
				var current_col = player_unit["grid_pos"].y
				var scenario_width = CombatWaveManager.get_scenario_width()
				var theoretical_enemy_col = scenario_width - weapon_range

				# Only advance if not yet at range
				if current_col < theoretical_enemy_col:
					return true

	return false

func move_unit_forward(unit: Dictionary, delta: float):
	"""Move unit forward toward target at movement_speed-based rate
	Enemies can also move vertically to change lanes toward players"""
	var container = unit["container"]
	var faction = unit.get("faction", "player")

	# Calculate movement this frame
	var distance_px = unit["movement_pixels_per_second"] * delta

	# Determine horizontal direction based on faction
	var horizontal_dir = 1.0 if faction == "player" else -1.0  # Player moves right, enemy moves left

	# Enemies only move horizontally (no lane changes)
	var vertical_dir = 0.0

	# Calculate new position (horizontal movement only)
	var current_pos = container.position
	var movement_vector = Vector2(horizontal_dir * distance_px, 0)
	var new_pos = current_pos + movement_vector

	# Update container position
	container.position = new_pos

	# Check if crossed cell boundary (row or column)
	var old_grid_pos = CombatGridManager.world_to_grid(current_pos)
	var new_grid_pos = CombatGridManager.world_to_grid(new_pos)

	# If grid position changed, update grid
	if old_grid_pos != new_grid_pos:
		# Check if new cell is occupied
		if not CombatGridManager.is_cell_occupied(new_grid_pos.x, new_grid_pos.y):
			# Free old cell
			CombatGridManager.free_cell(unit["grid_pos"].x, unit["grid_pos"].y)

			# Occupy new cell
			CombatGridManager.occupy_cell(new_grid_pos.x, new_grid_pos.y, unit)

			# Update unit grid position (logical position only, no visual snapping)
			unit["grid_pos"] = new_grid_pos

			print("Combat_3: Unit %s moved to (%d, %d)" % [unit.get("ship_id", "unknown"), new_grid_pos.x, new_grid_pos.y])
		else:
			# Cell occupied, just move horizontally (don't change lanes)
			var horizontal_only_pos = current_pos + Vector2(horizontal_dir * distance_px, 0)
			container.position = horizontal_only_pos
			new_grid_pos = CombatGridManager.world_to_grid(horizontal_only_pos)

			if old_grid_pos.y != new_grid_pos.y:
				CombatGridManager.free_cell(unit["grid_pos"].x, unit["grid_pos"].y)
				CombatGridManager.occupy_cell(new_grid_pos.x, new_grid_pos.y, unit)
				unit["grid_pos"] = new_grid_pos

func drift_to_grid_center(unit: Dictionary, delta: float):
	"""Slowly drift ship to the exact center of its logical grid position when idle"""
	var container = unit["container"]
	var current_pos = container.position

	# Get the center of the logical grid cell
	var grid_pos = unit["grid_pos"]
	var target_pos = CombatGridManager.grid_to_world(grid_pos.x, grid_pos.y)

	# Calculate distance to center
	var distance_to_center = current_pos.distance_to(target_pos)

	# Only drift if not already centered (threshold of 0.5 pixels)
	if distance_to_center > 0.5:
		# Slow drift speed (20 pixels per second)
		var drift_speed = 20.0
		var max_movement = drift_speed * delta

		# Move toward center, but don't overshoot
		var direction = (target_pos - current_pos).normalized()
		var movement_distance = min(max_movement, distance_to_center)
		container.position = current_pos + (direction * movement_distance)

func update_attack_timer(unit: Dictionary, delta: float):
	"""Update attack timer and fire weapon when ready"""
	# Decrement timer
	unit["attack_timer"] -= delta

	# Fire weapon when timer expires
	if unit["attack_timer"] <= 0:
		var target = unit.get("current_target", {})
		if not target.is_empty():
			# Fire weapon volley
			fire_weapon(unit, target)

			# Reset timer
			var attack_speed = unit.get("attack_speed", 1.0)
			unit["attack_timer"] = 1.0 / attack_speed

func fire_weapon(unit: Dictionary, target: Dictionary):
	"""Fire weapon at target using weapon system"""
	print("Combat_3: Unit %s firing at %s" % [unit.get("ship_id", "unknown"), target.get("ship_id", "unknown")])

	# Use weapon system to fire volley
	weapon_system.fire_weapon_volley(unit, target)

	# Gain energy (2-4 random)
	weapon_system.gain_energy(unit)

func check_and_cast_ability(unit: Dictionary):
	"""Check if unit can cast ability and trigger cinematic"""
	var current_energy = unit.get("current_energy", 0)
	var max_energy = unit.get("max_energy", 0)

	# Only units with an energy system can cast abilities
	if max_energy <= 0:
		return

	# Check if energy full
	if current_energy >= max_energy:
		print("Combat_3: Unit %s casting ability! (cinematic)" % unit.get("ship_id", "unknown"))

		# Trigger ability cinematic (non-blocking for now, will implement later)
		cast_ability_with_cinematic(unit)

func cast_ability_with_cinematic(unit: Dictionary):
	"""Cast ability with 1-second cinematic zoom (async)"""
	# Pause combat (only set cinematic flag, don't end combat)
	ability_cinematic_active = true

	# Zoom to unit
	var container = unit["container"]
	var target_zoom = 1.5

	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(camera, "position", container.position, 0.5)
	tween.parallel().tween_property(camera, "zoom", Vector2(target_zoom, target_zoom), 0.5)

	# Wait for zoom
	await tween.finished

	# Wait 1 second for ability display
	await get_tree().create_timer(1.0).timeout

	# Cast ability
	weapon_system.cast_ability(unit)

	# Restore camera
	snap_camera_to_ships()
	await get_tree().create_timer(0.5).timeout

	# Resume combat processing
	ability_cinematic_active = false

func is_unit_alive(unit: Dictionary) -> bool:
	"""Check if unit is alive (has armor > 0)"""
	return unit.get("current_armor", 0) > 0

func check_victory_defeat() -> bool:
	"""Check if combat should end due to damage sponge destruction
	Combat ends when either faction's damage sponge is destroyed"""

	# Check if enemy damage sponge is destroyed
	if enemy_sponge_pool["collective_armor"] <= 0:
		print("Combat_3: VICTORY - Enemy damage sponge destroyed!")
		return true

	# Check if player damage sponge is destroyed
	if player_sponge_pool["collective_armor"] <= 0:
		print("Combat_3: DEFEAT - Player damage sponge destroyed!")
		return true

	return false

func end_combat_phase():
	"""End combat phase and transition to cleanup"""
	combat_active = false
	print("Combat_3: Combat ending - Time remaining: %.1fs" % combat_time_remaining)

	# Hide combat timer UI
	combat_timer_container.visible = false

# ============================================================================
# TACTICAL MOVEMENT SYSTEM
# ============================================================================

func find_unit_at_mouse() -> Dictionary:
	"""Find player ship at mouse position (for tactical dragging)"""
	var mouse_pos = get_global_mouse_position()

	# Check all units for collision
	for unit in all_units:
		# Only player ships can be dragged
		if unit.get("faction", "") != "player":
			continue

		# Skip sponges
		if unit.get("is_sponge", false):
			continue

		var container = unit.get("container")
		if container == null:
			continue

		# Check if mouse is within ship bounds (using ship size)
		var ship_pos = container.position
		var ship_size = unit.get("size", 36)
		var half_size = ship_size / 2.0

		if mouse_pos.x >= ship_pos.x - half_size and mouse_pos.x <= ship_pos.x + half_size:
			if mouse_pos.y >= ship_pos.y - half_size and mouse_pos.y <= ship_pos.y + half_size:
				return unit

	return {}

func calculate_valid_move_cells(unit: Dictionary) -> Array:
	"""Calculate all valid cells this unit can move to (Manhattan distance)"""
	var valid_cells = []

	if unit.is_empty():
		return valid_cells

	var start_grid = unit.get("grid_pos", Vector2i(-1, -1))
	if start_grid.x < 0 or start_grid.y < 0:
		return valid_cells

	var movement_speed = unit.get("movement_speed", 2)
	var movement_used = unit.get("movement_used_this_turn", 0)
	var movement_remaining = movement_speed - movement_used

	# No movement left
	if movement_remaining <= 0:
		return valid_cells

	# Check all cells within remaining Manhattan distance
	for row in range(CombatGridManager.GRID_ROWS):
		for col in range(active_scenario_width):
			# Skip starting position
			if row == start_grid.x and col == start_grid.y:
				continue

			# Check Manhattan distance against remaining movement
			var manhattan = abs(row - start_grid.x) + abs(col - start_grid.y)
			if manhattan > movement_remaining:
				continue

			# Check direction (cannot move right toward enemy)
			if col > start_grid.y:
				continue

			# Check if cell is occupied
			if CombatGridManager.is_cell_occupied(row, col):
				continue

			# Valid cell!
			valid_cells.append(Vector2i(row, col))

	return valid_cells

func show_range_highlights(cells: Array):
	"""Show green highlights on valid movement cells"""
	clear_range_highlights()

	for cell_pos in cells:
		var world_pos = CombatGridManager.grid_to_world(cell_pos.x, cell_pos.y)
		var cell_size = CombatGridManager.CELL_SIZE

		# Create highlight rectangle
		var highlight = ColorRect.new()
		highlight.position = world_pos - Vector2(cell_size / 2, cell_size / 2)
		highlight.size = Vector2(cell_size, cell_size)
		highlight.color = Color(0.0, 1.0, 0.0, 0.2)  # Green, 20% opacity
		highlight.z_index = -5  # Below ships but above grid

		unit_container.add_child(highlight)
		range_highlights.append(highlight)

func clear_range_highlights():
	"""Remove all range highlight rectangles"""
	for highlight in range_highlights:
		if highlight != null:
			highlight.queue_free()
	range_highlights.clear()

func validate_tactical_move(unit: Dictionary, target_grid: Vector2i) -> bool:
	"""Check if a tactical move is valid"""
	if unit.is_empty():
		return false

	# Check if target is in valid_move_cells
	for cell in valid_move_cells:
		if cell == target_grid:
			return true

	return false

func create_drag_ghost(unit: Dictionary):
	"""Create semi-transparent ghost sprite for dragging"""
	if drag_ghost != null:
		drag_ghost.queue_free()

	var sprite = unit.get("sprite")
	if sprite == null:
		return

	# Clone the sprite
	drag_ghost = Sprite2D.new()
	drag_ghost.texture = sprite.texture
	drag_ghost.scale = sprite.scale
	drag_ghost.rotation = sprite.rotation
	drag_ghost.modulate = Color(1.0, 1.0, 1.0, 0.5)  # 50% opacity
	drag_ghost.z_index = 100  # Above everything

	unit_container.add_child(drag_ghost)

func update_drag_ghost_position(mouse_pos: Vector2):
	"""Update ghost position and tint based on validity"""
	if drag_ghost == null:
		return

	# Snap to grid
	var grid_pos = CombatGridManager.world_to_grid(mouse_pos)
	var snapped_world_pos = CombatGridManager.grid_to_world(grid_pos.x, grid_pos.y)
	drag_ghost.position = snapped_world_pos

	# Update tint based on validity
	if validate_tactical_move(dragging_unit, grid_pos):
		drag_ghost.modulate = Color(0.5, 1.0, 0.5, 0.7)  # Green tint (valid)
	else:
		drag_ghost.modulate = Color(1.0, 0.5, 0.5, 0.7)  # Red tint (invalid)

func destroy_drag_ghost():
	"""Remove the drag ghost sprite"""
	if drag_ghost != null:
		drag_ghost.queue_free()
		drag_ghost = null

func execute_tactical_move(unit: Dictionary, target_grid: Vector2i):
	"""Execute curved movement animation with overshoot"""
	if unit.is_empty():
		return

	var container = unit.get("container")
	if container == null:
		return

	var start_pos = container.position
	var target_pos = CombatGridManager.grid_to_world(target_grid.x, target_grid.y)

	# Calculate overshoot based on movement speed
	var movement_speed = unit.get("movement_speed", 2)
	var overshoot_distance = movement_speed * 15.0  # Pixels

	# Calculate overshoot direction (past the target)
	var direction = (target_pos - start_pos).normalized()
	var overshoot_pos = target_pos + (direction * overshoot_distance)

	# Calculate movement cost (Manhattan distance from current position)
	var start_grid = unit["grid_pos"]
	var distance_moved = abs(target_grid.x - start_grid.x) + abs(target_grid.y - start_grid.y)
	unit["movement_used_this_turn"] = unit.get("movement_used_this_turn", 0) + distance_moved
	unit["has_moved_this_turn"] = true

	print("Combat_3: Unit moved ", distance_moved, " cells (total used: ", unit["movement_used_this_turn"], "/", movement_speed, ")")

	# Update grid occupancy immediately (tactical phase is static)
	CombatGridManager.free_cell(unit["grid_pos"].x, unit["grid_pos"].y)
	CombatGridManager.occupy_cell(target_grid.x, target_grid.y, unit)
	unit["grid_pos"] = target_grid

	# Create curved path using Bezier: Start → Overshoot → Target
	var distance = start_pos.distance_to(target_pos)
	var duration = distance / (movement_speed * 100.0)  # Faster ships move quicker

	# Create tween for smooth curved movement
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Move to overshoot point
	tween.tween_property(container, "position", overshoot_pos, duration * 0.6)

	# Return to center
	tween.tween_property(container, "position", target_pos, duration * 0.4)

	print("Combat_3: Unit %s moving to (%d, %d) with overshoot" % [unit.get("ship_id", "unknown"), target_grid.x, target_grid.y])

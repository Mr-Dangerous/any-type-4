extends Node2D

# Tactical view combat system with 3 horizontal lanes

# Manager classes
var ship_manager: CombatShipManager = null
var targeting_system: CombatTargetingSystem = null
var projectile_manager: CombatProjectileManager = null
var status_effect_manager: CombatStatusEffectManager = null
var weapon_manager: Node = null  # CombatWeapons

# Preloaded scenes
const DamageNumber = preload("res://scripts/DamageNumber.gd")

# Constants and resources now loaded from CombatConstants autoload singleton
# Game state
var lanes: Array[Dictionary] = []  # Each lane can contain units
var lane_grids: Array = []  # Grid occupancy tracking: [lane_index][row][col] -> unit or null
var turrets: Array[Dictionary] = []  # Player turret battle objects
var enemy_turrets: Array[Dictionary] = []  # Enemy turret battle objects
var selected_ship_type: String = ""  # Currently selected ship for deployment
var ship_selection_panel: Panel = null
var deploy_button: Button = null

var selected_enemy_type: String = ""  # Currently selected enemy for deployment
var enemy_selection_panel: Panel = null
var deploy_enemy_button: Button = null
var is_zoomed: bool = false
var zoomed_lane_index: int = -1
var camera: Camera2D = null
var return_button: TextureButton = null
var ui_layer: CanvasLayer = null

# Combat state
var selected_attacker: Dictionary = {}  # Ship that will attack
var selected_target: Dictionary = {}  # Ship being targeted

# Ship repositioning state
var is_dragging_ship: bool = false  # Whether we're currently dragging a ship
var dragged_ship: Dictionary = {}  # The ship being dragged
var drag_start_pos: Vector2 = Vector2.ZERO  # Initial mouse position when drag started
var ghost_ship_container: Control = null  # Ghost ship that follows cursor
var cell_overlays: Array[ColorRect] = []  # Visual overlays for valid/invalid cells
var valid_move_cells: Array[Vector2i] = []  # List of valid grid positions for current drag

# Auto-combat state
var auto_combat_active: bool = false
var auto_combat_button: Button = null

# Turn-based combat state
var turn_mode_active: bool = false
var current_turn_phase: String = "tactical"  # tactical, lane_0, lane_1, lane_2
var turn_progression_button: Button = null
var waiting_for_combat_start: bool = false

# Auto-deploy button
var auto_deploy_button: Button = null

# Combat pause system
var combat_paused: bool = true  # Start paused in tactical view
var in_cleanup_phase: bool = false  # True during post-combat cleanup phase
var zoom_timer: Timer = null
var zoom_timer_label: Label = null

# Pre-combat check phase UI
var pre_combat_check_panel: Panel = null
var pre_combat_confirm_button: Button = null
var pre_combat_ability_list: VBoxContainer = null

# Idle behavior constants

# Debug system
var debug_panel: Panel = null
var debug_button: Button = null
var player_targeting_mode: String = "gamma"  # "gamma" (row-based), "alpha" (multi-row), or "random"
var enemy_targeting_mode: String = "gamma"   # "gamma" (row-based), "alpha" (multi-row), or "random"

# Ship tooltip tracking
var current_tooltip_ship: Dictionary = {}

# ============================================================================
# MANAGER INITIALIZATION
# ============================================================================

func initialize_managers():
	"""Initialize the combat manager systems"""
	# Create ship manager
	ship_manager = CombatShipManager.new()
	ship_manager.name = "ShipManager"
	add_child(ship_manager)
	ship_manager.initialize(self)

	# Create targeting system
	targeting_system = CombatTargetingSystem.new()
	targeting_system.name = "TargetingSystem"
	add_child(targeting_system)
	targeting_system.initialize(ship_manager)

	# Sync targeting modes
	targeting_system.player_targeting_mode = player_targeting_mode
	targeting_system.enemy_targeting_mode = enemy_targeting_mode

	# Create projectile manager
	projectile_manager = CombatProjectileManager.new()
	projectile_manager.name = "ProjectileManager"
	add_child(projectile_manager)
	projectile_manager.initialize(self, ship_manager)

	# Create status effect manager
	status_effect_manager = CombatStatusEffectManager.new()
	status_effect_manager.name = "StatusEffectManager"
	add_child(status_effect_manager)
	status_effect_manager.initialize(self)

	# Create weapon manager
	var CombatWeapons = load("res://scripts/CombatWeapons.gd")
	weapon_manager = CombatWeapons.new(self)
	weapon_manager.name = "WeaponManager"
	add_child(weapon_manager)

	# Connect signals
	ship_manager.ship_destroyed.connect(_on_ship_destroyed)
	projectile_manager.damage_dealt.connect(_on_damage_dealt)
	status_effect_manager.status_applied.connect(_on_status_applied)
	status_effect_manager.status_removed.connect(_on_status_removed)
	status_effect_manager.status_tick.connect(_on_status_tick)

	# Share state references between managers and main
	# Lanes and grids are now managed by ship_manager
	lanes = ship_manager.lanes
	lane_grids = ship_manager.lane_grids
	turrets = ship_manager.turrets
	enemy_turrets = ship_manager.enemy_turrets

	print("Combat_2: Manager systems initialized")

func _on_ship_destroyed(ship: Dictionary):
	"""Handle ship destruction event from ship manager"""
	# Clear target references
	targeting_system.clear_targets_referencing_ship(ship)
	# Could add more cleanup here

func _on_damage_dealt(attacker: Dictionary, target: Dictionary, damage_info: Dictionary):
	"""Handle damage dealt event from projectile manager"""
	# Update tooltip if viewing damaged ship
	if not current_tooltip_ship.is_empty() and current_tooltip_ship == target:
		show_ship_tooltip(target)
	
	if damage_info.get("destroyed", false):
		# Check if destroyed object is mothership or boss
		var object_type = target.get("object_type", "")

		if object_type == "mothership":
			_on_mothership_destroyed()
		elif object_type == "boss":
			_on_boss_destroyed()
		else:
			# Regular ship destruction
			ship_manager.destroy_ship(target)

func _on_status_applied(ship: Dictionary, effect_type: String, stacks: int):
	"""Update tooltip when status effect applied"""
	if not current_tooltip_ship.is_empty() and current_tooltip_ship == ship:
		show_ship_tooltip(ship)

func _on_status_removed(ship: Dictionary, effect_type: String):
	"""Update tooltip when status effect removed"""
	if not current_tooltip_ship.is_empty() and current_tooltip_ship == ship:
		show_ship_tooltip(ship)

func _on_status_tick(ship: Dictionary, effect_type: String, damage: int):
	"""Update tooltip after status effect damage"""
	if not current_tooltip_ship.is_empty() and current_tooltip_ship == ship:
		show_ship_tooltip(ship)

func _on_mothership_destroyed():
	"""Handle player mothership destruction - GAME OVER"""
	print("========================================")
	print("      MOTHERSHIP DESTROYED!")
	print("           DEFEAT")
	print("========================================")

	# Pause all combat
	combat_paused = true
	auto_combat_active = false

	# Create game over UI
	var game_over_panel = Panel.new()
	game_over_panel.name = "GameOverPanel"
	game_over_panel.position = Vector2(get_viewport_rect().size.x / 2 - 200, get_viewport_rect().size.y / 2 - 100)
	game_over_panel.custom_minimum_size = Vector2(400, 200)
	game_over_panel.z_index = 1000
	ui_layer.add_child(game_over_panel)

	var label = Label.new()
	label.text = "MOTHERSHIP DESTROYED\n\nDEFEAT\n\n(Close game to restart)"
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_panel.add_child(label)

func _on_boss_destroyed():
	"""Handle enemy boss destruction - VICTORY"""
	print("========================================")
	print("        ENEMY BOSS DESTROYED!")
	print("            VICTORY")
	print("========================================")

	# Pause all combat
	combat_paused = true
	auto_combat_active = false

	# Create victory UI
	var victory_panel = Panel.new()
	victory_panel.name = "VictoryPanel"
	victory_panel.position = Vector2(get_viewport_rect().size.x / 2 - 200, get_viewport_rect().size.y / 2 - 100)
	victory_panel.custom_minimum_size = Vector2(400, 200)
	victory_panel.z_index = 1000
	ui_layer.add_child(victory_panel)

	var label = Label.new()
	label.text = "ENEMY BOSS DESTROYED\n\nVICTORY!\n\n(Close game to restart)"
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.2, 1, 0.2, 1))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_panel.add_child(label)

# ============================================================================
# SCENE INITIALIZATION
# ============================================================================

func _ready():
	# Initialize manager systems
	initialize_managers()

	# Setup camera
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.enabled = true
	camera.position = Vector2(576, 324)  # Center of 1152x648 screen
	add_child(camera)

	# Get the UI CanvasLayer from the scene
	ui_layer = get_node("UI")

	# Setup resource UI
	setup_resource_ui()

	# Initialize lanes - now handled by ship_manager in initialize_managers()
	# initialize_lanes()

	# Setup mothership
	setup_mothership()

	# Setup turrets
	setup_turrets()

	# Setup enemy turrets
	setup_enemy_turrets()

	# Setup enemy boss
	setup_enemy_boss()

	# Setup deployment UI
	setup_deployment_ui()

	# Setup enemy deployment UI (for testing)
	setup_enemy_deployment_ui()

	# Setup return button (initially hidden)
	setup_return_button()

	# Setup debug UI
	setup_debug_ui()

	# Setup auto-combat button
	setup_auto_combat_button()

	# Setup auto-deploy button
	setup_auto_deploy_button()

	# Setup zoom timer label
	setup_zoom_timer_label()

	# Setup turn progression button
	setup_turn_progression_button()
	
	# Setup ship tooltip
	setup_ship_tooltip()
	
	# Setup card system
	setup_card_system()

	print("Combat_2 initialized with tactical view")

func _process(delta):
	# Update zoom timer label
	if zoom_timer and zoom_timer_label and zoom_timer_label.visible:
		var time_left = zoom_timer.time_left
		zoom_timer_label.text = "LANE %d: %ds" % [zoomed_lane_index + 1, ceil(time_left)]

func initialize_lanes():
	# Create 3 lanes
	for i in range(CombatConstants.NUM_LANES):
		var lane = {
			"index": i,
			"y_position": CombatConstants.LANE_Y_START + (i * CombatConstants.LANE_SPACING),
			"units": []
		}
		lanes.append(lane)

		# Initialize grid for this lane (4 rows x 10 columns)
		var grid = []
		for row in range(CombatConstants.GRID_ROWS):
			var grid_row = []
			for col in range(CombatConstants.GRID_COLS):
				grid_row.append(null)  # null = empty cell
			grid.append(grid_row)
		lane_grids.append(grid)

		# Create visual lane markers
		create_lane_marker(i, lane["y_position"])

func create_lane_marker(lane_index: int, y_pos: float):
	# Create a rectangle to visualize the lane with grid
	var lane_width = CombatConstants.GRID_COLS * CombatConstants.CELL_SIZE
	var lane_height = CombatConstants.GRID_ROWS * CombatConstants.CELL_SIZE

	# Position lane so its center aligns with y_pos
	var lane_rect = ColorRect.new()
	lane_rect.name = "Lane_%d" % lane_index
	lane_rect.position = Vector2(CombatConstants.GRID_START_X, y_pos - lane_height / 2)
	lane_rect.size = Vector2(lane_width, lane_height)
	lane_rect.color = Color(0.2, 0.4, 0.8, 0.2)  # Semi-transparent blue
	add_child(lane_rect)

	# Add outer border
	var border = ReferenceRect.new()
	border.border_color = Color(0.3, 0.5, 1.0, 0.9)
	border.border_width = 3.0
	border.size = lane_rect.size
	lane_rect.add_child(border)

	# Draw grid lines for each cell
	for row in range(CombatConstants.GRID_ROWS + 1):
		var line = ColorRect.new()
		line.position = Vector2(0, row * CombatConstants.CELL_SIZE)
		line.size = Vector2(lane_width, 1)
		line.color = Color(0.3, 0.5, 1.0, 0.4)
		lane_rect.add_child(line)

	for col in range(CombatConstants.GRID_COLS + 1):
		var line = ColorRect.new()
		line.position = Vector2(col * CombatConstants.CELL_SIZE, 0)
		line.size = Vector2(1, lane_height)
		line.color = Color(0.3, 0.5, 1.0, 0.4)
		lane_rect.add_child(line)

	# Add column numbers at the top of the lane
	for col in range(CombatConstants.GRID_COLS):
		var col_label = Label.new()
		col_label.text = str(col)
		col_label.position = Vector2(col * CombatConstants.CELL_SIZE + CombatConstants.CELL_SIZE / 2 - 8, -25)
		col_label.add_theme_font_size_override("font_size", 16)
		col_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.9))
		lane_rect.add_child(col_label)

	# Add lane label
	var label = Label.new()
	label.name = "LaneLabel_%d" % lane_index
	label.text = "Lane %d" % (lane_index + 1)
	label.position = Vector2(10, 10)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.8))
	lane_rect.add_child(label)

# Grid helper functions
func get_random_empty_cell(lane_index: int, columns: Array) -> Vector2i:
	# Returns a random empty cell (row, col) in the specified columns
	# Returns Vector2i(-1, -1) if no empty cells available
	var empty_cells = []

	for col in columns:
		for row in range(CombatConstants.GRID_ROWS):
			if lane_grids[lane_index][row][col] == null:
				empty_cells.append(Vector2i(row, col))

	if empty_cells.is_empty():
		return Vector2i(-1, -1)

	return empty_cells[randi() % empty_cells.size()]

func get_cell_world_position(lane_index: int, row: int, col: int) -> Vector2:
	# Returns the center world position of a grid cell
	var lane_y = lanes[lane_index]["y_position"]
	var lane_height = CombatConstants.GRID_ROWS * CombatConstants.CELL_SIZE

	# Calculate cell center position
	var x = CombatConstants.GRID_START_X + (col * CombatConstants.CELL_SIZE) + (CombatConstants.CELL_SIZE / 2)
	var y = (lane_y - lane_height / 2) + (row * CombatConstants.CELL_SIZE) + (CombatConstants.CELL_SIZE / 2)

	return Vector2(x, y)

func occupy_grid_cell(lane_index: int, row: int, col: int, unit: Dictionary):
	# Mark a grid cell as occupied by a unit
	if row >= 0 and row < CombatConstants.GRID_ROWS and col >= 0 and col < CombatConstants.GRID_COLS:
		lane_grids[lane_index][row][col] = unit

func free_grid_cell(lane_index: int, row: int, col: int):
	# Mark a grid cell as empty
	if row >= 0 and row < CombatConstants.GRID_ROWS and col >= 0 and col < CombatConstants.GRID_COLS:
		lane_grids[lane_index][row][col] = null

func get_valid_move_cells(unit: Dictionary) -> Array[Vector2i]:
	# Calculate all valid cells a unit can move to based on movement_speed
	# Uses Manhattan distance (no diagonals)
	var valid_cells: Array[Vector2i] = []

	if not unit.has("grid_row") or not unit.has("grid_col") or not unit.has("lane_index"):
		return valid_cells

	var current_row = unit["grid_row"]
	var current_col = unit["grid_col"]
	var lane_index = unit["lane_index"]
	var movement_speed = unit.get("movement_speed", 0)

	# Check all cells within Manhattan distance of movement_speed
	for row in range(CombatConstants.GRID_ROWS):
		for col in range(CombatConstants.GRID_COLS):
			# Skip current position
			if row == current_row and col == current_col:
				continue

			# Calculate Manhattan distance (no diagonals)
			var distance = abs(row - current_row) + abs(col - current_col)

			# Check if within movement range
			if distance <= movement_speed:
				# Check if cell is unoccupied
				if lane_grids[lane_index][row][col] == null:
					valid_cells.append(Vector2i(row, col))

	return valid_cells

func get_all_ships() -> Array:
	"""Get all ships from all lanes (used for AoE effects)"""
	var all_ships = []

	for lane in lanes:
		if lane.has("units"):
			for unit in lane["units"]:
				all_ships.append(unit)

	return all_ships

func show_movement_overlay(unit: Dictionary):
	# Show visual overlays for all cells in the lane
	# Blue for valid moves, grey for invalid
	if not unit.has("lane_index"):
		return

	# Clear any existing overlays
	clear_movement_overlay()

	var lane_index = unit["lane_index"]
	valid_move_cells = get_valid_move_cells(unit)

	# Create overlays for all cells in the lane
	for row in range(CombatConstants.GRID_ROWS):
		for col in range(CombatConstants.GRID_COLS):
			var cell_pos = Vector2i(row, col)
			var is_valid = false

			# Check if this cell is in the valid moves list
			for valid_cell in valid_move_cells:
				if valid_cell.x == row and valid_cell.y == col:
					is_valid = true
					break

			# Skip current position
			if row == unit["grid_row"] and col == unit["grid_col"]:
				continue

			# Create overlay rect
			var overlay = ColorRect.new()
			var world_pos = get_cell_world_position(lane_index, row, col)

			# Position at cell center, adjust for cell size
			overlay.position = Vector2(world_pos.x - CombatConstants.CELL_SIZE / 2, world_pos.y - CombatConstants.CELL_SIZE / 2)
			overlay.size = Vector2(CombatConstants.CELL_SIZE, CombatConstants.CELL_SIZE)

			# Set color based on validity
			if is_valid:
				overlay.color = Color(0.0, 0.5, 1.0, 0.3)  # Blue with transparency
			else:
				overlay.color = Color(0.4, 0.4, 0.4, 0.3)  # Grey with transparency

			add_child(overlay)
			cell_overlays.append(overlay)

func clear_movement_overlay():
	# Remove all cell overlay visuals
	for overlay in cell_overlays:
		overlay.queue_free()
	cell_overlays.clear()
	valid_move_cells.clear()

func start_ship_drag(unit: Dictionary, mouse_pos: Vector2):
	# Start dragging a ship
	if not unit.has("container") or not unit.has("sprite"):
		return

	is_dragging_ship = true
	dragged_ship = unit
	drag_start_pos = mouse_pos

	# Show movement overlay
	show_movement_overlay(unit)

	# Create ghost ship
	create_ghost_ship(unit)

	# Dim the original ship
	if unit.has("sprite"):
		unit["sprite"].modulate = Color(0.5, 0.5, 0.5, 0.5)

	print("Started dragging ship: ", unit.get("type", "unknown"))

func create_ghost_ship(unit: Dictionary):
	# Create a ghost ship that follows the cursor
	if ghost_ship_container != null:
		ghost_ship_container.queue_free()

	ghost_ship_container = Control.new()
	ghost_ship_container.name = "GhostShip"
	ghost_ship_container.z_index = 100  # Draw on top
	add_child(ghost_ship_container)

	# Create ghost sprite
	var ghost_sprite = TextureRect.new()
	ghost_sprite.texture = unit["sprite"].texture
	ghost_sprite.custom_minimum_size = Vector2(unit["size"], unit["size"])
	ghost_sprite.size = Vector2(unit["size"], unit["size"])
	ghost_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost_sprite.modulate = Color(1.0, 1.0, 1.0, 0.5)  # Semi-transparent
	ghost_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_ship_container.add_child(ghost_sprite)

	# Position at cursor
	var mouse_pos = get_global_mouse_position()
	ghost_ship_container.position = Vector2(mouse_pos.x - unit["size"] / 2, mouse_pos.y - unit["size"] / 2)

func update_ghost_ship_position(mouse_pos: Vector2):
	# Update ghost ship position to follow cursor
	if ghost_ship_container != null and dragged_ship.has("size"):
		ghost_ship_container.position = Vector2(mouse_pos.x - dragged_ship["size"] / 2, mouse_pos.y - dragged_ship["size"] / 2)

func end_ship_drag(mouse_pos: Vector2):
	# End ship drag and move ship if valid
	if not is_dragging_ship or dragged_ship.is_empty():
		return

	# Find which cell the mouse is over
	var target_cell = get_cell_at_position(mouse_pos, dragged_ship["lane_index"])

	# Check if it's a valid move
	var is_valid_move = false
	if target_cell != Vector2i(-1, -1):
		for valid_cell in valid_move_cells:
			if valid_cell.x == target_cell.x and valid_cell.y == target_cell.y:
				is_valid_move = true
				break

	# Move ship if valid
	if is_valid_move:
		move_ship_to_cell(dragged_ship, target_cell)
	else:
		# Invalid move - restore original ship appearance
		if dragged_ship.has("sprite"):
			dragged_ship["sprite"].modulate = Color(1, 1, 1)
		print("Invalid move - ship returned to original position")

	# Cleanup
	cleanup_ship_drag()

func get_cell_at_position(pos: Vector2, lane_index: int) -> Vector2i:
	# Convert world position to grid cell coordinates
	var lane_y = lanes[lane_index]["y_position"]
	var lane_height = CombatConstants.GRID_ROWS * CombatConstants.CELL_SIZE

	# Calculate which row and column
	var relative_x = pos.x - CombatConstants.GRID_START_X
	var relative_y = pos.y - (lane_y - lane_height / 2)

	var col = int(relative_x / CombatConstants.CELL_SIZE)
	var row = int(relative_y / CombatConstants.CELL_SIZE)

	# Check if within bounds
	if row >= 0 and row < CombatConstants.GRID_ROWS and col >= 0 and col < CombatConstants.GRID_COLS:
		return Vector2i(row, col)

	return Vector2i(-1, -1)

func cleanup_ship_drag():
	# Clean up drag state
	if ghost_ship_container != null:
		ghost_ship_container.queue_free()
		ghost_ship_container = null

	clear_movement_overlay()

	# Restore original ship appearance if still dragging
	if not dragged_ship.is_empty() and dragged_ship.has("sprite"):
		dragged_ship["sprite"].modulate = Color(1, 1, 1)

	is_dragging_ship = false
	dragged_ship = {}
	drag_start_pos = Vector2.ZERO

func move_ship_to_cell(unit: Dictionary, target_cell: Vector2i):
	# Move ship to a new grid cell with animation
	if not unit.has("grid_row") or not unit.has("grid_col") or not unit.has("lane_index"):
		return

	var old_row = unit["grid_row"]
	var old_col = unit["grid_col"]
	var new_row = target_cell.x
	var new_col = target_cell.y
	var lane_index = unit["lane_index"]

	# Free old cell
	free_grid_cell(lane_index, old_row, old_col)

	# Update unit position
	unit["grid_row"] = new_row
	unit["grid_col"] = new_col

	# Occupy new cell
	occupy_grid_cell(lane_index, new_row, new_col, unit)

	# Calculate new world position
	var new_world_pos = get_cell_world_position(lane_index, new_row, new_col)
	var target_pos = Vector2(new_world_pos.x - unit["size"] / 2, new_world_pos.y - unit["size"] / 2)

	# Update original position
	unit["original_position"] = target_pos

	# Animate ship to new position
	var container = unit["container"]

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(container, "position", target_pos, 0.5)

	# Restore ship appearance and mark as moved
	tween.finished.connect(func():
		if unit.has("sprite"):
			unit["sprite"].modulate = Color(1, 1, 1)
	)

	# Mark ship as having moved this turn
	unit["has_moved_this_turn"] = true

	print("Moved ship from (", old_row, ",", old_col, ") to (", new_row, ",", new_col, ")")

func enemy_pathfinding_alpha(lane_index: int):
	"""
	ENEMY PATHFINDING ALPHA
	Move all enemies in the specified lane toward the player (left/decreasing columns).
	Enemies move up to their movement_speed, stopping if blocked by player ships.
	This is a simple straight-line movement system with no pathfinding around obstacles.
	"""
	print("ENEMY PATHFINDING ALPHA - Moving enemies in lane ", lane_index)

	# Get all enemies in this lane
	var enemies_in_lane = []
	for unit in lanes[lane_index]["units"]:
		if unit.get("is_enemy", false) and unit.get("object_type") == "ship":
			enemies_in_lane.append(unit)

	if enemies_in_lane.is_empty():
		print("  No enemies in lane ", lane_index)
		return

	# Move each enemy
	for enemy in enemies_in_lane:
		var current_row = enemy.get("grid_row", -1)
		var current_col = enemy.get("grid_col", -1)
		var movement_speed = enemy.get("movement_speed", 2)

		if current_row == -1 or current_col == -1:
			continue

		# Calculate target column (move left toward player)
		var target_col = max(0, current_col - movement_speed)

		# Check each column from current toward target for blocking units
		var furthest_valid_col = current_col
		for check_col in range(current_col - 1, target_col - 1, -1):
			# Check if this cell is occupied
			var cell_contents = lane_grids[lane_index][current_row][check_col]

			if cell_contents != null:
				# Cell is occupied - check if it's a player unit
				if cell_contents.get("faction") == "player":
					# Blocked by player - stop here
					print("  Enemy at (", current_row, ",", current_col, ") blocked by player at (", current_row, ",", check_col, ")")
					break

			# Cell is empty or contains non-player unit - we can move here
			furthest_valid_col = check_col

		# Move enemy if we found a valid position
		if furthest_valid_col != current_col:
			var distance_moved = current_col - furthest_valid_col
			print("  Moving enemy from (", current_row, ",", current_col, ") to (", current_row, ",", furthest_valid_col, ") - distance: ", distance_moved)
			move_ship_to_cell(enemy, Vector2i(current_row, furthest_valid_col))
		else:
			print("  Enemy at (", current_row, ",", current_col, ") cannot move (blocked or at limit)")

func setup_mothership():
	# Create mothership as a targetable combat object
	var mothership_container = Control.new()
	mothership_container.name = "Mothership"
	# Position at top of combat area, spanning all lanes
	var combat_height = CombatConstants.LANE_SPACING * (CombatConstants.NUM_LANES - 1)
	mothership_container.position = Vector2(CombatConstants.MOTHERSHIP_X, CombatConstants.LANE_Y_START)
	add_child(mothership_container)

	# Add sprite - stretched vertically to span all lanes
	var sprite = TextureRect.new()
	sprite.name = "Sprite"
	sprite.texture = CombatConstants.MothershipTexture
	sprite.custom_minimum_size = Vector2(CombatConstants.MOTHERSHIP_SIZE, combat_height)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_SCALE
	mothership_container.add_child(sprite)

	# Add label
	var label = Label.new()
	label.name = "Label"
	label.text = "MOTHERSHIP"
	label.position = Vector2(0, CombatConstants.MOTHERSHIP_SIZE + 10)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.3, 0.8, 1, 1))
	mothership_container.add_child(label)

	# Create combat object Dictionary
	ship_manager.mothership = {
		"object_type": "mothership",
		"faction": "player",
		"type": "mothership",
		"display_name": "Mothership",
		"lane_index": -1,  # Special: not in a specific lane
		"grid_row": -1,  # Not in grid
		"grid_col": -1,
		"container": mothership_container,
		"sprite": sprite,
		"size": CombatConstants.MOTHERSHIP_SIZE,
		"current_armor": CombatConstants.MOTHERSHIP_ARMOR,
		"current_shield": CombatConstants.MOTHERSHIP_SHIELD,
		"stats": {
			"armor": CombatConstants.MOTHERSHIP_ARMOR,
			"shield": CombatConstants.MOTHERSHIP_SHIELD,
			"reinforced_armor": 0,
			"evasion": 0,
			"damage": 0,  # Mothership doesn't attack
			"accuracy": 0,
			"attack_speed": 0.0,
			"num_attacks": 0
		}
	}

	# Create health bar for mothership
	create_health_bar(
		mothership_container,
		CombatConstants.MOTHERSHIP_SIZE,
		CombatConstants.MOTHERSHIP_SHIELD,
		CombatConstants.MOTHERSHIP_ARMOR
	)

	print("Mothership created as targetable combat object with ", CombatConstants.MOTHERSHIP_ARMOR, " armor, ", CombatConstants.MOTHERSHIP_SHIELD, " shield")

func setup_turrets():
	# NEW: Create 3×5 grid of turrets (one per row per lane = 15 positions)
	# Only middle row (row 2) starts enabled with cannon turrets

	print("Setting up player turret grid (3 lanes × 5 rows = 15 positions)...")

	var turrets_created = 0

	# For each lane
	for lane_index in range(CombatConstants.NUM_LANES):
		# For each row in the lane
		for row_index in range(CombatConstants.NUM_TURRET_ROWS):
			# Only enable middle row (row 2) initially
			var is_enabled = (row_index == 2)
			var turret_type = "cannon_turret"  # All start as cannons (upgradeable later)

			if is_enabled:
				# Create enabled turret at this grid position
				create_turret_at_grid_position(lane_index, row_index, turret_type, true)
				turrets_created += 1
			else:
				# Create disabled turret placeholder
				create_turret_at_grid_position(lane_index, row_index, turret_type, false)

	print("Created ", turrets_created, " enabled turrets (middle row only), 12 disabled slots")

func create_turret_at_grid_position(lane_index: int, row_index: int, turret_type: String, is_enabled: bool):
	"""Create a turret at a specific grid position (lane, row)"""
	# Get turret data from database
	var db_turret_data = DataManager.get_ship_data(turret_type)
	if db_turret_data == null:
		print("ERROR: Turret type not found in database: ", turret_type)
		return

	# Calculate position using ship manager's helper
	var x_pos = CombatConstants.TURRET_X_OFFSET
	var y_pos = ship_manager.get_turret_y_position(lane_index, row_index)

	# Create turret container
	var turret_name = "Turret_L%d_R%d" % [lane_index, row_index]
	var turret_container = Control.new()
	turret_container.name = turret_name
	turret_container.position = Vector2(x_pos, y_pos)
	turret_container.z_index = 10
	add_child(turret_container)

	if is_enabled:
		# Load turret sprite
		var turret_texture: Texture2D = load(db_turret_data["sprite_path"])

		# Create enabled turret sprite
		var sprite = TextureRect.new()
		sprite.name = "Sprite"
		sprite.texture = turret_texture
		sprite.custom_minimum_size = Vector2(CombatConstants.TURRET_SIZE, CombatConstants.TURRET_SIZE)
		sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.position = Vector2(-CombatConstants.TURRET_SIZE / 2, -CombatConstants.TURRET_SIZE / 2)
		turret_container.add_child(sprite)

		# Create turret data dictionary
		var turret_data = {
			"object_type": "turret",
			"faction": "player",
			"type": turret_type,
			"display_name": db_turret_data["display_name"],
			"lane_index": lane_index,  # NEW: Grid position
			"grid_row": row_index,     # NEW: Grid row for targeting
			"grid_col": -1,  # Turrets don't have a column
			"container": turret_container,
			"sprite": sprite,
			"size": CombatConstants.TURRET_SIZE,
			"position": Vector2(x_pos, y_pos),
			"enabled": true,
			"current_armor": db_turret_data["armor"],
			"current_shield": db_turret_data["shield"],
			"stats": {
				"armor": db_turret_data["armor"],
				"shield": db_turret_data["shield"],
				"reinforced_armor": db_turret_data.get("reinforced_armor", 0),
				"damage": db_turret_data["damage"],
				"accuracy": db_turret_data["accuracy"],
				"attack_speed": db_turret_data["attack_speed"],
				"num_attacks": db_turret_data.get("num_attacks", 1),
				"evasion": db_turret_data.get("evasion", 0),
				"starting_energy": db_turret_data.get("starting_energy", 0)
			},
			"current_energy": db_turret_data.get("starting_energy", 0),
			"projectile_sprite": db_turret_data.get("projectile_sprite", "res://assets/Effects/laser_light/s_laser_light_001.png"),
			"projectile_size": db_turret_data.get("projectile_size", 30),
			"ability_function": db_turret_data.get("ability_function", ""),
			"ability_name": db_turret_data.get("ability", ""),
			"ability_description": db_turret_data.get("ability_description", "")
		}

		# Store in grid and legacy array
		ship_manager.set_turret_at_position(lane_index, row_index, turret_data, "player")
		turrets.append(turret_data)  # Also add to legacy array for compatibility

		# Create health bar
		create_health_bar(
			turret_container,
			CombatConstants.TURRET_SIZE,
			turret_data["current_shield"],
			turret_data["current_armor"]
		)

		# Initialize energy bar
		update_energy_bar(turret_data)
	else:
		# Create disabled turret placeholder
		var label = Label.new()
		label.name = "DisabledLabel"
		label.text = "[ ]"  # Empty slot indicator
		label.position = Vector2(-15, -15)
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 0.5))
		turret_container.add_child(label)

# Legacy function kept for backwards compatibility (not used in new grid system)
func create_turret(turret_name: String, turret_type: String, x_pos: float, y_pos: float, is_enabled: bool, target_lanes: Array, turret_index: int):
	# Get turret data from database
	var db_turret_data = DataManager.get_ship_data(turret_type)
	if db_turret_data == null:
		print("ERROR: Turret type not found in database: ", turret_type)
		return

	# Create turret container
	var turret_container = Control.new()
	turret_container.name = turret_name
	turret_container.position = Vector2(x_pos, y_pos)
	turret_container.z_index = 10  # Render turrets above lanes
	add_child(turret_container)

	# Load turret sprite
	var turret_texture: Texture2D = load(db_turret_data["sprite_path"])

	if is_enabled:
		# Create enabled turret sprite
		var sprite = TextureRect.new()
		sprite.name = "Sprite"
		sprite.texture = turret_texture
		sprite.custom_minimum_size = Vector2(CombatConstants.TURRET_SIZE, CombatConstants.TURRET_SIZE)
		sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.position = Vector2(-CombatConstants.TURRET_SIZE / 2, -CombatConstants.TURRET_SIZE / 2)  # Center the sprite
		turret_container.add_child(sprite)

		# Create turret data dictionary
		var turret_data = {
			"object_type": "turret",  # Mark as turret type
			"type": turret_type,
			"display_name": db_turret_data["display_name"],
			"container": turret_container,
			"sprite": sprite,
			"size": CombatConstants.TURRET_SIZE,  # Add size field for combat calculations
			"position": Vector2(x_pos, y_pos),
			"enabled": true,
			"target_lanes": target_lanes,  # Which lanes this turret can attack
			"current_armor": db_turret_data["armor"],
			"current_shield": db_turret_data["shield"],
			"stats": {
				"armor": db_turret_data["armor"],
				"shield": db_turret_data["shield"],
				"reinforced_armor": db_turret_data.get("reinforced_armor", 0),
				"damage": db_turret_data["damage"],
				"accuracy": db_turret_data["accuracy"],
				"attack_speed": db_turret_data["attack_speed"],
				"num_attacks": db_turret_data.get("num_attacks", 1),
				"evasion": db_turret_data.get("evasion", 0),
				"starting_energy": db_turret_data.get("starting_energy", 0)
			},
			"current_energy": db_turret_data.get("starting_energy", 0),
			"projectile_sprite": db_turret_data.get("projectile_sprite", "res://assets/Effects/laser_light/s_laser_light_001.png"),
			"projectile_size": db_turret_data.get("projectile_size", 30),
			"ability_function": db_turret_data.get("ability_function", ""),
			"ability_name": db_turret_data.get("ability", ""),
			"ability_description": db_turret_data.get("ability_description", "")
		}

		turrets.append(turret_data)

		# Create health bar
		create_health_bar(turret_container, CombatConstants.TURRET_SIZE, turret_data["current_shield"], turret_data["current_armor"])

		# Initialize energy bar
		update_energy_bar(turret_data)
	else:
		# Create disabled turret indicator (sad emoji)
		var label = Label.new()
		label.name = "DisabledLabel"
		label.text = "😢"  # Sad emoji
		label.position = Vector2(-20, -20)  # Center the emoji
		label.add_theme_font_size_override("font_size", 40)
		turret_container.add_child(label)

		# Add small text below
		var status_label = Label.new()
		status_label.name = "StatusLabel"
		status_label.text = "DISABLED"
		status_label.position = Vector2(-30, 25)
		status_label.add_theme_font_size_override("font_size", 10)
		status_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))
		turret_container.add_child(status_label)

		# Create placeholder turret data (not added to active turrets array)
		var turret_data = {
			"object_type": "turret",
			"type": turret_type,
			"display_name": db_turret_data["display_name"],
			"container": turret_container,
			"position": Vector2(x_pos, y_pos),
			"enabled": false
		}
		# Note: We don't add disabled turrets to the turrets array
		# They're just visual placeholders

func setup_enemy_turrets():
	# NEW: Create 3×5 grid of enemy turrets (one per row per lane = 15 positions)
	# Only middle row (row 2) starts enabled with cannon turrets

	print("Setting up enemy turret grid (3 lanes × 5 rows = 15 positions)...")

	var turrets_created = 0

	# For each lane
	for lane_index in range(CombatConstants.NUM_LANES):
		# For each row in the lane
		for row_index in range(CombatConstants.NUM_TURRET_ROWS):
			# Only enable middle row (row 2) initially
			var is_enabled = (row_index == 2)
			var turret_type = "cannon_turret"  # Match player turrets

			if is_enabled:
				# Create enabled turret at this grid position
				create_enemy_turret_at_grid_position(lane_index, row_index, turret_type, true)
				turrets_created += 1
			else:
				# Create disabled turret placeholder
				create_enemy_turret_at_grid_position(lane_index, row_index, turret_type, false)

	print("Created ", turrets_created, " enabled enemy turrets (middle row only), 12 disabled slots")

func create_enemy_turret_at_grid_position(lane_index: int, row_index: int, turret_type: String, is_enabled: bool):
	"""Create an enemy turret at a specific grid position (lane, row)"""
	# Get turret data from database
	var db_turret_data = DataManager.get_ship_data(turret_type)
	if db_turret_data == null:
		print("ERROR: Enemy turret type not found in database: ", turret_type)
		return

	# Calculate position using ship manager's helper
	var x_pos = CombatConstants.ENEMY_TURRET_X_OFFSET
	var y_pos = ship_manager.get_turret_y_position(lane_index, row_index)

	# Create turret container
	var turret_name = "EnemyTurret_L%d_R%d" % [lane_index, row_index]
	var turret_container = Control.new()
	turret_container.name = turret_name
	turret_container.position = Vector2(x_pos, y_pos)
	turret_container.z_index = 10
	add_child(turret_container)

	if is_enabled:
		# Load turret sprite
		var turret_texture: Texture2D = load(db_turret_data["sprite_path"])

		# Create enabled turret sprite
		var sprite = TextureRect.new()
		sprite.name = "Sprite"
		sprite.texture = turret_texture
		sprite.custom_minimum_size = Vector2(CombatConstants.TURRET_SIZE, CombatConstants.TURRET_SIZE)
		sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.flip_h = true  # Flip enemy turrets to face left
		sprite.position = Vector2(-CombatConstants.TURRET_SIZE / 2, -CombatConstants.TURRET_SIZE / 2)
		turret_container.add_child(sprite)

		# Create turret data dictionary
		var turret_data = {
			"object_type": "enemy_turret",
			"faction": "enemy",
			"type": turret_type,
			"display_name": db_turret_data["display_name"],
			"lane_index": lane_index,  # NEW: Grid position
			"grid_row": row_index,     # NEW: Grid row for targeting
			"grid_col": -1,  # Turrets don't have a column
			"container": turret_container,
			"sprite": sprite,
			"size": CombatConstants.TURRET_SIZE,
			"position": Vector2(x_pos, y_pos),
			"enabled": true,
			"current_armor": db_turret_data["armor"],
			"current_shield": db_turret_data["shield"],
			"stats": {
				"armor": db_turret_data["armor"],
				"shield": db_turret_data["shield"],
				"reinforced_armor": db_turret_data.get("reinforced_armor", 0),
				"damage": db_turret_data["damage"],
				"accuracy": db_turret_data["accuracy"],
				"attack_speed": db_turret_data["attack_speed"],
				"num_attacks": db_turret_data.get("num_attacks", 1),
				"evasion": db_turret_data.get("evasion", 0),
				"starting_energy": db_turret_data.get("starting_energy", 0)
			},
			"current_energy": db_turret_data.get("starting_energy", 0),
			"projectile_sprite": db_turret_data.get("projectile_sprite", "res://assets/Effects/laser_light/s_laser_light_001.png"),
			"projectile_size": db_turret_data.get("projectile_size", 30),
			"ability_function": db_turret_data.get("ability_function", ""),
			"ability_name": db_turret_data.get("ability", ""),
			"ability_description": db_turret_data.get("ability_description", "")
		}

		# Store in grid and legacy array
		ship_manager.set_turret_at_position(lane_index, row_index, turret_data, "enemy")
		enemy_turrets.append(turret_data)  # Also add to legacy array for compatibility

		# Create health bar
		create_health_bar(
			turret_container,
			CombatConstants.TURRET_SIZE,
			turret_data["current_shield"],
			turret_data["current_armor"]
		)

		# Initialize energy bar
		update_energy_bar(turret_data)
	else:
		# Create disabled turret placeholder
		var label = Label.new()
		label.name = "DisabledLabel"
		label.text = "[ ]"  # Empty slot indicator
		label.position = Vector2(-15, -15)
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", Color(0.5, 0.2, 0.2, 0.5))
		turret_container.add_child(label)

# Legacy function kept for backwards compatibility (not used in new grid system)
func create_enemy_turret(turret_name: String, turret_type: String, x_pos: float, y_pos: float, lane_index: int):
	# Get turret data from database
	var db_turret_data = DataManager.get_ship_data(turret_type)
	if db_turret_data == null:
		print("ERROR: Enemy turret type not found in database: ", turret_type)
		return

	# Create turret container
	var turret_container = Control.new()
	turret_container.name = turret_name
	turret_container.position = Vector2(x_pos, y_pos)
	turret_container.z_index = 10  # Render turrets above lanes
	add_child(turret_container)

	# Load turret sprite
	var turret_texture: Texture2D = load(db_turret_data["sprite_path"])

	# Create turret sprite
	var sprite = TextureRect.new()
	sprite.name = "Sprite"
	sprite.texture = turret_texture
	sprite.custom_minimum_size = Vector2(CombatConstants.TURRET_SIZE, CombatConstants.TURRET_SIZE)
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.position = Vector2(-CombatConstants.TURRET_SIZE / 2, -CombatConstants.TURRET_SIZE / 2)  # Center the sprite

	# Flip sprite to face left (toward player)
	sprite.flip_h = true

	turret_container.add_child(sprite)

	# Create turret data dictionary
	var turret_data = {
		"object_type": "enemy_turret",  # Mark as enemy turret type
		"faction": "enemy",  # Enemy faction
		"type": turret_type,
		"display_name": db_turret_data["display_name"],
		"container": turret_container,
		"sprite": sprite,
		"size": CombatConstants.TURRET_SIZE,
		"position": Vector2(x_pos, y_pos),
		"enabled": true,
		"target_lane": lane_index,  # This turret only attacks in this lane
		"current_armor": db_turret_data["armor"],
		"current_shield": db_turret_data["shield"],
		"stats": {
			"armor": db_turret_data["armor"],
			"shield": db_turret_data["shield"],
			"reinforced_armor": db_turret_data.get("reinforced_armor", 0),
			"damage": db_turret_data["damage"],
			"accuracy": db_turret_data["accuracy"],
			"attack_speed": db_turret_data["attack_speed"],
			"num_attacks": db_turret_data.get("num_attacks", 1),
			"evasion": db_turret_data.get("evasion", 0),
			"starting_energy": db_turret_data.get("starting_energy", 0)
		},
		"current_energy": db_turret_data.get("starting_energy", 0),
		"projectile_sprite": db_turret_data.get("projectile_sprite", "res://assets/Effects/laser_light/s_laser_light_001.png"),
		"projectile_size": db_turret_data.get("projectile_size", 30),
		"ability_function": db_turret_data.get("ability_function", ""),
		"ability_name": db_turret_data.get("ability", ""),
		"ability_description": db_turret_data.get("ability_description", "")
	}

	enemy_turrets.append(turret_data)

	# Create health bar
	create_health_bar(turret_container, CombatConstants.TURRET_SIZE, turret_data["current_shield"], turret_data["current_armor"])

	# Initialize energy bar
	update_energy_bar(turret_data)

func setup_enemy_boss():
	# Create enemy boss as a targetable combat object
	var boss_container = Control.new()
	boss_container.name = "EnemyBoss"
	# Position at top of combat area, spanning all lanes
	var combat_height = CombatConstants.LANE_SPACING * (CombatConstants.NUM_LANES - 1)
	boss_container.position = Vector2(CombatConstants.ENEMY_SPAWN_X, CombatConstants.LANE_Y_START)
	add_child(boss_container)

	# Add sprite (using elite enemy texture for now) - stretched vertically to span all lanes
	var sprite = TextureRect.new()
	sprite.name = "Sprite"
	sprite.texture = CombatConstants.EliteTexture
	sprite.custom_minimum_size = Vector2(CombatConstants.BOSS_SIZE, combat_height)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_SCALE
	sprite.flip_h = true  # Flip to face left
	boss_container.add_child(sprite)

	# Add label
	var label = Label.new()
	label.name = "Label"
	label.text = "ENEMY BOSS"
	label.position = Vector2(-20, CombatConstants.BOSS_SIZE + 10)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2, 1))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_container.add_child(label)

	# Create combat object Dictionary
	ship_manager.enemy_boss = {
		"object_type": "boss",
		"faction": "enemy",
		"type": "boss",
		"display_name": "Enemy Boss",
		"lane_index": -1,  # Special: not in a specific lane
		"grid_row": -1,  # Not in grid
		"grid_col": -1,
		"container": boss_container,
		"sprite": sprite,
		"size": CombatConstants.BOSS_SIZE,
		"current_armor": CombatConstants.BOSS_ARMOR,
		"current_shield": CombatConstants.BOSS_SHIELD,
		"stats": {
			"armor": CombatConstants.BOSS_ARMOR,
			"shield": CombatConstants.BOSS_SHIELD,
			"reinforced_armor": 0,
			"evasion": 0,
			"damage": 0,  # Boss doesn't attack in current implementation
			"accuracy": 0,
			"attack_speed": 0.0,
			"num_attacks": 0
		}
	}

	# Create health bar for boss
	create_health_bar(
		boss_container,
		CombatConstants.BOSS_SIZE,
		CombatConstants.BOSS_SHIELD,
		CombatConstants.BOSS_ARMOR
	)

	print("Enemy Boss created as targetable combat object with ", CombatConstants.BOSS_ARMOR, " armor, ", CombatConstants.BOSS_SHIELD, " shield")

func setup_resource_ui():
	# Create resource UI display
	var resource_ui = Control.new()
	resource_ui.name = "ResourceUI"
	var script = load("res://scripts/ResourceUI.gd")
	resource_ui.set_script(script)
	resource_ui.position = Vector2(20, 20)
	ui_layer.add_child(resource_ui)
	print("Resource UI created at top-left")

func setup_enemy_deployment_ui():
	# Create deploy enemy button (for testing)
	deploy_enemy_button = Button.new()
	deploy_enemy_button.name = "DeployEnemyButton"
	deploy_enemy_button.text = "DEPLOY ENEMY"
	deploy_enemy_button.position = Vector2(0, 550)  # Below player deploy button
	deploy_enemy_button.size = Vector2(200, 50)
	deploy_enemy_button.add_theme_font_size_override("font_size", 18)
	deploy_enemy_button.add_to_group("ui")
	deploy_enemy_button.pressed.connect(_on_deploy_enemy_button_pressed)
	add_child(deploy_enemy_button)

	# Get enemy ships from database
	var enemy_ships = DataManager.get_ships_by_faction("enemy")

	# Calculate panel height based on number of enemies
	var button_height = 50
	var button_spacing = 10
	var title_height = 60
	var close_button_height = 40
	var panel_height = title_height + (enemy_ships.size() * (button_height + button_spacing)) + close_button_height + 20

	# Create enemy selection panel (initially hidden)
	enemy_selection_panel = Panel.new()
	enemy_selection_panel.name = "EnemySelectionPanel"
	enemy_selection_panel.position = Vector2(350, 150)
	enemy_selection_panel.size = Vector2(450, panel_height)
	enemy_selection_panel.visible = false
	enemy_selection_panel.add_to_group("ui")
	add_child(enemy_selection_panel)

	# Add panel background
	var bg = ColorRect.new()
	bg.color = Color(0.2, 0.15, 0.15, 0.95)
	bg.size = enemy_selection_panel.size
	enemy_selection_panel.add_child(bg)

	# Add title
	var title = Label.new()
	title.text = "SELECT ENEMY TO DEPLOY"
	title.position = Vector2(20, 20)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
	enemy_selection_panel.add_child(title)

	# Create enemy selection buttons dynamically from database
	for i in range(enemy_ships.size()):
		var enemy_data = enemy_ships[i]
		var enemy_id = enemy_data["ship_id"]
		var display_name = enemy_data["display_name"]
		var sprite_path = enemy_data["sprite_path"]
		var enemy_size = enemy_data["size"]

		var button_y = title_height + (i * (button_height + button_spacing))

		var enemy_button = Button.new()
		enemy_button.name = enemy_id + "_button"
		enemy_button.position = Vector2(20, button_y)
		enemy_button.size = Vector2(410, button_height)
		enemy_button.text = display_name
		enemy_button.add_theme_font_size_override("font_size", 20)
		enemy_button.pressed.connect(_on_enemy_selected.bind(enemy_id))
		enemy_selection_panel.add_child(enemy_button)

		# Add enemy icon to button
		var icon = TextureRect.new()
		icon.texture = load(sprite_path)
		var icon_y = (button_height - enemy_size) / 2
		icon.position = Vector2(10, icon_y)
		icon.custom_minimum_size = Vector2(enemy_size, enemy_size)
		icon.size = Vector2(enemy_size, enemy_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		enemy_button.add_child(icon)

	# Add close button at bottom
	var close_button_y = panel_height - close_button_height - 10
	var close_button = Button.new()
	close_button.text = "CANCEL"
	close_button.position = Vector2(150, close_button_y)
	close_button.size = Vector2(150, 30)
	close_button.pressed.connect(_on_close_enemy_panel)
	enemy_selection_panel.add_child(close_button)

func _on_deploy_enemy_button_pressed():
	# Show enemy selection panel
	enemy_selection_panel.visible = true
	print("Deploy enemy button pressed - showing enemy selection")

func _on_enemy_selected(enemy_type: String):
	# Store selected enemy type
	selected_enemy_type = enemy_type
	enemy_selection_panel.visible = false
	print("Selected enemy: ", enemy_type, " - Click a lane to deploy")

func _on_close_enemy_panel():
	# Hide panel and clear selection
	enemy_selection_panel.visible = false
	selected_enemy_type = ""
	print("Enemy selection cancelled")

func setup_deployment_ui():
	# Create deploy ships button in top-right corner
	deploy_button = Button.new()
	deploy_button.name = "DeployButton"
	deploy_button.text = "DEPLOY SHIP"
	deploy_button.position = Vector2(0, 500)
	deploy_button.size = Vector2(200, 50)
	deploy_button.add_theme_font_size_override("font_size", 18)
	deploy_button.add_to_group("ui")
	deploy_button.pressed.connect(_on_deploy_button_pressed)
	add_child(deploy_button)

	# Get player ships from database
	var player_ships = DataManager.get_ships_by_faction("player")

	# Calculate panel height based on number of ships
	var button_height = 70
	var button_spacing = 10
	var title_height = 60
	var close_button_height = 40
	var panel_height = title_height + (player_ships.size() * (button_height + button_spacing)) + close_button_height + 20

	# Create ship selection panel (initially hidden)
	ship_selection_panel = Panel.new()
	ship_selection_panel.name = "ShipSelectionPanel"
	ship_selection_panel.position = Vector2(350, 150)
	ship_selection_panel.size = Vector2(450, panel_height)
	ship_selection_panel.visible = false
	ship_selection_panel.add_to_group("ui")
	add_child(ship_selection_panel)

	# Add panel background
	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.2, 0.95)
	bg.size = ship_selection_panel.size
	ship_selection_panel.add_child(bg)

	# Add title
	var title = Label.new()
	title.text = "SELECT SHIP TO DEPLOY"
	title.position = Vector2(20, 20)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 1, 1))
	ship_selection_panel.add_child(title)

	# Create ship selection buttons dynamically from database
	for i in range(player_ships.size()):
		var ship_data = player_ships[i]
		var ship_id = ship_data["ship_id"]
		var display_name = ship_data["display_name"]
		var sprite_path = ship_data["sprite_path"]
		var ship_size = ship_data["size"]

		var button_y = title_height + (i * (button_height + button_spacing))

		var ship_button = Button.new()
		ship_button.name = ship_id + "_button"
		ship_button.position = Vector2(20, button_y)
		ship_button.size = Vector2(410, button_height)
		ship_button.text = display_name
		ship_button.add_theme_font_size_override("font_size", 20)
		ship_button.pressed.connect(_on_ship_selected.bind(ship_id))
		ship_selection_panel.add_child(ship_button)

		# Add ship icon to button
		var icon = TextureRect.new()
		icon.texture = load(sprite_path)
		# Center the icon vertically in the button
		var icon_y = (button_height - ship_size) / 2
		icon.position = Vector2(10, icon_y)
		icon.custom_minimum_size = Vector2(ship_size, ship_size)
		icon.size = Vector2(ship_size, ship_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ship_button.add_child(icon)

	# Add close button at bottom
	var close_button_y = panel_height - close_button_height - 10
	var close_button = Button.new()
	close_button.text = "CANCEL"
	close_button.position = Vector2(150, close_button_y)
	close_button.size = Vector2(150, 30)
	close_button.pressed.connect(_on_close_panel)
	ship_selection_panel.add_child(close_button)

func _on_deploy_button_pressed():
	# Show ship selection panel
	ship_selection_panel.visible = true
	print("Deploy button pressed - showing ship selection")

func _on_ship_selected(ship_type: String):
	# Store selected ship type
	selected_ship_type = ship_type
	ship_selection_panel.visible = false
	print("Selected ship: ", ship_type, " - Click a lane to deploy")

	# Visual feedback - change cursor or add indicator
	# Player should now click a lane to deploy

func _on_close_panel():
	# Hide panel and clear selection
	ship_selection_panel.visible = false
	selected_ship_type = ""
	print("Ship selection cancelled")

func _input(event):
	# Handle escape key to return to tactical view
	if event.is_action_pressed("ui_cancel") and is_zoomed:
		_on_return_to_tactical()
		get_viewport().set_input_as_handled()
		return

	# Handle mouse motion for ship dragging
	if event is InputEventMouseMotion and is_dragging_ship:
		update_ghost_ship_position(get_global_mouse_position())
		return

	# Handle mouse button release - end drag
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_dragging_ship:
			end_ship_drag(get_global_mouse_position())
			get_viewport().set_input_as_handled()
			return

	# Handle lane click for ship deployment or zoom
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Don't process if clicking on UI elements
		if ship_selection_panel.visible or enemy_selection_panel.visible:
			return

		# Check if click is on any UI button or control element
		var mouse_pos = get_global_mouse_position()
		if is_clicking_on_ui(mouse_pos):
			return

		var lane_index = get_lane_at_position(mouse_pos)

		if selected_ship_type != "":
			# Ship selected - deploy to lane
			if lane_index != -1:
				deploy_ship_to_lane(selected_ship_type, lane_index)
				selected_ship_type = ""  # Clear selection after deployment
		elif selected_enemy_type != "":
			# Enemy selected - deploy to lane
			if lane_index != -1:
				deploy_enemy_to_lane(selected_enemy_type, lane_index)
				selected_enemy_type = ""  # Clear selection after deployment
		else:
			# Check for ship drag ONLY during lane precombat phase (zoomed but paused)
			if combat_paused and is_zoomed:
				var clicked_unit = get_unit_at_position(mouse_pos)
				if clicked_unit != null and not clicked_unit.is_empty():
					# Only allow dragging ships, not turrets
					var is_turret = clicked_unit.get("object_type", "") in ["turret", "enemy_turret"]
					if not is_turret:
						# Check if ship can be moved (hasn't moved this turn)
						if not clicked_unit.get("has_moved_this_turn", false):
							start_ship_drag(clicked_unit, mouse_pos)
							get_viewport().set_input_as_handled()
							return

			# Manual lane zoom removed - use turn progression button only

func is_clicking_on_ui(mouse_pos: Vector2) -> bool:
	# Check if mouse position is over any UI element (buttons, panels, etc.)
	# This prevents clicking through UI elements to the game world

	# Get all nodes and check if any Control nodes contain the mouse position
	var all_nodes = get_tree().get_nodes_in_group("ui")
	for node in all_nodes:
		if node is Control and node.visible:
			var rect = Rect2(node.global_position, node.size)
			if rect.has_point(mouse_pos):
				return true

	# Also check common UI elements directly
	var ui_elements = [
		deploy_button,
		deploy_enemy_button,
		ship_selection_panel,
		enemy_selection_panel,
		return_button,
		auto_combat_button,
		turn_progression_button,
		auto_deploy_button
	]

	for element in ui_elements:
		if element != null and is_instance_valid(element) and element.visible:
			var rect = Rect2(element.global_position, element.size)
			if rect.has_point(mouse_pos):
				return true

	return false

func get_lane_at_position(pos: Vector2) -> int:
	# Determine which lane a position is in
	for i in range(CombatConstants.NUM_LANES):
		var lane_y = lanes[i]["y_position"]
		# Check if mouse is within 75 pixels above or below lane center
		if abs(pos.y - lane_y) < 75:
			return i
	return -1

func get_unit_at_position(pos: Vector2) -> Dictionary:
	# Check if mouse position intersects with any unit (ship, enemy, or turret)

	# Check player turrets
	for turret in turrets:
		if not turret.has("container") or not turret.has("size"):
			continue

		var container = turret["container"]
		var turret_size = turret["size"]
		var turret_pos = container.position

		# Create bounding box for turret
		var box_x1 = turret_pos.x - turret_size / 2
		var box_y1 = turret_pos.y - turret_size / 2
		var box_x2 = turret_pos.x + turret_size / 2
		var box_y2 = turret_pos.y + turret_size / 2

		# Check if mouse is inside bounding box
		if pos.x >= box_x1 and pos.x <= box_x2 and pos.y >= box_y1 and pos.y <= box_y2:
			print("Found player turret at position - type: ", turret.get("type", "unknown"))
			return turret

	# Check enemy turrets
	for enemy_turret in enemy_turrets:
		if not enemy_turret.has("container") or not enemy_turret.has("size"):
			continue

		var container = enemy_turret["container"]
		var turret_size = enemy_turret["size"]
		var turret_pos = container.position

		# Create bounding box for turret
		var box_x1 = turret_pos.x - turret_size / 2
		var box_y1 = turret_pos.y - turret_size / 2
		var box_x2 = turret_pos.x + turret_size / 2
		var box_y2 = turret_pos.y + turret_size / 2

		# Check if mouse is inside bounding box
		if pos.x >= box_x1 and pos.x <= box_x2 and pos.y >= box_y1 and pos.y <= box_y2:
			print("Found enemy turret at position - type: ", enemy_turret.get("type", "unknown"))
			return enemy_turret

	# Check ships in lanes
	for lane in lanes:
		for unit in lane["units"]:
			if not unit.has("container") or not unit.has("size"):
				print("Warning: Invalid unit data in lane")
				continue

			var container = unit["container"]
			var unit_size = unit["size"]
			var unit_pos = container.position

			# Create bounding box for unit
			var box_x1 = unit_pos.x
			var box_y1 = unit_pos.y
			var box_x2 = unit_pos.x + unit_size
			var box_y2 = unit_pos.y + unit_size

			# Check if mouse is inside bounding box
			if pos.x >= box_x1 and pos.x <= box_x2 and pos.y >= box_y1 and pos.y <= box_y2:
				print("Found unit at position - type: ", unit.get("type", "unknown"), ", is_enemy: ", unit.get("is_enemy", false))
				return unit

	return {}  # Return empty dictionary if no unit found

func handle_unit_click(unit: Dictionary):
	# Handle clicking on a unit for combat
	# Now works for both player->enemy and enemy->player combat
	if unit.is_empty():
		print("Error: handle_unit_click called with empty unit")
		return

	var is_enemy = unit.get("is_enemy", false)
	print("Handling unit click - is_enemy: ", is_enemy)

	# First click: Select attacker (any unit)
	if selected_attacker.is_empty():
		select_attacker(unit)
		return

	# Clicking the same unit: Deselect
	if selected_attacker == unit:
		deselect_attacker()
		return

	# Check if this is a valid target
	var attacker_is_enemy = selected_attacker.get("is_enemy", false)
	var target_is_enemy = unit.get("is_enemy", false)

	# Valid targeting: attacker and target must be on opposite sides
	if attacker_is_enemy != target_is_enemy:
		# Valid target - start attacking
		select_target(unit)
	else:
		# Same side - switch to new attacker
		deselect_attacker()
		select_attacker(unit)

func select_attacker(unit: Dictionary):
	# Select any unit as the attacker (player ship or enemy)
	if unit.is_empty():
		print("Error: Attempted to select empty unit")
		return

	selected_attacker = unit
	var unit_type = unit.get("type", "unknown")
	var is_enemy = unit.get("is_enemy", false)
	print("Selected attacker: ", unit_type, " (enemy: ", is_enemy, ")")

	# Visual feedback - different colors for player vs enemy
	if unit.has("sprite"):
		var sprite = unit["sprite"]
		if is_enemy:
			sprite.modulate = Color(1.5, 0.5, 0.5)  # Red tint for enemy attackers
		else:
			sprite.modulate = Color(1.2, 1.2, 1.0)  # Yellow tint for player attackers
	else:
		print("Warning: Unit has no sprite")

func deselect_attacker():
	# Deselect the current attacker and stop attacking
	if not selected_attacker.is_empty():
		print("Deselected attacker")

		# Remove visual feedback
		var sprite = selected_attacker["sprite"]
		sprite.modulate = Color(1, 1, 1)  # Reset to normal

		# Stop attack timer if it exists
		stop_continuous_attack()

		selected_attacker = {}
		selected_target = {}

func select_target(unit: Dictionary):
	# Select an enemy as the target
	selected_target = unit
	print("Selected target: ", unit["type"])

	# Start attacking
	start_attack_sequence()

func deploy_ship_to_lane(ship_type: String, lane_index: int):
	# Deploy a ship to the specified lane
	print("Deploying ", ship_type, " to lane ", lane_index)

	# Get ship data from database
	var db_ship_data = DataManager.get_ship_data(ship_type)
	if db_ship_data.is_empty():
		print("ERROR: Ship type '", ship_type, "' not found in database")
		return

	# Extract ship properties from database
	var ship_texture: Texture2D = load(db_ship_data["sprite_path"])
	var ship_size: int = db_ship_data["size"]
	var deploy_duration: float = db_ship_data.get("deploy_speed", 3.0)  # Default 3.0s if not specified

	# Find random empty cell in player deployment zone (columns 0-3)
	var cell = get_random_empty_cell(lane_index, CombatConstants.PLAYER_DEPLOY_COLS)
	if cell == Vector2i(-1, -1):
		print("ERROR: No empty cells available in lane ", lane_index)
		return

	# Get target position at center of cell
	var cell_center = get_cell_world_position(lane_index, cell.x, cell.y)
	var target_x = cell_center.x - (ship_size / 2)
	var target_y = cell_center.y - (ship_size / 2)

	# Create ship sprite at mothership position
	var ship_container = Control.new()
	ship_container.name = ship_type + "_" + str(Time.get_ticks_msec())

	# Get mothership center position - all ships spawn from same point
	var mothership = get_node_or_null("Mothership")
	var mothership_center_y = get_viewport_rect().size.y / 2  # Screen center
	var start_pos: Vector2
	if mothership:
		# Center on mothership sprite
		start_pos = Vector2(mothership.position.x + 75, mothership_center_y - (ship_size / 2))
	else:
		start_pos = Vector2(CombatConstants.MOTHERSHIP_X + 75, mothership_center_y - (ship_size / 2))

	ship_container.position = start_pos
	add_child(ship_container)

	var sprite = TextureRect.new()
	sprite.name = "Sprite"
	sprite.texture = ship_texture
	sprite.custom_minimum_size = Vector2(ship_size, ship_size)
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Set pivot for rotation
	sprite.pivot_offset = Vector2(ship_size / 2, ship_size / 2)
	sprite.rotation = -PI / 2  # Start pointing up/north
	ship_container.add_child(sprite)

	# Calculate rotation angle to target
	var direction = Vector2(target_x, target_y) - start_pos
	var target_rotation = direction.angle()  # No offset needed, 0° is correct

	# Position animation: ease out for acceleration, ease in for braking
	# Split into two parts: accelerate then brake
	var halfway_pos = start_pos.lerp(Vector2(target_x, target_y), 0.5)

	# First half: accelerate (ease out)
	var tween_accel = create_tween()
	tween_accel.set_trans(Tween.TRANS_CUBIC)
	tween_accel.set_ease(Tween.EASE_OUT)
	tween_accel.tween_property(ship_container, "position", halfway_pos, deploy_duration * 0.4)

	# Rotation: quick rotation at the start (run parallel with acceleration)
	var tween_rotation = create_tween()
	tween_rotation.set_trans(Tween.TRANS_BACK)
	tween_rotation.set_ease(Tween.EASE_OUT)
	tween_rotation.tween_property(sprite, "rotation", target_rotation, deploy_duration * 0.3)

	# Wait for acceleration phase
	await tween_accel.finished

	# Second half: brake (ease in)
	var tween_brake = create_tween()
	tween_brake.set_trans(Tween.TRANS_CUBIC)
	tween_brake.set_ease(Tween.EASE_IN)
	tween_brake.tween_property(ship_container, "position", Vector2(target_x, target_y), deploy_duration * 0.6)

	# Wait for braking to complete
	await tween_brake.finished

	# Store original position for idle behavior
	var ship_data = {
		"object_type": "ship",  # Distinguish from turrets
		"type": ship_type,
		"faction": "player",  # Add faction field for targeting system
		"is_enemy": false,  # Boolean for quick checks
		"container": ship_container,
		"sprite": sprite,
		"size": ship_size,
		"original_position": Vector2(target_x, target_y),
		"idle_state": "waiting",  # States: waiting, drifting, returning
		"idle_timer": 0.0,
		"idle_paused": false,  # Paused during lane combat

		# Grid position
		"grid_row": cell.x,
		"grid_col": cell.y,
		"lane_index": lane_index,

		# Movement
		"movement_speed": db_ship_data.get("movement_speed", 2),  # Hardcoded to 2 for now
		"has_moved_this_turn": false,

		# Combat stats
		"stats": db_ship_data["stats"].duplicate(),
		"current_armor": db_ship_data["stats"]["armor"],
		"current_shield": db_ship_data["stats"]["shield"],
		"current_overshield": 0,  # Temporary shields, dissipates after lane 3
		"current_energy": db_ship_data["stats"]["starting_energy"],

		# Projectile data
		"projectile_sprite": db_ship_data.get("projectile_sprite", "res://assets/Effects/laser_light/s_laser_light_001.png"),
		"projectile_size": db_ship_data.get("projectile_size", 6),

		# Ability data
		"ability_function": db_ship_data.get("ability_function", ""),
		"ability_name": db_ship_data.get("ability", ""),
		"ability_description": db_ship_data.get("ability_description", ""),

		# Ability stack/queue system
		"ability_stack": [],  # Queue of abilities to execute
		"is_processing_abilities": false,  # True while executing abilities from stack

		# Status effects and elemental damage
		"status_effects": [],  # Array of active status effects (burn, freeze, etc.)
		"damage_types": []  # Array of elemental damage types (fire, ice, acid, etc.)
	}

	# Mark grid cell as occupied
	occupy_grid_cell(lane_index, cell.x, cell.y, ship_data)

	# Add to lane data
	lanes[lane_index]["units"].append(ship_data)

	# Create health bar
	create_health_bar(ship_container, ship_size, ship_data["current_shield"], ship_data["current_armor"])

	# Initialize energy bar
	update_energy_bar(ship_data)
	
	# Add hover detection for tooltip
	add_ship_hover_detection(ship_container, ship_data)

	# Start idle behavior
	start_ship_idle_behavior(ship_data)

	print("Ship deployed successfully at x=", target_x, " y=", target_y, " with size=", ship_size, " | Stats: Armor=", ship_data["current_armor"], " Shield=", ship_data["current_shield"], " AttackSpeed=", ship_data["stats"]["attack_speed"])

func deploy_enemy_to_lane(enemy_type: String, lane_index: int):
	# Deploy an enemy to the specified lane
	print("Deploying ", enemy_type, " to lane ", lane_index)

	# Get enemy data from database
	var db_enemy_data = DataManager.get_ship_data(enemy_type)
	if db_enemy_data.is_empty():
		print("ERROR: Enemy type '", enemy_type, "' not found in database")
		return

	# Extract enemy properties from database
	var enemy_texture: Texture2D = load(db_enemy_data["sprite_path"])
	var enemy_size: int = db_enemy_data["size"]

	# Find random empty cell in enemy deployment zone (columns 6-9)
	var cell = get_random_empty_cell(lane_index, CombatConstants.ENEMY_DEPLOY_COLS)
	if cell == Vector2i(-1, -1):
		print("ERROR: No empty cells available in lane ", lane_index, " for enemy deployment")
		return

	# Get target position at center of cell
	var cell_center = get_cell_world_position(lane_index, cell.x, cell.y)
	var x_pos = cell_center.x - (enemy_size / 2)
	var target_y = cell_center.y - (enemy_size / 2)

	# Create enemy sprite container
	var enemy_container = Control.new()
	enemy_container.name = enemy_type + "_enemy_" + str(Time.get_ticks_msec())
	enemy_container.position = Vector2(x_pos, target_y)
	add_child(enemy_container)

	var sprite = TextureRect.new()
	sprite.name = "Sprite"
	sprite.texture = enemy_texture
	sprite.custom_minimum_size = Vector2(enemy_size, enemy_size)
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Rotate enemy to face left (toward player)
	sprite.pivot_offset = Vector2(enemy_size / 2, enemy_size / 2)
	sprite.rotation = PI  # 180 degrees to face left

	enemy_container.add_child(sprite)

	# Create enemy data
	var enemy_data = {
		"object_type": "ship",  # Enemies are also ships (not turrets)
		"type": enemy_type,
		"faction": "enemy",  # Add faction field for targeting system
		"is_enemy": true,  # Boolean for quick checks
		"container": enemy_container,
		"sprite": sprite,
		"size": enemy_size,
		"position": Vector2(x_pos, target_y),
		"original_position": Vector2(x_pos, target_y),
		"idle_paused": false,  # Paused during lane combat

		# Grid position
		"grid_row": cell.x,
		"grid_col": cell.y,
		"lane_index": lane_index,

		# Movement
		"movement_speed": db_enemy_data.get("movement_speed", 2),  # Hardcoded to 2 for now
		"has_moved_this_turn": false,

		# Combat stats
		"stats": db_enemy_data["stats"].duplicate(),
		"current_armor": db_enemy_data["stats"]["armor"],
		"current_shield": db_enemy_data["stats"]["shield"],
		"current_overshield": 0,  # Temporary shields, dissipates after lane 3
		"current_energy": db_enemy_data["stats"]["starting_energy"],

		# Projectile data
		"projectile_sprite": db_enemy_data.get("projectile_sprite", "res://assets/Effects/laser_light/s_laser_light_001.png"),
		"projectile_size": db_enemy_data.get("projectile_size", 6),

		# Ability data
		"ability_function": db_enemy_data.get("ability_function", ""),
		"ability_name": db_enemy_data.get("abilty", ""),
		"ability_description": db_enemy_data.get("ability_description", ""),

		# Ability stack/queue system
		"ability_stack": [],  # Queue of abilities to execute
		"is_processing_abilities": false,  # True while executing abilities from stack

		# Status effects and elemental damage
		"status_effects": [],  # Array of active status effects (burn, freeze, etc.)
		"damage_types": []  # Array of elemental damage types (fire, ice, acid, etc.)
	}

	# Mark grid cell as occupied
	occupy_grid_cell(lane_index, cell.x, cell.y, enemy_data)

	# Add to lane data
	lanes[lane_index]["units"].append(enemy_data)

	# Create health bar
	create_health_bar(enemy_container, enemy_size, enemy_data["current_shield"], enemy_data["current_armor"])

	# Initialize energy bar
	update_energy_bar(enemy_data)
	
	# Add hover detection for tooltip
	add_ship_hover_detection(enemy_container, enemy_data)

	print("Enemy deployed successfully at x=", x_pos, " y=", target_y, " with size=", enemy_size, " | Stats: Armor=", db_enemy_data["stats"]["armor"], " Shield=", db_enemy_data["stats"]["shield"], " AttackSpeed=", db_enemy_data["stats"]["attack_speed"])

func start_ship_idle_behavior(ship_data: Dictionary):
	# Initial rotation to face enemy
	var sprite = ship_data["sprite"]
	var ship_container = ship_data["container"]

	# Calculate angle to enemy spawner
	var ship_pos = ship_data["original_position"]
	var enemy_pos = Vector2(CombatConstants.ENEMY_SPAWN_X, ship_pos.y)  # Enemy at same lane height
	var direction_to_enemy = enemy_pos - ship_pos
	var target_rotation = direction_to_enemy.angle()  # No offset needed

	# Smoothly rotate to face enemy
	var rotate_tween = create_tween()
	rotate_tween.set_trans(Tween.TRANS_SINE)
	rotate_tween.set_ease(Tween.EASE_IN_OUT)
	rotate_tween.tween_property(sprite, "rotation", target_rotation, 1.5)

	# Start idle cycle after delay
	await get_tree().create_timer(CombatConstants.DRIFT_DELAY).timeout

	# Check if ship still exists
	if not is_instance_valid(ship_container):
		return

	idle_cycle(ship_data)

func idle_cycle(ship_data: Dictionary):
	while is_instance_valid(ship_data["container"]):
		# Check if idle is paused (during lane combat)
		if ship_data.get("idle_paused", false):
			# Skip idle animation while paused, just wait and check again
			await get_tree().create_timer(0.5).timeout
			continue

		# Drift backward phase
		ship_data["idle_state"] = "drifting"
		await drift_backward(ship_data)

		if not is_instance_valid(ship_data["container"]):
			return

		# Short pause
		await get_tree().create_timer(0.5).timeout

		if not is_instance_valid(ship_data["container"]):
			return

		# Check pause status again before returning
		if ship_data.get("idle_paused", false):
			await get_tree().create_timer(0.5).timeout
			continue

		# Return to position phase
		ship_data["idle_state"] = "returning"
		await return_to_position(ship_data)

		if not is_instance_valid(ship_data["container"]):
			return

		# Wait before next cycle
		ship_data["idle_state"] = "waiting"
		await get_tree().create_timer(CombatConstants.DRIFT_DELAY).timeout

func drift_backward(ship_data: Dictionary) -> void:
	var ship_container = ship_data["container"]
	var original_pos = ship_data["original_position"]

	# Drift slowly toward mothership
	var drift_target = Vector2(original_pos.x - CombatConstants.DRIFT_DISTANCE, original_pos.y)

	var drift_tween = create_tween()
	drift_tween.set_trans(Tween.TRANS_SINE)
	drift_tween.set_ease(Tween.EASE_IN_OUT)
	drift_tween.tween_property(ship_container, "position", drift_target, CombatConstants.DRIFT_DURATION)

	await drift_tween.finished

func return_to_position(ship_data: Dictionary) -> void:
	var ship_container = ship_data["container"]
	var sprite = ship_data["sprite"]
	var original_pos = ship_data["original_position"]

	# Brief acceleration back to position
	var return_tween = create_tween()
	return_tween.set_trans(Tween.TRANS_CUBIC)
	return_tween.set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(ship_container, "position", original_pos, CombatConstants.RETURN_DURATION)

	# Slight rotation adjustment (subtle wobble)
	var current_rotation = sprite.rotation
	var wobble_rotation = current_rotation + deg_to_rad(randf_range(-3, 3))
	var sprite_tween = create_tween()
	sprite_tween.set_trans(Tween.TRANS_SINE)
	sprite_tween.set_ease(Tween.EASE_IN_OUT)
	sprite_tween.tween_property(sprite, "rotation", wobble_rotation, CombatConstants.RETURN_DURATION * 0.3)
	sprite_tween.tween_property(sprite, "rotation", current_rotation, CombatConstants.RETURN_DURATION * 0.7)

	await return_tween.finished

func setup_return_button():
	# Create close button to return to tactical view (initially hidden)
	return_button = TextureButton.new()
	return_button.name = "ReturnButton"
	return_button.texture_normal = CombatConstants.CloseButtonTexture
	return_button.position = Vector2(1110, 10)
	return_button.custom_minimum_size = Vector2(30, 30)
	return_button.ignore_texture_size = true
	return_button.add_to_group("ui")
	return_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	return_button.visible = false
	return_button.pressed.connect(_on_return_to_tactical)

	# Add to UI layer so it's not affected by camera zoom
	ui_layer.add_child(return_button)

func setup_auto_combat_button():
	# Create auto-combat button
	auto_combat_button = Button.new()
	auto_combat_button.name = "AutoCombatButton"
	auto_combat_button.text = "START AUTO-COMBAT"
	auto_combat_button.position = Vector2(0, 400)
	auto_combat_button.size = Vector2(250, 50)
	auto_combat_button.add_theme_font_size_override("font_size", 18)
	auto_combat_button.add_to_group("ui")
	auto_combat_button.pressed.connect(_on_auto_combat_toggled)
	add_child(auto_combat_button)

func setup_auto_deploy_button():
	# Create auto-deploy button
	auto_deploy_button = Button.new()
	auto_deploy_button.name = "AutoDeployButton"
	auto_deploy_button.text = "AUTO-DEPLOY"
	auto_deploy_button.position = Vector2(0, 450)  # Below auto-combat button
	auto_deploy_button.size = Vector2(250, 50)
	auto_deploy_button.add_theme_font_size_override("font_size", 18)
	auto_deploy_button.add_to_group("ui")
	auto_deploy_button.pressed.connect(_on_auto_deploy_pressed)
	add_child(auto_deploy_button)

func setup_debug_ui():
	# Create debug button (bottom-left corner, always visible)
	debug_button = Button.new()
	debug_button.name = "DebugButton"
	debug_button.text = "Debug"
	debug_button.position = Vector2(10, 600)  # Bottom-left
	debug_button.custom_minimum_size = Vector2(80, 40)
	debug_button.add_theme_font_size_override("font_size", 14)
	debug_button.pressed.connect(_on_debug_button_pressed)
	ui_layer.add_child(debug_button)

	# Create debug panel (initially hidden)
	debug_panel = Panel.new()
	debug_panel.name = "DebugPanel"
	debug_panel.position = Vector2(100, 200)
	debug_panel.custom_minimum_size = Vector2(400, 300)
	debug_panel.visible = false
	ui_layer.add_child(debug_panel)

	# Add title
	var title = Label.new()
	title.text = "Debug Controls"
	title.position = Vector2(10, 10)
	title.add_theme_font_size_override("font_size", 20)
	debug_panel.add_child(title)

	# Player targeting label
	var player_label = Label.new()
	player_label.text = "Player Targeting:"
	player_label.position = Vector2(10, 60)
	player_label.add_theme_font_size_override("font_size", 16)
	debug_panel.add_child(player_label)

	# Player targeting buttons
	var player_random_btn = Button.new()
	player_random_btn.text = "Random"
	player_random_btn.position = Vector2(180, 55)
	player_random_btn.custom_minimum_size = Vector2(90, 35)
	player_random_btn.pressed.connect(func(): set_player_targeting("random"))
	debug_panel.add_child(player_random_btn)

	var player_alpha_btn = Button.new()
	player_alpha_btn.text = "Alpha"
	player_alpha_btn.position = Vector2(280, 55)
	player_alpha_btn.custom_minimum_size = Vector2(90, 35)
	player_alpha_btn.toggle_mode = true
	player_alpha_btn.button_pressed = true  # Alpha is default
	player_alpha_btn.pressed.connect(func(): set_player_targeting("alpha"))
	debug_panel.add_child(player_alpha_btn)

	var player_beta_btn = Button.new()
	player_beta_btn.text = "Beta"
	player_beta_btn.position = Vector2(180, 95)
	player_beta_btn.custom_minimum_size = Vector2(90, 35)
	player_beta_btn.pressed.connect(func(): set_player_targeting("beta"))
	debug_panel.add_child(player_beta_btn)

	# Enemy targeting label
	var enemy_label = Label.new()
	enemy_label.text = "Enemy Targeting:"
	enemy_label.position = Vector2(10, 145)
	enemy_label.add_theme_font_size_override("font_size", 16)
	debug_panel.add_child(enemy_label)

	# Enemy targeting buttons
	var enemy_random_btn = Button.new()
	enemy_random_btn.text = "Random"
	enemy_random_btn.position = Vector2(180, 140)
	enemy_random_btn.custom_minimum_size = Vector2(90, 35)
	enemy_random_btn.pressed.connect(func(): set_enemy_targeting("random"))
	debug_panel.add_child(enemy_random_btn)

	var enemy_alpha_btn = Button.new()
	enemy_alpha_btn.text = "Alpha"
	enemy_alpha_btn.position = Vector2(280, 140)
	enemy_alpha_btn.custom_minimum_size = Vector2(90, 35)
	enemy_alpha_btn.toggle_mode = true
	enemy_alpha_btn.button_pressed = true  # Alpha is default
	enemy_alpha_btn.pressed.connect(func(): set_enemy_targeting("alpha"))
	debug_panel.add_child(enemy_alpha_btn)

	var enemy_beta_btn = Button.new()
	enemy_beta_btn.text = "Beta"
	enemy_beta_btn.position = Vector2(180, 180)
	enemy_beta_btn.custom_minimum_size = Vector2(90, 35)
	enemy_beta_btn.pressed.connect(func(): set_enemy_targeting("beta"))
	debug_panel.add_child(enemy_beta_btn)

	# Current status label
	var status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "Player: Alpha | Enemy: Alpha"
	status_label.position = Vector2(10, 230)
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	debug_panel.add_child(status_label)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.position = Vector2(300, 260)
	close_btn.custom_minimum_size = Vector2(80, 35)
	close_btn.pressed.connect(_on_debug_close_pressed)
	debug_panel.add_child(close_btn)

	print("Debug UI initialized")

func _on_debug_button_pressed():
	# Toggle debug panel visibility
	if debug_panel:
		debug_panel.visible = !debug_panel.visible

func _on_debug_close_pressed():
	# Hide debug panel
	if debug_panel:
		debug_panel.visible = false

func set_player_targeting(mode: String):
	# Set player targeting mode and reassign all player unit targets
	player_targeting_mode = mode
	print("Player targeting mode changed to: ", mode)

	# Update status label
	update_debug_status_label()

	# Reassign all player targets
	reassign_all_targets()

func set_enemy_targeting(mode: String):
	# Set enemy targeting mode and reassign all enemy unit targets
	enemy_targeting_mode = mode
	print("Enemy targeting mode changed to: ", mode)

	# Update status label
	update_debug_status_label()

	# Reassign all enemy targets
	reassign_all_targets()

func update_debug_status_label():
	# Update the status label in debug panel
	if debug_panel:
		var status_label = debug_panel.get_node_or_null("StatusLabel")
		if status_label:
			status_label.text = "Player: " + player_targeting_mode.capitalize() + " | Enemy: " + enemy_targeting_mode.capitalize()

func reassign_all_targets():
	# Reassign targets for all active units using their current targeting mode
	print("Reassigning all unit targets...")

	for lane in lanes:
		for unit in lane["units"]:
			# Clear existing target
			unit.erase("auto_target")

			# Assign new target based on current mode
			assign_random_target(unit)

	print("Target reassignment complete")

func setup_zoom_timer_label():
	# Create zoom timer countdown label
	zoom_timer_label = Label.new()
	zoom_timer_label.name = "ZoomTimerLabel"
	zoom_timer_label.text = "LANE 1: 5s"
	zoom_timer_label.position = Vector2(400, 150)  # Top center, below other buttons
	zoom_timer_label.add_theme_font_size_override("font_size", 28)
	zoom_timer_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))  # Bright yellow/gold
	zoom_timer_label.visible = false  # Hidden by default

	# Add to UI layer so it's not affected by camera zoom
	ui_layer.add_child(zoom_timer_label)

func setup_turn_progression_button():
	# Create turn progression button in bottom-right corner
	turn_progression_button = Button.new()
	turn_progression_button.name = "TurnProgressionButton"
	turn_progression_button.text = "Proceed to Lane 1"
	turn_progression_button.position = Vector2(850, 580)  # Bottom-right
	turn_progression_button.size = Vector2(280, 50)
	turn_progression_button.add_theme_font_size_override("font_size", 20)
	turn_progression_button.add_to_group("ui")
	turn_progression_button.visible = false  # Hidden until turn mode starts
	turn_progression_button.pressed.connect(_on_turn_progression_pressed)

	# Add to UI layer so it's not affected by camera zoom
	ui_layer.add_child(turn_progression_button)

# ============================================================================
# CARD SYSTEM
# ============================================================================

var draw_card_button: Button = null

# Ship tooltip UI
var ship_tooltip: Panel = null
var ship_tooltip_label: RichTextLabel = null
var tooltip_tween: Tween = null

func setup_ship_tooltip():
	"""Create the ship tooltip panel"""
	# Create tooltip panel
	ship_tooltip = Panel.new()
	ship_tooltip.name = "ShipTooltip"
	ship_tooltip.visible = false
	ship_tooltip.z_index = 1000
	ship_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block mouse events
	
	# Grey background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	ship_tooltip.add_theme_stylebox_override("panel", style)
	
	# Create label for stats
	ship_tooltip_label = RichTextLabel.new()
	ship_tooltip_label.name = "StatsLabel"
	ship_tooltip_label.add_theme_font_size_override("normal_font_size", 11)
	ship_tooltip_label.add_theme_color_override("default_color", Color.WHITE)
	ship_tooltip_label.add_theme_constant_override("line_separation", 2)
	ship_tooltip_label.bbcode_enabled = true
	ship_tooltip_label.fit_content = true
	ship_tooltip_label.scroll_active = false
	ship_tooltip.add_child(ship_tooltip_label)
	
	# Add to UI layer so it's not affected by camera
	ui_layer.add_child(ship_tooltip)
	
	print("Combat_2: Ship tooltip created")

func add_ship_hover_detection(ship_container: Control, ship_data: Dictionary):
	"""Add hover detection to a ship for tooltip display"""
	# Make the container detect mouse events
	ship_container.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Connect mouse enter/exit signals
	ship_container.mouse_entered.connect(_on_ship_hover_start.bind(ship_data))
	ship_container.mouse_exited.connect(_on_ship_hover_end.bind(ship_data))

func _on_ship_hover_start(ship_data: Dictionary):
	"""Show tooltip when hovering over ship"""
	if ship_data.is_empty():
		return
	
	current_tooltip_ship = ship_data
	show_ship_tooltip(ship_data)

func _on_ship_hover_end(ship_data: Dictionary):
	"""Hide tooltip when leaving ship"""
	if current_tooltip_ship == ship_data:
		hide_ship_tooltip()
		current_tooltip_ship = {}

func show_ship_tooltip(ship_data: Dictionary):
	"""Display tooltip with ship stats"""
	if not ship_tooltip or not ship_tooltip_label:
		return
	
	# Build stats text
	var stats_text = ""
	stats_text += "[b]%s[/b]\n" % ship_data.get("type", "Unknown").capitalize()
	stats_text += "━━━━━━━━━━━━━━\n"
	
	# Current health
	stats_text += "Shield: %d" % ship_data.get("current_shield", 0)
	if ship_data.get("current_overshield", 0) > 0:
		stats_text += " (+%d)" % ship_data.get("current_overshield", 0)
	stats_text += " / %d\n" % ship_data.get("stats", {}).get("shield", 0)
	
	stats_text += "Armor: %d / %d\n" % [ship_data.get("current_armor", 0), ship_data.get("stats", {}).get("armor", 0)]
	stats_text += "Energy: %d / %d\n" % [ship_data.get("current_energy", 0), ship_data.get("stats", {}).get("energy", 0)]
	stats_text += "\n"
	
	# Combat stats (with temporary modifiers)
	var stats = ship_data.get("stats", {})
	stats_text += "Damage: %d\n" % stats.get("damage", 0)

	# Attack Speed - show modified value if affected by freeze
	var base_attack_speed = stats.get("attack_speed", 0)
	var attack_speed_multiplier = 1.0
	if status_effect_manager:
		attack_speed_multiplier = status_effect_manager.get_freeze_attack_speed_multiplier(ship_data)

	if attack_speed_multiplier < 1.0:
		var modified_attack_speed = base_attack_speed * attack_speed_multiplier
		stats_text += "Attack Speed: %.1f [color=red](%.1f)[/color]\n" % [base_attack_speed, modified_attack_speed]
	else:
		stats_text += "Attack Speed: %.1f\n" % base_attack_speed

	stats_text += "Num Attacks: %d\n" % stats.get("num_attacks", 1)
	stats_text += "Accuracy: %d%%\n" % stats.get("accuracy", 0)

	# Evasion - show modified value if affected by freeze
	var base_evasion = stats.get("evasion", 0)
	var evasion_multiplier = 1.0
	if status_effect_manager:
		evasion_multiplier = status_effect_manager.get_freeze_evasion_multiplier(ship_data)

	if evasion_multiplier < 1.0:
		var modified_evasion = base_evasion * evasion_multiplier
		stats_text += "Evasion: %d%% [color=red](%d%%)[/color]\n" % [base_evasion, int(modified_evasion)]
	else:
		stats_text += "Evasion: %d%%\n" % base_evasion

	stats_text += "Reinforced: %d\n" % stats.get("reinforced_armor", 0)
	
	ship_tooltip_label.text = stats_text

	# Size tooltip to fit text (RichTextLabel needs explicit size)
	await get_tree().process_frame  # Wait for label to calculate size

	# Set a reasonable width and let height auto-calculate
	ship_tooltip_label.custom_minimum_size = Vector2(200, 0)
	ship_tooltip_label.size = Vector2(200, 0)
	await get_tree().process_frame  # Wait for RichTextLabel to calculate content height

	var content_size = ship_tooltip_label.get_content_height()
	ship_tooltip_label.custom_minimum_size = Vector2(200, content_size)
	ship_tooltip_label.size = Vector2(200, content_size)

	ship_tooltip.custom_minimum_size = Vector2(220, content_size + 20)  # Padding
	ship_tooltip_label.position = Vector2(10, 10)
	
	# Position near mouse
	var mouse_pos = get_viewport().get_mouse_position()
	ship_tooltip.position = mouse_pos + Vector2(20, 20)
	
	# Clamp to screen
	var viewport_size = get_viewport_rect().size
	if ship_tooltip.position.x + ship_tooltip.size.x > viewport_size.x:
		ship_tooltip.position.x = mouse_pos.x - ship_tooltip.size.x - 20
	if ship_tooltip.position.y + ship_tooltip.size.y > viewport_size.y:
		ship_tooltip.position.y = mouse_pos.y - ship_tooltip.size.y - 20
	
	# Pop-in animation
	ship_tooltip.scale = Vector2(0.5, 0.5)
	ship_tooltip.modulate.a = 0.0
	ship_tooltip.visible = true
	
	if tooltip_tween:
		tooltip_tween.kill()
	tooltip_tween = create_tween()
	tooltip_tween.set_parallel(true)
	tooltip_tween.set_ease(Tween.EASE_OUT)
	tooltip_tween.set_trans(Tween.TRANS_BACK)
	tooltip_tween.tween_property(ship_tooltip, "scale", Vector2.ONE, 0.2)
	tooltip_tween.tween_property(ship_tooltip, "modulate:a", 1.0, 0.15)

func hide_ship_tooltip():
	"""Hide the ship tooltip"""
	if not ship_tooltip:
		return
	
	if tooltip_tween:
		tooltip_tween.kill()
	
	ship_tooltip.visible = false

func setup_card_system():
	"""Initialize the card system"""
	print("Combat_2: Setting up card system...")
	
	# Setup hand UI
	CardHandManager.setup_hand_ui(self)
	
	# Initialize and shuffle deck
	CardHandManager.initialize_deck()
	
	# Set combat scene reference
	CardHandManager.set_combat_scene(self)
	
	# Create draw card button
	draw_card_button = Button.new()
	draw_card_button.name = "DrawCardButton"
	draw_card_button.text = "Draw Card"
	draw_card_button.position = Vector2(950, 20)  # Top right
	draw_card_button.size = Vector2(180, 50)
	draw_card_button.add_theme_font_size_override("font_size", 18)
	draw_card_button.add_to_group("ui")
	draw_card_button.visible = false  # Hidden until precombat phase
	draw_card_button.pressed.connect(_on_draw_card_pressed)
	ui_layer.add_child(draw_card_button)
	
	# Hide hand initially
	CardHandManager.set_hand_visible(false)
	
	print("Combat_2: Card system setup complete")

func _on_draw_card_pressed():
	"""Handle draw card button press"""
	var success = CardHandManager.draw_card()
	if not success:
		print("Combat_2: Cannot draw card")
		# Could add UI feedback here

func update_card_system_visibility():
	"""Update card UI visibility based on combat phase"""
	# Hand and draw button visible when zoomed into any lane (precombat or combat)
	# Cards are only PLAYABLE during precombat phase
	var in_lane_view = is_zoomed  # Show cards whenever in lane view
	var in_precombat = is_zoomed and combat_paused and waiting_for_combat_start  # Can only play cards in precombat
	
	if draw_card_button:
		draw_card_button.visible = in_lane_view  # Can draw during precombat OR combat
	
	CardHandManager.set_hand_visible(in_lane_view)  # Show hand in both phases
	
	# Update CardHandManager's current lane reference and playability
	if is_zoomed:
		CardHandManager.set_combat_scene(self, zoomed_lane_index)
		CardHandManager.set_cards_playable(in_precombat)  # Only playable during precombat

func _on_auto_deploy_pressed():
	# Auto-deploy player ships and enemies
	print("Auto-deploying ships and enemies...")

	# Deploy player ships
	# Lane 1 (index 0): Interceptor
	deploy_ship_to_lane("basic_interceptor", 0)

	# Lane 2 (index 1): Fighter
	deploy_ship_to_lane("basic_fighter", 1)

	# Lane 3 (index 2): Frigate
	deploy_ship_to_lane("basic_shield_frigate", 2)

	# Wait a moment for player ships to start deploying
	await get_tree().create_timer(0.5).timeout

	# Deploy enemies: 1 mook and 1 elite in each lane
	for lane_idx in range(3):
		deploy_enemy_to_lane("mook", lane_idx)
		deploy_enemy_to_lane("elite", lane_idx)

	print("Auto-deploy complete!")

func zoom_to_lane(lane_index: int):
	# Zoom camera to focus on specific lane
	print("Zooming to lane ", lane_index)
	is_zoomed = true
	zoomed_lane_index = lane_index

	# Calculate camera position to center on lane
	var lane_y = lanes[lane_index]["y_position"]
	var target_position = Vector2(576, lane_y)  # Center of screen width (1152/2)

	# Animate camera zoom
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "position", target_position, 0.5)
	tween.tween_property(camera, "zoom", Vector2(1.5, 1.5), 0.5)

	# Show return button (only if not in turn mode)
	if not turn_mode_active:
		return_button.visible = true

	# Hide deploy buttons while zoomed
	deploy_button.visible = false
	deploy_enemy_button.visible = false
	auto_deploy_button.visible = false

	# No longer move ships forward - they stay in their grid squares
	# Just pause their idle animations
	pause_lane_idle_animations(lane_index)

	# In turn mode, wait for player to click "Start Combat"
	# In normal mode, start combat immediately
	if not turn_mode_active:
		# Unpause combat for this lane
		combat_paused = false
		print("Combat UNPAUSED - lane active")

		# Start combat for all ships in this lane
		start_lane_combat(lane_index)

		# Start 5-second timer to auto-return (AFTER ships are in position)
		start_zoom_timer()
	else:
		print("Zoomed to lane ", lane_index, " - waiting for player to start combat")

func _on_return_to_tactical():
	# Return to tactical view
	print("Returning to tactical view")

	# Cancel zoom timer if active
	stop_zoom_timer()

	# Hide timer label
	if zoom_timer_label:
		zoom_timer_label.visible = false

	# Pause combat
	combat_paused = true
	print("Combat PAUSED - tactical view")

	# Reset status effect manager lane (no active lane in tactical view)
	if status_effect_manager:
		status_effect_manager.set_active_lane(-1)

	# Stop combat for the zoomed lane
	var prev_lane_index = zoomed_lane_index
	if prev_lane_index != -1:
		stop_lane_combat(prev_lane_index)

	# Resume idle animations for ALL lanes when returning to tactical view
	for i in range(CombatConstants.NUM_LANES):
		resume_lane_idle_animations(i)

	is_zoomed = false
	zoomed_lane_index = -1

	# Animate camera back to default (center of screen)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "position", Vector2(576, 324), 0.5)
	tween.tween_property(camera, "zoom", Vector2(1.0, 1.0), 0.5)

	# Hide return button
	return_button.visible = false

	# Show deploy buttons again
	deploy_button.visible = true
	deploy_enemy_button.visible = true
	auto_deploy_button.visible = true

# Lane ship movement functions

func pause_lane_idle_animations(lane_index: int):
	# Pause idle animations for all units in the lane
	if lane_index < 0 or lane_index >= lanes.size():
		return

	var lane = lanes[lane_index]
	for unit in lane["units"]:
		if not unit.has("container"):
			continue

		# Mark unit's idle as paused
		unit["idle_paused"] = true

		# Return unit to grid center position if drifting
		if unit.has("grid_row") and unit.has("grid_col") and unit.has("lane_index"):
			var container = unit["container"]
			var cell_center = get_cell_world_position(unit["lane_index"], unit["grid_row"], unit["grid_col"])
			var target_pos = Vector2(cell_center.x - unit["size"] / 2, cell_center.y - unit["size"] / 2)

			# Instantly snap to grid position (no animation)
			# This prevents conflicts with ship movement tweens
			container.position = target_pos

	print("Paused idle animations for lane ", lane_index)

func resume_lane_idle_animations(lane_index: int):
	# Resume idle animations for all units in the lane
	if lane_index < 0 or lane_index >= lanes.size():
		return

	var lane = lanes[lane_index]
	for unit in lane["units"]:
		if not unit.has("container"):
			continue

		# Ensure unit is at grid center position
		if unit.has("grid_row") and unit.has("grid_col") and unit.has("lane_index"):
			var container = unit["container"]
			var cell_center = get_cell_world_position(unit["lane_index"], unit["grid_row"], unit["grid_col"])
			var target_pos = Vector2(cell_center.x - unit["size"] / 2, cell_center.y - unit["size"] / 2)

			# Update original position to grid center
			unit["original_position"] = target_pos
			container.position = target_pos

		# Unpause idle animation
		unit["idle_paused"] = false

	print("Resumed idle animations for lane ", lane_index)

func start_zoom_timer():
	# Start 5-second timer for auto-return to tactical view
	if zoom_timer:
		zoom_timer.queue_free()

	zoom_timer = Timer.new()
	zoom_timer.name = "ZoomTimer"
	zoom_timer.wait_time = 5.0
	zoom_timer.one_shot = true
	zoom_timer.timeout.connect(_on_zoom_timer_timeout)
	add_child(zoom_timer)
	zoom_timer.start()

	# Show and initialize timer label
	if zoom_timer_label:
		zoom_timer_label.text = "LANE %d: 5s" % [zoomed_lane_index + 1]
		zoom_timer_label.visible = true

	print("Started 5-second zoom timer")

func stop_zoom_timer():
	# Stop and remove zoom timer
	if zoom_timer:
		zoom_timer.stop()
		zoom_timer.queue_free()
		zoom_timer = null

func _on_zoom_timer_timeout():
	# Handle zoom timer expiring
	if turn_mode_active:
		# In turn mode - progress to next phase
		print("Zoom timer expired - combat phase complete")
		on_combat_phase_complete()
	else:
		# Normal mode - auto-return to tactical view
		print("Zoom timer expired - auto-returning to tactical view")
		_on_return_to_tactical()

# Combat system functions

func start_attack_sequence():
	# Begin the attack sequence: rotate ship, then fire
	if selected_attacker.is_empty() or selected_target.is_empty():
		return

	# Don't allow manual combat in paused state
	if combat_paused:
		print("Combat is paused - cannot start manual attack")
		return

	print("Starting attack sequence")

	# First, rotate to face target
	rotate_ship_to_target()

	# Fire immediately after rotation completes (0.3s delay)
	await get_tree().create_timer(0.3).timeout

	# Fire the first shot
	fire_laser()

	# Start continuous attack timer
	start_continuous_attack()

func calculate_target_position(attacker: Dictionary, target: Dictionary, attacker_center: Vector2) -> Vector2:
	"""Calculate target position for projectiles.
	When targeting mothership/boss, fire down the lane (use attacker's Y position).
	Otherwise, aim at the center of the target."""
	var target_pos = target["container"].position
	var target_size = target["size"]
	var target_type = target.get("object_type", "")
	
	# Check if targeting mothership or boss
	if target_type == "mothership" or target_type == "boss":
		# Fire down the lane - use attacker's Y position
		return Vector2(target_pos.x + target_size / 2, attacker_center.y)
	else:
		# Normal targeting - aim at center of target
		return target_pos + Vector2(target_size / 2, target_size / 2)

func rotate_ship_to_target():
	# Rotate attacker to face the target
	if selected_attacker.is_empty() or selected_target.is_empty():
		return

	var attacker_sprite = selected_attacker["sprite"]
	var attacker_pos = selected_attacker["container"].position
	var attacker_size = selected_attacker["size"]

	# Calculate center positions
	var attacker_center = attacker_pos + Vector2(attacker_size / 2, attacker_size / 2)
	var target_center = calculate_target_position(selected_attacker, selected_target, attacker_center)

	# Calculate angle to target
	var direction = target_center - attacker_center
	var target_rotation = direction.angle()

	# Smoothly rotate to target
	var tween = create_tween()
	tween.tween_property(attacker_sprite, "rotation", target_rotation, 0.3)

	print("Rotating attacker to face target")

func fire_laser():
	# Fire laser projectiles from attacker to target using consolidated weapon system
	if selected_attacker.is_empty() or selected_target.is_empty():
		return

	if weapon_manager and weapon_manager.has_method("fire_weapon_volley"):
		# Rotate attacker to face target first
		if selected_attacker.has("sprite") and selected_target.has("sprite"):
			await rotate_attacker_to_target(selected_attacker, selected_target)

		# Fire all projectiles simultaneously
		weapon_manager.fire_weapon_volley(selected_attacker, selected_target)
	else:
		print("Combat_2: ERROR - weapon_manager not available for fire_laser")

# ============================================================================
# DEPRECATED FUNCTIONS (use weapon_manager.fire_weapon_volley instead)
# ============================================================================

func fire_single_laser():
	# DEPRECATED: Use weapon_manager.fire_weapon_volley instead
	# Fire a single laser projectile from attacker to target
	if selected_attacker.is_empty() or selected_target.is_empty():
		return

	var attacker_pos = selected_attacker["container"].position
	var attacker_size = selected_attacker["size"]

	# Calculate center positions
	var start_pos = attacker_pos + Vector2(attacker_size / 2, attacker_size / 2)
	var end_pos = calculate_target_position(selected_attacker, selected_target, start_pos)

	# Calculate direction and angle
	var direction = end_pos - start_pos
	var angle = direction.angle()

	# Get projectile sprite and size from attacker data
	var projectile_sprite_path = selected_attacker.get("projectile_sprite", "res://assets/Effects/laser_light/s_laser_light_001.png")
	var projectile_pixel_size = selected_attacker.get("projectile_size", 6)
	var projectile_texture: Texture2D = load(projectile_sprite_path)

	# Create laser sprite (projectile)
	var laser = Sprite2D.new()
	laser.texture = projectile_texture
	laser.position = start_pos
	laser.rotation = angle
	laser.z_index = 1  # Above ships
	add_child(laser)

	# Scale laser to desired pixel height
	var laser_height = projectile_texture.get_height()
	var scale_y = float(projectile_pixel_size) / laser_height
	laser.scale = Vector2(scale_y, scale_y)  # Uniform scale to maintain aspect ratio

	# Center the sprite
	laser.offset = Vector2(-projectile_texture.get_width() / 2, -projectile_texture.get_height() / 2)

	# Animate laser: fly quickly to target (0.2 seconds)
	var flight_duration = 0.2
	var tween = create_tween()
	tween.tween_property(laser, "position", end_pos, flight_duration)
	tween.tween_callback(on_laser_hit.bind(laser))

func on_laser_hit(laser: Sprite2D):
	# DEPRECATED: Use weapon_manager.fire_weapon_volley instead
	# Handle laser reaching target position
	# If hit: destroy laser and apply damage
	# If miss: continue traveling until off-screen

	# Calculate damage
	var damage_result = {"damage": 0, "is_crit": false, "is_miss": false}
	if not selected_attacker.is_empty() and not selected_target.is_empty():
		damage_result = calculate_damage(selected_attacker, selected_target)

	# Get target position for damage numbers (center of sprite)
	var target_pos = Vector2.ZERO
	if selected_target.has("sprite") and is_instance_valid(selected_target["sprite"]):
		var sprite = selected_target["sprite"]
		target_pos = sprite.global_position + Vector2(0, sprite.size.y / 2.0)

	# Check if attack hit or missed
	if damage_result["is_miss"]:
		# MISS - Show miss damage number and continue laser off-screen
		DamageNumber.show_miss(self, target_pos)
		continue_laser_off_screen(laser)
	elif damage_result["damage"] > 0:
		# HIT - Apply damage and show damage numbers
		var damage_breakdown = apply_damage(selected_target, damage_result["damage"])

		# Show damage numbers for shield and armor damage
		if damage_breakdown["shield_damage"] > 0:
			DamageNumber.show_shield_damage(self, target_pos, damage_breakdown["shield_damage"], damage_result["is_crit"])
		if damage_breakdown["armor_damage"] > 0:
			# Offset armor damage number slightly if both shield and armor were damaged
			var armor_pos = target_pos
			if damage_breakdown["shield_damage"] > 0:
				armor_pos.y += 20  # Offset downward
			DamageNumber.show_armor_damage(self, armor_pos, damage_breakdown["armor_damage"], damage_result["is_crit"])

		# Remove the laser projectile
		laser.queue_free()

		# Flash the target
		if not selected_target.is_empty() and selected_target.has("sprite"):
			var target_sprite = selected_target["sprite"]

			# Create flash animation - white flash then back to normal
			var flash_tween = create_tween()
			flash_tween.tween_property(target_sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.05)  # Flash white
			flash_tween.tween_property(target_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)   # Return to normal
	else:
		# No damage (shouldn't happen, but handle gracefully)
		continue_laser_off_screen(laser)

func continue_laser_off_screen(laser: Sprite2D):
	# Continue laser traveling in its current direction until it goes off-screen
	# Screen bounds: 1152x648 (from Combat_2.tscn)
	# Add extra margin to ensure complete cleanup

	if not is_instance_valid(laser):
		return

	# Get current position and rotation
	var current_pos = laser.position
	var angle = laser.rotation

	# Calculate direction vector from rotation
	var direction = Vector2(cos(angle), sin(angle))

	# Calculate distance needed to go completely off-screen
	# Use screen diagonal + margin to ensure it's fully off-screen
	var screen_size = Vector2(1152, 648)
	var max_distance = screen_size.length() + 200  # Diagonal + margin

	# Calculate final off-screen position
	var off_screen_pos = current_pos + (direction * max_distance)

	# Animate laser to off-screen position
	var travel_duration = max_distance / 1000.0  # Speed: ~1000 pixels/second
	var tween = create_tween()
	tween.tween_property(laser, "position", off_screen_pos, travel_duration)
	tween.tween_callback(func():
		# Destroy laser once it's off-screen
		if is_instance_valid(laser):
			laser.queue_free()
	)

func calculate_damage(attacker: Dictionary, target: Dictionary) -> Dictionary:
	# Calculate damage from attacker to target
	# Returns dictionary with: {damage: int, is_crit: bool, is_miss: bool}

	var result = {"damage": 0, "is_crit": false, "is_miss": false}

	if attacker.is_empty() or target.is_empty():
		return result

	# Get stats
	var attacker_accuracy = attacker["stats"].get("accuracy", 0)
	var attacker_damage = attacker["stats"].get("damage", 0)
	var target_evasion = target["stats"].get("evasion", 0)
	var target_reinforced = target["stats"].get("reinforced_armor", 0)

	# Hit chance calculation
	var hit_chance = 1.0
	hit_chance -= (target_evasion * 0.01)
	if hit_chance < 0:
		hit_chance = 0

	# Crit chance calculation
	var crit_chance = 1.0 - (attacker_accuracy * 0.01)
	var crit_roll = randf()
	var critical_hit = false
	if crit_roll > crit_chance:
		critical_hit = true
		result["is_crit"] = true

	# Roll for hit/miss
	var roll = randf()
	if roll > hit_chance:
		print("MISS! (rolled ", roll, " vs hit chance ", hit_chance, ")")
		result["is_miss"] = true
		return result

	# Hit! Calculate damage
	var base_damage = attacker_damage

	# Apply reinforced armor reduction
	var damage_multiplier = 1.0 - (float(target_reinforced) / 100.0)
	damage_multiplier = max(0.0, damage_multiplier)

	var final_damage = int(base_damage * damage_multiplier)
	if critical_hit:
		final_damage *= 2
		print("CRIT!")
	final_damage = max(1, final_damage)  # Always do at least 1 damage on hit

	result["damage"] = final_damage
	print("HIT! Damage: ", final_damage, " (base: ", base_damage, ", armor reduction: ", target_reinforced, "%)")
	return result

func apply_damage(target: Dictionary, damage: int) -> Dictionary:
	# Apply damage to target's shields first, then armor
	# Returns: {shield_damage: int, armor_damage: int}
	var damage_breakdown = {"shield_damage": 0, "armor_damage": 0}

	if target.is_empty():
		return damage_breakdown

	var remaining_damage = damage

	# Damage overshield first (temporary shields)
	if target.has("current_overshield") and target["current_overshield"] > 0:
		var overshield_damage = min(target["current_overshield"], remaining_damage)
		target["current_overshield"] -= overshield_damage
		remaining_damage -= overshield_damage
		print("  Overshield damaged: -", overshield_damage, " (", target["current_overshield"], " remaining)")

	# Then damage shields
	if remaining_damage > 0 and target.has("current_shield") and target["current_shield"] > 0:
		var shield_damage = min(target["current_shield"], remaining_damage)
		target["current_shield"] -= shield_damage
		remaining_damage -= shield_damage
		damage_breakdown["shield_damage"] = shield_damage
		print("  Shield damaged: -", shield_damage, " (", target["current_shield"], " remaining)")

	# Overflow damage goes to armor
	if remaining_damage > 0 and target.has("current_armor"):
		var armor_damage = min(target["current_armor"], remaining_damage)
		target["current_armor"] -= armor_damage
		damage_breakdown["armor_damage"] = armor_damage
		print("  Armor damaged: -", armor_damage, " (", target["current_armor"], " remaining)")

	# Update health bar
	update_health_bar(target)

	# Generate energy from damage taken (1 energy per 5% of combined health lost)
	if not target.get("ability_active", false):
		var max_energy = target.get("stats", {}).get("energy", 0)
		if max_energy > 0:
			var max_shield = target.get("stats", {}).get("shield", 0)
			var max_armor = target.get("stats", {}).get("armor", 0)
			var max_combined_health = max_shield + max_armor

			if max_combined_health > 0:
				var total_damage_dealt = damage_breakdown["shield_damage"] + damage_breakdown["armor_damage"]
				var percent_lost = float(total_damage_dealt) / float(max_combined_health)
				var energy_gain = floor(percent_lost * 20.0)  # 1 energy per 5% = 20 energy for 100%

				if energy_gain > 0:
					var current_energy = target.get("current_energy", 0)
					target["current_energy"] = min(current_energy + energy_gain, max_energy)
					print("  ", target.get("type", "unknown"), " gained ", energy_gain, " energy from damage (", target["current_energy"], "/", max_energy, ")")
					update_energy_bar(target)

					# Check if energy is full after damage
					if target["current_energy"] >= max_energy:
						cast_ability(target)

	# Check if ship is destroyed
	var total_health = target.get("current_armor", 0) + target.get("current_shield", 0)
	if total_health <= 0:
		print("  SHIP DESTROYED!")
		destroy_ship(target)

	return damage_breakdown

func start_continuous_attack():
	# Start attack cycle - attacks happen at attack_speed per second
	if selected_attacker.is_empty() or selected_target.is_empty():
		return

	# Calculate attack interval: 1 / attack_speed = seconds per attack
	# attack_speed of 1.5 = 1.5 attacks/second = 0.667s per attack
	# attack_speed of 0.3 = 0.3 attacks/second = 3.333s per attack
	# attack_speed of 10 = 10 attacks/second = 0.1s per attack
	var attack_speed = selected_attacker["stats"]["attack_speed"]
	# Apply freeze modifier if active
	if status_effect_manager:
		attack_speed *= status_effect_manager.get_freeze_attack_speed_multiplier(selected_attacker)
	var attack_interval = 1.0 / attack_speed

	# Start attack cycle
	attack_cycle(selected_attacker, selected_target, attack_interval)

	print("Started continuous attack - attack speed: ", attack_speed, " attacks/sec (", attack_interval, "s per attack)")

func attack_cycle(attacker: Dictionary, target: Dictionary, attack_interval: float):
	# Continuous attack cycle
	while not attacker.is_empty() and not target.is_empty():
		# Wait while combat is paused (resume when unpaused)
		while combat_paused:
			await get_tree().create_timer(0.1).timeout
			# Check if units still exist while paused
			if not is_instance_valid(attacker.get("container")) or not is_instance_valid(target.get("container")):
				print("Attack cycle ended - unit no longer exists")
				return

		# Check if still attacking same target
		if selected_attacker != attacker or selected_target != target:
			break

		# Fire all projectiles in this attack
		await fire_laser()

		# Wait for cooldown (timer resets AFTER last projectile fires)
		await get_tree().create_timer(attack_interval).timeout

		# Check if units still exist
		if not is_instance_valid(attacker.get("container")) or not is_instance_valid(target.get("container")):
			break

func _on_attack_timer_timeout():
	# Legacy callback - no longer used
	pass

func stop_continuous_attack():
	# Stop the continuous attack timer
	if selected_attacker.is_empty():
		return

	var container = selected_attacker["container"]
	var timer = container.get_node_or_null("AttackTimer")

	if timer:
		timer.stop()
		timer.queue_free()
		print("Stopped continuous attack")

func destroy_ship(ship: Dictionary):
	# Destroy a ship or turret when its health reaches 0
	if ship.is_empty():
		return

	var ship_type = ship.get("type", "unknown")
	var object_type = ship.get("object_type", "ship")
	var is_enemy = ship.get("is_enemy", false)

	if object_type == "turret":
		print("Destroying turret: ", ship_type)
	else:
		print("Destroying ship: ", ship_type, " (enemy: ", is_enemy, ")")

	# Clear selections if this ship was selected
	if selected_attacker == ship:
		deselect_attacker()
	if selected_target == ship:
		selected_target = {}

	# Stop any attack timer on this ship/turret
	if ship.has("container"):
		var container = ship["container"]
		var timer = container.get_node_or_null("AttackTimer")
		if timer:
			timer.stop()
			timer.queue_free()
		var switch_timer = container.get_node_or_null("TargetSwitchTimer")
		if switch_timer:
			switch_timer.stop()
			switch_timer.queue_free()

		# TODO: Play destruction animation/effect here
		# For now, just remove immediately
		container.queue_free()

	# Remove from appropriate collection
	if object_type == "turret":
		# Remove turret from turrets array
		var index = turrets.find(ship)
		if index != -1:
			turrets.remove_at(index)
			print("Turret removed from active turrets")
	else:
		# Remove ship from its lane
		for lane in lanes:
			var index = lane["units"].find(ship)
			if index != -1:
				lane["units"].remove_at(index)
				print("Ship removed from lane ", lane["index"])

				# Free the grid cell if ship has grid position
				if ship.has("grid_row") and ship.has("grid_col") and ship.has("lane_index"):
					free_grid_cell(ship["lane_index"], ship["grid_row"], ship["grid_col"])
					print("Grid cell freed at row=", ship["grid_row"], " col=", ship["grid_col"])

				break

	# In auto-combat or lane combat, reassign targets for any units that were targeting this destroyed object
	if auto_combat_active or is_zoomed:
		# Check ships in lanes
		for lane in lanes:
			for unit in lane["units"]:
				if unit.get("auto_target") == ship:
					assign_random_target(unit)

		# Check turrets
		for turret in turrets:
			if turret.get("auto_target") == ship:
				# Use the turret's active lane if set (during lane combat)
				var active_lane = turret.get("active_lane", -1)
				assign_turret_targets(turret, active_lane)

# Auto-combat functions

func _on_auto_combat_toggled():
	# Toggle turn-based combat mode
	turn_mode_active = !turn_mode_active

	if turn_mode_active:
		auto_combat_button.text = "STOP TURN MODE"
		start_turn_mode()
		print("Turn mode STARTED")
	else:
		auto_combat_button.text = "START AUTO-COMBAT"
		stop_turn_mode()
		print("Turn mode STOPPED")

# Turn-based combat functions

func start_turn_mode():
	# Start turn-based combat mode
	current_turn_phase = "tactical"
	waiting_for_combat_start = false

	# Show turn progression button
	if turn_progression_button:
		turn_progression_button.text = "Proceed to Lane 1"
		turn_progression_button.visible = true

	# Hide return button in turn mode (no manual returns allowed)
	if return_button:
		return_button.visible = false
	
	# Card UI hidden in tactical phase, shown in precombat
	update_card_system_visibility()

	print("Turn mode started - Tactical phase")

func stop_turn_mode():
	# Stop turn-based combat mode
	turn_mode_active = false
	current_turn_phase = "tactical"
	waiting_for_combat_start = false

	# Hide turn progression button
	if turn_progression_button:
		turn_progression_button.visible = false

	# Stop any active combat
	if is_zoomed:
		_on_return_to_tactical()

	print("Turn mode stopped")

func _on_turn_progression_pressed():
	# Handle turn progression button press
	if waiting_for_combat_start:
		# Player clicked "Start Combat" - begin the combat phase
		start_combat_phase()
	else:
		# Player clicked "Proceed to Lane X" - zoom to the next lane
		proceed_to_next_lane()

func proceed_to_next_lane():
	# Zoom to the appropriate lane based on current phase
	var target_lane = -1

	if current_turn_phase == "tactical":
		target_lane = 0
		current_turn_phase = "lane_0"
	elif current_turn_phase == "lane_0":
		target_lane = 1
		current_turn_phase = "lane_1"
	elif current_turn_phase == "lane_1":
		target_lane = 2
		current_turn_phase = "lane_2"

	if target_lane >= 0:
		# Update status effect manager with active lane
		if status_effect_manager:
			status_effect_manager.set_active_lane(target_lane)

		# Ensure combat is paused for precombat phase
		combat_paused = true
		print("Combat PAUSED - entering precombat phase for lane ", target_lane)

		# Reset movement flags for this lane's precombat phase
		reset_ship_movement_flags()

		# Set waiting_for_combat_start BEFORE zooming so cards become playable
		waiting_for_combat_start = true

		# Zoom to the lane
		zoom_to_lane(target_lane)

		# Update button to "Start Combat"
		if turn_progression_button:
			turn_progression_button.text = "Start Combat"

		# Update card system visibility (show hand and draw button)
		update_card_system_visibility()

func start_combat_phase():
	# Start combat in the current zoomed lane
	if not is_zoomed or zoomed_lane_index < 0:
		print("ERROR: Trying to start combat but not zoomed into a lane")
		return

	# Clean up any active drag state
	if is_dragging_ship:
		cleanup_ship_drag()

	# Hide the "Start Combat" button
	if turn_progression_button:
		turn_progression_button.visible = false

	waiting_for_combat_start = false

	# Hide card system during combat
	update_card_system_visibility()

	# Enter pre-combat check phase (combat stays PAUSED)
	enter_pre_combat_check_phase()

func enter_pre_combat_check_phase():
	"""Enter the pre-combat check phase - review abilities before combat starts"""
	print("=== ENTERING PRE-COMBAT CHECK PHASE ===")

	# Combat stays PAUSED during this phase
	var lane = lanes[zoomed_lane_index]

	# Auto-queue abilities for ships with max energy
	auto_queue_ship_abilities(zoomed_lane_index)

	# Collect all queued abilities from friendly ships
	var queued_abilities = []
	for unit in lane["units"]:
		if unit.get("is_enemy", false):
			continue  # Skip enemies
		if unit.has("ability_stack") and unit["ability_stack"].size() > 0:
			for ability_data in unit["ability_stack"]:
				# Predict target for this ability
				var predicted_target = targeting_system.select_target_for_unit(unit, "gamma")
				var target_name = "No Target"
				if predicted_target and not predicted_target.is_empty():
					target_name = predicted_target.get("type", "Unknown")

				queued_abilities.append({
					"ship": unit,
					"ability_data": ability_data,
					"predicted_target": target_name
				})

	# Display pre-combat check UI
	show_pre_combat_check_ui(queued_abilities)

	print("Pre-combat check phase ready - ", queued_abilities.size(), " abilities queued")

func auto_queue_ship_abilities(lane_index: int):
	"""Automatically queue abilities for ships with max energy"""
	if lane_index < 0 or lane_index >= lanes.size():
		return

	var lane = lanes[lane_index]
	var abilities_queued = 0
	
	for unit in lane["units"]:
		# Skip enemies
		if unit.get("is_enemy", false):
			continue

		# Check if ship has max energy
		var current_energy = unit.get("current_energy", 0)
		var max_energy = unit.get("stats", {}).get("energy", 100)

		if current_energy >= max_energy:
			# Check if ship has an ability to cast
			var ship_data = DataManager.get_ship_data(unit.get("type", ""))
			var ability_function = ship_data.get("ability_function", "")
			var ability_name = ship_data.get("ability", "")  # CSV column is "ability", not "ability_name"

			if ability_function != "" and ability_name != "":
				# Ensure ability_stack exists
				if not unit.has("ability_stack"):
					unit["ability_stack"] = []
				
				# Check if ability is already queued
				var already_queued = false
				for queued_ability in unit["ability_stack"]:
					if queued_ability.get("ability_name") == ability_name:
						already_queued = true
						break

				if not already_queued:
					# Queue the ability
					var ability_data = {
						"ability_name": ability_name,
						"ability_function": ability_function,
						"source": "ship_energy"
					}
					queue_ability_for_ship(unit, ability_data)
					abilities_queued += 1
					print("Auto-queued ", ability_name, " for ", unit.get("type", "Unknown"))

	if abilities_queued > 0:
		print("Auto-queued ", abilities_queued, " ship abilities with max energy")

func show_pre_combat_check_ui(queued_abilities: Array):
	"""Display the pre-combat check UI with all queued abilities"""
	# Create main panel
	pre_combat_check_panel = Panel.new()
	pre_combat_check_panel.name = "PreCombatCheckPanel"

	var viewport_size = get_viewport_rect().size
	var panel_width = 500
	var panel_height = 400
	pre_combat_check_panel.position = Vector2(viewport_size.x / 2 - panel_width / 2, viewport_size.y / 2 - panel_height / 2)
	pre_combat_check_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	pre_combat_check_panel.z_index = 150
	ui_layer.add_child(pre_combat_check_panel)

	# Create title
	var title = Label.new()
	title.text = "PRE-COMBAT CHECK"
	title.position = Vector2(20, 10)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.YELLOW)
	pre_combat_check_panel.add_child(title)

	# Create subtitle
	var subtitle = Label.new()
	if queued_abilities.is_empty():
		subtitle.text = "No abilities queued. Ready to begin combat."
	else:
		subtitle.text = "The following abilities will execute in order:"
	subtitle.position = Vector2(20, 45)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color.WHITE)
	pre_combat_check_panel.add_child(subtitle)

	# Create scrollable container for ability list
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(20, 75)
	scroll.custom_minimum_size = Vector2(panel_width - 40, panel_height - 150)
	pre_combat_check_panel.add_child(scroll)

	# Create ability list container
	pre_combat_ability_list = VBoxContainer.new()
	pre_combat_ability_list.custom_minimum_size = Vector2(panel_width - 60, 0)
	scroll.add_child(pre_combat_ability_list)

	# Add each ability to the list
	for i in range(queued_abilities.size()):
		var ability_info = queued_abilities[i]
		var ship = ability_info["ship"]
		var ability_data = ability_info["ability_data"]
		var predicted_target = ability_info["predicted_target"]

		# Create ability entry
		var entry = HBoxContainer.new()
		entry.custom_minimum_size = Vector2(panel_width - 60, 40)

		# Queue number
		var number_label = Label.new()
		number_label.text = str(i + 1) + "."
		number_label.custom_minimum_size = Vector2(30, 0)
		number_label.add_theme_font_size_override("font_size", 16)
		entry.add_child(number_label)

		# Ship name
		var ship_label = Label.new()
		ship_label.text = ship.get("type", "Unknown")
		ship_label.custom_minimum_size = Vector2(120, 0)
		ship_label.add_theme_font_size_override("font_size", 14)
		ship_label.add_theme_color_override("font_color", Color.CYAN)
		entry.add_child(ship_label)

		# Arrow
		var arrow_label = Label.new()
		arrow_label.text = "→"
		arrow_label.custom_minimum_size = Vector2(20, 0)
		arrow_label.add_theme_font_size_override("font_size", 16)
		entry.add_child(arrow_label)

		# Ability name
		var ability_label = Label.new()
		ability_label.text = ability_data.get("ability_name", "Unknown")
		ability_label.custom_minimum_size = Vector2(150, 0)
		ability_label.add_theme_font_size_override("font_size", 14)
		ability_label.add_theme_color_override("font_color", Color.ORANGE)
		entry.add_child(ability_label)

		# Arrow
		var arrow_label2 = Label.new()
		arrow_label2.text = "→"
		arrow_label2.custom_minimum_size = Vector2(20, 0)
		arrow_label2.add_theme_font_size_override("font_size", 16)
		entry.add_child(arrow_label2)

		# Target
		var target_label = Label.new()
		target_label.text = predicted_target
		target_label.custom_minimum_size = Vector2(100, 0)
		target_label.add_theme_font_size_override("font_size", 14)
		target_label.add_theme_color_override("font_color", Color.RED)
		entry.add_child(target_label)

		pre_combat_ability_list.add_child(entry)

	# Create confirm button
	pre_combat_confirm_button = Button.new()
	pre_combat_confirm_button.text = "Confirm Combat Start"
	pre_combat_confirm_button.position = Vector2(panel_width / 2 - 100, panel_height - 50)
	pre_combat_confirm_button.custom_minimum_size = Vector2(200, 40)
	pre_combat_confirm_button.pressed.connect(confirm_combat_start)
	pre_combat_check_panel.add_child(pre_combat_confirm_button)

func confirm_combat_start():
	"""Confirmed - proceed with combat after reviewing abilities"""
	print("=== CONFIRMING COMBAT START ===")

	# Hide pre-combat check UI
	if pre_combat_check_panel:
		pre_combat_check_panel.queue_free()
		pre_combat_check_panel = null

	# Keep combat PAUSED during ability processing
	# Process all queued abilities FIRST (before ships start attacking)
	await process_all_ability_queues_for_lane(zoomed_lane_index)

	# NOW unpause combat and start lane combat
	combat_paused = false
	print("Combat UNPAUSED - lane active")

	# Start lane combat (assign targets and begin attacks)
	start_lane_combat(zoomed_lane_index)

	# Start 5-second timer
	start_zoom_timer()

	print("Combat started for lane ", zoomed_lane_index)

func on_combat_phase_complete():
	# Called when combat timer expires - move to next phase
	print("Combat phase complete for lane ", zoomed_lane_index)

	# Start post-combat cleanup phase (1 second for projectiles to resolve)
	await post_combat_cleanup_phase()

	# Determine next action based on current phase
	if current_turn_phase == "lane_0":
		# Move to lane 1
		proceed_to_lane_transition(1, "lane_1")
	elif current_turn_phase == "lane_1":
		# Move to lane 2
		proceed_to_lane_transition(2, "lane_2")
	elif current_turn_phase == "lane_2":
		# All lanes complete - return to tactical
		return_to_tactical_phase()

func post_combat_cleanup_phase():
	"""1-second cleanup phase to allow projectiles to resolve"""
	print("=== POST-COMBAT CLEANUP PHASE ===")

	# Set cleanup phase flag to prevent new attacks/abilities
	in_cleanup_phase = true

	# Clear all temporary card effects from ships in active lane
	clear_card_effects_for_active_lane()

	# Show cleanup notification
	show_phase_notification("CLEANUP")

	# Wait 1 second for projectiles to finish
	await get_tree().create_timer(1.0).timeout

	# Clean up any remaining projectiles
	cleanup_remaining_projectiles()

	# Clear cleanup phase flag
	in_cleanup_phase = false

	print("=== CLEANUP PHASE COMPLETE ===")

func show_phase_notification(text: String):
	"""Show centered notification for phase transitions"""
	var notification = Label.new()
	notification.text = text
	notification.add_theme_font_size_override("font_size", 32)
	notification.add_theme_color_override("font_color", Color.YELLOW)
	notification.add_theme_color_override("font_outline_color", Color.BLACK)
	notification.add_theme_constant_override("outline_size", 4)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Center on screen
	var viewport_size = get_viewport_rect().size
	notification.position = Vector2(viewport_size.x / 2 - 100, viewport_size.y / 2)
	notification.z_index = 200  # Above everything
	add_child(notification)

	# Animate: fade in, hold, fade out
	notification.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(notification, "modulate:a", 1.0, 0.2)
	tween.tween_interval(0.6)
	tween.tween_property(notification, "modulate:a", 0.0, 0.2)
	tween.tween_callback(notification.queue_free)

func clear_card_effects_for_active_lane():
	"""Clear temporary card effects from all ships in the active lane"""
	if not status_effect_manager:
		return

	# Get all ships in the active lane from lanes array
	if zoomed_lane_index < 0 or zoomed_lane_index >= lanes.size():
		return

	var ships = lanes[zoomed_lane_index]["units"]

	# Clear card effects from each ship
	for ship in ships:
		if ship.has("card_effects") and ship["card_effects"].size() > 0:
			print("Combat_2: Clearing ", ship["card_effects"].size(), " card effects from ", ship.get("type", "unknown"))

			# Remove each card effect
			for effect in ship["card_effects"]:
				if status_effect_manager.has_method("_remove_card_effect"):
					status_effect_manager._remove_card_effect(ship, effect)

			# Clear the array
			ship["card_effects"].clear()

func cleanup_remaining_projectiles():
	"""Remove any projectiles that haven't resolved after cleanup phase"""
	var projectiles_cleaned = 0

	# Find all Sprite2D children that are projectiles (have laser textures)
	for child in get_children():
		if child is Sprite2D and is_instance_valid(child):
			# Check if this is a projectile (you can identify by texture path or other means)
			if child.texture != null:
				child.queue_free()
				projectiles_cleaned += 1

	if projectiles_cleaned > 0:
		print("Cleaned up ", projectiles_cleaned, " unresolved projectiles")

func proceed_to_lane_transition(next_lane_index: int, next_phase: String):
	# Transition to the next lane
	print("Transitioning to lane ", next_lane_index)

	# Clean up any active drag state
	if is_dragging_ship:
		cleanup_ship_drag()

	# Stop current lane combat
	stop_lane_combat(zoomed_lane_index)

	# Resume idle animations for the previous lane (now out of focus)
	if zoomed_lane_index >= 0:
		resume_lane_idle_animations(zoomed_lane_index)

	# Pause combat for precombat phase
	combat_paused = true
	print("Combat PAUSED - entering precombat phase for lane ", next_lane_index)

	# Update phase
	current_turn_phase = next_phase

	# Reset movement flags for this lane's precombat phase
	reset_ship_movement_flags()

	# Zoom to next lane
	zoom_to_lane(next_lane_index)

	# ENEMY PATHFINDING ALPHA - Move enemies toward player before precombat phase
	enemy_pathfinding_alpha(next_lane_index)

	# Show button and wait for player
	waiting_for_combat_start = true
	if turn_progression_button:
		turn_progression_button.text = "Start Combat"
		turn_progression_button.visible = true
	
	# Update card system visibility (show hand and make cards playable)
	update_card_system_visibility()

func return_to_tactical_phase():
	# Return to tactical view and reset turn cycle
	print("All lanes complete - returning to tactical view")
	
	# Dissipate all overshields and show notifications
	dissipate_all_overshields()

	# Discard hand after lane 3 combat completes
	print("Combat_2: Clearing hand after lane 3 completion")
	CardHandManager.clear_hand()

	# Stop combat and return to tactical
	_on_return_to_tactical()

	# Reset to tactical phase
	current_turn_phase = "tactical"
	waiting_for_combat_start = false

	# Reset movement flags for all units (new turn)
	reset_ship_movement_flags()
	
	# Draw 3 cards at start of tactical phase
	print("Combat_2: Drawing 3 cards for tactical phase")
	for i in range(3):
		var success = CardHandManager.draw_card()
		if not success:
			print("Combat_2: Could not draw card ", i + 1)
			break

	# Show proceed button for next turn
	if turn_progression_button:
		turn_progression_button.text = "Proceed to Lane 1"
		turn_progression_button.visible = true

func dissipate_all_overshields():
	# Remove all overshields from all units and show notifications
	# Called at the end of lane 3 combat
	print("Combat_2: Dissipating all overshields")
	
	for lane in lanes:
		for unit in lane["units"]:
			var current_overshield = unit.get("current_overshield", 0)
			if current_overshield > 0:
				# Show notification
				var notification_text = "-%d OVERSHIELD" % current_overshield
				show_overshield_dissipation_notification(unit, notification_text)
				
				# Remove overshield
				unit["current_overshield"] = 0
				
				# Update health bar
				update_health_bar(unit)

func show_overshield_dissipation_notification(unit: Dictionary, text: String):
	"""Show a notification that overshield is dissipating"""
	var container = unit.get("container")
	if not container:
		return
	
	# Create notification label
	var notification = Label.new()
	notification.text = text
	notification.add_theme_font_size_override("font_size", 14)
	notification.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0, 1.0))  # Gold
	notification.add_theme_color_override("font_outline_color", Color.BLACK)
	notification.add_theme_constant_override("outline_size", 2)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.z_index = 1000
	
	# Position above unit
	add_child(notification)
	notification.global_position = container.global_position + Vector2(container.size.x / 2 - 50, -40)
	
	# Animate and fade out
	var tween = notification.create_tween()
	tween.set_parallel(true)
	tween.tween_property(notification, "position:y", notification.position.y - 40, 1.5)
	tween.tween_property(notification, "modulate:a", 0.0, 1.5).set_delay(0.5)
	
	await tween.finished
	notification.queue_free()

func reset_ship_movement_flags():
	# Reset the has_moved_this_turn flag for all units
	# Called at the start of each new turn (tactical phase)
	for lane in lanes:
		for unit in lane["units"]:
			unit["has_moved_this_turn"] = false
	print("Reset movement flags for all ships")

func start_lane_combat(lane_index: int):
	# Start combat for all ships in a specific lane (when zoomed in)
	if lane_index < 0 or lane_index >= lanes.size():
		return

	var lane = lanes[lane_index]
	print("Starting combat for lane ", lane_index, " with ", lane["units"].size(), " units")

	# Activate turrets that can attack this lane
	activate_turrets_for_lane(lane_index)

	# Activate enemy turrets that can attack this lane
	activate_enemy_turrets_for_lane(lane_index)

	for unit in lane["units"]:
		# Assign random target (will be restricted to same lane due to is_zoomed)
		assign_random_target(unit)
		# Start target switching timer (switches every 3 seconds)
		start_target_switch_timer(unit)

func stop_lane_combat(lane_index: int):
	# Stop combat for all ships in a specific lane
	if lane_index < 0 or lane_index >= lanes.size():
		return

	var lane = lanes[lane_index]
	print("Stopping combat for lane ", lane_index)

	# Deactivate turrets that were attacking this lane
	deactivate_turrets_for_lane(lane_index)

	# Deactivate enemy turrets that were attacking this lane
	deactivate_enemy_turrets_for_lane(lane_index)

	for unit in lane["units"]:
		# End any active abilities when turn ends
		if unit.get("ability_active", false):
			end_active_ability(unit)

		# Stop attack timers
		if unit.has("container"):
			var container = unit["container"]
			var attack_timer = container.get_node_or_null("AttackTimer")
			if attack_timer:
				attack_timer.stop()
				attack_timer.queue_free()
			var switch_timer = container.get_node_or_null("TargetSwitchTimer")
			if switch_timer:
				switch_timer.stop()
				switch_timer.queue_free()
		# Clear auto-combat data
		unit.erase("auto_target")
		# Reset sprite modulation
		if unit.has("sprite"):
			unit["sprite"].modulate = Color(1, 1, 1)

# Turret combat functions

func activate_turrets_for_lane(lane_index: int):
	# NEW: Activate all turrets in this lane (all 5 rows)
	print("Activating turrets for lane ", lane_index)

	# Activate all enabled turrets in this lane's grid
	for row_index in range(CombatConstants.NUM_TURRET_ROWS):
		var turret = ship_manager.get_turret_at_position(lane_index, row_index, "player")

		if turret.is_empty() or not turret.get("enabled", false):
			continue

		print("  Turret ", turret["display_name"], " (row ", row_index, ") engaging lane ", lane_index)

		# Turret uses gamma targeting automatically
		var target = targeting_system.select_target_for_unit(turret, "gamma")
		turret["auto_target"] = target

		# Start attack timer
		start_turret_attack_timer(turret)

func deactivate_turrets_for_lane(lane_index: int):
	# NEW: Deactivate all turrets in this lane (all 5 rows)
	print("Deactivating turrets for lane ", lane_index)

	# Deactivate all enabled turrets in this lane's grid
	for row_index in range(CombatConstants.NUM_TURRET_ROWS):
		var turret = ship_manager.get_turret_at_position(lane_index, row_index, "player")

		if turret.is_empty() or not turret.get("enabled", false):
			continue

		# Stop this turret
		stop_turret_combat(turret)

func assign_turret_targets(turret: Dictionary, active_lane: int = -1):
	# NEW: Use gamma targeting system for turrets
	# Turrets now target: ship in same row → turret in same row → mothership/boss
	if turret.is_empty() or not turret["enabled"]:
		return

	# Use the targeting system to select target via gamma targeting
	var target = targeting_system.select_target_for_unit(turret, "gamma")

	if target.is_empty():
		print("  No targets found for turret ", turret.get("display_name", "unnamed turret"))
		turret.erase("auto_target")
		return

	turret["auto_target"] = target
	print("  Turret ", turret.get("display_name", "unnamed turret"), " targeting ", target.get("type", "unknown"))

func start_turret_attack_timer(turret: Dictionary):
	# Start attack timer for turret
	if not turret.has("container"):
		return

	var container = turret["container"]

	# Remove existing timer if any
	var existing_timer = container.get_node_or_null("AttackTimer")
	if existing_timer:
		existing_timer.queue_free()

	# Create attack timer
	var attack_timer = Timer.new()
	attack_timer.name = "AttackTimer"
	# Calculate attack interval: 1 / attack_speed = seconds per attack
	# attack_speed of 1.0 = 1 attack/second = 1.0s per attack
	# attack_speed of 0.5 = 0.5 attacks/second = 2.0s per attack
	# attack_speed of 2.0 = 2 attacks/second = 0.5s per attack
	var attack_speed = turret["stats"]["attack_speed"]
	# Apply freeze modifier if active
	if status_effect_manager:
		attack_speed *= status_effect_manager.get_freeze_attack_speed_multiplier(turret)
	var attack_interval = 1.0 / attack_speed
	attack_timer.wait_time = attack_interval
	attack_timer.one_shot = false
	attack_timer.timeout.connect(func(): execute_turret_attack(turret))
	container.add_child(attack_timer)
	attack_timer.start()

	# Also start target switching timer (switch targets every 3 seconds)
	var switch_timer = Timer.new()
	switch_timer.name = "TargetSwitchTimer"
	switch_timer.wait_time = 3.0
	switch_timer.one_shot = false
	# Use the active lane stored in the turret (if any)
	switch_timer.timeout.connect(func():
		var active_lane = turret.get("active_lane", -1)
		assign_turret_targets(turret, active_lane)
	)
	container.add_child(switch_timer)
	switch_timer.start()

func execute_turret_attack(turret: Dictionary):
	# Execute a turret attack

	# Don't attack during cleanup phase
	if in_cleanup_phase:
		return

	if not turret.has("auto_target") or turret["auto_target"].is_empty():
		# No target, try to find one
		var active_lane = turret.get("active_lane", -1)
		assign_turret_targets(turret, active_lane)
		return

	var target = turret["auto_target"]

	# Check if target is still valid (not destroyed)
	if not target.has("container") or not is_instance_valid(target["container"]):
		# Target destroyed, find new target
		var active_lane = turret.get("active_lane", -1)
		assign_turret_targets(turret, active_lane)
		return

	# Execute the attack (use auto-combat laser firing system)
	auto_fire_laser(turret, target)

func stop_turret_combat(turret: Dictionary):
	# Stop a turret's combat
	if not turret.has("container"):
		return

	var container = turret["container"]

	# Check if container is still valid (not freed)
	if not is_instance_valid(container):
		return

	# Stop attack timer
	var attack_timer = container.get_node_or_null("AttackTimer")
	if attack_timer:
		attack_timer.stop()
		attack_timer.queue_free()

	# Stop switch timer
	var switch_timer = container.get_node_or_null("TargetSwitchTimer")
	if switch_timer:
		switch_timer.stop()
		switch_timer.queue_free()

	# Clear target and active lane
	turret.erase("auto_target")
	turret.erase("active_lane")

	# Reset sprite modulation
	if turret.has("sprite"):
		turret["sprite"].modulate = Color(1, 1, 1)

# Enemy Turret Functions
func activate_enemy_turrets_for_lane(lane_index: int):
	# NEW: Activate all enemy turrets in this lane (all 5 rows)
	print("Activating enemy turrets for lane ", lane_index)

	# Activate all enabled enemy turrets in this lane's grid
	for row_index in range(CombatConstants.NUM_TURRET_ROWS):
		var enemy_turret = ship_manager.get_turret_at_position(lane_index, row_index, "enemy")

		if enemy_turret.is_empty() or not enemy_turret.get("enabled", false):
			continue

		print("  Enemy Turret ", enemy_turret["display_name"], " (row ", row_index, ") engaging lane ", lane_index)

		# Enemy turret uses gamma targeting automatically
		var target = targeting_system.select_target_for_unit(enemy_turret, "gamma")
		enemy_turret["auto_target"] = target

		# Start attack timer
		start_enemy_turret_attack_timer(enemy_turret)

func deactivate_enemy_turrets_for_lane(lane_index: int):
	# NEW: Deactivate all enemy turrets in this lane (all 5 rows)
	print("Deactivating enemy turrets for lane ", lane_index)

	# Deactivate all enabled enemy turrets in this lane's grid
	for row_index in range(CombatConstants.NUM_TURRET_ROWS):
		var enemy_turret = ship_manager.get_turret_at_position(lane_index, row_index, "enemy")

		if enemy_turret.is_empty() or not enemy_turret.get("enabled", false):
			continue

		stop_enemy_turret_combat(enemy_turret)

func assign_enemy_turret_target(enemy_turret: Dictionary, active_lane: int = -1):
	# NEW: Use gamma targeting system for enemy turrets
	# Enemy turrets now target: ship in same row → turret in same row → mothership
	if enemy_turret.is_empty() or not enemy_turret["enabled"]:
		return

	# Use the targeting system to select target via gamma targeting
	var target = targeting_system.select_target_for_unit(enemy_turret, "gamma")

	if target.is_empty():
		print("  No targets found for enemy turret ", enemy_turret.get("display_name", "unnamed enemy turret"))
		enemy_turret.erase("auto_target")
		return

	enemy_turret["auto_target"] = target
	print("  Enemy Turret ", enemy_turret.get("display_name", "unnamed enemy turret"), " targeting ", target.get("type", "unknown"))

func start_enemy_turret_attack_timer(enemy_turret: Dictionary):
	# Start attack timer for enemy turret
	if not enemy_turret.has("container"):
		return

	var container = enemy_turret["container"]

	# Remove existing timer if any
	var existing_timer = container.get_node_or_null("AttackTimer")
	if existing_timer:
		existing_timer.queue_free()

	# Create attack timer
	var attack_timer = Timer.new()
	attack_timer.name = "AttackTimer"
	var attack_speed = enemy_turret["stats"]["attack_speed"]
	# Apply freeze modifier if active
	if status_effect_manager:
		attack_speed *= status_effect_manager.get_freeze_attack_speed_multiplier(enemy_turret)
	var attack_interval = 1.0 / attack_speed
	attack_timer.wait_time = attack_interval
	attack_timer.autostart = true
	attack_timer.timeout.connect(func():
		enemy_turret_auto_attack(enemy_turret)
	)
	container.add_child(attack_timer)

	# Create target switch timer (switches targets every 3 seconds)
	var switch_timer = Timer.new()
	switch_timer.name = "TargetSwitchTimer"
	switch_timer.wait_time = 3.0
	switch_timer.autostart = true
	switch_timer.timeout.connect(func():
		# Reassign target
		var current_lane = enemy_turret.get("target_lane", -1)
		assign_enemy_turret_target(enemy_turret, current_lane)
	)
	container.add_child(switch_timer)

	print("  Enemy turret attack timer started: ", attack_interval, "s interval")

func enemy_turret_auto_attack(enemy_turret: Dictionary):
	# Enemy turret performs an auto-attack on its assigned target
	if enemy_turret.is_empty():
		return

	# Don't attack during cleanup phase
	if in_cleanup_phase:
		return

	# Check if we have a target
	if not enemy_turret.has("auto_target") or enemy_turret["auto_target"].is_empty():
		# Try to find a target
		assign_enemy_turret_target(enemy_turret, enemy_turret.get("target_lane", -1))
		return

	var target = enemy_turret["auto_target"]

	# Validate target still exists
	if not is_instance_valid(target.get("container")):
		# Target destroyed, find new target
		assign_enemy_turret_target(enemy_turret, enemy_turret.get("target_lane", -1))
		return

	# Rotate turret to face target
	#auto_rotate_to_target(enemy_turret, target)

	# Fire projectile at target
	auto_fire_laser(enemy_turret, target)

	# Generate energy (if applicable)
	if enemy_turret.has("current_energy") and not enemy_turret.get("ability_active", false):
		var energy_gain = randi_range(2, 4)
		enemy_turret["current_energy"] = min(
			enemy_turret["current_energy"] + energy_gain,
			enemy_turret["stats"].get("starting_energy", 100)
		)
		update_energy_bar(enemy_turret)

		# Check if ability should be cast
		if enemy_turret["current_energy"] >= enemy_turret["stats"].get("starting_energy", 100):
			cast_ability(enemy_turret)

func stop_enemy_turret_combat(enemy_turret: Dictionary):
	# Stop an enemy turret's combat
	if not enemy_turret.has("container"):
		return

	var container = enemy_turret["container"]

	# Stop attack timer
	var attack_timer = container.get_node_or_null("AttackTimer")
	if attack_timer:
		attack_timer.stop()
		attack_timer.queue_free()

	# Stop switch timer
	var switch_timer = container.get_node_or_null("TargetSwitchTimer")
	if switch_timer:
		switch_timer.stop()
		switch_timer.queue_free()

	# Clear target
	enemy_turret.erase("auto_target")

	# Reset sprite modulation
	if enemy_turret.has("sprite"):
		enemy_turret["sprite"].modulate = Color(1, 1, 1)

func start_auto_combat():
	# Start auto-combat: all ships attack random enemies
	# Assign random targets to all units
	for lane in lanes:
		for unit in lane["units"]:
			# Assign random target
			assign_random_target(unit)
			# Start target switching timer (switches every 3 seconds)
			start_target_switch_timer(unit)

func stop_auto_combat():
	# Stop all auto-combat attacks
	for lane in lanes:
		for unit in lane["units"]:
			# Stop attack timers
			if unit.has("container"):
				var container = unit["container"]
				var attack_timer = container.get_node_or_null("AttackTimer")
				if attack_timer:
					attack_timer.stop()
					attack_timer.queue_free()
				var switch_timer = container.get_node_or_null("TargetSwitchTimer")
				if switch_timer:
					switch_timer.stop()
					switch_timer.queue_free()
			# Clear auto-combat data
			unit.erase("auto_target")
			# Reset sprite modulation
			if unit.has("sprite"):
				unit["sprite"].modulate = Color(1, 1, 1)

# ============================================================================
# TARGETING HELPER FUNCTIONS (for targeting_function_alpha)
# ============================================================================

func find_closest_in_row(unit: Dictionary, unit_lane: int, unit_row: int, is_enemy: bool) -> Dictionary:
	# Find the closest enemy in the same lane and same grid row
	# Returns closest enemy by grid column distance, or empty Dictionary if none found

	if unit_lane < 0 or unit_row < 0:
		return {}

	var unit_col = unit.get("grid_col", -1)
	if unit_col < 0:
		return {}

	var lane = lanes[unit_lane]
	var closest_target = {}
	var closest_distance = 999999

	for other_unit in lane["units"]:
		# Skip if same faction
		var other_is_enemy = other_unit.get("is_enemy", false)
		if is_enemy == other_is_enemy:
			continue

		# Check if in same row
		var other_row = other_unit.get("grid_row", -1)
		if other_row != unit_row:
			continue

		# Calculate column distance
		var other_col = other_unit.get("grid_col", -1)
		if other_col < 0:
			continue

		var distance = abs(unit_col - other_col)
		if distance < closest_distance:
			closest_distance = distance
			closest_target = other_unit

	return closest_target

func find_targetable_turret(unit: Dictionary, unit_lane: int, is_enemy: bool) -> Dictionary:
	# Find a turret that the unit can target
	# Player units don't target turrets (turrets are player-only)
	# Enemy units target player turrets that can attack their lane

	if not is_enemy:
		# Player units don't target turrets
		return {}

	# Enemy units target player turrets
	for turret in turrets:
		if not turret.get("enabled", false):
			continue

		# Check if this turret can attack the unit's lane
		if unit_lane in turret.get("target_lanes", []):
			return turret

	return {}

func find_closest_in_adjacent_rows(unit: Dictionary, unit_lane: int, unit_row: int, is_enemy: bool) -> Dictionary:
	# Find the closest enemy in adjacent rows (row ± 1) within the same lane
	# Returns closest enemy across both adjacent rows

	if unit_lane < 0 or unit_row < 0:
		return {}

	var unit_col = unit.get("grid_col", -1)
	if unit_col < 0:
		return {}

	var lane = lanes[unit_lane]
	var closest_target = {}
	var closest_distance = 999999

	# Check row above (row - 1)
	var adjacent_rows = []
	if unit_row > 0:
		adjacent_rows.append(unit_row - 1)
	if unit_row < CombatConstants.GRID_ROWS - 1:
		adjacent_rows.append(unit_row + 1)

	for other_unit in lane["units"]:
		# Skip if same faction
		var other_is_enemy = other_unit.get("is_enemy", false)
		if is_enemy == other_is_enemy:
			continue

		# Check if in adjacent row
		var other_row = other_unit.get("grid_row", -1)
		if other_row not in adjacent_rows:
			continue

		# Calculate column distance
		var other_col = other_unit.get("grid_col", -1)
		if other_col < 0:
			continue

		var distance = abs(unit_col - other_col)
		if distance < closest_distance:
			closest_distance = distance
			closest_target = other_unit

	return closest_target

func find_any_in_lane(unit: Dictionary, unit_lane: int, is_enemy: bool) -> Dictionary:
	# Find any enemy in the unit's lane (fallback option)
	# Returns closest by column distance

	if unit_lane < 0:
		return {}

	var unit_col = unit.get("grid_col", -1)
	if unit_col < 0:
		return {}

	var lane = lanes[unit_lane]
	var closest_target = {}
	var closest_distance = 999999

	for other_unit in lane["units"]:
		# Skip if same faction
		var other_is_enemy = other_unit.get("is_enemy", false)
		if is_enemy == other_is_enemy:
			continue

		# Calculate column distance
		var other_col = other_unit.get("grid_col", -1)
		if other_col < 0:
			continue

		var distance = abs(unit_col - other_col)
		if distance < closest_distance:
			closest_distance = distance
			closest_target = other_unit

	return closest_target

# ============================================================================
# MAIN TARGETING FUNCTION (Row-Based Priority Targeting)
# ============================================================================

func targeting_function_alpha(unit: Dictionary) -> Dictionary:
	# Strategic row-based targeting with priority system:
	# 1. Closest enemy in same row (same lane + grid_row)
	# 2. Turret or spawner (if enemy unit)
	# 3. Closest enemy in adjacent rows (row ± 1)
	# 4. Mothership or boss (not implemented - skip for now)
	# 5. Any enemy in same lane
	# 6. No target (return empty)

	if unit.is_empty():
		return {}

	var unit_lane = unit.get("lane_index", -1)
	var unit_row = unit.get("grid_row", -1)
	var is_enemy = unit.get("is_enemy", false)

	# Priority 1: Same row (same lane + same grid_row)
	var same_row_target = find_closest_in_row(unit, unit_lane, unit_row, is_enemy)
	if not same_row_target.is_empty():
		print("  [Alpha] ", unit.get("type"), " → same row: ", same_row_target.get("type"))
		return same_row_target

	# Priority 2: Turrets/spawners
	var turret_target = find_targetable_turret(unit, unit_lane, is_enemy)
	if not turret_target.is_empty():
		print("  [Alpha] ", unit.get("type"), " → turret: ", turret_target.get("type"))
		return turret_target

	# Priority 3: Adjacent rows (row ± 1)
	var adjacent_target = find_closest_in_adjacent_rows(unit, unit_lane, unit_row, is_enemy)
	if not adjacent_target.is_empty():
		print("  [Alpha] ", unit.get("type"), " → adjacent row: ", adjacent_target.get("type"))
		return adjacent_target

	# Priority 4: Mothership or boss (skipped for now - would need targetable structure objects)

	# Priority 5: Any enemy in lane
	var lane_target = find_any_in_lane(unit, unit_lane, is_enemy)
	if not lane_target.is_empty():
		print("  [Alpha] ", unit.get("type"), " → any in lane: ", lane_target.get("type"))
		return lane_target

	# Priority 6: No target
	print("  [Alpha] ", unit.get("type"), " → no targets available")
	return {}

# ============================================================================
# BETA TARGETING FUNCTION (Row-focused combat)
# ============================================================================

func targeting_function_beta(unit: Dictionary) -> Dictionary:
	# Beta row-based targeting with strict row focus:
	# 1. Ships in same row only (same lane + grid_row)
	# 2. Turrets/spawners in lane (if no same-row ships)
	# 3. Mothership/boss (if no turrets)
	# 4. Any ship in same lane (fallback, ignores row)
	# 5. No target (return empty)

	if unit.is_empty():
		return {}

	var unit_lane = unit.get("lane_index", -1)
	var unit_row = unit.get("grid_row", -1)
	var is_enemy = unit.get("is_enemy", false)

	# Priority 1: Same row only (strict row-based combat)
	var same_row_target = find_closest_in_row(unit, unit_lane, unit_row, is_enemy)
	if not same_row_target.is_empty():
		print("  [Beta] ", unit.get("type"), " → same row: ", same_row_target.get("type"))
		return same_row_target

	# Priority 2: Turrets/spawners in lane
	var turret_target = find_targetable_turret(unit, unit_lane, is_enemy)
	if not turret_target.is_empty():
		print("  [Beta] ", unit.get("type"), " → turret: ", turret_target.get("type"))
		return turret_target

	# Priority 3: Mothership/boss (enemy units target player mothership)
	if is_enemy:
		# Find player mothership (stored in turrets array as special entry)
		# The mothership is not currently a targetable object, so we skip this
		# In the future, this could target a mothership Dictionary
		pass

	# Priority 4: Any ship in same lane (fallback)
	var lane_target = find_any_in_lane(unit, unit_lane, is_enemy)
	if not lane_target.is_empty():
		print("  [Beta] ", unit.get("type"), " → any in lane: ", lane_target.get("type"))
		return lane_target

	# Priority 5: No target
	print("  [Beta] ", unit.get("type"), " → no targets available")
	return {}

# ============================================================================
# CURRENT TARGETING FUNCTION (uses targeting_function_alpha)
# ============================================================================

func assign_random_target(unit: Dictionary, restrict_to_lane: int = -1):
	# NEW: Use CombatTargetingSystem for target selection
	# Assign a target to a unit based on current targeting mode (gamma is default)

	if unit.is_empty():
		return

	# Determine which targeting mode to use
	var is_enemy = unit.get("is_enemy", false)
	var target_mode = enemy_targeting_mode if is_enemy else player_targeting_mode

	# Use the targeting system to select target
	var target = targeting_system.select_target_for_unit(unit, target_mode)

	if target.is_empty():
		unit["auto_target"] = null
		print("No targets available for ", unit.get("type", "unknown"))
		return

	# Assign target and start attacking
	unit["auto_target"] = target
	start_auto_attack(unit, target)

# ============================================================================
# RANDOM TARGETING FUNCTION (Original priority-based random selection)
# ============================================================================

func targeting_function_random(unit: Dictionary, restrict_to_lane: int = -1) -> Dictionary:
	# Random targeting with priority system (original logic)
	# Returns a random target Dictionary, or empty Dictionary if none found

	if unit.is_empty():
		return {}

	var is_enemy = unit.get("is_enemy", false)

	# Determine which lane this unit is in
	var unit_lane_index = -1
	for lane in lanes:
		if lane["units"].has(unit):
			unit_lane_index = lane["index"]
			break

	# Priority 1: Ships in the same lane
	var ship_targets: Array[Dictionary] = []
	for lane in lanes:
		# Skip lanes if we're restricting to a specific lane
		if restrict_to_lane >= 0 and lane["index"] != restrict_to_lane:
			continue

		# When in zoomed mode, only target ships in the same lane
		if is_zoomed and lane["index"] != unit_lane_index:
			continue

		for other_unit in lane["units"]:
			var other_is_enemy = other_unit.get("is_enemy", false)
			if is_enemy != other_is_enemy:  # Opposite factions
				ship_targets.append(other_unit)

	# Priority 2: Secondary turrets (in-lane turrets with single target_lane)
	var secondary_turret_targets: Array[Dictionary] = []

	# Priority 3: Bi-lane turrets (turrets with multiple target_lanes)
	var bilane_turret_targets: Array[Dictionary] = []

	# If this is an enemy, also consider turrets as targets
	if is_enemy:
		for turret in turrets:
			if not turret["enabled"]:
				continue

			# Determine which lane to check
			var check_lane = restrict_to_lane if restrict_to_lane >= 0 else unit_lane_index

			# Check if turret is in a valid lane for targeting
			if check_lane >= 0 and check_lane in turret["target_lanes"]:
				# Separate by turret type
				if turret["target_lanes"].size() == 1:
					# Secondary turret (in-lane, single target lane)
					secondary_turret_targets.append(turret)
				else:
					# Bi-lane turret (multiple target lanes)
					bilane_turret_targets.append(turret)

	# Select from highest priority non-empty group
	var potential_targets: Array[Dictionary] = []
	if not ship_targets.is_empty():
		potential_targets = ship_targets
		# print("Targeting ships (priority 1)")
	elif not secondary_turret_targets.is_empty():
		potential_targets = secondary_turret_targets
		# print("Targeting secondary turrets (priority 2)")
	elif not bilane_turret_targets.is_empty():
		potential_targets = bilane_turret_targets
		# print("Targeting bi-lane turrets (priority 3)")

	# If no targets, return empty
	if potential_targets.is_empty():
		print("  [Random] No targets available for ", unit.get("type", "unknown"))
		return {}

	# Pick random target from the selected priority group
	var random_index = randi() % potential_targets.size()
	var target = potential_targets[random_index]

	print("  [Random] ", unit.get("type", "unknown"), " → ", target.get("type", "unknown"))
	return target

func start_target_switch_timer(unit: Dictionary):
	# Start a timer that switches targets every 3 seconds
	if unit.is_empty() or not unit.has("container"):
		return

	var container = unit["container"]

	# Clear existing timer
	var existing_timer = container.get_node_or_null("TargetSwitchTimer")
	if existing_timer:
		existing_timer.queue_free()

	# Create timer that fires every 3 seconds
	var timer = Timer.new()
	timer.name = "TargetSwitchTimer"
	timer.wait_time = 3.0
	timer.autostart = true
	timer.timeout.connect(func(): _on_target_switch_timeout(unit))
	container.add_child(timer)

func _on_target_switch_timeout(unit: Dictionary):
	# Switch to a new random target
	if not auto_combat_active:
		return

	if unit.is_empty() or not is_instance_valid(unit.get("container")):
		return

	print("Target switch timer - reassigning for ", unit.get("type", "unknown"))
	assign_random_target(unit)

func start_auto_attack(attacker: Dictionary, target: Dictionary):
	# Start an auto-attack sequence
	if attacker.is_empty() or target.is_empty():
		return

	# Rotate to face target
	auto_rotate_to_target(attacker, target)

	# Calculate attack interval: 1 / attack_speed = seconds per attack
	var attack_speed = attacker["stats"]["attack_speed"]
	# Apply freeze modifier if active
	if status_effect_manager:
		attack_speed *= status_effect_manager.get_freeze_attack_speed_multiplier(attacker)
	var attack_interval = 1.0 / attack_speed

	# Fire first shot after rotation
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(attacker.get("container")):
		return

	# Fire first volley immediately
	await auto_fire_laser(attacker, target)

	# Start continuous attack cycle
	auto_attack_cycle(attacker, target, attack_interval)

func auto_rotate_to_target(attacker: Dictionary, target: Dictionary):
	# Rotate attacker to face target (for auto-combat)
	if attacker.is_empty() or target.is_empty():
		return

	if not attacker.has("sprite") or not attacker.has("container"):
		return

	var attacker_sprite = attacker["sprite"]
	var attacker_pos = attacker["container"].position
	var attacker_size = attacker["size"]

	# Calculate center positions
	var attacker_center = attacker_pos + Vector2(attacker_size / 2, attacker_size / 2)
	var target_center = calculate_target_position(attacker, target, attacker_center)

	# Calculate angle to target
	var direction = target_center - attacker_center
	var target_rotation = direction.angle()

	# Smoothly rotate to target
	var tween = create_tween()
	tween.tween_property(attacker_sprite, "rotation", target_rotation, 0.3)

func auto_attack_cycle(attacker: Dictionary, target: Dictionary, attack_interval: float):
	# Continuous auto-attack cycle
	# Continue attacking while auto-combat is active OR while zoomed into a lane
	while (auto_combat_active or is_zoomed) and not attacker.is_empty() and not target.is_empty():
		# Stop if combat is paused
		if combat_paused:
			# Wait for combat to unpause
			await get_tree().create_timer(0.1).timeout
			continue

		# Stop if in cleanup phase
		if in_cleanup_phase:
			# Wait for cleanup to finish
			await get_tree().create_timer(0.1).timeout
			continue

		# Block autoattack while processing ability stack
		if attacker.get("is_processing_abilities", false):
			# Wait for abilities to finish processing
			await get_tree().create_timer(0.1).timeout
			continue

		# Check if target is still assigned and valid
		var current_target = attacker.get("auto_target")
		if current_target != target or not is_instance_valid(target.get("container")):
			# Target changed or destroyed, stop this cycle
			break

		# Check if attacker still exists
		if not is_instance_valid(attacker.get("container")):
			break

		# Fire all projectiles in this attack
		await auto_fire_laser(attacker, target)

		# Wait for cooldown (timer resets AFTER all projectiles fire)
		await get_tree().create_timer(attack_interval).timeout

func auto_fire_laser(attacker: Dictionary, target: Dictionary):
	# Fire laser projectiles in auto-combat using consolidated weapon system
	if weapon_manager and weapon_manager.has_method("fire_weapon_volley"):
		# Rotate attacker to face target first
		if attacker.has("sprite") and target.has("sprite"):
			await rotate_attacker_to_target(attacker, target)

		# Fire all projectiles simultaneously
		weapon_manager.fire_weapon_volley(attacker, target)
	else:
		print("Combat_2: ERROR - weapon_manager not available for auto_fire_laser")

func rotate_attacker_to_target(attacker: Dictionary, target: Dictionary):
	"""Orient attacker toward target before firing"""
	if not attacker.has("sprite") or not target.has("sprite"):
		return

	var attacker_pos = attacker["sprite"].global_position
	var target_pos = target["sprite"].global_position

	var angle = attacker_pos.angle_to_point(target_pos)

	# Animate rotation
	var tween = create_tween()
	tween.tween_property(attacker["sprite"], "rotation", angle, 0.2)
	await tween.finished

func auto_fire_single_laser(attacker: Dictionary, target: Dictionary):
	# DEPRECATED: Use weapon_manager.fire_weapon_volley instead
	# Fire a single laser in auto-combat
	if attacker.is_empty() or target.is_empty():
		return

	if not is_instance_valid(attacker.get("container")) or not is_instance_valid(target.get("container")):
		return

	var attacker_pos = attacker["container"].position
	var attacker_size = attacker["size"]

	# Calculate center positions
	var start_pos = attacker_pos + Vector2(attacker_size / 2, attacker_size / 2)
	var end_pos = calculate_target_position(attacker, target, start_pos)

	# Calculate direction and angle
	var direction = end_pos - start_pos
	var angle = direction.angle()

	# Get projectile sprite and size from attacker data
	var projectile_sprite_path = attacker.get("projectile_sprite", "res://assets/Effects/laser_light/s_laser_light_001.png")
	var projectile_pixel_size = attacker.get("projectile_size", 6)
	var projectile_texture: Texture2D = load(projectile_sprite_path)

	# Create laser sprite
	var laser = Sprite2D.new()
	laser.texture = projectile_texture
	laser.position = start_pos
	laser.rotation = angle
	laser.z_index = 1
	add_child(laser)

	# Scale laser to desired pixel height
	var laser_height = projectile_texture.get_height()
	var scale_y = float(projectile_pixel_size) / laser_height
	laser.scale = Vector2(scale_y, scale_y)
	laser.offset = Vector2(-projectile_texture.get_width() / 2, -projectile_texture.get_height() / 2)

	# Animate laser
	var flight_duration = 0.2
	var tween = create_tween()
	tween.tween_property(laser, "position", end_pos, flight_duration)
	tween.tween_callback(auto_on_laser_hit.bind(laser, attacker, target))

func auto_on_laser_hit(laser: Sprite2D, attacker: Dictionary, target: Dictionary):
	# DEPRECATED: Use weapon_manager.fire_weapon_volley instead
	# Handle laser reaching target position in auto-combat
	# If hit: destroy laser and apply damage
	# If miss: continue traveling until off-screen

	# Check if units still exist
	if attacker.is_empty() or target.is_empty():
		laser.queue_free()
		return
	if not is_instance_valid(target.get("container")):
		laser.queue_free()
		return

	# Calculate damage
	var damage_result = calculate_damage(attacker, target)

	# Get target position for damage numbers (center of sprite)
	var target_pos = Vector2.ZERO
	if target.has("sprite") and is_instance_valid(target["sprite"]):
		var sprite = target["sprite"]
		target_pos = sprite.global_position + Vector2(0, sprite.size.y / 2.0)

	# Check if attack hit or missed
	if damage_result["is_miss"]:
		# MISS - Show miss damage number and continue laser off-screen
		DamageNumber.show_miss(self, target_pos)
		continue_laser_off_screen(laser)
	elif damage_result["damage"] > 0:
		# HIT - Apply damage and show damage numbers
		var damage_breakdown = apply_damage(target, damage_result["damage"])

		# Show damage numbers for shield and armor damage
		if damage_breakdown["shield_damage"] > 0:
			DamageNumber.show_shield_damage(self, target_pos, damage_breakdown["shield_damage"], damage_result["is_crit"])
		if damage_breakdown["armor_damage"] > 0:
			# Offset armor damage number slightly if both shield and armor were damaged
			var armor_pos = target_pos
			if damage_breakdown["shield_damage"] > 0:
				armor_pos.y += 20  # Offset downward
			DamageNumber.show_armor_damage(self, armor_pos, damage_breakdown["armor_damage"], damage_result["is_crit"])

		# Remove the laser projectile
		laser.queue_free()

		# Flash target
		if target.has("sprite"):
			var target_sprite = target["sprite"]
			var flash_tween = create_tween()
			flash_tween.tween_property(target_sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.05)
			flash_tween.tween_property(target_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)

		# Check for burn application
		if status_effect_manager and attacker.get("burn_on_hit_chance", 0.0) > 0:
			var burn_chance = attacker.get("burn_on_hit_chance", 0.0)
			if randf() < burn_chance:
				status_effect_manager.apply_burn(target, 1)
	else:
		# No damage (shouldn't happen, but handle gracefully)
		continue_laser_off_screen(laser)


# Energy system functions

func gain_energy(unit: Dictionary):
	# Gain 2-4 random energy after each attack
	if unit.is_empty():
		return

	# Don't gain energy when combat is paused
	if combat_paused:
		return

	# Don't gain energy if ability is currently active
	if unit.get("ability_active", false):
		return

	# Skip if unit has no energy system (max energy = 0)
	var max_energy = unit["stats"].get("energy", 0)
	if max_energy <= 0:
		return

	# Random energy gain: 2, 3, or 4
	var energy_gain = randi_range(2, 4)
	var current_energy = unit.get("current_energy", 0)

	unit["current_energy"] = current_energy + energy_gain
	print(unit.get("type", "unknown"), " gained ", energy_gain, " energy (", unit["current_energy"], "/", max_energy, ")")

	# Update energy bar
	update_energy_bar(unit)

	# Check if energy is full
	if unit["current_energy"] >= max_energy:
		cast_ability(unit)

func cast_ability(unit: Dictionary):
	# Cast unit's ability when energy is full
	if unit.is_empty():
		return
	
	# Don't cast abilities while combat is paused (precombat phase)
	if combat_paused:
		print("Ability cast blocked - combat is paused")
		return

	var ability_name = unit.get("ability_name", "")
	var ability_function = unit.get("ability_function", "")

	if ability_name == "":
		print(unit.get("type", "unknown"), " has no ability to cast")
		return

	print("=== ABILITY CAST ===")
	print(unit.get("type", "unknown"), " casts: ", ability_name)
	print("Description: ", unit.get("ability_description", "No description"))
	print("Function: ", ability_function)
	print("====================")

	# Reset energy to 0
	unit["current_energy"] = 0
	update_energy_bar(unit)

	# Check if ability is a card effect (execute_*)
	var ability_func_lower = ability_function.to_lower()
	if ability_func_lower.begins_with("execute_"):
		# This is a card effect - queue it to the ability stack
		var normalized_function = normalize_card_function_name(ability_function) + "_Effect"

		# Create ability data for queue
		var ability_data = {
			"ability_name": ability_name,
			"ability_function": normalized_function,
			"source": "ship_energy"  # From ship energy, not a card
		}

		# Queue the ability on this unit
		queue_ability_for_ship(unit, ability_data)
	elif ability_function != "" and has_method(ability_function):
		# Other ability types - call directly
		call(ability_function, unit)
	else:
		print("WARNING: Ability function not found: ", ability_function)

func normalize_card_function_name(function_name: String) -> String:
	"""Normalize function names to match CardEffects naming convention"""
	# Convert "execute_missile_lock" to "execute_Missile_Lock"
	var parts = function_name.split("_")
	if parts.size() < 2:
		return function_name

	# Keep "execute" as is, capitalize first letter of each word after
	var result = parts[0]
	for i in range(1, parts.size()):
		var word = parts[i]
		if word.length() > 0:
			result += "_" + word.capitalize()

	return result

# ============================================================================
# ABILITY STACK/QUEUE SYSTEM
# ============================================================================

func queue_ability_for_ship(ship: Dictionary, ability_data: Dictionary):
	"""Add an ability to a ship's execution queue"""
	if ship.is_empty() or not ship.has("ability_stack"):
		print("ERROR: Invalid ship for ability queue")
		return

	ship["ability_stack"].append(ability_data)
	print("Queued ability '", ability_data.get("ability_name", "unknown"), "' for ", ship.get("type", "unknown"), " - will execute at combat start")

func process_ability_stack(ship: Dictionary):
	"""Process all abilities in a ship's queue with delays"""
	if ship.is_empty() or not ship.has("ability_stack"):
		return

	# Mark as processing
	ship["is_processing_abilities"] = true

	# Pause attack timer during ability execution
	var attack_timer = null
	if ship.has("container") and is_instance_valid(ship.get("container")):
		attack_timer = ship["container"].get_node_or_null("AttackTimer")
		if attack_timer and attack_timer.is_stopped() == false:
			attack_timer.paused = true

	# Process abilities one by one with cinematic presentation
	while ship["ability_stack"].size() > 0:
		var ability_data = ship["ability_stack"].pop_front()

		print("Processing ability: ", ability_data.get("ability_name", "unknown"))

		# Zoom camera to casting ship
		await zoom_to_unit(ship, 1.3)

		# Execute the ability (cinematic mode - 1.5 seconds total)
		await execute_queued_ability_cinematic(ship, ability_data)

		# Validate ship still exists
		if not is_instance_valid(ship.get("container")):
			break

	# Resume attack timer
	if attack_timer and is_instance_valid(attack_timer) and attack_timer.paused:
		attack_timer.paused = false

	# Reset energy to 0 after processing abilities (prevents re-queueing next turn)
	ship["current_energy"] = 0
	update_energy_bar(ship)

	# Mark as done processing
	ship["is_processing_abilities"] = false
	print(ship.get("type", "unknown"), " finished processing ability stack")

func process_all_ability_queues_for_lane(lane_index: int):
	"""Process ability queues for all ships in a lane at combat start"""
	if lane_index < 0 or lane_index >= lanes.size():
		return

	var lane = lanes[lane_index]
	var ships_with_abilities = []

	# Find all friendly ships with queued abilities
	for unit in lane["units"]:
		if unit.get("is_enemy", false):
			continue  # Skip enemies
		if unit.has("ability_stack") and unit["ability_stack"].size() > 0:
			ships_with_abilities.append(unit)

	if ships_with_abilities.is_empty():
		print("No abilities queued for lane ", lane_index)
		return

	print("=== PROCESSING ABILITY QUEUES FOR LANE ", lane_index, " ===")
	print("Ships with abilities: ", ships_with_abilities.size())

	# Process each ship's ability stack
	for ship in ships_with_abilities:
		await process_ability_stack(ship)

	# Reset camera to lane view
	await reset_camera_to_lane_view()

	# Release all stored projectiles at full speed
	release_stored_projectiles()

	print("=== FINISHED PROCESSING ALL ABILITY QUEUES FOR LANE ", lane_index, " ===")

func execute_queued_ability(ship: Dictionary, ability_data: Dictionary):
	"""Execute a single queued ability"""
	var ability_name = ability_data.get("ability_name", "")
	var ability_function = ability_data.get("ability_function", "")

	print("Executing queued ability: ", ability_name, " (", ability_function, ")")

	# Show notification
	show_ability_notification(ship, ability_name)

	# Validate ship still exists
	if not ship.has("sprite") or not is_instance_valid(ship.get("sprite")):
		print("Ability fizzled - source ship no longer valid")
		show_ability_notification(ship, ability_name + " FIZZLED")
		return

	# Get the target using gamma targeting
	var target = targeting_system.select_target_for_unit(ship, "gamma")

	if not target or target.is_empty():
		print("Ability fizzled - no valid target")
		show_ability_notification(ship, ability_name + " FIZZLED")
		# Still consume the time (already handled by 0.25s delay)
		return

	# Execute the ability effect
	if ability_function.begins_with("execute_"):
		# This is a card effect - use CardEffects
		var success = await CardEffects.execute_card_effect(ability_function, target, self)
		if success:
			print("Ability executed successfully: ", ability_name)
		else:
			print("Ability failed to execute: ", ability_name)
		if success:
			# Only add to discard if it's from a player card, not from ship energy
			var source = ability_data.get("source", "")
			if source != "ship_energy":
				CardHandManager.discard_card(ability_name)
				print("Card ability executed and discarded: ", ability_name)
			else:
				print("Ship ability executed: ", ability_name)
		else:
			print("Ability execution failed: ", ability_name)
	else:
		# Other ability types
		print("WARNING: Unknown ability type: ", ability_function)

func show_ability_notification(unit: Dictionary, ability_name: String):
	"""Display card popup when ability is cast"""
	if unit.is_empty() or not unit.has("container"):
		return

	var container = unit["container"]

	# Try to get card data for this ability
	var card_data = DataManager.get_card_data(ability_name)

	if card_data.is_empty():
		# Fallback to text notification if no card data found
		show_text_notification(unit, ability_name)
		return

	# Create a card instance for the popup
	var card_scene = preload("res://scenes/Card.tscn")
	var card_popup = card_scene.instantiate()

	# Setup card with data in SHORT display mode
	card_popup.card_data = card_data.duplicate()
	card_popup.current_display_mode = 0  # DisplayMode.SHORT
	card_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Scale the card to a reasonable size for popup
	card_popup.scale = Vector2(0.8, 0.8)
	card_popup.z_index = 150

	# Position above the ship
	var card_size = card_popup.custom_minimum_size * card_popup.scale
	card_popup.position = Vector2(-card_size.x / 2, -60)

	container.add_child(card_popup)
	card_popup.update_visuals()

	# Animate: float up and fade out
	var tween = create_tween()
	tween.set_parallel(true)

	# Float upward
	tween.tween_property(card_popup, "position:y", card_popup.position.y - 40, 1.2) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_OUT)

	# Fade out after 0.7 seconds
	tween.tween_property(card_popup, "modulate:a", 0.0, 0.5) \
		.set_delay(0.7)

	# Destroy after animation
	tween.finished.connect(func():
		if is_instance_valid(card_popup):
			card_popup.queue_free()
	)

func show_text_notification(unit: Dictionary, ability_name: String):
	"""Fallback text notification if no card data available"""
	if unit.is_empty() or not unit.has("container"):
		return

	var container = unit["container"]

	# Create notification label
	var notification = Label.new()
	notification.text = ability_name.to_upper() + "!"
	notification.add_theme_font_size_override("font_size", 18)
	notification.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	notification.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	notification.add_theme_constant_override("outline_size", 3)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Position above the ship
	notification.position = Vector2(-50, -40)
	notification.z_index = 150
	container.add_child(notification)

	# Animate: float up and fade out
	var tween = create_tween()
	tween.set_parallel(true)

	# Float upward
	tween.tween_property(notification, "position:y", notification.position.y - 30, 1.0) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_OUT)

	# Fade out after 0.5 seconds
	tween.tween_property(notification, "modulate:a", 0.0, 0.5) \
		.set_delay(0.5)

	# Destroy after animation
	tween.finished.connect(func():
		if is_instance_valid(notification):
			notification.queue_free()
	)

# ============================================================================
# ABILITY IMPLEMENTATIONS
# ============================================================================

func execute_alpha_strike(unit: Dictionary):
	"""Alpha Strike: Double attack speed for 3 seconds"""
	if unit.is_empty():
		return

	print(">>> Alpha Strike activated for ", unit.get("type", "unknown"), " <<<")

	# Store original attack speed
	var original_attack_speed = unit["stats"]["attack_speed"]
	unit["original_attack_speed"] = original_attack_speed

	# Double the attack speed
	unit["stats"]["attack_speed"] = original_attack_speed * 2.0

	# Mark ability as active (blocks energy generation)
	unit["ability_active"] = true

	# Update the attack timer if it exists
	if unit.has("container"):
		var container = unit["container"]
		var attack_timer = container.get_node_or_null("AttackTimer")
		if attack_timer:
			var new_interval = 1.0 / unit["stats"]["attack_speed"]
			attack_timer.wait_time = new_interval
			print("  Attack speed: ", original_attack_speed, " → ", unit["stats"]["attack_speed"])
			print("  Attack interval: ", new_interval, "s")

	# Create duration timer (3 seconds)
	var duration_timer = Timer.new()
	duration_timer.name = "AbilityDurationTimer"
	duration_timer.wait_time = 3.0
	duration_timer.one_shot = true
	duration_timer.timeout.connect(func():
		end_alpha_strike(unit)
	)
	unit["container"].add_child(duration_timer)
	duration_timer.start()

	print("  Duration: 3 seconds")

func end_alpha_strike(unit: Dictionary):
	"""End Alpha Strike ability - restore normal attack speed"""
	if unit.is_empty() or not is_instance_valid(unit.get("container")):
		return

	print(">>> Alpha Strike ended for ", unit.get("type", "unknown"), " <<<")

	# Restore original attack speed
	if unit.has("original_attack_speed"):
		unit["stats"]["attack_speed"] = unit["original_attack_speed"]
		unit.erase("original_attack_speed")

	# Clear ability active flag (re-enable energy generation)
	unit["ability_active"] = false

	# Update the attack timer
	if unit.has("container"):
		var container = unit["container"]
		var attack_timer = container.get_node_or_null("AttackTimer")
		if attack_timer:
			var new_interval = 1.0 / unit["stats"]["attack_speed"]
			attack_timer.wait_time = new_interval
			print("  Attack speed restored to: ", unit["stats"]["attack_speed"])

		# Clean up duration timer
		var duration_timer = container.get_node_or_null("AbilityDurationTimer")
		if duration_timer:
			duration_timer.queue_free()

func end_active_ability(unit: Dictionary):
	"""General function to end any active ability on a unit"""
	if unit.is_empty() or not unit.get("ability_active", false):
		return

	var ability_function = unit.get("ability_function", "")

	# Call the appropriate end function based on ability type
	if ability_function == "execute_alpha_strike":
		end_alpha_strike(unit)
	# Add other ability end functions here as they're implemented
	else:
		# Generic cleanup for unknown abilities
		print("Ending unknown ability: ", ability_function)
		unit["ability_active"] = false
		unit.erase("original_attack_speed")

		# Clean up duration timer
		if unit.has("container"):
			var container = unit["container"]
			var duration_timer = container.get_node_or_null("AbilityDurationTimer")
			if duration_timer:
				duration_timer.queue_free()

# Health bar functions

func create_health_bar(ship_container: Control, ship_size: int, max_shield: int, max_armor: int):
	# Create health bar UI above ship (max 32px wide)
	var bar_width = min(32, ship_size)  # Cap at 32 pixels
	var health_bar_container = Control.new()
	health_bar_container.name = "HealthBar"
	health_bar_container.position = Vector2((ship_size - bar_width) / 2, -18)  # Center above ship, raised a bit for 3-bar layout
	health_bar_container.size = Vector2(bar_width, 12)
	ship_container.add_child(health_bar_container)

	# Background (dark gray)
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.2, 0.2, 0.2, 0.8)
	bg.size = Vector2(bar_width, 12)
	health_bar_container.add_child(bg)

	# Shield bar (cyan/blue) - top
	var shield_bar = ColorRect.new()
	shield_bar.name = "ShieldBar"
	shield_bar.color = Color(0.2, 0.7, 1.0, 1.0)
	shield_bar.size = Vector2(bar_width, 4)
	shield_bar.position = Vector2(0, 0)
	health_bar_container.add_child(shield_bar)
	
	# Overshield bar (golden) - above shield bar
	var overshield_bar = ColorRect.new()
	overshield_bar.name = "OvershieldBar"
	overshield_bar.color = Color(1.0, 0.84, 0.0, 1.0)  # Gold
	overshield_bar.size = Vector2(0, 2)  # Thinner bar, starts at 0 width
	overshield_bar.position = Vector2(0, -2)  # Above shield bar
	health_bar_container.add_child(overshield_bar)

	# Armor bar (red/orange) - middle
	var armor_bar = ColorRect.new()
	armor_bar.name = "ArmorBar"
	armor_bar.color = Color(0.8, 0.3, 0.2, 1.0)
	armor_bar.size = Vector2(bar_width, 4)
	armor_bar.position = Vector2(0, 4)
	health_bar_container.add_child(armor_bar)

	# Energy bar (purple) - bottom
	var energy_bar = ColorRect.new()
	energy_bar.name = "EnergyBar"
	energy_bar.color = Color(0.7, 0.2, 1.0, 1.0)  # Purple
	energy_bar.size = Vector2(bar_width, 4)
	energy_bar.position = Vector2(0, 8)
	health_bar_container.add_child(energy_bar)

func update_health_bar(ship: Dictionary):
	# Update health bar to reflect current health
	if not ship.has("container"):
		return

	var container = ship["container"]
	var health_bar_container = container.get_node_or_null("HealthBar")
	if not health_bar_container:
		return

	var ship_size = ship["size"]
	var bar_width = min(32, ship_size)  # Cap at 32 pixels
	var max_armor = ship["stats"]["armor"]
	var max_shield = ship["stats"]["shield"]
	var current_armor = ship.get("current_armor", max_armor)
	var current_shield = ship.get("current_shield", max_shield)

	# Update armor bar width
	var armor_bar = health_bar_container.get_node_or_null("ArmorBar")
	if armor_bar and max_armor > 0:
		var armor_percent = float(current_armor) / float(max_armor)
		armor_bar.size.x = bar_width * armor_percent

	# Update shield bar width
	var shield_bar = health_bar_container.get_node_or_null("ShieldBar")
	if shield_bar and max_shield > 0:
		var shield_percent = float(current_shield) / float(max_shield)
		shield_bar.size.x = bar_width * shield_percent
	
	# Update overshield bar width (scales based on max_shield)
	var overshield_bar = health_bar_container.get_node_or_null("OvershieldBar")
	if overshield_bar:
		var current_overshield = ship.get("current_overshield", 0)
		if current_overshield > 0 and max_shield > 0:
			var overshield_percent = float(current_overshield) / float(max_shield)
			overshield_bar.size.x = min(bar_width * overshield_percent, bar_width)
			overshield_bar.visible = true
		else:
			overshield_bar.size.x = 0
			overshield_bar.visible = false

	# Also update energy bar
	update_energy_bar(ship)

func update_energy_bar(ship: Dictionary):
	# Update energy bar to reflect current energy
	if not ship.has("container"):
		return

	var container = ship["container"]
	var health_bar_container = container.get_node_or_null("HealthBar")
	if not health_bar_container:
		return

	var ship_size = ship["size"]
	var bar_width = min(32, ship_size)  # Cap at 32 pixels
	var max_energy = ship["stats"].get("energy", 0)
	var current_energy = ship.get("current_energy", 0)

	# Update energy bar width
	var energy_bar = health_bar_container.get_node_or_null("EnergyBar")
	if energy_bar:
		if max_energy > 0:
			var energy_percent = float(current_energy) / float(max_energy)
			energy_bar.size.x = bar_width * energy_percent
		else:
			# No energy system, hide the bar
			energy_bar.size.x = 0

# Stat helper functions

func get_unit_stat(unit: Dictionary, stat_name: String):
	# Get a stat value from a unit's stats dictionary
	if unit.has("stats") and unit["stats"].has(stat_name):
		return unit["stats"][stat_name]
	print("Warning: Unit missing stat '", stat_name, "'")
	return 0

func modify_unit_stat(unit: Dictionary, stat_name: String, amount: float):
	# Modify a stat value (for upgrades/debuffs)
	if unit.has("stats") and unit["stats"].has(stat_name):
		unit["stats"][stat_name] += amount
		print("Modified ", stat_name, " by ", amount, ". New value: ", unit["stats"][stat_name])
		return true
	print("Warning: Cannot modify stat '", stat_name, "' - unit missing stat")
	return false

func get_unit_health_percent(unit: Dictionary) -> float:
	# Calculate total health percentage (armor + shield)
	if not unit.has("stats"):
		return 0.0

	var max_armor = unit["stats"]["armor"]
	var max_shield = unit["stats"]["shield"]
	var current_armor = unit.get("current_armor", max_armor)
	var current_shield = unit.get("current_shield", max_shield)

	var max_health = max_armor + max_shield
	var current_health = current_armor + current_shield

	if max_health <= 0:
		return 0.0

	return (current_health / max_health) * 100.0

func display_unit_stats(unit: Dictionary):
	# Debug function to print all unit stats
	if not unit.has("stats"):
		print("Unit has no stats")
		return

	print("=== Unit Stats ===")
	print("Type: ", unit.get("type", "unknown"))
	print("Armor: ", unit.get("current_armor", 0), " / ", unit["stats"]["armor"])
	print("Shield: ", unit.get("current_shield", 0), " / ", unit["stats"]["shield"])
	print("Reinforced Armor: ", unit["stats"]["reinforced_armor"], "%")
	print("Evasion: ", unit["stats"]["evasion"], "%")
	print("Accuracy: ", unit["stats"]["accuracy"])
	print("Attack Speed: ", unit["stats"]["attack_speed"], "x")
	print("Num Attacks: ", unit["stats"]["num_attacks"])
	print("Amplitude: ", unit["stats"]["amplitude"])
	print("Frequency: ", unit["stats"]["frequency"])
	print("Health: ", get_unit_health_percent(unit), "%")
	print("==================")

# ============================================================================
# CINEMATIC ABILITY EXECUTION
# ============================================================================

var stored_projectiles: Array = []  # Stores projectiles created during ability queue

func execute_queued_ability_cinematic(ship: Dictionary, ability_data: Dictionary):
	"""Execute ability with cinematic 1.5 second presentation"""
	var ability_name = ability_data.get("ability_name", "")
	var ability_function = ability_data.get("ability_function", "")

	print("Executing CINEMATIC ability: ", ability_name)

	# Show card popup over ship
	show_ability_notification(ship, ability_name)

	# Validate ship still exists
	if not ship.has("sprite") or not is_instance_valid(ship.get("sprite")):
		print("Ability fizzled - source ship no longer valid")
		await get_tree().create_timer(1.5).timeout
		return

	# Get the target
	var target = targeting_system.select_target_for_unit(ship, "gamma")

	if not target or target.is_empty():
		print("Ability fizzled - no valid target")
		await get_tree().create_timer(1.5).timeout
		return

	# Execute the ability effect (this creates projectile in slow-mo)
	if ability_function.begins_with("execute_"):
		# Execute with cinematic flag
		var success = await CardEffects.execute_card_effect_cinematic(ability_function, ship, target, self)
		if success:
			print("Cinematic ability executed: ", ability_name)
		else:
			print("Cinematic ability failed: ", ability_name)

	# Total time is 1.5 seconds
	await get_tree().create_timer(1.5).timeout

func zoom_to_unit(unit: Dictionary, zoom_amount: float = 1.3):
	"""Zoom camera to focus on a specific unit"""
	if not unit.has("sprite") or not is_instance_valid(unit.get("sprite")):
		return

	var target_pos = unit["sprite"].global_position
	var current_pos = camera.global_position

	# Tween camera position and zoom
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	tween.tween_property(camera, "global_position", target_pos, 0.3)
	tween.tween_property(camera, "zoom", Vector2(zoom_amount, zoom_amount), 0.3)

	await tween.finished

func reset_camera_to_lane_view():
	"""Reset camera back to lane view after abilities"""
	if not is_zoomed or zoomed_lane_index < 0:
		return

	var lane = lanes[zoomed_lane_index]
	var lane_center_y = lane["y_position"]

	# Calculate the center position for the lane
	var viewport_size = get_viewport_rect().size
	var target_x = viewport_size.x / 2
	var target_y = lane_center_y
	var target_pos = Vector2(target_x, target_y)

	# Tween camera back to lane view
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	tween.tween_property(camera, "global_position", target_pos, 0.4)
	tween.tween_property(camera, "zoom", Vector2(1.0, 1.0), 0.4)

	await tween.finished

	print("Camera reset to lane view")

func release_stored_projectiles():
	"""Release all stored projectiles at full speed and apply effects"""
	print("Releasing ", stored_projectiles.size(), " stored projectiles at full speed")

	for projectile_data in stored_projectiles:
		var sprite = projectile_data.get("sprite")
		var end_pos = projectile_data.get("end_pos")
		var target = projectile_data.get("target")

		if not is_instance_valid(sprite):
			continue

		# Animate to target at full speed (0.3 seconds)
		var tween = create_tween()
		tween.tween_property(sprite, "position", end_pos, 0.3)

		# Wait for impact and apply effects
		tween.finished.connect(_on_stored_projectile_impact.bind(projectile_data))

	# Clear the stored projectiles array
	stored_projectiles.clear()

func _on_stored_projectile_impact(projectile_data: Dictionary):
	"""Handle impact of a released projectile"""
	var sprite = projectile_data.get("sprite")
	var target = projectile_data.get("target")
	var damage = projectile_data.get("damage", 0)

	# Remove projectile
	if is_instance_valid(sprite):
		sprite.queue_free()

	# Validate target still exists
	if not target.has("sprite") or not is_instance_valid(target.get("sprite")):
		print("Target no longer valid for projectile impact")
		return

	# Apply damage
	var damage_applied = CardEffects.apply_missile_damage(target, damage)

	# Flash target sprite
	if target.has("sprite") and is_instance_valid(target.get("sprite")):
		var target_sprite = target["sprite"]
		var original_modulate = target_sprite.modulate

		# Check if it's a burn effect (Incinerator Cannon)
		if projectile_data.has("burn_stacks"):
			target_sprite.modulate = Color(2, 1, 0.5, 1)  # Orange flash
		else:
			target_sprite.modulate = Color(2, 2, 2, 1)  # White flash

		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(target_sprite):
			target_sprite.modulate = original_modulate

	# Show damage number
	CardEffects.show_missile_damage_number(target, damage, damage_applied, self)

	# Apply burn if it's Incinerator Cannon
	if projectile_data.has("burn_stacks"):
		var burn_stacks = projectile_data.get("burn_stacks", 0)
		if status_effect_manager and status_effect_manager.has_method("apply_burn"):
			status_effect_manager.apply_burn(target, burn_stacks)
			print("Applied ", burn_stacks, " burn stacks from released projectile")

	# Apply AoE if it's Missile Lock
	if projectile_data.get("is_missile", false):
		CardEffects.apply_aoe_effect(target, damage, 1, "enemy", "damage", self)

	print("Projectile impact complete on ", target.get("type", "target"))

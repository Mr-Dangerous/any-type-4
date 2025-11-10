extends Node
class_name CombatShipManager

## CombatShipManager
## Handles ship spawning, positioning, movement, and lifecycle management

# References to parent combat scene
var combat_scene: Node2D = null

# Grid and Lane Data
var lanes: Array[Dictionary] = []
var lane_grids: Array = []

# Game Object References
var turrets: Array[Dictionary] = []  # Legacy array - deprecated
var enemy_turrets: Array[Dictionary] = []  # Legacy array - deprecated

# NEW: Turret Grid System (3 lanes × 5 rows = 15 turret positions)
var turret_grid: Array[Array] = []  # [lane_index][row_index] -> turret Dictionary or null
var enemy_turret_grid: Array[Array] = []  # [lane_index][row_index] -> turret Dictionary or null

# Mothership and Boss (single combat objects)
var mothership: Dictionary = {}
var enemy_boss: Dictionary = {}

# Ship repositioning state
var is_dragging_ship: bool = false
var dragged_ship: Dictionary = {}
var drag_start_pos: Vector2 = Vector2.ZERO
var ghost_ship_container: Control = null
var cell_overlays: Array[ColorRect] = []
var valid_move_cells: Array[Vector2i] = []

# Signals for cross-system communication
signal ship_deployed(ship: Dictionary)
signal ship_destroyed(ship: Dictionary)
signal ship_moved(ship: Dictionary, old_pos: Vector2i, new_pos: Vector2i)

func initialize(parent_scene: Node2D):
	"""Initialize the ship manager with reference to combat scene"""
	combat_scene = parent_scene
	initialize_lanes()
	initialize_turret_grids()

func initialize_lanes():
	"""Create lane structures and grid"""
	for i in range(CombatConstants.NUM_LANES):
		var lane = {
			"index": i,
			"y_position": CombatConstants.LANE_Y_START + (i * CombatConstants.LANE_SPACING),
			"units": []
		}
		lanes.append(lane)
		
		# Initialize grid for this lane
		var grid = []
		for row in range(CombatConstants.GRID_ROWS):
			var grid_row = []
			for col in range(CombatConstants.GRID_COLS):
				grid_row.append(null)
			grid.append(grid_row)
		lane_grids.append(grid)
		
		# Create visual lane markers
		create_lane_marker(i, lane["y_position"])

func create_lane_marker(lane_index: int, y_pos: float):
	"""Create visual representation of lane with grid"""
	var lane_width = CombatConstants.GRID_COLS * CombatConstants.CELL_SIZE
	var lane_height = CombatConstants.GRID_ROWS * CombatConstants.CELL_SIZE
	
	var lane_rect = ColorRect.new()
	lane_rect.name = "Lane_%d" % lane_index
	lane_rect.position = Vector2(CombatConstants.GRID_START_X, y_pos - lane_height / 2)
	lane_rect.size = Vector2(lane_width, lane_height)
	lane_rect.color = Color(0.2, 0.4, 0.8, 0.2)
	combat_scene.add_child(lane_rect)
	
	# Add border
	var border = ReferenceRect.new()
	border.border_color = Color(0.3, 0.5, 1.0, 0.9)
	border.border_width = 3.0
	border.size = lane_rect.size
	lane_rect.add_child(border)
	
	# Draw grid lines
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
	
	# Add column numbers
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

# ============================================================================
# GRID HELPER FUNCTIONS
# ============================================================================

func get_random_empty_cell(lane_index: int, columns: Array) -> Vector2i:
	"""Returns a random empty cell in specified columns"""
	var empty_cells = []
	
	for col in columns:
		for row in range(CombatConstants.GRID_ROWS):
			if lane_grids[lane_index][row][col] == null:
				empty_cells.append(Vector2i(row, col))
	
	if empty_cells.is_empty():
		return Vector2i(-1, -1)
	
	return empty_cells[randi() % empty_cells.size()]

func get_cell_world_position(lane_index: int, row: int, col: int) -> Vector2:
	"""Returns the center world position of a grid cell"""
	var lane_y = lanes[lane_index]["y_position"]
	var lane_height = CombatConstants.GRID_ROWS * CombatConstants.CELL_SIZE
	
	var x = CombatConstants.GRID_START_X + (col * CombatConstants.CELL_SIZE) + (CombatConstants.CELL_SIZE / 2)
	var y = (lane_y - lane_height / 2) + (row * CombatConstants.CELL_SIZE) + (CombatConstants.CELL_SIZE / 2)
	
	return Vector2(x, y)

func occupy_grid_cell(lane_index: int, row: int, col: int, unit: Dictionary):
	"""Mark a grid cell as occupied"""
	if row >= 0 and row < CombatConstants.GRID_ROWS and col >= 0 and col < CombatConstants.GRID_COLS:
		lane_grids[lane_index][row][col] = unit

func free_grid_cell(lane_index: int, row: int, col: int):
	"""Mark a grid cell as empty"""
	if row >= 0 and row < CombatConstants.GRID_ROWS and col >= 0 and col < CombatConstants.GRID_COLS:
		lane_grids[lane_index][row][col] = null

func get_valid_move_cells(unit: Dictionary) -> Array[Vector2i]:
	"""Calculate all valid cells a unit can move to based on movement_speed"""
	var valid_cells: Array[Vector2i] = []

	if not unit.has("grid_row") or not unit.has("grid_col") or not unit.has("lane_index"):
		return valid_cells

	var current_row = unit["grid_row"]
	var current_col = unit["grid_col"]
	var lane_index = unit["lane_index"]
	var movement_speed = unit.get("movement_speed", 0)

	for row in range(CombatConstants.GRID_ROWS):
		for col in range(CombatConstants.GRID_COLS):
			if row == current_row and col == current_col:
				continue

			var distance = abs(row - current_row) + abs(col - current_col)

			if distance <= movement_speed:
				if lane_grids[lane_index][row][col] == null:
					valid_cells.append(Vector2i(row, col))

	return valid_cells

# ============================================================================
# TURRET GRID SYSTEM
# ============================================================================

func initialize_turret_grids():
	"""Initialize 3x5 turret grids for player and enemy"""
	# Player turret grid
	for lane in range(CombatConstants.NUM_LANES):
		var row_array = []
		for row in range(CombatConstants.NUM_TURRET_ROWS):
			row_array.append(null)  # Start all positions empty
		turret_grid.append(row_array)

	# Enemy turret grid
	for lane in range(CombatConstants.NUM_LANES):
		var row_array = []
		for row in range(CombatConstants.NUM_TURRET_ROWS):
			row_array.append(null)  # Start all positions empty
		enemy_turret_grid.append(row_array)

	print("CombatShipManager: Turret grids initialized (3 lanes × 5 rows = 15 positions each)")

func get_turret_at_position(lane_index: int, row_index: int, faction: String) -> Dictionary:
	"""Get turret at a specific grid position"""
	if lane_index < 0 or lane_index >= CombatConstants.NUM_LANES:
		return {}
	if row_index < 0 or row_index >= CombatConstants.NUM_TURRET_ROWS:
		return {}

	var grid = turret_grid if faction == "player" else enemy_turret_grid
	var turret = grid[lane_index][row_index]

	return turret if turret != null else {}

func set_turret_at_position(lane_index: int, row_index: int, turret: Dictionary, faction: String):
	"""Place a turret at a specific grid position"""
	if lane_index < 0 or lane_index >= CombatConstants.NUM_LANES:
		return
	if row_index < 0 or row_index >= CombatConstants.NUM_TURRET_ROWS:
		return

	var grid = turret_grid if faction == "player" else enemy_turret_grid
	grid[lane_index][row_index] = turret

func get_turret_y_position(lane_index: int, row_index: int) -> float:
	"""Calculate Y position for turret based on lane and row"""
	var lane_y = lanes[lane_index]["y_position"]
	var lane_height = CombatConstants.GRID_ROWS * CombatConstants.CELL_SIZE
	var row_y_offset = (row_index * CombatConstants.CELL_SIZE) + (CombatConstants.CELL_SIZE / 2)

	return (lane_y - lane_height / 2) + row_y_offset

# ============================================================================
# SHIP DEPLOYMENT - Placeholder (to be fully implemented)
# ============================================================================

func deploy_ship(ship_type: String, lane_index: int, faction: String) -> Dictionary:
	"""Deploy a ship to a lane (placeholder)"""
	print("CombatShipManager: deploy_ship called for ", ship_type)
	# Full implementation to be added
	return {}

func destroy_ship(ship: Dictionary):
	"""Destroy a ship and cleanup"""
	print("CombatShipManager: destroy_ship called")
	ship_destroyed.emit(ship)
	# Full implementation to be added

# ============================================================================
# SHIP MOVEMENT
# ============================================================================

func move_ship_to_cell(unit: Dictionary, target_row: int, target_col: int):
	"""Move ship to a new grid cell with animation (placeholder)"""
	print("CombatShipManager: move_ship_to_cell called")
	# Full implementation to be added

func show_movement_overlay(unit: Dictionary):
	"""Show visual overlays for valid movement cells"""
	if not unit.has("lane_index"):
		return
	
	clear_movement_overlay()
	
	var lane_index = unit["lane_index"]
	valid_move_cells = get_valid_move_cells(unit)
	
	for row in range(CombatConstants.GRID_ROWS):
		for col in range(CombatConstants.GRID_COLS):
			var cell_pos = Vector2i(row, col)
			var is_valid = false
			
			for valid_cell in valid_move_cells:
				if valid_cell.x == row and valid_cell.y == col:
					is_valid = true
					break
			
			if row == unit["grid_row"] and col == unit["grid_col"]:
				continue
			
			var overlay = ColorRect.new()
			var world_pos = get_cell_world_position(lane_index, row, col)
			
			overlay.position = Vector2(world_pos.x - CombatConstants.CELL_SIZE / 2, world_pos.y - CombatConstants.CELL_SIZE / 2)
			overlay.size = Vector2(CombatConstants.CELL_SIZE, CombatConstants.CELL_SIZE)
			
			if is_valid:
				overlay.color = Color(0.0, 0.5, 1.0, 0.3)
			else:
				overlay.color = Color(0.4, 0.4, 0.4, 0.3)
			
			combat_scene.add_child(overlay)
			cell_overlays.append(overlay)

func clear_movement_overlay():
	"""Remove all cell overlay visuals"""
	for overlay in cell_overlays:
		overlay.queue_free()
	cell_overlays.clear()
	valid_move_cells.clear()

extends Node

## CombatGridManager Singleton
## Manages the 20×25 grid system for Combat_3
## Handles occupancy tracking, coordinate conversions, and grid operations

# Grid dimensions
const GRID_ROWS: int = 20
const GRID_COLS: int = 25
const CELL_SIZE: int = 72

# Grid origin (top-left corner in world coordinates)
var grid_origin: Vector2 = Vector2(50, 100)

# Grid occupancy tracking [row][col] -> unit reference
var grid: Array = []  # 2D array of dictionaries (or null if empty)

# Signals
signal cell_occupied(row: int, col: int, unit: Dictionary)
signal cell_freed(row: int, col: int)

func _ready():
	print("CombatGridManager: Initializing...")
	initialize_grid()

func initialize_grid():
	"""Initialize empty grid"""
	grid.clear()

	for row in range(GRID_ROWS):
		var row_array = []
		for col in range(GRID_COLS):
			row_array.append(null)  # Empty cell
		grid.append(row_array)

	print("CombatGridManager: Grid initialized (%d rows × %d cols)" % [GRID_ROWS, GRID_COLS])

# ============================================================================
# COORDINATE CONVERSIONS
# ============================================================================

func grid_to_world(row: int, col: int) -> Vector2:
	"""Convert grid coordinates to world position (center of cell)"""
	var x = grid_origin.x + col * CELL_SIZE + CELL_SIZE / 2
	var y = grid_origin.y + row * CELL_SIZE + CELL_SIZE / 2
	return Vector2(x, y)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	"""Convert world position to grid coordinates"""
	var col = int((world_pos.x - grid_origin.x) / CELL_SIZE)
	var row = int((world_pos.y - grid_origin.y) / CELL_SIZE)

	# Validate bounds
	if col < 0 or col >= GRID_COLS or row < 0 or row >= GRID_ROWS:
		return Vector2i(-1, -1)  # Invalid position

	return Vector2i(row, col)  # Note: Vector2i(row, col) for consistency

func is_valid_grid_pos(row: int, col: int) -> bool:
	"""Check if grid position is within bounds"""
	return row >= 0 and row < GRID_ROWS and col >= 0 and col < GRID_COLS

# ============================================================================
# OCCUPANCY MANAGEMENT
# ============================================================================

func is_cell_occupied(row: int, col: int) -> bool:
	"""Check if a cell is occupied by a unit"""
	if not is_valid_grid_pos(row, col):
		return true  # Out of bounds = occupied

	return grid[row][col] != null

func get_unit_at_cell(row: int, col: int):
	"""Get the unit at a specific cell (or null if empty)"""
	if not is_valid_grid_pos(row, col):
		return null

	return grid[row][col]

func occupy_cell(row: int, col: int, unit) -> bool:
	"""Occupy a cell with a unit. Returns true if successful."""
	if not is_valid_grid_pos(row, col):
		push_error("CombatGridManager: Cannot occupy cell (%d, %d) - out of bounds" % [row, col])
		return false

	if grid[row][col] != null:
		push_error("CombatGridManager: Cannot occupy cell (%d, %d) - already occupied" % [row, col])
		return false

	grid[row][col] = unit
	cell_occupied.emit(row, col, unit)
	return true

func free_cell(row: int, col: int) -> bool:
	"""Free a cell (remove unit). Returns true if successful."""
	if not is_valid_grid_pos(row, col):
		push_error("CombatGridManager: Cannot free cell (%d, %d) - out of bounds" % [row, col])
		return false

	if grid[row][col] == null:
		push_warning("CombatGridManager: Cell (%d, %d) is already empty" % [row, col])
		return false

	grid[row][col] = null
	cell_freed.emit(row, col)
	return true

func move_unit(from_row: int, from_col: int, to_row: int, to_col: int) -> bool:
	"""Move a unit from one cell to another. Returns true if successful."""
	# Validate source cell
	if not is_valid_grid_pos(from_row, from_col):
		push_error("CombatGridManager: Invalid source cell (%d, %d)" % [from_row, from_col])
		return false

	var unit = grid[from_row][from_col]
	if unit == null:
		push_error("CombatGridManager: No unit at source cell (%d, %d)" % [from_row, from_col])
		return false

	# Validate destination cell
	if not is_valid_grid_pos(to_row, to_col):
		push_error("CombatGridManager: Invalid destination cell (%d, %d)" % [to_row, to_col])
		return false

	if grid[to_row][to_col] != null:
		push_error("CombatGridManager: Destination cell (%d, %d) is occupied" % [to_row, to_col])
		return false

	# Move unit
	grid[from_row][from_col] = null
	grid[to_row][to_col] = unit

	# Update unit's grid_pos if it has that field
	if unit is Dictionary and unit.has("grid_pos"):
		unit["grid_pos"] = Vector2i(to_row, to_col)

	cell_freed.emit(from_row, from_col)
	cell_occupied.emit(to_row, to_col, unit)

	return true

# ============================================================================
# MOVEMENT VALIDATION
# ============================================================================

func is_valid_tactical_move(from_row: int, from_col: int, to_row: int, to_col: int, move_speed: int) -> bool:
	"""Check if a move is valid during tactical phase"""
	# Check bounds
	if not is_valid_grid_pos(from_row, from_col) or not is_valid_grid_pos(to_row, to_col):
		return false

	# Calculate Manhattan distance
	var distance = abs(to_row - from_row) + abs(to_col - from_col)
	if distance > move_speed:
		return false

	# Cannot move forward (right) during tactical phase
	if to_col > from_col:
		return false

	# Destination must be empty
	if is_cell_occupied(to_row, to_col):
		return false

	return true

func get_cells_in_range(center_row: int, center_col: int, range_cells: int) -> Array:
	"""Get all cells within Manhattan distance of center"""
	var cells = []

	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var distance = abs(row - center_row) + abs(col - center_col)
			if distance <= range_cells:
				cells.append(Vector2i(row, col))

	return cells

# ============================================================================
# UTILITY
# ============================================================================

func clear_grid():
	"""Clear all units from grid"""
	initialize_grid()
	print("CombatGridManager: Grid cleared")

func get_occupied_cells() -> Array:
	"""Get list of all occupied cells as Vector2i(row, col)"""
	var occupied = []

	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			if grid[row][col] != null:
				occupied.append(Vector2i(row, col))

	return occupied

func print_grid_state():
	"""Debug: Print grid occupancy state"""
	print("=== GRID STATE ===")
	for row in range(GRID_ROWS):
		var row_str = "Row %2d: " % row
		for col in range(GRID_COLS):
			row_str += "X" if grid[row][col] != null else "."
		print(row_str)
	print("==================")

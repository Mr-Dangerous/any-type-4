extends Node
class_name CombatEnemyManager

## CombatEnemyManager
## Handles enemy spawning and movement for combat turns
##
## TURN TIMING FLOW:
## 1. Turn Start (return_to_tactical_phase)
##    - Reset movement flags
##    - IF auto_spawn enabled:
##      a. Move all existing enemies forward
##      b. Spawn new wave at column 15
## 2. Tactical Phase (player draws cards, selects lane)
## 3. Lane Transition (proceed_to_lane_transition)
##    - Zoom to lane
##    - Enter pre-combat phase
## 4. Pre-combat Phase (auto-queue abilities, user confirms)
## 5. Combat Phase (5 seconds of combat)
## 6. Repeat steps 3-5 for remaining lanes
## 7. Turn End → Back to step 1

# Reference to Combat_2 scene
var combat_scene: Node2D = null

func initialize(parent_combat: Node2D):
	"""Initialize with reference to Combat_2 scene"""
	combat_scene = parent_combat
	print("CombatEnemyManager: Initialized")

# ============================================================================
# TURN SPAWN CYCLE
# ============================================================================

func process_turn_spawn_cycle():
	"""
	Main function called at turn start.
	TIMING: After movement flags reset, before drawing cards.

	Flow:
	1. Move all existing enemies forward
	2. Spawn new wave in column 15 (all lanes)
	3. Return control to Combat_2 for card draw and tactical phase
	"""
	if not combat_scene:
		print("ERROR: CombatEnemyManager not initialized")
		return

	print("=== ENEMY TURN SPAWN CYCLE START ===")

	# Step 1: Move all existing enemies forward
	move_all_enemies_forward()

	# Step 2: Spawn new wave at column 15
	spawn_new_wave_all_lanes()

	print("=== ENEMY TURN SPAWN CYCLE COMPLETE ===")

# ============================================================================
# ENEMY MOVEMENT
# ============================================================================

func move_all_enemies_forward():
	"""
	Move all enemies in all lanes forward toward player.
	Extracted from Combat_2.enemy_pathfinding_alpha()
	"""
	print("CombatEnemyManager: Moving all enemies forward")

	var lanes = combat_scene.lanes
	var total_moved = 0

	for lane_index in range(lanes.size()):
		var enemies_in_lane = get_enemies_in_lane(lane_index)

		for enemy in enemies_in_lane:
			if move_enemy_forward(enemy, lane_index):
				total_moved += 1

	print("CombatEnemyManager: Moved ", total_moved, " enemies")

func move_enemy_forward(enemy: Dictionary, lane_index: int) -> bool:
	"""
	Move a single enemy forward by its movement_speed.
	Returns true if enemy moved, false if blocked or already moved.
	"""
	# Skip if already moved this turn
	if enemy.get("has_moved_this_turn", false):
		return false

	# Get current position
	var current_row = enemy.get("grid_row", -1)
	var current_col = enemy.get("grid_col", -1)

	if current_row == -1 or current_col == -1:
		return false

	# Get movement speed
	var movement_speed = enemy.get("movement_speed", 2)

	# Calculate target column (move left toward player)
	var target_col = max(0, current_col - movement_speed)

	# Check each column for blocking units (player ships)
	var lane_grids = combat_scene.lane_grids
	var furthest_valid_col = current_col

	for check_col in range(current_col - 1, target_col - 1, -1):
		if check_col < 0:
			break

		var cell_contents = lane_grids[lane_index][current_row][check_col]
		if cell_contents != null:
			# Check if blocking unit is a player ship
			if cell_contents.get("faction") == "player":
				# Blocked by player - can't move further
				break

		furthest_valid_col = check_col

	# Move enemy if we found a valid position
	if furthest_valid_col != current_col:
		combat_scene.move_ship_to_cell(enemy, Vector2i(current_row, furthest_valid_col))
		return true

	return false

func get_enemies_in_lane(lane_index: int) -> Array:
	"""Get all enemy units in a specific lane"""
	var enemies = []
	var lanes = combat_scene.lanes

	if lane_index < 0 or lane_index >= lanes.size():
		return enemies

	for unit in lanes[lane_index]["units"]:
		if unit.get("is_enemy", false):
			enemies.append(unit)

	return enemies

# ============================================================================
# ENEMY SPAWNING
# ============================================================================

func spawn_new_wave_all_lanes():
	"""
	Spawn new wave of enemies at column 15 in all lanes.

	Spawn rules:
	- 2 mooks per lane (guaranteed)
	- 1 elite per lane (30% chance)
	"""
	print("CombatEnemyManager: Spawning new wave at column 15")

	var total_spawned = 0

	for lane_index in range(3):  # 3 lanes (0, 1, 2)
		var spawned = spawn_turn_wave(lane_index)
		total_spawned += spawned

	print("CombatEnemyManager: Spawned ", total_spawned, " total enemies")

func spawn_turn_wave(lane_index: int) -> int:
	"""
	Spawn turn wave for a single lane.
	Returns number of enemies spawned.

	Spawns:
	- 2 mooks at column 15
	- 30% chance for 1 elite at column 15
	"""
	var spawned_count = 0
	var spawn_column = 15

	# Get available spawn rows in column 15
	var available_rows = get_available_spawn_rows(lane_index, spawn_column)

	if available_rows.is_empty():
		print("WARNING: No available spawn positions in lane ", lane_index, " column ", spawn_column)
		return 0

	# Spawn mook #1
	if available_rows.size() >= 1:
		var row = available_rows[0]
		if spawn_enemy_at_position("mook", lane_index, row, spawn_column):
			spawned_count += 1
			available_rows.remove_at(0)  # Remove used row

	# Spawn mook #2
	if available_rows.size() >= 1:
		var row = available_rows[0]
		if spawn_enemy_at_position("mook", lane_index, row, spawn_column):
			spawned_count += 1
			available_rows.remove_at(0)  # Remove used row

	# 30% chance to spawn elite
	var elite_roll = randf()
	if elite_roll < 0.3 and available_rows.size() >= 1:
		var row = available_rows[0]
		if spawn_enemy_at_position("elite", lane_index, row, spawn_column):
			spawned_count += 1
			print("CombatEnemyManager: Elite spawned in lane ", lane_index, " (roll: ", elite_roll, ")")

	return spawned_count

func spawn_enemy_at_position(enemy_type: String, lane_index: int, row: int, col: int) -> bool:
	"""
	Spawn an enemy at a specific grid position.
	Uses MODERN spawning logic from Combat_2.deploy_enemy_to_lane().

	Returns true if spawn succeeded, false if failed.
	"""
	# Validate lane
	if lane_index < 0 or lane_index >= combat_scene.lanes.size():
		print("ERROR: Invalid lane_index: ", lane_index)
		return false

	# Get enemy data from database
	var db_enemy_data = DataManager.get_ship_data(enemy_type)
	if db_enemy_data.is_empty():
		print("ERROR: Enemy type not found: ", enemy_type)
		return false

	# Check if cell is occupied
	var lane_grids = combat_scene.lane_grids
	if lane_grids[lane_index][row][col] != null:
		print("WARNING: Cell occupied at lane ", lane_index, " (", row, ",", col, ")")
		return false

	# Extract enemy properties from database
	var enemy_texture: Texture2D = load(db_enemy_data["sprite_path"])
	var enemy_size: int = db_enemy_data["size"]

	# Get target position at center of cell
	var cell_center = combat_scene.get_cell_world_position(lane_index, row, col)
	var x_pos = cell_center.x - (enemy_size / 2)
	var target_y = cell_center.y - (enemy_size / 2)

	# Create enemy sprite container
	var enemy_container = Control.new()
	enemy_container.name = enemy_type + "_enemy_" + str(Time.get_ticks_msec())
	enemy_container.position = Vector2(x_pos, target_y)
	combat_scene.add_child(enemy_container)

	# Create sprite with MODERN texture settings
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

	# Create enemy data dictionary (MODERN pattern with all fields)
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
		"grid_row": row,
		"grid_col": col,
		"lane_index": lane_index,

		# Movement
		"movement_speed": db_enemy_data.get("movement_speed", 2),
		"has_moved_this_turn": false,

		# Combat stats (duplicate from database)
		"stats": db_enemy_data["stats"].duplicate(),
		"current_armor": db_enemy_data["stats"]["armor"],
		"current_shield": db_enemy_data["stats"]["shield"],
		"current_overshield": 0,  # Temporary shields, dissipates after lane 3
		"current_energy": db_enemy_data["stats"].get("starting_energy", 0),

		# Projectile data
		"projectile_sprite": db_enemy_data.get("projectile_sprite", "res://assets/Effects/laser_light/s_laser_light_001.png"),
		"projectile_size": db_enemy_data.get("projectile_size", 6),

		# Ability data
		"ability_function": db_enemy_data.get("ability_function", ""),
		"ability_name": db_enemy_data.get("ability", ""),
		"ability_description": db_enemy_data.get("ability_description", ""),

		# Ability stack/queue system
		"ability_stack": [],  # Queue of abilities to execute
		"is_processing_abilities": false,  # True while executing abilities from stack

		# Status effects and elemental damage
		"status_effects": [],  # Array of active status effects (burn, freeze, etc.)
		"damage_types": []  # Array of elemental damage types (fire, ice, acid, etc.)
	}

	# Mark grid cell as occupied
	combat_scene.occupy_grid_cell(lane_index, row, col, enemy_data)

	# Add to lane data
	combat_scene.lanes[lane_index]["units"].append(enemy_data)

	# Create health bar
	combat_scene.health_system.create_health_bar(enemy_container, enemy_size, enemy_data["current_shield"], enemy_data["current_armor"])

	# Initialize energy bar
	combat_scene.health_system.update_energy_bar(enemy_data)

	# Add hover detection for tooltip
	combat_scene.add_ship_hover_detection(enemy_container, enemy_data)

	print("CombatEnemyManager: Spawned ", enemy_type, " at lane ", lane_index, " (", row, ",", col, ") | Size: ", enemy_size, " | Armor: ", enemy_data["current_armor"], " | Shield: ", enemy_data["current_shield"])
	return true

func get_available_spawn_rows(lane_index: int, col: int) -> Array[int]:
	"""
	Get list of available (empty) rows in a specific column.
	Returns array of row indices [0-4] that are not occupied.
	"""
	var available: Array[int] = []
	var lane_grids = combat_scene.lane_grids

	for row in range(5):  # GRID_ROWS = 5
		if lane_grids[lane_index][row][col] == null:
			available.append(row)

	return available

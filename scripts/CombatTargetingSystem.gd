extends Node
class_name CombatTargetingSystem

## CombatTargetingSystem  
## Handles target selection and assignment for combat units

# Reference to ship manager for grid access
var ship_manager: CombatShipManager = null

# Targeting configuration
var player_targeting_mode: String = "gamma"  # Row-based combat is now default
var enemy_targeting_mode: String = "gamma"  # Row-based combat is now default

# Manual targeting state
var selected_attacker: Dictionary = {}
var selected_target: Dictionary = {}

# Signals
signal target_selected(attacker: Dictionary, target: Dictionary)
signal attacker_selected(attacker: Dictionary)

func initialize(manager: CombatShipManager):
	"""Initialize targeting system with ship manager reference"""
	ship_manager = manager

# ============================================================================
# TARGET SELECTION
# ============================================================================

func select_target_for_unit(unit: Dictionary, targeting_mode: String = "alpha") -> Dictionary:
	"""Select best target for a unit based on targeting algorithm"""
	match targeting_mode:
		"alpha":
			return targeting_function_alpha(unit)
		"gamma":
			return targeting_function_gamma(unit)
		"random":
			return targeting_function_random(unit)
		_:
			return targeting_function_gamma(unit)  # Gamma is now default

func targeting_function_alpha(attacker: Dictionary) -> Dictionary:
	"""Main strategic targeting with row-based priority"""
	if not attacker.has("lane_index") or not attacker.has("faction"):
		return {}
	
	var lane_index = attacker["lane_index"]
	var attacker_faction = attacker["faction"]
	var target_faction = "enemy" if attacker_faction == "player" else "player"
	
	# Priority 1: Closest in same row
	var target = find_closest_in_row(attacker, target_faction)
	if not target.is_empty():
		return target
	
	# Priority 2: Turrets/Spawners  
	target = find_targetable_turret(attacker, target_faction)
	if not target.is_empty():
		return target
	
	# Priority 3: Closest in adjacent rows
	target = find_closest_in_adjacent_rows(attacker, target_faction)
	if not target.is_empty():
		return target
	
	# Priority 4: Any in lane
	target = find_any_in_lane(attacker, target_faction)
	if not target.is_empty():
		return target
	
	return {}

func targeting_function_random(attacker: Dictionary) -> Dictionary:
	"""Random target selection"""
	if not attacker.has("lane_index") or not attacker.has("faction"):
		return {}

	var lane_index = attacker["lane_index"]
	var attacker_faction = attacker["faction"]
	var target_faction = "enemy" if attacker_faction == "player" else "player"

	# Get all possible targets in lane
	var possible_targets = []

	if ship_manager and ship_manager.lanes.size() > lane_index:
		for unit in ship_manager.lanes[lane_index]["units"]:
			if unit.get("faction", "") == target_faction:
				possible_targets.append(unit)

	# Add turrets
	var turret_list = ship_manager.enemy_turrets if target_faction == "enemy" else ship_manager.turrets
	for turret in turret_list:
		if turret.get("lane_index", -1) == lane_index:
			possible_targets.append(turret)

	if possible_targets.is_empty():
		return {}

	return possible_targets[randi() % possible_targets.size()]

func targeting_function_gamma(attacker: Dictionary) -> Dictionary:
	"""Row-locked targeting - ships only fight in their assigned row
	Priority: Ship in same row → Turret in same row → Mothership/Boss → Idle"""
	if not attacker.has("lane_index") or not attacker.has("faction") or not attacker.has("grid_row"):
		return {}

	var attacker_faction = attacker["faction"]
	var target_faction = "enemy" if attacker_faction == "player" else "player"

	# Priority 1: Closest ship in SAME ROW only
	var target = find_closest_in_row(attacker, target_faction)
	if not target.is_empty():
		return target

	# Priority 2: Turret in SAME ROW
	target = find_turret_in_row(attacker, target_faction)
	if not target.is_empty():
		return target

	# Priority 3: Mothership (player) or Boss (enemy)
	target = find_mothership_or_boss(attacker, target_faction)
	if not target.is_empty():
		return target

	# Priority 4: No valid target - ship goes idle
	return {}

# ============================================================================
# TARGET SEARCH HELPERS
# ============================================================================

func find_closest_in_row(attacker: Dictionary, target_faction: String) -> Dictionary:
	"""Find closest enemy in same grid row"""
	if not attacker.has("grid_row") or not attacker.has("lane_index"):
		return {}
	
	var attacker_row = attacker["grid_row"]
	var attacker_col = attacker.get("grid_col", -1)
	var lane_index = attacker["lane_index"]
	
	var closest_target = {}
	var closest_distance = 999999
	
	if ship_manager and ship_manager.lanes.size() > lane_index:
		for unit in ship_manager.lanes[lane_index]["units"]:
			if unit.get("faction", "") != target_faction:
				continue
			
			if unit.get("grid_row", -1) == attacker_row:
				var distance = abs(unit.get("grid_col", -1) - attacker_col)
				if distance < closest_distance:
					closest_distance = distance
					closest_target = unit
	
	return closest_target

func find_closest_in_adjacent_rows(attacker: Dictionary, target_faction: String) -> Dictionary:
	"""Find closest enemy in adjacent rows (±1)"""
	if not attacker.has("grid_row") or not attacker.has("lane_index"):
		return {}
	
	var attacker_row = attacker["grid_row"]
	var attacker_col = attacker.get("grid_col", -1)
	var lane_index = attacker["lane_index"]
	
	var closest_target = {}
	var closest_distance = 999999
	
	if ship_manager and ship_manager.lanes.size() > lane_index:
		for unit in ship_manager.lanes[lane_index]["units"]:
			if unit.get("faction", "") != target_faction:
				continue
			
			var row_diff = abs(unit.get("grid_row", -1) - attacker_row)
			if row_diff == 1:
				var distance = abs(unit.get("grid_col", -1) - attacker_col) + row_diff
				if distance < closest_distance:
					closest_distance = distance
					closest_target = unit
	
	return closest_target

func find_targetable_turret(attacker: Dictionary, target_faction: String) -> Dictionary:
	"""Identify turrets that can be targeted"""
	if not attacker.has("lane_index"):
		return {}
	
	var lane_index = attacker["lane_index"]
	var turret_list = ship_manager.enemy_turrets if target_faction == "enemy" else ship_manager.turrets
	
	for turret in turret_list:
		if turret.get("lane_index", -1) == lane_index:
			return turret
	
	return {}

func find_any_in_lane(attacker: Dictionary, target_faction: String) -> Dictionary:
	"""Fallback: find any enemy in lane"""
	if not attacker.has("lane_index"):
		return {}

	var lane_index = attacker["lane_index"]

	if ship_manager and ship_manager.lanes.size() > lane_index:
		for unit in ship_manager.lanes[lane_index]["units"]:
			if unit.get("faction", "") == target_faction:
				return unit

	return {}

func find_turret_in_row(attacker: Dictionary, target_faction: String) -> Dictionary:
	"""Find turret in the same row as attacker (for gamma targeting)"""
	if not attacker.has("lane_index") or not attacker.has("grid_row"):
		return {}

	var lane_index = attacker["lane_index"]
	var row_index = attacker["grid_row"]

	if not ship_manager:
		return {}

	# Get turret from grid at this lane/row position
	var turret = ship_manager.get_turret_at_position(lane_index, row_index, target_faction)

	# Check if turret is enabled
	if not turret.is_empty() and turret.get("enabled", false):
		return turret

	return {}

func find_mothership_or_boss(attacker: Dictionary, target_faction: String) -> Dictionary:
	"""Find mothership (if targeting player) or boss (if targeting enemy)"""
	if not ship_manager:
		return {}

	var target_object = {}

	if target_faction == "player":
		# Attacker is enemy, target player mothership
		target_object = ship_manager.mothership
	else:
		# Attacker is player, target enemy boss
		target_object = ship_manager.enemy_boss

	# Validate target exists and is alive
	if not target_object.is_empty():
		var total_health = target_object.get("current_armor", 0) + target_object.get("current_shield", 0)
		if total_health > 0:
			return target_object

	return {}

# ============================================================================
# TARGET REASSIGNMENT
# ============================================================================

func reassign_all_targets():
	"""Reassign targets for all units"""
	if not ship_manager:
		return
	
	for lane in ship_manager.lanes:
		for unit in lane["units"]:
			if unit.has("faction"):
				var mode = player_targeting_mode if unit["faction"] == "player" else enemy_targeting_mode
				var new_target = select_target_for_unit(unit, mode)
				unit["target"] = new_target

func clear_targets_referencing_ship(destroyed_ship: Dictionary):
	"""Clear target references for units targeting a destroyed ship"""
	if not ship_manager:
		return
	
	for lane in ship_manager.lanes:
		for unit in lane["units"]:
			if unit.has("target") and unit["target"] == destroyed_ship:
				unit["target"] = {}

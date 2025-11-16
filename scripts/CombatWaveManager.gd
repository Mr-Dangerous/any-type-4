extends Node

## CombatWaveManager Singleton
## Manages enemy wave spawning and scenario progression for Combat_3
## Loads enemy_waves.csv and scenarios.csv

# File paths
const ENEMY_WAVES_PATH = "res://card_database/enemy_waves.csv"
const SCENARIOS_PATH = "res://card_database/scenarios.csv"

# Data storage
var enemy_waves: Dictionary = {}  # {wave_name: [enemy_ship_ids]}
var scenarios: Dictionary = {}  # {scenario_name: scenario_data}

# Current scenario tracking
var current_scenario_name: String = ""
var current_wave_index: int = 0  # 0-based index into scenario's wave list
var total_waves: int = 0

func _ready():
	print("CombatWaveManager: Initializing...")
	load_enemy_waves()
	load_scenarios()
	print("CombatWaveManager: Ready")

# ============================================================================
# CSV LOADING
# ============================================================================

func load_enemy_waves() -> bool:
	"""Load enemy wave data from enemy_waves.csv"""
	print("CombatWaveManager: Loading enemy waves from: ", ENEMY_WAVES_PATH)

	var file = FileAccess.open(ENEMY_WAVES_PATH, FileAccess.READ)
	if file == null:
		push_error("CombatWaveManager: Could not open enemy waves: " + ENEMY_WAVES_PATH)
		return false

	# Read header
	var header = file.get_csv_line()
	if header.is_empty():
		push_error("CombatWaveManager: Enemy waves CSV is empty")
		file.close()
		return false

	# Parse rows
	var row_count = 0
	while not file.eof_reached():
		var row = file.get_csv_line()
		if row.is_empty() or (row.size() == 1 and row[0] == ""):
			continue

		var wave_name = row[0]
		if wave_name == "":
			continue

		# Collect all enemy ship_ids from spawn_1 to spawn_12 (columns 1-12)
		var enemies = []
		for i in range(1, row.size()):
			var enemy_id = row[i].strip_edges()
			if enemy_id != "":
				enemies.append(enemy_id)

		enemy_waves[wave_name] = enemies
		row_count += 1

	file.close()
	print("CombatWaveManager: Loaded ", row_count, " enemy waves")
	return true

func load_scenarios() -> bool:
	"""Load scenario data from scenarios.csv"""
	print("CombatWaveManager: Loading scenarios from: ", SCENARIOS_PATH)

	var file = FileAccess.open(SCENARIOS_PATH, FileAccess.READ)
	if file == null:
		push_error("CombatWaveManager: Could not open scenarios: " + SCENARIOS_PATH)
		return false

	# Read header
	var header = file.get_csv_line()
	if header.is_empty():
		push_error("CombatWaveManager: Scenarios CSV is empty")
		file.close()
		return false

	# Parse rows
	var row_count = 0
	while not file.eof_reached():
		var row = file.get_csv_line()
		if row.is_empty() or (row.size() == 1 and row[0] == ""):
			continue

		var scenario_name = row[0]
		if scenario_name == "":
			continue

		# Parse scenario data
		var scenario_data = {
			"scenario_name": scenario_name,
			"number_of_waves": int(row[1]) if row.size() > 1 else 0,
			"scenario_width": int(row[2]) if row.size() > 2 else 25,  # Default to full grid width
			"wave_width": int(row[3]) if row.size() > 3 else 20,  # Default to full grid height
			"boss_loop": row[4].to_lower() == "true" if row.size() > 4 else false,
			"boss_wave": row[5] if row.size() > 5 else "",
			"waves": []  # List of wave names
		}

		# Collect wave names from wave_1 to wave_8 (columns 6-13)
		for i in range(6, min(row.size(), 14)):
			var wave_name = row[i].strip_edges()
			if wave_name != "":
				scenario_data["waves"].append(wave_name)

		scenarios[scenario_name] = scenario_data
		row_count += 1

	file.close()
	print("CombatWaveManager: Loaded ", row_count, " scenarios")
	return true

# ============================================================================
# SCENARIO MANAGEMENT
# ============================================================================

func load_scenario(scenario_name: String) -> bool:
	"""Load a scenario and prepare for wave spawning"""
	if not scenarios.has(scenario_name):
		push_error("CombatWaveManager: Scenario not found: " + scenario_name)
		return false

	current_scenario_name = scenario_name
	current_wave_index = 0

	var scenario = scenarios[scenario_name]
	total_waves = scenario["number_of_waves"]

	print("CombatWaveManager: Loaded scenario '", scenario_name, "' with ", total_waves, " waves")
	return true

func get_current_wave_enemies() -> Array:
	"""Get the list of enemy ship_ids for the current wave"""
	if current_scenario_name == "":
		push_error("CombatWaveManager: No scenario loaded")
		return []

	var scenario = scenarios[current_scenario_name]
	if current_wave_index >= scenario["waves"].size():
		push_warning("CombatWaveManager: Wave index out of bounds")
		return []

	var wave_name = scenario["waves"][current_wave_index]
	if not enemy_waves.has(wave_name):
		push_error("CombatWaveManager: Wave not found: " + wave_name)
		return []

	print("CombatWaveManager: Getting enemies for wave ", current_wave_index + 1, " (", wave_name, ")")
	return enemy_waves[wave_name]

func advance_wave() -> bool:
	"""Advance to the next wave. Returns true if successful, false if no more waves."""
	if current_scenario_name == "":
		push_error("CombatWaveManager: No scenario loaded")
		return false

	current_wave_index += 1

	var scenario = scenarios[current_scenario_name]
	if current_wave_index >= scenario["waves"].size():
		print("CombatWaveManager: All waves completed")
		return false

	print("CombatWaveManager: Advanced to wave ", current_wave_index + 1, "/", total_waves)
	return true

func get_current_wave_number() -> int:
	"""Get the current wave number (1-indexed for display)"""
	return current_wave_index + 1

func get_total_waves() -> int:
	"""Get total number of waves in current scenario"""
	return total_waves

func is_scenario_complete() -> bool:
	"""Check if all waves in the scenario are complete"""
	if current_scenario_name == "":
		return false

	var scenario = scenarios[current_scenario_name]
	return current_wave_index >= scenario["waves"].size()

func get_wave_width() -> int:
	"""Get the wave_width for the current scenario"""
	if current_scenario_name == "":
		push_warning("CombatWaveManager: No scenario loaded")
		return 20  # Default to full grid height

	var scenario = scenarios[current_scenario_name]
	return scenario.get("wave_width", 20)

func get_scenario_width() -> int:
	"""Get the scenario_width (battlefield width) for the current scenario"""
	if current_scenario_name == "":
		push_warning("CombatWaveManager: No scenario loaded")
		return 25  # Default to full grid width

	var scenario = scenarios[current_scenario_name]
	return scenario.get("scenario_width", 25)

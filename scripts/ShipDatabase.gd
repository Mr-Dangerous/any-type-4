extends Node

# Ship Database Singleton
# Loads and manages ship data from ship_database.csv

const SHIP_DATABASE_PATH = "res://card_database/ship_database.csv"

# Cached ship data
var ships: Dictionary = {}  # ship_id -> ship_data
var ships_loaded: bool = false

func _ready():
	load_ship_database()

func load_ship_database() -> bool:
	print("Loading ship database from: ", SHIP_DATABASE_PATH)

	var file = FileAccess.open(SHIP_DATABASE_PATH, FileAccess.READ)
	if file == null:
		print("ERROR: Could not open ship database file: ", SHIP_DATABASE_PATH)
		print("Error code: ", FileAccess.get_open_error())
		return false

	# Read header line
	var header = file.get_csv_line()
	if header.size() == 0:
		print("ERROR: Ship database is empty")
		file.close()
		return false

	print("CSV Header: ", header)

	# Expected columns
	var expected_columns = [
		"ship_id", "display_name", "faction", "sprite_path", "projectile_sprite",
		"size", "deploy_speed", "armor", "shield", "reinforced_armor",
		"evasion", "accuracy", "attack_speed", "num_attacks", "amplitude",
		"frequency", "size_class", "description", "enabled"
	]

	# Validate header
	for col in expected_columns:
		if col not in header:
			print("WARNING: Missing expected column: ", col)

	# Parse data lines
	var ship_count = 0
	while not file.eof_reached():
		var line = file.get_csv_line()

		# Skip empty lines
		if line.size() == 0 or (line.size() == 1 and line[0] == ""):
			continue

		# Parse ship data
		var ship_data = parse_ship_line(header, line)
		if ship_data.is_empty():
			continue

		# Store ship data
		var ship_id = ship_data["ship_id"]
		ships[ship_id] = ship_data
		ship_count += 1

		print("Loaded ship: ", ship_id, " (", ship_data["display_name"], ")")

	file.close()

	print("Ship database loaded successfully: ", ship_count, " ships")
	ships_loaded = true
	return true

func parse_ship_line(header: PackedStringArray, line: PackedStringArray) -> Dictionary:
	# Parse a CSV line into a ship data dictionary
	if line.size() != header.size():
		print("WARNING: Line has ", line.size(), " columns, expected ", header.size())
		return {}

	# Create ship data dictionary
	var ship_data = {}

	for i in range(header.size()):
		var column_name = header[i]
		var value = line[i]

		# Parse value based on column type
		match column_name:
			"ship_id", "display_name", "faction", "sprite_path", "projectile_sprite", "size_class", "description":
				ship_data[column_name] = value

			"size", "armor", "shield", "reinforced_armor", "evasion", "damage", "accuracy", "num_attacks", "amplitude", "frequency":
				ship_data[column_name] = int(value) if value != "" else 0

			"deploy_speed", "attack_speed":
				ship_data[column_name] = float(value) if value != "" else 0.0

			"enabled":
				ship_data[column_name] = value.to_lower() == "true"

	# Organize stats into nested dictionary
	if ship_data.has("armor"):
		ship_data["stats"] = {
			"armor": ship_data.get("armor", 0),
			"shield": ship_data.get("shield", 0),
			"reinforced_armor": ship_data.get("reinforced_armor", 0),
			"evasion": ship_data.get("evasion", 0),
			"damage": ship_data.get("damage", 0),
			"accuracy": ship_data.get("accuracy", 0),
			"attack_speed": ship_data.get("attack_speed", 1.0),
			"num_attacks": ship_data.get("num_attacks", 1),
			"amplitude": ship_data.get("amplitude", 0),
			"frequency": ship_data.get("frequency", 0)
		}

	return ship_data

func get_ship_data(ship_id: String) -> Dictionary:
	# Get ship data by ship_id
	if not ships_loaded:
		print("WARNING: Ship database not loaded yet")
		return {}

	if not ships.has(ship_id):
		print("WARNING: Ship not found in database: ", ship_id)
		return {}

	return ships[ship_id]

func get_all_ships() -> Array[Dictionary]:
	# Get all ship data
	var all_ships: Array[Dictionary] = []
	for ship_id in ships.keys():
		all_ships.append(ships[ship_id])
	return all_ships

func get_ships_by_faction(faction: String) -> Array[Dictionary]:
	# Get all ships of a specific faction ("player" or "enemy")
	var faction_ships: Array[Dictionary] = []
	for ship_id in ships.keys():
		var ship_data = ships[ship_id]
		if ship_data.get("faction", "") == faction and ship_data.get("enabled", true):
			faction_ships.append(ship_data)
	return faction_ships

func get_enabled_ships() -> Array[Dictionary]:
	# Get all enabled ships
	var enabled_ships: Array[Dictionary] = []
	for ship_id in ships.keys():
		var ship_data = ships[ship_id]
		if ship_data.get("enabled", true):
			enabled_ships.append(ship_data)
	return enabled_ships

func ship_exists(ship_id: String) -> bool:
	# Check if a ship exists in the database
	return ships.has(ship_id)

func is_ship_enabled(ship_id: String) -> bool:
	# Check if a ship is enabled
	if not ships.has(ship_id):
		return false
	return ships[ship_id].get("enabled", true)

extends Node

## DataManager Singleton
## Centralized CSV loading and data management for the entire game
## Handles all database files and provides clean access interfaces

# CSV file paths
const SHIP_DATABASE_PATH = "res://card_database/ship_database.csv"
const CARD_DATABASE_PATH = "res://card_database/any_type_4_card_database.csv"
const STARTING_DECK_PATH = "res://card_database/starting_deck.csv"
const STAR_NAMES_PATH = "res://card_database/star_names.csv"
const ENEMIES_PATH = "res://card_database/enemies.csv"

# Cached data
var ships: Dictionary = {}  # ship_id -> ship_data
var cards: Dictionary = {}  # card_id -> card_data
var star_names: Array[String] = []
var enemies: Dictionary = {}  # enemy_id -> enemy_data

# Loading status flags
var ships_loaded: bool = false
var cards_loaded: bool = false
var star_names_loaded: bool = false
var enemies_loaded: bool = false

func _ready():
	print("DataManager: Initializing...")
	load_all_databases()

func load_all_databases():
	"""Load all CSV databases on startup"""
	load_ship_database()
	load_card_database()
	load_star_names()
	# Note: enemies.csv is deprecated, ships are in ship_database.csv
	print("DataManager: All databases loaded")

# ============================================================================
# SHIP DATABASE
# ============================================================================

func load_ship_database() -> bool:
	"""Load ship data from ship_database.csv"""
	print("DataManager: Loading ship database from: ", SHIP_DATABASE_PATH)

	var file = FileAccess.open(SHIP_DATABASE_PATH, FileAccess.READ)
	if file == null:
		push_error("DataManager: Could not open ship database: " + SHIP_DATABASE_PATH)
		return false

	# Read header
	var header = file.get_csv_line()
	if header.is_empty():
		push_error("DataManager: Ship database is empty")
		file.close()
		return false

	# Parse data lines
	var ship_count = 0
	while not file.eof_reached():
		var line = file.get_csv_line()

		# Skip empty lines
		if line.is_empty() or (line.size() == 1 and line[0] == ""):
			continue

		# Parse ship data
		var ship_data = parse_ship_data(header, line)
		if not ship_data.is_empty():
			var ship_id = ship_data.get("ship_id", "")
			if ship_id != "":
				ships[ship_id] = ship_data
				ship_count += 1

	file.close()
	ships_loaded = true
	print("DataManager: Loaded ", ship_count, " ships")
	return true

func parse_ship_data(header: Array, line: Array) -> Dictionary:
	"""Parse a single ship CSV line into a dictionary"""
	var ship_data = {}

	# Map CSV columns to dictionary keys
	for i in range(min(header.size(), line.size())):
		var column_name = header[i]
		var value = line[i]

		# Parse value based on column type
		match column_name:
			"ship_id", "display_name", "faction", "sprite_path", "projectile_sprite", "size_class", "description", "ability_function", "ability", "ability_description", "type":
				ship_data[column_name] = value

			"size", "projectile_size", "armor", "shield", "reinforced_armor", "evasion", "damage", "accuracy", "num_attacks", "amplitude", "frequency", "energy", "starting_energy", "upgrade_slots", "movement_speed":
				ship_data[column_name] = int(value) if value != "" else 0

			"deploy_speed", "attack_speed":
				ship_data[column_name] = float(value) if value != "" else 0.0

			"enabled":
				ship_data[column_name] = value.to_lower() == "true" or value == "1"

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
			"frequency": ship_data.get("frequency", 0),
			"energy": ship_data.get("energy", 0),
			"starting_energy": ship_data.get("starting_energy", 0)
		}

	return ship_data

func get_ship_data(ship_id: String) -> Dictionary:
	"""Get ship data by ship_id"""
	if not ships_loaded:
		push_warning("DataManager: Ship database not loaded yet")
		return {}

	if not ships.has(ship_id):
		push_warning("DataManager: Ship not found: " + ship_id)
		return {}

	return ships[ship_id]

func get_ships_by_faction(faction: String) -> Array[Dictionary]:
	"""Get all ships of a specific faction (player/enemy)"""
	var faction_ships: Array[Dictionary] = []

	for ship_id in ships.keys():
		var ship_data = ships[ship_id]
		if ship_data.get("faction", "") == faction and ship_data.get("enabled", true):
			faction_ships.append(ship_data)

	return faction_ships

func get_ships_by_type(type: String) -> Array[Dictionary]:
	"""Get all ships of a specific type (ship/turret)"""
	var type_ships: Array[Dictionary] = []

	for ship_id in ships.keys():
		var ship_data = ships[ship_id]
		if ship_data.get("type", "") == type and ship_data.get("enabled", true):
			type_ships.append(ship_data)

	return type_ships

func get_all_ships() -> Array[Dictionary]:
	"""Get all ship data"""
	var all_ships: Array[Dictionary] = []
	for ship_id in ships.keys():
		all_ships.append(ships[ship_id])
	return all_ships

func get_enabled_ships() -> Array[Dictionary]:
	"""Get all enabled ships"""
	var enabled_ships: Array[Dictionary] = []
	for ship_id in ships.keys():
		var ship_data = ships[ship_id]
		if ship_data.get("enabled", true):
			enabled_ships.append(ship_data)
	return enabled_ships

# ============================================================================
# CARD DATABASE
# ============================================================================

func load_card_database() -> bool:
	"""Load card data from any_type_4_card_database.csv"""
	print("DataManager: Loading card database from: ", CARD_DATABASE_PATH)

	var file = FileAccess.open(CARD_DATABASE_PATH, FileAccess.READ)
	if file == null:
		push_error("DataManager: Could not open card database: " + CARD_DATABASE_PATH)
		return false

	# Read header
	var header = file.get_csv_line()
	if header.is_empty():
		push_error("DataManager: Card database is empty")
		file.close()
		return false

	# Parse data lines
	var card_count = 0
	while not file.eof_reached():
		var line = file.get_csv_line()

		# Skip empty lines
		if line.is_empty() or (line.size() == 1 and line[0] == ""):
			continue

		# Parse card data
		var card_data = parse_card_data(header, line)
		if not card_data.is_empty():
			var card_id = card_data.get("card_id", "")
			if card_id != "":
				cards[card_id] = card_data
				card_count += 1

	file.close()
	cards_loaded = true
	print("DataManager: Loaded ", card_count, " cards")
	return true

func parse_card_data(header: Array, line: Array) -> Dictionary:
	"""Parse a single card CSV line into a dictionary"""
	var card_data = {}

	# Map CSV columns to dictionary keys
	for i in range(min(header.size(), line.size())):
		var column_name = header[i]
		var value = line[i]

		# Store all card fields as-is (type conversion can be done later if needed)
		card_data[column_name] = value

	return card_data

func get_card_data(card_id: String) -> Dictionary:
	"""Get card data by card_id"""
	if not cards_loaded:
		push_warning("DataManager: Card database not loaded yet")
		return {}

	if not cards.has(card_id):
		push_warning("DataManager: Card not found: " + card_id)
		return {}

	return cards[card_id]

func get_cards_by_type(card_type: String) -> Array[Dictionary]:
	"""Get all cards of a specific type"""
	var type_cards: Array[Dictionary] = []

	for card_id in cards.keys():
		var card_data = cards[card_id]
		if card_data.get("type", "") == card_type:
			type_cards.append(card_data)

	return type_cards

func get_all_cards() -> Array[Dictionary]:
	"""Get all card data"""
	var all_cards: Array[Dictionary] = []
	for card_id in cards.keys():
		all_cards.append(cards[card_id])
	return all_cards

func load_starting_deck() -> Array[String]:
	"""Load starting deck card IDs from starting_deck.csv"""
	var deck_card_ids: Array[String] = []

	var file = FileAccess.open(STARTING_DECK_PATH, FileAccess.READ)
	if file == null:
		push_error("DataManager: Could not open starting deck: " + STARTING_DECK_PATH)
		return deck_card_ids

	# Read header
	var _header = file.get_csv_line()

	# Read card IDs
	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() > 0 and line[0] != "":
			deck_card_ids.append(line[0])

	file.close()
	print("DataManager: Loaded starting deck with ", deck_card_ids.size(), " cards")
	return deck_card_ids

# ============================================================================
# STAR NAMES DATABASE
# ============================================================================

func load_star_names() -> bool:
	"""Load star names from star_names.csv"""
	print("DataManager: Loading star names from: ", STAR_NAMES_PATH)

	star_names.clear()
	var file = FileAccess.open(STAR_NAMES_PATH, FileAccess.READ)
	if file == null:
		push_error("DataManager: Could not open star names: " + STAR_NAMES_PATH)
		return false

	# Skip header
	var _header = file.get_csv_line()

	# Read star names
	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() > 0 and line[0] != "":
			star_names.append(line[0])

	file.close()
	star_names_loaded = true
	print("DataManager: Loaded ", star_names.size(), " star names")
	return true

func get_random_star_name() -> String:
	"""Get a random star name"""
	if not star_names_loaded or star_names.is_empty():
		return "Unknown Star"

	return star_names[randi() % star_names.size()]

func get_all_star_names() -> Array[String]:
	"""Get all star names"""
	return star_names.duplicate()

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

func reload_all_databases():
	"""Reload all CSV databases (useful for development)"""
	print("DataManager: Reloading all databases...")
	ships.clear()
	cards.clear()
	star_names.clear()

	ships_loaded = false
	cards_loaded = false
	star_names_loaded = false

	load_all_databases()

func is_all_data_loaded() -> bool:
	"""Check if all databases are loaded"""
	return ships_loaded and cards_loaded and star_names_loaded

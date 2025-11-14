extends Node

## DataManager Singleton
## Centralized CSV loading and data management for the entire game
## Handles all database files and provides clean access interfaces

# CSV file paths
const SHIP_DATABASE_PATH = "res://card_database/ship_database.csv"
const STARTING_DECK_PATH = "res://card_database/starting_deck.csv"
const STARTING_SHIPS_PATH = "res://card_database/starting_ships.csv"
const PILOT_DATABASE_PATH = "res://card_database/pilot_database.csv"
const STARTING_PILOTS_PATH = "res://card_database/starting_pilots.csv"
const STAR_NAMES_PATH = "res://card_database/star_names.csv"
const CARD_DATABASE_PATH = "res://card_database/card_database.csv"

# Cached data
var ships: Dictionary = {}  # ship_id -> ship_data
var pilots: Dictionary = {}  # call_sign -> pilot_data
var star_names: Array[String] = []
var cards: Dictionary = {}  # card_name -> card_data

# Loading status flags
var ships_loaded: bool = false
var pilots_loaded: bool = false
var star_names_loaded: bool = false
var cards_loaded: bool = false

func _ready():
	print("DataManager: Initializing...")
	load_all_databases()

func load_all_databases():
	"""Load all CSV databases on startup"""
	load_ship_database()
	load_pilot_database()
	load_star_names()
	load_card_database()
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
# PILOT DATABASE
# ============================================================================

func load_pilot_database() -> bool:
	"""Load pilot data from pilot_database.csv"""
	print("DataManager: Loading pilot database from: ", PILOT_DATABASE_PATH)

	var file = FileAccess.open(PILOT_DATABASE_PATH, FileAccess.READ)
	if file == null:
		push_error("DataManager: Could not open pilot database: " + PILOT_DATABASE_PATH)
		return false

	# Read header
	var header = file.get_csv_line()
	if header.is_empty():
		push_error("DataManager: Pilot database is empty")
		file.close()
		return false

	# Parse data lines
	var pilot_count = 0
	while not file.eof_reached():
		var line = file.get_csv_line()

		# Skip empty lines
		if line.is_empty() or (line.size() == 1 and line[0] == ""):
			continue

		# Parse pilot data
		var pilot_data = parse_pilot_data(header, line)
		if not pilot_data.is_empty():
			var call_sign = pilot_data.get("call_sign", "")
			if call_sign != "":
				pilots[call_sign] = pilot_data
				pilot_count += 1

	file.close()
	pilots_loaded = true
	print("DataManager: Loaded ", pilot_count, " pilots")
	return true

func parse_pilot_data(header: Array, line: Array) -> Dictionary:
	"""Parse a single pilot CSV line into a dictionary"""
	var pilot_data = {}

	# Map CSV columns to dictionary keys
	for i in range(min(header.size(), line.size())):
		var column_name = header[i]
		var value = line[i]

		# Parse value based on column type
		match column_name:
			"call_sign", "first_name", "last_name", "passive_ability", "ability_effect", "rarity", "portrait_path":
				pilot_data[column_name] = value

			"enabled":
				pilot_data[column_name] = value.to_lower() == "true" or value == "1"

	return pilot_data

func get_pilot_data(call_sign: String) -> Dictionary:
	"""Get pilot data by call_sign"""
	if not pilots_loaded:
		push_warning("DataManager: Pilot database not loaded yet")
		return {}

	if not pilots.has(call_sign):
		push_warning("DataManager: Pilot not found: " + call_sign)
		return {}

	return pilots[call_sign]

func get_all_pilots() -> Array[Dictionary]:
	"""Get all pilot data"""
	var all_pilots: Array[Dictionary] = []
	for call_sign in pilots.keys():
		all_pilots.append(pilots[call_sign])
	return all_pilots

func get_enabled_pilots() -> Array[Dictionary]:
	"""Get all enabled pilots"""
	var enabled_pilots: Array[Dictionary] = []
	for call_sign in pilots.keys():
		var pilot_data = pilots[call_sign]
		if pilot_data.get("enabled", true):
			enabled_pilots.append(pilot_data)
	return enabled_pilots

func load_starting_pilots() -> Array[String]:
	"""Load starting pilots from starting_pilots.csv and return call signs"""
	print("DataManager: Loading starting pilots from: ", STARTING_PILOTS_PATH)

	var pilot_call_signs: Array[String] = []
	var file = FileAccess.open(STARTING_PILOTS_PATH, FileAccess.READ)
	if file == null:
		push_error("DataManager: Could not open starting pilots: " + STARTING_PILOTS_PATH)
		return pilot_call_signs

	# Read call signs (no header in this CSV)
	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() > 0 and line[0] != "":
			pilot_call_signs.append(line[0])

	file.close()
	print("DataManager: Loaded ", pilot_call_signs.size(), " starting pilots")
	return pilot_call_signs

# ============================================================================
# CARD DATABASE
# ============================================================================

func load_card_database() -> bool:
	"""Load card data from card_database.csv"""
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
			var card_name = card_data.get("card_name", "")
			if card_name != "":
				cards[card_name] = card_data
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
		
		# All card fields are strings
		card_data[column_name] = value
	
	return card_data

func get_card_data(card_name: String) -> Dictionary:
	"""Get card data by card_name"""
	if not cards_loaded:
		push_warning("DataManager: Card database not loaded yet")
		return {}
	
	if not cards.has(card_name):
		push_warning("DataManager: Card not found: " + card_name)
		return {}
	
	return cards[card_name]

func get_all_cards() -> Array[Dictionary]:
	"""Get all card data"""
	var all_cards: Array[Dictionary] = []
	for card_name in cards.keys():
		all_cards.append(cards[card_name])
	return all_cards

func load_starting_deck() -> Array[String]:
	"""Load starting deck from starting_deck.csv and return card names"""
	print("DataManager: Loading starting deck from: ", STARTING_DECK_PATH)
	
	var deck_card_names: Array[String] = []
	var file = FileAccess.open(STARTING_DECK_PATH, FileAccess.READ)
	if file == null:
		push_error("DataManager: Could not open starting deck: " + STARTING_DECK_PATH)
		return deck_card_names
	
	# Skip header
	var _header = file.get_csv_line()
	
	# Read card names
	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() > 0 and line[0] != "":
			deck_card_names.append(line[0])
	
	file.close()
	print("DataManager: Loaded starting deck with ", deck_card_names.size(), " cards")
	return deck_card_names

func load_starting_ships() -> Array[String]:
	"""Load starting ships from starting_ships.csv and return ship IDs"""
	print("DataManager: Loading starting ships from: ", STARTING_SHIPS_PATH)

	var ship_ids: Array[String] = []
	var file = FileAccess.open(STARTING_SHIPS_PATH, FileAccess.READ)
	if file == null:
		push_error("DataManager: Could not open starting ships: " + STARTING_SHIPS_PATH)
		return ship_ids

	# Read ship IDs (no header in this CSV)
	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() > 0 and line[0] != "":
			ship_ids.append(line[0])

	file.close()
	print("DataManager: Loaded ", ship_ids.size(), " starting ships")
	return ship_ids

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

	return star_names[SeedManager.randi() % star_names.size()]

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
	pilots.clear()
	star_names.clear()
	cards.clear()

	ships_loaded = false
	pilots_loaded = false
	star_names_loaded = false
	cards_loaded = false

	load_all_databases()

func is_all_data_loaded() -> bool:
	"""Check if all databases are loaded"""
	return ships_loaded and pilots_loaded and star_names_loaded and cards_loaded

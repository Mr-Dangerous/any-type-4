extends Node

## Ship Database Singleton
## This is now a facade/proxy to DataManager for backwards compatibility
## All ship data loading is handled by DataManager

## DEPRECATED: This singleton is maintained for backwards compatibility
## New code should use DataManager directly instead

func _ready():
	# Data is loaded by DataManager autoload
	# This singleton just provides access methods for existing code
	pass

func get_ship_data(ship_id: String) -> Dictionary:
	"""Get ship data by ship_id (delegates to DataManager)"""
	return DataManager.get_ship_data(ship_id)

func get_ships_by_faction(faction: String) -> Array[Dictionary]:
	"""Get all ships of a specific faction (delegates to DataManager)"""
	return DataManager.get_ships_by_faction(faction)

func get_ships_by_type(type: String) -> Array[Dictionary]:
	"""Get all ships of a specific type (delegates to DataManager)"""
	return DataManager.get_ships_by_type(type)

func get_all_ships() -> Array[Dictionary]:
	"""Get all ship data (delegates to DataManager)"""
	return DataManager.get_all_ships()

func get_enabled_ships() -> Array[Dictionary]:
	"""Get all enabled ships"""
	var enabled_ships: Array[Dictionary] = []
	for ship_data in DataManager.get_all_ships():
		if ship_data.get("enabled", true):
			enabled_ships.append(ship_data)
	return enabled_ships

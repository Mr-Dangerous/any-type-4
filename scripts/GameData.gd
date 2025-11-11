extends Node

# Persistent starmap data
var star_data: Array[Dictionary] = []
var has_starmap_data: bool = false

# Persistent combat data
var combat_state: Dictionary = {}
var has_combat_state: bool = false

# Persistent deck data (only base cards, no generated cards)
var player_deck: Array[Dictionary] = []
var has_deck_data: bool = false

# Persistent seed data
var game_seed: int = 0
var has_seed: bool = false

# Player resources
var metal: int = 50
var crystals: int = 30
var fuel: int = 3
var pilots: int = 3
var metal_large: int = 3  # Placeholder
var crystal_large: int = 3  # Placeholder

func save_starmap(stars: Array[Dictionary]):
	star_data = stars.duplicate(true)
	has_starmap_data = true

func clear_starmap():
	star_data.clear()
	has_starmap_data = false

func save_combat_state(state: Dictionary):
	combat_state = state.duplicate(true)
	has_combat_state = true
	print("Combat state saved: ", combat_state.keys())

func get_combat_state() -> Dictionary:
	return combat_state

func clear_combat_state():
	combat_state.clear()
	has_combat_state = false

func save_deck(deck: Array[Dictionary]):
	# Only save base cards (not generated attack cards)
	player_deck.clear()
	for card_data in deck:
		var card_type = card_data["type"]
		# Exclude generated attack cards
		if card_type not in ["scout_attack", "corvette_attack", "interceptor_attack", "fighter_attack"]:
			player_deck.append(card_data.duplicate())
	has_deck_data = true
	print("Saved ", player_deck.size(), " cards to persistent deck")

func get_deck() -> Array[Dictionary]:
	return player_deck

func clear_deck():
	player_deck.clear()
	has_deck_data = false

func save_seed(seed_value: int):
	game_seed = seed_value
	has_seed = true
	print("Game seed saved: ", game_seed)

func get_seed() -> int:
	return game_seed

func clear_seed():
	game_seed = 0
	has_seed = false

# Resource management
func add_resource(type: String, amount: int):
	match type:
		"metal":
			metal += amount
		"crystals":
			crystals += amount
		"fuel":
			fuel += amount
		"pilots":
			pilots += amount
		"metal_large":
			metal_large += amount
		"crystal_large":
			crystal_large += amount
	print("Added ", amount, " ", type, ". New total: ", get_resource(type))

func spend_resource(type: String, amount: int) -> bool:
	var current = get_resource(type)
	if current >= amount:
		match type:
			"metal":
				metal -= amount
			"crystals":
				crystals -= amount
			"fuel":
				fuel -= amount
			"pilots":
				pilots -= amount
			"metal_large":
				metal_large -= amount
			"crystal_large":
				crystal_large -= amount
		print("Spent ", amount, " ", type, ". Remaining: ", get_resource(type))
		return true
	else:
		print("Insufficient ", type, ". Have: ", current, ", Need: ", amount)
		return false

func get_resource(type: String) -> int:
	match type:
		"metal":
			return metal
		"crystals":
			return crystals
		"fuel":
			return fuel
		"pilots":
			return pilots
		"metal_large":
			return metal_large
		"crystal_large":
			return crystal_large
	return 0

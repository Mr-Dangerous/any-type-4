extends Node

# Persistent starmap data
var star_data: Array[Dictionary] = []
var constellation_data: Array[Dictionary] = []
var has_starmap_data: bool = false

# Persistent combat data
var combat_state: Dictionary = {}
var has_combat_state: bool = false

# Persistent deck data (only base cards, no generated cards)
var player_deck: Array[Dictionary] = []
var has_deck_data: bool = false

func save_starmap(stars: Array[Dictionary], constellations: Array[Dictionary]):
	star_data = stars.duplicate(true)
	constellation_data = constellations.duplicate(true)
	has_starmap_data = true

func clear_starmap():
	star_data.clear()
	constellation_data.clear()
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

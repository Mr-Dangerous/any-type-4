extends Node2D

# Card database
var card_database: Dictionary = {}

# TODO: Card scene will be created when implementing new card system
# var CardScene = preload("res://scenes/Card.tscn")

# UI references
@onready var card_grid: GridContainer = $UI/ScrollContainer/CardGrid
@onready var deck_count_label: Label = $UI/DeckCountLabel
@onready var back_button: Button = $UI/BackButton

# Previous scene tracking
var previous_scene: String = ""

func _ready():
	# Load card database from DataManager
	load_cards_from_datamanager()

	# Connect back button
	back_button.pressed.connect(_on_back_button_pressed)

	# Check if we came from a specific scene
	if GameData.has_starmap_data:
		previous_scene = "res://scenes/StarMap.tscn"
	else:
		# Default to starmap
		previous_scene = "res://scenes/StarMap.tscn"

	# Load and display the deck
	load_deck()

func load_cards_from_datamanager():
	"""Load all cards from DataManager into card_database"""
	card_database.clear()

	for card_data in DataManager.get_all_cards():
		# Use card type as key for easy lookup
		var card_type = card_data.get("type", "")
		if card_type != "":
			card_database[card_type] = card_data

	print("DeckBuilder: Loaded ", card_database.size(), " cards from DataManager")

func load_deck():
	"""Load starting deck from DataManager"""
	var deck_cards: Array[Dictionary] = []

	# Get starting deck card IDs from DataManager
	var deck_card_ids = DataManager.load_starting_deck()

	# Look up each card in the database
	for card_id in deck_card_ids:
		var card_data = DataManager.get_card_data(card_id)
		if not card_data.is_empty():
			deck_cards.append(card_data.duplicate())
		else:
			# Try using card_id as type key (backwards compatibility)
			var card_type = card_id.to_lower().replace(" ", "_")
			if card_database.has(card_type):
				deck_cards.append(card_database[card_type].duplicate())
			else:
				print("DeckBuilder: Warning - Card not found: ", card_id)

	# Display the deck
	display_deck(deck_cards)

	# Update deck count
	deck_count_label.text = "Total Cards: %d" % deck_cards.size()

func display_deck(deck: Array[Dictionary]):
	# Clear existing cards
	for child in card_grid.get_children():
		child.queue_free()

	# TODO: Re-implement when new Card scene is created
	# Create card UI for each card in the deck
	# var card_index = 0
	# for card_data in deck:
	# 	var card = CardScene.instantiate()
	# 	card_grid.add_child(card)
	#
	# 	# Use setup method to initialize card
	# 	card.setup(card_data, "deck_card_%d" % card_index)
	#
	# 	# Scale down slightly for grid view
	# 	card.scale = Vector2(0.9, 0.9)
	#
	# 	# Disable mouse interaction in deck builder
	# 	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	#
	# 	card_index += 1

func _on_back_button_pressed():
	# Return to previous scene
	get_tree().change_scene_to_file(previous_scene)

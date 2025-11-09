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
	# Load card database
	load_cards_from_csv("res://card_database/any_type_4_card_database.csv")

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

func load_cards_from_csv(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		print("Failed to open CSV file: ", file_path)
		return false

	# Read header line
	var header = file.get_csv_line()
	if header.size() < 4:
		print("Invalid CSV format - expected at least 4 columns")
		file.close()
		return false

	# Parse each line
	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() >= 4 and line[0] != "":
			var card_data = {
				"name": line[0],
				"cost": int(line[1]),
				"description": line[2],
				"type": line[3],
				"armor": int(line[4]) if line.size() > 4 else 0,
				"shield": int(line[5]) if line.size() > 5 else 0
			}
			# Use lowercase type as key for easy lookup
			card_database[line[3]] = card_data

	file.close()
	print("Loaded ", card_database.size(), " cards from CSV")
	return true

func load_deck():
	# Load starting deck from CSV to get the default order
	var deck_cards: Array[Dictionary] = []

	var file = FileAccess.open("res://card_database/starting_deck.csv", FileAccess.READ)
	if file == null:
		print("Failed to open starting_deck.csv")
		return

	# Read header line
	var header = file.get_csv_line()

	# Read each card name and add to deck
	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() > 0 and line[0] != "":
			var card_name = line[0]
			# Convert card name to lowercase type key
			var card_type = card_name.to_lower().replace(" ", "_")
			if card_database.has(card_type):
				deck_cards.append(card_database[card_type].duplicate())
			else:
				print("Warning: Card type not found in database: ", card_type)

	file.close()

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

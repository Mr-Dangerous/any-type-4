extends Node2D

# Preload Card scene
const CardScene = preload("res://scenes/Card.tscn")

# Preload ship textures
const ScoutTexture = preload("res://assets/sprites/scout.svg")
const FighterTexture = preload("res://assets/sprites/fighter.svg")
const CorvetteTexture = preload("res://assets/sprites/corvette.svg")
const InterceptorTexture = preload("res://assets/sprites/interceptor.svg")

# Preload enemy textures
const SlimeTexture = preload("res://assets/sprites/slime.svg")
# Uncomment after restarting Godot so it imports the SVG:
# const TentacleHorrorTexture = preload("res://assets/sprites/tentacle_horror.svg")

# Game state
var player_armor: int = 50
var player_max_armor: int = 50
var player_shield: int = 10
var player_max_shield: int = 10
var player_block: int = 0

# Enemy data
var enemy_database: Dictionary = {}
var enemies: Array[Dictionary] = []  # Array of enemy instances
# Each enemy has: name, hp, max_hp, attack_index, intent

var energy: int = 3
var max_energy: int = 3

# Card piles
var draw_pile: Array[Dictionary] = []
var hand: Array[Card] = []
var discard_pile: Array[Dictionary] = []

# Deployed ships tracking (Dictionary with unique instance ID as key, ship data as value)
# Keys are like "scout_alpha", "corvette_bravo", etc.
var deployed_ships: Dictionary = {}

# Position names for deployed ships
var position_names: Array[String] = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet", "Kilo", "Lima", "Mike"]

# Ship line positioning
const FRONT_LINE_X: float = 250.0
const BACK_LINE_X: float = 50.0
const SHIP_START_Y: float = 150.0
const SHIP_VERTICAL_SPACING: float = 145.0

# Track next available position index
var next_position_index: int = 0

# Counter for generating unique card instance IDs
var card_instance_counter: int = 0

# Map of card instance ID to deployed ship instance ID
var card_to_deployed_ship: Dictionary = {}

# UI nodes
@onready var player_hp_label: Label = $UI/PlayerInfo/HPBarBackground/HPLabel
@onready var player_armor_bar: ColorRect = $UI/PlayerInfo/HPBarBackground/ArmorBar
@onready var player_shield_bar: ColorRect = $UI/PlayerInfo/HPBarBackground/ShieldBar
@onready var energy_icon_1: ColorRect = $UI/PlayerInfo/EnergyIcon1
@onready var energy_icon_2: ColorRect = $UI/PlayerInfo/EnergyIcon2
@onready var energy_icon_3: ColorRect = $UI/PlayerInfo/EnergyIcon3
@onready var hand_container: Control = $UI/HandContainer
@onready var card_display_zone: Control = $UI/CardDisplayZone
@onready var discard_pile_zone: Control = $UI/DiscardPileZone

# Hand display constants
const MAX_HAND_SIZE: int = 10
const CARD_WIDTH: float = 120.0
const MAX_CARD_SPACING: float = 130.0  # Maximum spacing between cards
const MIN_CARD_SPACING: float = 60.0   # Minimum spacing when hand is full
const HOVER_LIFT: float = 100.0  # How much to lift card on hover

var hovered_card: Card = null

# Card display zone queue
var display_queue: Array[Dictionary] = []
var is_displaying_card: bool = false

# Targeting system
var hovered_enemy_index: int = -1  # -1 means no enemy hovered
var targeted_enemy_index: int = -1  # -1 means auto-target first alive
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var draw_pile_label: Label = $UI/PileInfo/DrawPileLabel
@onready var discard_pile_label: Label = $UI/PileInfo/DiscardPileLabel
@onready var to_starmap_button: Button = $UI/ToStarMapButton
@onready var deck_builder_button: Button = $UI/DeckBuilderButton
@onready var notification_label: Label = $UI/NotificationLabel
@onready var previous_notification_label: Label = $UI/PreviousNotificationLabel
@onready var next_notification_label: Label = $UI/NextNotificationLabel
@onready var notification_help_label: Label = $UI/NotificationHelpLabel

# Notification system
var notification_queue: Array[String] = []
var notification_history: Array[String] = []
var current_history_index: int = -1  # -1 means showing live notifications
var is_showing_notification: bool = false

# Card definitions
var card_database: Dictionary = {}

# Ship type to attack type mapping
var ship_to_attack = {
	"scout": "scout_attack",
	"corvette": "corvette_attack",
	"interceptor": "interceptor_attack",
	"fighter": "fighter_attack"
}

func _ready():
	# Load cards from CSV
	load_cards_from_csv("res://card_database/any_type_4_card_database.csv")

	# Load enemies from CSV
	load_enemies_from_csv("res://card_database/enemies.csv")

	# Initialize enemies (spawn 2 Slimes for testing)
	spawn_enemies(["Slime", "Slime"])

	# Debug: Check if energy icons loaded
	print("Energy icon 1: ", energy_icon_1)
	print("Energy icon 2: ", energy_icon_2)
	print("Energy icon 3: ", energy_icon_3)
	print("Armor bar: ", player_armor_bar)
	print("Shield bar: ", player_shield_bar)

	# Connect buttons
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	to_starmap_button.pressed.connect(_on_to_starmap)
	deck_builder_button.pressed.connect(_on_deck_builder)

	# Check if we have a saved combat state to restore
	if GameData.has_combat_state:
		restore_combat_state()
	else:
		# Initialize deck
		initialize_deck()

		# Start first turn
		start_turn()

	# Update UI
	update_ui()

func _input(event):
	# Handle notification history navigation
	if notification_history.size() > 1:
		if event.is_action_pressed("ui_up"):
			# Scroll to older notification
			if current_history_index == -1:
				# Start browsing from second-to-last
				current_history_index = notification_history.size() - 2
			elif current_history_index > 0:
				current_history_index -= 1
			update_notification_display()
			get_viewport().set_input_as_handled()

		elif event.is_action_pressed("ui_down"):
			# Scroll to newer notification
			if current_history_index != -1:
				current_history_index += 1
				if current_history_index >= notification_history.size() - 1:
					# Return to live view
					current_history_index = -1
			update_notification_display()
			get_viewport().set_input_as_handled()

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

func load_enemies_from_csv(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		print("Failed to open enemies CSV file: ", file_path)
		return false

	# Read header line
	var header = file.get_csv_line()
	if header.size() < 5:
		print("Invalid enemies CSV format - expected at least 5 columns")
		file.close()
		return false

	# Parse each line
	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() >= 5 and line[0] != "":
			var enemy_data = {
				"name": line[0],
				"hp": int(line[1]),
				"attack1": int(line[2]),
				"attack2": int(line[3]),
				"attack3": int(line[4])
			}
			# Use name as key for easy lookup
			enemy_database[line[0]] = enemy_data

	file.close()
	print("Loaded ", enemy_database.size(), " enemies from CSV")
	return true

func spawn_enemies(enemy_names: Array):
	enemies.clear()

	for enemy_name in enemy_names:
		if not enemy_database.has(enemy_name):
			print("Error: Enemy not found: ", enemy_name)
			continue

		var enemy_data = enemy_database[enemy_name].duplicate()
		var enemy_instance = {
			"name": enemy_name,
			"hp": enemy_data["hp"],
			"max_hp": enemy_data["hp"],
			"attack_index": 0,
			"intent": "Attack",  # For now, always attack
			"attack1": enemy_data["attack1"],
			"attack2": enemy_data["attack2"],
			"attack3": enemy_data["attack3"]
		}
		enemies.append(enemy_instance)

	# Create enemy UI elements
	create_enemy_ui()

	print("Spawned ", enemies.size(), " enemies")

func create_enemy_ui():
	# Remove old enemy UI
	var old_enemy_info = $UI/EnemyInfo
	if old_enemy_info:
		old_enemy_info.queue_free()
	var old_slime_sprite = $UI/SlimeSprite
	if old_slime_sprite:
		old_slime_sprite.queue_free()

	# Create container for all enemies (vertical on right side)
	var enemies_container = VBoxContainer.new()
	enemies_container.name = "EnemiesContainer"
	enemies_container.position = Vector2(750, 150)
	enemies_container.add_theme_constant_override("separation", 20)
	$UI.add_child(enemies_container)

	# Create UI for each enemy
	for i in range(enemies.size()):
		var enemy = enemies[i]
		var enemy_vbox = VBoxContainer.new()
		enemy_vbox.name = "Enemy%d" % i
		enemy_vbox.custom_minimum_size = Vector2(150, 180)

		# Enemy sprite container with crosshair overlay
		var sprite_container = Control.new()
		sprite_container.name = "SpriteContainer"
		sprite_container.custom_minimum_size = Vector2(100, 100)

		var sprite = TextureRect.new()
		sprite.name = "Sprite"
		sprite.size = Vector2(100, 100)
		sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		match enemy["name"]:
			"Slime":
				sprite.texture = SlimeTexture
		sprite_container.add_child(sprite)

		# Crosshair targeting indicator (hidden by default)
		var crosshair = Label.new()
		crosshair.name = "Crosshair"
		crosshair.text = "✖"  # Crosshair character
		crosshair.add_theme_color_override("font_color", Color(1, 0, 0, 1))  # Red
		crosshair.add_theme_font_size_override("font_size", 48)
		crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		crosshair.size = Vector2(100, 100)
		crosshair.visible = false
		crosshair.z_index = 10
		sprite_container.add_child(crosshair)

		enemy_vbox.add_child(sprite_container)

		# Enemy name label
		var name_label = Label.new()
		name_label.name = "NameLabel"
		name_label.text = enemy["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 16)
		enemy_vbox.add_child(name_label)

		# HP label
		var hp_label = Label.new()
		hp_label.name = "HPLabel"
		hp_label.text = "HP: %d/%d" % [enemy["hp"], enemy["max_hp"]]
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
		hp_label.add_theme_font_size_override("font_size", 14)
		enemy_vbox.add_child(hp_label)

		# Intent label
		var intent_label = Label.new()
		intent_label.name = "IntentLabel"
		intent_label.text = "Intent: %s" % enemy["intent"]
		intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		intent_label.add_theme_color_override("font_color", Color(1, 1, 0.3, 1))
		intent_label.add_theme_font_size_override("font_size", 12)
		enemy_vbox.add_child(intent_label)

		enemies_container.add_child(enemy_vbox)

	print("Created UI for ", enemies.size(), " enemies")

func update_enemy_crosshairs():
	# Update crosshair visibility for all enemies
	var enemies_container = $UI.get_node_or_null("EnemiesContainer")
	if not enemies_container:
		return

	for i in range(enemies.size()):
		var enemy_vbox = enemies_container.get_node_or_null("Enemy%d" % i)
		if enemy_vbox:
			var sprite_container = enemy_vbox.get_node_or_null("SpriteContainer")
			if sprite_container:
				var crosshair = sprite_container.get_node_or_null("Crosshair")
				if crosshair:
					crosshair.visible = (i == hovered_enemy_index)

func get_enemy_at_position(pos: Vector2) -> int:
	# Check which enemy is at the given global position
	# Returns enemy index or -1 if none
	var enemies_container = $UI.get_node_or_null("EnemiesContainer")
	if not enemies_container:
		return -1

	for i in range(enemies.size()):
		if enemies[i]["hp"] <= 0:
			continue  # Skip dead enemies

		var enemy_vbox = enemies_container.get_node_or_null("Enemy%d" % i)
		if enemy_vbox:
			var rect = Rect2(enemy_vbox.global_position, enemy_vbox.size)
			if rect.has_point(pos):
				return i

	return -1

func initialize_deck():
	# Load starting deck from CSV
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
				draw_pile.append(card_database[card_type].duplicate())
			else:
				print("Warning: Card type not found in database: ", card_type)

	file.close()
	print("Loaded ", draw_pile.size(), " cards into starting deck")

	# Shuffle deck
	draw_pile.shuffle()

func start_turn():
	# Reset energy
	energy = max_energy

	# Draw 5 cards
	for i in range(5):
		draw_card()

	# Update UI
	update_ui()

func draw_card():
	if draw_pile.is_empty():
		# Reshuffle discard pile into draw pile
		if discard_pile.is_empty():
			return
		draw_pile = discard_pile.duplicate()
		discard_pile.clear()
		draw_pile.shuffle()

	if not draw_pile.is_empty():
		var card_data = draw_pile.pop_front()

		# Check if hand is full
		if hand.size() >= MAX_HAND_SIZE:
			# Show overflow card animation
			await show_overflow_card(card_data)
			# Add directly to discard
			discard_pile.append(card_data)
			show_notification("Hand full! Card discarded.")
		else:
			create_card_in_hand(card_data)

func create_card_in_hand(card_data: Dictionary):
	var card_instance = CardScene.instantiate()
	hand_container.add_child(card_instance)

	# Generate unique ID for this card instance
	card_instance_counter += 1
	var instance_id = "card_%d" % card_instance_counter

	card_instance.setup(card_data, instance_id)
	card_instance.card_played.connect(_on_card_played)
	card_instance.enemy_hover_changed.connect(_on_enemy_hover_changed)

	# Check if this card is a deployed ship that needs to be reconnected
	if card_data.has("is_deployed") and card_data["is_deployed"]:
		var deployed_instance_id = card_data["deployed_instance_id"]

		# Verify the deployed ship still exists
		if deployed_ships.has(deployed_instance_id):
			# Reconnect card to deployed ship
			card_instance.is_deployed = true
			card_instance.deployed_instance_id = deployed_instance_id
			card_instance.ship_position = deployed_ships[deployed_instance_id]["position"]

			# Update card to show current stats
			card_instance.armor = deployed_ships[deployed_instance_id]["armor"]
			card_instance.shield = deployed_ships[deployed_instance_id]["shield"]

			# Update the mapping
			card_to_deployed_ship[instance_id] = deployed_instance_id
			deployed_ships[deployed_instance_id]["card_instance_id"] = instance_id

			# Move ship back to front line (now in hand)
			move_ship_to_line(deployed_instance_id, true)

			card_instance.update_card_display()

	hand.append(card_instance)

	# Connect hover signals
	card_instance.mouse_entered.connect(_on_card_hover_start.bind(card_instance))
	card_instance.mouse_exited.connect(_on_card_hover_end.bind(card_instance))

	# Position cards in hand
	reposition_hand()

func add_card_to_hand_with_display(card_data: Dictionary, display_type: String = "normal"):
	# Add to display queue with callback to add to hand
	display_queue.append({
		"card_data": card_data,
		"display_type": display_type,
		"add_to_hand": true  # Flag to add to hand after displaying
	})

	# Start processing queue if not already displaying
	if not is_displaying_card:
		process_display_queue()

func _on_enemy_hover_changed(enemy_index: int):
	# Update which enemy is being hovered for crosshair display
	hovered_enemy_index = enemy_index
	update_enemy_crosshairs()

func _on_card_played(card: Card, target_enemy_index: int):
	# Store targeted enemy for this card play
	targeted_enemy_index = target_enemy_index

	if energy >= card.cost:
		# Check if this is a ship card (including activate versions)
		var is_ship = card.card_type in ["scout", "corvette", "interceptor", "fighter", "activate_scout", "activate_corvette", "activate_interceptor", "activate_fighter"]

		if is_ship:
			# Check if this specific card instance has been deployed
			if card_to_deployed_ship.has(card.card_instance_id):
				# Already deployed - use ship ability
				energy -= card.cost

				# Check if description has "activate" keyword (stays in hand)
				var has_activate = "activate" in card.description.to_lower()
				# Check if description requires discard cost
				var requires_discard = card.description.begins_with("Discard:")

				# Determine if card should be discarded
				var should_discard = not has_activate or requires_discard

				if should_discard:
					# Remove card from hand
					hand.erase(card)

					# Reposition remaining cards
					reposition_hand()

					# Animate card to discard pile
					await animate_card_to_discard(card)

					# Add to discard pile with deployed info so it can be drawn again
					var card_data = {
						"name": card.card_name,
						"cost": card.cost,
						"description": card.description,
						"type": card.card_type,
						"deployed_instance_id": card.deployed_instance_id,
						"is_deployed": true
					}
					discard_pile.append(card_data)

					# Remove from UI
					card.queue_free()

				# Execute ship ability based on type
				if card.card_type in ["corvette", "activate_corvette"]:
					# Corvette ability: shuffle a Torpedo into the deck
					if card_database.has("torpedo"):
						var torpedo_card = card_database["torpedo"].duplicate()
						# Link torpedo to the corvette that created it
						torpedo_card["source_ship_id"] = card.deployed_instance_id
						draw_pile.append(torpedo_card)
						draw_pile.shuffle()
						show_notification("%s %s fired! Torpedo shuffled into deck!" % [card.card_name, card.ship_position])
					else:
						show_notification("%s %s activated!" % [card.card_name, card.ship_position])
				elif card.card_type == "activate_fighter":
					# Fighter ability: next attack deals 3 additional damage
					# TODO: Implement damage buff system
					show_notification("%s %s empowers next attack! (+3 damage)" % [card.card_name, card.ship_position])
				else:
					# Scout, Interceptor: dodge ability
					show_notification("%s %s dodges! Ship evades enemy attacks this turn." % [card.card_name, card.ship_position])

				# Update UI
				update_ui()

				# If card stays in hand, reposition after effect
				if not should_discard:
					reposition_hand()
			else:
				# First time deploying this card - pay energy and deploy
				energy -= card.cost

				# Remove original card from hand (removed from game, not discarded)
				hand.erase(card)
				card.queue_free()

				# Deploy ship and create new deployed ship card
				deploy_ship_from_card(card.card_type)

				# Update UI
				update_ui()
		else:
			# Not a ship - normal card play (attack cards, shields up, etc.)
			# Pay energy cost
			energy -= card.cost

			# Execute card effect (with animation)
			await execute_card_effect(card)

			# Remove card from hand
			hand.erase(card)

			# Reposition remaining cards
			reposition_hand()

			# Animate card to discard pile
			await animate_card_to_discard(card)

			# Add to discard pile
			var card_data = {
				"name": card.card_name,
				"cost": card.cost,
				"description": card.description,
				"type": card.card_type
			}
			# Preserve source_ship_id for attack cards
			if card.source_ship_id != "":
				card_data["source_ship_id"] = card.source_ship_id
			discard_pile.append(card_data)

			# Remove from UI
			card.queue_free()

			# Update UI
			update_ui()

			# Check if all enemies are dead
			check_all_enemies_dead()
	else:
		# Not enough energy, return card to original position
		print("Not enough energy!")

func execute_card_effect(card: Card):
	match card.card_type:
		"scout_attack":
			# Play attack animation if ship exists
			if card.source_ship_id != "":
				await play_ship_attack_animation(card.source_ship_id)

			# Scout attack - 3 damage
			damage_enemy(3, targeted_enemy_index)

		"corvette_attack":
			# Play attack animation if ship exists
			if card.source_ship_id != "":
				await play_ship_attack_animation(card.source_ship_id)

			# Corvette attack - 5 damage
			damage_enemy(5, targeted_enemy_index)

		"interceptor_attack":
			# Play attack animation if ship exists
			if card.source_ship_id != "":
				await play_ship_attack_animation(card.source_ship_id)

			# Interceptor attack - 4 damage
			damage_enemy(4, targeted_enemy_index)

		"fighter_attack":
			# Play attack animation if ship exists
			if card.source_ship_id != "":
				await play_ship_attack_animation(card.source_ship_id)

			# Fighter attack - 7 damage
			damage_enemy(7, targeted_enemy_index)

		"torpedo":
			# Play attack animation if ship exists
			if card.source_ship_id != "":
				await play_ship_attack_animation(card.source_ship_id)

			# Torpedo - 10 damage
			damage_enemy(10, targeted_enemy_index)

		"tactical_command":
			# Find all attack cards in hand
			draw_card()
			draw_card()
			show_notification("Drew 2 cards!")
			var attack_cards = []
			for hand_card in hand:
				var is_attack = hand_card.card_type in ["scout_attack", "corvette_attack", "interceptor_attack", "fighter_attack", "torpedo"]
				if is_attack:
					attack_cards.append(hand_card)

			if attack_cards.size() > 0:
				# Randomly select an attack card
				var selected_card = attack_cards[randi() % attack_cards.size()]

				# Create card data for display
				var card_data = {
					"name": selected_card.card_name,
					"cost": selected_card.cost,
					"description": selected_card.description,
					"type": selected_card.card_type
				}
				if selected_card.source_ship_id != "":
					card_data["source_ship_id"] = selected_card.source_ship_id

				# Show in display zone
				await show_card_in_display_zone(card_data, "tactical_command")

				# Execute the attack card effect without cost
				await execute_card_effect(selected_card)

				# Remove from hand
				hand.erase(selected_card)

				# Add to discard pile
				discard_pile.append(card_data)

				# Remove from UI
				selected_card.queue_free()

				show_notification("Tactical Command played %s for free!" % selected_card.card_name)

				# Draw 2 cards
			
			else:
				show_notification("No attack cards in hand to command!")

				# Still draw 2 cards even if no attack available
				

		"shields_up":
			var ships_buffed = 0
			var deployed_count = 0
			var hand_count = 0

			# Give +1 shield to all deployed ships
			for ship_id in deployed_ships.keys():
				deployed_ships[ship_id]["shield"] += 1
				deployed_count += 1

			# Give +1 shield to all ship cards in hand
			for hand_card in hand:
				var is_ship = hand_card.card_type in ["scout", "corvette", "interceptor", "fighter"]
				if is_ship:
					hand_card.shield += 1
					hand_card.update_card_display()
					hand_count += 1

					# If this ship card is linked to a deployed ship, also update the deployed ship data
					if card_to_deployed_ship.has(hand_card.card_instance_id):
						var deployed_id = card_to_deployed_ship[hand_card.card_instance_id]
						if deployed_ships.has(deployed_id):
							deployed_ships[deployed_id]["shield"] += 1

			ships_buffed = deployed_count + hand_count
			update_deployed_ships_ui()
			show_notification("Shields Up! Buffed %d deployed ships and %d ships in hand!" % [deployed_count, hand_count])

		"strike":
			# Deal 5 damage to enemy (keeping for compatibility)
			damage_enemy(5, targeted_enemy_index)

		"defend":
			# Add block (reduces next attack by half)
			player_block += 1
			show_notification("Added block!")

func deploy_ship_from_card(ship_type: String):
	# Get ship data from database
	if not card_database.has(ship_type):
		print("Error: Ship type ", ship_type, " not found in database!")
		return

	var ship_data = card_database[ship_type].duplicate()

	# Get next position
	if next_position_index >= position_names.size():
		print("Error: No more positions available!")
		return

	var position = position_names[next_position_index]
	next_position_index += 1

	# Create unique instance ID using position
	var instance_id = "%s_%s" % [ship_type, position.to_lower()]

	# Create a new card for the deployed ship
	var deployed_card = CardScene.instantiate()
	hand_container.add_child(deployed_card)

	# Generate unique ID for this card instance
	card_instance_counter += 1
	var card_instance_id = "card_%d" % card_instance_counter

	# Check if there's a separate activate card type for deployed version
	var activate_type = "activate_%s" % ship_type
	var deployed_card_data = ship_data.duplicate()
	if card_database.has(activate_type):
		# Use the activate card's description and type
		var activate_data = card_database[activate_type]
		deployed_card_data["description"] = activate_data["description"]
		deployed_card_data["type"] = activate_data["type"]
		# Keep the original name and stats from ship_data

	# Setup the deployed card with modified data
	deployed_card.setup(deployed_card_data, card_instance_id)
	deployed_card.card_played.connect(_on_card_played)
	deployed_card.enemy_hover_changed.connect(_on_enemy_hover_changed)

	# Mark as deployed and add position
	deployed_card.is_deployed = true
	deployed_card.deployed_instance_id = instance_id
	deployed_card.ship_position = position

	# Description from CSV will be displayed with (deployed) replaced by position
	deployed_card.update_card_display()

	# Add to hand
	hand.append(deployed_card)

	# Connect hover signals for deployed card
	deployed_card.mouse_entered.connect(_on_card_hover_start.bind(deployed_card))
	deployed_card.mouse_exited.connect(_on_card_hover_end.bind(deployed_card))

	# Position cards in hand
	reposition_hand(false)  # No animation for immediate positioning

	# Mark ship as deployed with its stats and type
	deployed_ships[instance_id] = {
		"ship_type": ship_type,
		"position": position,
		"name": ship_data["name"],
		"armor": ship_data.get("armor", 0),
		"shield": ship_data.get("shield", 0),
		"card_instance_id": card_instance_id,  # Link to the new card
		"is_front_line": true  # Ships start at front line when deployed
	}

	# Link card to deployed ship
	card_to_deployed_ship[card_instance_id] = instance_id

	show_notification("Deployed %s %s! Armor: %d Shield: %d Total: %d" % [
		ship_data["name"],
		position,
		ship_data.get("armor", 0),
		ship_data.get("shield", 0),
		ship_data.get("armor", 0) + ship_data.get("shield", 0)
	])

	# Get the corresponding attack card type and add directly to hand
	if ship_to_attack.has(ship_type):
		var attack_type = ship_to_attack[ship_type]
		if card_database.has(attack_type):
			# Add attack card via display zone (will be added to hand after display)
			var attack_card = card_database[attack_type].duplicate()
			attack_card["source_ship_id"] = instance_id  # Link to the ship that created this attack
			add_card_to_hand_with_display(attack_card, "attack_card")

	# Create ship sprite
	create_ship_sprite(ship_type, position, instance_id)

	# Update deployed ships UI
	update_deployed_ships_ui()

func create_ship_sprite(ship_type: String, position_name: String, instance_id: String):
	# Get or create ships container on left side
	var ships_node = $UI.get_node_or_null("ShipsContainer")
	if not ships_node:
		ships_node = Node2D.new()
		ships_node.name = "ShipsContainer"
		$UI.add_child(ships_node)

	# Calculate vertical position based on number of ships
	var ship_index = deployed_ships.keys().find(instance_id)
	if ship_index == -1:
		ship_index = deployed_ships.size()

	# Create a container for this ship (sprite + health bar)
	var ship_container = Control.new()
	ship_container.name = instance_id
	ship_container.custom_minimum_size = Vector2(150, 130)

	# Position based on whether ship is in front line or back line
	var ship_data = deployed_ships.get(instance_id, {})
	var is_front_line = ship_data.get("is_front_line", true)
	var x_pos = FRONT_LINE_X if is_front_line else BACK_LINE_X
	ship_container.position = Vector2(x_pos, SHIP_START_Y + (ship_index * SHIP_VERTICAL_SPACING))

	# Create sprite
	var sprite = TextureRect.new()
	sprite.name = "Sprite"

	# Set texture based on ship type
	match ship_type:
		"scout":
			sprite.texture = ScoutTexture
		"fighter":
			sprite.texture = FighterTexture
		"corvette":
			sprite.texture = CorvetteTexture
		"interceptor":
			sprite.texture = InterceptorTexture

	sprite.custom_minimum_size = Vector2(100, 100)
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	ship_container.add_child(sprite)

	# Create health bar container
	var health_container = Control.new()
	health_container.name = "HealthBar"
	health_container.custom_minimum_size = Vector2(120, 20)

	# Health bar background
	var hp_bg = ColorRect.new()
	hp_bg.name = "Background"
	hp_bg.color = Color(0.2, 0.2, 0.2, 1)
	hp_bg.size = Vector2(120, 20)
	health_container.add_child(hp_bg)

	# Get ship stats (ship_data already declared earlier in function)
	var armor = ship_data.get("armor", 0)
	var shield = ship_data.get("shield", 0)
	var total_hp = armor + shield

	# Armor bar (gray)
	var armor_bar = ColorRect.new()
	armor_bar.name = "ArmorBar"
	armor_bar.color = Color(0.7, 0.7, 0.7, 1)
	if total_hp > 0:
		var armor_width = 120.0 * (float(armor) / float(total_hp))
		armor_bar.size = Vector2(armor_width, 20)
	health_container.add_child(armor_bar)

	# Shield bar (blue)
	var shield_bar = ColorRect.new()
	shield_bar.name = "ShieldBar"
	shield_bar.color = Color(0.3, 0.6, 1, 1)
	if total_hp > 0:
		var armor_width = 120.0 * (float(armor) / float(total_hp))
		shield_bar.position = Vector2(armor_width, 0)
		shield_bar.size = Vector2(120.0 - armor_width, 20)
	health_container.add_child(shield_bar)

	# HP text label
	var hp_label = Label.new()
	hp_label.name = "HPLabel"
	hp_label.text = "%d/%d" % [total_hp, armor]
	hp_label.size = Vector2(120, 20)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hp_label.add_theme_constant_override("outline_size", 2)
	hp_label.add_theme_font_size_override("font_size", 12)
	health_container.add_child(hp_label)

	ship_container.add_child(health_container)
	ships_node.add_child(ship_container)

func move_ship_to_line(instance_id: String, to_front_line: bool):
	# Move a ship to front line or back line with animation
	var ships_node = $UI.get_node_or_null("ShipsContainer")
	if not ships_node:
		return

	var ship_container = ships_node.get_node_or_null(instance_id)
	if not ship_container:
		return

	# Update ship data
	if deployed_ships.has(instance_id):
		deployed_ships[instance_id]["is_front_line"] = to_front_line

	# Calculate target x position
	var target_x = FRONT_LINE_X if to_front_line else BACK_LINE_X

	# Animate to new position
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(ship_container, "position:x", target_x, 0.5)

func _on_end_turn_pressed():
	# Discard only non-deployed cards from hand
	var cards_to_remove = []
	for card in hand:
		if not card.is_deployed:
			# Non-deployed card - add to discard pile
			var card_data = {
				"name": card.card_name,
				"cost": card.cost,
				"description": card.description,
				"type": card.card_type
			}
			discard_pile.append(card_data)
			cards_to_remove.append(card)

	# Remove non-deployed cards from hand and UI with animation
	for card in cards_to_remove:
		hand.erase(card)
		reposition_hand()
		await animate_card_to_discard(card)
		card.queue_free()

	print("Kept ", hand.size(), " deployed ships in hand for enemy turn")

	# Enemy turn (can attack deployed ships that are still in hand)
	enemy_turn()

	# Check if player is dead
	if player_armor <= 0 and player_shield <= 0:
		print("You died!")
		get_tree().reload_current_scene()
		return

	# After enemy turn, discard all remaining deployed ships and move them to back line
	cards_to_remove.clear()
	for card in hand:
		if card.is_deployed:
			# Deployed ship - add to discard pile with deployed info
			var card_data = {
				"name": card.card_name,
				"cost": card.cost,
				"description": card.description,
				"type": card.card_type,
				"deployed_instance_id": card.deployed_instance_id,  # Keep link to deployed ship
				"is_deployed": true
			}
			discard_pile.append(card_data)
			cards_to_remove.append(card)

			# Move ship to back line (no longer in hand)
			if card.deployed_instance_id != "":
				move_ship_to_line(card.deployed_instance_id, false)

	# Wait for ship animations to complete
	await get_tree().create_timer(0.5).timeout

	# Remove deployed ships from hand and UI
	for card in cards_to_remove:
		hand.erase(card)
		card.queue_free()

	print("Discarded ", cards_to_remove.size(), " deployed ships after enemy turn")

	# Start new turn with fresh hand
	start_turn()

func play_slime_attack_animation():
	# TODO: Update for multi-enemy system
	# Animation disabled for now
	pass

func play_ship_attack_animation(source_ship_id: String):
	# Find the ship container
	var ships_vbox = $UI.get_node_or_null("ShipsContainer")
	if not ships_vbox:
		print("Warning: Ships container not found")
		return

	var ship_container = ships_vbox.get_node_or_null(source_ship_id)
	if not ship_container:
		print("Warning: Ship container not found for attack animation: ", source_ship_id)
		return

	var ship_sprite = ship_container.get_node_or_null("Sprite")
	if not ship_sprite:
		print("Warning: Ship sprite not found for attack animation: ", source_ship_id)
		return

	# Find the first alive enemy sprite
	var enemies_container = $UI.get_node_or_null("EnemiesContainer")
	if not enemies_container:
		print("Warning: Enemies container not found")
		return

	var target_enemy_sprite = null
	var target_enemy_index = -1
	for i in range(enemies.size()):
		if enemies[i]["hp"] > 0:
			var enemy_vbox = enemies_container.get_node_or_null("Enemy%d" % i)
			if enemy_vbox:
				target_enemy_sprite = enemy_vbox.get_node_or_null("Sprite")
				target_enemy_index = i
				break

	if not target_enemy_sprite:
		print("Warning: No alive enemy sprite found for attack animation")
		return

	# Get ship center position in global coordinates
	var ship_center = ship_sprite.global_position + ship_sprite.size / 2

	# Get enemy center position
	var enemy_center = target_enemy_sprite.global_position + target_enemy_sprite.size / 2

	# Calculate angle to enemy
	var direction = enemy_center - ship_center
	var angle = direction.angle()

	# Store original rotation
	var original_rotation = ship_sprite.rotation

	# Rotate ship to face enemy
	var rotation_tween = create_tween()
	rotation_tween.tween_property(ship_sprite, "rotation", angle - PI/2, 0.15)  # -PI/2 because sprites face up by default
	await rotation_tween.finished

	# Create bullet
	var bullet = ColorRect.new()
	bullet.color = Color(1.0, 0.8, 0.2)  # Yellow/orange bullet
	bullet.size = Vector2(8, 8)
	bullet.position = ship_center - bullet.size / 2
	get_tree().root.add_child(bullet)

	# Animate bullet to enemy
	var bullet_tween = create_tween()
	bullet_tween.tween_property(bullet, "position", enemy_center - bullet.size / 2, 0.3)
	await bullet_tween.finished

	# Remove bullet
	bullet.queue_free()

	# Flash enemy
	var original_modulate = target_enemy_sprite.modulate
	for i in range(3):
		target_enemy_sprite.modulate = Color(2.0, 2.0, 2.0)  # Bright flash
		await get_tree().create_timer(0.05).timeout
		target_enemy_sprite.modulate = original_modulate
		await get_tree().create_timer(0.05).timeout

	# Rotate ship back to original position
	var return_tween = create_tween()
	return_tween.tween_property(ship_sprite, "rotation", original_rotation, 0.15)

func enemy_turn():
	# Process each enemy from left to right
	for enemy_index in range(enemies.size()):
		var enemy = enemies[enemy_index]

		# Get damage from attack pattern
		var attacks = [enemy["attack1"], enemy["attack2"], enemy["attack3"]]
		var base_damage = attacks[enemy["attack_index"]]

		# Cycle to next attack
		enemy["attack_index"] = (enemy["attack_index"] + 1) % 3

		show_notification("%s attacks for %d damage!" % [enemy["name"], base_damage])

		# Get all deployed ships, prioritizing front line
		var front_line_ships = []
		var back_line_ships = []

		for instance_id in deployed_ships.keys():
			var ship_data = deployed_ships[instance_id]
			if ship_data.get("is_front_line", false):
				front_line_ships.append(instance_id)
			else:
				back_line_ships.append(instance_id)

		# Target selection: front line first, then back line, then player
		var ship_instance_id = ""
		if front_line_ships.size() > 0:
			# Attack random front line ship
			ship_instance_id = front_line_ships[randi() % front_line_ships.size()]
		elif back_line_ships.size() > 0:
			# No front line ships, attack random back line ship
			ship_instance_id = back_line_ships[randi() % back_line_ships.size()]

		if ship_instance_id != "":

			if deployed_ships.has(ship_instance_id):
				var ship_data = deployed_ships[ship_instance_id]
				show_notification("%s attacks %s %s!" % [enemy["name"], ship_data["name"], ship_data["position"]])

				# Apply damage to ship (shield first, then armor)
				var remaining_damage = base_damage
				var original_shield = ship_data["shield"]
				var original_armor = ship_data["armor"]

				# Damage shield first
				if ship_data["shield"] > 0:
					var shield_damage = min(ship_data["shield"], remaining_damage)
					ship_data["shield"] -= shield_damage
					remaining_damage -= shield_damage
					show_notification("Shield absorbed %d damage (%d -> %d)" % [shield_damage, original_shield, ship_data["shield"]])

				# Then damage armor
				if remaining_damage > 0 and ship_data["armor"] > 0:
					var armor_damage = min(ship_data["armor"], remaining_damage)
					ship_data["armor"] -= armor_damage
					remaining_damage -= armor_damage
					show_notification("Armor absorbed %d damage (%d -> %d)" % [armor_damage, original_armor, ship_data["armor"]])

				# Check if ship is destroyed
				if ship_data["shield"] <= 0 and ship_data["armor"] <= 0:
					show_notification("%s %s destroyed!" % [ship_data["name"], ship_data["position"]])

					# Remove all attack cards from this ship
					remove_attack_cards_for_ship(ship_instance_id)

					# Find and remove card from hand if it exists
					var card_instance_id = ship_data.get("card_instance_id", "")
					if card_instance_id != "":
						for card in hand:
							if card.card_instance_id == card_instance_id:
								hand.erase(card)
								card.queue_free()
								break
						card_to_deployed_ship.erase(card_instance_id)

					# Remove ship from deployed list
					deployed_ships.erase(ship_instance_id)

					# Remove ship container
					var ships_vbox = $UI.get_node_or_null("ShipsContainer")
					if ships_vbox:
						var ship_container = ships_vbox.get_node_or_null(ship_instance_id)
						if ship_container:
							ship_container.queue_free()
					# Update UI
					update_deployed_ships_ui()
				else:
					# Ship survives - update card display with new stats if in hand
					var card_instance_id = ship_data.get("card_instance_id", "")
					if card_instance_id != "":
						for card in hand:
							if card.card_instance_id == card_instance_id:
								card.armor = ship_data["armor"]
								card.shield = ship_data["shield"]
								card.update_card_display()
								break
					# Update deployed ships UI
					update_deployed_ships_ui()
		else:
			# No deployed ships - attack player
			var damage = base_damage

			# Apply block if player has it
			if player_block > 0:
				damage = int(damage / 2.0)
				player_block = 0  # Consume block
				show_notification("Enemy attack reduced by block!")

			# Apply damage to shield first, then armor
			var remaining_damage = damage
			if player_shield > 0:
				var shield_damage = min(player_shield, remaining_damage)
				player_shield -= shield_damage
				remaining_damage -= shield_damage
				if shield_damage > 0:
					show_notification("Shield absorbed %d damage!" % shield_damage)

			if remaining_damage > 0:
				player_armor -= remaining_damage
				player_armor = max(0, player_armor)
				show_notification("Enemy dealt %d damage to armor!" % remaining_damage)

			# Check if player is defeated
			if player_armor <= 0 and player_shield <= 0:
				show_notification("You were defeated!")
				await get_tree().create_timer(2.0).timeout
				get_tree().reload_current_scene()
				return

		# Play attack animation for this enemy
		# TODO: Implement per-enemy attack animations
		# play_slime_attack_animation()
		await get_tree().create_timer(0.5).timeout
		update_ui()

	# After all enemies have attacked
	update_ui()

func remove_attack_cards_for_ship(ship_instance_id: String):
	# Remove attack cards from hand
	var cards_to_remove = []
	for card in hand:
		if card.source_ship_id == ship_instance_id:
			cards_to_remove.append(card)

	for card in cards_to_remove:
		hand.erase(card)
		card.queue_free()

	var removed_count = cards_to_remove.size()

	# Remove attack cards from draw pile
	var new_draw_pile: Array[Dictionary] = []
	for card_data in draw_pile:
		if card_data.get("source_ship_id", "") != ship_instance_id:
			new_draw_pile.append(card_data)
		else:
			removed_count += 1
	draw_pile = new_draw_pile

	# Remove attack cards from discard pile
	var new_discard_pile: Array[Dictionary] = []
	for card_data in discard_pile:
		if card_data.get("source_ship_id", "") != ship_instance_id:
			new_discard_pile.append(card_data)
		else:
			removed_count += 1
	discard_pile = new_discard_pile

	if removed_count > 0:
		show_notification("Removed %d attack cards from destroyed ship!" % removed_count)

func damage_enemy(damage: int, target_index: int = -1):
	# Attack specific enemy if targeted, otherwise attack first alive
	var target_enemy_index = -1

	if target_index >= 0 and target_index < enemies.size():
		# Specific enemy targeted
		if enemies[target_index]["hp"] > 0:
			target_enemy_index = target_index
	else:
		# Auto-target: find first alive enemy
		for i in range(enemies.size()):
			if enemies[i]["hp"] > 0:
				target_enemy_index = i
				break

	if target_enemy_index == -1:
		print("Warning: No alive enemies to damage!")
		return

	var enemy = enemies[target_enemy_index]
	enemy["hp"] -= damage
	enemy["hp"] = max(0, enemy["hp"])
	show_notification("%s took %d damage!" % [enemy["name"], damage])

	# Check if enemy died
	if enemy["hp"] <= 0:
		show_notification("%s defeated!" % enemy["name"])

		# Remove enemy UI
		var enemies_container = $UI.get_node_or_null("EnemiesContainer")
		if enemies_container:
			var enemy_vbox = enemies_container.get_node_or_null("Enemy%d" % target_enemy_index)
			if enemy_vbox:
				# Fade out animation
				var fade_tween = create_tween()
				fade_tween.tween_property(enemy_vbox, "modulate:a", 0.0, 0.3)
				await fade_tween.finished
				enemy_vbox.queue_free()

	update_ui()

func check_all_enemies_dead():
	# Check if all enemies are defeated
	for enemy in enemies:
		if enemy["hp"] > 0:
			return false

	# All enemies dead
	print("All enemies defeated! Restarting...")
	await get_tree().create_timer(1.0).timeout
	get_tree().reload_current_scene()
	return true

func update_ui():
	# Update HP label and bars
	if player_hp_label:
		player_hp_label.text = str(player_armor) + "/" + str(player_shield)

	# Calculate armor and shield percentages
	var armor_percentage = float(player_armor) / float(player_max_armor)
	var shield_percentage = float(player_shield) / float(player_max_shield)

	# Armor takes up 83.3% of the bar (50/60 total), shield takes 16.7% (10/60 total)
	if player_armor_bar:
		player_armor_bar.anchor_right = 0.833 * armor_percentage
	if player_shield_bar:
		player_shield_bar.anchor_left = 0.833
		player_shield_bar.anchor_right = 0.833 + (0.167 * shield_percentage)

	# Update enemy UIs
	var enemies_container = $UI.get_node_or_null("EnemiesContainer")
	if enemies_container:
		for i in range(enemies.size()):
			var enemy = enemies[i]
			var enemy_vbox = enemies_container.get_node_or_null("Enemy%d" % i)
			if enemy_vbox:
				var hp_label = enemy_vbox.get_node_or_null("HPLabel")
				if hp_label:
					hp_label.text = "HP: %d/%d" % [enemy["hp"], enemy["max_hp"]]
				var intent_label = enemy_vbox.get_node_or_null("IntentLabel")
				if intent_label:
					intent_label.text = "Intent: %s" % enemy["intent"]

	# Update energy icons (show/hide based on current energy)
	if energy_icon_1:
		energy_icon_1.visible = energy >= 1
		energy_icon_1.modulate.a = 1.0 if energy >= 1 else 0.3
	if energy_icon_2:
		energy_icon_2.visible = energy >= 2
		energy_icon_2.modulate.a = 1.0 if energy >= 2 else 0.3
	if energy_icon_3:
		energy_icon_3.visible = energy >= 3
		energy_icon_3.modulate.a = 1.0 if energy >= 3 else 0.3

	if draw_pile_label:
		draw_pile_label.text = "Draw: " + str(draw_pile.size())
	if discard_pile_label:
		discard_pile_label.text = "Discard: " + str(discard_pile.size())

func update_deployed_ships_ui():
	# Update health bars for all deployed ships
	var ships_vbox = $UI.get_node_or_null("ShipsContainer")
	if not ships_vbox:
		return

	for instance_id in deployed_ships.keys():
		var ship_data = deployed_ships[instance_id]
		var ship_container = ships_vbox.get_node_or_null(instance_id)
		if not ship_container:
			continue

		var health_container = ship_container.get_node_or_null("HealthBar")
		if not health_container:
			continue

		# Get current stats
		var armor = ship_data.get("armor", 0)
		var shield = ship_data.get("shield", 0)
		var total_hp = armor + shield

		# Update armor bar
		var armor_bar = health_container.get_node_or_null("ArmorBar")
		if armor_bar and total_hp > 0:
			var armor_width = 120.0 * (float(armor) / float(total_hp))
			armor_bar.size = Vector2(armor_width, 20)

		# Update shield bar
		var shield_bar = health_container.get_node_or_null("ShieldBar")
		if shield_bar and total_hp > 0:
			var armor_width = 120.0 * (float(armor) / float(total_hp))
			shield_bar.position = Vector2(armor_width, 0)
			shield_bar.size = Vector2(120.0 - armor_width, 20)

		# Update HP label
		var hp_label = health_container.get_node_or_null("HPLabel")
		if hp_label:
			hp_label.text = "%d/%d" % [total_hp, armor]

func _on_to_starmap():
	# Save combat state before leaving
	save_combat_state()
	get_tree().change_scene_to_file("res://scenes/StarMap.tscn")

func _on_deck_builder():
	# Save combat state before leaving
	save_combat_state()
	get_tree().change_scene_to_file("res://scenes/DeckBuilder.tscn")

func save_combat_state():
	# Save all card data from hand
	var hand_data: Array[Dictionary] = []
	for card in hand:
		var card_dict = {
			"name": card.card_name,
			"cost": card.cost,
			"description": card.description,
			"type": card.card_type,
			"armor": card.armor,
			"shield": card.shield,
			"is_deployed": card.is_deployed,
			"deployed_instance_id": card.deployed_instance_id,
			"ship_position": card.ship_position,
			"source_ship_id": card.source_ship_id,
			"card_instance_id": card.card_instance_id
		}
		hand_data.append(card_dict)

	var state = {
		"player_armor": player_armor,
		"player_max_armor": player_max_armor,
		"player_shield": player_shield,
		"player_max_shield": player_max_shield,
		"player_block": player_block,
		"enemies": enemies.duplicate(true),
		"energy": energy,
		"max_energy": max_energy,
		"draw_pile": draw_pile.duplicate(true),
		"hand": hand_data,
		"discard_pile": discard_pile.duplicate(true),
		"deployed_ships": deployed_ships.duplicate(true),
		"next_position_index": next_position_index,
		"card_instance_counter": card_instance_counter,
		"card_to_deployed_ship": card_to_deployed_ship.duplicate(true),
		"notification_history": notification_history.duplicate(true)
	}

	GameData.save_combat_state(state)

func restore_combat_state():
	var state = GameData.get_combat_state()

	# Restore basic stats
	player_armor = state.get("player_armor", 50)
	player_max_armor = state.get("player_max_armor", 50)
	player_shield = state.get("player_shield", 10)
	player_max_shield = state.get("player_max_shield", 10)
	player_block = state.get("player_block", 0)
	enemies = state.get("enemies", []).duplicate(true)
	energy = state.get("energy", 3)
	max_energy = state.get("max_energy", 3)

	# Recreate enemy UI after restoring enemies data
	if enemies.size() > 0:
		create_enemy_ui()

	# Restore card piles
	draw_pile = state.get("draw_pile", []).duplicate(true)
	discard_pile = state.get("discard_pile", []).duplicate(true)

	# Restore deployed ships data
	deployed_ships = state.get("deployed_ships", {}).duplicate(true)
	next_position_index = state.get("next_position_index", 0)
	card_instance_counter = state.get("card_instance_counter", 0)
	card_to_deployed_ship = state.get("card_to_deployed_ship", {}).duplicate(true)

	# Restore notification history
	notification_history = state.get("notification_history", []).duplicate(true)

	# Restore hand
	var hand_data = state.get("hand", [])
	for card_dict in hand_data:
		create_card_in_hand(card_dict)

	# Recreate ship sprites for deployed ships
	for ship_id in deployed_ships.keys():
		var ship_data = deployed_ships[ship_id]
		var ship_type = ship_data["ship_type"]
		var position_name = ship_data["position"]
		create_ship_sprite(ship_type, position_name, ship_id)

	# Update UI
	update_deployed_ships_ui()
	print("Combat state restored successfully")

func show_notification(message: String):
	# Add message to queue
	notification_queue.append(message)

	# Start displaying if not already showing
	if not is_showing_notification:
		display_next_notification()

func display_next_notification():
	if notification_queue.is_empty():
		is_showing_notification = false
		# Keep showing the last notification with history navigation available
		# Don't clear the notification, just unpause
		get_tree().paused = false
		return

	is_showing_notification = true
	# Pause the game
	get_tree().paused = true

	# Get next message and add to history
	var message = notification_queue.pop_front()
	notification_history.append(message)

	# Reset to show live notifications (not browsing history)
	current_history_index = -1

	# Update display
	update_notification_display()

	# Wait 1 second then show next
	await get_tree().create_timer(1.0, true, false, true).timeout
	display_next_notification()

func update_notification_display():
	# Determine which notification to show
	var display_index: int
	if current_history_index == -1:
		# Showing live notification (most recent)
		display_index = notification_history.size() - 1
	else:
		# Showing historical notification
		display_index = current_history_index

	# Show current notification
	if display_index >= 0 and display_index < notification_history.size():
		notification_label.text = notification_history[display_index]
	else:
		notification_label.text = ""

	# Show previous notification hint (if exists)
	if display_index > 0:
		previous_notification_label.text = notification_history[display_index - 1]
		previous_notification_label.visible = true
	else:
		previous_notification_label.text = ""
		previous_notification_label.visible = false

	# Show next notification hint (if exists)
	if display_index < notification_history.size() - 1:
		next_notification_label.text = notification_history[display_index + 1]
		next_notification_label.visible = true
	else:
		next_notification_label.text = ""
		next_notification_label.visible = false

	# Show help text only when there's history
	notification_help_label.visible = notification_history.size() > 1

func reposition_hand(animate: bool = true):
	if hand.is_empty():
		return

	var num_cards = hand.size()
	var container_width = hand_container.size.x
	var container_height = hand_container.size.y

	# Calculate dynamic spacing based on hand size
	var spacing = MAX_CARD_SPACING
	if num_cards > 1:
		var total_width_needed = CARD_WIDTH + (num_cards - 1) * MAX_CARD_SPACING
		if total_width_needed > container_width:
			# Need to compress spacing
			spacing = (container_width - CARD_WIDTH) / (num_cards - 1)
			spacing = max(spacing, MIN_CARD_SPACING)

	# Calculate total width of hand
	var total_width = CARD_WIDTH + (num_cards - 1) * spacing
	var start_x = (container_width - total_width) / 2

	# Position each card
	for i in range(num_cards):
		var card = hand[i]
		if card == hovered_card:
			continue  # Skip hovered card, it has special positioning

		var target_x = start_x + i * spacing
		var target_y = (container_height - card.size.y) / 2

		# Set z_index for layering (later cards on top)
		card.z_index = i

		if animate:
			# Smooth animation to new position
			var tween = create_tween()
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.set_ease(Tween.EASE_OUT)
			tween.tween_property(card, "position", Vector2(target_x, target_y), 0.2)
		else:
			card.position = Vector2(target_x, target_y)

func _on_card_hover_start(card: Card):
	if card.is_dragging:
		return

	hovered_card = card

	# Bring to front
	card.z_index = 1000

	# Calculate lifted position
	var num_cards = hand.size()
	var container_width = hand_container.size.x
	var container_height = hand_container.size.y

	var spacing = MAX_CARD_SPACING
	if num_cards > 1:
		var total_width_needed = CARD_WIDTH + (num_cards - 1) * MAX_CARD_SPACING
		if total_width_needed > container_width:
			spacing = (container_width - CARD_WIDTH) / (num_cards - 1)
			spacing = max(spacing, MIN_CARD_SPACING)

	var total_width = CARD_WIDTH + (num_cards - 1) * spacing
	var start_x = (container_width - total_width) / 2
	var card_index = hand.find(card)

	var target_x = start_x + card_index * spacing
	var target_y = (container_height - card.size.y) / 2 - HOVER_LIFT

	# Animate lift
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", Vector2(target_x, target_y), 0.15)

func _on_card_hover_end(card: Card):
	if card.is_dragging:
		return

	if hovered_card == card:
		hovered_card = null

	# Reposition back to normal
	reposition_hand(true)

func show_overflow_card(card_data: Dictionary):
	# Queue overflow card for display
	queue_card_display(card_data, "overflow")

func animate_card_to_discard(card: Card):
	# Animate card flying to discard pile zone
	var card_start_pos = card.global_position

	# Calculate target position (center of discard zone)
	var discard_global_pos = discard_pile_zone.global_position
	var discard_size = discard_pile_zone.size
	var target_pos = discard_global_pos + discard_size / 2 - card.size / 2

	# Bring card to front
	card.z_index = 500

	# Create animation tween
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)

	# Move to discard pile
	tween.tween_property(card, "global_position", target_pos, 0.4)

	# Shrink as it flies
	tween.tween_property(card, "scale", Vector2(0.5, 0.5), 0.4)

	# Fade out near the end
	tween.chain().tween_property(card, "modulate:a", 0.0, 0.1)

	await tween.finished

func queue_card_display(card_data: Dictionary, display_type: String = "normal"):
	# Add card to display queue
	display_queue.append({
		"card_data": card_data,
		"display_type": display_type  # "normal", "overflow", "tactical_command", etc.
	})

	# Start processing queue if not already displaying
	if not is_displaying_card:
		process_display_queue()

func process_display_queue():
	if display_queue.is_empty():
		is_displaying_card = false
		return

	is_displaying_card = true
	var queue_item = display_queue.pop_front()

	# Show the card in display zone
	await show_card_in_display_zone(queue_item["card_data"], queue_item["display_type"])

	# Check if card should be added to hand after display
	if queue_item.get("add_to_hand", false):
		create_card_in_hand(queue_item["card_data"])
		# Show notification that card was added to hand
		if queue_item["display_type"] == "attack_card":
			show_notification("Added %s to hand!" % queue_item["card_data"]["name"])

	# Wait before next card (shorter since card is already in hand now)
	await get_tree().create_timer(0.3).timeout

	# Process next card in queue
	process_display_queue()

func show_card_in_display_zone(card_data: Dictionary, display_type: String):
	# Create card instance
	var card_instance = CardScene.instantiate()
	card_display_zone.add_child(card_instance)

	# Setup card
	card_instance.setup(card_data, "display_temp")

	# Position in center of display zone
	var zone_size = card_display_zone.size
	var card_pos = Vector2(
		(zone_size.x - card_instance.size.x) / 2,
		(zone_size.y - card_instance.size.y) / 2 + 10  # +10 to account for label
	)
	card_instance.position = card_pos
	card_instance.z_index = 1000

	# Apply visual effects based on display type
	match display_type:
		"overflow":
			card_instance.modulate = Color(1.5, 0.5, 0.5)  # Red tint
		"tactical_command":
			card_instance.modulate = Color(1.5, 1.5, 0.8)  # Golden tint
		"attack_card":
			card_instance.modulate = Color(0.8, 1.2, 1.5)  # Blue tint
		_:
			card_instance.modulate = Color(1.2, 1.2, 1.2)  # Slight highlight

	# Fade in
	card_instance.modulate.a = 0.0
	var fade_in = create_tween()
	fade_in.tween_property(card_instance, "modulate:a", card_instance.modulate.a + 1.0, 0.2)
	await fade_in.finished

	# Wait for display duration (0.6 seconds)
	await get_tree().create_timer(0.6).timeout

	# Fade out
	var fade_out = create_tween()
	fade_out.tween_property(card_instance, "modulate:a", 0.0, 0.2)
	await fade_out.finished

	# Remove card
	card_instance.queue_free()

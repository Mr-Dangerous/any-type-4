extends Node2D

# Preload Card scene
const CardScene = preload("res://scenes/Card.tscn")

# Preload ship textures
const ScoutTexture = preload("res://assets/sprites/scout.svg")
const FighterTexture = preload("res://assets/sprites/fighter.svg")
const CorvetteTexture = preload("res://assets/sprites/corvette.svg")
const InterceptorTexture = preload("res://assets/sprites/interceptor.svg")

# Game state
var player_hp: int = 30
var player_max_hp: int = 30
var player_block: int = 0

var enemy_hp: int = 25
var enemy_max_hp: int = 25

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

# Track next available position index
var next_position_index: int = 0

# Counter for generating unique card instance IDs
var card_instance_counter: int = 0

# Map of card instance ID to deployed ship instance ID
var card_to_deployed_ship: Dictionary = {}

# UI nodes
@onready var player_hp_label: Label = $UI/PlayerInfo/PlayerHPLabel
@onready var enemy_hp_label: Label = $UI/EnemyInfo/EnemyHPLabel
@onready var energy_label: Label = $UI/PlayerInfo/EnergyLabel
@onready var hand_container: HBoxContainer = $UI/HandContainer
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var draw_pile_label: Label = $UI/PileInfo/DrawPileLabel
@onready var discard_pile_label: Label = $UI/PileInfo/DiscardPileLabel
@onready var player_block_label: Label = $UI/PlayerInfo/BlockLabel
@onready var to_starmap_button: Button = $UI/ToStarMapButton
@onready var deployed_ships_list: VBoxContainer = $UI/DeployedShips/ShipsList
@onready var notification_label: Label = $UI/NotificationLabel
@onready var previous_notification_label: Label = $UI/PreviousNotificationLabel
@onready var next_notification_label: Label = $UI/NextNotificationLabel
@onready var notification_help_label: Label = $UI/NotificationHelpLabel
@onready var slime_sprite: TextureRect = $UI/SlimeSprite
@onready var ships_container: Node2D = $UI/ShipsContainer

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

	# Connect buttons
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	to_starmap_button.pressed.connect(_on_to_starmap)

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

func initialize_deck():
	# Add 2 Scouts
	for i in range(2):
		draw_pile.append(card_database["scout"].duplicate())

	# Add 2 Corvettes
	for i in range(2):
		draw_pile.append(card_database["corvette"].duplicate())

	# Add 2 Interceptors
	for i in range(2):
		draw_pile.append(card_database["interceptor"].duplicate())

	# Add 3 Fighters
	for i in range(3):
		draw_pile.append(card_database["fighter"].duplicate())

	# Add 1 Shields Up
	draw_pile.append(card_database["shields_up"].duplicate())

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
		create_card_in_hand(card_data)

func create_card_in_hand(card_data: Dictionary):
	var card_instance = CardScene.instantiate()
	hand_container.add_child(card_instance)

	# Generate unique ID for this card instance
	card_instance_counter += 1
	var instance_id = "card_%d" % card_instance_counter

	card_instance.setup(card_data, instance_id)
	card_instance.card_played.connect(_on_card_played)

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

			card_instance.update_card_display()

	hand.append(card_instance)

func _on_card_played(card: Card):
	if energy >= card.cost:
		# Check if this is a ship card
		var is_ship = card.card_type in ["scout", "corvette", "interceptor", "fighter"]

		if is_ship:
			# Check if this specific card instance has been deployed
			if card_to_deployed_ship.has(card.card_instance_id):
				# Already deployed - use ship ability
				energy -= card.cost

				# Remove card from hand
				hand.erase(card)

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
				if card.card_type == "corvette":
					# Corvette ability: shuffle a Torpedo into the deck
					if card_database.has("torpedo"):
						var torpedo_card = card_database["torpedo"].duplicate()
						# Link torpedo to the corvette that created it
						torpedo_card["source_ship_id"] = card.deployed_instance_id
						draw_pile.append(torpedo_card)
						draw_pile.shuffle()
						show_notification("%s %s fired! Torpedo shuffled into deck!" % [card.card_name, card.ship_position])
					else:
						show_notification("%s %s discarded!" % [card.card_name, card.ship_position])
				else:
					# Scout, Fighter, Interceptor: dodge ability
					show_notification("%s %s dodges! Ship evades enemy attacks this turn." % [card.card_name, card.ship_position])

				# Update UI
				update_ui()
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

			# Check if enemy is dead
			check_enemy_death()
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
			enemy_hp -= 3
			enemy_hp = max(0, enemy_hp)
			show_notification("Scout attack dealt 3 damage!")

		"corvette_attack":
			# Play attack animation if ship exists
			if card.source_ship_id != "":
				await play_ship_attack_animation(card.source_ship_id)

			# Corvette attack - 5 damage
			enemy_hp -= 5
			enemy_hp = max(0, enemy_hp)
			show_notification("Corvette attack dealt 5 damage!")

		"interceptor_attack":
			# Play attack animation if ship exists
			if card.source_ship_id != "":
				await play_ship_attack_animation(card.source_ship_id)

			# Interceptor attack - 4 damage
			enemy_hp -= 4
			enemy_hp = max(0, enemy_hp)
			show_notification("Interceptor attack dealt 4 damage!")

		"fighter_attack":
			# Play attack animation if ship exists
			if card.source_ship_id != "":
				await play_ship_attack_animation(card.source_ship_id)

			# Fighter attack - 7 damage
			enemy_hp -= 7
			enemy_hp = max(0, enemy_hp)
			show_notification("Fighter attack dealt 7 damage!")

		"torpedo":
			# Play attack animation if ship exists
			if card.source_ship_id != "":
				await play_ship_attack_animation(card.source_ship_id)

			# Torpedo - 10 damage
			enemy_hp -= 10
			enemy_hp = max(0, enemy_hp)
			show_notification("Torpedo dealt 10 damage!")

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
			enemy_hp -= 5
			enemy_hp = max(0, enemy_hp)
			show_notification("Dealt 5 damage to enemy!")

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

	# Setup the deployed card with modified name
	deployed_card.setup(ship_data, card_instance_id)
	deployed_card.card_played.connect(_on_card_played)

	# Mark as deployed and add position
	deployed_card.is_deployed = true
	deployed_card.deployed_instance_id = instance_id
	deployed_card.ship_position = position

	# Update description based on ship type
	if ship_type == "corvette":
		deployed_card.description = "Discard to shuffle a Torpedo into your deck."
	else:
		# Scout, Fighter, Interceptor get dodge ability
		deployed_card.description = "Discard to dodge enemy attacks this turn."

	deployed_card.update_card_display()

	# Add to hand
	hand.append(deployed_card)

	# Mark ship as deployed with its stats and type
	deployed_ships[instance_id] = {
		"ship_type": ship_type,
		"position": position,
		"name": ship_data["name"],
		"armor": ship_data.get("armor", 0),
		"shield": ship_data.get("shield", 0),
		"card_instance_id": card_instance_id  # Link to the new card
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
			# Add attack card directly to hand with ship link
			var attack_card = card_database[attack_type].duplicate()
			attack_card["source_ship_id"] = instance_id  # Link to the ship that created this attack
			create_card_in_hand(attack_card)
			show_notification("Added %s to hand!" % attack_card["name"])

	# Create ship sprite
	create_ship_sprite(ship_type, position, instance_id)

	# Update deployed ships UI
	update_deployed_ships_ui()

func create_ship_sprite(ship_type: String, position_name: String, instance_id: String):
	# Create sprite
	var sprite = TextureRect.new()

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

	sprite.name = instance_id
	sprite.custom_minimum_size = Vector2(80, 80)
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Position underneath enemy (slime is at y=200-400, so position at y=420)
	var x_offset = 350 + ((next_position_index - 1) * 90)
	var y_offset = 420
	sprite.position = Vector2(x_offset, y_offset)

	ships_container.add_child(sprite)

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

	# Remove non-deployed cards from hand and UI
	for card in cards_to_remove:
		hand.erase(card)
		card.queue_free()

	print("Kept ", hand.size(), " deployed ships in hand for enemy turn")

	# Enemy turn (can attack deployed ships that are still in hand)
	enemy_turn()

	# Check if player is dead
	if player_hp <= 0:
		print("You died!")
		get_tree().reload_current_scene()
		return

	# After enemy turn, discard all remaining deployed ships
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

	# Remove deployed ships from hand and UI
	for card in cards_to_remove:
		hand.erase(card)
		card.queue_free()

	print("Discarded ", cards_to_remove.size(), " deployed ships after enemy turn")

	# Start new turn with fresh hand
	start_turn()

func play_slime_attack_animation():
	# Store original position
	var original_pos = slime_sprite.position

	# Create tween for attack animation
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)

	# Move forward (attack)
	tween.tween_property(slime_sprite, "position", original_pos + Vector2(0, 50), 0.2)
	# Move back (return)
	tween.tween_property(slime_sprite, "position", original_pos, 0.2)

func play_ship_attack_animation(source_ship_id: String):
	# Find the ship sprite
	var ship_sprite = ships_container.get_node_or_null(source_ship_id)
	if not ship_sprite:
		print("Warning: Ship sprite not found for attack animation: ", source_ship_id)
		return

	# Get ship center position in global coordinates
	var ship_center = ship_sprite.global_position + ship_sprite.size / 2

	# Get enemy center position
	var enemy_center = slime_sprite.global_position + slime_sprite.size / 2

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
	var original_modulate = slime_sprite.modulate
	for i in range(3):
		slime_sprite.modulate = Color(2.0, 2.0, 2.0)  # Bright flash
		await get_tree().create_timer(0.05).timeout
		slime_sprite.modulate = original_modulate
		await get_tree().create_timer(0.05).timeout

	# Rotate ship back to original position
	var return_tween = create_tween()
	return_tween.tween_property(ship_sprite, "rotation", original_rotation, 0.15)

func enemy_turn():
	var base_damage = 10

	# Get all deployed ships in hand
	var deployed_ships_in_hand = []
	for card in hand:
		if card.is_deployed:
			deployed_ships_in_hand.append(card)

	# Target selection: ships first, then player
	if deployed_ships_in_hand.size() > 0:
		# Randomly select a deployed ship to attack
		var target_card = deployed_ships_in_hand[randi() % deployed_ships_in_hand.size()]
		var ship_instance_id = target_card.deployed_instance_id

		if deployed_ships.has(ship_instance_id):
			var ship_data = deployed_ships[ship_instance_id]
			show_notification("Enemy attacks %s %s!" % [ship_data["name"], ship_data["position"]])

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

				# Remove ship from deployed list
				deployed_ships.erase(ship_instance_id)
				card_to_deployed_ship.erase(target_card.card_instance_id)
				# Remove card from hand
				hand.erase(target_card)
				target_card.queue_free()
				# Remove ship sprite
				var ship_sprite = ships_container.get_node_or_null(ship_instance_id)
				if ship_sprite:
					ship_sprite.queue_free()
				# Update UI
				update_deployed_ships_ui()
			else:
				# Ship survives - update card display with new stats
				target_card.armor = ship_data["armor"]
				target_card.shield = ship_data["shield"]
				target_card.update_card_display()
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

		player_hp -= damage
		player_hp = max(0, player_hp)
		show_notification("Enemy dealt %d damage to player!" % damage)
	# Play attack animation
	play_slime_attack_animation()
	await get_tree().create_timer(0.5).timeout
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

func check_enemy_death():
	if enemy_hp <= 0:
		print("Enemy defeated! Restarting...")
		await get_tree().create_timer(1.0).timeout
		get_tree().reload_current_scene()

func update_ui():
	player_hp_label.text = "HP: " + str(player_hp) + "/" + str(player_max_hp)
	enemy_hp_label.text = "HP: " + str(enemy_hp) + "/" + str(enemy_max_hp)
	energy_label.text = "Energy: " + str(energy) + "/" + str(max_energy)
	draw_pile_label.text = "Draw: " + str(draw_pile.size())
	discard_pile_label.text = "Discard: " + str(discard_pile.size())
	player_block_label.text = "Block: " + ("Active" if player_block > 0 else "None")

func update_deployed_ships_ui():
	# Clear existing ship displays
	for child in deployed_ships_list.get_children():
		child.queue_free()

	# Add each deployed ship instance
	for instance_id in deployed_ships.keys():
		var ship_data = deployed_ships[instance_id]

		# Create container for this ship
		var ship_container = VBoxContainer.new()
		ship_container.add_theme_constant_override("separation", 2)

		# Ship name label
		var ship_label = Label.new()
		ship_label.add_theme_font_size_override("font_size", 14)
		ship_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
		ship_label.text = "◆ %s %s" % [ship_data["name"], ship_data["position"]]
		ship_container.add_child(ship_label)

		# Health bar container (use Control for manual positioning)
		var health_bar_container = Control.new()
		health_bar_container.custom_minimum_size = Vector2(150, 20)

		# Background bar
		var bg_bar = ColorRect.new()
		bg_bar.color = Color(0.2, 0.2, 0.2, 1.0)
		bg_bar.size = Vector2(150, 20)
		bg_bar.position = Vector2(0, 0)
		health_bar_container.add_child(bg_bar)

		# Get current stats from card_database for max values
		var max_armor = card_database[ship_data["ship_type"]]["armor"]
		var max_shield = card_database[ship_data["ship_type"]]["shield"]
		var max_total = max_armor + max_shield
		var current_armor = ship_data["armor"]
		var current_shield = ship_data["shield"]

		# Calculate bar widths
		var bar_width = 150.0
		var armor_width = (float(current_armor) / float(max_total)) * bar_width
		var shield_width = (float(current_shield) / float(max_total)) * bar_width

		# Armor bar (red) - positioned at start
		var armor_bar = ColorRect.new()
		armor_bar.color = Color(0.9, 0.2, 0.2, 1.0)  # Red
		armor_bar.size = Vector2(armor_width, 20)
		armor_bar.position = Vector2(0, 0)
		health_bar_container.add_child(armor_bar)

		# Shield bar (blue) - positioned after armor
		var shield_bar = ColorRect.new()
		shield_bar.color = Color(0.2, 0.5, 1.0, 1.0)  # Blue
		shield_bar.size = Vector2(shield_width, 20)
		shield_bar.position = Vector2(armor_width, 0)
		health_bar_container.add_child(shield_bar)

		# Stats text overlay
		var stats_label = Label.new()
		stats_label.add_theme_font_size_override("font_size", 11)
		stats_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		stats_label.text = "A:%d S:%d" % [current_armor, current_shield]
		stats_label.position = Vector2(5, 2)
		health_bar_container.add_child(stats_label)

		ship_container.add_child(health_bar_container)
		deployed_ships_list.add_child(ship_container)

func _on_to_starmap():
	get_tree().change_scene_to_file("res://scenes/StarMap.tscn")

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

extends Node2D

# Tactical view combat system with 3 horizontal lanes

# Lane configuration
const NUM_LANES = 3
const LANE_Y_START = 200.0
const LANE_SPACING = 150.0

# Position constants
const MOTHERSHIP_X = 100.0
const ENEMY_SPAWN_X = 1000.0
const SHIP_DEPLOY_X_START = 280.0  # Where first ship deploys
const SHIP_SPACING = 40.0  # Horizontal spacing between ships in same lane

# Ship size classes (width in pixels)
const SIZE_TINY = 20  # 32-48 range, using middle value
const SIZE_SMALL = 24  # 40-56 range, using middle value
const SIZE_MEDIUM = 36  # 48-64 range, using middle value
const SIZE_LARGE = 48  # 64-128 range, using middle value
const SIZE_EXTRA_LARGE = 80  # 128-192 range, using middle value

# Ship data is now loaded from card_database/ship_database.csv via ShipDatabase singleton
# SHIP_SIZES, SHIP_DEPLOY_SPEED, and SHIP_STATS have been removed
# Use ShipDatabase.get_ship_data(ship_id) to access ship properties

# Preload ship textures
const MothershipTexture = preload("res://assets/Ships/illum_default/s_illum_default_24.png")
const InterceptorTexture = preload("res://assets/Ships/illum_default/s_illum_default_23.png")
const FighterTexture = preload("res://assets/Ships/illum_default/s_illum_default_19.png")
const FrigateTexture = preload("res://assets/Ships/illum_default/s_illum_default_01.png")

# Preload enemy textures
const MookTexture = preload("res://assets/Ships/alien/s_alien_09.png")
const EliteTexture = preload("res://assets/Ships/alien/s_alien_05.png")

# Preload UI textures
const CloseButtonTexture = preload("res://assets/UI/Close_BTN/Close_BTN.png")

# Preload background textures
const Space2Texture = preload("res://assets/Backgrounds/Space2/Bright/Space2.png")
const Stones1Texture = preload("res://assets/Backgrounds/Space2/Bright/stones1.png")

# Preload combat effects
const LaserTexture = preload("res://assets/Effects/laser_light/s_laser_light_001.png")

# Game state
var lanes: Array[Dictionary] = []  # Each lane can contain units
var selected_ship_type: String = ""  # Currently selected ship for deployment
var ship_selection_panel: Panel = null
var deploy_button: Button = null

var selected_enemy_type: String = ""  # Currently selected enemy for deployment
var enemy_selection_panel: Panel = null
var deploy_enemy_button: Button = null
var is_zoomed: bool = false
var zoomed_lane_index: int = -1
var camera: Camera2D = null
var return_button: TextureButton = null
var ui_layer: CanvasLayer = null

# Combat state
var selected_attacker: Dictionary = {}  # Ship that will attack
var selected_target: Dictionary = {}  # Ship being targeted

# Auto-combat state
var auto_combat_active: bool = false
var auto_combat_button: Button = null

# Turn-based combat state
var turn_mode_active: bool = false
var current_turn_phase: String = "tactical"  # tactical, lane_0, lane_1, lane_2
var turn_progression_button: Button = null
var waiting_for_combat_start: bool = false

# Auto-deploy button
var auto_deploy_button: Button = null

# Combat pause system
var combat_paused: bool = true  # Start paused in tactical view
var zoom_timer: Timer = null
var zoom_timer_label: Label = null

# Idle behavior constants
const DRIFT_DISTANCE = 10.0  # How far ships drift backward
const DRIFT_DURATION = 8.0  # How long drift takes (very slow)
const DRIFT_DELAY = 3.0  # Delay before starting drift
const RETURN_DURATION = 2.0  # How long return takes

# Background variables
var bg_scroll_direction: Vector2 = Vector2(1, 0)  # Direction of parallax scroll
var bg_scroll_speed: float = 10.0  # Pixels per second
var bg_tile_size: float = 1.0  # Scale multiplier for Space2.png tiles
var parallax_offset: Vector2 = Vector2.ZERO  # Current parallax offset

# Background nodes
var space_background: Node2D = null
var parallax_background: Node2D = null

func _ready():
	# Hide the existing solid background so we can see our space backgrounds
	var old_background = get_node_or_null("Background")
	if old_background:
		old_background.visible = false

	# Setup backgrounds first (render behind everything)
	setup_backgrounds()

	# Setup camera
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.enabled = true
	camera.position = Vector2(576, 324)  # Center of 1152x648 screen
	add_child(camera)

	# Get the UI CanvasLayer from the scene
	ui_layer = get_node("UI")

	# Setup resource UI
	setup_resource_ui()

	# Initialize lanes
	initialize_lanes()

	# Setup mothership
	setup_mothership()

	# Setup enemy spawner
	setup_enemy_spawner()

	# Setup deployment UI
	setup_deployment_ui()

	# Setup enemy deployment UI (for testing)
	setup_enemy_deployment_ui()

	# Setup return button (initially hidden)
	setup_return_button()

	# Setup auto-combat button
	setup_auto_combat_button()

	# Setup auto-deploy button
	setup_auto_deploy_button()

	# Setup zoom timer label
	setup_zoom_timer_label()

	# Setup turn progression button
	setup_turn_progression_button()

	print("Combat_2 initialized with tactical view")

func _process(delta):
	# Update parallax background scrolling
	if parallax_background:
		parallax_offset += bg_scroll_direction.normalized() * bg_scroll_speed * delta

		# Get texture size for wrapping
		var tex_width = Stones1Texture.get_width()
		var tex_height = Stones1Texture.get_height()

		# Wrap the offset to create seamless loop
		if parallax_offset.x > tex_width:
			parallax_offset.x -= tex_width
		elif parallax_offset.x < -tex_width:
			parallax_offset.x += tex_width

		if parallax_offset.y > tex_height:
			parallax_offset.y -= tex_height
		elif parallax_offset.y < -tex_height:
			parallax_offset.y += tex_height

		# Update all parallax sprite positions
		for child in parallax_background.get_children():
			if child is Sprite2D:
				var base_pos = child.get_meta("base_position")
				child.position = base_pos + parallax_offset

	# Update zoom timer label
	if zoom_timer and zoom_timer_label and zoom_timer_label.visible:
		var time_left = zoom_timer.time_left
		zoom_timer_label.text = "LANE %d: %ds" % [zoomed_lane_index + 1, ceil(time_left)]

func setup_backgrounds():
	# Create static space background (tiled)
	space_background = Node2D.new()
	space_background.name = "SpaceBackground"
	space_background.z_index = -100
	add_child(space_background)

	# Tile Space2.png across the screen
	var screen_size = Vector2(1152, 648)
	var tex_size = Space2Texture.get_size() * bg_tile_size
	var tiles_x = ceil(screen_size.x / tex_size.x) + 1
	var tiles_y = ceil(screen_size.y / tex_size.y) + 1

	print("Creating space background tiles: ", tiles_x, "x", tiles_y)
	print("Space2 texture size: ", Space2Texture.get_size())

	for x in range(tiles_x):
		for y in range(tiles_y):
			var sprite = Sprite2D.new()
			sprite.texture = Space2Texture
			sprite.scale = Vector2(bg_tile_size, bg_tile_size)
			sprite.position = Vector2(x * tex_size.x, y * tex_size.y)
			sprite.centered = false
			sprite.z_index = -100  # Ensure it's behind
			space_background.add_child(sprite)

	# Create parallax background (stones1 scrolling)
	parallax_background = Node2D.new()
	parallax_background.name = "ParallaxBackground"
	parallax_background.z_index = -50
	add_child(parallax_background)

	# Create a 3x3 grid of stones for seamless scrolling
	var stones_tex_size = Stones1Texture.get_size()
	print("Creating parallax stones, texture size: ", stones_tex_size)

	for x in range(-1, 2):
		for y in range(-1, 2):
			var sprite = Sprite2D.new()
			sprite.texture = Stones1Texture
			sprite.centered = false
			sprite.modulate.a = 0.7  # Make slightly transparent
			var base_pos = Vector2(x * stones_tex_size.x, y * stones_tex_size.y)
			sprite.position = base_pos
			sprite.z_index = -50
			sprite.set_meta("base_position", base_pos)
			parallax_background.add_child(sprite)

	print("Backgrounds created - Space at z:-100, Parallax at z:-50")

func update_background_tiles():
	# Rebuild space background with new tile size
	if space_background:
		# Clear old tiles
		for child in space_background.get_children():
			child.queue_free()

		# Create new tiles
		var screen_size = Vector2(1152, 648)
		var tex_size = Space2Texture.get_size() * bg_tile_size
		var tiles_x = ceil(screen_size.x / tex_size.x) + 1
		var tiles_y = ceil(screen_size.y / tex_size.y) + 1

		for x in range(tiles_x):
			for y in range(tiles_y):
				var sprite = Sprite2D.new()
				sprite.texture = Space2Texture
				sprite.scale = Vector2(bg_tile_size, bg_tile_size)
				sprite.position = Vector2(x * tex_size.x, y * tex_size.y)
				sprite.centered = false
				space_background.add_child(sprite)

func initialize_lanes():
	# Create 3 lanes
	for i in range(NUM_LANES):
		var lane = {
			"index": i,
			"y_position": LANE_Y_START + (i * LANE_SPACING),
			"units": []
		}
		lanes.append(lane)

		# Create visual lane markers
		create_lane_marker(i, lane["y_position"])

func create_lane_marker(lane_index: int, y_pos: float):
	# Create a rectangle to visualize the lane
	var lane_height = 128.0
	var lane_start_x = MOTHERSHIP_X + 150  # Offset after mothership
	var lane_width = ENEMY_SPAWN_X - lane_start_x - 50  # Extend to near enemy spawner

	var lane_rect = ColorRect.new()
	lane_rect.name = "Lane_%d" % lane_index
	lane_rect.position = Vector2(lane_start_x, y_pos - lane_height / 2)
	lane_rect.size = Vector2(lane_width, lane_height)
	lane_rect.color = Color(0.2, 0.4, 0.8, 0.35)  # Semi-transparent blue
	add_child(lane_rect)

	# Add border
	var border = ReferenceRect.new()
	border.border_color = Color(0.3, 0.5, 1.0, 0.9)
	border.border_width = 3.0
	border.size = lane_rect.size
	lane_rect.add_child(border)

	# Add lane label
	var label = Label.new()
	label.name = "LaneLabel_%d" % lane_index
	label.text = "Lane %d" % (lane_index + 1)
	label.position = Vector2(10, (lane_height - 24) / 2)  # Center vertically
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.8))
	lane_rect.add_child(label)

func setup_mothership():
	# Create mothership sprite on the left side
	var mothership_container = Control.new()
	mothership_container.name = "Mothership"
	mothership_container.position = Vector2(MOTHERSHIP_X, get_viewport_rect().size.y / 2 - 100)
	add_child(mothership_container)

	# Add sprite
	var sprite = TextureRect.new()
	sprite.name = "Sprite"
	sprite.texture = MothershipTexture
	sprite.custom_minimum_size = Vector2(150, 150)
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mothership_container.add_child(sprite)

	# Add label
	var label = Label.new()
	label.name = "Label"
	label.text = "MOTHERSHIP"
	label.position = Vector2(0, 160)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.3, 0.8, 1, 1))
	mothership_container.add_child(label)

	print("Mothership created at x=", MOTHERSHIP_X)

func setup_enemy_spawner():
	# Create enemy spawner placeholder on the right side
	var spawner_container = Control.new()
	spawner_container.name = "EnemySpawner"
	spawner_container.position = Vector2(ENEMY_SPAWN_X, get_viewport_rect().size.y / 2 - 100)
	add_child(spawner_container)

	# Add visual indicator (placeholder box)
	var indicator = ColorRect.new()
	indicator.name = "SpawnerIndicator"
	indicator.color = Color(0.8, 0.2, 0.2, 0.5)
	indicator.size = Vector2(100, 100)
	spawner_container.add_child(indicator)

	# Add label
	var label = Label.new()
	label.name = "Label"
	label.text = "ENEMY\nSPAWNER"
	label.position = Vector2(-20, 110)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2, 1))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spawner_container.add_child(label)

	print("Enemy spawner created at x=", ENEMY_SPAWN_X)

func setup_resource_ui():
	# Create resource UI display
	var resource_ui = Control.new()
	resource_ui.name = "ResourceUI"
	var script = load("res://scripts/ResourceUI.gd")
	resource_ui.set_script(script)
	resource_ui.position = Vector2(20, 20)
	ui_layer.add_child(resource_ui)
	print("Resource UI created at top-left")

func setup_enemy_deployment_ui():
	# Create deploy enemy button (for testing)
	deploy_enemy_button = Button.new()
	deploy_enemy_button.name = "DeployEnemyButton"
	deploy_enemy_button.text = "DEPLOY ENEMY"
	deploy_enemy_button.position = Vector2(920, 80)  # Below player deploy button
	deploy_enemy_button.size = Vector2(200, 50)
	deploy_enemy_button.add_theme_font_size_override("font_size", 18)
	deploy_enemy_button.pressed.connect(_on_deploy_enemy_button_pressed)
	add_child(deploy_enemy_button)

	# Get enemy ships from database
	var enemy_ships = ShipDatabase.get_ships_by_faction("enemy")

	# Calculate panel height based on number of enemies
	var button_height = 50
	var button_spacing = 10
	var title_height = 60
	var close_button_height = 40
	var panel_height = title_height + (enemy_ships.size() * (button_height + button_spacing)) + close_button_height + 20

	# Create enemy selection panel (initially hidden)
	enemy_selection_panel = Panel.new()
	enemy_selection_panel.name = "EnemySelectionPanel"
	enemy_selection_panel.position = Vector2(350, 150)
	enemy_selection_panel.size = Vector2(450, panel_height)
	enemy_selection_panel.visible = false
	add_child(enemy_selection_panel)

	# Add panel background
	var bg = ColorRect.new()
	bg.color = Color(0.2, 0.15, 0.15, 0.95)
	bg.size = enemy_selection_panel.size
	enemy_selection_panel.add_child(bg)

	# Add title
	var title = Label.new()
	title.text = "SELECT ENEMY TO DEPLOY"
	title.position = Vector2(20, 20)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
	enemy_selection_panel.add_child(title)

	# Create enemy selection buttons dynamically from database
	for i in range(enemy_ships.size()):
		var enemy_data = enemy_ships[i]
		var enemy_id = enemy_data["ship_id"]
		var display_name = enemy_data["display_name"]
		var sprite_path = enemy_data["sprite_path"]
		var enemy_size = enemy_data["size"]

		var button_y = title_height + (i * (button_height + button_spacing))

		var enemy_button = Button.new()
		enemy_button.name = enemy_id + "_button"
		enemy_button.position = Vector2(20, button_y)
		enemy_button.size = Vector2(410, button_height)
		enemy_button.text = display_name
		enemy_button.add_theme_font_size_override("font_size", 20)
		enemy_button.pressed.connect(_on_enemy_selected.bind(enemy_id))
		enemy_selection_panel.add_child(enemy_button)

		# Add enemy icon to button
		var icon = TextureRect.new()
		icon.texture = load(sprite_path)
		var icon_y = (button_height - enemy_size) / 2
		icon.position = Vector2(10, icon_y)
		icon.custom_minimum_size = Vector2(enemy_size, enemy_size)
		icon.size = Vector2(enemy_size, enemy_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		enemy_button.add_child(icon)

	# Add close button at bottom
	var close_button_y = panel_height - close_button_height - 10
	var close_button = Button.new()
	close_button.text = "CANCEL"
	close_button.position = Vector2(150, close_button_y)
	close_button.size = Vector2(150, 30)
	close_button.pressed.connect(_on_close_enemy_panel)
	enemy_selection_panel.add_child(close_button)

func _on_deploy_enemy_button_pressed():
	# Show enemy selection panel
	enemy_selection_panel.visible = true
	print("Deploy enemy button pressed - showing enemy selection")

func _on_enemy_selected(enemy_type: String):
	# Store selected enemy type
	selected_enemy_type = enemy_type
	enemy_selection_panel.visible = false
	print("Selected enemy: ", enemy_type, " - Click a lane to deploy")

func _on_close_enemy_panel():
	# Hide panel and clear selection
	enemy_selection_panel.visible = false
	selected_enemy_type = ""
	print("Enemy selection cancelled")

func setup_deployment_ui():
	# Create deploy ships button in top-right corner
	deploy_button = Button.new()
	deploy_button.name = "DeployButton"
	deploy_button.text = "DEPLOY SHIP"
	deploy_button.position = Vector2(920, 20)
	deploy_button.size = Vector2(200, 50)
	deploy_button.add_theme_font_size_override("font_size", 18)
	deploy_button.pressed.connect(_on_deploy_button_pressed)
	add_child(deploy_button)

	# Get player ships from database
	var player_ships = ShipDatabase.get_ships_by_faction("player")

	# Calculate panel height based on number of ships
	var button_height = 70
	var button_spacing = 10
	var title_height = 60
	var close_button_height = 40
	var panel_height = title_height + (player_ships.size() * (button_height + button_spacing)) + close_button_height + 20

	# Create ship selection panel (initially hidden)
	ship_selection_panel = Panel.new()
	ship_selection_panel.name = "ShipSelectionPanel"
	ship_selection_panel.position = Vector2(350, 150)
	ship_selection_panel.size = Vector2(450, panel_height)
	ship_selection_panel.visible = false
	add_child(ship_selection_panel)

	# Add panel background
	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.2, 0.95)
	bg.size = ship_selection_panel.size
	ship_selection_panel.add_child(bg)

	# Add title
	var title = Label.new()
	title.text = "SELECT SHIP TO DEPLOY"
	title.position = Vector2(20, 20)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 1, 1))
	ship_selection_panel.add_child(title)

	# Create ship selection buttons dynamically from database
	for i in range(player_ships.size()):
		var ship_data = player_ships[i]
		var ship_id = ship_data["ship_id"]
		var display_name = ship_data["display_name"]
		var sprite_path = ship_data["sprite_path"]
		var ship_size = ship_data["size"]

		var button_y = title_height + (i * (button_height + button_spacing))

		var ship_button = Button.new()
		ship_button.name = ship_id + "_button"
		ship_button.position = Vector2(20, button_y)
		ship_button.size = Vector2(410, button_height)
		ship_button.text = display_name
		ship_button.add_theme_font_size_override("font_size", 20)
		ship_button.pressed.connect(_on_ship_selected.bind(ship_id))
		ship_selection_panel.add_child(ship_button)

		# Add ship icon to button
		var icon = TextureRect.new()
		icon.texture = load(sprite_path)
		# Center the icon vertically in the button
		var icon_y = (button_height - ship_size) / 2
		icon.position = Vector2(10, icon_y)
		icon.custom_minimum_size = Vector2(ship_size, ship_size)
		icon.size = Vector2(ship_size, ship_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ship_button.add_child(icon)

	# Add close button at bottom
	var close_button_y = panel_height - close_button_height - 10
	var close_button = Button.new()
	close_button.text = "CANCEL"
	close_button.position = Vector2(150, close_button_y)
	close_button.size = Vector2(150, 30)
	close_button.pressed.connect(_on_close_panel)
	ship_selection_panel.add_child(close_button)

func _on_deploy_button_pressed():
	# Show ship selection panel
	ship_selection_panel.visible = true
	print("Deploy button pressed - showing ship selection")

func _on_ship_selected(ship_type: String):
	# Store selected ship type
	selected_ship_type = ship_type
	ship_selection_panel.visible = false
	print("Selected ship: ", ship_type, " - Click a lane to deploy")

	# Visual feedback - change cursor or add indicator
	# Player should now click a lane to deploy

func _on_close_panel():
	# Hide panel and clear selection
	ship_selection_panel.visible = false
	selected_ship_type = ""
	print("Ship selection cancelled")

func _input(event):
	# Handle escape key to return to tactical view
	if event.is_action_pressed("ui_cancel") and is_zoomed:
		_on_return_to_tactical()
		get_viewport().set_input_as_handled()
		return

	# Handle lane click for ship deployment or zoom
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Don't process if clicking on UI elements
		if ship_selection_panel.visible or enemy_selection_panel.visible:
			return

		var mouse_pos = get_global_mouse_position()
		var lane_index = get_lane_at_position(mouse_pos)

		if selected_ship_type != "":
			# Ship selected - deploy to lane
			if lane_index != -1:
				deploy_ship_to_lane(selected_ship_type, lane_index)
				selected_ship_type = ""  # Clear selection after deployment
		elif selected_enemy_type != "":
			# Enemy selected - deploy to lane
			if lane_index != -1:
				deploy_enemy_to_lane(selected_enemy_type, lane_index)
				selected_enemy_type = ""  # Clear selection after deployment
		else:
			# In tactical view (paused): prioritize lane zoom
			# But prevent manual zoom when turn mode is active
			if combat_paused and not is_zoomed and lane_index != -1 and not turn_mode_active:
				# Tactical view - zoom into lane
				zoom_to_lane(lane_index)
			elif is_zoomed:
				# Zoomed view - allow unit clicking for combat
				var clicked_unit = get_unit_at_position(mouse_pos)
				if clicked_unit != null and not clicked_unit.is_empty():
					handle_unit_click(clicked_unit)

func get_lane_at_position(pos: Vector2) -> int:
	# Determine which lane a position is in
	for i in range(NUM_LANES):
		var lane_y = lanes[i]["y_position"]
		# Check if mouse is within 75 pixels above or below lane center
		if abs(pos.y - lane_y) < 75:
			return i
	return -1

func get_unit_at_position(pos: Vector2) -> Dictionary:
	# Check if mouse position intersects with any unit (ship or enemy)
	for lane in lanes:
		for unit in lane["units"]:
			if not unit.has("container") or not unit.has("size"):
				print("Warning: Invalid unit data in lane")
				continue

			var container = unit["container"]
			var unit_size = unit["size"]
			var unit_pos = container.position

			# Create bounding box for unit
			var box_x1 = unit_pos.x
			var box_y1 = unit_pos.y
			var box_x2 = unit_pos.x + unit_size
			var box_y2 = unit_pos.y + unit_size

			# Check if mouse is inside bounding box
			if pos.x >= box_x1 and pos.x <= box_x2 and pos.y >= box_y1 and pos.y <= box_y2:
				print("Found unit at position - type: ", unit.get("type", "unknown"), ", is_enemy: ", unit.get("is_enemy", false))
				return unit

	return {}  # Return empty dictionary if no unit found

func handle_unit_click(unit: Dictionary):
	# Handle clicking on a unit for combat
	# Now works for both player->enemy and enemy->player combat
	if unit.is_empty():
		print("Error: handle_unit_click called with empty unit")
		return

	var is_enemy = unit.get("is_enemy", false)
	print("Handling unit click - is_enemy: ", is_enemy)

	# First click: Select attacker (any unit)
	if selected_attacker.is_empty():
		select_attacker(unit)
		return

	# Clicking the same unit: Deselect
	if selected_attacker == unit:
		deselect_attacker()
		return

	# Check if this is a valid target
	var attacker_is_enemy = selected_attacker.get("is_enemy", false)
	var target_is_enemy = unit.get("is_enemy", false)

	# Valid targeting: attacker and target must be on opposite sides
	if attacker_is_enemy != target_is_enemy:
		# Valid target - start attacking
		select_target(unit)
	else:
		# Same side - switch to new attacker
		deselect_attacker()
		select_attacker(unit)

func select_attacker(unit: Dictionary):
	# Select any unit as the attacker (player ship or enemy)
	if unit.is_empty():
		print("Error: Attempted to select empty unit")
		return

	selected_attacker = unit
	var unit_type = unit.get("type", "unknown")
	var is_enemy = unit.get("is_enemy", false)
	print("Selected attacker: ", unit_type, " (enemy: ", is_enemy, ")")

	# Visual feedback - different colors for player vs enemy
	if unit.has("sprite"):
		var sprite = unit["sprite"]
		if is_enemy:
			sprite.modulate = Color(1.5, 0.5, 0.5)  # Red tint for enemy attackers
		else:
			sprite.modulate = Color(1.2, 1.2, 1.0)  # Yellow tint for player attackers
	else:
		print("Warning: Unit has no sprite")

func deselect_attacker():
	# Deselect the current attacker and stop attacking
	if not selected_attacker.is_empty():
		print("Deselected attacker")

		# Remove visual feedback
		var sprite = selected_attacker["sprite"]
		sprite.modulate = Color(1, 1, 1)  # Reset to normal

		# Stop attack timer if it exists
		stop_continuous_attack()

		selected_attacker = {}
		selected_target = {}

func select_target(unit: Dictionary):
	# Select an enemy as the target
	selected_target = unit
	print("Selected target: ", unit["type"])

	# Start attacking
	start_attack_sequence()

func deploy_ship_to_lane(ship_type: String, lane_index: int):
	# Deploy a ship to the specified lane
	print("Deploying ", ship_type, " to lane ", lane_index)

	# Get ship data from database
	var db_ship_data = ShipDatabase.get_ship_data(ship_type)
	if db_ship_data.is_empty():
		print("ERROR: Ship type '", ship_type, "' not found in database")
		return

	# Extract ship properties from database
	var ship_texture: Texture2D = load(db_ship_data["sprite_path"])
	var ship_size: int = db_ship_data["size"]
	var deploy_duration: float = db_ship_data.get("deploy_speed", 3.0)  # Default 3.0s if not specified

	# Calculate target position
	var num_ships_in_lane = lanes[lane_index]["units"].size()
	var target_x = SHIP_DEPLOY_X_START + (num_ships_in_lane * SHIP_SPACING)

	# Calculate Y position with vertical stagger to prevent overlap
	var lane_center_y = lanes[lane_index]["y_position"]

	# Create vertical offset pattern based on ship index
	var vertical_positions = [
		-30,  # Upper part of lane
		0,    # Center of lane
		30    # Lower part of lane
	]
	var y_offset = vertical_positions[num_ships_in_lane % 3]

	# Add additional random offset based on ship size for more natural stagger
	var random_offset = randf_range(-ship_size * 0.3, ship_size * 0.3)
	var target_y = lane_center_y + y_offset + random_offset - (ship_size / 2)

	# Create ship sprite at mothership position
	var ship_container = Control.new()
	ship_container.name = ship_type + "_" + str(Time.get_ticks_msec())

	# Get mothership center position - all ships spawn from same point
	var mothership = get_node_or_null("Mothership")
	var mothership_center_y = get_viewport_rect().size.y / 2  # Screen center
	var start_pos: Vector2
	if mothership:
		# Center on mothership sprite
		start_pos = Vector2(mothership.position.x + 75, mothership_center_y - (ship_size / 2))
	else:
		start_pos = Vector2(MOTHERSHIP_X + 75, mothership_center_y - (ship_size / 2))

	ship_container.position = start_pos
	add_child(ship_container)

	var sprite = TextureRect.new()
	sprite.name = "Sprite"
	sprite.texture = ship_texture
	sprite.custom_minimum_size = Vector2(ship_size, ship_size)
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Set pivot for rotation
	sprite.pivot_offset = Vector2(ship_size / 2, ship_size / 2)
	sprite.rotation = -PI / 2  # Start pointing up/north
	ship_container.add_child(sprite)

	# Calculate rotation angle to target
	var direction = Vector2(target_x, target_y) - start_pos
	var target_rotation = direction.angle()  # No offset needed, 0° is correct

	# Position animation: ease out for acceleration, ease in for braking
	# Split into two parts: accelerate then brake
	var halfway_pos = start_pos.lerp(Vector2(target_x, target_y), 0.5)

	# First half: accelerate (ease out)
	var tween_accel = create_tween()
	tween_accel.set_trans(Tween.TRANS_CUBIC)
	tween_accel.set_ease(Tween.EASE_OUT)
	tween_accel.tween_property(ship_container, "position", halfway_pos, deploy_duration * 0.4)

	# Rotation: quick rotation at the start (run parallel with acceleration)
	var tween_rotation = create_tween()
	tween_rotation.set_trans(Tween.TRANS_BACK)
	tween_rotation.set_ease(Tween.EASE_OUT)
	tween_rotation.tween_property(sprite, "rotation", target_rotation, deploy_duration * 0.3)

	# Wait for acceleration phase
	await tween_accel.finished

	# Second half: brake (ease in)
	var tween_brake = create_tween()
	tween_brake.set_trans(Tween.TRANS_CUBIC)
	tween_brake.set_ease(Tween.EASE_IN)
	tween_brake.tween_property(ship_container, "position", Vector2(target_x, target_y), deploy_duration * 0.6)

	# Wait for braking to complete
	await tween_brake.finished

	# Store original position for idle behavior
	var ship_data = {
		"type": ship_type,
		"container": ship_container,
		"sprite": sprite,
		"size": ship_size,
		"original_position": Vector2(target_x, target_y),
		"idle_state": "waiting",  # States: waiting, drifting, returning
		"idle_timer": 0.0,

		# Combat stats
		"stats": db_ship_data["stats"].duplicate(),
		"current_armor": db_ship_data["stats"]["armor"],
		"current_shield": db_ship_data["stats"]["shield"],
		"current_energy": db_ship_data["stats"]["starting_energy"],

		# Ability data
		"ability_function": db_ship_data.get("ability_function", ""),
		"ability_name": db_ship_data.get("abilty", ""),
		"ability_description": db_ship_data.get("ability_description", "")
	}

	# Add to lane data
	lanes[lane_index]["units"].append(ship_data)

	# Create health bar
	create_health_bar(ship_container, ship_size, ship_data["current_shield"], ship_data["current_armor"])

	# Initialize energy bar
	update_energy_bar(ship_data)

	# Start idle behavior
	start_ship_idle_behavior(ship_data)

	print("Ship deployed successfully at x=", target_x, " y=", target_y, " with size=", ship_size, " | Stats: Armor=", ship_data["current_armor"], " Shield=", ship_data["current_shield"], " AttackSpeed=", ship_data["stats"]["attack_speed"])

func deploy_enemy_to_lane(enemy_type: String, lane_index: int):
	# Deploy an enemy to the specified lane
	print("Deploying ", enemy_type, " to lane ", lane_index)

	# Get enemy data from database
	var db_enemy_data = ShipDatabase.get_ship_data(enemy_type)
	if db_enemy_data.is_empty():
		print("ERROR: Enemy type '", enemy_type, "' not found in database")
		return

	# Extract enemy properties from database
	var enemy_texture: Texture2D = load(db_enemy_data["sprite_path"])
	var enemy_size: int = db_enemy_data["size"]

	# Count enemies in the same lane to calculate horizontal position
	var enemies_in_lane = 0
	for unit in lanes[lane_index]["units"]:
		if unit.get("is_enemy", false):
			enemies_in_lane += 1

	var lane_y = lanes[lane_index]["y_position"]

	# Position enemies on the right side (near enemy spawner)
	# Start from enemy spawner and move left with spacing
	var x_pos = ENEMY_SPAWN_X - 100 - (enemies_in_lane * 60)  # 60px spacing for enemies

	# Calculate Y position with vertical stagger (same as player ships)
	var vertical_positions = [
		-30,  # Upper part of lane
		0,    # Center of lane
		30    # Lower part of lane
	]
	var y_offset = vertical_positions[enemies_in_lane % 3]
	var random_offset = randf_range(-enemy_size * 0.3, enemy_size * 0.3)
	var target_y = lane_y + y_offset + random_offset - (enemy_size / 2)

	# Create enemy sprite container
	var enemy_container = Control.new()
	enemy_container.name = enemy_type + "_enemy_" + str(Time.get_ticks_msec())
	enemy_container.position = Vector2(x_pos, target_y)
	add_child(enemy_container)

	var sprite = TextureRect.new()
	sprite.name = "Sprite"
	sprite.texture = enemy_texture
	sprite.custom_minimum_size = Vector2(enemy_size, enemy_size)
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Rotate enemy to face left (toward player)
	sprite.pivot_offset = Vector2(enemy_size / 2, enemy_size / 2)
	sprite.rotation = PI  # 180 degrees to face left

	enemy_container.add_child(sprite)

	# Create enemy data
	var enemy_data = {
		"type": enemy_type,
		"container": enemy_container,
		"sprite": sprite,
		"size": enemy_size,
		"is_enemy": true,
		"position": Vector2(x_pos, target_y),

		# Combat stats
		"stats": db_enemy_data["stats"].duplicate(),
		"current_armor": db_enemy_data["stats"]["armor"],
		"current_shield": db_enemy_data["stats"]["shield"],
		"current_energy": db_enemy_data["stats"]["starting_energy"],

		# Ability data
		"ability_function": db_enemy_data.get("ability_function", ""),
		"ability_name": db_enemy_data.get("abilty", ""),
		"ability_description": db_enemy_data.get("ability_description", "")
	}

	# Add to lane data
	lanes[lane_index]["units"].append(enemy_data)

	# Create health bar
	create_health_bar(enemy_container, enemy_size, enemy_data["current_shield"], enemy_data["current_armor"])

	# Initialize energy bar
	update_energy_bar(enemy_data)

	print("Enemy deployed successfully at x=", x_pos, " y=", target_y, " with size=", enemy_size, " | Stats: Armor=", db_enemy_data["stats"]["armor"], " Shield=", db_enemy_data["stats"]["shield"], " AttackSpeed=", db_enemy_data["stats"]["attack_speed"])

func start_ship_idle_behavior(ship_data: Dictionary):
	# Initial rotation to face enemy
	var sprite = ship_data["sprite"]
	var ship_container = ship_data["container"]

	# Calculate angle to enemy spawner
	var ship_pos = ship_data["original_position"]
	var enemy_pos = Vector2(ENEMY_SPAWN_X, ship_pos.y)  # Enemy at same lane height
	var direction_to_enemy = enemy_pos - ship_pos
	var target_rotation = direction_to_enemy.angle()  # No offset needed

	# Smoothly rotate to face enemy
	var rotate_tween = create_tween()
	rotate_tween.set_trans(Tween.TRANS_SINE)
	rotate_tween.set_ease(Tween.EASE_IN_OUT)
	rotate_tween.tween_property(sprite, "rotation", target_rotation, 1.5)

	# Start idle cycle after delay
	await get_tree().create_timer(DRIFT_DELAY).timeout

	# Check if ship still exists
	if not is_instance_valid(ship_container):
		return

	idle_cycle(ship_data)

func idle_cycle(ship_data: Dictionary):
	while is_instance_valid(ship_data["container"]):
		# Drift backward phase
		ship_data["idle_state"] = "drifting"
		await drift_backward(ship_data)

		if not is_instance_valid(ship_data["container"]):
			return

		# Short pause
		await get_tree().create_timer(0.5).timeout

		if not is_instance_valid(ship_data["container"]):
			return

		# Return to position phase
		ship_data["idle_state"] = "returning"
		await return_to_position(ship_data)

		if not is_instance_valid(ship_data["container"]):
			return

		# Wait before next cycle
		ship_data["idle_state"] = "waiting"
		await get_tree().create_timer(DRIFT_DELAY).timeout

func drift_backward(ship_data: Dictionary) -> void:
	var ship_container = ship_data["container"]
	var original_pos = ship_data["original_position"]

	# Drift slowly toward mothership
	var drift_target = Vector2(original_pos.x - DRIFT_DISTANCE, original_pos.y)

	var drift_tween = create_tween()
	drift_tween.set_trans(Tween.TRANS_SINE)
	drift_tween.set_ease(Tween.EASE_IN_OUT)
	drift_tween.tween_property(ship_container, "position", drift_target, DRIFT_DURATION)

	await drift_tween.finished

func return_to_position(ship_data: Dictionary) -> void:
	var ship_container = ship_data["container"]
	var sprite = ship_data["sprite"]
	var original_pos = ship_data["original_position"]

	# Brief acceleration back to position
	var return_tween = create_tween()
	return_tween.set_trans(Tween.TRANS_CUBIC)
	return_tween.set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(ship_container, "position", original_pos, RETURN_DURATION)

	# Slight rotation adjustment (subtle wobble)
	var current_rotation = sprite.rotation
	var wobble_rotation = current_rotation + deg_to_rad(randf_range(-3, 3))
	var sprite_tween = create_tween()
	sprite_tween.set_trans(Tween.TRANS_SINE)
	sprite_tween.set_ease(Tween.EASE_IN_OUT)
	sprite_tween.tween_property(sprite, "rotation", wobble_rotation, RETURN_DURATION * 0.3)
	sprite_tween.tween_property(sprite, "rotation", current_rotation, RETURN_DURATION * 0.7)

	await return_tween.finished

func setup_return_button():
	# Create close button to return to tactical view (initially hidden)
	return_button = TextureButton.new()
	return_button.name = "ReturnButton"
	return_button.texture_normal = CloseButtonTexture
	return_button.position = Vector2(1110, 10)
	return_button.custom_minimum_size = Vector2(30, 30)
	return_button.ignore_texture_size = true
	return_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	return_button.visible = false
	return_button.pressed.connect(_on_return_to_tactical)

	# Add to UI layer so it's not affected by camera zoom
	ui_layer.add_child(return_button)

func setup_auto_combat_button():
	# Create auto-combat button
	auto_combat_button = Button.new()
	auto_combat_button.name = "AutoCombatButton"
	auto_combat_button.text = "START AUTO-COMBAT"
	auto_combat_button.position = Vector2(450, 20)
	auto_combat_button.size = Vector2(250, 50)
	auto_combat_button.add_theme_font_size_override("font_size", 18)
	auto_combat_button.pressed.connect(_on_auto_combat_toggled)
	add_child(auto_combat_button)

func setup_auto_deploy_button():
	# Create auto-deploy button
	auto_deploy_button = Button.new()
	auto_deploy_button.name = "AutoDeployButton"
	auto_deploy_button.text = "AUTO-DEPLOY"
	auto_deploy_button.position = Vector2(450, 80)  # Below auto-combat button
	auto_deploy_button.size = Vector2(250, 50)
	auto_deploy_button.add_theme_font_size_override("font_size", 18)
	auto_deploy_button.pressed.connect(_on_auto_deploy_pressed)
	add_child(auto_deploy_button)

func setup_zoom_timer_label():
	# Create zoom timer countdown label
	zoom_timer_label = Label.new()
	zoom_timer_label.name = "ZoomTimerLabel"
	zoom_timer_label.text = "LANE 1: 5s"
	zoom_timer_label.position = Vector2(400, 150)  # Top center, below other buttons
	zoom_timer_label.add_theme_font_size_override("font_size", 28)
	zoom_timer_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))  # Bright yellow/gold
	zoom_timer_label.visible = false  # Hidden by default

	# Add to UI layer so it's not affected by camera zoom
	ui_layer.add_child(zoom_timer_label)

func setup_turn_progression_button():
	# Create turn progression button in bottom-right corner
	turn_progression_button = Button.new()
	turn_progression_button.name = "TurnProgressionButton"
	turn_progression_button.text = "Proceed to Lane 1"
	turn_progression_button.position = Vector2(850, 580)  # Bottom-right
	turn_progression_button.size = Vector2(280, 50)
	turn_progression_button.add_theme_font_size_override("font_size", 20)
	turn_progression_button.visible = false  # Hidden until turn mode starts
	turn_progression_button.pressed.connect(_on_turn_progression_pressed)

	# Add to UI layer so it's not affected by camera zoom
	ui_layer.add_child(turn_progression_button)

func _on_auto_deploy_pressed():
	# Auto-deploy player ships and enemies
	print("Auto-deploying ships and enemies...")

	# Deploy player ships
	# Lane 1 (index 0): Interceptor
	deploy_ship_to_lane("basic_interceptor", 0)

	# Lane 2 (index 1): Fighter
	deploy_ship_to_lane("basic_fighter", 1)

	# Lane 3 (index 2): Frigate
	deploy_ship_to_lane("basic_shield_frigate", 2)

	# Wait a moment for player ships to start deploying
	await get_tree().create_timer(0.5).timeout

	# Deploy enemies: 1 mook and 1 elite in each lane
	for lane_idx in range(3):
		deploy_enemy_to_lane("mook", lane_idx)
		deploy_enemy_to_lane("elite", lane_idx)

	print("Auto-deploy complete!")

func zoom_to_lane(lane_index: int):
	# Zoom camera to focus on specific lane
	print("Zooming to lane ", lane_index)
	is_zoomed = true
	zoomed_lane_index = lane_index

	# Calculate camera position to center on lane
	var lane_y = lanes[lane_index]["y_position"]
	var target_position = Vector2(576, lane_y)  # Center of screen width (1152/2)

	# Animate camera zoom
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "position", target_position, 0.5)
	tween.tween_property(camera, "zoom", Vector2(1.5, 1.5), 0.5)

	# Show return button (only if not in turn mode)
	if not turn_mode_active:
		return_button.visible = true

	# Hide deploy buttons while zoomed
	deploy_button.visible = false
	deploy_enemy_button.visible = false
	auto_deploy_button.visible = false

	# Move ships in this lane into combat positions and wait for completion
	await move_lane_ships_forward(lane_index)

	# In turn mode, wait for player to click "Start Combat"
	# In normal mode, start combat immediately
	if not turn_mode_active:
		# Unpause combat for this lane
		combat_paused = false
		print("Combat UNPAUSED - lane active")

		# Start combat for all ships in this lane
		start_lane_combat(lane_index)

		# Start 5-second timer to auto-return (AFTER ships are in position)
		start_zoom_timer()
	else:
		print("Zoomed to lane ", lane_index, " - waiting for player to start combat")

func _on_return_to_tactical():
	# Return to tactical view
	print("Returning to tactical view")

	# Cancel zoom timer if active
	stop_zoom_timer()

	# Hide timer label
	if zoom_timer_label:
		zoom_timer_label.visible = false

	# Pause combat
	combat_paused = true
	print("Combat PAUSED - tactical view")

	# Stop combat for the zoomed lane
	var prev_lane_index = zoomed_lane_index
	if prev_lane_index != -1:
		stop_lane_combat(prev_lane_index)
		# Return ships to their formation positions
		return_lane_ships_to_formation(prev_lane_index)

	is_zoomed = false
	zoomed_lane_index = -1

	# Animate camera back to default (center of screen)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "position", Vector2(576, 324), 0.5)
	tween.tween_property(camera, "zoom", Vector2(1.0, 1.0), 0.5)

	# Hide return button
	return_button.visible = false

	# Show deploy buttons again
	deploy_button.visible = true
	deploy_enemy_button.visible = true
	auto_deploy_button.visible = true

# Lane ship movement functions

func move_lane_ships_forward(lane_index: int):
	# Move all ships in lane to combat positions (player ships forward, enemies toward player)
	if lane_index < 0 or lane_index >= lanes.size():
		return

	var lane = lanes[lane_index]
	var movement_tweens = []

	for unit in lane["units"]:
		if not unit.has("container"):
			continue

		var container = unit["container"]
		var current_pos = container.position
		var is_enemy = unit.get("is_enemy", false)

		# Save original position for returning later
		unit["zoom_original_position"] = current_pos

		# Determine movement direction:
		# Player ships move forward (+200px to right)
		# Enemy ships move backward (-200px to left, toward player)
		var offset = -200 if is_enemy else 200
		var target_pos = Vector2(current_pos.x + offset, current_pos.y)

		# Animate movement
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(container, "position", target_pos, 0.5)
		movement_tweens.append(tween)

	print("Moved ships in lane ", lane_index, " into combat positions")

	# Wait for all tweens to complete
	if movement_tweens.size() > 0:
		# Wait for the first tween (they all have same duration)
		await movement_tweens[0].finished

func return_lane_ships_to_formation(lane_index: int):
	# Return all ships in lane to their formation positions
	if lane_index < 0 or lane_index >= lanes.size():
		return

	var lane = lanes[lane_index]
	for unit in lane["units"]:
		if not unit.has("container") or not unit.has("zoom_original_position"):
			continue

		var container = unit["container"]
		var original_pos = unit["zoom_original_position"]

		# Animate movement back
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(container, "position", original_pos, 0.5)

		# Clear saved position
		unit.erase("zoom_original_position")

	print("Returned ships in lane ", lane_index, " to formation")

func start_zoom_timer():
	# Start 5-second timer for auto-return to tactical view
	if zoom_timer:
		zoom_timer.queue_free()

	zoom_timer = Timer.new()
	zoom_timer.name = "ZoomTimer"
	zoom_timer.wait_time = 5.0
	zoom_timer.one_shot = true
	zoom_timer.timeout.connect(_on_zoom_timer_timeout)
	add_child(zoom_timer)
	zoom_timer.start()

	# Show and initialize timer label
	if zoom_timer_label:
		zoom_timer_label.text = "LANE %d: 5s" % [zoomed_lane_index + 1]
		zoom_timer_label.visible = true

	print("Started 5-second zoom timer")

func stop_zoom_timer():
	# Stop and remove zoom timer
	if zoom_timer:
		zoom_timer.stop()
		zoom_timer.queue_free()
		zoom_timer = null

func _on_zoom_timer_timeout():
	# Handle zoom timer expiring
	if turn_mode_active:
		# In turn mode - progress to next phase
		print("Zoom timer expired - combat phase complete")
		on_combat_phase_complete()
	else:
		# Normal mode - auto-return to tactical view
		print("Zoom timer expired - auto-returning to tactical view")
		_on_return_to_tactical()

# Combat system functions

func start_attack_sequence():
	# Begin the attack sequence: rotate ship, then fire
	if selected_attacker.is_empty() or selected_target.is_empty():
		return

	# Don't allow manual combat in paused state
	if combat_paused:
		print("Combat is paused - cannot start manual attack")
		return

	print("Starting attack sequence")

	# First, rotate to face target
	rotate_ship_to_target()

	# Fire immediately after rotation completes (0.3s delay)
	await get_tree().create_timer(0.3).timeout

	# Fire the first shot
	fire_laser()

	# Start continuous attack timer
	start_continuous_attack()

func rotate_ship_to_target():
	# Rotate attacker to face the target
	if selected_attacker.is_empty() or selected_target.is_empty():
		return

	var attacker_sprite = selected_attacker["sprite"]
	var attacker_pos = selected_attacker["container"].position
	var attacker_size = selected_attacker["size"]
	var target_pos = selected_target["container"].position
	var target_size = selected_target["size"]

	# Calculate center positions
	var attacker_center = attacker_pos + Vector2(attacker_size / 2, attacker_size / 2)
	var target_center = target_pos + Vector2(target_size / 2, target_size / 2)

	# Calculate angle to target
	var direction = target_center - attacker_center
	var target_rotation = direction.angle()

	# Smoothly rotate to target
	var tween = create_tween()
	tween.tween_property(attacker_sprite, "rotation", target_rotation, 0.3)

	print("Rotating attacker to face target")

func fire_laser():
	# Fire laser projectiles from attacker to target
	# Number of projectiles based on ship's num_attacks stat
	if selected_attacker.is_empty() or selected_target.is_empty():
		return

	var num_attacks = selected_attacker["stats"]["num_attacks"]
	print("Firing ", num_attacks, " projectile(s)")

	# Fire multiple projectiles with slight spacing
	for i in range(num_attacks):
		if i > 0:
			# Add small delay between projectiles (0.05s)
			await get_tree().create_timer(0.05).timeout
		fire_single_laser()

	# Gain energy after attack (2-4 random)
	gain_energy(selected_attacker)

func fire_single_laser():
	# Fire a single laser projectile from attacker to target
	if selected_attacker.is_empty() or selected_target.is_empty():
		return

	var attacker_pos = selected_attacker["container"].position
	var attacker_size = selected_attacker["size"]
	var target_pos = selected_target["container"].position
	var target_size = selected_target["size"]

	# Calculate center positions
	var start_pos = attacker_pos + Vector2(attacker_size / 2, attacker_size / 2)
	var end_pos = target_pos + Vector2(target_size / 2, target_size / 2)

	# Calculate direction and angle
	var direction = end_pos - start_pos
	var angle = direction.angle()

	# Create laser sprite (small projectile)
	var laser = Sprite2D.new()
	laser.texture = LaserTexture
	laser.position = start_pos
	laser.rotation = angle
	laser.z_index = 1  # Above ships
	add_child(laser)

	# Scale laser to be 6 pixels tall
	var laser_height = LaserTexture.get_height()
	var scale_y = 6.0 / laser_height
	laser.scale = Vector2(scale_y, scale_y)  # Uniform scale to maintain aspect ratio

	# Center the sprite
	laser.offset = Vector2(-LaserTexture.get_width() / 2, -LaserTexture.get_height() / 2)

	# Animate laser: fly quickly to target (0.2 seconds)
	var flight_duration = 0.2
	var tween = create_tween()
	tween.tween_property(laser, "position", end_pos, flight_duration)
	tween.tween_callback(func():
		# Hit the target
		on_laser_hit(laser)
	)

func on_laser_hit(laser: Sprite2D):
	# Handle laser hitting the target
	# Remove the laser projectile
	laser.queue_free()

	# Calculate and apply damage
	if not selected_attacker.is_empty() and not selected_target.is_empty():
		var damage_dealt = calculate_damage(selected_attacker, selected_target)
		if damage_dealt > 0:
			apply_damage(selected_target, damage_dealt)

	# Flash the target
	if not selected_target.is_empty() and selected_target.has("sprite"):
		var target_sprite = selected_target["sprite"]

		# Create flash animation - white flash then back to normal
		var flash_tween = create_tween()
		flash_tween.tween_property(target_sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.05)  # Flash white
		flash_tween.tween_property(target_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)   # Return to normal

func calculate_damage(attacker: Dictionary, target: Dictionary) -> int:
	# Calculate damage from attacker to target
	# Returns 0 if attack misses, otherwise returns damage amount

	if attacker.is_empty() or target.is_empty():
		return 0

	# Get stats
	var attacker_accuracy = attacker["stats"].get("accuracy", 0)
	var attacker_damage = attacker["stats"].get("damage", 0)
	var target_evasion = target["stats"].get("evasion", 0)
	var target_reinforced = target["stats"].get("reinforced_armor", 0)

	# Hit chance calculation: accuracy / (accuracy + evasion)

	var hit_chance = 1.0
	hit_chance -= (target_evasion*.01)
	if hit_chance < 0:
		hit_chance = 0
	
	var crit_chance = 1.0-((attacker_accuracy)*.01)
	var crit_roll = randf()
	var critical_hit = false
	if crit_roll > crit_chance:
		critical_hit = true
	if (critical_hit):
		#it has a chance to negate a crit via a critical hit of its own.  so if a ship has 15 reinforced, then it has a 15% chance to negate any critical hit against it and reduce it to a normal hit
		print("crit!")
	# Roll for hit/miss
	var roll = randf()  # Random float between 0.0 and 1.0
	if roll > hit_chance:
		print("MISS! (rolled ", roll, " vs hit chance ", hit_chance, ")")
		return 0  # Attack missed

	# Hit! Calculate damage
	var base_damage = attacker_damage

	# Apply reinforced armor reduction (reduces damage by %)
	# reinforced_armor of 10 = 10% damage reduction
	# reinforced_armor of 50 = 50% damage reduction
	var damage_multiplier = 1.0 - (float(target_reinforced) / 100.0)
	damage_multiplier = max(0.0, damage_multiplier)  # Can't go below 0

	var final_damage = int(base_damage * damage_multiplier)
	if (critical_hit):
		final_damage*=2
	final_damage = max(1, final_damage)  # Always do at least 1 damage on hit

	print("HIT! Damage: ", final_damage, " (base: ", base_damage, ", armor reduction: ", target_reinforced, "%)")
	return final_damage

func apply_damage(target: Dictionary, damage: int):
	# Apply damage to target's shields first, then armor
	if target.is_empty():
		return

	var remaining_damage = damage

	# Damage shields first
	if target.has("current_shield") and target["current_shield"] > 0:
		var shield_damage = min(target["current_shield"], remaining_damage)
		target["current_shield"] -= shield_damage
		remaining_damage -= shield_damage
		print("  Shield damaged: -", shield_damage, " (", target["current_shield"], " remaining)")

	# Overflow damage goes to armor
	if remaining_damage > 0 and target.has("current_armor"):
		var armor_damage = min(target["current_armor"], remaining_damage)
		target["current_armor"] -= armor_damage
		print("  Armor damaged: -", armor_damage, " (", target["current_armor"], " remaining)")

	# Update health bar
	update_health_bar(target)

	# Check if ship is destroyed
	var total_health = target.get("current_armor", 0) + target.get("current_shield", 0)
	if total_health <= 0:
		print("  SHIP DESTROYED!")
		destroy_ship(target)

func start_continuous_attack():
	# Start attack cycle - attacks happen at attack_speed per second
	if selected_attacker.is_empty() or selected_target.is_empty():
		return

	# Calculate attack interval: 1 / attack_speed = seconds per attack
	# attack_speed of 1.5 = 1.5 attacks/second = 0.667s per attack
	# attack_speed of 0.3 = 0.3 attacks/second = 3.333s per attack
	# attack_speed of 10 = 10 attacks/second = 0.1s per attack
	var attack_speed = selected_attacker["stats"]["attack_speed"]
	var attack_interval = 1.0 / attack_speed

	# Start attack cycle
	attack_cycle(selected_attacker, selected_target, attack_interval)

	print("Started continuous attack - attack speed: ", attack_speed, " attacks/sec (", attack_interval, "s per attack)")

func attack_cycle(attacker: Dictionary, target: Dictionary, attack_interval: float):
	# Continuous attack cycle
	while not attacker.is_empty() and not target.is_empty():
		# Stop if combat is paused
		if combat_paused:
			print("Attack cycle stopped - combat paused")
			break

		# Check if still attacking same target
		if selected_attacker != attacker or selected_target != target:
			break

		# Fire all projectiles in this attack
		await fire_laser()

		# Wait for cooldown (timer resets AFTER last projectile fires)
		await get_tree().create_timer(attack_interval).timeout

		# Check if units still exist
		if not is_instance_valid(attacker.get("container")) or not is_instance_valid(target.get("container")):
			break

func _on_attack_timer_timeout():
	# Legacy callback - no longer used
	pass

func stop_continuous_attack():
	# Stop the continuous attack timer
	if selected_attacker.is_empty():
		return

	var container = selected_attacker["container"]
	var timer = container.get_node_or_null("AttackTimer")

	if timer:
		timer.stop()
		timer.queue_free()
		print("Stopped continuous attack")

func destroy_ship(ship: Dictionary):
	# Destroy a ship when its health reaches 0
	if ship.is_empty():
		return

	var ship_type = ship.get("type", "unknown")
	var is_enemy = ship.get("is_enemy", false)
	print("Destroying ship: ", ship_type, " (enemy: ", is_enemy, ")")

	# Clear selections if this ship was selected
	if selected_attacker == ship:
		deselect_attacker()
	if selected_target == ship:
		selected_target = {}

	# Stop any attack timer on this ship
	if ship.has("container"):
		var container = ship["container"]
		var timer = container.get_node_or_null("AttackTimer")
		if timer:
			timer.stop()
			timer.queue_free()

		# TODO: Play destruction animation/effect here
		# For now, just remove immediately
		container.queue_free()

	# Remove ship from its lane
	for lane in lanes:
		var index = lane["units"].find(ship)
		if index != -1:
			lane["units"].remove_at(index)
			print("Ship removed from lane ", lane["index"])
			break

	# In auto-combat, reassign targets for any ships that were targeting this destroyed ship
	if auto_combat_active:
		for lane in lanes:
			for unit in lane["units"]:
				if unit.get("auto_target") == ship:
					assign_random_target(unit)

# Auto-combat functions

func _on_auto_combat_toggled():
	# Toggle turn-based combat mode
	turn_mode_active = !turn_mode_active

	if turn_mode_active:
		auto_combat_button.text = "STOP TURN MODE"
		start_turn_mode()
		print("Turn mode STARTED")
	else:
		auto_combat_button.text = "START AUTO-COMBAT"
		stop_turn_mode()
		print("Turn mode STOPPED")

# Turn-based combat functions

func start_turn_mode():
	# Start turn-based combat mode
	current_turn_phase = "tactical"
	waiting_for_combat_start = false

	# Show turn progression button
	if turn_progression_button:
		turn_progression_button.text = "Proceed to Lane 1"
		turn_progression_button.visible = true

	# Hide return button in turn mode (no manual returns allowed)
	if return_button:
		return_button.visible = false

	print("Turn mode started - Tactical phase")

func stop_turn_mode():
	# Stop turn-based combat mode
	turn_mode_active = false
	current_turn_phase = "tactical"
	waiting_for_combat_start = false

	# Hide turn progression button
	if turn_progression_button:
		turn_progression_button.visible = false

	# Stop any active combat
	if is_zoomed:
		_on_return_to_tactical()

	print("Turn mode stopped")

func _on_turn_progression_pressed():
	# Handle turn progression button press
	if waiting_for_combat_start:
		# Player clicked "Start Combat" - begin the combat phase
		start_combat_phase()
	else:
		# Player clicked "Proceed to Lane X" - zoom to the next lane
		proceed_to_next_lane()

func proceed_to_next_lane():
	# Zoom to the appropriate lane based on current phase
	var target_lane = -1

	if current_turn_phase == "tactical":
		target_lane = 0
		current_turn_phase = "lane_0"
	elif current_turn_phase == "lane_0":
		target_lane = 1
		current_turn_phase = "lane_1"
	elif current_turn_phase == "lane_1":
		target_lane = 2
		current_turn_phase = "lane_2"

	if target_lane >= 0:
		# Zoom to the lane
		zoom_to_lane(target_lane)

		# Update button to "Start Combat"
		waiting_for_combat_start = true
		if turn_progression_button:
			turn_progression_button.text = "Start Combat"

func start_combat_phase():
	# Start combat in the current zoomed lane
	if not is_zoomed or zoomed_lane_index < 0:
		print("ERROR: Trying to start combat but not zoomed into a lane")
		return

	# Hide the button during combat
	if turn_progression_button:
		turn_progression_button.visible = false

	waiting_for_combat_start = false

	# Unpause combat
	combat_paused = false
	print("Combat UNPAUSED - lane active")

	# Start lane combat (this will assign targets and begin attacks)
	start_lane_combat(zoomed_lane_index)

	# Start 5-second timer
	start_zoom_timer()

	print("Combat started for lane ", zoomed_lane_index)

func on_combat_phase_complete():
	# Called when combat timer expires - move to next phase
	print("Combat phase complete for lane ", zoomed_lane_index)

	# Determine next action based on current phase
	if current_turn_phase == "lane_0":
		# Move to lane 1
		proceed_to_lane_transition(1, "lane_1")
	elif current_turn_phase == "lane_1":
		# Move to lane 2
		proceed_to_lane_transition(2, "lane_2")
	elif current_turn_phase == "lane_2":
		# All lanes complete - return to tactical
		return_to_tactical_phase()

func proceed_to_lane_transition(next_lane_index: int, next_phase: String):
	# Transition to the next lane
	print("Transitioning to lane ", next_lane_index)

	# Stop current lane combat
	stop_lane_combat(zoomed_lane_index)

	# Update phase
	current_turn_phase = next_phase

	# Zoom to next lane
	zoom_to_lane(next_lane_index)

	# Show button and wait for player
	waiting_for_combat_start = true
	if turn_progression_button:
		turn_progression_button.text = "Start Combat"
		turn_progression_button.visible = true

func return_to_tactical_phase():
	# Return to tactical view and reset turn cycle
	print("All lanes complete - returning to tactical view")

	# Stop combat and return to tactical
	_on_return_to_tactical()

	# Reset to tactical phase
	current_turn_phase = "tactical"
	waiting_for_combat_start = false

	# Show proceed button for next turn
	if turn_progression_button:
		turn_progression_button.text = "Proceed to Lane 1"
		turn_progression_button.visible = true

func start_lane_combat(lane_index: int):
	# Start combat for all ships in a specific lane (when zoomed in)
	if lane_index < 0 or lane_index >= lanes.size():
		return

	var lane = lanes[lane_index]
	print("Starting combat for lane ", lane_index, " with ", lane["units"].size(), " units")

	for unit in lane["units"]:
		# Assign random target (will be restricted to same lane due to is_zoomed)
		assign_random_target(unit)
		# Start target switching timer (switches every 3 seconds)
		start_target_switch_timer(unit)

func stop_lane_combat(lane_index: int):
	# Stop combat for all ships in a specific lane
	if lane_index < 0 or lane_index >= lanes.size():
		return

	var lane = lanes[lane_index]
	print("Stopping combat for lane ", lane_index)

	for unit in lane["units"]:
		# Stop attack timers
		if unit.has("container"):
			var container = unit["container"]
			var attack_timer = container.get_node_or_null("AttackTimer")
			if attack_timer:
				attack_timer.stop()
				attack_timer.queue_free()
			var switch_timer = container.get_node_or_null("TargetSwitchTimer")
			if switch_timer:
				switch_timer.stop()
				switch_timer.queue_free()
		# Clear auto-combat data
		unit.erase("auto_target")
		# Reset sprite modulation
		if unit.has("sprite"):
			unit["sprite"].modulate = Color(1, 1, 1)

func start_auto_combat():
	# Start auto-combat: all ships attack random enemies
	# Assign random targets to all units
	for lane in lanes:
		for unit in lane["units"]:
			# Assign random target
			assign_random_target(unit)
			# Start target switching timer (switches every 3 seconds)
			start_target_switch_timer(unit)

func stop_auto_combat():
	# Stop all auto-combat attacks
	for lane in lanes:
		for unit in lane["units"]:
			# Stop attack timers
			if unit.has("container"):
				var container = unit["container"]
				var attack_timer = container.get_node_or_null("AttackTimer")
				if attack_timer:
					attack_timer.stop()
					attack_timer.queue_free()
				var switch_timer = container.get_node_or_null("TargetSwitchTimer")
				if switch_timer:
					switch_timer.stop()
					switch_timer.queue_free()
			# Clear auto-combat data
			unit.erase("auto_target")
			# Reset sprite modulation
			if unit.has("sprite"):
				unit["sprite"].modulate = Color(1, 1, 1)

func assign_random_target(unit: Dictionary, restrict_to_lane: int = -1):
	# Assign a random enemy target to a unit
	# If restrict_to_lane >= 0, only target ships in that lane
	if unit.is_empty():
		return

	var is_enemy = unit.get("is_enemy", false)
	var potential_targets: Array[Dictionary] = []

	# Determine which lane this unit is in
	var unit_lane_index = -1
	for lane in lanes:
		if lane["units"].has(unit):
			unit_lane_index = lane["index"]
			break

	# Find all valid targets (opposite faction)
	for lane in lanes:
		# Skip lanes if we're restricting to a specific lane
		if restrict_to_lane >= 0 and lane["index"] != restrict_to_lane:
			continue

		# When in zoomed mode, only target ships in the same lane
		if is_zoomed and lane["index"] != unit_lane_index:
			continue

		for other_unit in lane["units"]:
			var other_is_enemy = other_unit.get("is_enemy", false)
			if is_enemy != other_is_enemy:  # Opposite factions
				potential_targets.append(other_unit)

	# If no targets, clear auto_target
	if potential_targets.is_empty():
		unit["auto_target"] = null
		print("No targets available for ", unit.get("type", "unknown"))
		return

	# Pick random target
	var random_index = randi() % potential_targets.size()
	var target = potential_targets[random_index]
	unit["auto_target"] = target

	# Start attacking
	start_auto_attack(unit, target)

	print("Assigned target: ", unit.get("type", "unknown"), " -> ", target.get("type", "unknown"))

func start_target_switch_timer(unit: Dictionary):
	# Start a timer that switches targets every 3 seconds
	if unit.is_empty() or not unit.has("container"):
		return

	var container = unit["container"]

	# Clear existing timer
	var existing_timer = container.get_node_or_null("TargetSwitchTimer")
	if existing_timer:
		existing_timer.queue_free()

	# Create timer that fires every 3 seconds
	var timer = Timer.new()
	timer.name = "TargetSwitchTimer"
	timer.wait_time = 3.0
	timer.autostart = true
	timer.timeout.connect(func(): _on_target_switch_timeout(unit))
	container.add_child(timer)

func _on_target_switch_timeout(unit: Dictionary):
	# Switch to a new random target
	if not auto_combat_active:
		return

	if unit.is_empty() or not is_instance_valid(unit.get("container")):
		return

	print("Target switch timer - reassigning for ", unit.get("type", "unknown"))
	assign_random_target(unit)

func start_auto_attack(attacker: Dictionary, target: Dictionary):
	# Start an auto-attack sequence
	if attacker.is_empty() or target.is_empty():
		return

	# Rotate to face target
	auto_rotate_to_target(attacker, target)

	# Calculate attack interval: 1 / attack_speed = seconds per attack
	var attack_speed = attacker["stats"]["attack_speed"]
	var attack_interval = 1.0 / attack_speed

	# Fire first shot after rotation
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(attacker.get("container")):
		return

	# Fire first volley immediately
	await auto_fire_laser(attacker, target)

	# Start continuous attack cycle
	auto_attack_cycle(attacker, target, attack_interval)

func auto_rotate_to_target(attacker: Dictionary, target: Dictionary):
	# Rotate attacker to face target (for auto-combat)
	if attacker.is_empty() or target.is_empty():
		return

	if not attacker.has("sprite") or not attacker.has("container"):
		return

	var attacker_sprite = attacker["sprite"]
	var attacker_pos = attacker["container"].position
	var attacker_size = attacker["size"]
	var target_pos = target["container"].position
	var target_size = target["size"]

	# Calculate center positions
	var attacker_center = attacker_pos + Vector2(attacker_size / 2, attacker_size / 2)
	var target_center = target_pos + Vector2(target_size / 2, target_size / 2)

	# Calculate angle to target
	var direction = target_center - attacker_center
	var target_rotation = direction.angle()

	# Smoothly rotate to target
	var tween = create_tween()
	tween.tween_property(attacker_sprite, "rotation", target_rotation, 0.3)

func auto_attack_cycle(attacker: Dictionary, target: Dictionary, attack_interval: float):
	# Continuous auto-attack cycle
	# Continue attacking while auto-combat is active OR while zoomed into a lane
	while (auto_combat_active or is_zoomed) and not attacker.is_empty() and not target.is_empty():
		# Stop if combat is paused
		if combat_paused:
			# Wait for combat to unpause
			await get_tree().create_timer(0.1).timeout
			continue

		# Check if target is still assigned and valid
		var current_target = attacker.get("auto_target")
		if current_target != target or not is_instance_valid(target.get("container")):
			# Target changed or destroyed, stop this cycle
			break

		# Check if attacker still exists
		if not is_instance_valid(attacker.get("container")):
			break

		# Fire all projectiles in this attack
		await auto_fire_laser(attacker, target)

		# Wait for cooldown (timer resets AFTER all projectiles fire)
		await get_tree().create_timer(attack_interval).timeout

func auto_fire_laser(attacker: Dictionary, target: Dictionary):
	# Fire laser projectiles in auto-combat (all projectiles in one attack)
	if attacker.is_empty() or target.is_empty():
		return

	if not is_instance_valid(attacker.get("container")) or not is_instance_valid(target.get("container")):
		return

	var num_attacks = attacker["stats"]["num_attacks"]

	# Fire multiple projectiles with small delay between them
	for i in range(num_attacks):
		if i > 0:
			await get_tree().create_timer(0.05).timeout
		auto_fire_single_laser(attacker, target)

	# Gain energy after attack (2-4 random)
	gain_energy(attacker)

func auto_fire_single_laser(attacker: Dictionary, target: Dictionary):
	# Fire a single laser in auto-combat
	if attacker.is_empty() or target.is_empty():
		return

	if not is_instance_valid(attacker.get("container")) or not is_instance_valid(target.get("container")):
		return

	var attacker_pos = attacker["container"].position
	var attacker_size = attacker["size"]
	var target_pos = target["container"].position
	var target_size = target["size"]

	# Calculate center positions
	var start_pos = attacker_pos + Vector2(attacker_size / 2, attacker_size / 2)
	var end_pos = target_pos + Vector2(target_size / 2, target_size / 2)

	# Calculate direction and angle
	var direction = end_pos - start_pos
	var angle = direction.angle()

	# Create laser sprite
	var laser = Sprite2D.new()
	laser.texture = LaserTexture
	laser.position = start_pos
	laser.rotation = angle
	laser.z_index = 1
	add_child(laser)

	# Scale laser
	var laser_height = LaserTexture.get_height()
	var scale_y = 6.0 / laser_height
	laser.scale = Vector2(scale_y, scale_y)
	laser.offset = Vector2(-LaserTexture.get_width() / 2, -LaserTexture.get_height() / 2)

	# Animate laser
	var flight_duration = 0.2
	var tween = create_tween()
	tween.tween_property(laser, "position", end_pos, flight_duration)
	tween.tween_callback(func():
		auto_on_laser_hit(laser, attacker, target)
	)

func auto_on_laser_hit(laser: Sprite2D, attacker: Dictionary, target: Dictionary):
	# Handle laser hit in auto-combat
	laser.queue_free()

	# Check if units still exist
	if attacker.is_empty() or target.is_empty():
		return
	if not is_instance_valid(target.get("container")):
		return

	# Calculate and apply damage
	var damage_dealt = calculate_damage(attacker, target)
	if damage_dealt > 0:
		apply_damage(target, damage_dealt)

	# Flash target
	if target.has("sprite"):
		var target_sprite = target["sprite"]
		var flash_tween = create_tween()
		flash_tween.tween_property(target_sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.05)
		flash_tween.tween_property(target_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)


# Energy system functions

func gain_energy(unit: Dictionary):
	# Gain 2-4 random energy after each attack
	if unit.is_empty():
		return

	# Don't gain energy when combat is paused
	if combat_paused:
		return

	# Skip if unit has no energy system (max energy = 0)
	var max_energy = unit["stats"].get("energy", 0)
	if max_energy <= 0:
		return

	# Random energy gain: 2, 3, or 4
	var energy_gain = randi_range(2, 4)
	var current_energy = unit.get("current_energy", 0)

	unit["current_energy"] = current_energy + energy_gain
	print(unit.get("type", "unknown"), " gained ", energy_gain, " energy (", unit["current_energy"], "/", max_energy, ")")

	# Update energy bar
	update_energy_bar(unit)

	# Check if energy is full
	if unit["current_energy"] >= max_energy:
		cast_ability(unit)

func cast_ability(unit: Dictionary):
	# Cast unit's ability when energy is full
	if unit.is_empty():
		return

	var ability_name = unit.get("ability_name", "")
	var ability_function = unit.get("ability_function", "")

	if ability_name == "":
		print(unit.get("type", "unknown"), " has no ability to cast")
		return

	print("=== ABILITY CAST ===")
	print(unit.get("type", "unknown"), " casts: ", ability_name)
	print("Description: ", unit.get("ability_description", "No description"))
	print("Function: ", ability_function)
	print("====================")

	# Reset energy to 0
	unit["current_energy"] = 0
	update_energy_bar(unit)

	# TODO: Actually call the ability function when implemented
	# For now just print to console

# Health bar functions

func create_health_bar(ship_container: Control, ship_size: int, max_shield: int, max_armor: int):
	# Create health bar UI above ship (max 32px wide)
	var bar_width = min(32, ship_size)  # Cap at 32 pixels
	var health_bar_container = Control.new()
	health_bar_container.name = "HealthBar"
	health_bar_container.position = Vector2((ship_size - bar_width) / 2, -18)  # Center above ship, raised a bit for 3-bar layout
	health_bar_container.size = Vector2(bar_width, 12)
	ship_container.add_child(health_bar_container)

	# Background (dark gray)
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.2, 0.2, 0.2, 0.8)
	bg.size = Vector2(bar_width, 12)
	health_bar_container.add_child(bg)

	# Shield bar (cyan/blue) - top
	var shield_bar = ColorRect.new()
	shield_bar.name = "ShieldBar"
	shield_bar.color = Color(0.2, 0.7, 1.0, 1.0)
	shield_bar.size = Vector2(bar_width, 4)
	shield_bar.position = Vector2(0, 0)
	health_bar_container.add_child(shield_bar)

	# Armor bar (red/orange) - middle
	var armor_bar = ColorRect.new()
	armor_bar.name = "ArmorBar"
	armor_bar.color = Color(0.8, 0.3, 0.2, 1.0)
	armor_bar.size = Vector2(bar_width, 4)
	armor_bar.position = Vector2(0, 4)
	health_bar_container.add_child(armor_bar)

	# Energy bar (purple) - bottom
	var energy_bar = ColorRect.new()
	energy_bar.name = "EnergyBar"
	energy_bar.color = Color(0.7, 0.2, 1.0, 1.0)  # Purple
	energy_bar.size = Vector2(bar_width, 4)
	energy_bar.position = Vector2(0, 8)
	health_bar_container.add_child(energy_bar)

func update_health_bar(ship: Dictionary):
	# Update health bar to reflect current health
	if not ship.has("container"):
		return

	var container = ship["container"]
	var health_bar_container = container.get_node_or_null("HealthBar")
	if not health_bar_container:
		return

	var ship_size = ship["size"]
	var bar_width = min(32, ship_size)  # Cap at 32 pixels
	var max_armor = ship["stats"]["armor"]
	var max_shield = ship["stats"]["shield"]
	var current_armor = ship.get("current_armor", max_armor)
	var current_shield = ship.get("current_shield", max_shield)

	# Update armor bar width
	var armor_bar = health_bar_container.get_node_or_null("ArmorBar")
	if armor_bar and max_armor > 0:
		var armor_percent = float(current_armor) / float(max_armor)
		armor_bar.size.x = bar_width * armor_percent

	# Update shield bar width
	var shield_bar = health_bar_container.get_node_or_null("ShieldBar")
	if shield_bar and max_shield > 0:
		var shield_percent = float(current_shield) / float(max_shield)
		shield_bar.size.x = bar_width * shield_percent

	# Also update energy bar
	update_energy_bar(ship)

func update_energy_bar(ship: Dictionary):
	# Update energy bar to reflect current energy
	if not ship.has("container"):
		return

	var container = ship["container"]
	var health_bar_container = container.get_node_or_null("HealthBar")
	if not health_bar_container:
		return

	var ship_size = ship["size"]
	var bar_width = min(32, ship_size)  # Cap at 32 pixels
	var max_energy = ship["stats"].get("energy", 0)
	var current_energy = ship.get("current_energy", 0)

	# Update energy bar width
	var energy_bar = health_bar_container.get_node_or_null("EnergyBar")
	if energy_bar:
		if max_energy > 0:
			var energy_percent = float(current_energy) / float(max_energy)
			energy_bar.size.x = bar_width * energy_percent
		else:
			# No energy system, hide the bar
			energy_bar.size.x = 0

# Stat helper functions

func get_unit_stat(unit: Dictionary, stat_name: String):
	# Get a stat value from a unit's stats dictionary
	if unit.has("stats") and unit["stats"].has(stat_name):
		return unit["stats"][stat_name]
	print("Warning: Unit missing stat '", stat_name, "'")
	return 0

func modify_unit_stat(unit: Dictionary, stat_name: String, amount: float):
	# Modify a stat value (for upgrades/debuffs)
	if unit.has("stats") and unit["stats"].has(stat_name):
		unit["stats"][stat_name] += amount
		print("Modified ", stat_name, " by ", amount, ". New value: ", unit["stats"][stat_name])
		return true
	print("Warning: Cannot modify stat '", stat_name, "' - unit missing stat")
	return false

func get_unit_health_percent(unit: Dictionary) -> float:
	# Calculate total health percentage (armor + shield)
	if not unit.has("stats"):
		return 0.0

	var max_armor = unit["stats"]["armor"]
	var max_shield = unit["stats"]["shield"]
	var current_armor = unit.get("current_armor", max_armor)
	var current_shield = unit.get("current_shield", max_shield)

	var max_health = max_armor + max_shield
	var current_health = current_armor + current_shield

	if max_health <= 0:
		return 0.0

	return (current_health / max_health) * 100.0

func display_unit_stats(unit: Dictionary):
	# Debug function to print all unit stats
	if not unit.has("stats"):
		print("Unit has no stats")
		return

	print("=== Unit Stats ===")
	print("Type: ", unit.get("type", "unknown"))
	print("Armor: ", unit.get("current_armor", 0), " / ", unit["stats"]["armor"])
	print("Shield: ", unit.get("current_shield", 0), " / ", unit["stats"]["shield"])
	print("Reinforced Armor: ", unit["stats"]["reinforced_armor"], "%")
	print("Evasion: ", unit["stats"]["evasion"], "%")
	print("Accuracy: ", unit["stats"]["accuracy"])
	print("Attack Speed: ", unit["stats"]["attack_speed"], "x")
	print("Num Attacks: ", unit["stats"]["num_attacks"])
	print("Amplitude: ", unit["stats"]["amplitude"])
	print("Frequency: ", unit["stats"]["frequency"])
	print("Health: ", get_unit_health_percent(unit), "%")
	print("==================")

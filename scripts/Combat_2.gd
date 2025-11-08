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

# Ship type to size mapping
const SHIP_SIZES = {
	"interceptor": SIZE_TINY,
	"fighter": SIZE_MEDIUM,
	"frigate": SIZE_LARGE
}

# Ship deployment animation speeds (duration in seconds)
const SHIP_DEPLOY_SPEED = {
	"interceptor": 2.0,  # Fast
	"fighter": 3.0,      # Medium
	"frigate": 5.0       # Slow
}

# Preload ship textures
const MothershipTexture = preload("res://assets/Ships/illum_default/s_illum_default_24.png")
const InterceptorTexture = preload("res://assets/Ships/illum_default/s_illum_default_23.png")
const FighterTexture = preload("res://assets/Ships/illum_default/s_illum_default_19.png")
const FrigateTexture = preload("res://assets/Ships/illum_default/s_illum_default_01.png")

# Preload UI textures
const CloseButtonTexture = preload("res://assets/UI/Close_BTN/Close_BTN.png")

# Preload background textures
const Space2Texture = preload("res://assets/Backgrounds/Space2/Bright/Space2.png")
const Stones1Texture = preload("res://assets/Backgrounds/Space2/Bright/stones1.png")

# Game state
var lanes: Array[Dictionary] = []  # Each lane can contain units
var selected_ship_type: String = ""  # Currently selected ship for deployment
var ship_selection_panel: Panel = null
var deploy_button: Button = null
var is_zoomed: bool = false
var zoomed_lane_index: int = -1
var camera: Camera2D = null
var return_button: TextureButton = null
var ui_layer: CanvasLayer = null

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

	# Initialize lanes
	initialize_lanes()

	# Setup mothership
	setup_mothership()

	# Setup enemy spawner
	setup_enemy_spawner()

	# Setup deployment UI
	setup_deployment_ui()

	# Setup return button (initially hidden)
	setup_return_button()

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

	# Create ship selection panel (initially hidden)
	ship_selection_panel = Panel.new()
	ship_selection_panel.name = "ShipSelectionPanel"
	ship_selection_panel.position = Vector2(350, 150)
	ship_selection_panel.size = Vector2(450, 350)
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

	# Create ship selection buttons
	var ship_types = [
		{"name": "Basic Interceptor", "type": "interceptor", "texture": InterceptorTexture, "y": 80},
		{"name": "Basic Fighter", "type": "fighter", "texture": FighterTexture, "y": 170},
		{"name": "Basic Frigate", "type": "frigate", "texture": FrigateTexture, "y": 260}
	]

	for ship in ship_types:
		var ship_button = Button.new()
		ship_button.name = ship["type"] + "_button"
		ship_button.position = Vector2(20, ship["y"])
		ship_button.size = Vector2(410, 70)
		ship_button.text = ship["name"]
		ship_button.add_theme_font_size_override("font_size", 20)
		ship_button.pressed.connect(_on_ship_selected.bind(ship["type"]))
		ship_selection_panel.add_child(ship_button)

		# Add ship icon to button (sized according to ship class)
		var icon = TextureRect.new()
		icon.texture = ship["texture"]
		var icon_size = SHIP_SIZES[ship["type"]]
		# Center the icon vertically in the button
		var icon_y = (70 - icon_size) / 2
		icon.position = Vector2(10, icon_y)
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.size = Vector2(icon_size, icon_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ship_button.add_child(icon)

	# Add close button
	var close_button = Button.new()
	close_button.text = "CANCEL"
	close_button.position = Vector2(150, 310)
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
		if ship_selection_panel.visible:
			return

		var mouse_pos = get_global_mouse_position()
		var lane_index = get_lane_at_position(mouse_pos)

		if selected_ship_type != "":
			# Ship selected - deploy to lane
			if lane_index != -1:
				deploy_ship_to_lane(selected_ship_type, lane_index)
				selected_ship_type = ""  # Clear selection after deployment
		elif not is_zoomed and lane_index != -1:
			# No ship selected and not zoomed - zoom into lane
			zoom_to_lane(lane_index)

func get_lane_at_position(pos: Vector2) -> int:
	# Determine which lane a position is in
	for i in range(NUM_LANES):
		var lane_y = lanes[i]["y_position"]
		# Check if mouse is within 75 pixels above or below lane center
		if abs(pos.y - lane_y) < 75:
			return i
	return -1

func deploy_ship_to_lane(ship_type: String, lane_index: int):
	# Deploy a ship to the specified lane
	print("Deploying ", ship_type, " to lane ", lane_index)

	# Get ship texture and size
	var ship_texture: Texture2D
	var ship_size: int
	var deploy_duration: float
	match ship_type:
		"interceptor":
			ship_texture = InterceptorTexture
			ship_size = SHIP_SIZES["interceptor"]
			deploy_duration = SHIP_DEPLOY_SPEED["interceptor"]
		"fighter":
			ship_texture = FighterTexture
			ship_size = SHIP_SIZES["fighter"]
			deploy_duration = SHIP_DEPLOY_SPEED["fighter"]
		"frigate":
			ship_texture = FrigateTexture
			ship_size = SHIP_SIZES["frigate"]
			deploy_duration = SHIP_DEPLOY_SPEED["frigate"]

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
		"idle_timer": 0.0
	}

	# Add to lane data
	lanes[lane_index]["units"].append(ship_data)

	# Start idle behavior
	start_ship_idle_behavior(ship_data)

	print("Ship deployed successfully at x=", target_x, " y=", target_y, " with size=", ship_size)

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

	# Show return button
	return_button.visible = true

	# Hide deploy button while zoomed
	deploy_button.visible = false

func _on_return_to_tactical():
	# Return to tactical view
	print("Returning to tactical view")
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

	# Show deploy button again
	deploy_button.visible = true

# Future functions to add:
# - spawn_enemy(lane_index: int, enemy_type: String)
# - update_lane(lane_index: int)

extends Node2D

## BackgroundManager handles all background and parallax sprites
## Separated from combat logic for modularity and reusability
## This replaces the background logic from Combat_2.gd

# Export variables to customize background appearance
@export_group("Background Settings")
@export var bg_tile_size: float = 1.0  # Scale multiplier for Space2.png tiles
@export var bg_scroll_direction: Vector2 = Vector2(1, 0)  # Direction of parallax scroll
@export var bg_scroll_speed: float = 10.0  # Pixels per second
@export var enable_auto_scroll: bool = true

@export_group("Visual Settings")
@export var parallax_opacity: float = 0.7  # Transparency for parallax layer

# Internal variables
var parallax_offset: Vector2 = Vector2.ZERO  # Current parallax offset
var screen_size: Vector2 = Vector2(1152, 648)  # Default screen size

# Background nodes
var space_background: Node2D = null
var parallax_background: Node2D = null

func _ready() -> void:
	setup_backgrounds()

func _process(delta: float) -> void:
	if enable_auto_scroll:
		update_parallax_scroll(delta)

func setup_backgrounds() -> void:
	"""Setup both static background and parallax layers"""
	setup_space_background()
	setup_parallax_background()
	print("BackgroundManager: Backgrounds initialized - Space at z:-100, Parallax at z:-50")

func setup_space_background() -> void:
	"""Create static space background (tiled)"""
	space_background = Node2D.new()
	space_background.name = "SpaceBackground"
	space_background.z_index = -100
	add_child(space_background)

	# Tile Space2.png across the screen
	var tex_size = CombatConstants.Space2Texture.get_size() * bg_tile_size
	var tiles_x = ceil(screen_size.x / tex_size.x) + 1
	var tiles_y = ceil(screen_size.y / tex_size.y) + 1

	print("BackgroundManager: Creating space background tiles: ", tiles_x, "x", tiles_y)
	print("BackgroundManager: Space2 texture size: ", CombatConstants.Space2Texture.get_size())

	for x in range(tiles_x):
		for y in range(tiles_y):
			var sprite = Sprite2D.new()
			sprite.texture = CombatConstants.Space2Texture
			sprite.scale = Vector2(bg_tile_size, bg_tile_size)
			sprite.position = Vector2(x * tex_size.x, y * tex_size.y)
			sprite.centered = false
			sprite.z_index = -100  # Ensure it's behind everything
			space_background.add_child(sprite)

func setup_parallax_background() -> void:
	"""Create parallax background (stones1 scrolling)"""
	parallax_background = Node2D.new()
	parallax_background.name = "ParallaxBackground"
	parallax_background.z_index = -50
	add_child(parallax_background)

	# Create a 3x3 grid of stones for seamless scrolling
	var stones_tex_size = CombatConstants.Stones1Texture.get_size()
	print("BackgroundManager: Creating parallax stones, texture size: ", stones_tex_size)

	for x in range(-1, 2):
		for y in range(-1, 2):
			var sprite = Sprite2D.new()
			sprite.texture = CombatConstants.Stones1Texture
			sprite.centered = false
			sprite.modulate.a = parallax_opacity  # Make slightly transparent
			var base_pos = Vector2(x * stones_tex_size.x, y * stones_tex_size.y)
			sprite.position = base_pos
			sprite.z_index = -50
			sprite.set_meta("base_position", base_pos)
			parallax_background.add_child(sprite)

func update_parallax_scroll(delta: float) -> void:
	"""Update parallax background scrolling effect"""
	if not parallax_background:
		return

	parallax_offset += bg_scroll_direction.normalized() * bg_scroll_speed * delta

	# Get texture size for wrapping
	var tex_width = CombatConstants.Stones1Texture.get_width()
	var tex_height = CombatConstants.Stones1Texture.get_height()

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

func update_background_tiles() -> void:
	"""Rebuild space background with new tile size"""
	if not space_background:
		return

	# Clear old tiles
	for child in space_background.get_children():
		child.queue_free()

	# Create new tiles
	var tex_size = CombatConstants.Space2Texture.get_size() * bg_tile_size
	var tiles_x = ceil(screen_size.x / tex_size.x) + 1
	var tiles_y = ceil(screen_size.y / tex_size.y) + 1

	print("BackgroundManager: Updating background tiles: ", tiles_x, "x", tiles_y)

	for x in range(tiles_x):
		for y in range(tiles_y):
			var sprite = Sprite2D.new()
			sprite.texture = CombatConstants.Space2Texture
			sprite.scale = Vector2(bg_tile_size, bg_tile_size)
			sprite.position = Vector2(x * tex_size.x, y * tex_size.y)
			sprite.centered = false
			sprite.z_index = -100
			space_background.add_child(sprite)

## Set the scroll direction for parallax effect
func set_scroll_direction(direction: Vector2) -> void:
	bg_scroll_direction = direction

## Set the scroll speed for parallax effect
func set_scroll_speed(speed: float) -> void:
	bg_scroll_speed = speed

## Enable or disable automatic scrolling
func set_auto_scroll(enabled: bool) -> void:
	enable_auto_scroll = enabled

## Set the tile size for the background
func set_tile_size(size: float) -> void:
	bg_tile_size = size
	update_background_tiles()

## Set the opacity of the parallax layer
func set_parallax_opacity(opacity: float) -> void:
	parallax_opacity = clamp(opacity, 0.0, 1.0)
	if parallax_background:
		for child in parallax_background.get_children():
			if child is Sprite2D:
				child.modulate.a = parallax_opacity

## Manually set the parallax offset
func set_parallax_offset(offset: Vector2) -> void:
	parallax_offset = offset

## Get the current parallax offset
func get_parallax_offset() -> Vector2:
	return parallax_offset

extends Control

# Resource icon paths
const MetalIcon = preload("res://assets/Icons/metal_small_icon.png")
const CrystalIcon = preload("res://assets/Icons/crystal_small_icon.png")
const FuelIcon = preload("res://assets/Icons/fuel_icon.png")
const PilotIcon = preload("res://assets/Icons/pilot_icon.png")
const MetalLargeIcon = preload("res://assets/Icons/metal_large_icon.png")
const CrystalLargeIcon = preload("res://assets/Icons/crystal_large_icon.png")

# Background sprites
const ButtonSingle = preload("res://assets/UI/s_button_1/s_button_1.png")
const ButtonLeft = preload("res://assets/UI/s_button_1_left/s_button_1_left.png")
const ButtonCenter = preload("res://assets/UI/s_button_1_center/s_button_1_center.png")
const ButtonRight = preload("res://assets/UI/s_button_1_right/s_button_1_right.png")

# UI elements
var metal_label: Label
var crystal_label: Label
var fuel_label: Label
var pilot_label: Label
var metal_large_label: Label
var crystal_large_label: Label
var background_container: Control

func _ready():
	setup_resources()
	update_resources()

func setup_resources():
	# Create background container (rendered behind)
	background_container = Control.new()
	background_container.name = "BackgroundContainer"
	background_container.z_index = -1
	add_child(background_container)

	# Create vertical container to hold two rows
	var vbox = VBoxContainer.new()
	vbox.name = "ResourceContainer"
	vbox.add_theme_constant_override("separation", 5)
	vbox.z_index = 0
	add_child(vbox)

	# First row: Metal, Crystals, Fuel
	var row1 = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 20)
	vbox.add_child(row1)
	add_resource_display(row1, "metal", MetalIcon)
	add_resource_display(row1, "crystals", CrystalIcon)
	add_resource_display(row1, "fuel", FuelIcon)

	# Second row: Pilots, Metal Large (placeholder), Crystal Large (placeholder)
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 20)
	vbox.add_child(row2)
	add_resource_display(row2, "pilots", PilotIcon)
	add_resource_display(row2, "metal_large", MetalLargeIcon)
	add_resource_display(row2, "crystal_large", CrystalLargeIcon)

	# Wait for sizing and create background
	await get_tree().process_frame
	var content_size = vbox.size
	var needed_width = content_size.x + 40  # Add padding
	var needed_height = content_size.y + 20

	# Create background
	create_background(needed_width, needed_height)

	# Position content on top of background
	vbox.position = Vector2(20, 10)

	# Adjust overall size
	custom_minimum_size = Vector2(needed_width, needed_height)

func create_background(width: float, height: float):
	# Clear any existing background sprites
	for child in background_container.get_children():
		child.queue_free()

	# Use single sprite for now
	var sprite = Sprite2D.new()
	sprite.texture = ButtonSingle
	sprite.centered = false
	sprite.position = Vector2(0, 0)
	background_container.add_child(sprite)

func add_resource_display(container: HBoxContainer, resource_type: String, icon: Texture2D):
	# Create container for this resource
	var resource_hbox = HBoxContainer.new()
	resource_hbox.add_theme_constant_override("separation", 8)
	container.add_child(resource_hbox)

	# Add icon
	var icon_texture = TextureRect.new()
	icon_texture.texture = icon
	icon_texture.custom_minimum_size = Vector2(32, 32)
	icon_texture.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
	icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	resource_hbox.add_child(icon_texture)

	# Add label
	var label = Label.new()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	resource_hbox.add_child(label)

	# Store label reference
	match resource_type:
		"metal":
			metal_label = label
		"crystals":
			crystal_label = label
		"fuel":
			fuel_label = label
		"pilots":
			pilot_label = label
		"metal_large":
			metal_large_label = label
		"crystal_large":
			crystal_large_label = label

func update_resources():
	# Update all resource displays from GameData
	if metal_label:
		metal_label.text = str(GameData.get_resource("metal"))
	if crystal_label:
		crystal_label.text = str(GameData.get_resource("crystals"))
	if fuel_label:
		fuel_label.text = str(GameData.get_resource("fuel"))
	if pilot_label:
		pilot_label.text = str(GameData.get_resource("pilots"))
	if metal_large_label:
		metal_large_label.text = str(GameData.get_resource("metal_large"))
	if crystal_large_label:
		crystal_large_label.text = str(GameData.get_resource("crystal_large"))

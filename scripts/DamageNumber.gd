extends Node2D
class_name DamageNumber

## DamageNumber - Floating damage/healing numbers with animations
## Shows damage dealt, healing, crits, and misses with visual feedback

enum NumberType {
	SHIELD_DAMAGE,   # Blue
	ARMOR_DAMAGE,    # Red
	HEALING,         # Green
	MISS,            # Gray/White
	CRIT             # Special - larger, bounces more
}

# Animation parameters
const LAUNCH_SPEED = 150.0   # Initial launch velocity
const GRAVITY = 200.0        # Gravity strength (pixels/s²)
const FLOAT_DURATION = 1.0   # How long the animation lasts
const FADE_START_TIME = 0.7  # When to start fading (as ratio of duration)

# 12 pre-determined launch angles (in degrees)
# Alternates between right (positive) and left (negative)
#const LAUNCH_ANGLES = [
	#-75,  # Left, steep
	#75,   # Right, steep
	#-60,  # Left, high
	#60,   # Right, high
	#-45,  # Left, diagonal
	#45,   # Right, diagonal
	#-30,  # Left, shallow
	#30,   # Right, shallow
	#-85,  # Left, very steep
	#85,   # Right, very steep
	#-50,  # Left, medium-high
	#50    # Right, medium-high
#]

const LAUNCH_ANGLES = [75,125,90,115,90,75,125,87,115,90,87,112]

# Static counter to track which angle to use next
static var angle_index: int = 0

var label: Label
var number_type: NumberType
var is_crit: bool = false
var damage_amount: int = 0
var velocity: Vector2 = Vector2.ZERO
var launch_angle: float = 0.0

func _ready():
	# Create label
	label = Label.new()
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)

	# Get the next launch angle from the sequence
	launch_angle = deg_to_rad(LAUNCH_ANGLES[angle_index])
	angle_index = (angle_index + 1) % LAUNCH_ANGLES.size()

	# Calculate initial velocity based on angle
	velocity = Vector2(
		cos(launch_angle) * LAUNCH_SPEED,
		-sin(launch_angle) * LAUNCH_SPEED  # Negative Y is up
	)

	# Start animation
	animate()

func _process(delta: float):
	# Apply gravity to velocity
	velocity.y += GRAVITY * delta

	# Update position based on velocity
	position += velocity * delta

func setup(amount: int, type: NumberType, crit: bool = false):
	"""Setup the damage number with amount, type, and crit status"""
	damage_amount = amount
	number_type = type
	is_crit = crit

	# Set text based on type
	match type:
		NumberType.MISS:
			label.text = "MISS"
		_:
			label.text = str(amount)

	# Apply styling based on type and crit
	apply_styling()

func apply_styling():
	"""Apply color, size, and style based on number type"""
	var color = Color.WHITE
	var font_size = 14  # Smaller default size

	match number_type:
		NumberType.SHIELD_DAMAGE:
			color = Color(0.2, 0.6, 1.0)  # Cyan/Blue

		NumberType.ARMOR_DAMAGE:
			color = Color(1.0, 0.2, 0.2)  # Red

		NumberType.HEALING:
			color = Color(0.2, 1.0, 0.2)  # Green

		NumberType.MISS:
			color = Color(0.7, 0.7, 0.7)  # Gray
			font_size = 12

	# Crit modifications
	if is_crit:
		font_size = 20  # Larger but still smaller than before
		# Make colors brighter for crits
		color = color.lightened(0.3)

	# Apply styles
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)

	# Add outline for better visibility
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)  # Smaller outline

	# If crit, add "CRIT!" text above damage
	if is_crit and number_type != NumberType.MISS:
		var crit_label = Label.new()
		crit_label.text = "CRIT!"
		crit_label.add_theme_font_size_override("font_size", 10)
		crit_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2))  # Yellow
		crit_label.add_theme_color_override("font_outline_color", Color.BLACK)
		crit_label.add_theme_constant_override("outline_size", 1)
		crit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crit_label.position = Vector2(-15, -15)  # Position above main number
		add_child(crit_label)

func animate():
	"""Animate the damage number with fade and physics"""
	# Create tween for fade out
	var tween = create_tween()

	# Fade out near the end
	tween.tween_property(label, "modulate:a", 0.0, FLOAT_DURATION * (1.0 - FADE_START_TIME)) \
		.set_delay(FLOAT_DURATION * FADE_START_TIME)

	# Scale animation for crits (pulse effect)
	if is_crit:
		var scale_tween = create_tween()
		scale_tween.tween_property(label, "scale", Vector2(1.3, 1.3), 0.08) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)
		scale_tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.15) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_IN)

	# Clean up after animation duration
	await get_tree().create_timer(FLOAT_DURATION).timeout
	queue_free()

## Static helper function to spawn damage numbers
static func spawn(parent: Node, pos: Vector2, amount: int, type: NumberType, crit: bool = false) -> DamageNumber:
	"""Spawn a damage number at the given position"""
	var damage_number = preload("res://scenes/DamageNumber.tscn").instantiate()
	damage_number.position = pos
	parent.add_child(damage_number)
	damage_number.setup(amount, type, crit)
	return damage_number

## Convenience functions for common damage types
static func show_shield_damage(parent: Node, pos: Vector2, amount: int, crit: bool = false):
	spawn(parent, pos, amount, NumberType.SHIELD_DAMAGE, crit)

static func show_armor_damage(parent: Node, pos: Vector2, amount: int, crit: bool = false):
	spawn(parent, pos, amount, NumberType.ARMOR_DAMAGE, crit)

static func show_healing(parent: Node, pos: Vector2, amount: int):
	spawn(parent, pos, amount, NumberType.HEALING, false)

static func show_miss(parent: Node, pos: Vector2):
	spawn(parent, pos, 0, NumberType.MISS, false)

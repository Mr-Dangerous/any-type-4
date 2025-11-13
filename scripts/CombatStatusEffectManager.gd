extends Node
class_name CombatStatusEffectManager

## Manages status effects (burn, freeze, etc.) on ships during combat
## Handles DOT ticks, visual indicators, and lane-aware timing

signal status_applied(ship, effect_type, stacks)
signal status_removed(ship, effect_type)
signal status_tick(ship, effect_type, damage)

var combat_scene = null
var active_lane_index: int = -1

# Status effect type constants
enum StatusType {
	BURN,
	# Future: FREEZE, ACID, STATIC, GRAVITY, etc.
}

# Status effect configurations
const STATUS_CONFIGS = {
	"burn": {
		"damage_per_tick": 5,
		"tick_interval": 1.0,
		"duration": 10.0,
		"icon": "🔥",
		"color": Color.ORANGE_RED
	},
	"freeze": {
		"attack_speed_multiplier": 0.75,  # 25% slower (0.75x speed per stack)
		"evasion_multiplier": 0.75,       # 25% less evasion per stack
		"duration": 2.0,                   # 2 seconds per stack
		"icon": "❄️",
		"color": Color.CYAN
	}
}


func _ready():
	set_process(true)


func initialize(p_combat_scene):
	"""Initialize the manager with reference to combat scene"""
	combat_scene = p_combat_scene


func set_active_lane(lane_index: int):
	"""Set the currently active lane for lane-aware DOT timing"""
	active_lane_index = lane_index


func _process(delta: float):
	"""Process status effect ticks for ships in active lane"""
	if combat_scene == null or active_lane_index < 0:
		return

	# Process status effects only for ships in the active lane
	var ships = get_ships_in_active_lane()
	for ship in ships:
		if not ship.get("enabled", false):
			continue

		if not ship.has("status_effects"):
			continue

		# Process each status effect on the ship
		var effects = ship["status_effects"]
		var effects_to_remove = []

		for i in range(effects.size()):
			var effect = effects[i]

			# Handle DOT effects (burn, etc.) with tick_interval
			if effect.has("tick_interval"):
				effect["tick_timer"] += delta

				# Check if it's time to tick
				if effect["tick_timer"] >= effect["tick_interval"]:
					effect["tick_timer"] = 0.0
					_process_effect_tick(ship, effect)

					# Decrease duration
					effect["duration"] -= effect["tick_interval"]
					if effect["duration"] <= 0:
						effects_to_remove.append(i)
			else:
				# Handle stat modifier effects (freeze, etc.) without ticks
				# Just decrease duration over time
				effect["duration"] -= delta

				# Debug: Print freeze duration countdown
				if effect["type"] == "freeze":
					print("CombatStatusEffectManager: Freeze on ", ship.get("type", "unknown"), " - Duration: %.2f, Stacks: %d" % [effect["duration"], effect.get("stacks", 1)])

				if effect["duration"] <= 0:
					effects_to_remove.append(i)
					print("CombatStatusEffectManager: Marking ", effect["type"], " for removal on ", ship.get("type", "unknown"))

		# Remove expired effects (in reverse order to maintain indices)
		for i in range(effects_to_remove.size() - 1, -1, -1):
			var effect_index = effects_to_remove[i]
			var removed_effect = effects[effect_index]
			effects.remove_at(effect_index)
			emit_signal("status_removed", ship, removed_effect["type"])
			update_status_visual(ship)

		# Note: Card effects (like Cryo Rounds) are NOT time-based
		# They persist for the entire lane combat and are cleared manually
		# during the post-combat cleanup phase by Combat_2.clear_card_effects_for_active_lane()


func _process_effect_tick(ship: Dictionary, effect: Dictionary):
	"""Process a single tick of a status effect"""
	match effect["type"]:
		"burn":
			_process_burn_tick(ship, effect)


func _process_burn_tick(ship: Dictionary, effect: Dictionary):
	"""Process burn DOT damage"""
	var damage = effect["damage_per_tick"] * effect["stacks"]

	print("CombatStatusEffectManager: Burn tick - Ship:", ship.get("type", "unknown"), " | Damage:", damage, " | Stacks:", effect["stacks"])

	var remaining_damage = damage
	var shield_damage = 0
	var armor_damage = 0

	# Apply to shield first
	if ship.get("current_shield", 0) > 0:
		shield_damage = min(remaining_damage, ship["current_shield"])
		ship["current_shield"] -= shield_damage
		remaining_damage -= shield_damage

	# Apply remaining damage to armor
	if remaining_damage > 0:
		armor_damage = min(remaining_damage, ship.get("current_armor", 0))
		ship["current_armor"] = max(0, ship.get("current_armor", 0) - armor_damage)

	var total_damage = shield_damage + armor_damage

	print("  Shield damage:", shield_damage, " | Armor damage:", armor_damage, " | Total:", total_damage)

	# Emit signal for visual feedback
	emit_signal("status_tick", ship, "burn", total_damage)

	# Update ship visual
	if combat_scene and combat_scene.has_method("update_health_bar"):
		combat_scene.update_health_bar(ship)

	# Show damage number
	show_burn_damage_number(ship, total_damage)

	# Check if ship died from burn
	if ship["current_armor"] <= 0:
		if combat_scene and combat_scene.has_method("handle_ship_death"):
			combat_scene.handle_ship_death(ship)


func apply_burn(target: Dictionary, stacks: int = 1):
	"""Apply burn status to a target ship"""
	print("CombatStatusEffectManager: apply_burn called - Target:", target.get("type", "unknown"), " | Stacks:", stacks)

	if not target.has("status_effects"):
		target["status_effects"] = []
		print("  Created status_effects array")

	# Check if burn already exists
	var existing_burn = null
	for effect in target["status_effects"]:
		if effect["type"] == "burn":
			existing_burn = effect
			break

	if existing_burn:
		# Add stacks and refresh duration
		existing_burn["stacks"] += stacks
		existing_burn["duration"] = STATUS_CONFIGS["burn"]["duration"]
		print("  Added to existing burn - New stacks:", existing_burn["stacks"])
	else:
		# Create new burn effect
		var burn_effect = {
			"type": "burn",
			"stacks": stacks,
			"duration": STATUS_CONFIGS["burn"]["duration"],
			"damage_per_tick": STATUS_CONFIGS["burn"]["damage_per_tick"],
			"tick_interval": STATUS_CONFIGS["burn"]["tick_interval"],
			"tick_timer": 0.0
		}
		target["status_effects"].append(burn_effect)
		print("  Created new burn effect")

	# Emit signal and update visual
	emit_signal("status_applied", target, "burn", stacks)
	update_status_visual(target)
	print("  Visual updated")


func apply_freeze(target: Dictionary, stacks: int = 1):
	"""Apply freeze status to a target ship - each stack tracked individually"""
	print("CombatStatusEffectManager: apply_freeze called - Target:", target.get("type", "unknown"), " | Stacks:", stacks)

	if not target.has("status_effects"):
		target["status_effects"] = []
		print("  Created status_effects array")

	# Create individual freeze effects for each stack (each with its own 2s timer)
	for i in range(stacks):
		var freeze_effect = {
			"type": "freeze",
			"stacks": 1,  # Each effect represents 1 stack
			"duration": STATUS_CONFIGS["freeze"]["duration"]
		}
		target["status_effects"].append(freeze_effect)
		print("  Created freeze stack #", i + 1, " with 2s duration")

	# Emit signal and update visual
	emit_signal("status_applied", target, "freeze", stacks)
	update_status_visual(target)
	print("  Visual updated")


func get_freeze_attack_speed_multiplier(ship: Dictionary) -> float:
	"""Get attack speed multiplier based on freeze stacks (multiplicative)"""
	if not ship.has("status_effects"):
		return 1.0

	var multiplier = 1.0
	var freeze_multiplier = STATUS_CONFIGS["freeze"]["attack_speed_multiplier"]

	# Count all freeze effects (each effect = 1 stack with individual timer)
	for effect in ship["status_effects"]:
		if effect["type"] == "freeze":
			# Each freeze effect applies the multiplier once (0.75 per stack)
			multiplier *= freeze_multiplier

	return multiplier


func get_freeze_evasion_multiplier(ship: Dictionary) -> float:
	"""Get evasion multiplier based on freeze stacks (multiplicative)"""
	if not ship.has("status_effects"):
		return 1.0

	var multiplier = 1.0
	var freeze_multiplier = STATUS_CONFIGS["freeze"]["evasion_multiplier"]

	# Count all freeze effects (each effect = 1 stack with individual timer)
	for effect in ship["status_effects"]:
		if effect["type"] == "freeze":
			# Each freeze effect applies the multiplier once (0.75 per stack)
			multiplier *= freeze_multiplier

	return multiplier


func remove_status(target: Dictionary, effect_type: String):
	"""Remove a specific status effect from target"""
	if not target.has("status_effects"):
		return

	var effects = target["status_effects"]
	for i in range(effects.size() - 1, -1, -1):
		if effects[i]["type"] == effect_type:
			effects.remove_at(i)
			emit_signal("status_removed", target, effect_type)
			update_status_visual(target)
			break


func clear_all_status(target: Dictionary):
	"""Clear all status effects from target"""
	if target.has("status_effects"):
		target["status_effects"].clear()
		update_status_visual(target)


func get_status_stacks(target: Dictionary, effect_type: String) -> int:
	"""Get the number of stacks of a status effect on target"""
	if not target.has("status_effects"):
		return 0

	for effect in target["status_effects"]:
		if effect["type"] == effect_type:
			return effect.get("stacks", 1)

	return 0


func update_status_visual(ship: Dictionary):
	"""Update the visual indicator for status effects on a ship"""
	print("CombatStatusEffectManager: update_status_visual called - Ship:", ship.get("type", "unknown"))

	if not ship.has("container"):
		print("  No container on ship!")
		return

	var container = ship["container"]
	if not is_instance_valid(container):
		print("  Container not valid!")
		return

	print("  Container valid, updating icons")

	# Find or create status icon container
	var status_container = container.get_node_or_null("StatusIcons")
	if status_container == null:
		status_container = HBoxContainer.new()
		status_container.name = "StatusIcons"
		status_container.position = Vector2(0, -20)  # Above health bar
		status_container.custom_minimum_size = Vector2(32, 16)
		status_container.alignment = BoxContainer.ALIGNMENT_CENTER
		container.add_child(status_container)
		print("  Created new StatusIcons container")
	else:
		print("  Using existing StatusIcons container")

	# Clear existing icons
	for child in status_container.get_children():
		child.queue_free()

	# Count status effects by type (for effects like freeze with individual stacks)
	var effect_counts = {}
	if ship.has("status_effects"):
		print("  Ship has", ship["status_effects"].size(), "status effects")
		for effect in ship["status_effects"]:
			var effect_type = effect["type"]
			if not effect_counts.has(effect_type):
				effect_counts[effect_type] = 0
			effect_counts[effect_type] += effect.get("stacks", 1)

	# Display grouped status effects
	for effect_type in effect_counts.keys():
		var icon_label = Label.new()
		var config = STATUS_CONFIGS.get(effect_type, {})
		var icon_text = config.get("icon", "•")
		var total_stacks = effect_counts[effect_type]

		if total_stacks > 1:
			icon_label.text = "%s%d" % [icon_text, total_stacks]
		else:
			icon_label.text = icon_text

		print("  Creating icon label with text:", icon_label.text, " for ", effect_type)

		icon_label.add_theme_color_override("font_color", config.get("color", Color.WHITE))
		icon_label.add_theme_font_size_override("font_size", 10)
		status_container.add_child(icon_label)
		print("  Icon label added to container")


func show_burn_damage_number(ship: Dictionary, damage: int):
	"""Show floating damage number for burn DOT"""
	if not ship.has("container"):
		return

	var container = ship["container"]
	if not is_instance_valid(container):
		return

	# Create damage label
	var damage_label = Label.new()
	damage_label.text = "🔥-%d" % damage
	damage_label.add_theme_color_override("font_color", Color.ORANGE_RED)
	damage_label.add_theme_font_size_override("font_size", 10)
	damage_label.position = Vector2(container.size.x / 2, 0)
	container.add_child(damage_label)

	# Animate upward and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(damage_label, "position:y", -30, 1.0)
	tween.tween_property(damage_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(damage_label.queue_free)


func _remove_card_effect(ship: Dictionary, effect: Dictionary):
	"""Remove a card effect and clean up its modifications"""
	match effect["type"]:
		"cryo_rounds":
			_remove_cryo_rounds(ship)


func _remove_cryo_rounds(ship: Dictionary):
	"""Remove Cryo Rounds effect from ship"""
	print("CombatStatusEffectManager: Removing Cryo Rounds from ", ship.get("type", "unknown"))

	# Remove ice from damage_types
	if ship.has("damage_types") and "ice" in ship["damage_types"]:
		ship["damage_types"].erase("ice")
		print("  Removed ice damage type")

	# Remove freeze_on_hit_chance
	if ship.has("freeze_on_hit_chance"):
		ship.erase("freeze_on_hit_chance")
		print("  Removed freeze_on_hit_chance")

	# Show notification
	if ship.has("container") and is_instance_valid(ship["container"]):
		var notification = Label.new()
		notification.text = "CRYO AMMO EXPIRED"
		notification.add_theme_color_override("font_color", Color.GRAY)
		notification.add_theme_font_size_override("font_size", 8)
		notification.position = Vector2(0, -30)
		notification.z_index = 10
		ship["container"].add_child(notification)

		# Fade out and remove
		var tween = create_tween()
		tween.tween_property(notification, "modulate:a", 0.0, 1.0)
		tween.tween_callback(notification.queue_free)


func get_ships_in_active_lane() -> Array:
	"""Get all ships in the currently active lane"""
	if combat_scene == null or active_lane_index < 0:
		return []

	# Get ships from the lanes array in combat scene
	if not "lanes" in combat_scene or combat_scene.lanes == null:
		return []

	if active_lane_index >= combat_scene.lanes.size():
		return []

	# Return all units in the active lane
	return combat_scene.lanes[active_lane_index]["units"]

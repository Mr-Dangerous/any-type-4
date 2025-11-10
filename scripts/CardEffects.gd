extends Node

## CardEffects Static Class
## Implements all card effect functions
## Each card's card_function maps to a method here

class_name CardEffects

static func execute_card_effect(function_name: String, target, combat_scene: Node) -> bool:
	"""Execute a card effect by function name"""
	print("CardEffects: Executing ", function_name)
	
	match function_name:
		"execute_Strike":
			return execute_Strike(target, combat_scene)
		"execute_Shield":
			return execute_Shield(target, combat_scene)
		"execute_Energy_Alpha":
			return execute_Energy_Alpha(target, combat_scene)
		"execute_Turret_Blast":
			return execute_Turret_Blast(target, combat_scene)
		_:
			push_error("CardEffects: Unknown function: " + function_name)
			return false

static func execute_Strike(target, _combat_scene: Node) -> bool:
	"""Target ship gains +50% attack speed"""
	if not target is Dictionary or not target.has("container"):
		return false
	
	var ship_type = target.get("type", "")
	if ship_type == "":
		return false
	
	# Increase attack speed by 50%
	var current_speed = target.get("stats", {}).get("attack_speed", 1.0)
	var new_speed = current_speed * 1.5
	target["stats"]["attack_speed"] = new_speed
	
	print("CardEffects: Strike - Increased attack speed of ", ship_type, " to ", new_speed)
	
	# Show notification
	show_effect_notification(target, "+50% ATTACK SPEED", Color.ORANGE)
	
	return true

static func execute_Shield(target, combat_scene: Node) -> bool:
	"""Target ship gains 30 shields (excess becomes overshield at 1/3 rate)"""
	if not target is Dictionary or not target.has("container"):
		return false
	
	var ship_type = target.get("type", "")
	if ship_type == "":
		return false
	
	# Calculate shield application with overshield mechanic
	var current_shield = target.get("current_shield", 0)
	var max_shield = target.get("stats", {}).get("shield", 100)
	var shield_to_add = 30
	
	var shield_space = max_shield - current_shield
	
	if shield_space >= shield_to_add:
		# All shields fit normally
		target["current_shield"] = current_shield + shield_to_add
		print("CardEffects: Shield - Added ", shield_to_add, " shields to ", ship_type, " (now ", target["current_shield"], ")")
		show_effect_notification(target, "+30 SHIELD", Color.CYAN)
	else:
		# Fill normal shields, convert overflow to overshield at 1/3 rate (min 1)
		var normal_shield_gain = shield_space
		var overflow = shield_to_add - normal_shield_gain
		var overshield_gain = max(1, int(overflow / 3.0))
		
		target["current_shield"] = max_shield
		var current_overshield = target.get("current_overshield", 0)
		target["current_overshield"] = current_overshield + overshield_gain
		
		print("CardEffects: Shield - Added ", normal_shield_gain, " shields + ", overshield_gain, " overshield to ", ship_type)
		show_effect_notification(target, "+%d SHIELD\n+%d OVERSHIELD" % [normal_shield_gain, overshield_gain], Color.GOLD)
	
	# Update UI if exists
	update_ship_ui(target, combat_scene)
	
	return true

static func execute_Energy_Alpha(target, combat_scene: Node) -> bool:
	"""Target ship gains 100 energy"""
	if not target is Dictionary or not target.has("container"):
		print("CardEffects: Energy Alpha - Invalid target (not dictionary or no container)")
		return false
	
	var ship_type = target.get("type", "")
	if ship_type == "":
		print("CardEffects: Energy Alpha - Invalid target (no type)")
		return false
	
	# Add 100 energy
	var current_energy = target.get("current_energy", 0)
	# Max energy is stored as "energy" in stats (not "starting_energy")
	var max_energy = target.get("stats", {}).get("energy", 100)
	var new_energy = min(current_energy + 100, max_energy)
	
	print("CardEffects: Energy Alpha - Before: ", current_energy, " | Adding: 100 | Max: ", max_energy)
	target["current_energy"] = new_energy
	print("CardEffects: Energy Alpha - After: ", target["current_energy"], " | Ship: ", ship_type)
	
	# Update energy bar if combat scene has the function
	if combat_scene and combat_scene.has_method("update_energy_bar"):
		combat_scene.update_energy_bar(target)
	
	# Check if energy reached max - cast ability immediately (only if combat is not paused)
	if new_energy >= max_energy and combat_scene and combat_scene.has_method("cast_ability"):
		if not combat_scene.get("combat_paused"):
			print("CardEffects: Energy Alpha - Energy at max! Casting ability for ", ship_type)
			combat_scene.cast_ability(target)
		else:
			print("CardEffects: Energy Alpha - Energy at max but combat is paused, ability will cast when combat starts")
	
	# Show notification
	show_effect_notification(target, "+100 ENERGY", Color.YELLOW)
	
	return true

static func execute_Turret_Blast(target, combat_scene: Node) -> bool:
	"""Activate a turret ability"""
	if not target is Dictionary or not target.has("container"):
		return false
	
	# Check if target is actually a turret
	if target.get("object_type") != "turret":
		print("CardEffects: Turret Blast - Target is not a turret")
		return false
	
	var turret_type = target.get("type", "")
	print("CardEffects: Turret Blast - Activating turret ", turret_type)
	
	# Trigger turret ability
	# Get the combat scene's ability manager
	if combat_scene and combat_scene.has_method("cast_ability"):
		combat_scene.cast_ability(target)
	
	# Show notification
	show_effect_notification(target, "TURRET ACTIVATED", Color.RED)
	
	return true

static func show_effect_notification(target: Dictionary, text: String, color: Color):
	"""Show a popup notification above the target"""
	var container = target.get("container")
	if not container:
		return
	
	# Create notification label
	var notification = Label.new()
	notification.text = text
	notification.add_theme_font_size_override("font_size", 16)
	notification.add_theme_color_override("font_color", color)
	notification.add_theme_color_override("font_outline_color", Color.BLACK)
	notification.add_theme_constant_override("outline_size", 2)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.z_index = 1000
	
	# Position above target
	var parent = container.get_parent()
	if parent:
		parent.add_child(notification)
		notification.global_position = container.global_position + Vector2(container.size.x / 2 - 50, -30)
		
		# Animate and fade out
		var tween = notification.create_tween()
		tween.set_parallel(true)
		tween.tween_property(notification, "position:y", notification.position.y - 40, 1.0)
		tween.tween_property(notification, "modulate:a", 0.0, 1.0).set_delay(0.5)
		
		await tween.finished
		notification.queue_free()

static func update_ship_ui(ship: Dictionary, combat_scene: Node):
	"""Update the ship's UI display (health bars, shields, etc.)"""
	# The combat scene should have UI update methods
	if combat_scene and combat_scene.has_method("update_ship_display"):
		combat_scene.update_ship_display(ship)
	
	# Alternative: Update the ship's own UI if it has one
	var container = ship.get("container")
	if container and container.has_node("UI"):
		var ui = container.get_node("UI")
		if ui.has_method("update_display"):
			ui.update_display(ship)

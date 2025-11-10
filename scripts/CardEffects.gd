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
		"execute_Missile_Lock":
			return execute_Missile_Lock(target, combat_scene)
		"execute_Missile_Lock_Effect":
			return await execute_Missile_Lock_Effect(target, combat_scene)
		_:
			print("CardEffects: Unknown function (not yet implemented): " + function_name)
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

static func execute_Missile_Lock(target, combat_scene: Node) -> bool:
	"""Queue Missile Lock ability for a friendly ship"""
	if not target is Dictionary or not target.has("container"):
		print("CardEffects: Missile Lock - Invalid target (not dictionary or no container)")
		return false

	# Validate target is a friendly ship
	var is_enemy = target.get("is_enemy", true)
	if is_enemy:
		print("CardEffects: Missile Lock - Target must be a friendly ship, not enemy")
		return false

	# Validate target type (must be a ship with ability_stack)
	var object_type = target.get("object_type", "")
	if object_type != "ship":
		print("CardEffects: Missile Lock - Target must be a ship, got: ", object_type)
		return false

	if not target.has("ability_stack"):
		print("CardEffects: Missile Lock - Target ship has no ability_stack")
		return false

	var ship_name = target.get("type", "Unknown")
	print("CardEffects: Missile Lock - Queuing Missile Lock for ", ship_name)

	# Create ability data
	var ability_data = {
		"ability_name": "Missile Lock",
		"ability_function": "execute_Missile_Lock_Effect",  # Actual execution function
		"source": "card"  # This was from a card, not ship energy
	}

	# Queue the ability on the target ship
	if combat_scene and combat_scene.has_method("queue_ability_for_ship"):
		combat_scene.queue_ability_for_ship(target, ability_data)

	# Show notification
	show_effect_notification(target, "MISSILE LOCK QUEUED", Color.ORANGE)

	return true

static func execute_Missile_Lock_Effect(target: Dictionary, combat_scene: Node) -> bool:
	"""Fire a missile projectile with fixed 50 damage and 0.4s flight time"""
	if not target.has("sprite") or not is_instance_valid(target.get("sprite")):
		print("CardEffects: Missile Lock Effect - Invalid target sprite")
		return false

	# Get card data from DataManager to access projectile properties
	var card_data = DataManager.get_card_data("Missile Lock")

	# Missile properties from card database
	var missile_sprite_path = card_data.get("projectile_sprite_path", "res://assets/Effects/s_fxProjectile_2_drone/s_fxProjectile_2_drone.png")
	var missile_size_raw = card_data.get("projectile size", "70")  # Column name has space
	var missile_size = int(missile_size_raw) if missile_size_raw != "" else 70  # Convert from String to int
	var missile_damage = 50
	var missile_flight_time = 0.4

	# Load missile texture
	var missile_texture = load(missile_sprite_path)
	if missile_texture == null:
		print("CardEffects: Failed to load missile texture: ", missile_sprite_path)
		return false

	# Create missile sprite
	var missile = Sprite2D.new()
	missile.texture = missile_texture
	missile.z_index = 1

	# Get start position (center of screen, since card was played)
	# For now, we'll start from a position slightly off-screen left
	var viewport_size = combat_scene.get_viewport_rect().size
	var start_pos = Vector2(viewport_size.x * 0.3, viewport_size.y * 0.5)

	# Get end position (target)
	var end_pos = target["sprite"].global_position

	# Calculate angle and scale
	var angle = start_pos.angle_to_point(end_pos)
	missile.rotation = angle

	# Scale missile based on missile_size
	var texture_height = missile_texture.get_height()
	var scale_y = missile_size / float(texture_height) if texture_height > 0 else 1.0
	missile.scale = Vector2(scale_y, scale_y)

	# Position missile
	missile.position = start_pos
	combat_scene.add_child(missile)

	# Animate missile to target
	var tween = combat_scene.create_tween()
	tween.tween_property(missile, "position", end_pos, missile_flight_time)

	# Wait for animation to complete, then handle impact
	await tween.finished

	# Remove missile
	missile.queue_free()

	# Validate target still exists
	if not target.has("sprite") or not is_instance_valid(target.get("sprite")):
		print("CardEffects: Missile Lock - Target no longer valid")
		return false

	# Apply fixed 50 damage (no accuracy/crit calculations)
	var damage_applied = apply_missile_damage(target, missile_damage)

	# Flash target sprite
	if target.has("sprite") and is_instance_valid(target.get("sprite")):
		var sprite = target["sprite"]
		var original_modulate = sprite.modulate
		sprite.modulate = Color(2, 2, 2, 1)
		await combat_scene.get_tree().create_timer(0.1).timeout
		if is_instance_valid(sprite):
			sprite.modulate = original_modulate

	# Show damage number
	show_missile_damage_number(target, missile_damage, damage_applied, combat_scene)

	print("CardEffects: Missile Lock - Hit ", target.get("type", "target"), " for ", missile_damage, " damage")

	return true

static func apply_missile_damage(target: Dictionary, damage: int) -> Dictionary:
	"""Apply missile damage to target (shield first, then armor)"""
	var shield_damage = 0
	var armor_damage = 0
	var remaining_damage = damage

	# Apply to overshield first (if exists)
	if target.has("current_overshield") and target.get("current_overshield", 0) > 0:
		var overshield_damage = min(remaining_damage, target["current_overshield"])
		target["current_overshield"] -= overshield_damage
		remaining_damage -= overshield_damage
		shield_damage += overshield_damage

	# Apply to shield
	if remaining_damage > 0 and target.get("current_shield", 0) > 0:
		var shield_dmg = min(remaining_damage, target["current_shield"])
		target["current_shield"] -= shield_dmg
		remaining_damage -= shield_dmg
		shield_damage += shield_dmg

	# Apply remaining damage to armor
	if remaining_damage > 0:
		armor_damage = min(remaining_damage, target.get("current_armor", 0))
		target["current_armor"] = max(0, target.get("current_armor", 0) - armor_damage)

	# Check if destroyed
	var destroyed = target.get("current_armor", 0) <= 0

	return {
		"shield_damage": shield_damage,
		"armor_damage": armor_damage,
		"destroyed": destroyed,
		"total_damage": shield_damage + armor_damage
	}

static func show_missile_damage_number(target: Dictionary, intended_damage: int, damage_info: Dictionary, combat_scene: Node):
	"""Show damage number for missile hit"""
	if not target.has("sprite"):
		return

	var pos = target["sprite"].global_position
	var total_damage = damage_info.get("total_damage", 0)

	# Create damage label
	var damage_label = Label.new()
	damage_label.text = str(total_damage)
	damage_label.add_theme_font_size_override("font_size", 24)
	damage_label.add_theme_color_override("font_color", Color.ORANGE_RED)
	damage_label.add_theme_color_override("font_outline_color", Color.BLACK)
	damage_label.add_theme_constant_override("outline_size", 3)
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.z_index = 1000

	combat_scene.add_child(damage_label)
	damage_label.global_position = pos + Vector2(-20, -40)

	# Animate
	var tween = damage_label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(damage_label, "position:y", damage_label.position.y - 60, 1.2)
	tween.tween_property(damage_label, "modulate:a", 0.0, 1.2).set_delay(0.3)

	await tween.finished
	damage_label.queue_free()

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

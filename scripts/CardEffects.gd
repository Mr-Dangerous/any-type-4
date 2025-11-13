extends Node

## CardEffects Static Class
## Implements all card effect functions
## Each card's card_function maps to a method here

class_name CardEffects

static func execute_card_effect_cinematic(function_name: String, source, target, combat_scene: Node) -> bool:
	"""Execute a card effect in cinematic mode (slow-motion projectile)"""
	print("CardEffects: Executing CINEMATIC ", function_name)

	# For now, just call the effect version which handles projectiles
	# We'll modify the effect functions to accept a cinematic flag
	match function_name:
		"execute_Incinerator_Cannon_Effect":
			return await execute_Incinerator_Cannon_Effect_Cinematic(source, target, combat_scene)
		"execute_Missile_Lock_Effect":
			return await execute_Missile_Lock_Effect_Cinematic(source, target, combat_scene)
		_:
			print("CardEffects: No cinematic version for: " + function_name)
			return false

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
		"execute_Energy_Beta":
			return execute_Energy_Beta(target, combat_scene)
		"execute_Turret_Blast":
			return execute_Turret_Blast(target, combat_scene)
		"execute_Missile_Lock":
			return execute_Missile_Lock(target, combat_scene)
		"execute_Missile_Lock_Effect":
			return await execute_Missile_Lock_Effect(target, combat_scene)
		"execute_Incendiary_Rounds":
			return execute_Incendiary_Rounds(target, combat_scene)
		"execute_Cryo_Rounds":
			return execute_Cryo_Rounds(target, combat_scene)
		"execute_Incinerator_Cannon":
			return execute_Incinerator_Cannon(target, combat_scene)
		"execute_Incinerator_Cannon_Effect":
			return await execute_Incinerator_Cannon_Effect(target, combat_scene)
		"execute_Shield_Battery":
			return execute_Shield_Battery(target, combat_scene)
		"execute_Shield_Battery_Effect":
			return await execute_Shield_Battery_Effect(target, combat_scene)
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

static func execute_Energy_Beta(target, combat_scene: Node) -> bool:
	"""Target ship gains 75 energy + AoE(1): ships at distance 1 gain 37 energy"""
	if not target is Dictionary or not target.has("container"):
		print("CardEffects: Energy Beta - Invalid target (not dictionary or no container)")
		return false

	var ship_type = target.get("type", "")
	if ship_type == "":
		print("CardEffects: Energy Beta - Invalid target (no type)")
		return false

	# Apply 75 energy to primary target
	var current_energy = target.get("current_energy", 0)
	var max_energy = target.get("stats", {}).get("energy", 100)
	var energy_to_add = 75
	var new_energy = min(current_energy + energy_to_add, max_energy)

	print("CardEffects: Energy Beta - Primary Target: ", ship_type, " | Before: ", current_energy, " | Adding: ", energy_to_add)
	target["current_energy"] = new_energy

	# Update energy bar for primary target
	if combat_scene and combat_scene.has_method("update_energy_bar"):
		combat_scene.update_energy_bar(target)

	# Check if energy reached max for primary target
	if new_energy >= max_energy and combat_scene and combat_scene.has_method("cast_ability"):
		if not combat_scene.get("combat_paused"):
			print("CardEffects: Energy Beta - Primary target energy at max! Casting ability for ", ship_type)
			combat_scene.cast_ability(target)

	# Show notification for primary target
	show_effect_notification(target, "+75 ENERGY", Color.YELLOW)

	# Apply AoE effect with range 1, friendly targets only
	var affected_ships = apply_aoe_effect(target, energy_to_add, 1, "friendly", "energy", combat_scene)

	print("CardEffects: Energy Beta - Affected ", affected_ships.size(), " additional ships with AoE")

	return true

static func apply_aoe_effect(primary_target: Dictionary, base_value: int, aoe_range: int, target_faction: String, effect_type: String, combat_scene: Node) -> Array:
	"""
	Apply AoE effect to ships near primary target.
	Effect reduces by 50% per Manhattan distance unit (rounded down).
	Returns array of affected ships (excluding primary target).

	Parameters:
	- primary_target: The ship directly targeted by the card
	- base_value: The base effect value (will be halved per distance)
	- aoe_range: Maximum Manhattan distance to affect
	- target_faction: "friendly" or "enemy" - filters which ships to affect
	- effect_type: Type of effect ("energy", "shield", "damage", etc.)
	- combat_scene: Reference to combat scene for accessing ships
	"""
	var affected_ships = []

	# Get primary target position
	var primary_row = primary_target.get("grid_row", -1)
	var primary_col = primary_target.get("grid_col", -1)

	if primary_row == -1 or primary_col == -1:
		print("CardEffects: AoE - Primary target has no grid position")
		return affected_ships

	# Get all ships from combat scene
	var all_ships = []
	if combat_scene and combat_scene.has_method("get_all_ships"):
		all_ships = combat_scene.get_all_ships()
	else:
		print("CardEffects: AoE - Combat scene doesn't have get_all_ships method")
		return affected_ships

	# Determine if we're targeting friendlies or enemies
	var primary_is_enemy = primary_target.get("is_enemy", false)
	var target_is_enemy = (target_faction == "enemy")

	# For friendly faction, target ships with same is_enemy value as primary
	# For enemy faction, target ships with opposite is_enemy value
	var looking_for_enemy = primary_is_enemy if (target_faction == "friendly") else (not primary_is_enemy)

	print("CardEffects: AoE - Primary at (", primary_row, ",", primary_col, ") | Range: ", aoe_range, " | Target faction: ", target_faction)

	# Find and affect ships within range
	for ship in all_ships:
		# Skip the primary target
		if ship == primary_target:
			continue

		# Check faction
		var ship_is_enemy = ship.get("is_enemy", false)
		if ship_is_enemy != looking_for_enemy:
			continue

		# Get ship position
		var ship_row = ship.get("grid_row", -1)
		var ship_col = ship.get("grid_col", -1)

		if ship_row == -1 or ship_col == -1:
			continue

		# Calculate Manhattan distance
		var manhattan_dist = abs(ship_row - primary_row) + abs(ship_col - primary_col)

		# Skip if out of range
		if manhattan_dist > aoe_range or manhattan_dist == 0:
			continue

		# Calculate reduced effect value (halved per distance, rounded down)
		var effect_value = base_value
		for i in range(manhattan_dist):
			effect_value = int(effect_value / 2.0)

		if effect_value <= 0:
			continue

		print("CardEffects: AoE - Affecting ", ship.get("type", "Unknown"), " at distance ", manhattan_dist, " with value ", effect_value)

		# Apply effect based on type
		match effect_type:
			"energy":
				apply_energy_effect(ship, effect_value, combat_scene)
			"shield":
				apply_shield_effect(ship, effect_value, combat_scene)
			"damage":
				apply_damage_effect(ship, effect_value, combat_scene)
			_:
				print("CardEffects: AoE - Unknown effect type: ", effect_type)

		affected_ships.append(ship)

	return affected_ships

static func apply_energy_effect(ship: Dictionary, energy_amount: int, combat_scene: Node):
	"""Apply energy to a ship (used by AoE system)"""
	var current_energy = ship.get("current_energy", 0)
	var max_energy = ship.get("stats", {}).get("energy", 100)
	var new_energy = min(current_energy + energy_amount, max_energy)

	ship["current_energy"] = new_energy

	# Update energy bar
	if combat_scene and combat_scene.has_method("update_energy_bar"):
		combat_scene.update_energy_bar(ship)

	# Check if energy reached max
	if new_energy >= max_energy and combat_scene and combat_scene.has_method("cast_ability"):
		if not combat_scene.get("combat_paused"):
			combat_scene.cast_ability(ship)

	# Show notification
	show_effect_notification(ship, "+%d ENERGY" % energy_amount, Color.LIGHT_YELLOW)

static func apply_shield_effect(ship: Dictionary, shield_amount: int, combat_scene: Node):
	"""Apply shield to a ship (used by AoE system)"""
	var current_shield = ship.get("current_shield", 0)
	var max_shield = ship.get("stats", {}).get("shield", 100)
	var shield_space = max_shield - current_shield

	if shield_space >= shield_amount:
		ship["current_shield"] = current_shield + shield_amount
		show_effect_notification(ship, "+%d SHIELD" % shield_amount, Color.CYAN)
	else:
		var normal_shield_gain = shield_space
		var overflow = shield_amount - normal_shield_gain
		var overshield_gain = max(1, int(overflow / 3.0))

		ship["current_shield"] = max_shield
		var current_overshield = ship.get("current_overshield", 0)
		ship["current_overshield"] = current_overshield + overshield_gain

		show_effect_notification(ship, "+%d SHIELD\n+%d OVERSHIELD" % [normal_shield_gain, overshield_gain], Color.GOLD)

	update_ship_ui(ship, combat_scene)

static func apply_damage_effect(ship: Dictionary, damage_amount: int, combat_scene: Node):
	"""Apply damage to a ship (used by AoE system)"""
	var damage_info = apply_missile_damage(ship, damage_amount)
	show_effect_notification(ship, "-%d" % damage_info.get("total_damage", 0), Color.RED)
	update_ship_ui(ship, combat_scene)

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
	"""Fire a missile projectile with fixed 50 damage and 0.4s flight time. AoE(1): 25 damage to adjacent enemies"""
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

	# Apply AoE damage (range 1, half damage to adjacent enemies)
	var affected_ships = apply_aoe_effect(target, missile_damage, 1, "enemy", "damage", combat_scene)

	print("CardEffects: Missile Lock AoE - Affected ", affected_ships.size(), " additional enemy ships")

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

static func execute_Incendiary_Rounds(target, _combat_scene: Node) -> bool:
	"""Target ship attacks become fire damage and have 25% chance to apply 1 burn on hit"""
	if not target is Dictionary or not target.has("container"):
		return false

	var ship_type = target.get("type", "")
	if ship_type == "":
		return false

	# Add fire to damage types (if not already present)
	if not target.has("damage_types"):
		target["damage_types"] = []

	if not "fire" in target["damage_types"]:
		target["damage_types"].append("fire")

	# Set burn application chance (0.25 = 25%)
	target["burn_on_hit_chance"] = 0.25

	print("CardEffects: Incendiary Rounds - Added fire damage and 25% burn chance to ", ship_type)

	# Show notification with fire icon
	show_effect_notification(target, "🔥 FIRE AMMO LOADED", Color.ORANGE_RED)

	return true

static func execute_Cryo_Rounds(target, _combat_scene: Node) -> bool:
	"""Target ship attacks become ice damage and have 25% chance to apply 1 freeze on hit (lasts until lane cleanup)"""
	if not target is Dictionary or not target.has("container"):
		return false

	var ship_type = target.get("type", "")
	if ship_type == "":
		return false

	# Initialize card_effects array if not present
	if not target.has("card_effects"):
		target["card_effects"] = []

	# Check if Cryo Rounds is already active (don't apply twice)
	for effect in target["card_effects"]:
		if effect["type"] == "cryo_rounds":
			print("CardEffects: Cryo Rounds - Already active on ", ship_type)
			show_effect_notification(target, "❄️ CRYO AMMO ACTIVE", Color.CYAN)
			return true

	# Create new card effect (no duration - lasts until lane cleanup)
	var cryo_effect = {
		"type": "cryo_rounds"
	}
	target["card_effects"].append(cryo_effect)

	# Add ice to damage types (if not already present)
	if not target.has("damage_types"):
		target["damage_types"] = []

	if not "ice" in target["damage_types"]:
		target["damage_types"].append("ice")

	# Set freeze application chance (0.25 = 25%)
	target["freeze_on_hit_chance"] = 0.25

	print("CardEffects: Cryo Rounds - Added ice damage and 25% freeze chance to ", ship_type, " (until lane cleanup)")

	# Show notification with ice icon
	show_effect_notification(target, "❄️ CRYO AMMO LOADED", Color.CYAN)

	return true

static func execute_Incinerator_Cannon(target, combat_scene: Node) -> bool:
	"""Queue Incinerator Cannon ability for a friendly ship"""
	if not target is Dictionary or not target.has("container"):
		print("CardEffects: Incinerator Cannon - Invalid target")
		return false

	if not target.has("ability_stack"):
		print("CardEffects: Incinerator Cannon - Target has no ability_stack")
		return false

	var ship_name = target.get("type", "Unknown")
	print("CardEffects: Incinerator Cannon - Queuing for ", ship_name)

	# Create ability data
	var ability_data = {
		"ability_name": "Incinerator Cannon",
		"ability_function": "execute_Incinerator_Cannon_Effect",
		"source": "card"
	}

	# Queue the ability
	if combat_scene and combat_scene.has_method("queue_ability_for_ship"):
		combat_scene.queue_ability_for_ship(target, ability_data)

	# Show notification
	show_effect_notification(target, "INCINERATOR CANNON QUEUED", Color.ORANGE_RED)

	return true

static func execute_Incinerator_Cannon_Effect(target: Dictionary, combat_scene: Node) -> bool:
	"""Fire an incinerator beam projectile with 20 fire damage and 3 burn stacks"""
	if not target.has("sprite") or not is_instance_valid(target.get("sprite")):
		print("CardEffects: Incinerator Cannon Effect - Invalid target sprite")
		return false

	# Get card data from DataManager to access projectile properties
	var card_data = DataManager.get_card_data("Incinerator Cannon")

	# Projectile properties from card database
	var beam_sprite_path = card_data.get("projectile_sprite_path", "res://assets/Effects/laser_huge/s_fxProjectile_2_drone/s_laser_huge_04.png")
	var beam_size_raw = card_data.get("projectile size", "30")
	var beam_size = int(beam_size_raw) if beam_size_raw != "" else 30
	var beam_damage = 20  # Fixed fire damage
	var burn_stacks = 3   # Burn stacks to apply
	var beam_flight_time = 0.3  # Fast beam

	# Load beam texture
	var beam_texture = load(beam_sprite_path)
	if beam_texture == null:
		print("CardEffects: Failed to load beam texture: ", beam_sprite_path)
		return false

	# Create beam sprite
	var beam = Sprite2D.new()
	beam.texture = beam_texture
	beam.z_index = 1

	# Get start position (from friendly ship position)
	var start_pos = target["sprite"].global_position

	# Get end position (target enemy using combat scene's targeting system)
	# Use gamma targeting to select enemy
	var enemy_target = null
	if combat_scene and combat_scene.has_method("select_target_for_unit"):
		enemy_target = combat_scene.select_target_for_unit(target, "gamma")
	elif combat_scene and "targeting_system" in combat_scene:
		var targeting_system = combat_scene.targeting_system
		if targeting_system and targeting_system.has_method("select_target_for_unit"):
			enemy_target = targeting_system.select_target_for_unit(target, "gamma")

	if not enemy_target or (enemy_target is Dictionary and enemy_target.is_empty()):
		print("CardEffects: Incinerator Cannon - No valid enemy target")
		return false

	var end_pos = enemy_target["sprite"].global_position

	# Calculate angle and scale
	var angle = start_pos.angle_to_point(end_pos)
	beam.rotation = angle

	# Scale beam based on beam_size
	var texture_height = beam_texture.get_height()
	var scale_y = beam_size / float(texture_height) if texture_height > 0 else 1.0
	beam.scale = Vector2(scale_y, scale_y)

	# Position beam
	beam.position = start_pos
	combat_scene.add_child(beam)

	# Animate beam to target
	var tween = combat_scene.create_tween()
	tween.tween_property(beam, "position", end_pos, beam_flight_time)

	# Wait for animation to complete, then handle impact
	await tween.finished

	# Remove beam
	beam.queue_free()

	# Validate enemy target still exists
	if not enemy_target.has("sprite") or not is_instance_valid(enemy_target.get("sprite")):
		print("CardEffects: Incinerator Cannon - Target no longer valid")
		return false

	# Apply 20 fire damage (fixed damage, no accuracy/crit)
	var damage_applied = apply_missile_damage(enemy_target, beam_damage)

	# Flash target sprite with orange for fire
	if enemy_target.has("sprite") and is_instance_valid(enemy_target.get("sprite")):
		var sprite = enemy_target["sprite"]
		var original_modulate = sprite.modulate
		sprite.modulate = Color(2, 1, 0.5, 1)  # Orange flash for fire
		await combat_scene.get_tree().create_timer(0.1).timeout
		if is_instance_valid(sprite):
			sprite.modulate = original_modulate

	# Show damage number
	show_missile_damage_number(enemy_target, beam_damage, damage_applied, combat_scene)

	print("CardEffects: Incinerator Cannon - Hit ", enemy_target.get("type", "target"), " for ", beam_damage, " fire damage")

	# Apply 3 stacks of burn
	if combat_scene and "status_effect_manager" in combat_scene:
		var status_manager = combat_scene.status_effect_manager
		if status_manager and status_manager.has_method("apply_burn"):
			status_manager.apply_burn(enemy_target, burn_stacks)
			print("CardEffects: Incinerator Cannon - Applied ", burn_stacks, " burn stacks")

	return true

static func execute_Shield_Battery(target, combat_scene: Node) -> bool:
	"""Queue Shield Battery ability for a friendly ship"""
	if not target is Dictionary or not target.has("container"):
		print("CardEffects: Shield Battery - Invalid target")
		return false
	
	# Validate target is a friendly ship
	var is_enemy = target.get("is_enemy", true)
	if is_enemy:
		print("CardEffects: Shield Battery - Target must be friendly")
		return false
	
	if not target.has("ability_stack"):
		print("CardEffects: Shield Battery - Target has no ability_stack")
		return false
	
	var ship_name = target.get("type", "Unknown")
	print("CardEffects: Shield Battery - Queuing for ", ship_name)
	
	# Create ability data
	var ability_data = {
		"ability_name": "Shield Battery",
		"ability_function": "execute_Shield_Battery_Effect",
		"source": "card"
	}
	
	# Queue the ability
	if combat_scene and combat_scene.has_method("queue_ability_for_ship"):
		combat_scene.queue_ability_for_ship(target, ability_data)
	
	# Show notification
	show_effect_notification(target, "SHIELD BATTERY QUEUED", Color.CYAN)
	
	return true

static func apply_aoe_full_effect(primary_target: Dictionary, base_value: int, aoe_range: int, target_faction: String, effect_type: String, combat_scene: Node) -> Array:
	"""
	Apply AoE effect with FULL value (no reduction) to all ships within range.
	Unlike apply_aoe_effect, this does not reduce effect by distance.
	
	Parameters:
	- primary_target: The ship directly targeted by the card
	- base_value: The effect value to apply (same for all ships in range)
	- aoe_range: Maximum Manhattan distance to affect
	- target_faction: "friendly" or "enemy" - filters which ships to affect
	- effect_type: Type of effect ("energy", "shield", "damage", etc.)
	- combat_scene: Reference to combat scene for accessing ships
	"""
	var affected_ships = []
	
	# Get primary target position
	var primary_row = primary_target.get("grid_row", -1)
	var primary_col = primary_target.get("grid_col", -1)
	
	if primary_row == -1 or primary_col == -1:
		print("CardEffects: AoE Full - Primary target has no grid position")
		return affected_ships
	
	# Get all ships
	var all_ships = []
	if combat_scene and combat_scene.has_method("get_all_ships"):
		all_ships = combat_scene.get_all_ships()
	else:
		print("CardEffects: AoE Full - Combat scene doesn't have get_all_ships method")
		return affected_ships
	
	# Determine target faction
	var primary_is_enemy = primary_target.get("is_enemy", false)
	var looking_for_enemy = primary_is_enemy if (target_faction == "friendly") else (not primary_is_enemy)
	
	print("CardEffects: AoE Full - Primary at (", primary_row, ",", primary_col, ") | Range: ", aoe_range, " | Target faction: ", target_faction)
	
	# Find and affect ships within range
	for ship in all_ships:
		# Skip the primary target (it's already been affected)
		if ship == primary_target:
			continue
		
		# Check faction
		if ship.get("is_enemy", false) != looking_for_enemy:
			continue
		
		# Get ship position
		var ship_row = ship.get("grid_row", -1)
		var ship_col = ship.get("grid_col", -1)
		
		if ship_row == -1 or ship_col == -1:
			continue
		
		# Calculate Manhattan distance
		var manhattan_dist = abs(ship_row - primary_row) + abs(ship_col - primary_col)
		
		# Skip if out of range
		if manhattan_dist > aoe_range or manhattan_dist == 0:
			continue
		
		print("CardEffects: AoE Full - Affecting ", ship.get("type", "Unknown"), " at distance ", manhattan_dist, " with FULL value ", base_value)
		
		# Apply FULL effect (no distance reduction)
		match effect_type:
			"shield":
				apply_shield_effect(ship, base_value, combat_scene)
			"energy":
				apply_energy_effect(ship, base_value, combat_scene)
			"damage":
				apply_damage_effect(ship, base_value, combat_scene)
			_:
				print("CardEffects: AoE Full - Unknown effect type: ", effect_type)
		
		affected_ships.append(ship)
	
	return affected_ships

static func display_aura_effect(target: Dictionary, combat_scene: Node):
	"""Display aura effect sprite at target location"""
	var card_data = DataManager.get_card_data("Shield Battery")
	var aura_path = card_data.get("aura_sprite_path", "")
	var aura_size_str = card_data.get("aura_size", "90")
	var aura_size = int(aura_size_str) if aura_size_str != "" else 90
	
	if aura_path == "":
		print("CardEffects: Display Aura - No aura path specified")
		return
	
	var aura_texture = load(aura_path)
	if aura_texture == null:
		print("CardEffects: Failed to load aura texture: ", aura_path)
		return
	
	# Create aura sprite
	var aura = Sprite2D.new()
	aura.texture = aura_texture
	aura.z_index = 10
	
	# Scale based on aura_size
	var texture_height = aura_texture.get_height()
	var scale_factor = aura_size / float(texture_height) if texture_height > 0 else 1.0
	aura.scale = Vector2(scale_factor, scale_factor)
	
	# Position at target
	aura.position = target["sprite"].global_position
	combat_scene.add_child(aura)
	
	print("CardEffects: Display Aura - Created aura at ", aura.position, " with scale ", scale_factor)
	
	# Fade out animation (1 second visible, then 0.5s fade)
	var tween = aura.create_tween()
	tween.tween_property(aura, "modulate:a", 0.0, 0.5).set_delay(1.0)
	
	await tween.finished
	aura.queue_free()

static func execute_Shield_Battery_Effect(target: Dictionary, combat_scene: Node) -> bool:
	"""Restore 50 shields with AoE(2)Full effect (full effect on all ships within range 2)"""
	if not target.has("sprite") or not is_instance_valid(target.get("sprite")):
		print("CardEffects: Shield Battery Effect - Invalid target")
		return false
	
	var shield_amount = 50
	var ship_name = target.get("type", "Unknown")
	print("CardEffects: Shield Battery - Applying to ", ship_name)
	
	# Apply shield to primary target
	apply_shield_effect(target, shield_amount, combat_scene)
	
	# Apply AoE(2)Full - get all friendly ships within range 2 with FULL effect
	var affected_ships = apply_aoe_full_effect(target, shield_amount, 2, "friendly", "shield", combat_scene)
	
	print("CardEffects: Shield Battery - Affected ", affected_ships.size(), " additional ships")
	
	# Display aura effect
	await display_aura_effect(target, combat_scene)
	
	return true

static func execute_Incinerator_Cannon_Effect_Cinematic(source: Dictionary, target: Dictionary, combat_scene: Node) -> bool:
	"""Fire incinerator beam in slow-motion cinematic mode"""
	if not source.has("sprite") or not is_instance_valid(source.get("sprite")):
		print("CardEffects: Incinerator Cannon Cinematic - Invalid source sprite")
		return false

	# Get card data
	var card_data = DataManager.get_card_data("Incinerator Cannon")
	var beam_sprite_path = card_data.get("projectile_sprite_path", "res://assets/Effects/laser_huge/s_laser_huge_04.png")
	var beam_size_raw = card_data.get("projectile size", "30")
	var beam_size = int(beam_size_raw) if beam_size_raw != "" else 30

	# Load beam texture
	var beam_texture = load(beam_sprite_path)
	if beam_texture == null:
		print("CardEffects: Failed to load beam texture")
		return false

	# Create beam sprite
	var beam = Sprite2D.new()
	beam.texture = beam_texture
	beam.z_index = 1

	# Get positions
	var start_pos = source["sprite"].global_position
	var end_pos = target["sprite"].global_position

	# Calculate angle and scale
	var angle = start_pos.angle_to_point(end_pos)
	beam.rotation = angle

	var texture_height = beam_texture.get_height()
	var scale_y = beam_size / float(texture_height) if texture_height > 0 else 1.0
	beam.scale = Vector2(scale_y, scale_y)

	# Position beam
	beam.position = start_pos
	combat_scene.add_child(beam)

	# Move beam slightly in slow motion (10% of distance over 1.2 seconds)
	var direction = (end_pos - start_pos).normalized()
	var slow_distance = start_pos.distance_to(end_pos) * 0.1
	var slow_end_pos = start_pos + (direction * slow_distance)

	var tween = combat_scene.create_tween()
	tween.tween_property(beam, "position", slow_end_pos, 1.2)

	# Don't wait for tween - let it animate while we wait
	# The beam will be released at full speed after all abilities complete

	# Store projectile data for later release
	var projectile_data = {
		"sprite": beam,
		"start_pos": start_pos,
		"end_pos": end_pos,
		"target": target,
		"damage": 20,
		"burn_stacks": 3,
		"source": source
	}
	combat_scene.stored_projectiles.append(projectile_data)

	return true

static func execute_Missile_Lock_Effect_Cinematic(source: Dictionary, target: Dictionary, combat_scene: Node) -> bool:
	"""Fire missile in slow-motion cinematic mode"""
	# Similar to Incinerator Cannon but with missile properties
	var card_data = DataManager.get_card_data("Missile Lock")
	var missile_sprite_path = card_data.get("projectile_sprite_path", "res://assets/Effects/s_fxProjectile_2_drone/s_fxProjectile_2_drone.png")
	var missile_size_raw = card_data.get("projectile size", "70")
	var missile_size = int(missile_size_raw) if missile_size_raw != "" else 70

	var missile_texture = load(missile_sprite_path)
	if missile_texture == null:
		print("CardEffects: Failed to load missile texture")
		return false

	var missile = Sprite2D.new()
	missile.texture = missile_texture
	missile.z_index = 1

	var start_pos = source["sprite"].global_position
	var end_pos = target["sprite"].global_position

	var angle = start_pos.angle_to_point(end_pos)
	missile.rotation = angle

	var texture_height = missile_texture.get_height()
	var scale_y = missile_size / float(texture_height) if texture_height > 0 else 1.0
	missile.scale = Vector2(scale_y, scale_y)

	missile.position = start_pos
	combat_scene.add_child(missile)

	# Slow motion - move 10% of distance
	var direction = (end_pos - start_pos).normalized()
	var slow_distance = start_pos.distance_to(end_pos) * 0.1
	var slow_end_pos = start_pos + (direction * slow_distance)

	var tween = combat_scene.create_tween()
	tween.tween_property(missile, "position", slow_end_pos, 1.2)

	# Store for later release
	var projectile_data = {
		"sprite": missile,
		"start_pos": start_pos,
		"end_pos": end_pos,
		"target": target,
		"damage": 50,
		"is_missile": true,
		"source": source
	}
	combat_scene.stored_projectiles.append(projectile_data)

	return true

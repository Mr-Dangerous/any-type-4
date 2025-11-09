extends Node

# CombatWeapons - Consolidated weapon firing, damage calculation, and energy system
# Handles both manual and auto-combat weapon systems

signal weapon_fired(attacker, target)
signal unit_destroyed(unit)

# Reference to parent Combat_2 node (set by Combat_2._ready())
var combat_manager: Node2D = null

func _init(parent: Node2D = null):
	combat_manager = parent

func set_combat_manager(parent: Node2D):
	combat_manager = parent

# ============================================================================
# WEAPON FIRING FUNCTIONS (Consolidated manual + auto)
# ============================================================================

func fire_weapon(attacker: Dictionary, target: Dictionary, projectile_delay: float = 0.05):
	# Fire weapon projectiles from attacker to target
	# Works for both manual and auto-combat
	# projectile_delay: delay between multiple projectiles in one attack

	if attacker.is_empty() or target.is_empty():
		return

	# Validate instances still exist (important for auto-combat)
	if not is_instance_valid(attacker.get("container")) or not is_instance_valid(target.get("container")):
		return

	var num_attacks = attacker["stats"]["num_attacks"]

	# Fire multiple projectiles with slight spacing
	for i in range(num_attacks):
		if i > 0:
			# Add small delay between projectiles
			await combat_manager.get_tree().create_timer(projectile_delay).timeout
		fire_projectile(attacker, target)

	# Gain energy after attack (2-4 random)
	gain_energy(attacker)

	# Emit signal
	weapon_fired.emit(attacker, target)

func fire_projectile(attacker: Dictionary, target: Dictionary):
	# Fire a single projectile from attacker to target
	# Consolidated version of fire_single_laser() and auto_fire_single_laser()

	if attacker.is_empty() or target.is_empty():
		return

	# Validate instances (important for auto-combat)
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

	# Get projectile sprite and size from attacker data
	var projectile_sprite_path = attacker.get("projectile_sprite", "res://assets/Effects/laser_light/s_laser_light_001.png")
	var projectile_pixel_size = attacker.get("projectile_size", 6)
	var projectile_texture: Texture2D = load(projectile_sprite_path)

	# Create projectile sprite
	var projectile = Sprite2D.new()
	projectile.texture = projectile_texture
	projectile.position = start_pos
	projectile.rotation = angle
	projectile.z_index = 1  # Above ships
	combat_manager.add_child(projectile)

	# Scale projectile to match size from database
	var projectile_height = projectile_texture.get_height()
	var scale_y = float(projectile_pixel_size) / projectile_height
	projectile.scale = Vector2(scale_y, scale_y)  # Uniform scale to maintain aspect ratio

	# Center the sprite
	projectile.offset = Vector2(-projectile_texture.get_width() / 2, -projectile_texture.get_height() / 2)

	# Animate projectile: fly quickly to target (0.2 seconds)
	var flight_duration = 0.2
	var tween = combat_manager.create_tween()
	tween.tween_property(projectile, "position", end_pos, flight_duration)
	tween.tween_callback(func():
		on_projectile_hit(projectile, attacker, target)
	)

func on_projectile_hit(projectile: Sprite2D, attacker: Dictionary, target: Dictionary):
	# Handle projectile hitting the target
	# Consolidated version of on_laser_hit() and auto_on_laser_hit()

	# Remove the projectile
	projectile.queue_free()

	# Validate units still exist
	if attacker.is_empty() or target.is_empty():
		return
	if not is_instance_valid(target.get("container")):
		return

	# Calculate and apply damage
	var damage_dealt = calculate_damage(attacker, target)
	if damage_dealt > 0:
		apply_damage(target, damage_dealt)

	# Flash the target
	if target.has("sprite"):
		var target_sprite = target["sprite"]

		# Create flash animation - white flash then back to normal
		var flash_tween = combat_manager.create_tween()
		flash_tween.tween_property(target_sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.05)  # Flash white
		flash_tween.tween_property(target_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)   # Return to normal

# ============================================================================
# ROTATION FUNCTIONS (Consolidated manual + auto)
# ============================================================================

func rotate_to_target(attacker: Dictionary, target: Dictionary):
	# Rotate attacker to face the target
	# Consolidated version of rotate_ship_to_target() and auto_rotate_to_target()

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
	var tween = combat_manager.create_tween()
	tween.tween_property(attacker_sprite, "rotation", target_rotation, 0.3)

# ============================================================================
# DAMAGE CALCULATION AND APPLICATION
# ============================================================================

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
	hit_chance -= (target_evasion * 0.01)
	if hit_chance < 0:
		hit_chance = 0

	var crit_chance = 1.0 - ((attacker_accuracy) * 0.01)
	var crit_roll = randf()
	var critical_hit = false
	if crit_roll > crit_chance:
		critical_hit = true
	if (critical_hit):
		# it has a chance to negate a crit via a critical hit of its own. so if a ship has 15 reinforced,
		# then it has a 15% chance to negate any critical hit against it and reduce it to a normal hit
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
		final_damage *= 2
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

	# Update health bar (call back to combat_manager)
	if combat_manager.has_method("update_health_bar"):
		combat_manager.update_health_bar(target)

	# Check if ship is destroyed
	var total_health = target.get("current_armor", 0) + target.get("current_shield", 0)
	if total_health <= 0:
		print("  UNIT DESTROYED!")
		destroy_unit(target)

func destroy_unit(unit: Dictionary):
	# Destroy a ship or turret when its health reaches 0
	# This is called by apply_damage(), but final cleanup is delegated to combat_manager

	if unit.is_empty():
		return

	# Emit signal so combat_manager can handle cleanup
	unit_destroyed.emit(unit)

# ============================================================================
# ENERGY AND ABILITY SYSTEM
# ============================================================================

func gain_energy(unit: Dictionary):
	# Gain 2-4 random energy after each attack
	if unit.is_empty():
		return

	# Don't gain energy when combat is paused
	if combat_manager and combat_manager.get("combat_paused"):
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

	# Update energy bar (call back to combat_manager)
	if combat_manager.has_method("update_energy_bar"):
		combat_manager.update_energy_bar(unit)

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
	if combat_manager.has_method("update_energy_bar"):
		combat_manager.update_energy_bar(unit)

	# TODO: Actually call the ability function when implemented
	# For now just print to console

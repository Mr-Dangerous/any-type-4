extends Node
class_name CombatProjectileManager

## CombatProjectileManager
## Handles projectile creation, animation, collision, and damage application

# References
var combat_scene: Node2D = null
var ship_manager: CombatShipManager = null

# Preloaded resources
const DamageNumber = preload("res://scripts/DamageNumber.gd")

# Signals
signal damage_dealt(attacker: Dictionary, target: Dictionary, damage_info: Dictionary)
signal projectile_fired(attacker: Dictionary, target: Dictionary)

func initialize(parent_scene: Node2D, manager: CombatShipManager):
	"""Initialize projectile manager"""
	combat_scene = parent_scene
	ship_manager = manager

# ============================================================================
# PROJECTILE FIRING
# ============================================================================

func fire_projectiles(attacker: Dictionary, target: Dictionary):
	"""Fire projectiles from attacker to target"""
	if not attacker.has("sprite") or not target.has("sprite"):
		print("CombatProjectileManager: Invalid attacker or target for firing")
		return
	
	# Rotate attacker to face target
	await rotate_ship_to_target(attacker, target)
	
	# Fire multiple projectiles based on num_attacks
	var num_attacks = attacker.get("num_attacks", 1)
	
	for i in range(num_attacks):
		fire_single_projectile(attacker, target)
		if i < num_attacks - 1:
			await combat_scene.get_tree().create_timer(0.1).timeout
	
	projectile_fired.emit(attacker, target)

func fire_single_projectile(attacker: Dictionary, target: Dictionary):
	"""Create and animate a single projectile"""
	if not attacker.has("sprite") or not target.has("sprite"):
		return
	
	# Get projectile sprite and size from attacker data
	var projectile_sprite_path = attacker.get("projectile_sprite", "res://assets/Effects/laser_light/s_laser_light_001.png")
	var projectile_size = attacker.get("projectile_size", 6)
	
	# Load projectile texture
	var projectile_texture = load(projectile_sprite_path)
	if projectile_texture == null:
		print("CombatProjectileManager: Failed to load projectile texture: ", projectile_sprite_path)
		return
	
	# Create projectile sprite
	var laser = Sprite2D.new()
	laser.texture = projectile_texture
	laser.z_index = 1
	
	# Get start and end positions
	var start_pos = attacker["sprite"].global_position
	var end_pos = target["sprite"].global_position
	
	# Calculate angle and scale
	var angle = start_pos.angle_to_point(end_pos)
	laser.rotation = angle
	
	# Scale projectile based on projectile_size
	var texture_height = projectile_texture.get_height()
	var scale_y = projectile_size / float(texture_height) if texture_height > 0 else 1.0
	laser.scale = Vector2(scale_y, scale_y)
	
	# Position projectile
	laser.position = start_pos
	var texture_width = projectile_texture.get_width() * scale_y
	var width = texture_width
	var height = projectile_size
	laser.offset = Vector2(-width / 2, -height / 2)
	
	combat_scene.add_child(laser)
	
	# Animate projectile to target
	var tween = combat_scene.create_tween()
	tween.tween_property(laser, "position", end_pos, 0.3)
	
	# Wait for animation to complete, then handle impact
	await tween.finished
	
	# Handle projectile hit
	on_projectile_hit(laser, attacker, target)

func on_projectile_hit(projectile: Sprite2D, attacker: Dictionary, target: Dictionary):
	"""Handle projectile reaching target"""
	# Remove projectile
	projectile.queue_free()
	
	# Validate target still exists
	if not target.has("sprite") or not is_instance_valid(target.get("sprite")):
		print("CombatProjectileManager: Target no longer valid")
		return
	
	# Calculate damage
	var damage_result = calculate_damage(attacker, target)
	
	# Apply damage to target
	var damage_info = apply_damage(target, damage_result)
	
	# Display damage number
	show_damage_number(target, damage_result, damage_info)
	
	# Flash target sprite
	flash_target_sprite(target)
	
	# Emit damage signal
	damage_dealt.emit(attacker, target, damage_info)
	
	# Grant energy to attacker
	if attacker.has("current_energy"):
		var energy_gain = 1  # Energy per shot
		attacker["current_energy"] = min(attacker["current_energy"] + energy_gain, attacker.get("energy", 0))

# ============================================================================
# DAMAGE CALCULATION
# ============================================================================

func calculate_damage(attacker: Dictionary, target: Dictionary) -> Dictionary:
	"""Calculate damage with accuracy/evasion and critical hit mechanics"""
	var base_damage = attacker.get("damage", 0)
	var accuracy = attacker.get("accuracy", 100)
	var evasion = target.get("evasion", 0)
	
	# Calculate hit chance
	var hit_chance = accuracy - evasion
	hit_chance = clamp(hit_chance, 5, 95)  # Min 5%, max 95%
	
	# Roll for hit/miss
	var roll = randi() % 100
	var is_miss = roll >= hit_chance
	
	if is_miss:
		return {
			"damage": 0,
			"is_crit": false,
			"is_miss": true
		}
	
	# Roll for critical hit (10% chance)
	var is_crit = (randi() % 100) < 10
	var final_damage = base_damage
	
	if is_crit:
		final_damage = int(base_damage * 1.5)
	
	return {
		"damage": final_damage,
		"is_crit": is_crit,
		"is_miss": false
	}

func apply_damage(target: Dictionary, damage_result: Dictionary) -> Dictionary:
	"""Apply damage to target's shield/armor"""
	var damage = damage_result.get("damage", 0)
	var is_miss = damage_result.get("is_miss", false)
	
	if is_miss:
		return {
			"shield_damage": 0,
			"armor_damage": 0,
			"destroyed": false
		}
	
	var shield_damage = 0
	var armor_damage = 0
	var remaining_damage = damage
	
	# Apply to shield first
	if target.get("current_shield", 0) > 0:
		shield_damage = min(remaining_damage, target["current_shield"])
		target["current_shield"] -= shield_damage
		remaining_damage -= shield_damage
	
	# Apply remaining damage to armor
	if remaining_damage > 0:
		armor_damage = min(remaining_damage, target.get("current_armor", 0))
		target["current_armor"] = max(0, target.get("current_armor", 0) - armor_damage)
	
	# Update health bar if exists
	if target.has("health_bar"):
		update_health_bar(target)
	
	# Check if destroyed
	var destroyed = target.get("current_armor", 0) <= 0
	
	return {
		"shield_damage": shield_damage,
		"armor_damage": armor_damage,
		"destroyed": destroyed
	}

# ============================================================================
# VISUAL EFFECTS
# ============================================================================

func rotate_ship_to_target(attacker: Dictionary, target: Dictionary):
	"""Orient attacker toward target before firing"""
	if not attacker.has("sprite") or not target.has("sprite"):
		return
	
	var attacker_pos = attacker["sprite"].global_position
	var target_pos = target["sprite"].global_position
	
	var angle = attacker_pos.angle_to_point(target_pos)
	
	# Animate rotation
	var tween = combat_scene.create_tween()
	tween.tween_property(attacker["sprite"], "rotation", angle, 0.2)
	await tween.finished

func flash_target_sprite(target: Dictionary):
	"""Flash target sprite white on hit"""
	if not target.has("sprite") or not is_instance_valid(target.get("sprite")):
		return
	
	var sprite = target["sprite"]
	var original_modulate = sprite.modulate
	
	# Flash white
	sprite.modulate = Color(2, 2, 2, 1)
	
	# Return to original after delay
	await combat_scene.get_tree().create_timer(0.1).timeout
	
	if is_instance_valid(sprite):
		sprite.modulate = original_modulate

func show_damage_number(target: Dictionary, damage_result: Dictionary, damage_info: Dictionary):
	"""Display damage number at impact point"""
	if not target.has("sprite"):
		return
	
	var damage_number = DamageNumber.new()
	var pos = target["sprite"].global_position
	
	if damage_result.get("is_miss", false):
		damage_number.display_miss(pos)
	elif damage_result.get("is_crit", false):
		damage_number.display_crit(pos, damage_result.get("damage", 0))
	else:
		var total_damage = damage_info.get("shield_damage", 0) + damage_info.get("armor_damage", 0)
		damage_number.display_damage(pos, total_damage)
	
	combat_scene.add_child(damage_number)

func update_health_bar(target: Dictionary):
	"""Update target's health bar visual (placeholder)"""
	# Implementation depends on health bar structure
	# To be implemented when integrating with Combat_2.gd
	pass

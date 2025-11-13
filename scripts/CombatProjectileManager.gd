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

func launch_projectile(attacker: Dictionary, target: Dictionary, spawn_offset: Vector2 = Vector2.ZERO):
	"""Launch a single projectile with offset - non-blocking for simultaneous firing"""
	if not attacker.has("sprite") or not target.has("sprite"):
		print("CombatProjectileManager: Invalid attacker or target for launch_projectile")
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

	# Get start and end positions (with spawn offset applied)
	var start_pos = attacker["sprite"].global_position + spawn_offset
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

	# Animate projectile to target (30% slower = 0.2 * 1.3 = 0.26 seconds)
	var tween = combat_scene.create_tween()
	tween.tween_property(laser, "position", end_pos, 0.26)

	# When animation completes, handle impact
	tween.finished.connect(_on_launch_projectile_hit.bind(laser, attacker, target))

func _on_launch_projectile_hit(laser: Sprite2D, attacker: Dictionary, target: Dictionary):
	"""Handle projectile hit for launch_projectile (callback version)"""
	# Get impact position before removing projectile
	var impact_pos = laser.position

	# Remove projectile
	laser.queue_free()

	# Validate target still exists
	if not target.has("sprite") or not is_instance_valid(target.get("sprite")):
		print("CombatProjectileManager: Target no longer valid")
		return

	# Show explosion animation at impact point
	show_explosion_effect(impact_pos)

	# Calculate damage
	var damage_result = calculate_damage(attacker, target)

	# Apply damage to target
	var damage_info = apply_damage(target, damage_result)

	# Get target position for damage numbers
	var target_pos = target["sprite"].global_position

	# Display damage numbers using DamageNumber static methods
	if damage_result.get("is_miss", false):
		DamageNumber.show_miss(combat_scene, target_pos)
	else:
		# Show shield damage if any
		if damage_info.get("shield_damage", 0) > 0:
			DamageNumber.show_shield_damage(combat_scene, target_pos, damage_info["shield_damage"], damage_result.get("is_crit", false))

		# Show armor damage if any (offset if both exist)
		if damage_info.get("armor_damage", 0) > 0:
			var armor_pos = target_pos
			if damage_info.get("shield_damage", 0) > 0:
				armor_pos.y += 20  # Offset downward
			DamageNumber.show_armor_damage(combat_scene, armor_pos, damage_info["armor_damage"], damage_result.get("is_crit", false))

	# Flash target sprite
	flash_target_sprite(target)

	# Emit damage signal
	damage_dealt.emit(attacker, target, damage_info)

	# Apply burn status effect if attacker has fire damage
	apply_burn_on_hit(attacker, target, damage_result)

	# Apply freeze status effect if attacker has ice damage
	apply_freeze_on_hit(attacker, target, damage_result)

# ============================================================================
# DEPRECATED FUNCTIONS (kept for reference, use launch_projectile instead)
# ============================================================================

func fire_projectiles(attacker: Dictionary, target: Dictionary):
	"""DEPRECATED: Use launch_projectile instead - Fire projectiles from attacker to target"""
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
	"""DEPRECATED: Use launch_projectile instead - Create and animate a single projectile"""
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
	"""DEPRECATED: Use launch_projectile instead - Handle projectile reaching target"""
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

	# Apply burn status effect if attacker has fire damage
	print("CombatProjectileManager: About to check for burn application...")
	apply_burn_on_hit(attacker, target, damage_result)

	# Apply freeze status effect if attacker has ice damage
	apply_freeze_on_hit(attacker, target, damage_result)

	# Grant energy to attacker
	if attacker.has("current_energy"):
		var energy_gain = 1  # Energy per shot
		attacker["current_energy"] = min(attacker["current_energy"] + energy_gain, attacker.get("energy", 0))

# ============================================================================
# DAMAGE CALCULATION
# ============================================================================

func calculate_damage(attacker: Dictionary, target: Dictionary) -> Dictionary:
	"""Calculate damage with accuracy/evasion and critical hit mechanics"""
	var base_damage = attacker.get("stats", {}).get("damage", 0)
	var accuracy = attacker.get("stats", {}).get("accuracy", 100)
	var evasion = target.get("stats", {}).get("evasion", 0)

	# Apply freeze modifier to evasion if active
	if combat_scene and "status_effect_manager" in combat_scene:
		var status_manager = combat_scene.status_effect_manager
		if status_manager:
			evasion *= status_manager.get_freeze_evasion_multiplier(target)

	# Calculate miss chance based on evasion only
	var miss_chance = clamp(evasion, 0, 95)  # Max 95% evasion
	
	# Roll for hit/miss
	var roll = randi() % 100
	var is_miss = roll < miss_chance
	
	if is_miss:
		return {
			"damage": 0,
			"is_crit": false,
			"is_miss": true
		}
	
	# Roll for critical hit based on accuracy
	var crit_chance = clamp(accuracy, 0, 100)
	var is_crit = (randi() % 100) < crit_chance
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

func show_explosion_effect(position: Vector2, size: String = "Low"):
	"""Display explosion animation at the specified position"""
	# Validate combat scene
	if not combat_scene or not is_instance_valid(combat_scene):
		print("CombatProjectileManager: Invalid combat scene for explosion")
		return

	# Load explosion sprite sheet frames
	var explosion_frames: Array[Texture2D] = []
	var base_path = "res://assets/Effects/bombs-and-explosions-pixel-art-set/3 Effects/2 " + size + "/"

	# Load the 3 sprite sheets (each has 8 frames)
	for sheet_num in range(1, 4):
		var texture_path = base_path + str(sheet_num) + ".png"
		var texture = load(texture_path)
		if texture:
			explosion_frames.append(texture)

	if explosion_frames.is_empty():
		print("CombatProjectileManager: Failed to load explosion textures")
		return

	# Create sprite for explosion
	var explosion_sprite = Sprite2D.new()
	explosion_sprite.position = position
	explosion_sprite.z_index = 2  # Above projectiles

	# Use the first frame to start
	explosion_sprite.texture = explosion_frames[0]

	# Calculate sprite sheet parameters (8 frames per sheet, arranged horizontally)
	var frames_per_sheet = 8
	var frame_width = explosion_frames[0].get_width() / frames_per_sheet
	var frame_height = explosion_frames[0].get_height()

	# Set up region to show first frame
	explosion_sprite.region_enabled = true
	explosion_sprite.region_rect = Rect2(0, 0, frame_width, frame_height)
	explosion_sprite.centered = true

	combat_scene.add_child(explosion_sprite)

	# Animate through all frames
	var frame_duration = 0.05  # 50ms per frame
	var current_sheet = 0
	var current_frame = 0
	var total_frames = explosion_frames.size() * frames_per_sheet

	for i in range(total_frames):
		# Check if sprite is still valid
		if not is_instance_valid(explosion_sprite):
			return

		current_sheet = i / frames_per_sheet
		current_frame = i % frames_per_sheet

		if current_sheet < explosion_frames.size():
			explosion_sprite.texture = explosion_frames[current_sheet]
			explosion_sprite.region_rect = Rect2(current_frame * frame_width, 0, frame_width, frame_height)

		await combat_scene.get_tree().create_timer(frame_duration).timeout

	# Remove explosion sprite after animation completes
	if is_instance_valid(explosion_sprite):
		explosion_sprite.queue_free()

# ============================================================================
# STATUS EFFECT APPLICATION
# ============================================================================

func apply_burn_on_hit(attacker: Dictionary, target: Dictionary, damage_result: Dictionary):
	"""Apply burn status effect if attacker has fire damage and burn chance"""
	print("CombatProjectileManager: apply_burn_on_hit called")
	print("  Attacker:", attacker.get("type", "unknown"))
	print("  Target:", target.get("type", "unknown"))
	print("  Miss:", damage_result.get("is_miss", false))

	# Check if attack missed
	if damage_result.get("is_miss", false):
		print("  Attack missed, skipping burn")
		return

	# Check if attacker has burn chance
	var burn_chance = attacker.get("burn_on_hit_chance", 0.0)
	print("  Burn chance:", burn_chance)
	if burn_chance <= 0:
		print("  No burn chance, skipping")
		return

	# Roll for burn application
	var roll = randf()
	print("  Rolled:", roll, " vs chance:", burn_chance)
	if roll >= burn_chance:
		print("  Roll failed, no burn")
		return

	# Get status effect manager from combat scene
	print("  Getting status manager...")
	if not combat_scene or not "status_effect_manager" in combat_scene:
		print("  ERROR: No status effect manager available")
		return

	var status_manager = combat_scene.status_effect_manager
	if not status_manager or not status_manager.has_method("apply_burn"):
		print("  ERROR: Status manager doesn't have apply_burn method")
		return

	# Apply 1 stack of burn
	print("  Applying burn to target...")
	status_manager.apply_burn(target, 1)
	print("  SUCCESS: Applied 1 burn stack to ", target.get("type", "target"))


func apply_freeze_on_hit(attacker: Dictionary, target: Dictionary, damage_result: Dictionary):
	"""Apply freeze status effect if attacker has ice damage and freeze chance"""
	print("CombatProjectileManager: apply_freeze_on_hit called")
	print("  Attacker:", attacker.get("type", "unknown"))
	print("  Target:", target.get("type", "unknown"))
	print("  Miss:", damage_result.get("is_miss", false))

	# Check if attack missed
	if damage_result.get("is_miss", false):
		print("  Attack missed, skipping freeze")
		return

	# Check if attacker has freeze chance
	var freeze_chance = attacker.get("freeze_on_hit_chance", 0.0)
	print("  Freeze chance:", freeze_chance)
	if freeze_chance <= 0:
		print("  No freeze chance, skipping")
		return

	# Roll for freeze application
	var roll = randf()
	print("  Rolled:", roll, " vs chance:", freeze_chance)
	if roll >= freeze_chance:
		print("  Roll failed, no freeze")
		return

	# Get status effect manager from combat scene
	print("  Getting status manager...")
	if not combat_scene or not "status_effect_manager" in combat_scene:
		print("  ERROR: No status effect manager available")
		return

	var status_manager = combat_scene.status_effect_manager
	if not status_manager or not status_manager.has_method("apply_freeze"):
		print("  ERROR: Status manager doesn't have apply_freeze method")
		return

	# Apply 1 stack of freeze
	print("  Applying freeze to target...")
	status_manager.apply_freeze(target, 1)
	print("  SUCCESS: Applied 1 freeze stack to ", target.get("type", "target"))

extends Node
class_name DamageCalculator

## DamageCalculator
## Centralized damage calculation utility for all combat systems
##
## Consolidates damage logic from CombatWeapons, CombatProjectileManager, and Combat_2
## Fixes critical bug where crit chance was inverted (high accuracy = low crit)
##
## Usage:
##   var result = DamageCalculator.calculate_damage(attacker, target, combat_scene)
##   # Returns: {damage: int, is_crit: bool, is_miss: bool}

## Calculate damage with accuracy/evasion, critical hits, and armor reduction
##
## Args:
##   attacker: Dictionary with ["stats"] containing damage, accuracy
##   target: Dictionary with ["stats"] containing evasion, reinforced_armor
##   combat_scene: Optional combat scene reference for status effect support
##
## Returns:
##   Dictionary: {
##     damage: int - Final damage amount (0 if miss, >= 1 if hit)
##     is_crit: bool - Whether this was a critical hit
##     is_miss: bool - Whether the attack missed
##   }
static func calculate_damage(attacker: Dictionary, target: Dictionary, combat_scene = null) -> Dictionary:
	var result = {
		"damage": 0,
		"is_crit": false,
		"is_miss": false
	}

	# Validate inputs
	if attacker.is_empty() or target.is_empty():
		return result

	if not attacker.has("stats") or not target.has("stats"):
		print("ERROR: DamageCalculator - attacker or target missing stats dictionary")
		return result

	# Get base stats
	var base_damage = attacker["stats"].get("damage", 0)
	var accuracy = attacker["stats"].get("accuracy", 0)
	var evasion = target["stats"].get("evasion", 0)
	var reinforced = target["stats"].get("reinforced_armor", 0)

	# Apply status effect modifiers (if combat scene and status manager available)
	if combat_scene != null:
		if "status_effect_manager" in combat_scene:
			var status_manager = combat_scene.status_effect_manager
			if status_manager != null and status_manager.has_method("get_freeze_evasion_multiplier"):
				evasion *= status_manager.get_freeze_evasion_multiplier(target)

	# Calculate miss chance: evasion as direct percentage (capped at 95%)
	# Example: 30 evasion = 30% chance to miss
	var miss_chance = clamp(evasion, 0, 95)
	var miss_roll = randi() % 100

	if miss_roll < miss_chance:
		result["is_miss"] = true
		return result

	# Calculate critical hit: accuracy as direct percentage (capped at 100%)
	# Example: 25 accuracy = 25% chance to crit
	# FIXED BUG: Previous implementations had inverted formula!
	var crit_chance = clamp(accuracy, 0, 100)
	var crit_roll = randi() % 100
	var is_crit = (crit_roll < crit_chance)

	# Apply reinforced armor damage reduction
	# Example: 20 reinforced = 20% damage reduction
	var damage_multiplier = 1.0 - (float(reinforced) / 100.0)
	damage_multiplier = max(0.0, damage_multiplier)  # Can't be negative

	var final_damage = int(base_damage * damage_multiplier)

	# Apply critical hit multiplier (2x damage)
	if is_crit:
		final_damage = int(final_damage * 2.0)
		result["is_crit"] = true

	# Ensure minimum damage on successful hit (at least 1 damage)
	final_damage = max(1, final_damage)

	result["damage"] = final_damage

	return result

## Get hit chance percentage for UI display
## Returns value between 0.0 and 1.0
static func get_hit_chance(attacker: Dictionary, target: Dictionary, combat_scene = null) -> float:
	if attacker.is_empty() or target.is_empty():
		return 0.0

	if not attacker.has("stats") or not target.has("stats"):
		return 0.0

	var evasion = target["stats"].get("evasion", 0)

	# Apply status effect modifiers
	if combat_scene != null:
		if "status_effect_manager" in combat_scene:
			var status_manager = combat_scene.status_effect_manager
			if status_manager != null and status_manager.has_method("get_freeze_evasion_multiplier"):
				evasion *= status_manager.get_freeze_evasion_multiplier(target)

	var miss_chance = clamp(evasion, 0, 95)
	return 1.0 - (miss_chance / 100.0)

## Get crit chance percentage for UI display
## Returns value between 0.0 and 1.0
static func get_crit_chance(attacker: Dictionary) -> float:
	if attacker.is_empty():
		return 0.0

	if not attacker.has("stats"):
		return 0.0

	var accuracy = attacker["stats"].get("accuracy", 0)
	var crit_chance = clamp(accuracy, 0, 100)
	return crit_chance / 100.0

## Get expected damage (average damage accounting for hit/miss/crit)
## Useful for AI decision making or UI tooltips
static func get_expected_damage(attacker: Dictionary, target: Dictionary, combat_scene = null) -> float:
	if attacker.is_empty() or target.is_empty():
		return 0.0

	var hit_chance = get_hit_chance(attacker, target, combat_scene)
	var crit_chance = get_crit_chance(attacker)

	var base_damage = attacker["stats"].get("damage", 0)
	var reinforced = target["stats"].get("reinforced_armor", 0)
	var damage_multiplier = 1.0 - (float(reinforced) / 100.0)
	damage_multiplier = max(0.0, damage_multiplier)

	var normal_damage = base_damage * damage_multiplier
	var crit_damage = normal_damage * 2.0

	# Expected damage = hit_chance * (normal_damage * (1 - crit_chance) + crit_damage * crit_chance)
	var expected = hit_chance * (normal_damage * (1.0 - crit_chance) + crit_damage * crit_chance)

	return expected

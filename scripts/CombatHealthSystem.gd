extends Node

# ============================================================================
# COMBAT HEALTH SYSTEM
# ============================================================================
# Handles all health, shield, armor, and health bar management for combat units.
# This is a standalone system that manages:
#   - Damage application (shield → armor flow)
#   - Health bar creation (visual UI above units)
#   - Health bar updates (visual feedback)
#   - Healing and shield restoration
#
# Usage:
#   var health_system = CombatHealthSystem.new()
#   health_system.create_health_bar(ship_container, ship_size, max_shield, max_armor)
#   health_system.apply_damage(target, damage_amount)
# ============================================================================

signal unit_destroyed(unit: Dictionary)

# Reference to parent combat manager for callbacks (optional)
var combat_manager = null

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init(manager = null):
	combat_manager = manager

# ============================================================================
# HEALTH BAR CREATION
# ============================================================================

func create_health_bar(ship_container: Control, ship_size: int, max_shield: int, max_armor: int):
	"""
	Create health bar UI above a unit.

	Args:
		ship_container: The Control node that represents the ship visually
		ship_size: Size of the ship in pixels (bar width is capped at min(32, ship_size))
		max_shield: Maximum shield value (for initial display)
		max_armor: Maximum armor value (for initial display)

	Creates a layered health bar with:
		- Background (dark gray)
		- Shield bar (cyan, top)
		- Overshield bar (gold, above shield)
		- Armor bar (red/orange, middle)
		- Energy bar (purple, bottom)
	"""
	var bar_width = min(32, ship_size)  # Cap at 32 pixels
	var health_bar_container = Control.new()
	health_bar_container.name = "HealthBar"
	health_bar_container.position = Vector2((ship_size - bar_width) / 2, -18)  # Center above ship, raised for 3-bar layout
	health_bar_container.size = Vector2(bar_width, 12)
	ship_container.add_child(health_bar_container)

	# Background (dark gray)
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.2, 0.2, 0.2, 0.8)
	bg.size = Vector2(bar_width, 12)
	health_bar_container.add_child(bg)

	# Shield bar (cyan/blue) - top
	var shield_bar = ColorRect.new()
	shield_bar.name = "ShieldBar"
	shield_bar.color = Color(0.2, 0.7, 1.0, 1.0)
	shield_bar.size = Vector2(bar_width, 4)
	shield_bar.position = Vector2(0, 0)
	health_bar_container.add_child(shield_bar)

	# Overshield bar (golden) - above shield bar
	var overshield_bar = ColorRect.new()
	overshield_bar.name = "OvershieldBar"
	overshield_bar.color = Color(1.0, 0.84, 0.0, 1.0)  # Gold
	overshield_bar.size = Vector2(0, 2)  # Thinner bar, starts at 0 width
	overshield_bar.position = Vector2(0, -2)  # Above shield bar
	health_bar_container.add_child(overshield_bar)

	# Armor bar (red/orange) - middle
	var armor_bar = ColorRect.new()
	armor_bar.name = "ArmorBar"
	armor_bar.color = Color(0.8, 0.3, 0.2, 1.0)
	armor_bar.size = Vector2(bar_width, 4)
	armor_bar.position = Vector2(0, 4)
	health_bar_container.add_child(armor_bar)

	# Energy bar (purple) - bottom
	var energy_bar = ColorRect.new()
	energy_bar.name = "EnergyBar"
	energy_bar.color = Color(0.7, 0.2, 1.0, 1.0)  # Purple
	energy_bar.size = Vector2(bar_width, 4)
	energy_bar.position = Vector2(0, 8)
	health_bar_container.add_child(energy_bar)

# ============================================================================
# HEALTH BAR UPDATES
# ============================================================================

func update_health_bar(unit: Dictionary):
	"""
	Update health bar to reflect current health/shield/armor values.

	Args:
		unit: Dictionary containing:
			- container: Node with HealthBar child
			- size: Unit size in pixels
			- stats: {armor: int, shield: int}
			- current_armor: Current armor value
			- current_shield: Current shield value
			- current_overshield: (optional) Current overshield value

	This is the MAIN function you call when unit health changes.
	It updates all visual bars (shield, armor, overshield, energy).
	"""
	if not unit.has("container"):
		print("DEBUG: update_health_bar - no container found")
		return

	var container = unit["container"]
	var health_bar_container = container.get_node_or_null("HealthBar")
	if not health_bar_container:
		print("DEBUG: update_health_bar - no HealthBar container found")
		return

	var unit_size = unit["size"]
	var bar_width = min(32, unit_size)  # Cap at 32 pixels
	var max_armor = unit["stats"]["armor"]
	var max_shield = unit["stats"]["shield"]
	var current_armor = unit.get("current_armor", max_armor)
	var current_shield = unit.get("current_shield", max_shield)

	print("DEBUG: update_health_bar - bar_width=", bar_width, " max_armor=", max_armor, " current_armor=", current_armor, " max_shield=", max_shield, " current_shield=", current_shield)

	# Update armor bar width
	var armor_bar = health_bar_container.get_node_or_null("ArmorBar")
	if armor_bar and max_armor > 0:
		var armor_percent = float(current_armor) / float(max_armor)
		var new_width = bar_width * armor_percent
		print("DEBUG: ArmorBar - percent=", armor_percent, " new_width=", new_width, " old size=", armor_bar.size)
		# IMPORTANT: Use Vector2 assignment, not .x modification (Godot 4.x requirement)
		armor_bar.size = Vector2(new_width, armor_bar.size.y)
		print("DEBUG: ArmorBar - after setting, size=", armor_bar.size)

	# Update shield bar width
	var shield_bar = health_bar_container.get_node_or_null("ShieldBar")
	if shield_bar and max_shield > 0:
		var shield_percent = float(current_shield) / float(max_shield)
		var new_width = bar_width * shield_percent
		print("DEBUG: ShieldBar - percent=", shield_percent, " new_width=", new_width, " old size=", shield_bar.size)
		# IMPORTANT: Use Vector2 assignment, not .x modification (Godot 4.x requirement)
		shield_bar.size = Vector2(new_width, shield_bar.size.y)
		print("DEBUG: ShieldBar - after setting, size=", shield_bar.size)

	# Update overshield bar width (scales based on max_shield)
	var overshield_bar = health_bar_container.get_node_or_null("OvershieldBar")
	if overshield_bar:
		var current_overshield = unit.get("current_overshield", 0)
		if current_overshield > 0 and max_shield > 0:
			var overshield_percent = float(current_overshield) / float(max_shield)
			var overshield_width = min(bar_width * overshield_percent, bar_width)
			overshield_bar.size = Vector2(overshield_width, overshield_bar.size.y)
			overshield_bar.visible = true
		else:
			overshield_bar.size = Vector2(0, overshield_bar.size.y)
			overshield_bar.visible = false

	# Also update energy bar
	update_energy_bar(unit)

func update_energy_bar(unit: Dictionary):
	"""
	Update energy bar to reflect current energy.

	Args:
		unit: Dictionary containing:
			- container: Node with HealthBar child
			- size: Unit size in pixels
			- stats: {energy: int}
			- current_energy: Current energy value
	"""
	if not unit.has("container"):
		return

	var container = unit["container"]
	var health_bar_container = container.get_node_or_null("HealthBar")
	if not health_bar_container:
		return

	var unit_size = unit["size"]
	var bar_width = min(32, unit_size)  # Cap at 32 pixels
	var max_energy = unit["stats"].get("energy", 0)
	var current_energy = unit.get("current_energy", 0)

	# Update energy bar width
	var energy_bar = health_bar_container.get_node_or_null("EnergyBar")
	if energy_bar:
		if max_energy > 0:
			var energy_percent = float(current_energy) / float(max_energy)
			energy_bar.size = Vector2(bar_width * energy_percent, energy_bar.size.y)
		else:
			# No energy system, hide the bar
			energy_bar.size = Vector2(0, energy_bar.size.y)

# ============================================================================
# DAMAGE APPLICATION
# ============================================================================

func apply_damage(target: Dictionary, damage: int) -> Dictionary:
	"""
	Apply damage to a target unit.

	Damage flow: Overshield → Shield → Armor

	Args:
		target: Dictionary containing current_overshield, current_shield, current_armor
		damage: Amount of damage to apply

	Returns:
		Dictionary with damage breakdown:
			{
				"overshield_damage": int,
				"shield_damage": int,
				"armor_damage": int
			}

	This function:
		1. Applies damage in order (overshield → shield → armor)
		2. Updates health bar visually
		3. Generates energy from damage taken (if unit has energy system)
		4. Checks if unit is destroyed and emits signal
	"""
	var damage_breakdown = {
		"overshield_damage": 0,
		"shield_damage": 0,
		"armor_damage": 0
	}

	if target.is_empty():
		return damage_breakdown

	var remaining_damage = damage

	# 1. Damage overshield first (temporary shields)
	if target.has("current_overshield") and target["current_overshield"] > 0:
		var overshield_damage = min(target["current_overshield"], remaining_damage)
		target["current_overshield"] -= overshield_damage
		remaining_damage -= overshield_damage
		damage_breakdown["overshield_damage"] = overshield_damage
		print("  Overshield damaged: -", overshield_damage, " (", target["current_overshield"], " remaining)")

	# 2. Then damage shields
	if remaining_damage > 0 and target.has("current_shield") and target["current_shield"] > 0:
		var shield_damage = min(target["current_shield"], remaining_damage)
		target["current_shield"] -= shield_damage
		remaining_damage -= shield_damage
		damage_breakdown["shield_damage"] = shield_damage
		print("  Shield damaged: -", shield_damage, " (", target["current_shield"], " remaining)")

	# 3. Overflow damage goes to armor
	if remaining_damage > 0 and target.has("current_armor"):
		var armor_damage = min(target["current_armor"], remaining_damage)
		target["current_armor"] -= armor_damage
		damage_breakdown["armor_damage"] = armor_damage
		print("  Armor damaged: -", armor_damage, " (", target["current_armor"], " remaining)")

	# 4. Update health bar visually
	update_health_bar(target)

	# 5. Generate energy from damage taken (1 energy per 5% of combined health lost)
	if not target.get("ability_active", false):
		var max_energy = target.get("stats", {}).get("energy", 0)
		if max_energy > 0:
			var max_shield = target.get("stats", {}).get("shield", 0)
			var max_armor = target.get("stats", {}).get("armor", 0)
			var max_combined_health = max_shield + max_armor

			if max_combined_health > 0:
				var total_damage_dealt = damage_breakdown["shield_damage"] + damage_breakdown["armor_damage"]
				var percent_lost = float(total_damage_dealt) / float(max_combined_health)
				var energy_gain = floor(percent_lost * 20.0)  # 1 energy per 5% = 20 energy for 100%

				if energy_gain > 0:
					var current_energy = target.get("current_energy", 0)
					target["current_energy"] = min(current_energy + energy_gain, max_energy)
					print("  ", target.get("type", "unknown"), " gained ", energy_gain, " energy from damage (", target["current_energy"], "/", max_energy, ")")
					update_energy_bar(target)

					# Notify combat manager if energy is full (for ability casting)
					if target["current_energy"] >= max_energy and combat_manager and combat_manager.has_method("cast_ability"):
						combat_manager.cast_ability(target)

	# 6. Check if unit is destroyed
	var total_health = target.get("current_armor", 0) + target.get("current_shield", 0)
	if total_health <= 0:
		print("  UNIT DESTROYED!")
		unit_destroyed.emit(target)

	return damage_breakdown

# ============================================================================
# HEALING AND RESTORATION
# ============================================================================

func heal_armor(target: Dictionary, amount: int):
	"""Restore armor (capped at max)."""
	if target.is_empty() or not target.has("current_armor"):
		return

	var max_armor = target.get("stats", {}).get("armor", 0)
	target["current_armor"] = min(target["current_armor"] + amount, max_armor)
	update_health_bar(target)
	print("  ", target.get("type", "unknown"), " armor restored: +", amount, " (", target["current_armor"], "/", max_armor, ")")

func restore_shield(target: Dictionary, amount: int):
	"""Restore shield (capped at max)."""
	if target.is_empty() or not target.has("current_shield"):
		return

	var max_shield = target.get("stats", {}).get("shield", 0)
	target["current_shield"] = min(target["current_shield"] + amount, max_shield)
	update_health_bar(target)
	print("  ", target.get("type", "unknown"), " shield restored: +", amount, " (", target["current_shield"], "/", max_shield, ")")

func add_overshield(target: Dictionary, amount: int):
	"""Add overshield (temporary shields on top of regular shields)."""
	if target.is_empty():
		return

	if not target.has("current_overshield"):
		target["current_overshield"] = 0

	target["current_overshield"] += amount
	update_health_bar(target)
	print("  ", target.get("type", "unknown"), " gained overshield: +", amount, " (", target["current_overshield"], " total)")

func heal_full(target: Dictionary):
	"""Fully restore armor, shield, and remove overshield."""
	if target.is_empty():
		return

	target["current_armor"] = target.get("stats", {}).get("armor", 0)
	target["current_shield"] = target.get("stats", {}).get("shield", 0)
	target["current_overshield"] = 0
	update_health_bar(target)
	print("  ", target.get("type", "unknown"), " fully healed")

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

func get_health_percentage(unit: Dictionary) -> float:
	"""Get combined health percentage (0.0 to 1.0)."""
	if unit.is_empty():
		return 0.0

	var max_armor = unit.get("stats", {}).get("armor", 0)
	var max_shield = unit.get("stats", {}).get("shield", 0)
	var max_health = max_armor + max_shield

	if max_health <= 0:
		return 0.0

	var current_armor = unit.get("current_armor", 0)
	var current_shield = unit.get("current_shield", 0)
	var current_health = current_armor + current_shield

	return float(current_health) / float(max_health)

func is_alive(unit: Dictionary) -> bool:
	"""Check if unit is alive (has any armor or shield remaining)."""
	if unit.is_empty():
		return false

	var current_armor = unit.get("current_armor", 0)
	var current_shield = unit.get("current_shield", 0)
	return (current_armor + current_shield) > 0

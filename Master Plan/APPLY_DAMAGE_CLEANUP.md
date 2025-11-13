# apply_damage() Function Cleanup - Complete!

## Problem

There were **4 different `apply_damage` functions** scattered across the codebase, causing confusion about which one was being used and why health bars weren't updating.

## Solution: ONE Source of Truth

### ✅ **THE ONE TRUE `apply_damage`**: `scripts/CombatHealthSystem.gd:211`

**This is the ONLY implementation that should exist.**

```gdscript
func apply_damage(target: Dictionary, damage: int) -> Dictionary
```

**What it does:**
1. Applies damage: overshield → shield → armor
2. **Automatically calls `update_health_bar()`**
3. Generates energy from damage taken
4. Emits `unit_destroyed` signal when unit dies
5. Returns damage breakdown dictionary

**Location**: `scripts/CombatHealthSystem.gd` line 211

---

## What Was Removed/Fixed

### ❌ **REMOVED**: `Combat_2.gd:3034`
**Status**: Completely removed and replaced with comment explaining where to find it

**Why**: This was a duplicate implementation that:
- Did its own damage calculation
- Was never supposed to be called directly
- Caused confusion about which function was "real"

**Action Taken**:
- Removed the entire 65-line function
- Replaced with clear comment pointing to CombatHealthSystem
- Updated the 2 deprecated function calls to use `health_system.apply_damage()`

---

### ✅ **KEPT**: `CombatWeapons.gd:305`
**Status**: Valid delegator (3 lines)

```gdscript
func apply_damage(target: Dictionary, damage: int):
    if health_system:
        health_system.apply_damage(target, damage)
```

**Why kept**: This is a thin wrapper that delegates to the health system. It's valid because:
- Weapons module needs to apply damage
- It properly delegates to the authority (CombatHealthSystem)
- Only 3 lines - just a passthrough

---

### ✅ **KEPT**: `CombatProjectileManager.gd:294`
**Status**: Valid delegator with format conversion

```gdscript
func apply_damage(target: Dictionary, damage_result: Dictionary) -> Dictionary:
    var damage = damage_result.get("damage", 0)
    # ... handle miss case ...
    var damage_breakdown = health_system.apply_damage(target, damage)
    # ... format return value ...
```

**Why kept**: This wrapper:
- Takes a different parameter format (`damage_result` dict instead of int)
- Handles miss detection
- Delegates actual damage to health system
- Converts return format for projectile system needs

---

## Current Call Chain

### Main Combat Flow:
```
1. Projectile hits
   ↓
2. CombatProjectileManager.apply_damage(target, damage_result)
   └─> Extracts damage from result dict
   └─> Handles miss case
   ↓
3. health_system.apply_damage(target, damage)  ← THE ONE TRUE FUNCTION
   └─> Applies damage (overshield → shield → armor)
   └─> Calls update_health_bar(target)  ← Bars update here!
   └─> Generates energy
   └─> Emits unit_destroyed if dead
   ↓
4. Returns to CombatProjectileManager
   ↓
5. Shows damage numbers on screen
```

### Alternative Flow (Weapons):
```
1. Weapon fires
   ↓
2. CombatWeapons.apply_damage(target, damage)
   ↓
3. health_system.apply_damage(target, damage)  ← Same function!
   └─> (same as above)
```

---

## Summary of Changes

### Files Modified:

1. **`scripts/Combat_2.gd`**
   - ❌ **REMOVED** `apply_damage()` function (was at line 3034)
   - ✅ Replaced with comment pointing to CombatHealthSystem
   - ✅ Updated 2 deprecated function calls to use `health_system.apply_damage()`

2. **`scripts/CombatProjectileManager.gd`**
   - ✅ Added `health_system` reference
   - ✅ Modified `initialize()` to get health system
   - ✅ Updated `apply_damage()` to delegate to health system

3. **`scripts/CombatWeapons.gd`**
   - ✅ Already updated to delegate to health system (from previous refactor)

4. **`scripts/CombatHealthSystem.gd`**
   - ✅ Contains the ONE TRUE `apply_damage()` implementation

---

## How to Apply Damage Now

### From anywhere in the code:

```gdscript
# Get the health system (usually passed as reference)
var health_system = get_node("/root/Combat_2/HealthSystem")

# Apply damage
var damage_breakdown = health_system.apply_damage(target, damage_amount)

# damage_breakdown contains:
# {
#     "overshield_damage": int,
#     "shield_damage": int,
#     "armor_damage": int
# }
```

### The health system automatically:
- ✅ Reduces shield/armor values
- ✅ Updates health bars visually
- ✅ Generates energy from damage
- ✅ Emits signal if unit destroyed
- ✅ Prints debug info

---

## Testing

Run the game and attack a ship. You should now see:

```
CombatProjectileManager: Health system linked
...
DEBUG: update_health_bar - bar_width=32 max_armor=200 current_armor=197 ...
  Shield damaged: -3 (147 remaining)
DEBUG: ShieldBar - percent=0.98 new_width=31.36 old size=(32, 4)
DEBUG: ShieldBar - after setting, size=(31.36, 4)
```

**Signs it's working:**
- ✅ "Health system linked" message on startup
- ✅ "DEBUG: update_health_bar" messages when damage dealt
- ✅ "Shield damaged" / "Armor damaged" messages
- ✅ Visual bars shrinking as units take damage

---

## Benefits

1. **No Confusion**: Only ONE place to look for damage logic
2. **No Duplicates**: Can't accidentally call the wrong function
3. **Easier to Maintain**: Change damage logic in ONE place
4. **Clear Hierarchy**: Everyone delegates to CombatHealthSystem
5. **Self-Documenting**: Clear comments explain where things are

---

**The codebase is now clean! All damage goes through ONE function in CombatHealthSystem.**

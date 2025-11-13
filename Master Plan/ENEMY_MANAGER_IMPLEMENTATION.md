# Enemy Manager Implementation - Complete!

**Date:** 2025-11-13
**Status:** ✅ Complete

## Summary

Created **CombatEnemyManager** module to handle automatic enemy spawning and movement in combat. This system spawns waves of enemies each turn and manages their forward movement toward player ships.

---

## What Was Created

### New File: `scripts/CombatEnemyManager.gd`

A standalone manager class that handles:

**Core Functions:**
- `process_turn_spawn_cycle()` - Main function called at turn start
- `move_all_enemies_forward()` - Moves all enemies in all lanes
- `spawn_new_wave_all_lanes()` - Spawns enemies at column 15
- `spawn_turn_wave(lane_index)` - Spawns for a single lane
- `spawn_enemy_at_position()` - Spawns enemy at specific grid position

**Spawn Rules Per Lane:**
- 2 mooks (guaranteed)
- 1 elite (30% chance)
- All spawn at column 15 (rightmost enemy column)

---

## Turn Timing Flow

**Detailed timing with comments in code:**

```
1. TURN START (return_to_tactical_phase)
   a. Reset movement flags for all units
   b. IF auto_spawn enabled:
      - Move all existing enemies forward
      - Spawn new wave at column 15
   c. Draw 3 cards
   d. Show "Proceed to Lane 1" button

2. TACTICAL PHASE
   - Player plays cards, manages fleet
   - Player clicks "Proceed to Lane X"

3. LANE TRANSITION (proceed_to_lane_transition)
   - Reset movement flags for this lane
   - Zoom to lane
   - IF auto_spawn disabled: Move enemies (backward compatibility)
   - Show "Start Combat" button

4. PRE-COMBAT PHASE (enter_pre_combat_check_phase)
   - Auto-queue ship abilities
   - Show ability review UI
   - User confirms combat start

5. COMBAT PHASE
   - 5 seconds of combat
   - Repeat steps 3-5 for remaining lanes

6. TURN END
   - Back to step 1 (new turn begins)
```

---

## UI Integration

### Auto Spawn Button

**Location:** Top-left at (0, 500)
**Text:** "AUTO SPAWN: OFF" / "AUTO SPAWN: ON"
**Function:** Toggles `auto_spawn_enabled` flag

When enabled:
- Enemies spawn automatically each turn
- Movement happens at turn start (not per-lane)

When disabled:
- Manual enemy deployment only
- Movement happens per-lane (old behavior)

---

## Files Modified

### 1. Combat_2.gd

**Variable Declarations** (lines 12, 62-63):
```gdscript
var enemy_manager: CombatEnemyManager = null
var auto_spawn_enabled: bool = false
var auto_spawn_button: Button = null
```

**Manager Initialization** (lines 134-138):
```gdscript
enemy_manager = CombatEnemyManager.new()
enemy_manager.name = "EnemyManager"
add_child(enemy_manager)
enemy_manager.initialize(self)
```

**Button Setup** (line 313):
```gdscript
setup_auto_spawn_button()
```

**Button Creation Function** (lines 2153-2163):
```gdscript
func setup_auto_spawn_button():
    auto_spawn_button = Button.new()
    auto_spawn_button.name = "AutoSpawnButton"
    auto_spawn_button.text = "AUTO SPAWN: OFF"
    auto_spawn_button.position = Vector2(0, 500)
    auto_spawn_button.size = Vector2(250, 50)
    auto_spawn_button.add_theme_font_size_override("font_size", 18)
    auto_spawn_button.add_to_group("ui")
    auto_spawn_button.pressed.connect(_on_auto_spawn_toggled)
    add_child(auto_spawn_button)
```

**Toggle Callback** (lines 2612-2621):
```gdscript
func _on_auto_spawn_toggled():
    auto_spawn_enabled = not auto_spawn_enabled
    if auto_spawn_enabled:
        auto_spawn_button.text = "AUTO SPAWN: ON"
        print("Auto-spawn ENABLED")
    else:
        auto_spawn_button.text = "AUTO SPAWN: OFF"
        print("Auto-spawn DISABLED")
```

**Turn Start Hook** (lines 3700-3703):
```gdscript
# Auto-spawn enemies if enabled (AFTER resetting movement flags, BEFORE drawing cards)
if auto_spawn_enabled and enemy_manager:
    print("Combat_2: Processing turn spawn cycle")
    enemy_manager.process_turn_spawn_cycle()
```

**Lane Transition Update** (lines 3667-3670):
```gdscript
# ENEMY PATHFINDING ALPHA - Move enemies toward player before precombat phase
# NOTE: If auto_spawn is enabled, enemy movement happens at turn start instead
if not auto_spawn_enabled:
    enemy_pathfinding_alpha(next_lane_index)
```

---

## Enemy Types (from ship_database.csv)

### Mook
- ship_id: "mook"
- sprite: res://assets/Ships/alien/s_alien_09.png
- size: 30
- movement_speed: 3
- armor: 150
- shield: 0
- damage: 3

### Elite
- ship_id: "elite"
- sprite: res://assets/Ships/alien/s_alien_05.png
- size: 36
- movement_speed: 2
- armor: 500
- shield: 100
- damage: 10
- ability: "Acid Splash"

---

## Implementation Details

### Spawning Logic

**Column 15 Selection:**
- Enemies spawn at column 15 (rightmost column in grid)
- Uses `get_available_spawn_rows()` to find empty rows
- Sequentially fills rows 0-4 as available

**Wave Composition:**
```gdscript
1. Spawn mook #1 at first available row
2. Spawn mook #2 at second available row
3. Roll 30% chance:
   - If success: Spawn elite at third available row
   - Logs: "Elite spawned in lane X (roll: Y)"
```

**Grid Position:**
- Grid is 5 rows × 16 columns (0-4, 0-15)
- Player deploys in columns 0-3
- Enemies spawn in columns 12-15
- Column 15 = rightmost spawn position

### Movement Logic

**Forward Movement:**
- Extracted from `enemy_pathfinding_alpha()` in Combat_2
- Each enemy moves left by their `movement_speed` value
- Checks for blocking player ships
- Stops when adjacent to player (no collision, just blocks)
- Updates grid positions using `move_ship_to_cell()`

**Movement Flags:**
- `has_moved_this_turn` prevents double-moving
- Reset at turn start via `reset_ship_movement_flags()`
- New spawns have `has_moved_this_turn = false` (can move next turn)

### Grid Integration

**spawn_enemy_at_position():**
- Creates enemy_dict with all required fields
- Calls `occupy_grid_cell()` to mark position
- Adds to `lanes[lane_index]["units"]` array
- Creates health bar via `health_system.create_health_bar()`
- Validates cell is empty before spawning

**move_enemy_forward():**
- Gets current position from `grid_row`, `grid_col`
- Calculates target based on `movement_speed`
- Checks each cell for player ships (blocking)
- Calls `move_ship_to_cell()` (handles grid updates)
- Returns true if moved, false if blocked/already moved

---

## Usage

### Enable Auto-Spawn Mode

1. Click "AUTO SPAWN: OFF" button (changes to "AUTO SPAWN: ON")
2. Play through all 3 lanes of combat
3. When turn ends and you return to tactical phase:
   - All existing enemies move forward
   - New wave spawns at column 15
   - You draw 3 cards
4. Repeat

### Disable Auto-Spawn Mode

1. Click "AUTO SPAWN: ON" button (changes to "AUTO SPAWN: OFF")
2. Back to manual enemy deployment
3. Enemies move per-lane (old behavior)

---

## Testing Checklist

- [x] Auto-spawn button appears at correct position
- [x] Button toggles ON/OFF correctly
- [x] Turn start spawns 2 mooks per lane
- [x] 30% elite spawn chance works
- [x] Enemies spawn at column 15
- [x] Enemies move forward at turn start
- [x] Movement stops when blocked by player ships
- [x] Grid positions update correctly
- [x] Health bars display on spawned enemies
- [x] Spawned enemies can attack player ships
- [x] No double-movement per turn
- [x] Backward compatibility when auto-spawn OFF

---

## Future Enhancements

### Potential Additions:

1. **Wave Difficulty Scaling**
   - Increase mooks per lane as turns progress
   - Higher elite spawn chance over time
   - Boss waves every N turns

2. **Enemy Variety**
   - Different enemy types per lane
   - Special units (tanks, snipers, healers)
   - Enemy formations

3. **Spawn Position Variety**
   - Alternate spawn columns (14, 15)
   - Random row selection vs sequential
   - Pre-positioned enemies before turn 1

4. **Victory/Defeat Conditions**
   - Check if enemies reach column 0
   - Game over if mothership damaged
   - Wave counter UI

---

## Code Organization

**Module Pattern:**
- CombatEnemyManager is a standalone class
- Instantiated by Combat_2 (not autoload)
- Has reference to parent combat scene
- Calls Combat_2 methods (move_ship_to_cell, occupy_grid_cell)

**Benefits:**
- Clean separation of concerns
- Enemy logic isolated from Combat_2
- Easy to test and extend
- Follows existing manager pattern

---

## Statistics

**New Code:**
- CombatEnemyManager.gd: ~370 lines
- Combat_2.gd additions: ~50 lines

**Modified:**
- Combat_2.gd: Added manager integration, button, hooks

**Total Implementation:**
- 1 new file
- 1 modified file
- ~420 lines of new code

---

**The enemy spawning system is now fully functional!**

## Quick Reference

### How to Use (from code):

```gdscript
# Enable auto-spawn
auto_spawn_enabled = true

# At turn start (automatically triggered):
enemy_manager.process_turn_spawn_cycle()
# This calls:
#   1. move_all_enemies_forward()
#   2. spawn_new_wave_all_lanes()

# Manual spawn (if needed):
enemy_manager.spawn_enemy_at_position("mook", lane_index, row, col)
```

---

**Document Generated:** 2025-11-13
**Related Systems:** Combat turn flow, grid system, ship manager
**Impact:** High - Enables automated enemy spawning for gameplay loop

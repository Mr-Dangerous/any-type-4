# Combat_3 Module - Design Plan

## Overview
Combat_3 is a complete redesign of the combat system, shifting from the 3-lane tactical view (Combat_2) to a large grid-based battlefield with continuous forward movement and turn-based tactical phases. This system emphasizes deployment strategy, positional tactics, and timing-based ability execution.

---

## Core Grid System

### Grid Specifications
- **Dimensions**: 20 rows (vertical) × 25 columns (horizontal)
- **Cell Size**: 32px (matching Combat_2's existing grid system)
- **Total Combat Area**: 640px tall × 800px wide
- **Column 0**: Reserved for player turret slots (empty for now, future feature)
- **Deployment Zones**:
  - **Player**: Columns 1-5 (determined by movement speed)
  - **Enemy**: Columns 20-25 (calculated as 25 - movement_speed)

### Grid Occupancy
- **One unit per cell** - Ships cannot stack
- **Occupancy tracking**: 2D array `grid[row][col]` storing unit references
- **Helper functions**:
  - `is_cell_occupied(row, col) -> bool`
  - `occupy_cell(row, col, unit)`
  - `free_cell(row, col)`
  - `get_unit_at_cell(row, col) -> Unit`

---

## Game Flow Structure

### Phase Diagram
```
START COMBAT
    ↓
PRE-COMBAT PHASE (Initial Deployment)
    ↓
    ┌─────────────────────────────────┐
    │  MAIN GAME LOOP                 │
    │                                 │
    │  PRE-TACTICAL PHASE             │
    │  - Enemy spawn                  │
    │  - Pre-tactical abilities       │
    │  - Camera pan down enemy column │
    │                                 │
    │  TACTICAL PHASE                 │
    │  - Draw 3 cards                 │
    │  - Play cards                   │
    │  - Move ships                   │
    │  - Build ability queue          │
    │  - Press "Move to Combat"       │
    │                                 │
    │  PRE-COMBAT PHASE               │
    │  - Ability queue resolves       │
    │  - 1 second per ability         │
    │  - Cinematic zoom + slow-mo     │
    │  - Release projectiles          │
    │                                 │
    │  COMBAT PHASE (20 seconds)      │
    │  - Auto-attack in range         │
    │  - Move forward when not        │
    │  - Ship abilities cast          │
    │  - Combos trigger               │
    │                                 │
    │  CLEANUP PHASE                  │
    │  - Discard all cards            │
    │  - Clear temporary effects      │
    │                                 │
    └─────────────────────────────────┘
    ↓ (loop until victory/defeat)
VICTORY/DEFEAT CONDITION CHECK
```

---

## Phase 1: Pre-Combat Phase (Initial Deployment)

### Player Ship Deployment
**Timing**: When entering combat module

**Deployment Logic**:
1. **Determine deployment column**: `deployment_column = ship.movement_speed`
   - Movement speed 1 → Column 1
   - Movement speed 2 → Column 2
   - Movement speed 3 → Column 3
   - etc.

2. **Determine deployment row**: Start from center (row 10), spiral outward
   - First ship → Row 10
   - Second ship → Row 9
   - Third ship → Row 11
   - Fourth ship → Row 8
   - Fifth ship → Row 12
   - Pattern: 10, 9, 11, 8, 12, 7, 13, 6, 14, 5, 15, 4, 16, 3, 17, 2, 18, 1, 19, 0

3. **Collision check**: If target cell occupied, skip to next row in spiral

**Deployment Animation**:
```
Start Position: Bottom-left corner off-screen (-50, viewport_height + 50)
↓
Phase 1: Fly straight up until (row_target - 1)
   - Duration: Based on distance, ~0.5s per 100px
   - Rotation: Ship faces up (rotation = -PI/2)
↓
Phase 2: Turn right and fly to column
   - Smooth rotation transition (-PI/2 → 0)
   - Duration: 0.3s
↓
Phase 3: Settle into grid position
   - Final position: grid_position(row, col)
   - Rotation: Face right (rotation = 0)
```

**Data Structure** (per deployed ship):
```gdscript
{
    "ship_id": "basic_interceptor",
    "container": Node2D,  # Visual container
    "sprite": TextureRect,
    "grid_pos": Vector2i(10, 2),  # row, col
    "stats": {...},  # From ship_database
    "current_armor": 200,
    "current_shield": 150,
    "current_energy": 10,
    "ability_queue": [],  # Queued abilities from cards
    "status_effects": {},  # burn, freeze, etc.
    "temporary_modifiers": {},  # Card effects this turn
    "has_moved_this_turn": false,
    "attack_target": null,
    "attack_timer": Timer
}
```

### Enemy Initial Deployment
**Timing**: Simultaneous with player deployment

**Deployment Logic**:
1. **Determine deployment column**: `deployment_column = 25 - enemy.movement_speed`
   - Movement speed 1 → Column 24
   - Movement speed 2 → Column 23
   - Movement speed 3 → Column 22

2. **Determine deployment row**: Weighted random
   - **Default weights**: Gaussian distribution centered on row 10
   - **Weight array example**:
     ```
     Row 10 (center): 20% weight
     Rows 9, 11: 15% each
     Rows 8, 12: 12% each
     Rows 7, 13: 10% each
     Rows 6, 14: 6% each
     Rows 5, 15: 4% each
     Rows 0-4, 16-19: 1% each
     ```
   - **Scenario override**: Different scenarios can adjust weights (e.g., boss waves favor specific rows)

3. **Collision check**: If target cell occupied, re-roll row (max 10 attempts)

**Deployment Animation**:
```
Start Position: Off-screen right, aligned with target row
   - Position: (viewport_width + 100, grid_y[row])
↓
Phase 1: Fly straight left to deployment column
   - Duration: 0.8s
   - Rotation: Ship faces left (rotation = PI)
↓
Phase 2: Settle into grid position
   - No rotation change
```

---

## Phase 2: Main Game Loop - Pre-Tactical Phase

### Enemy Spawning
**Timing**: Start of each turn (before tactical phase)

**Spawn Logic** (similar to initial deployment):
- Spawn at column `25 - movement_speed`
- Weighted row selection (scenario-dependent)
- Cannot stack on existing enemies
- must be able to accommodate units that are 2x2 or 3x3 or even 5x5, but not at first
- **Wave composition** (scenario-dependent):
  - Example: 2-3 mooks + 30% chance for 1 elite per turn
  - Boss waves: Specific compositions
  - will be built using a csv. 

**Camera Pan Animation**:
```
Start: Current camera position
↓
Transition: Smooth pan to enemy spawn column (column 22-25)
   - Duration: 1.0s
   - Easing: Cubic in-out
↓
Pan Down: Scroll from top (row 0) to bottom (row 19)
   - Duration: 2.0s
   - Speed: ~10 rows/second
   - Purpose: Show player all spawning enemies
↓
Return: Pan back to tactical view (columns 0-12 visible)
   - Duration: 0.8s
```

### Pre-Tactical Abilities
**Trigger Condition**: "At the start of the next tactical phase..."

**Examples**:
- Regeneration effects
- Buff/debuff applications
- Energy generation
- Shield restoration

**Execution**:
- All pre-tactical abilities resolve in order
- Visual notifications for each effect
- Brief pause (0.5s) between effects

---

## Phase 3: Main Game Loop - Tactical Phase

### Card Draw System
**Timing**: Immediately after pre-tactical phase

**Draw Logic**:
- Draw 3 cards from deck
- If deck empty, shuffle discard pile into deck
- Add cards to hand UI (bottom of screen)
- Hand persists from previous turns

**Integration with Combat_2 Systems**:
- Reuse CardHandManager singleton
- Reuse Card.tscn and card drag-and-drop logic
- Card effects from CardEffects.gd

### Card Playing
**Target Types** (from card_database.csv):
- `friendly_ship` - Drag to allied ship
- `friendly_turret` - Drag to turret (future)
- `enemy_ship` - Targeting handled via ability_queue_target

**Card Execution Types**:
1. **Instant Execution** (`ability_queue = FALSE`):
   - Effect applies immediately
   - Examples: Shield, Strike, Energy Alpha
   - Visual notification above target

2. **Ability Queue** (`ability_queue = TRUE`):
   - Ability stored on target ship's `ability_queue` array
   - Includes: card effect, target type, projectile data
   - Executes during pre-combat phase
   - Examples: Missile Lock, Incinerator Cannon

**Ability Queue Data Structure**:
```gdscript
{
    "card_name": "Missile Lock",
    "effect_function": "execute_Missile_Lock",
    "target_type": "enemy",  # from ability_queue_target column
    "projectile_sprite": "res://...",
    "projectile_size": 70,
    "combo_trigger_flag": true,
    "trigger_type": "explosive"
}
```

### Ship Movement During Tactical Phase
**Movement Rules**:
- Ships can move **up to movement_speed cells** per turn
- **Directions allowed**:
  - Up/Down (same column)
  - Backward (left, toward player side)
- **Restrictions**:
  - Cannot move forward (right) during tactical phase
  - Cannot move onto occupied cells (allied ships)
  - Cannot move more than once per turn (`has_moved_this_turn` flag)

**Movement Implementation**:
- **Drag-and-drop** (similar to Combat_2):
  1. Click and hold ship
  2. Drag to target cell
  3. Highlight valid cells (green) and invalid cells (red)
  4. Release to move
  5. Animate movement (0.3s tween)
  6. Set `has_moved_this_turn = true`

- **Valid move detection**:
  ```gdscript
  func is_valid_tactical_move(from: Vector2i, to: Vector2i, move_speed: int) -> bool:
      var distance = abs(to.x - from.x) + abs(to.y - from.y)  # Manhattan
      if distance > move_speed:
          return false
      if to.x > from.x:  # No forward movement
          return false
      if is_cell_occupied(to.y, to.x):
          return false
      return true
  ```

### Ship Deployment During Tactical Phase
**Trigger**: Some scenarios allow deploying additional ships mid-combat

**Logic**:
- Same deployment rules as initial pre-combat phase
- Ships deploy to column matching movement speed
- Find first available row near center
- Deployment animation (fly in from bottom-left)

### "Move to Combat" Button
**UI Position**: Bottom-right corner (CanvasLayer)

**Functionality**:
- Press to end tactical phase
- Triggers transition to pre-combat phase
- Disabled until player has drawn cards (prevents skipping draw)

---

## Phase 4: Main Game Loop - Pre-Combat Phase

### Ability Queue Resolution
**Timing**: After player presses "Move to Combat", before 20s combat

**Resolution Order**: FIFO (First In, First Out)
- Cards played earlier resolve first
- If multiple ships have queued abilities, interleave by play order

**Cinematic Presentation** (per ability):
```
Step 1: Pause all combat activity
↓
Step 2: Camera zoom to casting ship
   - Zoom level: 1.5x
   - Duration: 0.3s
   - Target: Ship's grid position
↓
Step 3: Card popup above ship
   - Display card sprite and name
   - Scale-in animation (0.2s)
   - Hold for 0.5s
↓
Step 4: Launch projectiles in slow-motion
   - Projectiles move 10% of distance
   - Duration: 0.5s
   - Projectiles pause mid-flight
↓
Step 5: Card popup fades out (0.2s)
↓
Step 6: Move to next ability in queue
   (Total time per ability: ~1.5s)
```

**After All Abilities**:
```
Step 1: Camera reset to battlefield overview
   - Zoom out to show full combat area
   - Duration: 0.4s
↓
Step 2: Release all projectiles simultaneously
   - All paused projectiles fly to targets at full speed
   - Flight duration: 0.3s
↓
Step 3: Projectiles hit targets
   - Damage calculation
   - Combo checks (if applicable)
   - Status effect application
↓
Step 4: Begin 20-second combat phase
```

### Staggered Projectile Launch
**Problem**: Multiple abilities from same ship would overlap

**Solution**: Projectiles from same ship launch with slight offset
- First ability: Launch from ship center
- Second ability: Launch from ship center + 15px offset
- Third ability: Launch from ship center + 30px offset
- Creates visual separation while maintaining timing

---

## Phase 5: Main Game Loop - Combat Phase (20 Seconds)

### Combat Timer
**Duration**: 20 seconds per combat phase

**UI Display**:
- Large countdown timer (top-center, UI layer)
- Updates every 0.1s
- Red color when < 5 seconds
- Timer pauses when abilities cast or combos trigger

### Auto-Attack System
**Range Check**:
- Ships attack when in range of enemy in same row
- Range value from `ship_database.csv` (future column)
- For now: Default range = 5 cells (160px)

**Attack Logic**:
```gdscript
func check_for_targets_in_range(unit):
    var row = unit.grid_pos.x
    var col = unit.grid_pos.y

    # Search right (forward) along row
    for distance in range(1, unit.range + 1):
        var check_col = col + distance
        if check_col >= 25:
            break

        var target = get_unit_at_cell(row, check_col)
        if target and target.faction != unit.faction:
            return target  # Found enemy in range

    return null  # No target in range
```

**Attack Execution**:
- Fire projectiles at `attack_speed` intervals (from database)
- Number of projectiles = `num_attacks` (from database)
- Attack continues until:
  - Target destroyed
  - Target moves out of range
  - Combat phase ends

**Attack Priority**:
1. Closest enemy in row
2. If no enemy in row → Check turrets/mothership (player) or boss (enemy)

### Movement During Combat
**Trigger**: No valid targets in range

**Movement Logic**:
```
If no target in range:
    Begin moving forward (right, toward enemy)

    Movement speed: 5 / movement_speed seconds per grid cell
        - Movement speed 1: 5 seconds per cell
        - Movement speed 2: 2.5 seconds per cell
        - Movement speed 3: 1.67 seconds per cell

    While moving:
        Continuously check for targets in range

        If target found:
            Slow down and settle into current grid cell
            Begin attacking

        If next grid cell occupied by ally:
            If this ship has higher movement_speed:
                And next grid cell after ally is free:
                    Begin overtaking (target cell + 1)
            Else:
                Stop behind ally

        If reached valid grid cell:
            Occupy cell
            Check for targets
```

**Movement Animation**:
- Smooth tween from current position to next cell
- Duration: `5.0 / movement_speed` seconds
- Easing: Linear (constant speed)
- Ship continues to face right (rotation = 0)

**Settling Animation** (when target found mid-movement):
```
Current state: Ship between cells A and B, moving toward B
Target found!
↓
Calculate remaining distance to cell B
Ease out movement speed (cubic easing)
Arrive at cell B over next 0.5s
Set position to exact grid center
Begin attacking
```

### Overtaking Mechanic
**Scenario**: Fast ship behind slow ship, both in same row

**Conditions**:
1. Ship A (faster) is behind Ship B (slower)
2. Ship A has `movement_speed > Ship B.movement_speed`
3. Cell ahead of Ship B is empty
4. Both ships are allies

**Behavior**:
```
Ship A detects Ship B blocking forward movement
↓
Ship A checks if overtake possible:
   - Is Ship A faster? (movement_speed comparison)
   - Is cell after Ship B empty?
↓
If yes:
   Ship A sets target cell = Ship B position + 1
   Ship A moves around Ship B (no collision)
   Ship A occupies new cell
↓
If no:
   Ship A stops behind Ship B
   Ship A waits until Ship B moves or is destroyed
```

**Visual Implementation**:
- No fancy path-finding or diagonal movement (alpha version)
- Ship simply "skips" the occupied cell in movement calculation
- Future: Could add slight vertical offset animation for visual clarity

### Boss/Mothership Targeting
**Scenario**: No valid ship targets in row

**Player Ships**:
- If no enemies in row → Target enemy boss/spawner
- Move toward rightmost column (column 24)
- Attack when in range

**Enemy Ships**:
- If no player ships in row → Target mothership/turrets
- Move toward leftmost column (column 0)
- Attack when in range

**Victory/Defeat Conditions**:
- **Victory**: All enemy ships destroyed + wave counter = 0
- **Defeat**: Mothership health reaches 0 (future implementation)

### Ship Ability Casting During Combat
**Trigger**: Ship energy reaches maximum

**Execution**:
```
Ship reaches max energy
↓
Pause combat (set combat_paused = true)
↓
Cinematic zoom to ship (1.0s):
   - Zoom to 1.3x
   - Center on ship
↓
Card popup appears (0.5s):
   - Display ability card above ship
   - Show ability name and icon
↓
Launch projectiles in slow-motion (1.0s):
   - Projectiles move 10% of distance
   - Pause mid-flight
↓
Resume combat (set combat_paused = false)
↓
Release projectiles at full speed (0.3s)
↓
Projectiles hit targets
   - Apply damage
   - Check for combos
   - Apply status effects
↓
Camera zoom out to battlefield (0.4s)
```

**Energy Reduction**:
- After casting, energy resets to 0
- Energy generation resumes with next attack

---

## Phase 6: Combo System

### Combo Trigger Mechanism
**Setup Phase**: Apply status effect to enemy
- Example: Incinerator Cannon → 3 burn stacks on enemy

**Trigger Phase**: Hit enemy with combo trigger card
- **Trigger check** (in projectile hit handler):
  ```gdscript
  if projectile.combo_trigger_flag:
      var trigger_type = projectile.trigger_type  # "explosive", "fire", etc.
      var target_status = target.status_effects

      # Check for matching combo
      var combo = check_for_combos(trigger_type, target_status)
      if combo:
          execute_combo(combo, target)
  ```

**Combo Execution**:
```
Combo detected!
↓
Pause combat (combat_paused = true)
↓
Zoom in to target (0.3s):
   - Zoom: 1.5x
   - Center: Target position
↓
Display combo notification (1.0s):
   - Large text: "SHRAPNEL BLAST!"
   - Color: Bright orange/yellow
   - Scale-up animation + screen shake
↓
Execute combo effect:
   - Calculate damage (e.g., 20 damage per burn stack)
   - Apply to target + AoE
   - Consume status effect stacks
↓
Display damage numbers
↓
Resume combat (combat_paused = false)
↓
Camera zoom out (0.4s)
```

### Combo Registry
**Data Structure** (in CombatComboSystem.gd):
```gdscript
var combos = [
    {
        "name": "Shrapnel Blast",
        "trigger_type": "explosive",
        "required_status": "burn",
        "effect_function": "execute_Shrapnel_Blast",
        "description": "20 fire damage per burn stack. AoE(1)"
    },
    {
        "name": "Steam Explosion",
        "trigger_type": "fire",
        "required_status": "freeze",
        "effect_function": "execute_Steam_Explosion",
        "description": "30 fire damage, blind for 2s. AoE(1)"
    },
    # Add all combos from card_database.csv
]
```

### Combo Resolution Modes
**Option 1**: Priority Mode (default)
- Only first matching combo executes
- Priority order: burn → freeze → static → acid → gravity

**Option 2**: Multi-Combo Mode (configurable)
- All applicable combos execute in sequence
- Each combo has 1.5s cinematic
- Screen shake stacks

**Configuration**:
```gdscript
# In Combat_3.gd
var ALLOW_MULTIPLE_COMBOS = false  # Default: priority mode
```

---

## Phase 7: Cleanup Phase

### Card Discard
**Timing**: After 20-second combat phase ends

**Logic**:
- All cards in hand → Discard pile
- Hand UI clears
- Ability queue on all ships clears
- CardHandManager.discard_hand() function

### Temporary Effect Removal
**Effects to Clear**:
- Card-based modifiers (Strike, Incendiary Rounds, Cryo Rounds, etc.)
- Temporary stat bonuses
- Visual indicators (e.g., "Fire Ammo" label)

**Effects to Persist**:
- Status effects (burn, freeze - continue ticking)
- Ship health/shields/energy
- Ship positions on grid
- Attack timers

**Visual Notification**:
- Floating text: "Effects cleared"
- Brief fade-out of temporary effect icons

### Reset Flags
```gdscript
for ship in all_ships:
    ship.has_moved_this_turn = false
    ship.temporary_modifiers = {}
```

---

## Victory and Defeat Conditions

### Victory Condition
```gdscript
func check_victory():
    if all_enemy_ships_destroyed() and wave_counter == 0:
        trigger_victory()
```

**Victory Sequence**:
1. Stop combat timer
2. Disable all input
3. Display "VICTORY" notification (2s)
4. Show rewards screen (future)
5. Return to starmap

### Defeat Condition
```gdscript
func check_defeat():
    if mothership.health <= 0:
        trigger_defeat()
```

**Defeat Sequence**:
1. Stop combat timer
2. Display "DEFEAT" notification (2s)
3. Show retry/quit options
4. Return to main menu

### Wave Counter System
**Wave Counter**: Number of enemy waves remaining

**Scenario Configuration**:
- Easy scenarios: 3 waves
- Medium scenarios: 5 waves
- Hard scenarios: 7+ waves
- Boss scenarios: Custom wave compositions

**Wave Counter UI**:
- Display at top-right: "Wave 1/5"
- Decrements after each pre-tactical phase (when enemies spawn)
- Red color on final wave

**Wave Decrement Timing**:
```
Pre-Tactical Phase begins
↓
Spawn enemies (wave_counter decrements)
↓
Update wave counter UI
↓
Check if wave_counter == 0 and no enemies left → Victory
```

---

## Camera System

### Camera Modes

#### Tactical View (Default)
- **Zoom**: 1.0x (or slightly zoomed out to fit grid)
- **Position**: Centered on columns 5-15 (mid-battlefield)
- **Purpose**: See player and enemy positions, plan moves

#### Enemy Spawn Pan (Pre-Tactical)
- **Zoom**: 1.2x
- **Start**: Top of enemy column (row 0, column 23)
- **End**: Bottom of enemy column (row 19, column 23)
- **Duration**: 2.0s
- **Purpose**: Show player all spawning enemies

#### Ability Cinematic Zoom
- **Zoom**: 1.5x
- **Position**: Centered on casting ship
- **Duration**: 1.5s per ability
- **Purpose**: Highlight ability cast

#### Combo Cinematic Zoom
- **Zoom**: 1.5x
- **Position**: Centered on target
- **Duration**: 1.0s
- **Purpose**: Highlight combo trigger

### Camera Transitions
All camera movements use **cubic easing** (in-out) for smooth transitions.

**Transition Helper Function**:
```gdscript
func transition_camera(target_pos: Vector2, target_zoom: float, duration: float):
    var tween = create_tween()
    tween.set_ease(Tween.EASE_IN_OUT)
    tween.set_trans(Tween.TRANS_CUBIC)
    tween.parallel().tween_property(camera, "position", target_pos, duration)
    tween.parallel().tween_property(camera, "zoom", Vector2(target_zoom, target_zoom), duration)
```

---

## Grid and Cell Positioning

### Coordinate System
- **Grid coordinates**: `Vector2i(row, col)` - integer grid positions
- **World coordinates**: `Vector2(x, y)` - pixel positions in scene

**Conversion Functions**:
```gdscript
const CELL_SIZE = 32
const GRID_ORIGIN = Vector2(50, 100)  # Top-left corner of grid

func grid_to_world(row: int, col: int) -> Vector2:
    var x = GRID_ORIGIN.x + col * CELL_SIZE + CELL_SIZE / 2
    var y = GRID_ORIGIN.y + row * CELL_SIZE + CELL_SIZE / 2
    return Vector2(x, y)

func world_to_grid(world_pos: Vector2) -> Vector2i:
    var col = int((world_pos.x - GRID_ORIGIN.x) / CELL_SIZE)
    var row = int((world_pos.y - GRID_ORIGIN.y) / CELL_SIZE)
    return Vector2i(row, col)
```

### Grid Visualization (Debug Mode)
**Debug Toggle**: Press 'G' to toggle grid overlay

**Grid Overlay**:
- Semi-transparent lines for all rows and columns
- Cell numbers at intersections (small font)
- Different colors for zones:
  - Column 0 (turrets): Yellow
  - Columns 1-5 (player deploy): Blue
  - Columns 6-19 (battlefield): Gray
  - Columns 20-25 (enemy deploy): Red

---

## UI Layout

### Screen Layout (1152×648 default window)
```
┌─────────────────────────────────────────────────────┐
│  [Resources]           COMBAT_3         [Wave 3/5]  │ Top bar
├─────────────────────────────────────────────────────┤
│                                                      │
│                                                      │
│                  COMBAT GRID                         │
│              (20 rows × 25 columns)                  │
│                                                      │
│                                                      │
│                                                      │
├─────────────────────────────────────────────────────┤
│  [Card] [Card] [Card] [Card] [Card]                 │ Hand UI
└─────────────────────────────────────────────────────┘

Right side (overlay):
  - [Move to Combat] button (tactical phase)
  - Combat timer (combat phase)
```

### UI Elements

**Resources Panel** (top-left):
- Same as Combat_2 (reuse ResourceUI.gd)
- Metal, Crystals, Fuel, Pilots, etc.

**Wave Counter** (top-right):
- Text: "Wave 3/5"
- Font size: 24pt
- Red color on final wave

**Hand UI** (bottom, CanvasLayer z:500):
- Same as Combat_2 (reuse CardHandManager)
- 5-10 cards visible
- Drag-and-drop to play

**Combat Timer** (top-center, during combat):
- Text: "15.3s"
- Font size: 32pt
- Color: White (>5s), Red (<5s)
- Only visible during combat phase

**Phase Indicator** (top-center, during tactical):
- Text: "TACTICAL PHASE"
- Font size: 20pt
- Color: Cyan

**Move to Combat Button** (bottom-right):
- Text: "MOVE TO COMBAT"
- Size: 200×60px
- Only visible during tactical phase

---

## Technical Architecture

### Scene Structure
```
Combat_3.tscn
├── CanvasLayer (Background, z:-100)
│   └── BackgroundManager (reuse from Combat_2)
├── Node2D (GridContainer)
│   ├── GridOverlay (debug visualization)
│   └── UnitContainer (all ships spawn here)
├── Camera2D
├── CanvasLayer (UI, z:500)
│   ├── ResourceUI (top-left)
│   ├── WaveCounter (top-right)
│   ├── PhaseIndicator (top-center)
│   ├── CombatTimer (top-center)
│   ├── MoveToCombutButton (bottom-right)
│   └── HandUI (bottom)
└── CanvasLayer (Notifications, z:1000)
    ├── AbilityNotification
    ├── ComboNotification
    └── DamageNumbers
```

### Script Modules

**Combat_3.gd** (main script):
- Game loop state machine
- Phase transitions
- Grid management
- Unit spawning and tracking

**CombatGridManager.gd** (helper module):
- Grid occupancy tracking
- Coordinate conversions
- Valid move detection
- Pathfinding (future)

**CombatMovementSystem.gd** (helper module):
- Ship movement during combat
- Overtaking logic
- Animation and tweening
- Collision avoidance

**CombatCameraController.gd** (helper module):
- Camera transitions
- Cinematic zooms
- Enemy spawn pan
- Tactical view reset

**Reuse from Combat_2**:
- CombatProjectileManager.gd
- CombatStatusEffectManager.gd
- CombatComboSystem.gd
- CombatTargetingSystem.gd
- CombatWeapons.gd (for attack calculations)
- CardHandManager.gd (singleton)
- CardEffects.gd

---

## Data Requirements

### Ship Database Extensions
**New columns for ship_database.csv**:
- `range` (int): Attack range in cells (default: 5)
- `pre_tactical_ability` (string): Ability that triggers at turn start (optional)

### Scenario/Wave Configuration
**New CSV**: `enemy_waves.csv`
```csv
wave,Enemy,difficulty,conditions
1,mook,1,center_weighted
1,mook,1,center_weighted
2,mook,1,center_weighted
2,mook,1,center_weighted
2,elite,1,top_weighted
3,mook,1,random
3,elite,1,center_weighted
3,elite,1,center_weighted
```

**Columns**:
- `wave`: Wave number (1-7)
- `Enemy`: Enemy ship_id from ship_database.csv
- `difficulty`: Difficulty scaling multiplier
- `conditions`: Row weighting (center_weighted, top_weighted, bottom_weighted, random)

### Card Database Extensions
**Existing columns used**:
- `ability_queue`: TRUE/FALSE (whether card queues)
- `ability_queue_target`: "enemy", "self", etc. (target for queued abilities)
- `combo_trigger_flag`: TRUE/FALSE (can trigger combos)
- `trigger_type`: "explosive", "fire", etc. (which combos trigger)
- `combo_setup`: Status effect this combo requires (burn, freeze, etc.)
- `combo_trigger`: Trigger type required (fire, explosive, etc.)

---

## Implementation Phases

### Phase 1: Core Grid and Deployment (Week 1)
- [x] Create Combat_3.tscn scene
- [x] Implement 20×25 grid system (CombatGridManager)
- [x] Grid occupancy tracking
- [x] Grid coordinate conversions
- [x] Player ship deployment (initial)
- [x] Enemy ship deployment (initial)
- [x] Deployment animations (fly-in from edges)
- [x] Grid debug visualization
- [x] Dynamic scenario width (hide unused columns)
- [x] Wave-based enemy spawning system
- [x] CombatWaveManager singleton (loads scenarios.csv, enemy_waves.csv)
- [x] Weighted row selection (wave_width parameter)
- [x] Cinematic deployment camera sequence
- [x] Smart edge scrolling (blocks when no units in direction)
- [x] Spacebar camera snap-to-ships with auto-zoom

### Phase 2: Tactical Phase (Week 1-2)
- [ ] Tactical phase state machine
- [ ] Card draw system (reuse CardHandManager)
- [ ] Card playing (instant + queue)
- [ ] Ship movement (drag-and-drop, validation)
- [ ] "Move to Combat" button
- [ ] Phase UI indicators

### Phase 3: Pre-Combat Phase (Week 2)
- [ ] Ability queue resolution
- [ ] Cinematic camera zooms
- [ ] Card popup animations
- [ ] Slow-motion projectile launch
- [ ] Projectile release at full speed
- [ ] Staggered projectiles from same ship

### Phase 4: Combat Phase (Week 2-3)
- [ ] 20-second combat timer
- [ ] Auto-attack in range
- [ ] Forward movement when no targets
- [ ] Movement animation (5/movement_speed formula)
- [ ] Settling animation when target found
- [ ] Overtaking mechanic
- [ ] Boss/Mothership targeting
- [ ] Ship ability casting during combat

### Phase 5: Pre-Tactical Phase (Week 3)
- [ ] Enemy spawning system (load from enemy_waves.csv)
- [ ] Camera pan down enemy column
- [ ] Weighted row selection
- [ ] Pre-tactical abilities execution
- [ ] Wave counter system

### Phase 6: Cleanup and Loop (Week 3)
- [ ] Cleanup phase (discard, clear effects)
- [ ] Flag resets (has_moved_this_turn)
- [ ] Loop back to pre-tactical
- [ ] Victory/defeat condition checks
- [ ] Wave counter decrement

### Phase 7: Combo System (Week 4)
- [ ] Integrate CombatComboSystem.gd
- [ ] Combo detection in projectile hits
- [ ] Combo execution with cinematics
- [ ] Screen shake on combos
- [ ] Status effect consumption
- [ ] Multi-combo vs priority mode

### Phase 8: Polish and Testing (Week 4)
- [ ] Camera transitions polish
- [ ] UI animations and feedback
- [ ] Sound effects (placeholders)
- [ ] Balance testing (movement speeds, combat duration)
- [ ] Bug fixes
- [ ] Performance optimization

---

## Open Questions and Design Decisions

### Resolved
✓ **Grid size**: 20×25 (large enough for tactical depth, small enough to fit on screen)
✓ **Cell size**: 72px (increased from 32px for better visibility and ship centering)
✓ **Combat duration**: 20 seconds (long enough for movement, short enough to stay engaging)
✓ **Card draw**: 3 cards per turn (balance between options and hand bloat)
✓ **Movement formula**: 5/movement_speed seconds per cell (higher speed = faster movement)
✓ **Scenario width**: Variable per scenario (test_scenario = 15 columns, configurable in scenarios.csv)
✓ **Wave width**: Limits enemy spawn rows (test_scenario = 5 rows centered on player center)
✓ **Enemy deployment**: column = scenario_width - movement_speed (dynamic based on scenario)
✓ **Camera system**: Smart edge scrolling, cinematic deployment sequence, spacebar snap-to-all-ships

### To Decide
- **Camera zoom level for tactical view**: 1.0x? 0.8x? (Need to fit entire grid)
- **Turret implementation**: How many turrets in column 0? What abilities?
- **Boss/Mothership health**: How much health? Visual representation?
- **Energy generation during combat**: Only from attacks, or also from taking damage?
- **Ship abilities during tactical phase**: Can players manually trigger ship abilities, or only auto-cast?
- **Movement blocking**: Should player ships be able to block enemy advances strategically?
- **Range values**: What's a good default range? Should it vary significantly by ship class?
- **Scenario selection**: How does player choose which scenario to play?
- **Rewards system**: What rewards after victory? (Cards, resources, ship upgrades?)

### Future Enhancements
- **Pathfinding beta**: Ships path around obstacles (not just straight lines)
- **Diagonal movement**: Ships can move diagonally (changes movement rules)
- **Terrain/obstacles**: Grid cells with special properties (asteroids, nebulae, etc.)
- **Formations**: Pre-set ship formations for quick deployment
- **Retreat mechanic**: Ships can retreat to repair, but enemies advance
- **Multi-lane abilities**: Some abilities affect multiple rows
- **Environmental effects**: Space hazards that damage ships over time

---

## Integration with Existing Systems

### Reusable from Combat_2
- **CardHandManager**: Deck, hand, discard pile management
- **CardEffects.gd**: All card effect functions
- **CombatProjectileManager**: Projectile spawning and management
- **CombatStatusEffectManager**: Burn, freeze, acid, etc.
- **CombatComboSystem**: Combo detection and execution
- **CombatTargetingSystem**: Target selection logic (alpha/beta modes)
- **CombatWeapons.gd**: Damage calculation formulas
- **BackgroundManager**: Parallax scrolling background
- **ResourceUI**: Resource display at top-left
- **ShipDatabase**: Ship data loading from CSV

### New Systems for Combat_3
- **CombatGridManager**: 20×25 grid with occupancy tracking
- **CombatMovementSystem**: Forward movement and overtaking
- **CombatCameraController**: Cinematic zooms and pans
- **Enemy wave spawning**: Load from enemy_waves.csv
- **Turn-based state machine**: Pre-tactical → Tactical → Pre-combat → Combat → Cleanup

### Modified Systems
- **Ship positioning**: Grid-based instead of lane-based
- **Camera system**: Larger battlefield, more zoom levels
- **Combat flow**: Distinct phases with timer
- **Deployment**: Movement speed determines column

---

## Testing Plan

### Unit Tests
1. **Grid system**: Occupancy tracking, coordinate conversion
2. **Movement validation**: Valid/invalid moves, Manhattan distance
3. **Overtaking logic**: Fast ship passing slow ship
4. **Wave spawning**: Weighted row selection, collision avoidance
5. **Ability queue**: FIFO order, correct target resolution

### Integration Tests
1. **Full turn cycle**: Pre-tactical → Tactical → Pre-combat → Combat → Cleanup
2. **Card playing**: Instant effects vs queued abilities
3. **Combat phase**: Attack, movement, ability casting
4. **Combo triggers**: Status effect + trigger card
5. **Victory/defeat**: Conditions trigger correctly

### Balance Testing
1. **Movement speeds**: Do fast ships feel significantly faster?
2. **Combat duration**: Is 20 seconds the right length?
3. **Card draw rate**: Do players run out of cards? Have too many?
4. **Enemy difficulty**: Wave compositions feel fair?
5. **Combo frequency**: Are combos rare enough to feel special?

### Performance Testing
1. **Grid updates**: 500 grid queries per frame acceptable?
2. **Projectile count**: Can handle 50+ projectiles simultaneously?
3. **Camera transitions**: Smooth on lower-end hardware?
4. **Status effect ticks**: Performance with 20+ units with burn/freeze?

---

## Summary

Combat_3 represents a significant evolution of the combat system:
- **Larger battlefield** (20×25 grid vs 3 lanes)
- **Continuous movement** (ships advance when not attacking)
- **Distinct phases** (tactical planning → cinematic abilities → 20s combat)
- **Strategic depth** (positioning, movement speed, overtaking)
- **Cinematic presentation** (camera zooms, slow-motion, combo notifications)

This system maintains the card-based tactical gameplay of Combat_2 while adding:
- More spatial tactics (20 rows instead of 3)
- Time pressure (20-second combat windows)
- Movement strategy (deployment columns, overtaking)
- Turn-based structure (clear phases, wave progression)

The modular architecture allows reusing many Combat_2 systems (cards, projectiles, status effects, combos) while replacing the core combat loop with a grid-based, phase-driven design.

---

*This plan is ready for implementation. Next step: Create Combat_3.tscn and begin Phase 1 (Core Grid and Deployment).*

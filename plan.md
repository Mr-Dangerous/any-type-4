# Auto Battler Card Game - Development Plan

## Project Overview
A topdown auto battler card game combining elements from Slay the Spire and FTL. Players navigate a starmap, manage their fleet in a hangar, and engage in lane-based combat against waves of enemies. Built in Godot with CSV-driven data.

## Important Implementation Notes

### Current Combat System
- **Active Scene**: `Combat_2.tscn` with `Combat_2.gd` script
- **Deprecated**: `Combat.tscn` and `Combat.gd` are no longer used
- **Hangar**: The deckbuilder system will eventually become the hangar interface

## Game Design Specifications

### Combat System
- **Lanes**: 3 horizontal combat lanes with visual rectangles
- **Lane Visuals**:
  - 128px tall semi-transparent blue rectangles
  - Positioned between mothership and enemy spawner
  - Clickable for zoom functionality
- **Mothership**:
  - Positioned on the left side of the screen
  - Ships deploy from mothership center and fly to lane positions
  - Starting point for all ship deployment animations
- **Enemy Spawner**:
  - Positioned on the right side of the screen
  - Enemy spawn point (not yet implemented)
- **Player Ships**:
  - Deploy with smooth acceleration/deceleration animations (BUG: Needs reorking)
  - Stagger horizontally within lanes (40px spacing between ships)
  - Stagger vertically within lanes (alternating top/middle/bottom positions)
  - Ships face direction of travel during deployment
  - Idle behavior: ships drift backward slowly (10px over 8s), then return to position
  - Ships rotate to face enemy spawner when idle
  - Ship sizes: Interceptor (20px), Fighter (36px), Frigate (48px)
- **Combat Flow**:
  - Ship selection via deployment panel INTERMEDIARY STEP FOR NOW
  - Click lane to deploy selected ship
  - Ships animate from mothership to lane position
  - Lane zoom: click lane rectangle to zoom in (1.5x), click again to zoom out
  - Background: Space2.png tiled background with stones1.png parallax scrolling

### Resources
Resources will be displayed in a UI.
TODO: The  UI has two additionlal resources, needs a proper window, and also needs to fit in the window in the case of overflow.
- **Metal**: Generated in combat/mining, used for building ships and repairs 
- **Fuel**: Generated via salvage/mining, required for jumps, can run out (forces waiting for aliens)
- **Crystals**: Currency for traders and advanced systems
- **Pilots**: Living resource, recruited through events/rewards


### Progression Structure
- **Acts**: 3 acts total
- **Exploration**: Column style explorer
- **Pressure Mechanic**: Alien swarm pursues the player (similar to FTL's rebel fleet)

---

## Phase 1: Project Foundation & Core Systems

### 1.1 Project Setup
- [x] Initialize Godot project structure
- [x] Create folder organization:
  - `/scenes/` - All game scenes
  - `/scripts/` - GDScript files
  - `/assets/` - Sprites, backgrounds, effects, UI
  - `/card_database/` - CSV files
- [x] Set up project settings (resolution, window mode, etc.)
- [x] Create autoload singletons:
  - `GameData.gd` - Overall game state and resource management ✓
  - `ShipDatabase.gd` - Ship data loading from CSV ✓
- [ ] Future singletons:
  - `DataManager.gd` - Centralized CSV loading (if needed)
  - `EventBus.gd` - Signal hub for inter-scene communication

### 1.2 Data Management System
- [x] Create CSV structure for:
  - `any_type_4_card_database.csv` - Card definitions
  - `starting_deck.csv` - Starting deck composition
  - `enemies.csv` - Enemy types and stats (deprecated, see ship_database.csv)
  - `star_names.csv` - Procedural star name generation
  - `ship_database.csv` - Ship and enemy data (all stats, sprites, properties) ✓
- [x] Build CSV parser in Combat.gd (basic implementation)
- [x] Implement ShipDatabase singleton with CSV loading
  - Parses ship_database.csv on startup
  - Provides get_ship_data(), get_ships_by_faction(), etc.
  - Supports dynamic ship loading without code changes
- [ ] Centralize other CSV loading in DataManager singleton
- [ ] Create data structures/classes for card and event types
- [x] Implement data validation for ship database

---

## Phase 2: Combat Scene (Combat_2.tscn)

### 2.1 Combat Arena Setup ✓ COMPLETED
- [x] Create `Combat_2.tscn` scene
- [x] Implement 3-lane system with visual rectangles
  - Semi-transparent blue rectangles (128px tall)
  - Positioned between mothership and enemy spawner
  - Clickable for zoom functionality
- [x] Create mothership at left defensive position
  - Ships spawn from mothership center
- [x] Create enemy spawner placeholder at right position
- [x] Set up camera controls
  - Camera2D with smooth zoom interpolation
  - Lane zoom: 1.5x zoom when clicking lane
  - ESC to return to tactical view
- [x] Implement parallax background system
  - Space2.png: Static tiled background (z-index: -100)
  - stones1.png: Scrolling parallax layer (z-index: -50)
  - Configurable scroll direction and speed
  - Seamless looping
- [x] Design combat UI layout:
  - Deploy ship button (top-right)
  - Ship selection panel with icons
  - Return button (appears when zoomed)
  - Lane labels within rectangles
  - Tactical view title

### 2.2 Ship Deployment System ✓ COMPLETED
- [x] Create ship deployment UI
  - Modal ship selection panel
  - Three ship types: Interceptor, Fighter, Frigate
  - Ship icons sized appropriately (20px, 36px, 48px)
  - Cancel button to close panel
- [x] Implement lane click detection
  - Get lane at mouse position
  - Deploy ship when lane clicked with ship selected
  - Zoom to lane when clicked without ship selected
- [x] Create ship sprite spawning
  - Ships spawn at mothership center
  - TextureRect with proper sizing
  - Sprite rotation with pivot offset
- [x] Implement deployment animations
  - Start position: mothership center (regardless of target lane)
  - Smooth acceleration phase (40% of duration)
  - Smooth braking phase (60% of duration)
  - Rotation to face travel direction
  - Speed varies by ship type:
    - Interceptor: 2.0s (fast)
    - Fighter: 3.0s (medium)
    - Frigate: 5.0s (slow)

### 2.3 Ship Positioning & Staggering ✓ COMPLETED
- [x] Implement horizontal staggering
  - Ships positioned left-to-right within lane
  - 40px spacing between ships
  - Starting offset: 20px from lane edge
- [x] Implement vertical staggering
  - Alternating pattern: top (-30px), middle (0px), bottom (+30px)
  - Additional random offset (±30% of ship size)
  - Prevents sprite overlap
- [x] Position ships within 128px lane rectangles
  - Ships centered vertically in lanes
  - Health bars displayed below ships

### 2.4 Ship Idle Behavior ✓ COMPLETED
- [x] Ships rotate to face enemy after deployment
  - 1.5s smooth rotation to face enemy spawner
  - Calculate angle to enemy position
- [x] Implement drift behavior
  - 3s delay before first drift
  - Slow backward drift: 10px over 8 seconds
  - Sine easing for smooth movement
- [x] Implement return behavior
  - 0.5s pause after drift
  - Return to original position over 2 seconds
  - Subtle rotation wobble (±3°) during return
  - Continuous cycle while in lane

### 2.5 Lane Zoom System ✓ COMPLETED
- [x] Lane click detection for zoom
  - Click lane rectangle to zoom
  - Only zooms if no ship is selected for deployment
- [x] Camera zoom animation
  - Zoom to 1.5x
  - Center camera on lane
  - Smooth cubic interpolation
  - 0.5s animation duration
- [x] Return to tactical view
  - Click lane again to zoom out
  - Press ESC to return
  - Return button (close icon) in top-right
  - Smooth zoom out animation
- [x] UI state management
  - Hide deploy button when zoomed
  - Show return button when zoomed
  - Return button in CanvasLayer (unaffected by camera)

### 2.6 Visual Polish ✓ COMPLETED
- [x] Background system
  - Space2.png tiled across screen
  - stones1.png parallax scrolling (70% opacity)
  - Scroll direction: right (configurable)
  - Scroll speed: 10 px/s (configurable)
  - Seamless infinite scrolling
- [x] Lane visual design
  - Semi-transparent blue fill
  - Bright blue borders (3px)
  - "FRONT LINE" and "BACK LINE" labels
  - Labels positioned inside rectangles
- [x] Ship sprite integration
  - Ship textures from assets/Ships/illum_default/
  - Proper sprite sizing per ship class
  - Rotation with centered pivot

### 2.7 Ship Data & Stats ✓ COMPLETED
- [x] CSV-driven ship database system
  - `ship_database.csv` contains all ship and enemy data
  - 19 columns including: ship_id, display_name, faction, sprite_path, projectile_sprite
  - Stats: size, deploy_speed, armor, shield, reinforced_armor, evasion, accuracy
  - Combat: attack_speed, num_attacks, amplitude, frequency
  - Metadata: size_class, description, enabled flag
- [x] ShipDatabase singleton (autoload)
  - Loads CSV on startup
  - get_ship_data(ship_id) - Get specific ship
  - get_ships_by_faction(faction) - Get player/enemy ships
  - get_enabled_ships() - Filter by enabled flag
- [x] Ship size definitions loaded from database
  - Interceptor: 20px, Fighter: 36px, Frigate: 48px
  - Mook: 20px, Elite: 36px
- [x] Ship deployment speed from database
  - Different animation durations per ship type
  - Interceptor: 2.0s, Fighter: 3.0s, Frigate: 5.0s
- [x] Ship tracking in lanes
  - Dictionary storing ship data per lane
  - Track: type, container, sprite, size, position, stats
  - Track idle state and behavior
  - Track current armor and shields
- [x] Ship combat stats loaded from database
  - Armor, shield, reinforced_armor
  - Evasion, accuracy
  - Attack speed, num_attacks
  - Amplitude, frequency
- [ ] Ship abilities (not yet implemented)

### 2.8 Combat Targeting System ✓ COMPLETED
- [x] Click-to-select combat system
  - Click any unit (player ship or enemy) to select as attacker
  - Click opposite-faction unit to select as target
  - Visual feedback: yellow tint for player attackers, red tint for enemy attackers
  - Click same unit again to deselect
- [x] Laser projectile system
  - Projectiles fire from attacker to target
  - Number of projectiles based on ship's num_attacks stat
  - Small delay between multiple projectiles (0.05s)
  - Laser sprites scale to 6px height
  - Flight duration: 0.2s
- [x] Attack rotation
  - Attackers smoothly rotate to face target (0.3s)
  - Rotation calculated from center-to-center positions
- [x] Continuous attack system
  - Attack timer created on first shot
  - Fires repeatedly based on attack_speed stat
  - Timer interval = 1.0 / attack_speed
  - Timer automatically stops when attacker/target deselected
- [x] Hit effects
  - White flash on target when hit (0.05s flash + 0.1s return)
  - Future: damage calculation and health reduction
- [x] Bidirectional combat
  - Player ships can attack enemies
  - Enemies can attack player ships
  - Same targeting system for both

### 2.9 Resource UI System ✓ COMPLETED
- [x] ResourceUI.gd script
  - Extends Control, attached to UI CanvasLayer
  - Positioned at top-left (20, 20)
  - Updates from GameData singleton
- [x] Six resource displays
  - Row 1: Metal, Crystals, Fuel
  - Row 2: Pilots, Metal Large, Crystal Large
  - Each with icon and label
- [x] Resource icons
  - 32x32 TextureRect for each resource
  - Icons loaded from assets/Icons/
  - Custom icons for each resource type
- [x] Background panel
  - Button sprite background (s_button_1.png)
  - Auto-sizes to content
  - Padding: 40px horizontal, 20px vertical
- [x] Live resource tracking
  - update_resources() function
  - Reads from GameData.get_resource()
  - Can be called to refresh display

### 2.10 Enemy Deployment System ✓ COMPLETED
- [x] Enemy deployment UI (for testing)
  - "DEPLOY ENEMY" button at top-right
  - Enemy selection panel (similar to ship panel)
  - Enemy buttons with sprites and names
- [x] Dynamic enemy loading
  - Enemies loaded from ShipDatabase.get_ships_by_faction("enemy")
  - Enemy buttons created dynamically from CSV data
  - Currently includes: Mook, Elite
- [x] Enemy deployment to lanes
  - deploy_enemy_to_lane() function
  - Enemies positioned on right side near spawner
  - Enemies face left (toward player)
  - 60px horizontal spacing between enemies
  - Vertical staggering (same as player ships)
- [x] Enemy data integration
  - Enemy sprites, sizes, stats all from database
  - Enemy combat stats tracked in lane units
  - Enemies can be targeted by player ships

### 2.11 NOT YET IMPLEMENTED
The following systems from the original plan are not yet implemented:

- [ ] Damage calculation and health reduction
- [ ] Health bar display for ships
- [ ] Ship destruction when health reaches 0
- [ ] Card system (hand, draw, discard)
- [ ] Enemy wave system and AI movement
- [ ] Pilot system
- [ ] Turret system
- [ ] Powerup system
- [ ] Drone system
- [ ] Victory/defeat conditions
- [ ] Rewards system
- [ ] VFX and particle effects beyond basic hit flash
- [ ] Combo system

---

## Phase 3: Starmap Scene

### 3.1 Basic Starmap ✓ COMPLETED
- [x] Create `StarMap.tscn` scene
- [x] Implement basic star system nodes
  - 10 star systems as clickable buttons
  - Node positions in grid layout
  - Connection lines between nodes
- [x] Create node navigation
  - Click node to travel
  - Scene transition to Combat
  - Return to StarMap after combat
- [x] Procedural star names
  - Load from star_names.csv
  - Random name generation for each node
- [ ] Implement procedural map generation
- [ ] Create node types (combat, event, shop, rest, boss)
- [ ] Add path validation
- [ ] Implement alien swarm pursuit mechanic

---

## Phase 4: Hangar Scene (Future Deckbuilder)

### 4.1 Basic Deck Builder ✓ COMPLETED
- [x] Create `DeckBuilder.tscn` scene
- [x] Display current deck cards
  - Scrolling container
  - Card previews with stats
  - Card count display
- [x] Deck statistics
  - Total card count
  - Cards by type
- [x] Return to combat button
- [ ] Convert to full hangar interface with:
  - Fleet display area
  - Pilot roster panel
  - Resources display
  - Upgrades/Relics panel
  - Technology/Blueprints panel

**Note**: The current DeckBuilder will be expanded into a full Hangar management interface in future development.

---

## Phase 5: Menus & UI Flow

### 5.1 NOT YET IMPLEMENTED
- [ ] Title screen
- [ ] Main menu
- [ ] Settings menu
- [ ] Pause menu
- [ ] Scene transitions

---

## Technical Implementation Details

### Current Architecture

#### Active Scenes
1. **Combat_2.tscn** (`Combat_2.gd`)
   - Main combat scene with lane-based tactical view
   - 3 horizontal lanes with visual rectangles
   - Ship deployment and idle behavior
   - Camera zoom system
   - Parallax background system

2. **StarMap.tscn** (`StarMap.gd`)
   - Basic node-based navigation
   - Scene transitions to/from combat
   - Procedural star name generation

3. **DeckBuilder.tscn** (`DeckBuilder.gd`)
   - Basic deck viewing
   - Will become Hangar in future

#### Deprecated Scenes
- **Combat.tscn** / **Combat.gd** - Old combat system, no longer used

#### Key Constants (Combat_2.gd)
```gdscript
# Lane positioning
NUM_LANES = 3
LANE_Y_START = 200.0
LANE_SPACING = 150.0
LANE_HEIGHT = 128.0

# Position constants
MOTHERSHIP_X = 100.0
ENEMY_SPAWN_X = 1000.0
SHIP_DEPLOY_X_START = 280.0
SHIP_SPACING = 40.0

# Ship sizes
SIZE_TINY = 20px (Interceptor)
SIZE_MEDIUM = 36px (Fighter)
SIZE_LARGE = 48px (Frigate)

# Deployment animation speeds
Interceptor: 2.0s
Fighter: 3.0s
Frigate: 5.0s

# Idle behavior
DRIFT_DISTANCE = 10.0
DRIFT_DURATION = 8.0s
DRIFT_DELAY = 3.0s
RETURN_DURATION = 2.0s
```

#### Background System
```gdscript
# Background layers
Space2.png - Static tiled (z-index: -100)
stones1.png - Scrolling parallax (z-index: -50)

# Background variables
bg_scroll_direction: Vector2(1, 0) - Right
bg_scroll_speed: 10.0 px/s
bg_tile_size: 1.0x scale
```

### Scene Flow
```
MainMenu (not implemented)
    ↓
StarMap → Combat_2 ⟷ DeckBuilder (future: Hangar)
    ↓
StarMap → ...
```

---

## Development Priorities

### Completed ✓
1. Basic scene structure (Combat_2, StarMap, DeckBuilder)
2. Lane system with visual rectangles
3. Ship deployment with animations
4. Ship positioning and staggering
5. Idle behavior system
6. Lane zoom functionality
7. Parallax background system
8. CSV-driven ship database system
9. ShipDatabase singleton with dynamic loading
10. Combat targeting system (click-to-attack)
11. Laser projectile firing with continuous attacks
12. Resource UI display (6 resource types)
13. Enemy deployment system (for testing)
14. Bidirectional combat (player↔enemy)

### Immediate Next Steps
1. **Damage & Health System**
   - Implement damage calculation when lasers hit
   - Apply accuracy vs evasion mechanics
   - Reduce shield first, then armor
   - Account for reinforced_armor stat
   - Display health bars above ships
   - Ship destruction when health reaches 0

2. **Enemy AI & Wave System**
   - Enemy auto-targeting (select nearest player ship)
   - Enemy wave spawning from right side
   - Enemy movement toward player ships
   - Wave preview and timing
   - Multiple enemy types per wave

3. **Card System Integration**
   - Implement card hand UI
   - Draw 3 cards per turn
   - Card play mechanics
   - Connect cards to ship deployment
   - Card effects and abilities

4. **Basic Game Loop**
   - Turn-based structure
   - Victory conditions (defeat all enemies)
   - Defeat conditions (mothership destroyed)
   - Combat rewards (resources)
   - Resource spending for ship deployment

### Medium-Term Goals
1. Pilot system (assignment, traits, injury)
2. Turret system
3. Ability system (energy generation, auto-cast)
4. Enemy waves and previews
5. Expand starmap with node types
6. Convert DeckBuilder to Hangar

### Long-Term Goals
1. Complete card set
2. Technology/blueprints
3. Upgrades/relics
4. Drone system
5. Combo system
6. Meta-progression
7. Polish and VFX

---

## Design Decisions Made

✓ **Combat System**: Lane-based tactical view with visual rectangles
✓ **Ship Deployment**: Animated launches from mothership with physics-based movement
✓ **Ship Staggering**: Horizontal and vertical offsets to prevent overlap
✓ **Idle Behavior**: Ships drift and return, rotate to face enemies
✓ **Camera**: Zoom-to-lane functionality for tactical focus
✓ **Backgrounds**: Parallax scrolling with configurable direction/speed
✓ **Ship Sizes**: 20px (Interceptor), 36px (Fighter), 48px (Frigate)
✓ **Lane Count**: 3 lanes (128px tall rectangles)
✓ **Deployment Speed**: Varies by ship class (2s to 5s)
✓ **Data Management**: CSV-driven ship database with dynamic loading
✓ **Combat Targeting**: Click-to-select attacker, click-to-target system
✓ **Projectiles**: Laser sprites, attack speed-based firing, multi-shot support
✓ **Resources**: 6 types tracked (metal, crystals, fuel, pilots, metal_large, crystal_large)
✓ **Enemy Data**: Enemies stored in same ship_database.csv as player ships

---

## Questions Still to Consider

### Answered ✓
- ✓ How should ships target enemies in lanes? → Click-to-select targeting system
- ✓ How are ship stats stored? → CSV database with ShipDatabase singleton
- ✓ How do resources display? → ResourceUI at top-left with icons

### Still Open
- How exactly does damage calculation work? (accuracy vs evasion, reinforced armor)
- When do ships generate energy vs auto-attack?
- How do cards interact with deployed ships?
- What happens when a lane is full?
- Should ships be able to move between lanes?
- How do enemy waves spawn and advance? (from right? waves? timing?)
- Should enemies auto-target or use AI behavior?
- What triggers the end of combat?
- How does the pilot system integrate with ship deployment?
- Should we have a turn system or real-time combat?
- How do ship abilities work? (energy cost, cooldowns, targeting)

---

*This plan is a living document and should be updated as development progresses and requirements change.*

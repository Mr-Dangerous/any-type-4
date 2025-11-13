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
- **Combat Setup**:
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
  - `SeedManager.gd` - Deterministic RNG for procedural generation ✓
  - `DataManager.gd` - Centralized CSV loading ✓
  - `GameData.gd` - Overall game state and resource management ✓
  - `CombatConstants.gd` - Combat constants and resource preloads ✓
  - `CardHandManager.gd` - Card system management ✓
- [ ] Future singletons:
  - `EventBus.gd` - Signal hub for inter-scene communication

### 1.2 Data Management System
- [x] Create CSV structure for:
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

### 2.11 Damage & Health System ✓ COMPLETED
- [x] Damage calculation system
  - Hit chance: 1.0 - (target_evasion * 0.01)
  - Critical hit chance: 1.0 - (attacker_accuracy * 0.01)
  - Reinforced armor damage reduction
  - Critical hits deal 2x damage
  - Minimum 1 damage on hit
- [x] Health bar display
  - 3-tier health bars above ships
  - Shield bar (cyan, top row)
  - Armor bar (red, middle row)
  - Energy bar (purple, bottom row)
  - Max 32px width, scales with ship health
- [x] Damage application
  - Damage shields first, overflow to armor
  - Ships destroyed when total health reaches 0
  - Hit flash visual feedback (white flash)
  - Health bars update in real-time
- [x] Ship destruction system
  - Ships removed from lane when destroyed
  - Container freed from scene tree
  - Attack timers cleaned up
  - Auto-targets reassigned if needed

### 2.12 Auto-Combat System ✓ COMPLETED
- [x] Auto-targeting system
  - Assign random targets to all ships
  - Target switching every 3 seconds
  - Targets restricted to opposite faction
  - Lane-restricted targeting when zoomed
- [x] Auto-attack cycle
  - Continuous attacks based on attack_speed
  - Auto-rotation to face current target
  - Energy generation after each attack (2-4 random)
  - Ability auto-cast when energy full
- [x] Combat state management
  - combat_paused flag controls all combat
  - Start/stop auto-combat via button
  - All ships attack simultaneously
  - Clean timer management on stop

### 2.13 Turn-Based Combat Structure ✓ COMPLETED
- [x] Turn mode system
  - "START AUTO-COMBAT" button initiates turn mode
  - Turn progression button (bottom-right, UI layer)
  - Four phases: tactical, lane_0, lane_1, lane_2
  - Sequential lane combat with player control
- [x] Turn progression flow
  - Tactical phase: "Proceed to Lane 1" button
  - Zoom to lane when proceeding
  - "Start Combat" button appears when ready
  - 5-second combat timer per lane
  - Auto-transition to next lane after timer
  - Return to tactical after all lanes complete
- [x] Turn mode restrictions
  - Manual lane zoom disabled in turn mode
  - Return button hidden in turn mode
  - Lane-restricted targeting enforced
  - Combat only active during lane phase
- [x] UI integration
  - Turn progression button on UI layer (zoom-safe)
  - Zoom timer label on UI layer
  - Button text updates based on phase
  - Button hides during active combat

### 2.14 Energy & Ability System ✓ COMPLETED
- [x] Energy generation
  - Ships gain 2-4 energy per attack
  - Energy tracked per ship (current_energy)
  - Max energy defined in ship stats
  - Energy bar displays current/max
- [x] Ability casting
  - Auto-cast when energy reaches max
  - Energy resets to 0 after cast
  - Ability name and description from database
  - Console logging for ability casts
- [ ] Ability effects (not yet implemented - functions are placeholders)

### 2.15 Background System Refactoring ✓ COMPLETED
- [x] Separate BackgroundManager module
  - Extracted all background logic from Combat_2.gd
  - BackgroundManager.gd handles tiled static background and parallax layers
  - Reusable BackgroundManager.tscn scene
  - Export variables for customization (scroll speed, direction, opacity)
  - Background tiles larger than window size for full coverage
- [x] Background system features
  - Static space background (Space2.png tiled at z:-100)
  - Parallax scrolling layer (stones1.png at z:-50)
  - Seamless infinite scrolling with wrapping
  - Configurable scroll direction and speed
  - Helper functions for runtime adjustments

### 2.16 Targeting System Enhancements ✓ COMPLETED
- [x] Beta targeting mode (row-focused combat)
  - targeting_function_beta() with strict row-based priority
  - Priority: Same row → Turrets → Mothership → Any lane
  - More focused than alpha mode (skips adjacent rows)
  - Creates tighter row-vs-row combat formations
- [x] Debug UI integration
  - Beta buttons added for player and enemy targeting
  - Three targeting modes: alpha, beta, random
  - Status label automatically displays current modes
  - Targeting mode changes reassign all unit targets
- [x] Targeting system architecture
  - assign_random_target() dispatcher supports all modes
  - Helper functions shared across modes (find_closest_in_row, etc.)
  - Mode selection per faction (player_targeting_mode, enemy_targeting_mode)

### 2.17 Projectile System Improvements ✓ COMPLETED
- [x] Missed projectiles continue traveling
  - Projectiles that miss don't destroy immediately
  - continue_laser_off_screen() function handles misses
  - Projectiles travel until completely off-screen
  - Automatic cleanup after off-screen (~1.3s additional travel)
  - Creates realistic combat feedback for misses
- [x] Dynamic projectile loading from database
  - projectile_sprite and projectile_size from ship_database.csv
  - Each ship/turret can have unique projectile appearance
  - Projectile size varies by unit type (3-50 pixels)
  - Examples: Mook (3px), Fighter (8px), Interceptor (40px), Turrets (30-50px)
  - Default fallbacks if CSV data missing
- [x] Attack speed bug fix
  - Fixed turret attack timing to match ships
  - Correct formula: attack_interval = 1.0 / attack_speed
  - attack_speed now consistent across all unit types
  - attack_speed = 1.0 → 1 attack/second
  - attack_speed = 0.5 → 0.5 attacks/second (2s interval)
- [x] Consolidated projectile system (CombatProjectileManager.gd)
  - Separate projectile manager for cleaner code organization
  - launch_projectile() for simultaneous non-blocking projectile firing
  - Projectiles 30% slower (0.26s flight time instead of 0.2s)
  - Post-combat cleanup phase (1 second for projectiles to resolve)
  - No new projectiles/abilities during cleanup phase

### 2.18 Grid-Based Movement System ✓ COMPLETED
- [x] Grid cell system
  - 5 rows × 16 columns per lane
  - 32px cell size
  - Player deployment zone: columns 0-3
  - Enemy deployment zone: columns 12-15
  - Grid occupancy tracking per lane
- [x] Ship movement mechanics
  - Drag-and-drop ship repositioning
  - Valid move detection (adjacent cells only)
  - Visual feedback (green/red cell overlays)
  - Grid cell occupation/release
  - Smooth animation to new position
  - has_moved_this_turn flag prevents multiple moves

### 2.19 Turret System ✓ COMPLETED
- [x] Turret placement and configuration
  - 15 turrets total
  - Positioned at mothership + offsets
  - Each turret targets specific lanes
  - 40px turret size, health bars above
- [x] Turret combat
  - Auto-targeting enemies in target lanes
  - Attack timers based on turret attack_speed
  - Target switching every 3 seconds
  - Turrets can be targeted and destroyed by enemies
  - Turret data loaded from ship_database.csv
- [x] Lane-specific turret activation
  - Turrets activate during lane combat phase
  - Only attack enemies in active lane
  - Return to multi-lane targeting after combat

### 2.20 Card System ✓ CORE COMPLETE, EXPANDING
- [x] Card database and data loading
  - card_database.csv with 10+ cards (Strike, Shield, Energy Alpha, Energy Beta, Turret Blast, Missile Lock, Incendiary Rounds, Cryo Rounds, **Incinerator Cannon**)
  - starting_deck.csv with starting deck composition
  - DataManager loads card data on startup
  - ability_queue column determines if card queues or executes immediately
- [x] Card visual system
  - Card.tscn with NinePatchRect frame
  - Card artwork from sprite_path in CSV
  - Card name, description display
  - Hand UI at bottom of screen (CanvasLayer z:500)
- [x] Card hand management
  - CardHandManager singleton for deck/hand/discard
  - Draw pile, hand, discard pile tracking
  - Shuffle deck functionality
  - Draw card button (visible in lane view)
- [x] Card drag-and-drop
  - Drag cards to play (offset below cursor)
  - Semi-transparent during drag
  - Return to hand on invalid drop
  - Play animation to target
- [x] Card targeting system
  - Target detection by faction (friendly_ship, friendly_turret, enemy_ship)
  - Red glow on valid targets (300px detection radius)
  - Grid-based and distance-based targeting
  - Target validation before card play
- [x] Card effects implementation
  - CardEffects.gd with static effect functions
  - Strike: +50% attack speed for one turn
  - Shield: +30 shields to target ship (overshield at 1/3 rate)
  - Energy Alpha: +100 energy to target ship
  - Energy Beta: +75 energy to target ship, AoE(1) with 50% falloff
  - Turret Blast: Activate turret ability
  - Missile Lock: 50 explosive damage (AoE 1), queued ability
  - **Incinerator Cannon**: 20 fire damage + 3 burn stacks, queued ability
  - Incendiary Rounds: Convert attacks to fire damage, 25% burn chance
  - Cryo Rounds: Convert attacks to ice damage, 25% freeze chance (lasts until lane cleanup)
  - Visual effect notifications (floating text)
- [x] **Ability Queue System** ✓ NEW
  - ability_queue CSV column marks cards for queuing vs instant execution
  - Ships have ability_stack arrays for storing queued abilities
  - Abilities queue during precombat phase (when cards are played)
  - All queued abilities execute at combat start in sequence
  - 0.25 second delay between ability executions
  - Attack timers paused during ability execution phase
  - Fizzle handling for invalid targets
- [x] **Cinematic Ability System** ✓ NEW
  - Camera zooms to casting ship (1.3x zoom, 0.3s transition)
  - Card popup displayed above ship during cast
  - Projectiles spawn in slow-motion (move 10% distance over 1.2s)
  - Total 1.5 seconds per ability with cinematic presentation
  - Camera resets to lane view after all abilities (0.4s transition)
  - ALL stored projectiles release at full speed simultaneously
  - Projectiles fly to targets at normal speed (0.3s)
  - Full damage/effect application on impact
  - [!] BUG: Ships not in queue auto-fire during ability cast phase (TODO: fix tomorrow)
- [x] Card system integration with combat
  - Cards visible in both precombat and combat phases
  - Draw cards anytime during lane view
  - Cards only playable during precombat phase
  - Cards removed from hand after successful play
  - Cards persist across lanes
- [x] Temporary card effects
  - Card effects persist for entire lane combat
  - Cleared automatically during post-combat cleanup phase
  - Visual notification when effects expire
- [x] Ability casting on energy max
  - Ships cast abilities when energy reaches max
  - Ability casting blocked during combat_paused
  - Energy Alpha can trigger instant ability cast in combat
- [ ] TODO:
  - Fix: Ships auto-firing during ability cast phase (should wait)
  - Need more card types and effects (Acid Rounds, Gravity Rounds, etc.)
  - No card cost system yet
  - No deck building between battles
  - Elemental combo cards not yet implemented

### 2.21 Status Effect System ✓ COMPLETED
- [x] Status effect manager (CombatStatusEffectManager.gd)
  - Centralized status effect processing
  - Lane-aware effect timing (only active during lane combat)
  - Support for DOT effects (burn) and stat modifiers (freeze)
  - Visual indicators above ships (icons with stack counts)
- [x] Burn status effect
  - 5 damage per tick per stack
  - 1-second tick interval
  - 10-second total duration
  - Damage numbers show fire icon
  - Applies to shields first, then armor
- [x] Freeze status effect
  - 25% attack speed reduction per stack (multiplicative: 0.75^stacks)
  - 25% evasion reduction per stack (multiplicative: 0.75^stacks)
  - 2-second duration per stack
  - Each stack tracked individually with separate timer
  - Stacks expire one at a time
  - Visual indicator shows total stack count (❄️)
- [x] Status effect application
  - Incendiary Rounds: 25% chance to apply 1 burn stack on hit
  - Cryo Rounds: 25% chance to apply 1 freeze stack on hit
  - Status effects check in projectile hit handlers
  - Only apply on successful hits (not on miss)
- [x] Status effect visuals
  - HBoxContainer above health bars
  - Fire icon (🔥) for burn with stack count
  - Ice icon (❄️) for freeze with stack count
  - Color-coded text (orange for burn, cyan for freeze)
  - Floating damage numbers for burn ticks
- [x] Status effect integration
  - Freeze modifiers applied to attack speed calculations (4 locations)
  - Freeze modifiers applied to evasion in hit chance calculation
  - Burn damage ticks during active lane combat
  - Effects update in real-time during combat

### 2.22 Ship Inspector Tooltip ✓ COMPLETED
- [x] Hover tooltip system
  - Mouse enter/exit detection on ship containers
  - Tooltip follows mouse position (offset to avoid cursor)
  - Smooth pop-in animation (scale + fade)
  - Auto-hides when mouse leaves ship
- [x] Ship stats display
  - Ship name/type at top
  - Current/max values for shield, armor, energy
  - Overshield display (+value)
  - Combat stats: damage, attack speed, num attacks, accuracy, evasion, reinforced armor
- [x] Temporary stat display
  - RichTextLabel with BBCode support
  - Base stats in white
  - Modified stats in red (when reduced)
  - Format: "Attack Speed: 2.0 (1.5)" where 1.5 is red
  - Format: "Evasion: 20% (15%)" where 15% is red
  - Shows freeze stack effects in real-time
- [x] Tooltip positioning
  - Initially appears at mouse + offset
  - Clamped to screen bounds
  - Repositions to avoid going off-screen
  - Consistent size (200px width, auto height)

### 2.23 Enemy Pathfinding Alpha ✓ COMPLETED
- [x] Enemy movement system (enemy_pathfinding_alpha)
  - Implemented in Combat_2.gd (line 645-698)
  - Triggers at start of each lane's precombat phase
  - Enemies move toward player (left/decreasing columns)
  - Movement distance: up to movement_speed cells (default 2)
  - Straight-line movement only (same row)
- [x] Collision detection
  - Checks each column from current position toward target
  - Stops movement if player ship encountered
  - Cannot path around obstacles (alpha version)
  - Uses existing move_ship_to_cell() for animation
- [x] Integration with lane transitions
  - Called in proceed_to_lane_transition() after camera zoom
  - Executes before "Start Combat" button appears
  - Happens before player can play cards
  - Movement flags reset for each lane
- [x] Movement animation
  - 0.5 second tween with cubic easing
  - Ships slide smoothly to new grid position
  - Grid cells properly updated (free old, occupy new)
  - Visual feedback with modulate restoration
- [ ] TODO (Future Improvements):
  - Pathfinding around obstacles (beta version)
  - Diagonal movement options
  - Different movement patterns per enemy type
  - Movement cost/action point system

### 2.24 NOT YET IMPLEMENTED
The following systems from the original plan are not yet implemented:

- [ ] Enemy wave system and spawning
- [ ] Pilot system
- [ ] Powerup system
- [ ] Drone system
- [ ] Victory/defeat conditions
- [ ] Rewards system
- [ ] VFX and particle effects beyond basic hit flash and off-screen projectiles
- [ ] Combo system
- [ ] Expanded card system (more cards, costs, deck building)

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
    ## TODO need to fix background scaling.

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

#### Seed Manager System
The **SeedManager** singleton (`SeedManager.gd`) provides deterministic random number generation for reproducible gameplay experiences. It controls procedural generation and progression systems but **does not** control real-time combat RNG.

**Purpose**:
- Enable challenge runs with specific seeds
- Allow sharing of interesting map configurations
- Support deterministic testing and debugging
- Ensure same seed = same starmap/encounters/progression

**Implementation**:
- Autoload singleton with `RandomNumberGenerator` instance
- Single global seed controls all deterministic systems
- Auto-generates seed on startup (using system time)
- Supports manual seed input for challenge runs
- Seed persistence through `GameData.save_seed()`/`get_seed()`

**RNG Methods**:
```gdscript
SeedManager.initialize_seed(seed_value)  # Set specific seed
SeedManager.generate_new_seed()          # Generate random seed
SeedManager.randi()                       # Seeded random integer
SeedManager.randf()                       # Seeded random float
SeedManager.randi_range(from, to)        # Seeded range integer
SeedManager.randf_range(from, to)        # Seeded range float
SeedManager.shuffle_array(array)         # Seeded array shuffle
SeedManager.pick_random(array)           # Seeded array element
```

**Systems Using Seed Manager** (Deterministic):
1. **StarMap.gd** (10+ integration points):
   - Background star positions, sizes, colors
   - Node count per column
   - Node positions and star assignments
   - Encounter type selection (combat/treasure/mystery/trading/mining)
   - Star name selection
   - Exit node selection
   - Skip connection generation
   - Candidate shuffling for path generation
2. **CardHandManager.gd**:
   - Deck shuffling (starting deck and reshuffles)
3. **DataManager.gd**:
   - Random star name selection
4. **Future Systems** (when implemented):
   - Hangar encounter generation
   - Loot/reward tables
   - Event outcomes
   - Progression unlocks
   - Starting deck configuration (via progression system)

**Systems NOT Using Seed Manager** (Non-Deterministic Combat RNG):
- Critical hit rolls
- Hit/miss chance calculations
- Evasion checks
- Energy generation amounts (2-4 random per attack)
- Auto-target selection timing
- Combat floating point calculations
- Any real-time combat randomness

**Design Philosophy**:
The seed controls the "journey" (what encounters you face, what loot appears, map layout) but not the "battles" (hit chances, crits, combat outcomes). This ensures:
- Reproducible runs for challenge/speedrun communities
- Fair combat that depends on player skill/strategy, not RNG manipulation
- Different combat outcomes even with same seed (based on tactics/timing)

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
7. Parallax background system (refactored into BackgroundManager module)
8. CSV-driven ship database system
9. ShipDatabase singleton with dynamic loading
10. Combat targeting system (click-to-attack)
11. Laser projectile firing with continuous attacks
12. Resource UI display (6 resource types)
13. Enemy deployment system (for testing)
14. Bidirectional combat (player↔enemy)
15. **Damage & Health System** - Damage calculation, health bars, ship destruction
16. **Auto-Combat System** - Auto-targeting, target switching, continuous attacks
17. **Turn-Based Combat Structure** - Sequential lane combat, turn progression button
18. **Energy & Ability System** - Energy generation, ability auto-cast (effects not yet implemented)
19. **BackgroundManager Module** - Separate background system with parallax layers
20. **Beta Targeting Mode** - Row-focused combat targeting option
21. **Projectile Miss Behavior** - Missed projectiles continue off-screen before cleanup
22. **Dynamic Projectile System** - Projectile sprites and sizes loaded from CSV database
23. **Attack Speed Fix** - Corrected turret attack timing to match ship formula
24. **Grid-Based Movement** - Drag-and-drop ship repositioning with valid move detection
25. **Turret System** - 5 turrets with lane-specific targeting and combat integration
26. **Card System (Core Complete)** - Hand UI, draw mechanics, drag-and-drop targeting, 10+ card effects including elemental ammo types
27. **Seed Manager System** - Deterministic RNG for starmap, deck shuffling, and progression (combat RNG remains non-deterministic)
28. **Status Effect System** - Burn (DOT) and Freeze (stat modifier) effects with individual stack tracking
29. **Ship Inspector Tooltip** - Hover tooltips showing stats with real-time temporary stat modifiers in color
30. **Ability Queue System** - Cards can queue abilities on ships that execute at combat start with proper sequencing
31. **Cinematic Ability System** - Camera zoom, slow-motion projectiles, card popups, and full-speed release after queue
32. **Incinerator Cannon Card** - Implemented fire beam projectile with 20 damage + 3 burn stacks
33. **Enemy Pathfinding Alpha** - Enemies move toward player (left/decreasing columns) at start of each lane precombat phase, up to movement_speed cells, stopping if blocked by player ships

### Immediate Next Steps - PILOT SYSTEM
The combat mechanics and card system are solid. Next focus is implementing the pilot system:

**Priority 1: Pilot Data & Management**
1. **Pilot CSV Database**
   - pilot_database.csv with pilot stats and traits
   - Columns: pilot_id, display_name, portrait_path, class/specialty
   - Base stats: accuracy_bonus, evasion_bonus, attack_speed_bonus
   - Traits: special abilities or passive bonuses
   - Experience/level progression (optional for MVP)

2. **Pilot Roster System**
   - PilotManager singleton for pilot tracking
   - Available pilots pool
   - Assigned pilots (linked to ships)
   - Injured/unavailable pilots
   - Pilot hiring/recruitment mechanics

3. **Pilot-Ship Assignment**
   - UI for assigning pilots to ships
   - Visual indicator showing assigned pilot (portrait/icon)
   - Stat bonuses applied when pilot assigned
   - Unassign/reassign mechanics
   - Ship performance without pilot (baseline stats)

**Priority 2: Pilot Integration with Combat**
1. **Stat Bonuses**
   - Apply pilot accuracy bonus to ship accuracy
   - Apply pilot evasion bonus to ship evasion
   - Apply pilot attack speed bonus to ship attack speed
   - Display modified stats in ship inspector tooltip

2. **Pilot Traits/Abilities**
   - Passive traits (e.g., +10% shield regeneration)
   - Active abilities (cooldown-based)
   - Trait effects trigger during combat
   - Visual feedback for trait activation

3. **Pilot Experience & Injury**
   - Pilots gain XP from combat participation
   - Ships destroyed = pilot injured (unavailable for X turns)
   - Pilot level-up system (optional for MVP)
   - Medical bay/recovery mechanics

**Priority 3: Pilot UI**
1. **Pilot Selection Interface**
   - Pilot roster panel (in hangar or pre-combat)
   - Pilot portraits and stat displays
   - Assignment drag-and-drop or click-to-assign
   - Current assignments visible

2. **Combat Pilot Display**
   - Small pilot portrait on ship containers
   - Tooltip shows pilot name and bonuses
   - Pilot status indicators (healthy/injured)

3. **Pilot Management Screen**
   - Full roster view with filtering
   - Pilot details and history
   - Recruitment/dismissal options
   - Medical bay status

### Medium-Term Goals
1. **Pilot System** (next priority) - Assignment, traits, injury, XP
2. **Enemy Waves** - Spawn timing, wave composition, preview system
3. **Victory/Defeat Conditions** - Combat end triggers, rewards screen
4. **Expand Starmap** - Node types (combat/event/shop/rest/boss), path validation
5. **Convert DeckBuilder to Hangar** - Fleet management, pilot roster, upgrades panel
6. **More Card Types** - Complete elemental ammo set, combo cards, ship deployment cards

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
✓ **Damage System**: Accuracy vs evasion, critical hits, reinforced armor reduction
✓ **Health Display**: 3-tier bars (shield/armor/energy) above ships, max 32px width
✓ **Auto-Combat**: Ships auto-target and attack, switch targets every 3 seconds
✓ **Turn Structure**: Sequential lane combat with player-controlled progression
✓ **Energy System**: Ships gain 2-4 energy per attack, auto-cast abilities at max
✓ **Lane Restrictions**: When zoomed, ships only target enemies in same lane

---

## Questions Still to Consider

### Answered ✓
- ✓ How should ships target enemies in lanes? → Auto-targeting based on enemy in lane
- ✓ How are ship stats stored? → CSV database with ShipDatabase singleton
- ✓ How do resources display? → ResourceUI at top-left with icons
- ✓ How exactly does damage calculation work? → Hit chance (1.0 - evasion%), crit chance (1.0 - accuracy%), reinforced armor can negate crits
- ✓ When do ships generate energy vs auto-attack? → Ships generate 2-4 energy per attack, abilities auto-cast at max energy.  Ships generate 1 energy for each 5% of their max combined health they take
- ✓ Should we have a turn system or real-time combat? → Turn-based with sequential lane combat
- ✓ How do ship abilities work? → Energy-based, auto-cast when full (effects TBD)
- ✓ Should enemies auto-target or use AI behavior? → Auto-targeting same as player ships
- ✓ Lane restrictions? → When zoomed, ships only target same lane

### Still Open
- How do cards interact with deployed ships?
- What happens when a lane is full?
- Should ships be able to move between lanes?
- How do enemy waves spawn and advance? (from right? waves? timing?)
- What triggers the end of combat?
- How does the pilot system integrate with ship deployment?
- What are the actual ability effects for each ship?
- How does the card system integrate with turn-based combat?
- Should there be a hand size limit? Discard mechanics?
- How do players acquire new cards? (rewards, shops, events)

---

*This plan is a living document and should be updated as development progresses and requirements change.*

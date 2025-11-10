extends Node

# CombatConstants - Centralized constants and resource preloads for combat system
# This is an autoload singleton for easy access from any combat-related script

# Lane configuration
const NUM_LANES = 3
const LANE_Y_START = 150.0
const LANE_SPACING = 200.0

# Position constants
const MOTHERSHIP_X = 100.0
const ENEMY_SPAWN_X = 1000.0
const SHIP_DEPLOY_X_START = 280.0  # Where first ship deploys
const SHIP_SPACING = 40.0  # Horizontal spacing between ships in same lane

# Grid system constants
const GRID_ROWS = 5  # Height of each lane grid
const GRID_COLS = 16  # Width of each lane grid
const CELL_SIZE = 32  # Size of each grid cell in pixels
const GRID_START_X = 400.0  # Where the grid starts horizontally
const PLAYER_DEPLOY_COLS = [0, 1, 2, 3]  # Columns 0-3 for player deployment
const ENEMY_DEPLOY_COLS = [12, 13, 14, 15]  # Columns 12-15 for enemy deployment (last 4 columns)

# Turret constants
const NUM_TURRET_ROWS = 5  # Matches GRID_ROWS - one turret per row per lane
const TURRET_X_OFFSET = 180.0  # X position for player turrets
const ENEMY_TURRET_X_OFFSET = 920.0  # X position for enemy turrets
const TURRET_SIZE = 50  # Turrets are larger than regular ships
const SECONDARY_TURRET_X_OFFSET = 280  # Legacy constant (deprecated)

# Mothership and Boss constants
const MOTHERSHIP_ARMOR = 1000
const MOTHERSHIP_SHIELD = 500
const MOTHERSHIP_SIZE = 100
const BOSS_ARMOR = 1500
const BOSS_SHIELD = 750
const BOSS_SIZE = 120

# Ship size classes (width in pixels)
const SIZE_TINY = 20  # 32-48 range, using middle value
const SIZE_SMALL = 24  # 40-56 range, using middle value
const SIZE_MEDIUM = 36  # 48-64 range, using middle value
const SIZE_LARGE = 48  # 64-128 range, using middle value
const SIZE_EXTRA_LARGE = 80  # 128-192 range, using middle value

# Idle behavior constants
const DRIFT_DISTANCE = 10.0  # How far ships drift backward
const DRIFT_DURATION = 8.0  # How long drift takes (very slow)
const DRIFT_DELAY = 3.0  # Delay before starting drift
const RETURN_DURATION = 2.0  # How long return takes

# Preload ship textures
const MothershipTexture = preload("res://assets/Ships/illum_default/s_illum_default_24.png")
const InterceptorTexture = preload("res://assets/Ships/illum_default/s_illum_default_23.png")
const FighterTexture = preload("res://assets/Ships/illum_default/s_illum_default_19.png")
const FrigateTexture = preload("res://assets/Ships/illum_default/s_illum_default_01.png")

# Preload enemy textures
const MookTexture = preload("res://assets/Ships/alien/s_alien_09.png")
const EliteTexture = preload("res://assets/Ships/alien/s_alien_05.png")

# Preload UI textures
const CloseButtonTexture = preload("res://assets/UI/Close_BTN/Close_BTN.png")

# Preload background textures
const Space2Texture = preload("res://assets/Backgrounds/Space2/Bright/Space2.png")
const Stones1Texture = preload("res://assets/Backgrounds/Space2/Bright/stones1.png")

# Preload combat effects
const LaserTexture = preload("res://assets/Effects/laser_light/s_laser_light_001.png")

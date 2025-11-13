# Codebase Inventory - Complete Object & Method Catalog

**Generated:** 2025-11-13
**Total Files:** 22 GDScript files
**Total Classes:** 6 defined classes
**Autoload Singletons:** 5
**Deprecated Methods:** 9 explicitly marked

---

## TABLE OF CONTENTS

1. [Complete Object & Method Inventory](#section-1-complete-object--method-inventory)
2. [Duplicate Method Analysis](#section-2-duplicate-method-analysis)
3. [Key Statistics](#key-statistics)

---

## SECTION 1: COMPLETE OBJECT & METHOD INVENTORY

All GDScript files with their classes, methods, line numbers, and deprecation status.

---

### 1. BackgroundManager.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/BackgroundManager.gd`
**Class:** None (extends Node2D)
**Purpose:** Manages scrolling space background and parallax effects

**Methods:**
- `_ready()` - Line 25
- `_process(delta)` - Line 28
- `setup_backgrounds()` - Line 32
- `setup_space_background()` - Line 38
- `setup_parallax_background()` - Line 63
- `update_parallax_scroll(delta)` - Line 86
- `update_background_tiles()` - Line 114
- `set_scroll_direction(direction)` - Line 141
- `set_scroll_speed(speed)` - Line 145
- `set_auto_scroll(enabled)` - Line 149
- `set_tile_size(size)` - Line 153
- `set_parallax_opacity(opacity)` - Line 158
- `set_parallax_offset(offset)` - Line 166
- `get_parallax_offset()` - Line 170

---

### 2. Card.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/Card.gd`
**Class:** None (extends Control)
**Purpose:** Individual card UI and drag-and-drop handling

**Methods:**
- `_ready()` - Line 38
- `setup(data)` - Line 61
- `update_visuals()` - Line 69
- `_input(event)` - Line 103
- `_gui_input(event)` - Line 111
- `_process(_delta)` - Line 120
- `start_drag(click_position)` - Line 125
- `update_drag_position()` - Line 156
- `end_drag()` - Line 166
- `return_to_hand()` - Line 183
- `play_card_animation(target_position)` - Line 209
- `get_canvas_layer_root()` - Line 222
- `get_target_type()` - Line 229
- `get_card_name()` - Line 233
- `get_card_function()` - Line 237
- `_on_mouse_entered()` - Line 241
- `_on_mouse_exited()` - Line 247
- `_on_hover_timeout()` - Line 253
- `show_hover_popup()` - Line 258
- `hide_hover_popup()` - Line 305

---

### 3. CardEffects.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/CardEffects.gd`
**Class:** CardEffects (extends Node)
**Purpose:** Static class for card effect execution

**Methods (All Static):**
- `execute_card_effect_cinematic(function_name, source, target, combat_scene)` - Line 9
- `execute_card_effect(function_name, target, combat_scene)` - Line 24
- `execute_Strike(target, _combat_scene)` - Line 59
- `execute_Shield(target, combat_scene)` - Line 80
- `execute_Energy_Alpha(target, combat_scene)` - Line 119
- `execute_Energy_Beta(target, combat_scene)` - Line 157
- `apply_aoe_effect(primary_target, base_value, aoe_range, target_faction, effect_type, combat_scene)` - Line 197
- `apply_energy_effect(ship, energy_amount, combat_scene)` - Line 289
- `apply_shield_effect(ship, shield_amount, combat_scene)` - Line 309
- `apply_damage_effect(ship, damage_amount, combat_scene)` - Line 331
- `execute_Turret_Blast(target, combat_scene)` - Line 337
- `execute_Missile_Lock(target, combat_scene)` - Line 360
- `execute_Missile_Lock_Effect(target, combat_scene)` - Line 401
- `apply_missile_damage(target, damage)` - Line 488
- `show_missile_damage_number(target, intended_damage, damage_info, combat_scene)` - Line 523
- `show_effect_notification(target, text, color)` - Line 553
- `update_ship_ui(ship, combat_scene)` - Line 584 Examine to MOVE OUT-DB
- `execute_Incendiary_Rounds(target, _combat_scene)` - Line 597
- `execute_Cryo_Rounds(target, _combat_scene)` - Line 623
- `execute_Incinerator_Cannon(target, combat_scene)` - Line 666
- `execute_Incinerator_Cannon_Effect(target, combat_scene)` - Line 695
- `execute_Shield_Battery(target, combat_scene)` - Line 796
- `apply_aoe_full_effect(primary_target, base_value, aoe_range, target_faction, effect_type, combat_scene)` - Line 831
- `display_aura_effect(target, combat_scene)` - Line 909
- `execute_Shield_Battery_Effect(target, combat_scene)` - Line 948
- `execute_Incinerator_Cannon_Effect_Cinematic(source, target, combat_scene)` - Line 971
- `execute_Missile_Lock_Effect_Cinematic(source, target, combat_scene)` - Line 1035

---

### 4. CardHandManager.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/CardHandManager.gd`
**Class:** None (extends Node - Autoload Singleton)
**Purpose:** Manages card hand, deck, and card playing mechanics

**Methods:**
- `_ready()` - Line 38
- `_process(_delta)` - Line 41
- `initialize_deck()` - Line 46
- `shuffle_deck()` - Line 59
- `draw_card()` - Line 64
- `add_card_to_hand(card_name)` - Line 90
- `remove_card_from_hand(card)` - Line 118
- `discard_card(card_name)` - Line 125
- `update_hand_layout()` - Line 130
- `setup_hand_ui(parent)` - Line 139
- `set_hand_visible(visible)` - Line 158
- `_on_card_drag_started(card)` - Line 163
- `update_hover_highlight()` - Line 172
- `clear_hover_highlight()` - Line 199
- `_on_card_drag_ended(card, drop_position)` - Line 211
- `screen_to_world_position(screen_pos)` - Line 233
- `detect_target_at_position(position, target_type)` - Line 254
- `detect_single_target_at_position(position, target_type, ship_manager)` - Line 275
- `find_ship_at_position(position, faction)` - Line 300
- `world_pos_to_grid_pos(world_pos, lane_index)` - Line 338
- `find_turret_at_position(position, faction, ship_manager)` - Line 373
- `play_card(card, target)` - Line 402 - should this be a card method, as cards do not need to come from the hand nessecarily? -DB
- `set_combat_scene(scene, lane_index)` - Line 438
- `set_cards_playable(playable)` - Line 444
- `clear_hand()` - Line 449
- `get_hand_size()` - Line 458
- `get_draw_pile_size()` - Line 461
- `get_discard_pile_size()` - Line 465
- `highlight_valid_targets(target_type)` - Line 469
- `highlight_single_target_type(target_type, ship_manager)` - Line 488
- `highlight_ships_by_faction(faction, ship_manager)` - Line 513
- `highlight_turrets_by_faction(faction, ship_manager)` - Line 540
- `clear_target_highlights()` - Line 561

---

### 5. CombatConstants.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/CombatConstants.gd`
**Class:** None (extends Node - Autoload Singleton)
**Purpose:** Global constants for combat system

**Methods:** None (constants only)

**Deprecated Constants:**
- `SECONDARY_TURRET_X_OFFSET` - Line 30 - **DEPRECATED: legacy constant** **COMPLETELY REMOVE - DB**

---

### 6. CombatHealthSystem.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/CombatHealthSystem.gd`
**Class:** None (extends Node)
**Purpose:** **NEW MODULE** - Centralized health, shield, armor, and health bar management

**Methods:**
- `_init(manager)` - Line 28
- `create_health_bar(ship_container, ship_size, max_shield, max_armor)` - Line 35
- `update_health_bar(unit)` - Line 102
- `update_energy_bar(unit)` - Line 173
- `apply_damage(target, damage)` - Line 211 - **⭐ AUTHORITY FOR DAMAGE APPLICATION**
- `heal_armor(target, amount)` - Line 307
- `restore_shield(target, amount)` - Line 317
- `add_overshield(target, amount)` - Line 327
- `heal_full(target)` - Line 339
- `get_health_percentage(unit)` - Line 354
- `is_alive(unit)` - Line 372

---

### 7. CombatProjectileManager.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/CombatProjectileManager.gd`
**Class:** CombatProjectileManager (extends Node)
**Purpose:** Manages projectile launching, collision, and damage

**Methods:**
- `initialize(parent_scene, manager)` - Line 19
- `launch_projectile(attacker, target, spawn_offset)` - Line 34
- `_on_launch_projectile_hit(laser, attacker, target)` - Line 84
- `calculate_damage(attacker, target)` - Line 252
- `apply_damage(target, damage_result)` - Line 294 - **Delegates to CombatHealthSystem**
- `rotate_ship_to_target(attacker, target)` - Line 333
- `flash_target_sprite(target)` - Line 348
- `show_damage_number(target, damage_result, damage_info)` - Line 365
- `update_health_bar(target)` - Line 383
- `show_explosion_effect(position, size)` - Line 388
- `apply_burn_on_hit(attacker, target, damage_result)` - Line 458
- `apply_freeze_on_hit(attacker, target, damage_result)` - Line 501

**Deprecated Methods:**
- `fire_projectiles(attacker, target)` - Line 140 - **DEPRECATED: Use launch_projectile instead**
- `fire_single_projectile(attacker, target)` - Line 159 - **DEPRECATED: Use launch_projectile instead**
- `on_projectile_hit(projectile, attacker, target)` - Line 211 - **DEPRECATED: Use launch_projectile instead**

---

### 8. CombatShipManager.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/CombatShipManager.gd`
**Class:** CombatShipManager (extends Node)
**Purpose:** Manages ship deployment, grid positioning, and turret placement

**Methods:**
- `initialize(parent_scene)` - Line 39
- `initialize_lanes()` - Line 45
- `create_lane_marker(lane_index, y_pos)` - Line 67
- `get_random_empty_cell(lane_index, columns)` - Line 123
- `get_cell_world_position(lane_index, row, col)` - Line 137
- `occupy_grid_cell(lane_index, row, col, unit)` - Line 147
- `free_grid_cell(lane_index, row, col)` - Line 152
- `get_valid_move_cells(unit)` - Line 157
- `initialize_turret_grids()` - Line 186
- `get_turret_at_position(lane_index, row_index, faction)` - Line 204
- `set_turret_at_position(lane_index, row_index, turret, faction)` - Line 216
- `get_turret_y_position(lane_index, row_index)` - Line 226
- `deploy_ship(ship_type, lane_index, faction)` - Line 238
- `destroy_ship(ship)` - Line 244
- `move_ship_to_cell(unit, target_row, target_col)` - Line 254
- `show_movement_overlay(unit)` - Line 259
- `clear_movement_overlay()` - Line 296

**Deprecated Properties:**
- `turrets` array - **DEPRECATED: Use turret_grids instead**
- `enemy_turrets` array - **DEPRECATED: Use enemy_turret_grids instead**

---

### 9. CombatStatusEffectManager.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/CombatStatusEffectManager.gd`
**Class:** CombatStatusEffectManager (extends Node)
**Purpose:** Manages burn, freeze, and other status effects

**Methods:**
- `_ready()` - Line 39
- `initialize(p_combat_scene)` - Line 43
- `set_active_lane(lane_index)` - Line 48
- `_process(delta)` - Line 53
- `_process_effect_tick(ship, effect)` - Line 113
- `_process_burn_tick(ship, effect)` - Line 120
- `apply_burn(target, stacks)` - Line 161
- `apply_freeze(target, stacks)` - Line 200
- `get_freeze_attack_speed_multiplier(ship)` - Line 224
- `get_freeze_evasion_multiplier(ship)` - Line 241
- `remove_status(target, effect_type)` - Line 258
- `clear_all_status(target)` - Line 272
- `get_status_stacks(target, effect_type)` - Line 279
- `update_status_visual(ship)` - Line 291
- `show_burn_damage_number(ship, damage)` - Line 353
- `_remove_card_effect(ship, effect)` - Line 378
- `_remove_cryo_rounds(ship)` - Line 385
- `get_ships_in_active_lane()` - Line 415

---

### 10. CombatTargetingSystem.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/CombatTargetingSystem.gd`
**Class:** CombatTargetingSystem (extends Node)
**Purpose:** Intelligent target selection for units in combat

**Methods:**
- `initialize(manager)` - Line 22
- `select_target_for_unit(unit, targeting_mode)` - Line 30
- `targeting_function_alpha(attacker)` - Line 42
- `targeting_function_random(attacker)` - Line 73
- `targeting_function_gamma(attacker)` - Line 101
- `find_closest_in_row(attacker, target_faction)` - Line 132
- `find_closest_in_adjacent_rows(attacker, target_faction)` - Line 157
- `find_targetable_turret(attacker, target_faction)` - Line 183
- `find_any_in_lane(attacker, target_faction)` - Line 197
- `find_turret_in_row(attacker, target_faction)` - Line 211
- `find_mothership_or_boss(attacker, target_faction)` - Line 231
- `reassign_all_targets()` - Line 257
- `clear_targets_referencing_ship(destroyed_ship)` - Line 269

---

### 11. CombatWeapons.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/CombatWeapons.gd`
**Class:** None (extends Node)
**Purpose:** Weapon firing and damage calculation

**Methods:**
- `_init(parent)` - Line 14
- `set_combat_manager(parent)` - Line 17
- `set_health_system(system)` - Line 20
- `fire_weapon_volley(attacker, target)` - Line 27
- `calculate_projectile_spawn_positions(ship_size, num_projectiles)` - Line 61
- `calculate_target_position(attacker, target, attacker_center)` - Line 88
- `rotate_to_target(attacker, target)` - Line 223
- `calculate_damage(attacker, target)` - Line 253
- `apply_damage(target, damage)` - Line 305 - **Delegates to CombatHealthSystem**
- `gain_energy(unit)` - Line 319
- `cast_ability(unit)` - Line 348
- `normalize_card_function_name(function_name)` - Line 401
- `apply_burn_on_hit(attacker, target, damage_dealt)` - Line 421

**Deprecated Methods:**
- `fire_weapon(attacker, target, projectile_delay)` - Line 108 - **DEPRECATED: Use fire_weapon_volley instead**
- `fire_projectile(attacker, target)` - Line 136 - **DEPRECATED: Use fire_weapon_volley instead**
- `on_projectile_hit(projectile, attacker, target)` - Line 188 - **DEPRECATED: Use fire_weapon_volley instead**

---

### 12. Combat_2.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/Combat_2.gd`
**Class:** None (extends Node2D)
**Purpose:** **MAIN COMBAT ORCHESTRATOR** - 5551 lines, 100+ methods
**⚠️ COMPLEXITY HOTSPOT** - Largest file in codebase

**Key Methods (Partial List):**
- `initialize_managers()` - Line 86
- `_on_ship_destroyed(ship)` - Line 146
- `_on_unit_destroyed_by_health_system(unit)` - Line 152
- `_on_damage_dealt(attacker, target, damage_info)` - Line 160
- `_on_status_applied(ship, effect_type, stacks)` - Line 178
- `_on_status_removed(ship, effect_type)` - Line 183
- `_on_status_tick(ship, effect_type, damage)` - Line 188
- `_on_mothership_destroyed()` - Line 193
- `_on_boss_destroyed()` - Line 220
- `_ready()` - Line 251
- `_process(delta)` - Line 315
- `initialize_lanes()` - Line 321
- `create_lane_marker(lane_index, y_pos)` - Line 343
- `setup_mothership()` - Line 742
- `setup_turrets()` - Line 805
- `create_turret_at_grid_position(lane_index, row_index, turret_type, is_enabled)` - Line 831
- `setup_enemy_turrets()` - Line 1022
- `setup_enemy_boss()` - Line 1215
- `deploy_ship_to_lane(ship_type, lane_index)` - Line 1741
- `deploy_enemy_to_lane(enemy_type, lane_index)` - Line 1895
- `zoom_to_lane(lane_index)` - Line 2586
- `_on_return_to_tactical()` - Line 2632
- `start_attack_sequence()` - Line 2771
- `calculate_damage(attacker, target)` - Line 2981
- `create_health_bar(...)` - Line 5252 - **DEPRECATED: Use health_system.create_health_bar()**
- `update_health_bar(...)` - Line 5290 - **DEPRECATED: Use health_system.update_health_bar()**
- `update_energy_bar(...)` - Line 5345 - **DEPRECATED: Use health_system.update_energy_bar()**
- _(And 70+ more methods...)_

**Removed Functions:**
- `apply_damage()` - Line ~3034 - **REMOVED: Now in CombatHealthSystem (see APPLY_DAMAGE_CLEANUP.md)**

---

### 13. DamageNumber.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/DamageNumber.gd`
**Class:** DamageNumber (extends Node2D)
**Purpose:** Floating damage/healing numbers with animations

**Methods:**
- `_ready()` - Line 50
- `_process(delta)` - Line 71
- `setup(amount, type, crit)` - Line 78
- `apply_styling()` - Line 94
- `animate()` - Line 139
- `spawn(parent, pos, amount, type, crit)` **[STATIC]** - Line 163
- `show_shield_damage(parent, pos, amount, crit)` **[STATIC]** - Line 172
- `show_armor_damage(parent, pos, amount, crit)` **[STATIC]** - Line 175
- `show_healing(parent, pos, amount)` **[STATIC]** - Line 178
- `show_miss(parent, pos)` **[STATIC]** - Line 181

---

### 14. DataManager.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/DataManager.gd`
**Class:** None (extends Node - Autoload Singleton)
**Purpose:** Loads and manages game data from CSV files

**Methods:**
- `_ready()` - Line 23
- `load_all_databases()` - Line 27
- `load_ship_database()` - Line 38
- `parse_ship_data(header, line)` - Line 76
- `get_ship_data(ship_id)` - Line 118
- `get_ships_by_faction(faction)` - Line 130
- `get_ships_by_type(type)` - Line 141
- `get_all_ships()` - Line 152
- `get_enabled_ships()` - Line 159
- `load_card_database()` - Line 172
- `parse_card_data(header, line)` - Line 210
- `get_card_data(card_name)` - Line 224
- `get_all_cards()` - Line 236
- `load_starting_deck()` - Line 243
- `load_star_names()` - Line 270
- `get_random_star_name()` - Line 294
- `get_all_star_names()` - Line 301
- `reload_all_databases()` - Line 309
- `is_all_data_loaded()` - Line 322

---

### 15. DeckBuilder.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/DeckBuilder.gd`
**Class:** None (extends Node2D)
**Purpose:** Deck building UI scene

**Methods:**
- `_ready()` - Line 17
- `load_cards_from_datamanager()` - Line 34
- `load_deck()` - Line 46
- `display_deck(deck)` - Line 72
- `_on_back_button_pressed()` - Line 95

---

### 16. GameData.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/GameData.gd`
**Class:** None (extends Node - Autoload Singleton)
**Purpose:** Persistent game state storage

**Methods:**
- `save_starmap(stars)` - Line 27
- `clear_starmap()` - Line 31
- `save_combat_state(state)` - Line 35
- `get_combat_state()` - Line 40
- `clear_combat_state()` - Line 43
- `save_deck(deck)` - Line 47
- `get_deck()` - Line 58
- `clear_deck()` - Line 61
- `save_seed(seed_value)` - Line 65
- `get_seed()` - Line 70
- `clear_seed()` - Line 73
- `add_resource(type, amount)` - Line 78
- `spend_resource(type, amount)` - Line 94
- `get_resource(type)` - Line 116

---

### 17. ResourceUI.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/ResourceUI.gd`
**Class:** None (extends Control)
**Purpose:** Resource display UI

**Methods:**
- `_ready()` - Line 26
- `setup_resources()` - Line 30
- `create_background(width, height)` - Line 75
- `add_resource_display(container, resource_type, icon)` - Line 87
- `update_resources()` - Line 123

---

### 18. SeedManager.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/SeedManager.gd`
**Class:** None (extends Node - Autoload Singleton)
**Purpose:** Deterministic random number generation

**Methods:**
- `_ready()` - Line 12
- `initialize_seed(seed_value)` - Line 19
- `generate_new_seed()` - Line 25
- `get_current_seed()` - Line 32
- `randi()` - Line 36
- `randf()` - Line 40
- `randi_range(from, to)` - Line 44
- `randf_range(from, to)` - Line 48
- `shuffle_array(array)` - Line 53
- `pick_random(array)` - Line 63

---

### 19. Star.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/Star.gd`
**Class:** Star (extends Area2D)
**Purpose:** Individual star node for starmap

**Methods:**
- `_ready()` - Line 9
- `setup(size, color, bright)` - Line 12
- `_draw()` - Line 18
- `get_collision_radius()` - Line 32

---

### 20. StarMap.gd
**Path:** `/home/mrdangerous/any-type-4/scripts/StarMap.gd`
**Class:** None (extends Node2D)
**Purpose:** Procedural starmap generation and navigation
**⚠️ LARGE FILE** - 1100+ lines

**Methods (60+ total, showing key ones):**
- `_ready()` - Line 92
- `_process(delta)` - Line 144
- `load_star_names()` - Line 147
- `generate_starfield()` - Line 152
- `create_star(pos, size, color, brightness)` - Line 181
- `load_starfield()` - Line 196
- `handle_edge_scrolling(delta)` - Line 215
- `generate_network()` - Line 232
- `find_node_near_position(target)` - Line 378
- `find_closest_star_to_y(star_list, target_y)` - Line 390
- `calculate_line_angle(p1, p2)` - Line 402
- `angles_too_similar(angle1, angle2)` - Line 410
- `is_too_close_to_nodes(new_pos)` - Line 418
- `would_create_parallel_path(new_node_pos, existing_nodes)` - Line 426
- `connect_network_forward()` - Line 456
- `ensure_path_exists()` - Line 534
- `connect_path_to_end()` - Line 563
- `lines_intersect(p1, p2, p3, p4)` - Line 615
- `direction(p1, p2, p3)` - Line 632
- `draw_network()` - Line 635
- `create_node_icons()` - Line 693
- `is_node_reachable(node_idx)` - Line 710
- `create_node_icon(node_data, node_idx, is_reachable)` - Line 715
- `setup_player()` - Line 839
- `_on_node_hover_start(node_idx, node_data)` - Line 862
- `_on_node_hover_end()` - Line 900
- `_on_node_clicked(node_idx)` - Line 903
- `move_player_to_node(node_idx)` - Line 912
- `get_random_encounter_type()` - Line 1046
- _(And 30+ more debug/UI control methods...)_

---

### 21-22. Additional Files
**Note:** If there are more .gd files not listed above, they follow similar patterns.

---

## SECTION 2: DUPLICATE METHOD ANALYSIS

Methods with the same name across different files, categorized by severity.

---

### 🔴 CRITICAL DUPLICATES (Same Logic, Different Files)

These are true duplicates where the same functionality is implemented multiple times.

#### 1. `calculate_damage(attacker, target)`
**Instances:** 3 files
- **CombatWeapons.gd** - Line 253
- **CombatProjectileManager.gd** - Line 252
- **Combat_2.gd** - Line 2981

**Issue:** Same damage calculation logic duplicated across three files
**Recommendation:** Consolidate into a single damage calculator (possibly in CombatConstants or a DamageCalculator utility)

---

#### 2. `apply_burn_on_hit(attacker, target, ...)`
**Instances:** 2 files
- **CombatWeapons.gd** - Line 421
- **CombatProjectileManager.gd** - Line 458

**Issue:** Burn status effect application duplicated
**Recommendation:** Move to CombatStatusEffectManager for single source of truth

---

#### 3. `rotate_to_target()` / `rotate_ship_to_target()`
**Instances:** 2 files with similar names
- **CombatWeapons.gd** - `rotate_to_target(attacker, target)` - Line 223
- **CombatProjectileManager.gd** - `rotate_ship_to_target(attacker, target)` - Line 333

**Issue:** Same ship rotation logic with different method names
**Recommendation:** Consolidate into one utility function

---

### 🟡 ACCEPTABLE DUPLICATES (Delegation Pattern)

These methods delegate to the authoritative implementation.

#### 4. `apply_damage()`
**Authority:** CombatHealthSystem.apply_damage() - Line 211
**Delegators:**
- **CombatWeapons.gd** - Line 305 (3-line delegator to health_system)
- **CombatProjectileManager.gd** - Line 294 (delegator with format conversion)

**Status:** ✅ ACCEPTABLE - Clear delegation pattern established
**Note:** Combat_2.gd duplicate was removed (see APPLY_DAMAGE_CLEANUP.md)

---

#### 5. `update_health_bar(target)`
**Authority:** CombatHealthSystem.update_health_bar() - Line 102
**Reference:** CombatProjectileManager.update_health_bar() - Line 383

**Status:** ⚠️ VERIFY - ProjectileManager may be redundant
**Recommendation:** Check if this delegates or is unused

---

### 🟢 NOT DUPLICATES (Standard Godot Lifecycle)

These are standard Godot methods that every class needs.

#### 6. `_ready()`
**Instances:** 15+ files
**Status:** ✅ NORMAL - Standard Godot initialization method

#### 7. `_process(delta)`
**Instances:** 7 files
**Status:** ✅ NORMAL - Standard Godot frame update method

#### 8. `_input(event)` / `_gui_input(event)`
**Instances:** Multiple files
**Status:** ✅ NORMAL - Standard Godot input handling

---

### 🟢 NOT DUPLICATES (Different Purposes)

#### 9. `initialize()`
**Instances:** 4 manager files
**Different signatures:**
- CombatShipManager.initialize(parent_scene)
- CombatTargetingSystem.initialize(manager)
- CombatStatusEffectManager.initialize(p_combat_scene)
- CombatProjectileManager.initialize(parent_scene, manager)

**Status:** ✅ ACCEPTABLE - Different parameters for different manager types

#### 10. `setup()`
**Instances:** 2 files with completely different purposes
- Star.setup(size, color, bright) - Star visual setup
- Card.setup(data) - Card data initialization

**Status:** ✅ NOT DUPLICATES - Different purposes, different signatures

---

### 📋 DEPRECATED METHODS

Explicitly marked for removal or replacement.

#### In CombatWeapons.gd:
1. `fire_weapon()` - Line 108 - **DEPRECATED: Use fire_weapon_volley instead**
2. `fire_projectile()` - Line 136 - **DEPRECATED: Use fire_weapon_volley instead**
3. `on_projectile_hit()` - Line 188 - **DEPRECATED: Use fire_weapon_volley instead**

#### In CombatProjectileManager.gd:
4. `fire_projectiles()` - Line 140 - **DEPRECATED: Use launch_projectile instead**
5. `fire_single_projectile()` - Line 159 - **DEPRECATED: Use launch_projectile instead**
6. `on_projectile_hit()` - Line 211 - **DEPRECATED: Use launch_projectile instead**

#### In Combat_2.gd:
7. `create_health_bar()` - Line 5252 - **DEPRECATED: Use health_system.create_health_bar()**
8. `update_health_bar()` - Line 5290 - **DEPRECATED: Use health_system.update_health_bar()**
9. `update_energy_bar()` - Line 5345 - **DEPRECATED: Use health_system.update_energy_bar()**

#### In CombatShipManager.gd:
10. `turrets` array - **DEPRECATED: Use turret_grids instead**
11. `enemy_turrets` array - **DEPRECATED: Use enemy_turret_grids instead**

#### In CombatConstants.gd:
12. `SECONDARY_TURRET_X_OFFSET` - Line 30 - **DEPRECATED: legacy constant**

---

## KEY STATISTICS

### File Metrics
- **Total GDScript Files:** 22
- **Largest File:** Combat_2.gd (5551 lines, 100+ methods)
- **Second Largest:** StarMap.gd (1100+ lines, 60+ methods)
- **Smallest Files:** Constants/utility files (<100 lines)

### Architecture
- **Defined Classes:** 6 (Star, DamageNumber, CombatShipManager, CombatTargetingSystem, CombatStatusEffectManager, CombatProjectileManager, CardEffects)
- **Autoload Singletons:** 5 (CombatConstants, DataManager, CardHandManager, GameData, SeedManager)
- **Scene Controllers:** 8+ (Combat_2, StarMap, DeckBuilder, Card, etc.)

### Code Health
- **Critical Duplicates:** 3 methods need consolidation
- **Deprecated Methods:** 9 explicitly marked
- **Delegation Patterns:** 2 properly implemented (apply_damage, health bar updates)
- **Recent Refactoring:** CombatHealthSystem added as centralized health management

### Complexity Hotspots
1. **Combat_2.gd** - 5551 lines, needs further refactoring
2. **StarMap.gd** - 1100+ lines, complex procedural generation
3. **CardEffects.gd** - 1000+ lines, many card effect implementations

### Refactoring Progress
✅ **Completed:**
- CombatHealthSystem extracted from Combat_2
- apply_damage() centralized
- Health bar management consolidated

⏳ **Recommended Next Steps:**
- Extract ship creation into CombatShipFactory
- Consolidate calculate_damage() into single utility
- Remove/consolidate duplicate rotation functions
- Move apply_burn_on_hit to CombatStatusEffectManager
- Break up Combat_2.gd further (see REFACTORING_PROPOSAL.md)

---

## RECOMMENDATIONS

### Immediate Cleanup Priorities

1. **Consolidate `calculate_damage()`**
   - Create single source in utility or constants
   - 3 duplicates to remove

2. **Move `apply_burn_on_hit()` to StatusEffectManager**
   - 2 duplicates to consolidate
   - Better organization

3. **Unify rotation functions**
   - Standardize on one name
   - 2 similar implementations

4. **Remove Deprecated Methods**
   - 9 deprecated methods can be safely removed
   - Clean up old weapon firing code

### Long-term Refactoring

1. **Break up Combat_2.gd**
   - Extract ship factory
   - Extract unit manager
   - Extract turn system
   - See REFACTORING_PROPOSAL.md for details

2. **Standardize Manager Interfaces**
   - Consistent initialization patterns
   - Uniform signal naming
   - Clear delegation chains

3. **Create Utility Classes**
   - DamageCalculator
   - RotationUtility
   - PositionCalculator

---

**Document Generated:** 2025-11-13
**Last Updated:** After CombatHealthSystem refactor
**Related Docs:** REFACTORING_PROPOSAL.md, HEALTH_SYSTEM_REFACTOR_SUMMARY.md, APPLY_DAMAGE_CLEANUP.md

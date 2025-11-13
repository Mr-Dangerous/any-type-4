# Combat System Refactoring Proposal

## Problem
- `Combat_2.gd` is 5566 lines with 179 functions
- Ship creation, damage, and UI updates are tangled together
- Hard to understand data flow
- Circular dependencies between managers

## Current Architecture Issues

### Current File Responsibilities (Messy)
- `Combat_2.gd` - Does EVERYTHING (ship creation, UI, combat logic, health bars, etc.)
- `CombatWeapons.gd` - Damage application, calls back to Combat_2
- `CombatProjectileManager.gd` - Projectile logic, calls CombatWeapons
- Circular: ProjectileManager → Weapons → Combat_2

## Proposed Module Structure

### 1. **CombatShipFactory.gd** (NEW)
**Responsibility**: Create ship/enemy/turret game objects
- `create_player_ship(ship_data, position) -> Dictionary`
- `create_enemy(enemy_data, position) -> Dictionary`
- `create_turret(turret_data, position) -> Dictionary`
- `create_mothership(position) -> Dictionary`
- `create_boss(position) -> Dictionary`

**Returns**: Ship dictionary with all required fields:
```gdscript
{
    "id": "ship_123",
    "type": "ship",
    "stats": {...},
    "current_armor": 100,
    "current_shield": 50,
    "container": Node2D,  # Visual container
    "sprite": TextureRect,
    # ... etc
}
```

---

### 2. **CombatHealthSystem.gd** (NEW)
**Responsibility**: Health/shield/armor management + health bar UI
- `apply_damage(target: Dictionary, damage: int) -> Dictionary`
- `heal_target(target: Dictionary, amount: int)`
- `add_shield(target: Dictionary, amount: int)`
- `update_health_bar(target: Dictionary)`  # Updates visual bars
- `create_health_bar(container: Node, ship_size: int, max_shield: int, max_armor: int)`

**No dependencies on Combat_2** - Standalone health system

---

### 3. **CombatWeapons.gd** (REFACTOR)
**Responsibility**: Weapon firing and projectile creation ONLY
- Remove: `apply_damage()` (move to CombatHealthSystem)
- Keep: `fire_weapon()`, `calculate_damage()`, weapon definitions

---

### 4. **CombatProjectileManager.gd** (REFACTOR)
**Responsibility**: Projectile movement and collision
- Keep: Projectile spawning, movement, collision detection
- Change: Instead of calling `apply_damage()`, emit signal or call CombatHealthSystem directly

---

### 5. **CombatUnitManager.gd** (NEW)
**Responsibility**: Track all units in combat
- `register_unit(unit: Dictionary)`
- `get_units_in_lane(lane: int) -> Array[Dictionary]`
- `get_unit_by_id(id: String) -> Dictionary`
- `remove_unit(id: String)`
- Maintains lists: `player_ships`, `enemy_ships`, `turrets`, etc.

---

### 6. **Combat_2.gd** (SLIM DOWN)
**Responsibility**: Combat orchestration and game loop ONLY
- Initialize all managers
- Handle turn phases (tactical → precombat → combat → postcombat)
- Lane management
- Victory/defeat conditions
- Delegates everything else to specialized managers

**Remove from Combat_2:**
- Ship creation functions (→ CombatShipFactory)
- Health bar creation/update (→ CombatHealthSystem)
- Damage application (→ CombatHealthSystem)
- Unit tracking (→ CombatUnitManager)

---

## Data Flow After Refactoring

### Ship Creation Flow
```
Combat_2.deploy_ship()
  ↓
CombatShipFactory.create_player_ship(data, position)
  ↓
Returns ship Dictionary
  ↓
CombatHealthSystem.create_health_bar(ship.container, ...)
  ↓
CombatUnitManager.register_unit(ship)
  ↓
Combat_2 stores reference
```

### Damage Flow
```
Projectile hits target
  ↓
CombatProjectileManager detects collision
  ↓
CombatHealthSystem.apply_damage(target, damage)
  ↓ (inside apply_damage)
  - Update current_shield/current_armor
  - Call update_health_bar(target)  # Same module!
  - Check if destroyed
  ↓
If destroyed: emit signal → Combat_2 handles cleanup
```

**Key improvement**: Health system is self-contained. Damage → Update bar happens in ONE module.

---

## Benefits

1. **Clearer Responsibility**: Each module has ONE job
2. **No Circular Dependencies**: Clear hierarchy
3. **Easier to Understand**: Want to know about health? Look at CombatHealthSystem
4. **Easier to Test**: Each module can be tested independently
5. **Reusable**: CombatHealthSystem could be used in other game modes

---

## Migration Strategy

### Phase 1: Extract Health System (SAFEST FIRST)
1. Create `CombatHealthSystem.gd`
2. Move `create_health_bar()` and `update_health_bar()` from Combat_2
3. Move `apply_damage()` from CombatWeapons
4. Update CombatWeapons to use new health system
5. Test thoroughly

### Phase 2: Extract Ship Factory
1. Create `CombatShipFactory.gd`
2. Move ship creation functions from Combat_2
3. Update Combat_2 to use factory
4. Test thoroughly

### Phase 3: Extract Unit Manager
1. Create `CombatUnitManager.gd`
2. Move unit tracking arrays from Combat_2
3. Update all unit lookups to use manager
4. Test thoroughly

### Phase 4: Clean up Combat_2
1. Remove moved code
2. Simplify to orchestration only
3. Final testing

---

## Next Steps

Would you like me to:
1. **Start with Phase 1** (Extract Health System) - This will immediately solve your confusion about health bar updates
2. **Create all new files first** then migrate gradually
3. **Just create CombatHealthSystem** as a proof of concept to show you how it works

I recommend starting with Phase 1, as it directly addresses your question about understanding health bar updates.

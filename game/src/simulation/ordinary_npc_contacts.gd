extends RefCounted
## One gun's ordered NPC contact pass. The world owner must supply its complete
## target list, then commit both returned owners. Explicit point providers are
## authoritative; ordinary cubes may use the caller's verified bounds selection.
## This does not advance time or implement non-NPC contacts and visual effects.
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Geometry = preload("res://src/simulation/ordinary_hit_geometry.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
var error := ""

func evaluate(projectiles: RefCounted, combat: RefCounted, ordered_actor_ids: Variant, bounds_selection: Variant = null) -> Dictionary:
	return _evaluate(projectiles,combat,ordered_actor_ids,bounds_selection,false)

## Only for an outer transaction that owns BOTH detached inputs and discards
## them on any failure. Standalone callers use evaluate() for atomic isolation.
func evaluate_staged(projectiles: RefCounted, combat: RefCounted, ordered_actor_ids: Variant, bounds_selection: Variant = null) -> Dictionary:
	return _evaluate(projectiles,combat,ordered_actor_ids,bounds_selection,true)

func _evaluate(projectiles: RefCounted, combat: RefCounted, ordered_actor_ids: Variant, bounds_selection: Variant, staged: bool) -> Dictionary:
	error = ""
	if projectiles==null or combat==null or projectiles.get_script()!=Projectiles or combat.get_script()!=Combat:
		return fail("NPC contacts require ordinary projectile and opening NPC owners")
	if not ordered_actor_ids is Array or ordered_actor_ids.size()>65536:
		return fail("NPC contacts require an explicit bounded ordered target list")
	var shots: Dictionary = projectiles.snapshot()
	if shots.is_empty(): return fail("Configure ordinary projectiles before checking contacts")
	if bounds_selection==null: bounds_selection=shots.weapon.get("collision_bounds")
	if not bounds_selection is Dictionary: return fail("NPC contacts require explicit bounds selection")
	var target_bounds: bool = bounds_selection.get("mode")=="target"
	if target_bounds:
		if bounds_selection.size()!=1: return fail("Target bounds cannot contain a weapon override")
	elif bounds_selection.get("mode")!="fixed" or bounds_selection.size()!=2 or not Vitals.integer(bounds_selection.get("half_extent")):
		return fail("Unsupported or malformed weapon bounds override")
	var staged_combat: RefCounted = combat if staged else combat.fork_for_frame()
	if not staged_combat.supports_weapon_hit(shots.weapon): return fail(staged_combat.error)
	# Validate the complete list before any result is produced. Do not sort or
	# deduplicate: source target-list append operations preserve both properties.
	for id in ordered_actor_ids:
		if staged_combat.collision_context(id).is_empty(): return fail(staged_combat.error)
	var staged_shots: RefCounted = projectiles if staged else projectiles.fork_state()
	var geometry := Geometry.new()
	var contacts := []
	var last_contact_actor_id: Variant = null
	for id in ordered_actor_ids:
		# Activity and positive hull are sampled once per target, before its slots.
		# Death from an early slot does not suppress marking later slot contacts.
		var target: Dictionary = staged_combat.collision_context(id)
		if not target.eligible: continue
		if target.path not in ["bounds","point_geometry"]:return fail("Unsupported NPC collision provider")
		var half_extent: int = target.half_extent if target_bounds else bounds_selection.half_extent
		for index in shots.slots.size():
			var projectile: Variant = shots.slots[index]
			if projectile==null: continue
			# Retained real projectiles participate regardless of remaining lifetime.
			# Marking a contact preserves geometry for later overlapping targets.
			var query: Dictionary=geometry.box_geometry(projectile.position,target.center,target.get("boxes")) if target.path=="point_geometry" else geometry.bounds(projectile.position,projectile.velocity,target.center,half_extent)
			if query.is_empty(): return fail(geometry.error)
			if not query.hit: continue
			var hit: Dictionary = staged_combat.weapon_hit(id,shots.weapon)
			if hit.is_empty(): return fail(staged_combat.error)
			if not staged_combat.record_contact(id,projectile.velocity,query.get("box_index")): return fail(staged_combat.error)
			if not staged_shots.mark_impact(projectile.id): return fail(staged_shots.error)
			last_contact_actor_id=id
			contacts.append({"actor_id":id,"slot":index,"projectile_id":projectile.id,"geometry":query,"damage":hit})
	return {"projectiles":staged_shots,"combat":staged_combat,"contacts":contacts,"last_contact_actor_id":last_contact_actor_id}

func fail(message: String) -> Dictionary:
	error = message
	return {}

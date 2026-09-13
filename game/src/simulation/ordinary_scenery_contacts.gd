extends RefCounted
## One ordinary gun's ordered scenery contacts. The world owner supplies this
## portion of its target list and commits both returned owners atomically.
## Timers, target selection, mining, destruction effects and rewards are separate.
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Bodies = preload("res://src/simulation/scenery_bodies.gd")
const Geometry = preload("res://src/simulation/ordinary_hit_geometry.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
var error := ""

func evaluate(projectiles: RefCounted, bodies: RefCounted, ordered_object_indices: Variant, bounds_selection: Variant = null) -> Dictionary:
	error = ""
	if projectiles==null or bodies==null or projectiles.get_script()!=Projectiles or bodies.get_script()!=Bodies:
		return fail("Scenery contacts require ordinary projectile and scenery body owners")
	if not ordered_object_indices is Array or ordered_object_indices.size()>65536:
		return fail("Scenery contacts require an explicit bounded ordered target list")
	var shots: Dictionary = projectiles.snapshot()
	if shots.is_empty(): return fail("Configure ordinary projectiles before checking contacts")
	if bounds_selection==null: bounds_selection=shots.weapon.get("collision_bounds")
	if not bounds_selection is Dictionary: return fail("Scenery contacts require explicit bounds selection")
	var target_bounds: bool = bounds_selection.get("mode")=="target"
	if target_bounds:
		if bounds_selection.size()!=1: return fail("Target bounds cannot contain a weapon override")
	elif bounds_selection.get("mode")!="fixed" or bounds_selection.size()!=2 or not Vitals.integer(bounds_selection.get("half_extent")):
		return fail("Unsupported or malformed weapon bounds override")
	var staged_bodies: RefCounted = bodies.fork_for_frame()
	if not staged_bodies.supports_weapon_hit(shots.weapon): return fail(staged_bodies.error)
	# World append order is meaningful and may include duplicate target entries.
	for object_index in ordered_object_indices:
		if staged_bodies.collision_context(object_index).is_empty(): return fail(staged_bodies.error)
	var staged_shots: RefCounted = projectiles.fork_state()
	var geometry := Geometry.new()
	var contacts := []
	var last_contact_object_index: Variant = null
	for object_index in ordered_object_indices:
		# A target remains in this inner pass after an earlier slot kills it. A
		# subsequent duplicate target entry samples its updated eligibility again.
		var target: Dictionary = staged_bodies.collision_context(object_index)
		if not target.eligible: continue
		if target.path!="bounds": return fail("Scenery point geometry requires its own verified provider")
		var half_extent: int = target.half_extent if target_bounds else bounds_selection.half_extent
		for slot in shots.slots.size():
			var projectile: Variant = shots.slots[slot]
			if projectile==null: continue
			# Source collision sees retained real slots, including expired and
			# previously impacted projectiles, until the owner's movement cleanup.
			var query: Dictionary = geometry.bounds(projectile.position,projectile.velocity,target.center,half_extent)
			if query.is_empty(): return fail(geometry.error)
			if not query.hit: continue
			var hit: Dictionary = staged_bodies.weapon_hit(object_index,shots.weapon)
			if hit.is_empty(): return fail(staged_bodies.error)
			if not staged_bodies.record_contact(object_index,projectile.velocity): return fail(staged_bodies.error)
			if not staged_shots.mark_impact(projectile.id): return fail(staged_shots.error)
			last_contact_object_index=object_index
			contacts.append({"object_index":object_index,"slot":slot,"projectile_id":projectile.id,"geometry":query,"damage":hit})
	return {"projectiles":staged_shots,"bodies":staged_bodies,"contacts":contacts,"last_contact_object_index":last_contact_object_index}

func fail(message: String) -> Dictionary:
	error = message
	return {}

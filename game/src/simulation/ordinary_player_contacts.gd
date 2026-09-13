extends RefCounted
## One ordinary NPC gun's fresh player contact pass. Commit both returned owners.
## Movement and deferred cleanup follow the complete target pass in the caller.
const Player = preload("res://src/simulation/opening_player_state.gd")
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Geometry = preload("res://src/simulation/ordinary_hit_geometry.gd")
var error := ""

func evaluate(projectiles: RefCounted, player: RefCounted, pose: Variant, shooter_present: Variant, shooter_hostile: Variant, special_flight: Variant) -> Dictionary:
	error=""
	if not projectiles is Projectiles or not player is Player: return fail("Player contact requires ordinary projectiles and fresh player statistics")
	if not shooter_present is bool or not shooter_hostile is bool or not special_flight is bool: return fail("Player contact requires explicit shooter and flight state")
	var shots: Dictionary=projectiles.snapshot()
	if shots.is_empty() or not player.supports_weapon_hit(shots.weapon): return fail(player.error if not player.error.is_empty() else "Missing NPC projectile weapon")
	var target: Dictionary=player.collision_context(pose)
	if target.is_empty(): return fail(player.error)
	var staged_player: RefCounted=player.fork_for_frame()
	var staged_shots: RefCounted=projectiles.fork_state()
	var contacts := []
	var geometry := Geometry.new()
	if target.eligible:
		for index in shots.slots.size():
			var shot: Variant=shots.slots[index]
			if shot==null: continue
			var query := geometry.bounds(shot.position,shot.velocity,target.center,target.half_extent)
			if query.is_empty(): return fail(geometry.error)
			if not query.hit: continue
			var hit: Dictionary=staged_player.weapon_hit(shots.weapon,shooter_present,shooter_hostile,special_flight)
			if hit.is_empty(): return fail(staged_player.error)
			if not staged_player.record_contact(shot.velocity): return fail(staged_player.error)
			if not staged_shots.mark_impact(shot.id): return fail(staged_shots.error)
			contacts.append({"slot":index,"projectile_id":shot.id,"geometry":query,"damage":hit})
	# The source retains the target's linked actor, which is null for this player.
	return {"projectiles":staged_shots,"player":staged_player,"contacts":contacts,"last_contact_actor":null}

func fail(message: String) -> Dictionary:
	error=message
	return {}

extends RefCounted
## Sample an admitted portal's source contact volume without moving the player.
static func evaluate(rules: Dictionary,close_start_ms: int,observation: Dictionary) -> Dictionary:
	for field in ["environment_contact_enabled","portal_visible","mining_active"]:
		if not observation.get(field) is bool:return {}
	if not observation.environment_contact_enabled or not observation.portal_visible or observation.mining_active:return {}
	var elapsed: Variant=observation.get("portal_elapsed_ms")
	var offset: Variant=observation.get("player_offset")
	if not elapsed is int or not offset is Vector3:return {}
	if not offset.is_finite() or elapsed>close_start_ms:return {}
	var extent: float=rules.cube_half_extent
	if absf(offset.x)>=extent or absf(offset.y)>=extent or absf(offset.z)>=extent:return {}
	var distance:=int(offset.length())
	var remaining:=int(rules.pull_radius)-distance
	if remaining<=0:return {}
	return {"distance":distance,"pull_distance":remaining>>int(rules.pull_distance_shift),
		"entry_contact":distance<=int(rules.entry_distance_maximum)}

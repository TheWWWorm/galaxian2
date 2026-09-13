extends RefCounted
## Resolve normal damage against a player. Shooter presence/hostility and special
## flight are sampled by the encounter owner, independently of targeting gates.
const Definitions = preload("res://src/content/player_hit_definitions.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
var error := ""

func resolve(damage: Variant, policy: Dictionary, shooter_present: Variant, shooter_hostile: Variant, special_flight: Variant) -> Dictionary:
	error=""
	if not Vitals.integer(damage) or not Definitions.parameters(policy) or not shooter_present is bool or not shooter_hostile is bool or not special_flight is bool:
		return fail("Player damage requires supported source parameters and explicit shooter/flight state")
	var amount: int=damage
	var branch := "ordinary"
	if shooter_present and not shooter_hostile:
		branch="nonhostile"
		amount=int(Vitals.single(Vitals.single(float(damage))*float(policy.nonhostile_scale)))
	elif special_flight:
		branch="special_flight"
		var scaled := Vitals.single(float(damage))
		for factor in policy.special_flight_multipliers: scaled=Vitals.single(scaled*float(factor))
		amount=int(scaled)
	if not Vitals.integer(amount): return fail("Player damage conversion exceeds supported integer bounds")
	return {"amount":amount,"branch":branch,"source_damage":damage}

func fail(message: String) -> Dictionary:
	error=message
	return {}

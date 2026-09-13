extends RefCounted
## Native normal-hit pool accounting. The encounter owner supplies verified
## current values, damage and permission to receive damage. No weapon, ownership,
## regeneration, reputation, linked-actor or mission behavior is inferred here.
const MAX_INTEGER := 2147483647
# Largest binary32 value below the signed integer conversion boundary.
const MAX_SHIELD := 2147483520.0
var error := ""
var _pools := {}

func clear() -> void:
	error = ""
	_pools = {}

func configure(hull: Variant, armor: Variant, shield: Variant) -> bool:
	clear()
	if not integer(hull) or not integer(armor) or not (shield is int or shield is float):
		return reject("Combat pools require integer hull/armor and numeric shield charge")
	if not is_finite(float(shield)) or shield < 0 or shield > MAX_SHIELD:
		return reject("Shield charge is outside the supported finite range")
	_pools = {"hull": hull, "armor": armor, "shield": single(float(shield))}
	return true

func snapshot() -> Dictionary:
	return _pools.duplicate()

func normal_hit(amount: Variant, damage_allowed: Variant) -> Dictionary:
	error = ""
	if _pools.is_empty(): return fail("Configure combat pools before applying a hit")
	if not integer(amount) or not damage_allowed is bool:
		return fail("Normal hits require nonnegative integer damage and explicit permission")
	var before := snapshot()
	if not damage_allowed or before.hull == 0:
		return {"accepted": false, "before": before, "after": snapshot(),
			"impact_layer": "", "destroyed_now": false}
	var after := before.duplicate()
	# The source's ordinary hit discards fractional shield charge on every
	# accepted hit, including zero damage. Preserve binary32 storage on output.
	var shield_units := int(before.shield)
	var remaining := maxi(0, amount - shield_units)
	after.shield = single(float(maxi(0, shield_units - amount)))
	after.armor = maxi(0, before.armor - remaining)
	after.hull = maxi(0, before.hull - maxi(0, remaining - before.armor))
	# Exact depletion belongs to the exhausted layer, not the following one.
	var layer := "shield" if amount <= shield_units else ("armor" if remaining <= before.armor else "hull")
	_pools = after
	return {"accepted": true, "before": before, "after": snapshot(),
		"impact_layer": layer, "destroyed_now": after.hull == 0}

static func integer(value: Variant) -> bool:
	return value is int and value >= 0 and value <= MAX_INTEGER

static func single(value: float) -> float:
	return PackedFloat32Array([value])[0]

func fail(message: String) -> Dictionary:
	reject(message)
	return {}

func reject(message: String) -> bool:
	error = message
	return false

extends RefCounted
## Intact source scenery bodies and ordinary weapon damage. Zero hull is an
## explicit boundary: effect playback, destruction accounting and mining are
## separate owners and are not completed or rewarded by this component.
const Resources = preload("res://src/content/scenery_body_resources.gd")
const Definitions = preload("res://src/content/scenery_resource_definitions.gd")
const HitDefinitions = preload("res://src/content/ordinary_hit_definitions.gd")
const WeaponHit = preload("res://src/simulation/ordinary_weapon_hit.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const TrainingWeapons=preload("res://src/content/combat_training_weapon_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
var error := ""
var _identity := {}
var _hit_policy := {}
var _rows := []
var _vitals := []
var _primary_cursors:=[]

func configure(bindings: RefCounted, field: Dictionary, resources: RefCounted) -> bool:
	clear()
	if bindings==null or resources==null or resources.get_script()!=Resources:
		return reject("Scenery bodies require source bindings and model bounds")
	var source: Dictionary = resources.snapshot()
	if source.is_empty() or source.get("base_content_id")!=bindings.base_content_id or source.get("binding_id")!=bindings.binding_id:
		return reject("Scenery model bounds belong to another content identity")
	for key in ["base_content_id","binding_id"]:
		if field.get(key)!=source.get(key): return reject("Scenery bodies belong to another field identity")
	var declarations: Variant = bindings.scenery_resources
	if not Definitions.parameters(declarations): return reject("Scenery body resource declarations are unavailable")
	var policy: Variant = bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if not policy is Dictionary or policy.is_empty() or not HitDefinitions.parameters(policy):
		return reject("Scenery bodies require the source ordinary hit policy")
	var objects: Variant = field.get("objects")
	if not objects is Array or objects.size()>8192: return reject("Invalid scenery body population")
	var rows := []
	var pools := []
	for index in objects.size():
		var row: Variant = objects[index]
		if not row is Dictionary or not row.get("index") is int or row.index!=index:
			return reject("Scenery body order is invalid")
		if not Vitals.integer(row.get("model_variant")) or row.model_variant>=declarations.model_ids.size() or row.get("model_id")!=int(declarations.model_ids[row.model_variant]):
			return reject("Scenery body model does not match its source variant")
		if not Vitals.integer(row.get("item_id")) or not Vitals.integer(row.get("source_size_value")) or row.source_size_value<4 or row.source_size_value>7:
			return reject("Scenery body content is invalid")
		if not row.get("position") is Vector3 or not row.position.is_finite() or not row.get("large") is bool:
			return reject("Scenery body requires a finite source position and size class")
		if (not row.get("scale") is float and not row.get("scale") is int) or not is_finite(row.scale) or row.scale<=0:
			return reject("Scenery body scale must be finite and positive")
		var scale := Vitals.single(float(row.scale))
		var radius: float = resources.model_radius(row.model_id)
		if radius<=0: return reject(resources.error)
		# The source uses the stored base-model sphere radius, not visual AABB,
		# LOD bounds, sphere-center distance or the rotating model's extent.
		var extent := Vitals.single(Vitals.single(radius*scale)*Vitals.single(0.7))
		var hull := Vitals.single(Vitals.single(100.0*scale)+30.0)
		if not is_finite(extent) or not is_finite(hull) or extent<0 or extent>Vitals.MAX_SHIELD or hull<1 or hull>Vitals.MAX_SHIELD:
			return reject("Scenery body bounds or hull exceed source precision")
		var vitals := Vitals.new()
		if not vitals.configure(int(hull),0,0.0): return reject(vitals.error)
		pools.append(vitals)
		rows.append({"index":index,"item_id":row.item_id,"model_id":row.model_id,
			"scale":scale,"source_size_value":row.source_size_value,"large":row.large,
			"position":row.position,"model_radius":radius,"half_extent":int(extent),
			"initial_hull":int(hull),"active":true,"damage_allowed":true,
			"collision_enabled":true,"motion_scalar":0.0,"damaged":false,"hit_feedback":0.0,
			"contact":false,"impact_vector":Vector3.ZERO,
			"hit_layers":{"shield":false,"armor":false,"hull":false}})
	_identity={"base_content_id":source.base_content_id,"binding_id":source.binding_id}
	_hit_policy=policy.duplicate(true)
	_rows=rows;_vitals=pools
	if TrainingWeapons.parameters(bindings.combat_training_weapons):
		_primary_cursors.append(7)
		if Travel.parameters(bindings.mido_travel):
			_primary_cursors.append(10)
			for cursor in [11,12]:
				if not Travel.journey(bindings.mido_travel,cursor).is_empty():_primary_cursors.append(cursor)
			if bindings.early_contracts.has("world_initialization") and Travel.navigation_available(bindings.mido_travel,13):_primary_cursors.append(13)
			if not Convoy.flight(bindings,79).is_empty():_primary_cursors.append(14)
			if not Alioth.flight(bindings,98).is_empty():_primary_cursors.append(16)
			if load("res://src/content/free_flight_definitions.gd").available(bindings):_primary_cursors.append(18)
			if load("res://src/content/free_campaign_definitions.gd").supported(bindings.mido_travel,19):_primary_cursors.append(19)
	return true

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var result := _identity.duplicate()
	result.objects=[]
	for index in _rows.size():
		var row: Dictionary = _rows[index].duplicate(true)
		row.vitals=_vitals[index].snapshot()
		row.destruction_pending=row.vitals.hull==0
		result.objects.append(row)
	return result

func collision_context(object_index: Variant) -> Dictionary:
	error=""
	if not valid_index(object_index): return fail("Collision target names an unavailable scenery body")
	var row: Dictionary = _rows[object_index]
	return {"base_content_id":_identity.base_content_id,"binding_id":_identity.binding_id,
		"object_index":object_index,"eligible":row.active and row.collision_enabled and _vitals[object_index].snapshot().hull>0,
		"path":"bounds","center":row.position,"half_extent":row.half_extent}

func supports_weapon_hit(weapon: Variant) -> bool:
	var kinds:=[0]
	if weapon is Dictionary and weapon.get("campaign_cursor") in _primary_cursors and TrainingWeapons.dispersed_primary(weapon):kinds.append(2)
	if weapon is Dictionary and weapon.get("campaign_cursor") in [18,19] and preload("res://src/content/ordinary_fitting_definitions.gd").ordinary(weapon):kinds=[0,1,2]
	error=WeaponHit.validate(weapon,_identity,_hit_policy,kinds)
	return error.is_empty()

func weapon_hit(object_index: Variant, weapon: Variant) -> Dictionary:
	if not supports_weapon_hit(weapon): return {}
	if not valid_index(object_index): return fail("Weapon hit names an unavailable scenery body")
	var before: float = _rows[object_index].motion_scalar
	# The ordinary scenery prelude runs even if a previous projectile slot has
	# already exhausted hull, or the damage permission rejects this hit.
	_rows[object_index].motion_scalar=0.0
	var result := normal_hit(object_index,weapon.ordinary_hit_policy.nonplayer_damage)
	if result.is_empty(): return {}
	result.motion_scalar_before=before
	result.motion_scalar_after=0.0
	return result

func normal_hit(object_index: Variant, amount: Variant) -> Dictionary:
	error=""
	if not valid_index(object_index): return fail("Normal hit names an unavailable scenery body")
	var row: Dictionary = _rows[object_index]
	var result: Dictionary = _vitals[object_index].normal_hit(amount,row.active and row.damage_allowed)
	if result.is_empty(): return fail(_vitals[object_index].error)
	if result.accepted:
		row.damaged=true
		row.hit_feedback=Vitals.single(row.hit_feedback+Vitals.single(0.065))
		# Source pool markers accumulate until their separate frame owner resets
		# them. Even an accepted zero-damage hit marks the shield branch.
		row.hit_layers[result.impact_layer]=true
	return result

func record_contact(object_index: Variant, incoming_velocity: Variant) -> bool:
	error=""
	if not valid_index(object_index) or not incoming_velocity is Vector3 or not incoming_velocity.is_finite():
		return reject("Scenery contact requires an existing body and finite incoming velocity")
	var impact := Vector3.ZERO
	for axis in 3: impact[axis]=Vitals.single(-incoming_velocity[axis])
	if not impact.is_finite(): return reject("Scenery contact exceeds source precision")
	_rows[object_index].contact=true
	_rows[object_index].impact_vector=impact
	return true

func set_permissions(object_index: Variant, active: Variant, damage_allowed: Variant) -> bool:
	error=""
	if not valid_index(object_index) or not active is bool or not damage_allowed is bool:
		return reject("Scenery permissions require an existing body and explicit booleans")
	if _rows[object_index].get("mined",false) and (active or damage_allowed):return reject("A mined asteroid cannot be reactivated")
	_rows[object_index].active=active;_rows[object_index].damage_allowed=damage_allowed
	return true

func retire_mined(object_index: int) -> bool:
	error=""
	if not valid_index(object_index):return reject("Mining names an unavailable asteroid")
	var row: Dictionary=_rows[object_index]
	if not row.active or row.get("mined",false) or _vitals[object_index].snapshot().hull<=0:return reject("The asteroid is already exhausted")
	# Represent the source negative-hull sentinel explicitly. Combat pools stay
	# nonnegative, and mining can never enter the zero-hull destruction path.
	row.mined=true;row.active=false;row.damage_allowed=false;row.collision_enabled=false
	return true

func has_pending_destruction() -> bool:
	for pool in _vitals:
		if pool.snapshot().hull==0: return true
	return false

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._identity=_identity.duplicate();copy._hit_policy=_hit_policy.duplicate(true)
	copy._primary_cursors=_primary_cursors.duplicate()
	copy._rows=_rows.duplicate(true)
	for pool in _vitals:
		var values: Dictionary = pool.snapshot()
		var duplicate := Vitals.new()
		duplicate.configure(values.hull,values.armor,values.shield)
		copy._vitals.append(duplicate)
	return copy

func clear() -> void:
	error="";_identity={};_hit_policy={};_rows=[];_vitals=[]
	_primary_cursors=[]

func valid_index(index: Variant) -> bool:
	return index is int and index>=0 and index<_rows.size()

func fail(message: String) -> Dictionary:
	reject(message);return {}

func reject(message: String) -> bool:
	error=message;return false

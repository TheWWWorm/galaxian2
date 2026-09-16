extends RefCounted
## Own one EMP bomb's motion and emit detached blast results. The flight owner
## supplies collision candidates and commits ammunition and systems damage.
## This component does not select targets, alter inventory or complete missions.
const Definitions=preload("res://src/content/emp_bombs_definitions.gd")
const Weapons=preload("res://src/simulation/weapon_loadout.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
var error:=""
var _weapon:={}
var _shot:={}
var _elapsed_ms:=0
var _next_id:=1

func configure(bindings: RefCounted,cat: RefCounted,item_id: Variant,equipment_ids: Array) -> bool:
	error=""
	if not Definitions.available(bindings) or cat==null or cat.content_id!=bindings.base_content_id or not item_id is int or item_id not in Definitions.VALUES.item_ids:return reject("This content has no supported EMP bomb")
	var resolver:=Weapons.new()
	if not resolver.configure(bindings,cat,bindings.base_content_id):return reject(resolver.error)
	var weapon:=resolver.resolve(item_id,equipment_ids)
	if weapon.is_empty() or weapon.category!=int(Definitions.VALUES.category) or weapon.kind!=int(Definitions.VALUES.kind):return reject("The equipped item is not an EMP bomb")
	var properties: Dictionary=cat.tables.items[item_id].properties
	var damage: Variant=properties.get(int(Definitions.VALUES.system_damage_property))
	var radius: Variant=properties.get(int(Definitions.VALUES.blast_radius_property))
	if not Vitals.integer(damage) or not Vitals.integer(radius) or radius<1:return reject("The EMP bomb lacks its systems damage or blast radius")
	weapon.system_damage=damage;weapon.radius=radius;weapon.launch_mode="emp_bomb"
	weapon.model_id=int(Definitions.VALUES.model_ids[Definitions.VALUES.item_ids.find(item_id)])
	_weapon=weapon;_shot={};_elapsed_ms=weapon.interval_ms
	return true

func trigger(pose: Transform3D,ammunition: Variant,targets: Variant,permitted: Variant=true) -> Dictionary:
	error=""
	if _weapon.is_empty():return fail("Configure the EMP bomb before firing")
	if not Vitals.integer(ammunition) or not permitted is bool or not pose.origin.is_finite() or not pose.basis.is_finite() or not _valid_targets(targets):return fail("Invalid EMP firing context")
	var result:=_event()
	if not permitted:return result
	# A second press detonates the live round even after the last round was used.
	if _shot.get("phase")=="flying":return detonate(_shot.id,targets)
	if ammunition==0 or _elapsed_ms<=_weapon.interval_ms:return result
	if _next_id>=Vitals.MAX_INTEGER:return fail("The EMP projectile handle limit was reached")
	var offset: Array=Definitions.VALUES.muzzle_offset
	var position:=pose*Vector3(offset[0],offset[1],offset[2])
	var direction:=Vectors.normalized(pose.basis.z)
	var velocity:=Vectors.scaled(direction,_weapon.speed_units_per_millisecond)
	if not position.is_finite() or not velocity.is_finite() or direction==Vector3.ZERO:return fail("EMP launch exceeds finite world coordinates")
	_shot={"id":_next_id,"phase":"flying","position":position,"previous_position":position,"velocity":velocity,"remaining_ms":_weapon.lifetime_ms}
	_next_id+=1;_elapsed_ms=0
	result.action="launched";result.ammunition_consumed=int(Definitions.VALUES.ammunition_per_launch);result.shot=_shot.duplicate(true)
	return result

func advance(delta_ms: Variant,targets: Variant) -> Dictionary:
	error=""
	if _weapon.is_empty() or not Vitals.integer(delta_ms) or _elapsed_ms>Vitals.MAX_INTEGER-delta_ms or not _valid_targets(targets):return fail("Invalid EMP frame or collision candidates")
	var result:=_event();var next: Dictionary=_shot.duplicate(true)
	if next.get("phase")=="detonated":next={}
	elif not next.is_empty():
		var position:=Vectors.added(next.position,Vectors.scaled(next.velocity,Vitals.single(float(delta_ms))))
		if not position.is_finite():return fail("EMP motion exceeds finite world coordinates")
		next.previous_position=next.position;next.position=position;next.remaining_ms-=delta_ms
		if next.remaining_ms<=0:
			var blast:=_blast(next,targets)
			if blast.is_empty():return {}
			next.phase="detonated";next.remaining_ms=int(Definitions.VALUES.detonated_lifetime)
			result.action="detonated";result.blast=blast
	_shot=next;_elapsed_ms+=delta_ms
	return result

func detonate(projectile_id: Variant,targets: Variant) -> Dictionary:
	error=""
	if _weapon.is_empty() or not projectile_id is int or _shot.get("id")!=projectile_id or _shot.get("phase")!="flying" or not _valid_targets(targets):return fail("EMP detonation requires a live projectile and current targets")
	var blast:=_blast(_shot,targets)
	if blast.is_empty():return {}
	_shot.phase="detonated";_shot.remaining_ms=int(Definitions.VALUES.detonated_lifetime)
	var result:=_event();result.action="detonated";result.blast=blast
	return result

func _blast(shot: Dictionary,targets: Array) -> Dictionary:
	var hits:=[]
	for target in targets:
		if not target.active or target.emp_immune:continue
		var difference: Vector3=target.position-shot.position
		var distance:=Vitals.single(sqrt(Vectors.dot(difference,difference)))
		if not is_finite(distance) or distance>Vitals.MAX_SHIELD:return fail("EMP target distance exceeds supported coordinates")
		var whole:=int(distance)
		if whole>=_weapon.radius:continue
		var fraction:=Vitals.single(Vitals.single(float(_weapon.radius-whole))/Vitals.single(float(_weapon.radius)))
		var damage:=int(Vitals.single(Vitals.single(float(_weapon.system_damage))*fraction))
		hits.append({"actor_id":target.actor_id,"system_damage":damage,"distance":whole})
	return {"base_content_id":_weapon.base_content_id,"binding_id":_weapon.binding_id,
		"projectile_id":shot.id,"item_id":_weapon.item_id,"position":shot.position,"hits":hits}

static func _valid_targets(targets: Variant) -> bool:
	if not targets is Array or targets.size()>4096:return false
	var ids:={}
	for target in targets:
		if not target is Dictionary or not Vitals.integer(target.get("actor_id")) or ids.has(target.actor_id):return false
		if not target.get("position") is Vector3 or not target.position.is_finite() or not target.get("active") is bool or not target.get("emp_immune") is bool:return false
		ids[target.actor_id]=true
	return true

static func _event() -> Dictionary:return {"action":"none","ammunition_consumed":0,"shot":{},"blast":{}}

func snapshot() -> Dictionary:
	return {"weapon":_weapon.duplicate(true),"shot":_shot.duplicate(true),"elapsed_ms":_elapsed_ms}

func fork() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._weapon=_weapon.duplicate(true);copy._shot=_shot.duplicate(true);copy._elapsed_ms=_elapsed_ms;copy._next_id=_next_id
	return copy

func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:reject(message);return {}

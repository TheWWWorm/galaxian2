extends RefCounted
## Per-projectile-slot impact clocks. A contact restarts time after sampling, so
## the last sampled pose survives until the following ordinary weapon update.
const Definitions=preload("res://src/content/projectile_impact_definitions.gd")
const Visuals=preload("res://src/simulation/projectile_visual_state.gd")
const AEM=preload("res://src/content/aem.gd")
const Ranges=preload("res://src/content/scenery_effect_resources.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Playback=preload("res://src/simulation/model_playback.gd")
const PATHS=["resources/data/assets/main/3d/meshes/fx/impact_000_lookat_anim_add.aem","resources/data/assets/main/3d/meshes/fx/impact_005_lookat_anim_add.aem"]
var error:=""
var _state:={}
var _identity: RefCounted
var _pending:=false
var _previous_elapsed:=0

func configure(bindings: RefCounted, library: RefCounted, world: Dictionary) -> bool:
	_state={};_identity=null;_pending=false;_previous_elapsed=0;error=""
	if bindings==null or library==null or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Impact models require matching original content")
	var rules: Dictionary=bindings.opening_staging.get("projectile_impacts",{})
	if not Definitions.parameters(rules):return reject("Ordinary impact presentation is unavailable")
	for key in ["base_content_id","binding_id"]:
		if world.get(key)!=bindings.get(key):return reject("Impact models belong to another world")
	if world.get("elapsed_ms")!=0:return reject("Impact models must join before time advances")
	var inputs:=Visuals.weapons(world)
	if inputs.is_empty():return reject("Impact models need configured weapons")
	var metadata:={};var weapons:=[];var seen:={}
	for entry in inputs:
		var weapon: Dictionary=entry.projectiles.get("weapon",{})
		if not Numbers.integer(weapon.get("item_id"),0,2147483647) or not Numbers.integer(weapon.get("projectile_capacity"),1,256):return reject("Invalid impact weapon")
		var index: int=rules.item_ids.find(float(weapon.item_id))
		if index<0:index=rules.item_ids.find(int(weapon.item_id))
		if index<0 or weapon.get("kind")!=rules.kinds[index] or weapon.get("category")!=0 or seen.has(entry.key):return reject("Impact weapon is outside the fresh ordinary population")
		seen[entry.key]=true
		for key in ["base_content_id","binding_id"]:
			if weapon.get(key)!=world[key]:return reject("Foreign impact weapon")
		var id:=int(rules.model_ids[index]);var path: String=bindings.resolve(id,"mesh")
		if path!=PATHS[index]:return reject("Unsupported impact model mapping")
		if not metadata.has(id):
			var reader:=AEM.new();var decoded:=reader.decode(library.read_resource(path,AEM.MAX_BYTES))
			if decoded.is_empty():return reject(reader.error)
			var timing:=Ranges.playback_range(decoded.surfaces)
			if timing.is_empty() or timing.end_ms<=0:return reject("Unsupported impact animation range")
			metadata[id]=timing
		var timing: Dictionary=metadata[id];var slots:=[]
		for slot in int(weapon.projectile_capacity):slots.append({"start_ms":timing.start_ms,"end_ms":timing.end_ms,"time_ms":timing.start_ms,"sample_time_ms":timing.start_ms,"playing":false,"position":Vector3.ZERO})
		weapons.append({"key":entry.key,"item_id":int(weapon.item_id),"kind":int(weapon.kind),"capacity":slots.size(),"model_id":id,"resource":path,"slots":slots})
	_state={"base_content_id":world.base_content_id,"binding_id":world.binding_id,"elapsed_ms":0,"rules":rules.duplicate(true),"weapons":weapons,"hits":[]}
	_identity=RefCounted.new()
	return true

func advance(delta_ms: Variant) -> bool:
	error=""
	if _state.is_empty() or _pending or not Numbers.integer(delta_ms,0,150):return reject("Invalid or unfinished impact frame")
	_previous_elapsed=_state.elapsed_ms
	for weapon in _state.weapons:
		for slot in weapon.slots:
			if slot.playing:
				Playback.advance([slot],int(delta_ms))
				# Source samples its final key even when this update stops playback.
				slot.sample_time_ms=slot.time_ms
	_state.elapsed_ms+=int(delta_ms);_state.hits=[];_pending=true
	return true

func apply_contacts(previous_world: Dictionary, primary_events: Array, npc_events: Array) -> bool:
	error=""
	if _state.is_empty() or not _pending or previous_world.get("elapsed_ms")!=_previous_elapsed:return reject("Impacts require this frame's preceding weapon slots")
	for key in ["base_content_id","binding_id"]:
		if previous_world.get(key)!=_state[key]:return reject("Impact contacts belong to another world")
	var inputs:=Visuals.weapons(previous_world)
	if inputs.size()!=_state.weapons.size():return reject("Impact weapon population changed")
	var by_key:={};var by_mount:={}
	for i in inputs.size():
		var input: Dictionary=inputs[i];var row: Dictionary=_state.weapons[i]
		if input.key!=row.key or input.projectiles.get("weapon",{}).get("item_id")!=row.item_id or not input.projectiles.get("slots") is Array or input.projectiles.slots.size()!=row.capacity:return reject("Impact weapon slots changed")
		by_key[input.key]=i
	for i in previous_world.get("primaries",{}).get("guns",[]).size():
		var gun: Dictionary=previous_world.primaries.guns[i]
		by_mount[int(gun.mount_id)]="player:%d"%i
	var events:=[];var seen:={}
	for event in primary_events:
		if not event is Dictionary or not Numbers.integer(event.get("mount_id"),1,2147483647) or not by_mount.has(int(event.mount_id)):return reject("Unknown impact primary owner")
		events.append({"key":by_mount[int(event.mount_id)],"contacts":event.get("contacts")})
	for event in npc_events:
		if not event is Dictionary or not Numbers.integer(event.get("actor_id"),0,2147483647):return reject("Unknown impact NPC owner")
		events.append({"key":"npc:%d"%int(event.actor_id),"contacts":event.get("contacts")})
	if events.size()!=inputs.size():return reject("Impact frame omitted a weapon contact pass")
	var staged: Dictionary=_state.duplicate(true)
	for event in events:
		if not by_key.has(event.key) or seen.has(event.key) or not event.contacts is Array:return reject("Invalid impact contact group")
		seen[event.key]=true
		var index: int=by_key[event.key];var row: Dictionary=staged.weapons[index]
		for contact in event.contacts:
			if not contact is Dictionary or not Numbers.integer(contact.get("slot"),0,row.capacity-1) or not Numbers.integer(contact.get("projectile_id"),1,2147483647) or not contact.get("geometry") is Dictionary or contact.geometry.get("hit")!=true:return reject("Invalid ordinary impact contact")
			var shot: Variant=inputs[index].projectiles.slots[int(contact.slot)]
			if not shot is Dictionary or shot.get("id")!=contact.projectile_id or not shot.get("position") is Vector3 or not shot.position.is_finite():return reject("Impact contact lost its original shot position")
			var slot: Dictionary=row.slots[int(contact.slot)]
			Playback.restart([slot]);slot.position=shot.position
			# Restart deliberately leaves sample_time_ms intact.
			staged.hits.append({"key":event.key,"slot":int(contact.slot),"projectile_id":int(contact.projectile_id),"position":shot.position})
	_state=staged;_pending=false
	return true

func snapshot() -> Dictionary:return _state.duplicate(true)
func presentation_identity() -> RefCounted:return _identity
func fork_for_frame() -> RefCounted:
	var next: RefCounted=get_script().new();next._state=_state.duplicate(true);next._identity=_identity;next._pending=_pending;next._previous_elapsed=_previous_elapsed;return next
func reject(message: String) -> bool:error=message;return false

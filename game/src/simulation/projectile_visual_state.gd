extends RefCounted
## Shared animation clocks for fresh ordinary projectile models. Projectile slots
## retain their physics owner; these clocks advance even while no shot is visible.
const Definitions=preload("res://src/content/projectile_visual_definitions.gd")
const AEM=preload("res://src/content/aem.gd")
const Ranges=preload("res://src/content/scenery_effect_resources.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Playback=preload("res://src/simulation/model_playback.gd")
const Training=preload("res://src/content/combat_training_visual_definitions.gd")
const PATHS={6756:"resources/data/assets/main/3d/meshes/fx/projectile_002_anim_add.aem",6795:"resources/data/assets/main/3d/meshes/fx/projectile_019_anim_add.aem",14600:"resources/data/assets/main/3d/meshes/fx/impact_000_lookat_anim_add.aem",14605:"resources/data/assets/main/3d/meshes/fx/impact_005_lookat_anim_add.aem"}
var error:=""
var _state: Dictionary={}
var _identity: RefCounted

func configure(bindings: RefCounted, library: RefCounted, world: Dictionary) -> bool:
	_state={};_identity=null;error=""
	if bindings==null or library==null or library.manifest.get("content_id")!=bindings.base_content_id: return reject("Projectile models require matching content")
	var rules: Dictionary=bindings.opening_staging.get("projectile_visuals",{})
	if not Definitions.parameters(rules): return reject("Ordinary projectile visuals are unavailable")
	for key in ["base_content_id","binding_id"]:
		if world.get(key)!=bindings.get(key): return reject("Projectile models belong to another world")
	if world.get("elapsed_ms")!=0:return reject("Projectile models must join before the world advances")
	var inputs:=weapons(world)
	if inputs.is_empty(): return reject("Projectile models require configured opening weapons")
	var metadata:={};var models:=[];var seen:={}
	for entry in inputs:
		var weapon: Dictionary=entry.projectiles.get("weapon",{})
		if not Numbers.integer(weapon.get("item_id"),0,2147483647) or not Numbers.integer(weapon.get("projectile_capacity"),1,256):return reject("Invalid projectile weapon declaration")
		var mapping:=model_mapping(bindings,weapon,entry.key,false)
		if mapping.is_empty() or seen.has(entry.key):return reject("Unsupported or duplicate ordinary projectile weapon")
		seen[entry.key]=true
		for key in ["base_content_id","binding_id"]:
			if weapon.get(key)!=world[key]:return reject("Projectile weapon has a foreign identity")
		var id: int=mapping.id;var path: String=bindings.resolve(id,"mesh")
		if path!=mapping.resource:return reject("Unsupported projectile model mapping")
		if not metadata.has(id):
			var reader:=AEM.new();var decoded:=reader.decode(library.read_resource(path,AEM.MAX_BYTES))
			if decoded.is_empty():return reject(reader.error)
			var timing:=Ranges.playback_range(decoded.surfaces,true)
			if timing.is_empty():return reject("Unsupported projectile animation range: "+path)
			metadata[id]=timing
		var timing: Dictionary=metadata[id]
		models.append({"key":entry.key,"item_id":int(weapon.item_id),"kind":int(weapon.kind),"capacity":int(weapon.projectile_capacity),"model_id":id,"resource":path,"captured_up":mapping.captured_up,"start_ms":timing.start_ms,"end_ms":timing.end_ms,"time_ms":timing.start_ms,"playing":true})
	_state={"base_content_id":world.base_content_id,"binding_id":world.binding_id,"models":models,"elapsed_ms":0,"rules":rules.duplicate(true)}
	_identity=RefCounted.new()
	return true

func advance(delta_ms: Variant) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(delta_ms,0,150):return reject("Invalid projectile animation frame")
	Playback.advance(_state.models,int(delta_ms),true)
	_state.elapsed_ms+=int(delta_ms)
	return true

func snapshot() -> Dictionary:return _state.duplicate(true)
func presentation_identity() -> RefCounted:return _identity
func fork_for_frame() -> RefCounted:
	var next: RefCounted=get_script().new();next._state=_state.duplicate(true);next._identity=_identity;return next
func reject(message: String) -> bool:error=message;return false

static func model_mapping(bindings: RefCounted, weapon: Dictionary, key: String, impact: bool) -> Dictionary:
	if weapon.get("campaign_cursor")==7:return Training.model(bindings.combat_training_visuals,weapon,key,impact)
	var rules: Dictionary=bindings.opening_staging.get("projectile_impacts" if impact else "projectile_visuals",{})
	for i in rules.get("item_ids",[]).size():
		if weapon.get("item_id")!=rules.item_ids[i] or weapon.get("kind")!=rules.kinds[i] or weapon.get("category")!=0:continue
		var id:=int(rules.model_ids[i])
		if not PATHS.has(id):return {}
		return {"id":id,"resource":PATHS[id],"captured_up":false}
	return {}

static func weapons(world: Dictionary) -> Array:
	var result:=[]
	if not world.get("primaries",{}) is Dictionary or not world.get("weapons",{}) is Dictionary:return []
	var primary: Variant=world.get("primaries",{}).get("guns",[])
	var actors: Variant=world.get("weapons",{}).get("actors",[])
	if not primary is Array or not actors is Array:return []
	for i in primary.size():
		if not primary[i] is Dictionary or not primary[i].get("projectiles") is Dictionary:return []
		result.append({"key":"player:%d"%i,"projectiles":primary[i].projectiles})
	for actor in actors:
		if not actor is Dictionary or not Numbers.integer(actor.get("actor_id"),0,2147483647) or not actor.get("projectiles") is Dictionary:return []
		result.append({"key":"npc:%d"%int(actor.actor_id),"projectiles":actor.projectiles})
	return result

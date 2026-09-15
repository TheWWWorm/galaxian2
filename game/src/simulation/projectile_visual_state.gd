extends RefCounted
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
## Shared animation clocks for fresh ordinary projectile models. Projectile slots
## retain their physics owner; these clocks advance even while no shot is visible.
const Definitions=preload("res://src/content/projectile_visual_definitions.gd")
const AEM=preload("res://src/content/aem.gd")
const Ranges=preload("res://src/content/scenery_effect_resources.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Playback=preload("res://src/simulation/model_playback.gd")
const Training=preload("res://src/content/combat_training_visual_definitions.gd")
const Fitting=preload("res://src/content/ordinary_fitting_definitions.gd")
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
	if inputs.is_empty() and not empty_ordinary_population(bindings,world): return reject("Projectile models require a configured weapon population")
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
	if weapon.get("campaign_cursor")==18 and key.begins_with("player:") and Fitting.available(bindings):return Fitting.model(bindings,weapon,impact)
	if weapon.get("campaign_cursor")==16:
		if not load("res://src/content/alioth_flight_definitions.gd").available(bindings):return {}
		if key.begins_with("player:"):
			var source:=weapon.duplicate(true);source.campaign_cursor=7
			return Training.model(bindings.combat_training_visuals,source,key,impact)
		if not key.begins_with("npc:") or not key.substr(4).is_valid_int() or weapon.get("nonplayer_source")!=true or weapon.get("category")!=0:return {}
		var id:=int(key.substr(4))
		if id<3 or id>9:return {}
		var void_weapon: Dictionary=bindings.mido_travel.alioth_attack.weapons["void"]
		if weapon.get("item_id")!=(int(void_weapon.item_id) if id<7 else 0):return {}
		var model:=int(void_weapon.impact_model_id if impact else void_weapon.model_resource_id) if id<7 else (ContractWorld.impact_model(bindings,0) if impact else int(bindings.early_contracts.ship_combat.weapons.factions[0].model_resource_id))
		var path: String=bindings.resolve(model,"mesh")
		return {} if path.is_empty() else {"id":model,"resource":path,"captured_up":false}
	if weapon.get("campaign_cursor") in [13,14,18]:
		if weapon.get("campaign_cursor")==18 and not load("res://src/content/free_flight_definitions.gd").available(bindings):return {}
		if not ContractWorld.available(bindings) or weapon.get("category")!=0:return {}
		if key.begins_with("player:"):
			var source:=weapon.duplicate(true);source.campaign_cursor=7
			return Training.model(bindings.combat_training_visuals,source,key,impact)
		if not key.begins_with("npc:") or not key.substr(4).is_valid_int() or int(key.substr(4))<0 or weapon.get("projectile_capacity")!=int(bindings.early_contracts.ship_combat.weapons.capacity) or weapon.get("nonplayer_source")!=true:return {}
		for row in bindings.early_contracts.ship_combat.weapons.factions:
			if int(row.item_id)!=weapon.get("item_id") or int(row.kind)!=weapon.get("kind"):continue
			var id:=ContractWorld.impact_model(bindings,int(row.item_id)) if impact else int(row.model_resource_id)
			var resource: String=bindings.resolve(id,"mesh")
			return {} if resource.is_empty() else {"id":id,"resource":resource,"captured_up":false}
		return {}
	if weapon.get("campaign_cursor") in [10,11,12]:return Training.local_model(bindings.combat_training_visuals,bindings.mido_travel,weapon,key,impact)
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
		if world.get("campaign_cursor") in [11,12,13,14,16,18] and actor.get("definition",{}).get("unarmed",false) and actor.projectiles.is_empty():continue
		result.append({"key":"npc:%d"%int(actor.actor_id),"projectiles":actor.projectiles})
	return result

static func empty_ordinary_population(bindings: RefCounted,world: Dictionary) -> bool:
	# An equipped owner can contain zero guns. Require its explicit identity
	# and well-formed unarmed traffic; malformed weapon packets also resolve
	# to an empty list and must not be mistaken for this supported population.
	if not Fitting.available(bindings) or world.get("campaign_cursor")!=18:return false
	var primary: Variant=world.get("primaries");var traffic: Variant=world.get("weapons")
	if not primary is Dictionary or not primary.get("guns") is Array or not primary.guns.is_empty() or not primary.get("loadout") is Dictionary:return false
	var loadout: Dictionary=primary.loadout
	for key in ["base_content_id","binding_id"]:
		if loadout.get(key)!=bindings.get(key):return false
	if loadout.get("campaign_cursor")!=18 or not loadout.get("slots") is Array or not loadout.get("equipment_ids") is Array:return false
	var ids:=[]
	for slot in loadout.slots:
		if slot==null:continue
		if not slot is Dictionary or not Numbers.integer(slot.get("category"),1,3) or not Numbers.integer(slot.get("item_id"),0,2147483647):return false
		ids.append(slot.item_id)
	if ids!=loadout.equipment_ids or not traffic is Dictionary or not traffic.get("actors") is Array:return false
	var seen:=[]
	for actor in traffic.actors:
		if not actor is Dictionary or not Numbers.integer(actor.get("actor_id"),0,2147483647) or seen.has(actor.actor_id):return false
		if not actor.get("definition") is Dictionary or actor.definition.get("unarmed")!=true or not actor.get("projectiles") is Dictionary or not actor.projectiles.is_empty():return false
		seen.append(actor.actor_id)
	return true

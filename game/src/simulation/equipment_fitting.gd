extends RefCounted
## Resolve fitting against the same native owners used by flight. Unsupported
## devices keep an explicit reason; stock availability never grants behavior.
const Rules=preload("res://src/content/ordinary_fitting_definitions.gd")
const Stats=preload("res://src/simulation/equipment_stats.gd")
const Vehicle=preload("res://src/simulation/vehicle_response.gd")
const Weapons=preload("res://src/simulation/weapon_loadout.gd")
const Projectiles=preload("res://src/simulation/ordinary_projectiles.gd")
const Hits=preload("res://src/simulation/ordinary_weapon_hit.gd")
const Audio=preload("res://src/simulation/weapon_audio.gd")
const Recharge=preload("res://src/simulation/shield_recharge.gd")
const Secondaries=preload("res://src/simulation/secondary_weapons.gd")
const BurstResources=preload("res://src/content/emp_detonation_resources.gd")
const Tracks=preload("res://src/content/animation_tracks.gd")
const Materials=preload("res://src/presentation/material_library.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const AEM=preload("res://src/content/aem.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Surface=preload("res://src/presentation/animated_additive_model.gd")
const Tractor=preload("res://src/simulation/tractor_recovery.gd")
var error:=""

func prepare_assets(bindings: RefCounted,cat: RefCounted,library: RefCounted) -> Dictionary:
	error=""
	if not Rules.available(bindings) or library==null or cat==null or library.manifest.get("content_id")!=bindings.base_content_id or cat.content_id!=bindings.base_content_id:return fail("Fitting requires its original content assets")
	var resources:={};var items:={}
	for item in cat.tables.items:
		if item.arrays[2][3]!=0:continue
		var id:=int(item.id);var mapping:=Rules.primary(bindings.mido_travel.ordinary_fitting,id,int(item.arrays[2][5]))
		if mapping.is_empty():continue
		items[id]=""
		for key in ["projectile_model_id","impact_model_id"]:
			var model: int=mapping[key]
			if not resources.has(model):
				var path: String=bindings.resolve(model,"mesh");var reader:=AEM.new()
				var decoded:=reader.decode(library.read_resource(path,AEM.MAX_BYTES))
				if decoded.is_empty():return fail("An original weapon model could not be read: "+path)
				var sampler:=Sampler.new()
				var supported: bool=decoded.surfaces.all(func(surface):return Surface.supported_surface(surface)) and sampler.configure(decoded.surfaces,key=="projectile_model_id")
				supported=supported and bindings.material_for_mesh(path,"high").get("render_type")==2
				resources[model]="" if supported else "This weapon's animated model is not yet supported"
			if not resources[model].is_empty():items[id]=resources[model]
	if Secondaries.Definitions.available(bindings):
		# Stock presence is not a capability. Verify the same original static
		# body and animated burst used by the actual equipped flight renderer.
		var bursts:=BurstResources.new()
		if not bursts.configure(library,bindings):return fail(bursts.error)
		var models: Array=Secondaries.Bomb.Definitions.VALUES.model_ids
		var ids: Array=Secondaries.Definitions.VALUES.item_ids
		for index in ids.size():
			var model:=int(models[index])
			if not resources.has(model):
				var path: String=bindings.resolve(model,"mesh");var reader:=AEM.new()
				var decoded:=reader.decode(library.read_resource(path,AEM.MAX_BYTES))
				if decoded.is_empty():return fail("An original EMP body could not be read: "+path)
				var supported: bool=model==14684 and path.ends_with("/misc/bomb_emp_a.aem") and Tracks.has_identity_tracks(decoded.surfaces) and Materials.supports(bindings.material_for_mesh(path,"high"))
				resources[model]="" if supported else "This EMP body's visual behavior is not yet supported"
			items[int(ids[index])]=resources[model]
	if Tractor.Definitions.available(bindings):
		var rules: Dictionary=bindings.mido_travel.tractor_recovery
		for item in cat.tables.items:
			if item.arrays[2][3]!=3 or item.arrays[2][5]!=int(rules.equipment.category) or item.properties.get(int(rules.equipment.mode_property))!=0:continue
			var tractor:=Tractor.new()
			var loadout:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
				"ship_id":int(rules.pull.supported_player_hulls[0]),"equipment_ids":[int(item.id)]}
			items[int(item.id)]="" if tractor.configure(bindings,cat,loadout,library) else "This tractor's beam is not yet supported"
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"items":items}

func inspect(bindings: RefCounted,cat: RefCounted,loadout: Dictionary,assets: Dictionary) -> Dictionary:
	error=""
	if not Rules.available(bindings) or cat==null or cat.content_id!=bindings.base_content_id or loadout.get("base_content_id")!=bindings.base_content_id or loadout.get("binding_id")!=bindings.binding_id:return fail("Fitting belongs to another content identity")
	if assets.get("base_content_id")!=bindings.base_content_id or assets.get("binding_id")!=bindings.binding_id or not assets.get("items") is Dictionary:return fail("Fitting lost its verified weapon assets")
	var ship: Variant=loadout.get("ship_id")
	if not Numbers.integer(ship,0,cat.tables.ships.size()-1):return fail("The equipped ship is absent from the catalogue")
	var weapon:=Weapons.new()
	if not weapon.configure(bindings,cat,bindings.base_content_id):return fail(weapon.error)
	var ids: Array=loadout.equipment_ids
	var support:={}
	for item in cat.tables.items:
		var id:=int(item.id)
		support[id]=_item_reason(bindings,cat,weapon,id,ids,int(ship))
		if support[id].is_empty() and item.arrays[2][3] in [0,1]:support[id]=assets.items.get(id,"This weapon's model is unavailable")
		if support[id].is_empty() and item.arrays[2][3]==3 and item.arrays[2][5]==13:support[id]=assets.items.get(id,"This tractor's beam is unavailable")
	for id in ids:
		if not support.has(id) or not support[id].is_empty():return fail("Installed equipment is unavailable: "+str(support.get(id,"unknown item")))
	var slots: Variant=loadout.get("slots")
	var secondary_slots: bool=slots is Array and slots.any(func(slot):return slot is Dictionary and slot.get("category")==1)
	if secondary_slots or ids.any(func(id):return cat.tables.items[id].arrays[2][3]==1):
		var secondaries:=Secondaries.new()
		if not secondaries.configure(bindings,cat,loadout):return fail(secondaries.error)
	var pools:=Stats.resolve_capacities(cat.tables.items,ids,bindings.opening_actors.player_initialization)
	var repair: Dictionary=bindings.opening_actors.player_initialization.repair
	var hull:=Stats.resolve_ship_hull(cat.tables.ships[ship].fields[int(repair.base_hull_field)],repair.initial_upgrades,repair)
	var device:=Stats.resolve_repair_device(cat.tables.items,ids,repair)
	var capacity:=Stats.cargo_capacity(bindings,cat,loadout)
	var passengers:=Stats.capacity_sum(cat,ids,int(Rules.VALUES.passenger_subtype),int(Rules.VALUES.passenger_property))
	var vehicle:=Vehicle.new()
	if not vehicle.configure(bindings,cat,bindings.base_content_id):return fail(vehicle.error)
	var handling:=vehicle.resolve(ship,[],ids)
	if pools.is_empty() or hull<0 or device.is_empty() or capacity<0 or passengers<0 or handling.is_empty():return fail("Equipment produces unsupported ship capacities or handling")
	return {"support":support,"stats":{"hull":hull,"armor":pools.armor,"shield":pools.shield,
		"cargo_capacity":capacity,"passenger_capacity":passengers,"repair_mode":device.mode,
		"response_factor":handling.response_factor,"handling_bonus_percent":handling.equipment_percent}}

func _item_reason(bindings: RefCounted,cat: RefCounted,resolver: RefCounted,id: int,ids: Array,ship: int) -> String:
	var item: Dictionary=cat.tables.items[id]
	var category: int=item.arrays[2][3];var subtype: int=item.arrays[2][5]
	var properties: Dictionary=item.properties
	if category==0:
		var weapon: Dictionary=resolver.resolve(id,ids)
		if weapon.is_empty():return "This weapon's firing behavior is not yet supported"
		var projectiles:=Projectiles.new()
		if not projectiles.configure(weapon):return "This weapon's firing behavior is not yet supported"
		var reason:=Hits.validate(weapon,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id},bindings.weapon_parameters.ordinary_hit_policy,[0,1,2])
		if not reason.is_empty():return "This weapon's damage effects are not yet supported"
		if Rules.model(bindings,weapon,false).is_empty() or Rules.model(bindings,weapon,true).is_empty():return "This primary weapon's visual behavior is not yet supported"
		if Audio.player_entries(bindings.weapon_parameters.audio,cat.tables.items,[weapon]).size()!=1:return "This weapon's audio is not yet supported"
		return ""
	if category==1:
		if not Secondaries.Definitions.available(bindings) or id not in Secondaries.Definitions.VALUES.item_ids:return "This secondary weapon's flight behavior is not yet supported"
		var bomb:=Secondaries.Bomb.new()
		return "" if bomb.configure(bindings,cat,id,ids) else "This EMP bomb's firing behavior is not yet supported"
	if category!=3:return "Fitting this equipment is not yet supported"
	var rule: Dictionary=bindings.opening_actors.player_initialization
	match subtype:
		9:
			var pools:=Stats.resolve_capacities(cat.tables.items,[id],rule)
			if pools.is_empty():return "The shield has no supported capacity"
			var charge:=Recharge.new()
			var duration: Variant=properties.get(int(rule.recharge.equipment_property))
			if not Numbers.integer(duration,0,2147483647) or not charge.configure(rule.recharge,pools.shield,duration):return "The shield has no supported recharge duration"
		10:
			if Stats.resolve_capacities(cat.tables.items,[id],rule).is_empty():return "The armor has no supported capacity"
		12,20:
			var property:=int(Rules.VALUES.cargo_property if subtype==12 else Rules.VALUES.passenger_property)
			if not Numbers.integer(properties.get(property),0,2147483647):return "The equipment has no supported capacity"
		13:
			if not Tractor.Definitions.available(bindings):return "Tractor recovery is not yet supported by this content pack"
			var tractor: Dictionary=bindings.mido_travel.tractor_recovery
			if not tractor.pull.supported_player_hulls.any(func(hull):return int(hull)==ship):return "Tractor recovery is not yet supported for this ship"
			if properties.get(int(tractor.equipment.mode_property))!=0:return "Automatic tractor recovery is not yet supported"
		15:
			if Stats.resolve_repair_device(cat.tables.items,[id],rule.repair).is_empty():return "The repair device is unavailable"
		16:
			if not Numbers.integer(properties.get(int(bindings.vehicle_response.equipment_percent_property)),0,2147483647):return "The handling upgrade is unavailable"
		17:
			var scanner: Dictionary=bindings.opening_staging.npc_scanner
			if properties.get(int(scanner.cargo_property))==1:return "Cargo inspection of ordinary traffic is not yet supported"
			if not Numbers.integer(properties.get(int(scanner.duration_property)),1,2147483647):return "The scanner acquisition duration is unavailable"
		19:
			for property in [bindings.mining_drill.stability_property,bindings.mining_drill.rate_property]:
				if not Numbers.integer(properties.get(int(property)),1,100000):return "The drill performance is unavailable"
		28:
			for property in [bindings.weapon_parameters.interval_percent_property,bindings.weapon_parameters.damage_percent_property]:
				if not Weapons.signed_integer(properties.get(int(property))):return "The weapon modifier is unavailable"
		_:
			return "This device's flight behavior is not yet supported"
	return ""

func fail(message: String) -> Dictionary:error=message;return {}

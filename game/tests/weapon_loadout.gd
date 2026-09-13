extends SceneTree
const Resolver = preload("res://src/simulation/weapon_loadout.gd")
const Definitions = preload("res://src/content/weapon_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
const Opening = preload("res://src/simulation/opening_loadout.gd")
var failures := 0

func _initialize() -> void:
	var bindings := Bindings.new()
	bindings.base_content_id="a".repeat(64)
	bindings.binding_id="b".repeat(64)
	bindings.weapon_parameters=parameters()
	var catalogues := Catalogues.new()
	catalogues.content_id=bindings.base_content_id
	catalogues.tables.items=[item(0,0,{49:6,51:380,52:2000,53:20}),item(3,26,{79:-10,80:20}),item(3,26,{79:20,80:-10}),item(1,5,{49:70,51:2000,52:6000,53:8}),item(3,26,{79:20,80:-150})]
	var resolver := Resolver.new()
	check(resolver.resolve(0,[]).is_empty() and not resolver.error.is_empty(),"Unconfigured weapon resolution accepted")
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	check(resolver.resolve(0,[]).launch_mode=="unsupported","Legacy scalar declarations inferred a launch path")
	bindings.weapon_parameters.launch_modes={"alternate_item_ids":[0.0,3.0],"provenance":{}}
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	check(resolver.resolve(0,[]).launch_mode=="alternate","JSON float IDs did not match integer catalogue indices")
	bindings.weapon_parameters=parameters()
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	check_values(resolver,0,[],6,380,2000,20)
	check_values(resolver,0,[1],7,418,2000,20)
	check_values(resolver,0,[2],5,304,2000,20)
	check_values(resolver,0,[1,2],5,304,2000,20)
	check_values(resolver,0,[2,1],7,418,2000,20)
	check_values(resolver,3,[1,2],70,2000,6000,8)
	check_values(resolver,0,[4],6,212,2000,20)
	var detached: Dictionary = resolver.resolve(0,[])
	detached.damage=999
	catalogues.tables.items[0].properties[49]=20
	bindings.weapon_parameters.damage_property=999
	check_values(resolver,0,[],6,380,2000,20)
	bindings.weapon_parameters=parameters()
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	check(resolver.resolve(0,[4]).is_empty(),"Negative effective damage silently accepted")
	catalogues.tables.items[0].properties[49]=6
	bindings.weapon_parameters.missing_multiplier=-0.5
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	check_values(resolver,0,[4],6,304,2000,20)
	bindings.weapon_parameters=parameters()
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	for bad in [-1,5,true,0.0,"0",null]:
		check(resolver.resolve(bad,[]).is_empty() and not resolver.error.is_empty(),"Invalid weapon index accepted")
		check(resolver.resolve(0,[bad]).is_empty() and not resolver.error.is_empty(),"Invalid installed index accepted")
	check(resolver.resolve(1,[]).is_empty(),"Equipment resolved as a weapon")
	for bad in [-1,0.5,true,"1",null]:
		catalogues.tables.items[0].properties[49]=bad
		check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
		check(resolver.resolve(0,[]).is_empty(),"Malformed damage property accepted")
	for field in [49,51,52,53]:
		catalogues.tables.items[0]=item(0,0,{49:6,51:380,52:2000,53:20})
		catalogues.tables.items[0].properties.erase(field)
		check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
		check(resolver.resolve(0,[]).is_empty(),"Missing weapon property inferred")
	check(not resolver.configure(bindings,catalogues,"c".repeat(64)) and resolver.binding_id.is_empty(),"Foreign content retained weapon state")
	check(resolver.resolve(0,[]).is_empty(),"Failed configuration retained weapons")
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("Weapon loadout checks: %d failures" % failures)
	quit(1 if failures else 0)

func parameters() -> Dictionary:
	return {"damage_property":49,"interval_property":51,"lifetime_property":52,"speed_property":53,"interval_percent_property":79,"damage_percent_property":80,"low_damage_threshold":10,"item_type_value_index":5,"item_category_value_index":3,"primary_category":0,"modifier_type":26,"percent_divisor":100.0,"default_multiplier":1.0,"missing_multiplier":-979797952.0,"low_damage_interval_scale":0.699999988079071}

func item(category: int, kind: int, properties: Dictionary) -> Dictionary:
	return {"arrays":[[],[],[0,0,1,category,2,kind]],"properties":properties}

func check_values(resolver: RefCounted, id: int, equipment: Array, damage: int, interval: int, lifetime: int, speed: float) -> void:
	var result: Dictionary = resolver.resolve(id,equipment)
	check(not result.is_empty(),resolver.error)
	if result.is_empty(): return
	check(result.damage==damage and result.interval_ms==interval and result.lifetime_ms==lifetime and result.speed_units_per_millisecond==speed,"Incorrect resolved weapon: "+str(result))

func check_profile(content: String, binding_path: String) -> void:
	var library := Library.new()
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(binding_path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error)
		return
	var data: Dictionary = bindings.weapon_parameters
	check(not data.is_empty(),"Original pack has no weapon declarations")
	if data.is_empty(): return
	var resolver := Resolver.new()
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	var opening := Opening.new()
	check(opening.configure(bindings,catalogues,catalogues.content_id),opening.error)
	var state: Dictionary = opening.snapshot()
	for slot in state.slots:
		if slot!=null and slot.category==0: check_values(resolver,slot.item_id,state.equipment_ids,6,380,2000,20)
	check_values(resolver,36,state.equipment_ids,70,2000,6000,8)
	check_values(resolver,2,[186],5,304,2000,20)
	check_values(resolver,2,[187],7,418,2000,20)
	var supported := 0
	var unsupported := []
	for row in catalogues.tables.items:
		if row.arrays[2][3]>2: continue
		if resolver.resolve(row.id,[]).is_empty(): unsupported.append(row.id)
		else: supported+=1
	print(library.manifest.profile.edition,": ",supported," weapon scalar records resolved; unsupported IDs: ",unsupported)
	var header: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(binding_path.path_join("bindings.json")))
	var architecture: String = header.architecture
	var size := int(header.source_executable_bytes)
	check(Definitions.validate(data,size,architecture,bindings.vehicle_response,bindings.opening_loadout).is_empty(),"Valid original weapon provenance rejected")
	for key in Definitions.FIELDS:
		var bad := data.duplicate(true)
		bad[key]=true
		check(not Definitions.validate(bad,size,architecture,bindings.vehicle_response,bindings.opening_loadout).is_empty(),"Boolean parameter accepted")
	for key in data.provenance:
		var bad := data.duplicate(true)
		bad.provenance[key].bytes+=1
		check(not Definitions.validate(bad,size,architecture,bindings.vehicle_response,bindings.opening_loadout).is_empty(),"Malformed provenance accepted: "+key)
	if data.has("launch_modes") and not data.launch_modes.is_empty():
		for ids in [[],[true,3],[9,9],[-1,3],[0.5,3]]:
			var bad := data.duplicate(true)
			bad.launch_modes.alternate_item_ids=ids
			check(not Definitions.validate(bad,size,architecture,bindings.vehicle_response,bindings.opening_loadout).is_empty(),"Malformed launch IDs accepted")
		for key in data.launch_modes.provenance:
			var bad := data.duplicate(true)
			bad.launch_modes.provenance[key].bytes+=1
			check(not Definitions.validate(bad,size,architecture,bindings.vehicle_response,bindings.opening_loadout).is_empty(),"Malformed launch provenance accepted")
	if data.has("projectile_capacity") and not data.projectile_capacity.is_empty():
		for value in [0,4097,true,1.5,null]:
			var bad := data.duplicate(true)
			bad.projectile_capacity.slots=value
			check(not Definitions.validate(bad,size,architecture,bindings.vehicle_response,bindings.opening_loadout).is_empty(),"Malformed projectile capacity accepted")
		for key in data.projectile_capacity.provenance:
			var bad := data.duplicate(true)
			bad.projectile_capacity.provenance[key].bytes+=1
			check(not Definitions.validate(bad,size,architecture,bindings.vehicle_response,bindings.opening_loadout).is_empty(),"Malformed capacity provenance accepted")
		var disconnected := data.duplicate(true)
		disconnected.projectile_capacity.provenance.item_classification.offset+=1
		check(not Definitions.validate(disconnected,size,architecture,bindings.vehicle_response,bindings.opening_loadout).is_empty(),"Capacity from another item classification accepted")
	if not data.get("collision_bounds",{}).is_empty():
		for key in data.collision_bounds.provenance:
			for field in ["bytes","offset"]:
				var bad := data.duplicate(true)
				bad.collision_bounds.provenance[key][field]+=1
				# Wrapper location alone is metadata; its link was checked by the reader.
				if key=="wrapper" and field=="offset": continue
				check(not Definitions.validate(bad,size,architecture,bindings.vehicle_response,bindings.opening_loadout).is_empty(),"Invalid bounds proof accepted: "+key+" "+field)
		for bounds in [null,{"mode":"fixed","provenance":{}},{"mode":"target","provenance":{},"extra":1}]:
			var bad := data.duplicate(true)
			bad.collision_bounds=bounds
			check(not Definitions.validate(bad,size,architecture,bindings.vehicle_response,bindings.opening_loadout).is_empty(),"Invalid collision bounds accepted")
	check(Definitions.validate({},size,architecture,{},{}).is_empty(),"Explicit unsupported scope rejected")
	check(not Definitions.validate(null,size,architecture,{},{}).is_empty(),"Missing scope accepted")
	check_pack_versions(bindings,library.manifest,binding_path,header)
	check(not bindings.open("/unavailable-weapon-binding-pack",library.manifest) and bindings.weapon_parameters.is_empty(),"Failed open retained weapon declarations")

func check_pack_versions(bindings: RefCounted, base: Dictionary, source: String, header: Dictionary) -> void:
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("registrations.json")))
	var directory := "user://tests/weapons-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	check(DirAccess.make_dir_recursive_absolute(directory)==OK,"Cannot create binding test directory")
	var scenarios := ["v33","v34","unsupported","missing","malformed"]
	if header.reader in ["resource-registration-v35","resource-registration-v36","resource-registration-v37","resource-registration-v38","resource-registration-v39","resource-registration-v40","resource-registration-v41", "resource-registration-v42"]: scenarios.append_array(["v35","missing_launch"])
	if header.reader in ["resource-registration-v36","resource-registration-v37","resource-registration-v38","resource-registration-v39","resource-registration-v40","resource-registration-v41", "resource-registration-v42"]: scenarios.append("missing_capacity")
	if header.reader in ["resource-registration-v39","resource-registration-v40","resource-registration-v41", "resource-registration-v42"]: scenarios.append("missing_hit_policy")
	if header.reader in ["resource-registration-v40","resource-registration-v41", "resource-registration-v42"]: scenarios.append("missing_bounds")
	for scenario in scenarios:
		var body := original.duplicate(true)
		var metadata := header.duplicate(true)
		if scenario in ["v33","v34","v35","unsupported"]:
			# A partial/older pack cannot retain newer world owners whose proof
			# requires the weapon capability being removed. Keep independent
			# catalogue, scene and equipment declarations available for browsing.
			body.opening_actors={}
			body.opening_staging={}
			body.damage_particles={}
			body.weapon_parameters.erase("audio")
			body.weapon_parameters.erase("player_hit_policy")
		if scenario in ["v33","v34","v35"]:
			body.opening_dialogue.erase("voice")
			body.vehicle_response.erase("audio")
		if scenario=="v33":
			body.reader="resource-registration-v33"
			metadata.reader=body.reader
			body.erase("weapon_parameters")
		elif scenario=="v34":
			body.reader="resource-registration-v34"
			metadata.reader=body.reader
			body.weapon_parameters.erase("launch_modes")
			body.weapon_parameters.erase("projectile_capacity")
			body.weapon_parameters.erase("ordinary_hit_policy")
			body.weapon_parameters.erase("collision_bounds")
		elif scenario=="v35":
			body.reader="resource-registration-v35"
			metadata.reader=body.reader
			body.weapon_parameters.erase("projectile_capacity")
			body.weapon_parameters.erase("ordinary_hit_policy")
			body.weapon_parameters.erase("collision_bounds")
		elif scenario=="unsupported": body.weapon_parameters={}
		elif scenario=="missing": body.erase("weapon_parameters")
		elif scenario=="missing_launch": body.weapon_parameters.erase("launch_modes")
		elif scenario=="missing_bounds": body.weapon_parameters.erase("collision_bounds")
		elif scenario=="missing_hit_policy": body.weapon_parameters.erase("ordinary_hit_policy")
		elif scenario=="missing_capacity": body.weapon_parameters.erase("projectile_capacity")
		else: body.weapon_parameters.damage_property=true
		var serialized := JSON.stringify(body,"",true,true)
		metadata.records_sha256=serialized.sha256_text()
		metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n" % [metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file := FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE)
		file.store_string(serialized)
		file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(metadata))
		file.close()
		check(bindings.open(source,base),bindings.error)
		var accepted: bool = bindings.open(directory,base)
		if scenario in ["v33","unsupported"]:
			check(accepted and bindings.weapon_parameters.is_empty() and not bindings.opening_loadout.is_empty(),"Compatible pack rejected: "+scenario+": "+bindings.error)
		elif scenario=="v34":
			check(accepted and not bindings.weapon_parameters.is_empty() and not bindings.weapon_parameters.has("launch_modes"),"Legacy v34 weapon parameters rejected")
		elif scenario=="v35":
			check(accepted and bindings.weapon_parameters.has("launch_modes") and not bindings.weapon_parameters.has("projectile_capacity"),"Legacy v35 weapon parameters rejected")
		else:
			check(not accepted and "weapon" in bindings.error.to_lower(),"Invalid weapon scope accepted or wrong failure: "+scenario+": "+bindings.error)
			check(bindings.weapon_parameters.is_empty() and bindings.records.is_empty() and bindings.opening_loadout.is_empty() and bindings.binding_id.is_empty(),"Failed pack retained staged state")
	DirAccess.remove_absolute(directory.path_join("registrations.json"))
	DirAccess.remove_absolute(directory.path_join("bindings.json"))
	DirAccess.remove_absolute(directory)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)

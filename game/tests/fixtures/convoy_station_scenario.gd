extends RefCounted
## Private test checkpoint of the actual four-job station, never a player save.
## Only these four native state owners may be restored. No script path in the
## capture can select code; originals and imported bindings remain external.
const TYPES=[preload("res://src/simulation/station_entry.gd"),preload("res://src/simulation/station_equipment.gd"),preload("res://src/simulation/contract_session.gd"),preload("res://src/simulation/lounge_cache.gd")]
const EquipmentScenario=preload("res://tests/fixtures/equipment_scenario.gd")
var error:=""

static func hashes() -> Dictionary:
	var result:=EquipmentScenario.producer_hashes()
	for script in TYPES:result[script.resource_path]=FileAccess.get_sha256(script.resource_path)
	return result

func capture(path: String,station: RefCounted,bindings: RefCounted) -> bool:
	error=""
	if not private_path(path) or FileAccess.file_exists(path):return reject("Use a new private convoy checkpoint path")
	if station.get_script()!=TYPES[0] or not accepts(station.snapshot(),bindings):return reject("Capture requires the earned station accepted by this scenario")
	var data:={"schema":1,"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"producers":hashes(),"snapshot":station.snapshot(),"owner":encode(station)}
	if not error.is_empty():return false
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return reject("Cannot write private convoy checkpoint")
	file.store_var(data);file.close();return true

func open(path: String,bindings: RefCounted) -> RefCounted:
	error=""
	if not private_path(path):reject("Keep convoy checkpoints outside engine source");return null
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>8*1024*1024:reject("Missing or oversized convoy checkpoint");return null
	var data: Variant=file.get_var(false);file.close()
	if not data is Dictionary or data.get("schema")!=1 or data.get("base_content_id")!=bindings.base_content_id or data.get("binding_id")!=bindings.binding_id or data.get("producers")!=hashes():reject("Convoy checkpoint identity or producers changed; capture the earned station again");return null
	if not data.get("snapshot") is Dictionary or not accepts(data.snapshot,bindings):reject("The checkpoint has not earned the four-job handoff");return null
	var restored: RefCounted=decode(data.get("owner"))
	if restored==null or restored.get_script()!=TYPES[0] or restored.snapshot()!=data.snapshot:reject("Convoy checkpoint differs from its captured station");return null
	return restored

func encode(owner: RefCounted) -> Dictionary:
	if owner==null:return {}
	var kind:=TYPES.find(owner.get_script())
	if kind<0:reject("Unsupported checkpoint owner");return {}
	var fields:={}
	for p in owner.get_property_list():
		if not (int(p.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE) or not String(p.name).begins_with("_"):continue
		var value: Variant=owner.get(p.name)
		fields[p.name]={"owner":encode(value)} if value is Object else {"value":value}
	return {"kind":kind,"fields":fields}

func decode(data: Variant) -> RefCounted:
	if not data is Dictionary or not data.get("kind") is int or data.kind<0 or data.kind>=TYPES.size() or not data.get("fields") is Dictionary:return null
	var owner: RefCounted=TYPES[data.kind].new()
	var names:=[]
	for p in owner.get_property_list():
		if int(p.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE and String(p.name).begins_with("_"):names.append(String(p.name))
	if data.fields.size()!=names.size():return null
	for name in names:
		var field: Variant=data.fields.get(name)
		if not field is Dictionary or field.size()!=1:return null
		if field.has("owner"):
			var child:=decode(field.owner)
			if child==null:return null
			owner.set(name,child)
		elif field.has("value"):owner.set(name,field.value)
		else:return null
	return owner

static func private_path(path: String) -> bool:
	var resources:=ProjectSettings.globalize_path("res://").trim_suffix("/")
	# Export templates have no filesystem path for the embedded resource pack.
	var engine:=OS.get_executable_path().get_base_dir() if resources.is_empty() else resources.get_base_dir()
	return path.is_absolute_path() and not path.simplify_path().begins_with(engine+"/")

func accepts(state: Dictionary,bindings: RefCounted) -> bool:return earned(state,bindings)

static func earned(state: Dictionary,bindings: RefCounted) -> bool:
	return state.get("base_content_id")==bindings.base_content_id and state.get("binding_id")==bindings.binding_id and state.get("campaign_cursor")==13 and state.get("phase")=="contracts_required" and state.get("loadout",{}).get("station_id")==79 and state.get("completed_side_missions")==4 and state.get("contracts",{}).get("completed_side_missions")==4 and state.get("progress")==state.get("contracts",{}).get("progress")

func reject(message: String) -> bool:error=message;return false

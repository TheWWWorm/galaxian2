extends "res://src/simulation/station_targeting.gd"
## Mission29's environment-slot0 player lock. The flight supplies its live
## station body and owner gates; radio observes only mother_ship_locked.
const Probe=preload("res://src/content/void_probe_definitions.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const VoidWorld=preload("res://src/simulation/void_environment.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")

func configure(bindings: RefCounted,catalogues: RefCounted,loadout: Dictionary,void_environment: RefCounted,frame_radii: Vector2) -> bool:
	error=""
	if bindings==null or not Library.valid_hash(bindings.get("base_content_id")) or not Library.valid_hash(bindings.get("binding_id")) or not bindings.get("mido_travel") is Dictionary or not Probe.parameters(bindings.mido_travel.get("void_probe",{})):
		return reject("Void station targeting requires source mission29 declarations")
	if not catalogues is Catalogues or catalogues.content_id!=bindings.base_content_id or not void_environment is VoidWorld:
		return reject("Void station targeting requires matching catalogues and world")
	var world: Dictionary=void_environment.snapshot()
	if world.get("base_content_id")!=bindings.base_content_id or world.get("binding_id")!=bindings.binding_id or world.get("campaign_cursor")!=29 or world.get("station_id")!=-1 or world.get("system_id")!=-1:
		return reject("Void station targeting requires its selected Void29 world")
	var station: Dictionary=void_environment.object_state(0)
	if station.get("index")!=0 or station.get("kind")!="station" or not station.get("pose") is Transform3D or not Flight.rigid_pose(station.pose) or not void_environment.object_state(1).is_empty() or void_environment.object_state(2).get("kind")!="gate":
		return reject("Void station targeting requires its original environment slots")
	var rules: Dictionary=bindings.mido_travel.void_probe.world29.target_lock
	if loadout.get("base_content_id")!=bindings.base_content_id or loadout.get("binding_id")!=bindings.binding_id or not Numbers.integer(loadout.get("ship_id"),0,catalogues.tables.ships.size()-1) or not loadout.get("equipment_ids") is Array:
		return reject("Void station targeting requires an equipped source ship")
	var equipped: Array=loadout.equipment_ids
	var seen:={};var scanner:=-1;var duration:=int(rules.default_duration_ms)
	for value in equipped:
		if not Numbers.integer(value,0,catalogues.tables.items.size()-1) or seen.has(int(value)):
			return reject("Void station targeting has invalid installed equipment")
		var id:=int(value);seen[id]=true
		var item: Dictionary=catalogues.tables.items[id]
		var properties: Dictionary=item.properties
		if scanner<0 and properties.get(1)==3 and properties.get(2)==int(rules.equipped_scanner_category):
			var imported: Variant=properties.get(int(rules.scanner_duration_property))
			if not Numbers.integer(imported,1,2147483647):return reject("Void scanner lacks its source acquisition time")
			scanner=id;duration=int(imported)
	var projection:=TargetProjection.new()
	if not projection.configure(bindings.flight_projection,Vector2i.ONE,frame_radii):return reject(projection.error)
	var frame_limit: int=Frames.simulation_limit(bindings)
	if frame_limit<=0 or duration<1:return reject("Void station lock has no supported frame or duration")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":29}
	_rules=rules.duplicate(true);_perspective=bindings.flight_projection.duplicate(true)
	_frame_radii=frame_radii;_max_frame_ms=frame_limit;_scanner_id=scanner;_duration_ms=duration;_station_id=-1
	_found_index=-1;_aimed_index=-1;_locked_index=-1;_elapsed_ms=0;_sample={}
	return true

extends RefCounted
## The real Void station and its fallback incoming gate. The normal-sector seed
## is restored before these position draws; no second ordinary destination exists.
const Definitions=preload("res://src/content/post_sahi_definitions.gd")
const Generator=preload("res://src/simulation/seeded_random.gd")
const Orientation=preload("res://src/simulation/scenery_orientation.gd")
var error:=""
var _state:={}

func configure(bindings: RefCounted,random_state: Dictionary,cursor:=25) -> bool:
	error=""
	if not Definitions.available(bindings) or cursor not in [25,29] or not Definitions.portal_available(bindings.mido_travel,cursor):return reject("The source Void environment is unavailable")
	var random:=Generator.new()
	if not random.restore(random_state):return reject(random.error)
	var rules: Dictionary=bindings.mido_travel.post_sahi["void"]
	var positions:=Vector3(0,int(rules.gate.position_offsets[1])+random.next_int(int(rules.gate.position_bounds[1])),int(rules.gate.position_offsets[2])+random.next_int(int(rules.gate.position_bounds[2])))
	var objects:=[]
	for source in [rules.station,rules.gate]:
		var resources:={}
		for id in source.model_ids:
			var path: String=bindings.resolve(int(id),"mesh")
			if path.is_empty():return reject(bindings.error)
			resources[int(id)]=path
		var gate: bool=source.environment_slot==2
		var pose:=Transform3D.IDENTITY
		if gate:pose=Transform3D(Basis.looking_at(-positions,Vector3.UP,true),positions)
		objects.append({"index":int(source.environment_slot),"pose":pose,"models":resources,
			"model_ids":source.model_ids.map(func(id):return int(id)),"kind":"gate" if gate else "station"})
	var orientation:=Orientation.new().for_station(-1)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":cursor,"station_id":-1,"system_id":-1,"return_station_id":91 if cursor==29 else int(rules.return_station_id),"return_system_id":18 if cursor==29 else int(rules.return_system_id),
		"objects":objects,"player_position":positions,"initial_random":random_state.duplicate(true),"random_state":random.snapshot(),
		"sky":rules.sky.duplicate(true),"sky_orientation":orientation,"field":rules.field.duplicate(true),"docking_available":false}
	return true

func object_state(index: int) -> Dictionary:
	for row in _state.get("objects",[]):
		if row.index==index:return row.duplicate(true)
	return {}

func snapshot() -> Dictionary:return _state.duplicate(true)
func fork() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true)
	return copy
func reject(message: String) -> bool:error=message;return false

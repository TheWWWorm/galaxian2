extends RefCounted
## Native clocks for the original gate layers. Activation replaces only the
## second child; base geometry and emissive layers keep their ordinary clocks.
const Definitions=preload("res://src/content/gate_transit_definitions.gd")
const Layout=preload("res://src/simulation/gate_environment.gd")
const AEM=preload("res://src/content/aem.gd")
const Resources=preload("res://src/content/scenery_effect_resources.gd")
const Playback=preload("res://src/simulation/model_playback.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _state:={}
var _rules:={}
var _identity: RefCounted

func configure(bindings: RefCounted,catalogues: RefCounted,library: RefCounted,station_id: int) -> bool:
	error=""
	if not Definitions.available(bindings) or library==null or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Gate animation requires matching original content and transit declarations")
	var layout:=Layout.new()
	if not layout.configure(bindings,catalogues,station_id):return reject(layout.error)
	var next: Dictionary=layout.snapshot();var decoded:={};var objects:=[]
	for gate in next.objects:
		var models:=[]
		var ids: Array=[gate.mesh_id];ids.append_array(gate.child_mesh_ids);ids.append(gate.jump_mesh_id)
		for id in ids:
			if not decoded.has(id):
				var reader:=AEM.new();var path: String=gate.models[id]
				var mesh:=reader.decode(library.read_resource(path,AEM.MAX_BYTES))
				if mesh.is_empty():return reject(reader.error+library.error)
				var timing:=Resources.playback_range(mesh.surfaces,true)
				if timing.is_empty():return reject("Gate layer has unsupported original animation channels")
				var material: Dictionary=bindings.material_for_mesh(path,"high")
				if material.is_empty():return reject(bindings.error)
				decoded[id]={"model_id":id,"resource":path,"start_ms":timing.start_ms,"end_ms":timing.end_ms,"render_type":int(material.render_type)}
			var model: Dictionary=decoded[id].duplicate()
			model.time_ms=model.start_ms;model.playing=model.end_ms>0 and id!=gate.jump_mesh_id
			models.append(model)
		if models[3].end_ms<=int(bindings.mido_travel.gate_transit.animation.acceleration_after_ms):return reject("Gate jump animation ends before its acceleration threshold")
		objects.append({"index":gate.index,"active":false,"models":models})
	_rules=bindings.mido_travel.gate_transit.animation.duplicate(true)
	_state={"layout":next,"objects":objects,"elapsed_ms":0};_identity=RefCounted.new()
	return true

func activate(index: int) -> bool:
	error=""
	var gate:=object_state(index)
	if _state.is_empty() or index!=1 or gate.is_empty():return reject("Only the source outgoing gate can activate")
	if gate.active:return true
	var next:=_state.duplicate(true)
	for row in next.objects:
		if row.index==index:
			row.active=true;Playback.restart([row.models[3]])
	_state=next
	return true

func advance(milliseconds: int,paused:=false) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(milliseconds,0,150):return reject("Gate animation requires a bounded ordinary frame")
	if paused:return true
	if _state.elapsed_ms>9223372036854775807-milliseconds:return reject("Gate clock exceeds the native time range")
	var next:=_state.duplicate(true);next.elapsed_ms+=milliseconds
	for gate in next.objects:
		for index in 3:
			if gate.active and index==int(_rules.replaced_child_index)+1:continue
			Playback.advance([gate.models[index]],milliseconds,true)
		if gate.active:Playback.advance([gate.models[3]],milliseconds,bool(_rules.loop_jump))
	_state=next
	return true

func accelerating() -> bool:
	var gate:=object_state(1)
	return not gate.is_empty() and gate.models[3].time_ms>int(_rules.acceleration_after_ms)

func completed() -> bool:
	var gate:=object_state(1)
	return not gate.is_empty() and gate.active and not gate.models[3].playing

func object_state(index: int) -> Dictionary:
	for gate in _state.get("objects",[]):
		if gate.index==index:return gate.duplicate(true)
	return {}

func presentation_identity() -> RefCounted:return _identity
func snapshot() -> Dictionary:return _state.duplicate(true)
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._rules=_rules.duplicate(true);copy._identity=_identity
	return copy
func reject(message: String) -> bool:error=message;return false

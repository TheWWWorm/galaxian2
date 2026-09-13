extends RefCounted
## Stateless engine selection/control evaluation. Playback ownership is separate.
const Definitions=preload("res://src/content/engine_audio_definitions.gd")
const Numbers=preload("res://src/content/audio_definitions.gd")
const Envelopes=preload("res://src/content/audio_envelope.gd")
const Vehicle=preload("res://src/simulation/vehicle_response.gd")
var error:=""
var _rules:={}
var _vehicle: RefCounted
var _events: Array=[]

func configure(bindings: RefCounted, catalogues: RefCounted) -> bool:
	error="";_rules={};_vehicle=null;_events=[]
	if bindings==null or catalogues==null:return reject("Engine selection requires content and catalogues")
	var rules: Dictionary=bindings.vehicle_response.get("audio",{})
	if not Definitions.parameters(rules):return reject("This profile has no verified engine selection")
	var vehicle:=Vehicle.new()
	if not vehicle.configure(bindings,catalogues,bindings.base_content_id):return reject(vehicle.error)
	if not bindings.audio.get("events") is Array:return reject("Engine selection requires the source audio project")
	_rules=rules.duplicate(true);_vehicle=vehicle;_events=bindings.audio.events.duplicate(true)
	return true

func select(ship_id: int, upgrades: Array, equipment: Array) -> Dictionary:
	error=""
	if _vehicle==null:return fail("Configure engine selection before resolving a ship")
	var vehicle: Dictionary=_vehicle.resolve(ship_id,upgrades,equipment)
	if vehicle.is_empty():return fail(_vehicle.error)
	var id:=select_event(_rules,ship_id,float(vehicle.effective_handling))
	if id<0 or id>=_events.size():return fail("Selected engine event is absent from this edition")
	return {"ship_id":ship_id,"source_id":id,"effective_handling":vehicle.effective_handling}

static func select_event(rules: Dictionary, ship_id: int, handling: float) -> int:
	if not Definitions.parameters(rules) or ship_id<0 or not is_finite(handling) or handling<0:return -1
	for pair in rules.ship_overrides:
		if ship_id==int(pair[0]):return int(pair[1])
	var index:=0
	for threshold in rules.thresholds:
		if handling<float(threshold):break
		index+=1
	return int(rules.event_ids[index])

func program(id: int) -> Dictionary:
	error=""
	if _rules.is_empty() or id<0 or id>=_events.size():return fail("Engine event is outside the configured source project")
	var result:=read_program(_events[id])
	if result.is_empty():return fail("This engine requires additional parameter, layer or envelope behavior")
	return result

static func read_program(event: Variant) -> Dictionary:
	if not event is Dictionary or not Numbers.integer(event.get("type"),8,8) or not event.get("parameters") is Array or not event.get("layers") is Array:return {}
	if not Numbers.integer(event.get("id"),0,19999):return {}
	if event.parameters.size()!=3 or event.layers.size()!=1:return {}
	var names:=["Vertical","Horizontal","load"]
	for i in 3:
		var p: Variant=event.parameters[i]
		if not fields_match(p,{"name":names[i],"flags":3 if i==0 else 2,"velocity":0,"min":0,"max":1,"seek_speed":0,"sustain_points":[],"envelopes":1}):return {}
	var layer: Variant=event.layers[0]
	if not fields_match(layer,{"flags":2,"priority":65535,"parameter":0}) or not layer.get("sounds") is Array or layer.sounds.size()!=1 or not layer.get("envelopes") is Array or layer.envelopes.size()!=3:return {}
	var sound: Variant=layer.sounds[0]
	if not fields_match(sound,{"flags":0,"flags2":0,"loop_count":-1,"auto_pitch":0,"fine_tune":0,"x":0,"width":1,"fade_in":-1,"fade_out":-1,"auto_pitch_reference":0,"auto_pitch_zero":0,"fade_in_type":4,"fade_out_type":4}):return {}
	if not Numbers.number(sound.get("volume"),0,1) or not Numbers.integer(sound.get("sound_def"),0,65535):return {}
	var targets:={};var parameters:={}
	for envelope in layer.envelopes:
		if not Envelopes.supported(envelope,3):return {}
		var target: String=Envelopes.TARGETS[int(envelope.flags)]
		if targets.has(target) or parameters.has(int(envelope.parameter_index)):return {}
		targets[target]=envelope.duplicate(true);parameters[int(envelope.parameter_index)]=true
	return {"source_id":int(event.id),"sound_definition":int(sound.sound_def),"sound_volume":float(sound.volume),"envelopes":targets,"parameter_count":3}

static func fields_match(data: Variant, expected: Dictionary) -> bool:
	if not data is Dictionary:return false
	for key in expected:
		if not Definitions.equivalent(data.get(key),expected[key]):return false
	return true

func controls(source_commands: Vector2, previous: Array) -> Array:
	error=""
	if _rules.is_empty() or not source_commands.is_finite() or not valid_parameters(previous):reject("Invalid engine control input or retained parameters");return []
	# Inputs are the source's retained command fields, before angular response.
	# Do not feed smoothed rotation units into these two controls.
	var values:=previous.duplicate()
	values[int(_rules.steering_parameter)]=clampf(maxf(absf(source_commands.x),absf(source_commands.y)),0.0,1.0)
	var horizontal:=float32(source_commands.y*float(_rules.horizontal_scale))
	values[int(_rules.horizontal_parameter)]=clampf(float32(horizontal+float(_rules.horizontal_offset)),0.0,1.0)
	return values

static func float32(value: float) -> float:
	return PackedFloat32Array([value])[0]

static func valid_parameters(values: Variant) -> bool:
	if not values is Array or values.size()!=3:return false
	for value in values:
		if not Numbers.number(value,0,1):return false
	return true

static func evaluate(program_data: Dictionary, values: Array) -> Dictionary:
	if not valid_parameters(values) or not program_data.get("envelopes") is Dictionary or program_data.envelopes.size()!=3 or not Numbers.number(program_data.get("sound_volume"),0,1):return {}
	var result:={"gain":float(program_data.sound_volume),"pitch":1.0,"spread_degrees":0.0}
	for target in program_data.envelopes:
		if not target is String or target not in ["gain","pitch","spread_degrees"]:return {}
		var envelope: Variant=program_data.envelopes[target]
		if not Envelopes.supported(envelope,3) or Envelopes.TARGETS[int(envelope.flags)]!=target:return {}
		var value:=Envelopes.evaluate(envelope,float(values[int(envelope.parameter_index)]))
		if target=="spread_degrees":result[target]=value
		else:result[target]*=value
	return result

func reject(message: String) -> bool:
	error=message;return false

func fail(message: String) -> Dictionary:
	reject(message);return {}

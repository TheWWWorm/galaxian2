extends RefCounted
## Native ring drilling. The flight owner supplies the shared random stream and
## an already docked asteroid. Approach, cargo mutation and missions have separate
## owners. Presentation can resize without changing the reference coordinates.
const Definitions=preload("res://src/content/mining_drill_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
var error:=""
var _rules:={}
var _state:={}
var _field_identity: RefCounted

func configure_for_scenery(bindings: RefCounted, catalogues: RefCounted, equipment_ids: Array, scenery: RefCounted, object_index: int, reference_center: Vector2) -> bool:
	error=""
	if scenery==null or scenery.get_script()!=Scenery:return reject("Drilling requires a live scenery owner")
	var field: Dictionary=scenery.snapshot().get("bodies",{})
	if not configure(bindings,catalogues,equipment_ids,field,object_index,reference_center):return false
	_field_identity=scenery.presentation_identity()
	return true

func configure(bindings: RefCounted, catalogues: RefCounted, equipment_ids: Array, field: Dictionary, object_index: int, reference_center: Vector2) -> bool:
	error=""
	if bindings==null or catalogues==null or not Definitions.parameters(bindings.mining_drill):return reject("This pack has no supported mining drill")
	if catalogues.content_id!=bindings.base_content_id or field.get("base_content_id")!=bindings.base_content_id or field.get("binding_id")!=bindings.binding_id:return reject("Drilling requires the active field and equipment catalogue")
	if not reference_center.is_finite() or reference_center!=reference_center.floor() or absf(reference_center.x)>16384 or absf(reference_center.y)>16384:return reject("Drilling requires finite integer reference coordinates")
	var objects: Variant=field.get("objects")
	if not objects is Array or object_index<0 or object_index>=objects.size() or not objects[object_index] is Dictionary:return reject("Drilling requires an existing asteroid")
	var body: Dictionary=objects[object_index]
	var rules: Dictionary=bindings.mining_drill
	if body.get("index")!=object_index or not Numbers.integer(body.get("source_size_value"),int(rules.size_min),int(rules.size_max)):return reject("Unsupported asteroid drilling layers")
	# A body snapshot may carry lifecycle state. A geometric field alone does
	# not certify docking; the approach owner must make that decision.
	var vitals: Variant=body.get("vitals",{})
	if not vitals is Dictionary or not Numbers.integer(vitals.get("hull",1),1,2147483647) or body.get("active",true)!=true or body.get("destruction_pending",false):return reject("Cannot drill an exhausted asteroid")
	var items: Array=catalogues.tables.get("items",[])
	if not Numbers.integer(body.get("item_id"),0,items.size()-1):return reject("Asteroid ore is absent from this catalogue")
	var ore_id:=int(body.item_id)
	var ore_supported:=ore_id==int(bindings.scenery_resources.get("override_item_id",-1)) or ore_id==int(bindings.scenery_resources.get("fallback_item_id",-1))
	for id in bindings.scenery_resources.get("ore_item_ids",[]):
		if ore_id==int(id):ore_supported=true
	if not ore_supported:return reject("Asteroid does not declare a supported ore")
	var selected:={};var drill_id:=-1
	for id in equipment_ids:
		if not Numbers.integer(id,0,items.size()-1):return reject("Invalid installed drill equipment")
		var properties: Dictionary=items[int(id)].properties
		if properties.get(int(rules.item_kind_property))!=int(rules.equipment_kind):continue
		if properties.get(int(rules.item_category_property))==int(rules.drill_category):
			if drill_id>=0:return reject("Multiple installed drills require an unverified equipment selection")
			drill_id=int(id);selected=properties
	if drill_id<0:return reject("No mining drill is equipped")
	for key in [rules.stability_property,rules.rate_property]:
		if not Numbers.integer(selected.get(int(key)),0,100000):return reject("Unsupported drill performance property")
	var stability:=f32(f32(f32(float(selected[int(rules.stability_property)])/float(rules.property_divisor))*float(rules.stability_gain))+float(rules.stability_bias))
	var rate:=f32(float(selected[int(rules.rate_property)])/float(rules.property_divisor))
	if stability<=0 or rate<=0:return reject("The equipped drill cannot extract ore")
	_rules=rules.duplicate(true)
	_field_identity=null
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"object_index":object_index,
		"item_id":ore_id,"drill_id":drill_id,"layer_count":int(body.source_size_value),"stability":stability,"rate":rate,
		"center":reference_center,"point":reference_center,"command":Vector2.ZERO,"input":Vector2.ZERO,"drift":Vector2.ZERO,
		"drift_elapsed_ms":0,"outside_elapsed_ms":0,"layer_elapsed_ms":0,"layer_index":0,"elapsed_ms":0,
		"ore_progress":0.0,"phase":"drilling","all_layers":false,"core":false,"spin":0.0,"spinner_steps":0,"pulse":0.0,
		"random_state":{},"drift_changes":0}
	return true

func set_command(command: Vector2) -> bool:
	error=""
	if _state.is_empty() or _state.phase!="drilling" or not command.is_finite() or absf(command.x)>1.0 or absf(command.y)>1.0:return reject("Invalid drilling control input")
	var input:=Vector2.ZERO
	for axis in 2:input[axis]=f32(f32(f32(command[axis])*absf(f32(command[axis])))*float(_rules.input_gain))
	_state.command=command;_state.input=input
	return true

func advance(milliseconds: Variant, random_state: Variant, paused:=false) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(milliseconds,0,int(_rules.max_frame_ms)):return reject("Invalid drilling frame")
	var random:=Random.new()
	if not random.restore(random_state):return reject(random.error)
	if paused or _state.phase!="drilling":return true
	var dt:=int(milliseconds)
	_state.elapsed_ms+=dt;_state.drift_elapsed_ms+=dt
	if _state.drift_elapsed_ms>int(_rules.drift_threshold_ms):
		_state.drift_elapsed_ms=int(_rules.drift_timer_base)+random.next_int(int(_rules.drift_timer_bound))
		var drift:=Vector2.ZERO
		for axis in 2:
			var magnitude:=int(_rules.drift_magnitude_base)+random.next_int(int(_rules.drift_magnitude_bound))
			var direction:=1 if random.next_int(2)==0 else -1
			drift[axis]=f32(f32(float(magnitude*direction)/float(_rules.drift_divisor))/_state.stability)
		_state.drift=drift;_state.drift_changes+=1
	_state.random_state=random.snapshot()
	var point: Vector2=_state.point
	for axis in 2:
		var velocity:=f32(f32(_state.input[axis]+_state.drift[axis])/float(_rules.reference_motion_divisor))
		point[axis]=f32(point[axis]+f32(velocity*float(dt)))
	_state.point=point
	if not _inside():
		_state.outside_elapsed_ms+=dt
		if _state.outside_elapsed_ms>int(_rules.outside_limit_ms):
			_state.outside_elapsed_ms=int(_rules.outside_limit_ms);_state.ore_progress=0.0;_state.phase="failed"
		else:_state.pulse=1.0
		return true
	# Returning inside resumes extraction, but never refunds time spent outside.
	var progress:=f32(float(_state.layer_index+1)/float(_rules.progress_layer_divisor))
	progress=f32(f32(progress*float(_rules.progress_gain))+float(_rules.progress_bias))
	progress=f32(f32(f32(progress*_state.rate)/float(_rules.milliseconds_per_second))*float(dt))
	var previous_tons:=int(_state.ore_progress)
	_state.ore_progress=f32(_state.ore_progress+progress)
	if int(_state.ore_progress)>previous_tons:_state.pulse=0.0
	_state.pulse=minf(1.0,f32(_state.pulse+f32(float(dt)/float(_rules.pulse_duration_ms))))
	_state.spin=f32(_state.spin+f32(f32(float(_rules.spin_rates[_state.layer_index])*f32(float(dt)/float(_rules.milliseconds_per_second)))*float(_rules.spinner_gain)))
	if _state.spin>=float(_rules.spinner_threshold):_state.spin=0.0;_state.spinner_steps+=1
	_state.layer_elapsed_ms+=dt
	if _state.layer_elapsed_ms>=int(_rules.layer_duration_ms):
		_state.layer_index+=1;_state.layer_elapsed_ms=0
		if _state.layer_index==_state.layer_count:
			_state.all_layers=true;_state.core=_state.layer_count==int(_rules.core_size);_state.phase="extracted"
	return true

func stop() -> bool:
	error=""
	if _state.is_empty() or _state.phase!="drilling":return reject("No active drill can be stopped")
	_state.phase="stopped"
	return true

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true)
	result.ore_tons=int(_state.ore_progress)
	result.radii=[]
	for diameter in _rules.diameters[int(_rules.size_max)-_state.layer_count]:
		if diameter>0:result.radii.append(f32(float(int(diameter) >> 1)*float(_rules.reference_ring_scale)))
	result.radius=0.0 if _state.all_layers else _radius()
	result.inside=not _state.all_layers and _inside()
	return result

func _radius() -> float:
	var diameter:=int(_rules.diameters[int(_rules.size_max)-_state.layer_count][_state.layer_index])
	return f32(float(diameter >> 1)*float(_rules.reference_ring_scale))

func _inside() -> bool:
	var offset: Vector2=_state.point-_state.center
	var distance:=f32(sqrt(f32(f32(offset.x*offset.x)+f32(offset.y*offset.y))))
	return _radius()>distance

func fork() -> RefCounted:
	var copy: RefCounted=get_script().new();copy._state=_state.duplicate(true);copy._rules=_rules.duplicate(true)
	copy._field_identity=_field_identity
	return copy
func field_identity() -> RefCounted:return _field_identity
func clear() -> void:error="";_state={};_rules={};_field_identity=null
static func f32(value: float) -> float:return PackedFloat32Array([value])[0]
func reject(message: String) -> bool:error=message;return false

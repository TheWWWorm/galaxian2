extends RefCounted
## The fresh player's retained engine. Rendering owns the actual sound instance.
## Raw commands are consumed before manual movement and sampled after the camera.
const Selection=preload("res://src/simulation/engine_audio.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
var error:=""
var _selection: RefCounted
var _state:={}
var _commands:=Vector2.ZERO
var _ordinary_phase:=-1
var _arrival_id:=-1

func configure(bindings: RefCounted,catalogues: RefCounted,scene: Dictionary) -> bool:
	_selection=null;_state={};_commands=Vector2.ZERO;_ordinary_phase=-1;_arrival_id=-1;error=""
	if bindings==null or catalogues==null:return reject("Engine ownership requires the fresh content and loadout")
	for key in ["base_content_id","binding_id"]:
		if scene.get(key)!=bindings.get(key):return reject("Player engine belongs to another opening scene")
	var pose: Variant=scene.get("player_pose")
	if not pose is Transform3D or not pose.is_finite():return reject("Player engine requires its initial source position")
	var repair: Dictionary=bindings.opening_actors.get("player_initialization",{}).get("repair",{})
	var flight: Dictionary=bindings.opening_staging.get("player_flight",{})
	if repair.is_empty() or flight.is_empty():return reject("Player engine lacks its fresh movement and equipment owners")
	var selection:=Selection.new();var loadout:=Loadout.new()
	if not selection.configure(bindings,catalogues) or not loadout.configure(bindings,catalogues,bindings.base_content_id):return reject(selection.error+loadout.error)
	var seed: Dictionary=loadout.snapshot()
	var chosen: Dictionary=selection.select(seed.ship_id,repair.initial_upgrades,seed.equipment_ids)
	if chosen.is_empty():return reject(selection.error)
	if selection.program(int(chosen.source_id)).is_empty():return reject(selection.error)
	# Fresh FEV parameters start at their minima; the supported program has three
	# minima of zero. No source setter drives load during ordinary manual flight.
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"initial_source_id":int(chosen.source_id),"source_id":int(chosen.source_id),
		"generation":0,"parameters":[0.0,0.0,0.0],"position":pose.origin,"active":true,"elapsed_ms":0}
	_selection=selection;_ordinary_phase=int(flight.ordinary_phase)
	_arrival_id=int(bindings.opening_staging.get("escape",{}).get("arrival_engine_sound_id",-1))
	return true

func before_motion(phase: int) -> bool:
	error=""
	if _selection==null or phase<0 or phase>16:return reject("Invalid retained engine movement phase")
	if phase!=_ordinary_phase:return true
	if _state.generation!=0:return reject("The arrival engine has no supported manual control path")
	var values: Array=_selection.controls(_commands,_state.parameters)
	if values.is_empty():return reject(_selection.error)
	_state.parameters=values;_commands=Vector2.ZERO
	return true

func follow_player(pose: Transform3D,hull: int,delta_ms: int) -> bool:
	error=""
	if _selection==null or not pose.is_finite() or delta_ms<0 or delta_ms>150:return reject("Invalid retained engine movement frame")
	_state.position=pose.origin;_state.active=hull>0;_state.elapsed_ms+=delta_ms
	return true

func sample_commands(axes: Vector2) -> bool:
	error=""
	if _selection==null or not axes.is_finite() or absf(axes.x)>1.0 or absf(axes.y)>1.0:return reject("Invalid normalized engine steering input")
	# Native axes describe positive angular pitch/yaw. The source yaw command
	# has the opposite sign; both source setters receive squared stick inputs.
	_commands=Vector2(Selection.float32(axes.x*absf(axes.x)),-Selection.float32(axes.y*absf(axes.y)))
	return true

func apply_controller(escape: Dictionary,pose: Transform3D) -> bool:
	error=""
	if _selection==null or not pose.is_finite():return reject("Invalid player engine controller context")
	var operations: Variant=escape.get("frame",{}).get("audio",[])
	if not operations is Array:return reject("Invalid player engine controller operations")
	var replace:=false
	for op in operations:
		if not op is Dictionary:return reject("Invalid player engine controller operation")
		if op.get("action")!="set_player_engine":continue
		if replace or _state.generation!=0 or _arrival_id<0 or op.get("source_id")!=_arrival_id:return reject("Unsupported retained engine replacement")
		replace=true
	if replace:
		_state.source_id=_arrival_id;_state.generation=1;_state.parameters=[]
		_state.position=pose.origin;_state.active=true
	# The early slowdown stops a cached event ID, not this retained instance.
	return true

func snapshot() -> Dictionary:
	var result:=_state.duplicate(true)
	if not result.is_empty():result.source_commands=_commands
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._selection=_selection;copy._state=_state.duplicate(true);copy._commands=_commands
	copy._ordinary_phase=_ordinary_phase;copy._arrival_id=_arrival_id
	return copy

func reject(message: String) -> bool:error=message;return false

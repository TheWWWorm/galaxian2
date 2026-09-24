extends RefCounted
## Campaign visits offer their original conversation at the source boundary.
## The caller commits the acknowledged transition with its owned career. This
## component never relocates the player, pays rewards or opens destinations.
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const Kappa=preload("res://src/content/kappa_preparation_definitions.gd")
const Preparation=preload("res://src/simulation/campaign_preparation.gd")
const Lines=preload("res://src/content/dialogue_lines.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Rescue=preload("res://src/simulation/kappa_rescue.gd")
var error:=""
var _state:={}
var _rules:={}
var _lines:=[]
var _station_only:=false
var _station_count:=0
var _preparation: RefCounted
var _station_loadout:={}
var _result_mode:=false
var _failure_rules:={}
var _failure_lines:=[]
var _result_observation:={}

func configure(bindings: RefCounted,library: RefCounted,cursor: Variant,mission: Variant) -> bool:
	error=""
	var rules:=Campaign.dialogue_rules(bindings,cursor,mission)
	if rules.is_empty():return reject("Unsupported campaign visit")
	if not _configure_lines(bindings,library,cursor,mission,rules):return false
	_station_only=false;_station_count=0;_preparation=null
	return true

func configure_station(bindings: RefCounted,library: RefCounted,catalogues: RefCounted,cursor: Variant,mission: Variant) -> bool:
	error=""
	if bindings==null or catalogues==null or catalogues.content_id!=bindings.base_content_id:return reject("Station conversation belongs to another content pack")
	var preparation: RefCounted
	var rules:=Campaign.dialogue_rules(bindings,cursor,mission,true)
	if Kappa.selected(bindings,cursor,mission,"fitting"):
		rules=bindings.mido_travel.kappa_preparation.fitting
		preparation=Preparation.new()
		if not preparation.configure(bindings,catalogues,cursor,mission):return reject(preparation.error)
	if rules.is_empty():return reject("Unsupported campaign station conversation")
	if not _configure_lines(bindings,library,cursor,mission,rules):return false
	_station_only=true;_station_count=catalogues.tables.stations.size();_preparation=preparation
	return true

## A result is offered by the actual rescue controller. Like station and visit
## conversations, its receipt is prospective; the owning session commits it.
func configure_result(bindings: RefCounted,library: RefCounted,cursor: Variant,mission: Variant) -> bool:
	error=""
	var rules:=Campaign.result_rules(bindings,cursor,mission)
	if rules.is_empty():return reject("Unsupported campaign flight result")
	var failure_lines:=Campaign.Outcome.failure_lines(bindings,library)
	if failure_lines.is_empty():return reject("Campaign failure text is unavailable in this language")
	if not _configure_lines(bindings,library,cursor,mission,rules):return false
	_station_only=false;_station_count=0;_preparation=null;_result_mode=true
	_failure_rules=bindings.mido_travel.kappa_outcome.failure.duplicate(true)
	_failure_lines=failure_lines;_state.outcome=""
	return true

func poll_result(rescue: RefCounted,completion_allowed: bool) -> bool:
	error=""
	if _state.is_empty() or not _result_mode or not rescue is Rescue:return reject("A campaign result requires its native rescue controller")
	var observed: Dictionary=rescue.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if observed.get(key)!=_state[key]:return reject("Campaign result belongs to another rescue")
	if _state.phase!="waiting":return true
	var outcome: String=rescue.poll_outcome(completion_allowed)
	if not rescue.error.is_empty():return reject(rescue.error)
	if outcome.is_empty():return true
	if outcome=="failed":_lines=_failure_lines.duplicate(true)
	_state.outcome=outcome;_state.phase="conversation"
	_result_observation=observed
	return true

func matches_result_observation(rescue: RefCounted) -> bool:
	return _result_mode and not _result_observation.is_empty() and rescue is Rescue and rescue.snapshot()==_result_observation

func _configure_lines(bindings: RefCounted,library: RefCounted,cursor: int,mission: Dictionary,rules: Dictionary) -> bool:
	var resolver:=Lines.new()
	var lines:=resolver.read(bindings,library,rules.events)
	if lines.size()!=rules.events.size():return reject(resolver.error)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language,
		"campaign_cursor":cursor,"mission":_native_mission(mission),"phase":"waiting","line_index":0,
		"acknowledged":false,"world_elapsed_ms":0,"reward_credits":0,"mission_completed":false}
	_rules=rules.duplicate(true);_lines=lines
	_station_loadout={}
	_result_mode=false;_failure_rules={};_failure_lines=[];_result_observation={}
	return true

func poll_station(loadout: Variant,docked: Variant,poll_blocked:=false) -> bool:
	error=""
	if _state.is_empty() or not _station_only or _result_mode:return reject("Configure a station conversation before polling it")
	if not loadout is Dictionary or not docked is bool or not loadout.get("station_id") is int or not Numbers.integer(loadout.station_id,0,_station_count-1):return reject("Invalid campaign station context")
	for key in ["base_content_id","binding_id"]:
		if loadout.get(key)!=_state[key]:return reject("Station conversation belongs to another content identity")
	if _state.phase!="waiting" or poll_blocked:return true
	if not docked:return true
	if _rules.target_station_required and loadout.station_id!=int(_rules.mission.station_id):return true
	if _preparation!=null:
		var installed: Dictionary=_preparation.installed_equipment(loadout,docked)
		if installed.is_empty():return reject(_preparation.error)
		if not installed.ready:return true
	_station_loadout=loadout.duplicate(true)
	_state.station_id=loadout.station_id;_state.phase="conversation";_state.mission_completed=true
	return true

func matches_station_inventory(loadout: Dictionary) -> bool:
	return _station_only and not _station_loadout.is_empty() and loadout==_station_loadout

func poll(station_id: Variant,world_elapsed_ms: Variant,hud_elapsed_ms: Variant,docked:=false,poll_blocked:=false) -> bool:
	error=""
	if _state.is_empty() or _station_only or _result_mode:return reject("Configure a flight visit before polling it")
	if not Numbers.integer(station_id,0,2147483647) or not Numbers.integer(world_elapsed_ms,0,9223372036854775807) or not Numbers.integer(hud_elapsed_ms,0,9223372036854775807):return reject("Invalid campaign visit clock or location")
	if _state.phase!="waiting" or poll_blocked:return true
	if world_elapsed_ms<_state.world_elapsed_ms:return reject("The campaign visit clock moved backwards")
	_state.world_elapsed_ms=int(world_elapsed_ms)
	if docked or station_id!=int(_rules.mission.station_id) or hud_elapsed_ms<int(_rules.hud_poll_minimum_ms):return true
	if world_elapsed_ms>int(_rules.world_elapsed_after_ms):_state.phase="conversation";_state.mission_completed=true
	return true

func navigate(action: String) -> bool:
	error=""
	if _state.get("phase")!="conversation" or action not in ["next","previous"]:return reject("No campaign visit conversation awaits navigation")
	if action=="previous":
		if _state.line_index==0:return reject("No previous dialogue line")
		_state.line_index-=1
	elif _state.line_index<_lines.size()-1:_state.line_index+=1
	else:
		_state.phase="acknowledged";_state.acknowledged=true
	return true

func transition() -> Dictionary:
	if not _state.get("acknowledged",false):return {}
	if _result_mode and _state.outcome=="failed":
		return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
			"from_cursor":_state.campaign_cursor,"previous_mission":_state.mission.duplicate(true),
			"outcome":"failed","source_state":int(_failure_rules.continue_source_state),
			"reward_credits":int(_failure_rules.reward_credits)}
	var result:={"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
		"from_cursor":int(_rules.campaign_cursor),"campaign_cursor":int(_rules.next_cursor),
		"previous_mission":_state.mission.duplicate(true),"mission":_native_mission(_rules.next_mission),
		"station_id":int(_state.station_id if _station_only else _rules.mission.station_id),"reward_credits":int(_rules.reward_credits)}
	if _result_mode:result.outcome=_state.outcome
	if _rules.has("unlock_system_ids"):
		result.unlock_system_ids=[]
		for id in _rules.unlock_system_ids:result.unlock_system_ids.append(int(id))
		result.next_course=_native_mission(_rules.next_course)
	return result

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true)
	result.dialogue={"visible":_state.phase=="conversation","index":_state.line_index,"count":_lines.size(),
		"previous_available":_state.phase=="conversation" and _state.line_index>0}
	if result.dialogue.visible:result.dialogue.merge(_lines[_state.line_index].duplicate(true))
	return result

func fork() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._rules=_rules.duplicate(true);copy._lines=_lines.duplicate(true)
	copy._station_only=_station_only;copy._station_count=_station_count
	copy._station_loadout=_station_loadout.duplicate(true)
	copy._result_mode=_result_mode;copy._failure_rules=_failure_rules.duplicate(true)
	copy._failure_lines=_failure_lines.duplicate(true);copy._result_observation=_result_observation.duplicate(true)
	if _preparation!=null:copy._preparation=_preparation.fork()
	return copy

static func _native_mission(data: Dictionary) -> Dictionary:
	var result:={}
	for key in data:result[key]=int(data[key])
	return result

func reject(message: String) -> bool:
	error=message
	return false

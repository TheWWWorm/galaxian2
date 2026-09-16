extends RefCounted
## A flight visit offers its original conversation at the source clock boundary.
## The caller commits the acknowledged transition with its owned career. This
## component never relocates the player, pays rewards or opens destinations.
const Definitions=preload("res://src/content/suttnar_visit_definitions.gd")
const Kappa=preload("res://src/content/kappa_preparation_definitions.gd")
const Lines=preload("res://src/content/dialogue_lines.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _state:={}
var _rules:={}
var _lines:=[]

func configure(bindings: RefCounted,library: RefCounted,cursor: Variant,mission: Variant) -> bool:
	error=""
	var rules: Dictionary
	if Definitions.selected(bindings,cursor,mission):rules=bindings.mido_travel.suttnar_visit
	elif Kappa.selected(bindings,cursor,mission,"visit"):rules=bindings.mido_travel.kappa_preparation.visit
	else:return reject("Unsupported campaign visit")
	var resolver:=Lines.new()
	var lines:=resolver.read(bindings,library,rules.events)
	if lines.size()!=rules.events.size():return reject(resolver.error)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language,
		"campaign_cursor":cursor,"mission":_native_mission(mission),"phase":"waiting","line_index":0,
		"acknowledged":false,"world_elapsed_ms":0,"reward_credits":0}
	_rules=rules.duplicate(true);_lines=lines
	return true

func poll(station_id: Variant,world_elapsed_ms: Variant,hud_elapsed_ms: Variant,docked:=false,poll_blocked:=false) -> bool:
	error=""
	if _state.is_empty():return reject("Configure the campaign visit before polling it")
	if not Numbers.integer(station_id,0,2147483647) or not Numbers.integer(world_elapsed_ms,0,9223372036854775807) or not Numbers.integer(hud_elapsed_ms,0,9223372036854775807):return reject("Invalid campaign visit clock or location")
	if _state.phase!="waiting" or poll_blocked:return true
	if world_elapsed_ms<_state.world_elapsed_ms:return reject("The campaign visit clock moved backwards")
	_state.world_elapsed_ms=int(world_elapsed_ms)
	if docked or station_id!=int(_rules.mission.station_id) or hud_elapsed_ms<int(_rules.hud_poll_minimum_ms):return true
	if world_elapsed_ms>int(_rules.world_elapsed_after_ms):_state.phase="conversation"
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
	return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
		"from_cursor":int(_rules.campaign_cursor),"campaign_cursor":int(_rules.next_cursor),
		"previous_mission":_state.mission.duplicate(true),"mission":_native_mission(_rules.next_mission),
		"station_id":int(_rules.mission.station_id),"reward_credits":int(_rules.reward_credits)}

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
	return copy

static func _native_mission(data: Dictionary) -> Dictionary:
	var result:={}
	for key in data:result[key]=int(data[key])
	return result

func reject(message: String) -> bool:
	error=message
	return false

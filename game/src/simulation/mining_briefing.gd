extends RefCounted
## Entry and acknowledged briefing for supported ordinary flights. The caller owns
## world/camera updates and uses simulation_delta_ms() for this frame. This owner
## never mines cargo, completes missions, advances the campaign or grants rewards.
const Ordinary=preload("res://src/content/ordinary_flight_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Lines=preload("res://src/content/dialogue_lines.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _state:={}
var _rules:={}
var _lines:=[]
var _simulation_ms:=0
var _controller_holds_clock:=false
var _poll_due:=false
var _failure_line:={}

func configure(bindings: RefCounted, library: RefCounted, construction: RefCounted, dock_key: String, fast_forward_key:="T", input_labels: Dictionary={}) -> bool:
	error=""
	if bindings==null or library==null or construction==null or construction.get_script()!=Construction:return reject("Mining briefing requires a prepared departure")
	var flight: Dictionary=construction.snapshot()
	if flight.is_empty() or flight.get("base_content_id")!=bindings.base_content_id or flight.get("binding_id")!=bindings.binding_id or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Mining briefing belongs to another flight or content identity")
	if Ordinary.for_departure(bindings,flight).is_empty():return reject("This construction has no connected ordinary flight context")
	var training: bool=flight.get("campaign_cursor")==7
	var rules:=Ordinary.briefing(bindings,flight.get("campaign_cursor"),(Ordinary.FreeFlight.ordinary_entry(bindings,flight) or flight.get("scenery",{}).get("world_initialization",{}).has("contract_context")),int(flight.location.station_id))
	if rules.is_empty():return reject("This departure has no supported mining briefing")
	if flight.activated or flight.entry_released or flight.briefing_started:return reject("Mining briefing requires a fresh prepared departure")
	var instruction_rules: Dictionary=rules if training else Ordinary.briefing(bindings,2)
	if instruction_rules.is_empty() or instruction_rules.events.is_empty():return reject("Flight briefing requires its source instruction")
	var instruction_id:=int(instruction_rules.events[-1].text_id)
	if bindings.desktop_text_id(instruction_id)!=instruction_id+1:return reject("Flight briefing requires its desktop instruction mapping")
	if dock_key.strip_edges().is_empty() or dock_key.length()>32 or dock_key.contains("#") or dock_key.contains("\n"):return reject("Mining instruction requires its active mining/dock key label")
	if fast_forward_key.strip_edges().is_empty() or fast_forward_key.length()>32 or fast_forward_key.contains("#") or fast_forward_key.contains("\n"):return reject("Flight instruction requires its active Fast Forward key label")
	var substitutions:=input_labels.duplicate()
	substitutions[rules.key_token]=dock_key;substitutions["#KEY_FAST_FORWARD"]=fast_forward_key
	var reader:=Lines.new()
	var lines:=reader.read(bindings,library,rules.events,substitutions)
	if not reader.error.is_empty():return reject(reader.error)
	var failure_line:={}
	var instruction: Dictionary=bindings.mining_session.get("failure_instruction",{})
	if not instruction.is_empty():
		for id in [instruction.text_id,instruction.title_text_id]:
			if int(id)>=library.strings.size() or not library.strings[int(id)] is String or library.strings[int(id)].is_empty():return reject("Mining failure instruction is unavailable in this language")
		failure_line={"speaker_id":16,"speaker_name":library.strings[int(instruction.title_text_id)],"text_id":int(instruction.text_id),
			"text":library.strings[int(instruction.text_id)],"desktop_text_id":int(instruction.text_id),"desktop_text":library.strings[int(instruction.text_id)],"voice_event_id":-1}
	_rules=rules.duplicate(true);_lines=lines;_simulation_ms=0;_controller_holds_clock=false;_poll_due=false;_failure_line=failure_line
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language,
		"campaign_cursor":int(rules.campaign_cursor),"phase":"entry","entry_elapsed_ms":0,"hud_elapsed_ms":0,"world_elapsed_ms":0,
		"entry_released":false,"briefing_pending":false,"briefing_started":false,"acknowledged":false,"line_index":0,
		"mission":flight.departure.mission.duplicate(true),"progress":flight.departure.progress.duplicate(true),
		"cargo_used":flight.departure.cargo_used,"mining_completed":false,"reward_credits":0}
	return true

func advance(milliseconds: Variant, paused:=false, defer_poll:=false) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(milliseconds,0,int(_rules.max_frame_ms)):return reject("Invalid mining briefing frame")
	_simulation_ms=0;_poll_due=false
	if paused or _state.phase in ["briefing","mining_instruction"]:return true
	_simulation_ms=int(milliseconds)
	# The previous controller result holds the poll clock during departure.
	# The initial HUD value is false, so only the very first frame may add time
	# before that controller has run. Release affects the following HUD update.
	if not _controller_holds_clock:_state.hud_elapsed_ms+=_simulation_ms
	_state.world_elapsed_ms+=_simulation_ms
	_poll_due=_state.hud_elapsed_ms>=int(_rules.briefing_minimum_ms)
	# The HUD checks readiness before this frame's entry-controller update.
	if _state.briefing_pending and not _state.briefing_started and _state.hud_elapsed_ms>=int(_rules.briefing_minimum_ms):
		_state.phase="briefing";_state.briefing_started=true
	if not _state.entry_released:
		_state.entry_elapsed_ms+=_simulation_ms
		if _state.entry_elapsed_ms>=int(_rules.entry_release_ms):
			_state.entry_elapsed_ms=0;_state.entry_released=true;_state.briefing_pending=true
			if _lines.is_empty():_state.briefing_pending=false;_state.phase="flight"
	_controller_holds_clock=not _state.entry_released
	if not defer_poll:finish_mission_poll(false)
	return true

func mission_poll_due() -> bool:return _poll_due

func show_mining_failure_instruction() -> bool:
	if _state.is_empty() or _failure_line.is_empty() or _state.phase!="flight":return reject("The mining failure instruction cannot replace an active dialogue")
	_state.phase="mining_instruction"
	return true

func retain_mining_hint(seen: bool) -> void:
	_state.progress.mining_failure_hint_seen=seen

func finish_mission_poll(opened: bool) -> void:
	# An unsuccessful due poll resets to zero, including on the frame that
	# creates the initial briefing. Successful completion keeps the clock held.
	if _poll_due and not opened:_state.hud_elapsed_ms=0
	_poll_due=false

func retire_dialogue() -> void:
	# Completion may replace an initial briefing on its creation frame. Closing
	# it here does not claim that its remaining instructions were acknowledged.
	if not _state.is_empty():_state.phase="flight"

func navigate(action: String) -> bool:
	error=""
	if not _state.is_empty() and _state.phase=="mining_instruction":
		if action!="next":return reject("The mining instruction requires acknowledgement")
		_state.phase="flight"
		return true
	if _state.is_empty() or _state.phase!="briefing" or action not in ["next","previous"]:return reject("No mining briefing awaits navigation")
	if action=="previous":
		if _state.line_index==0:return reject("No previous mining instruction is available")
		_state.line_index-=1
	elif _state.line_index<_lines.size()-1:_state.line_index+=1
	else:
		_state.acknowledged=true;_state.briefing_pending=false;_state.phase="flight"
	return true

func simulation_delta_ms() -> int:return _simulation_ms
func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true)
	if _state.phase=="mining_instruction":
		result.dialogue={"visible":true,"index":0,"count":1,"previous_available":false}
		result.dialogue.merge(_failure_line.duplicate(true))
		return result
	result.dialogue={"visible":_state.phase=="briefing","index":_state.line_index,"count":_lines.size(),"previous_available":_state.phase=="briefing" and _state.line_index>0}
	if result.dialogue.visible:result.dialogue.merge(_lines[_state.line_index].duplicate(true))
	return result
func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._state=_state.duplicate(true);result._rules=_rules.duplicate(true);result._lines=_lines.duplicate(true);result._simulation_ms=_simulation_ms
	result._controller_holds_clock=_controller_holds_clock;result._poll_due=_poll_due
	result._failure_line=_failure_line.duplicate(true)
	return result
func clear() -> void:error="";_state={};_rules={};_lines=[];_failure_line={};_simulation_ms=0;_controller_holds_clock=false;_poll_due=false
func reject(message: String) -> bool:error=message;return false

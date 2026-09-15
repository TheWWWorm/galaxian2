extends RefCounted
## Entry and acknowledged briefing for supported ordinary flights. The caller owns
## world/camera updates and uses simulation_delta_ms() for this frame. This owner
## never mines cargo, completes missions, advances the campaign or grants rewards.
const Ordinary=preload("res://src/content/ordinary_flight_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _state:={}
var _rules:={}
var _lines:=[]
var _simulation_ms:=0
var _controller_holds_clock:=false
var _poll_due:=false

func configure(bindings: RefCounted, library: RefCounted, construction: RefCounted, dock_key: String) -> bool:
	error=""
	if bindings==null or library==null or construction==null or construction.get_script()!=Construction:return reject("Mining briefing requires a prepared departure")
	var flight: Dictionary=construction.snapshot()
	if flight.is_empty() or flight.get("base_content_id")!=bindings.base_content_id or flight.get("binding_id")!=bindings.binding_id or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Mining briefing belongs to another flight or content identity")
	if Ordinary.for_departure(bindings,flight).is_empty():return reject("This construction has no connected ordinary flight context")
	var training: bool=flight.get("campaign_cursor")==7
	var rules:=Ordinary.briefing(bindings,flight.get("campaign_cursor"),flight.get("scenery",{}).get("world_initialization",{}).has("contract_context"))
	if rules.is_empty():return reject("This departure has no supported mining briefing")
	if flight.activated or flight.entry_released or flight.briefing_started:return reject("Mining briefing requires a fresh prepared departure")
	if bindings.desktop_text_id(1728 if training else 1703)!=(1729 if training else 1704):return reject("Flight briefing requires its desktop instruction mapping")
	if dock_key.strip_edges().is_empty() or dock_key.length()>32 or dock_key.contains("#") or dock_key.contains("\n"):return reject("Mining instruction requires its active mining/dock key label")
	var lines:=[]
	for event in rules.events:
		var text_id:=int(event.text_id)
		var desktop_id: int=bindings.desktop_text_id(text_id)
		if desktop_id<0:return reject(bindings.error)
		var texts:=[]
		for id in [text_id,desktop_id]:
			if id>=library.strings.size() or not library.strings[id] is String or library.strings[id].is_empty():return reject("Mining briefing text is unavailable in this language")
			var text: String=library.strings[id].replace(rules.key_token,dock_key)
			if "#KEY_" in text:return reject("Mining briefing needs an unsupported input-key substitution")
			texts.append(text)
		var speaker: String=bindings.resolve_speaker_name(int(event.speaker_id),library)
		if not bindings.error.is_empty():return reject(bindings.error)
		lines.append({"speaker_id":int(event.speaker_id),"speaker_name":speaker,"text_id":text_id,
			"text":texts[0],"desktop_text_id":desktop_id,"desktop_text":texts[1],"voice_event_id":int(event.voice_event_id)})
	_rules=rules.duplicate(true);_lines=lines;_simulation_ms=0;_controller_holds_clock=false;_poll_due=false
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
	if paused or _state.phase=="briefing":return true
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
	result.dialogue={"visible":_state.phase=="briefing","index":_state.line_index,"count":_lines.size(),"previous_available":_state.phase=="briefing" and _state.line_index>0}
	if result.dialogue.visible:result.dialogue.merge(_lines[_state.line_index].duplicate(true))
	return result
func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._state=_state.duplicate(true);result._rules=_rules.duplicate(true);result._lines=_lines.duplicate(true);result._simulation_ms=_simulation_ms
	result._controller_holds_clock=_controller_holds_clock;result._poll_due=_poll_due
	return result
func clear() -> void:error="";_state={};_rules={};_lines=[];_simulation_ms=0;_controller_holds_clock=false;_poll_due=false
func reject(message: String) -> bool:error=message;return false

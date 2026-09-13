extends RefCounted
## Supported mining cargo checks and acknowledged return instructions. Reaching the
## cargo threshold offers dialogue; its last acknowledgement selects the return
## mission. The hold is preserved and station arrival remains a separate step.
const Story=preload("res://src/content/ordinary_flight_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
var error:=""
var _state:={}
var _rules:={}
var _progress_rules:={}
var _lines:=[]
var _field_identity: RefCounted
var _initial_progress:={}

func configure(bindings: RefCounted, library: RefCounted, construction: RefCounted, autopilot_key: String, dock_key: String) -> bool:
	error=""
	if bindings==null or library==null or construction==null or construction.get_script()!=Construction:return reject("Mining objective requires a prepared departure")
	var flight: Dictionary=construction.snapshot()
	if flight.is_empty() or flight.get("base_content_id")!=bindings.base_content_id or flight.get("binding_id")!=bindings.binding_id or library.manifest.get("content_id")!=bindings.base_content_id:return reject("Mining objective belongs to another departure or content identity")
	var rules:=Story.objective(bindings,flight.get("campaign_cursor"))
	if rules.is_empty():return reject("This departure has no supported mining objective")
	if flight.campaign_cursor!=int(rules.campaign_cursor) or flight.activated or flight.entry_released or flight.briefing_started:return reject("Mining objective requires its fresh prepared departure")
	var mission: Dictionary=flight.departure.mission
	if mission!={"kind":int(rules.mission_kind),"station_id":int(rules.station_id),"reward":0,"bonus":0,"source_parameter":int(rules.required_cargo)}:return reject("Unsupported mining mission or reward")
	for key in [autopilot_key,dock_key]:
		if key.strip_edges().is_empty() or key.length()>32 or key.contains("#") or key.contains("\n"):return reject("Return instructions require the active autopilot and docking key labels")
	if bindings.desktop_text_id(1708)!=1709:return reject("Return instruction desktop mapping is unavailable")
	var lines:=[]
	for event in rules.events:
		var text_id:=int(event.text_id)
		var desktop_id: int=bindings.desktop_text_id(text_id)
		var texts:=[]
		for id in [text_id,desktop_id]:
			if id<0 or id>=library.strings.size() or not library.strings[id] is String or library.strings[id].is_empty():return reject("Return instruction text is unavailable in this language")
			var text: String=library.strings[id].replace(rules.key_tokens[0],autopilot_key).replace(rules.key_tokens[1],dock_key)
			if "#KEY_" in text:return reject("Return instruction requires an unsupported key substitution")
			texts.append(text)
		var speaker: String=bindings.resolve_speaker_name(int(event.speaker_id),library)
		if not bindings.error.is_empty():return reject(bindings.error)
		lines.append({"speaker_id":int(event.speaker_id),"speaker_name":speaker,"text_id":text_id,"text":texts[0],
			"desktop_text_id":desktop_id,"desktop_text":texts[1],"voice_event_id":int(event.voice_event_id)})
	_rules=rules.duplicate(true);_lines=lines;_progress_rules=bindings.opening_handoff.duplicate(true)
	_field_identity=construction.scenery_owner().presentation_identity()
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language,
		"campaign_cursor":int(rules.campaign_cursor),"phase":"collecting","line_index":0,"cargo_at_check":0,
		"cargo_objective_satisfied":false,"cargo_objective_acknowledged":false,"station_return_required":false,
		"required_cargo":int(rules.required_cargo),"mission":mission.duplicate(true),"progress":flight.departure.progress.duplicate(true),
		"reward_credits":0,"mining_completed":false}
	_initial_progress=flight.departure.progress.duplicate(true)
	if rules.has("defeat_condition"):
		_state.combat_objective_satisfied=false;_state.combat_objective_acknowledged=false
	return true

func poll(cargo: RefCounted, scenery: RefCounted, player_alive:=true, encounter: RefCounted=null) -> bool:
	error=""
	if _state.is_empty() or cargo==null or cargo.get_script()!=Cargo or scenery==null or scenery.get_script()!=Scenery:return reject("Mining objective needs its owned cargo and field")
	var held: Dictionary=cargo.snapshot()
	if held.get("base_content_id")!=_state.base_content_id or held.get("binding_id")!=_state.binding_id or cargo.field_identity()!=_field_identity or scenery.presentation_identity()!=_field_identity or not cargo.matches_mined_field(scenery.snapshot()):return reject("Mining objective cargo and field history do not match")
	if _rules.has("defeat_condition"):
		if not encounter is Encounter or encounter.snapshot().get("campaign_cursor")!=7:return reject("Training completion requires the retained four-actor encounter")
		var combat: Dictionary=encounter.snapshot()
		for key in ["base_content_id","binding_id"]:
			if combat.get(key)!=_state[key]:return reject("Training completion belongs to another encounter")
		if not observe_combat(encounter):return false
		if _state.phase!="collecting" or not player_alive:return true
		var condition: Dictionary=combat.controller.defeat_status
		if condition!={"kind":18,"defeated":3,"required":3,"satisfied":true}:return true
		_state.combat_objective_satisfied=true;_state.phase="return_instructions"
		return true
	if _state.phase!="collecting" or not player_alive:return true
	_state.cargo_at_check=int(held.used)
	if held.used>=int(_rules.required_cargo):
		_state.cargo_objective_satisfied=true;_state.phase="return_instructions"
	return true

func observe_combat(encounter: RefCounted) -> bool:
	error=""
	if not _rules.has("defeat_condition") or not encounter is Encounter:return reject("Training progress requires its native encounter")
	var state: Dictionary=encounter.snapshot()
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=_state[key]:return reject("Training progress belongs to another encounter")
	if state.get("campaign_cursor")!=7:return reject("Training progress has another mission")
	var counters: Dictionary=state.controller.accounting.counter_deltas
	var progress:=_initial_progress.duplicate(true)
	progress.player_kills+=int(counters.player_kills);progress.pirate_kills+=int(counters.pirate_kills)
	progress.campaign_cursor=_state.campaign_cursor
	progress.rank_score=progress.other_score+progress.player_kills*int(_progress_rules.player_kill_weight)+progress.pirate_kills*int(_progress_rules.pirate_kill_weight)+progress.campaign_cursor*int(_progress_rules.cursor_weight)
	for i in _progress_rules.rank_thresholds.size():
		if progress.rank_score>=int(_progress_rules.rank_thresholds[i]):progress.rank=i
	_state.progress=progress
	return true

func navigate(action: String) -> bool:
	error=""
	if _state.is_empty() or _state.phase!="return_instructions" or action not in ["next","previous"]:return reject("No mining return instruction awaits navigation")
	if action=="previous":
		if _state.line_index==0:return reject("No previous return instruction is available")
		_state.line_index-=1
	elif _state.line_index<_lines.size()-1:_state.line_index+=1
	else:
		if _rules.has("defeat_condition"):_state.combat_objective_acknowledged=true
		else:_state.cargo_objective_acknowledged=true
		_state.phase="return_required";_state.station_return_required=true
		_state.campaign_cursor=int(_rules.cursor_after_acknowledgement)
		_state.progress.campaign_cursor=_state.campaign_cursor
		_state.progress.rank_score+=int(_progress_rules.cursor_weight)
		for i in _progress_rules.rank_thresholds.size():
			if _state.progress.rank_score>=int(_progress_rules.rank_thresholds[i]):_state.progress.rank=i
		_state.mission={"kind":int(_rules.next_kind),"station_id":int(_rules.station_id),"reward":0,"bonus":0}
	return true

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true)
	result.dialogue={"visible":_state.phase=="return_instructions","index":_state.line_index,"count":_lines.size(),"previous_available":_state.phase=="return_instructions" and _state.line_index>0}
	if result.dialogue.visible:result.dialogue.merge(_lines[_state.line_index].duplicate(true))
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._rules=_rules.duplicate(true);copy._progress_rules=_progress_rules.duplicate(true)
	copy._lines=_lines.duplicate(true);copy._field_identity=_field_identity
	copy._initial_progress=_initial_progress.duplicate(true)
	return copy
func clear() -> void:error="";_state={};_rules={};_progress_rules={};_lines=[];_field_identity=null;_initial_progress={}
func reject(message: String) -> bool:error=message;return false

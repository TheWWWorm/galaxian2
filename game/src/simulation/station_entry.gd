extends RefCounted
## Initial Mac station visit and both mining returns. The first visit replaces
## the rescue loadout; each return preserves its ship, current vitals and cargo.
## Conversation advances only through explicit acknowledgement.
const Definitions=preload("res://src/content/station_entry_definitions.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Departure=preload("res://src/content/station_departure_definitions.gd")
const FullHoldDeparture=preload("res://src/content/full_hold_departure_definitions.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const ReturnDefinitions=preload("res://src/content/station_return_definitions.gd")
const FullHoldReturn=preload("res://src/content/full_hold_return_definitions.gd")
const Flight=preload("res://src/simulation/first_flight_frame.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
var error := ""
var _state := {}
var _lines := []
var _rules := {}
var _progress_rules := {}
var _return_rules := {}
var _equipment: RefCounted
var _equipment_rules:={}
var _equipment_lines:=[]

func configure(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, packet: Dictionary) -> bool:
	clear()
	if bindings==null or library==null or catalogues==null or not Definitions.parameters(bindings.station_entry):return fail("This pack has no supported first station visit")
	if library.manifest.get("content_id")!=bindings.base_content_id or catalogues.content_id!=bindings.base_content_id:return fail("First station belongs to another content identity")
	if packet.size()!=6 or packet.get("base_content_id")!=bindings.base_content_id or packet.get("binding_id")!=bindings.binding_id or packet.get("campaign_cursor")!=1:return fail("Station entry needs its completed rescue packet")
	if not packet.get("rescue_entry") is Dictionary or not packet.get("rescue_finished") is Dictionary:return fail("Station entry has no rescue completion evidence")
	var finish: Dictionary=packet.rescue_finished
	if finish!={"boundary":"station_transition_required","finished":[true,true,true],"fade_active":false,"fade_alpha_byte":255}:return fail("Finish the rescue and its fade before entering the station")
	if packet.get("source_state")!=int(bindings.station_entry.source_state):return fail("Unsupported station transition")
	# Reuse the rescue's complete player/progress validation; a new hull must not
	# conceal an invalid previous loadout, identity, kill credit or rank.
	var arrival:=Arrival.new()
	if arrival.restore_packet(bindings,catalogues,packet.rescue_entry)==null:return fail(arrival.error)
	var loadout:=Loadout.new()
	if not loadout.configure_station(bindings,catalogues,bindings.base_content_id):return fail(loadout.error)
	var seed:=loadout.snapshot()
	if seed.station_id!=int(bindings.station_entry.station_id) or seed.system_id!=int(bindings.station_entry.system_id):return fail("First-station location disagrees with its catalogue")
	var lines:=_read_lines(bindings,library,bindings.station_entry.dialogue.events)
	if lines.is_empty():return false
	_rules=bindings.station_entry.duplicate(true)
	_progress_rules=bindings.opening_handoff.duplicate(true)
	_lines=lines
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language,
		"campaign_cursor":1,"phase":"conversation","line_index":0,"loadout":seed,
		"source_ship_configuration":int(_rules.source_ship_configuration),"display_ship_configuration":int(_rules.display_ship_configuration),
		"source_marked_item_ids":_rules.source_marked_item_ids.map(func(id):return int(id)),
		"progress":packet.rescue_entry.progress.duplicate(true),"rescue_disposition":packet.rescue_entry.rescue_disposition.duplicate(true),
		"mission":{"kind":int(_rules.mission.kind),"station_id":seed.station_id,"reward":0,"bonus":0},
		"acknowledged":false,"reward_credits":0,"mining_completed":false}
	return true

func configure_return(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, flight: RefCounted) -> bool:
	error=""
	if bindings==null or library==null or catalogues==null or flight==null or flight.get_script()!=Flight:return fail("Station return requires its supported live flight")
	if library.manifest.get("content_id")!=bindings.base_content_id or catalogues.content_id!=bindings.base_content_id:return fail("Station return belongs to another content identity")
	var current: Dictionary=flight.snapshot()
	var packet: Dictionary=flight.prepare_station()
	if packet.is_empty():return fail(flight.error)
	var rules:=FullHoldReturn.select(bindings,packet.get("campaign_cursor"))
	if rules.is_empty():return fail("This pack has no supported conversation for the accepted station return")
	if current.get("boundary")!="station_transition_required" or packet.get("base_content_id")!=bindings.base_content_id or packet.get("binding_id")!=bindings.binding_id or packet.get("campaign_cursor")!=int(rules.campaign_cursor) or packet.get("source_state")!=int(rules.source_state):return fail("Station return needs an accepted docking transition")
	var loadout:=Loadout.new()
	if not loadout.configure_station(bindings,catalogues,bindings.base_content_id):return fail(loadout.error)
	var seed:=loadout.snapshot()
	if packet.get("loadout")!=seed or packet.get("source_ship_configuration")!=int(bindings.station_entry.source_ship_configuration):return fail("Station return changed the mining ship or equipment")
	for key in ["cargo","progress","mission","player"]:
		if packet.get(key)!=current.get(key):return fail("Station return differs from its accepted flight: "+key)
	if packet.mission!={"kind":int(rules.mission_kind),"station_id":int(rules.station_id),"reward":0,"bonus":0} or not current.cargo_objective_acknowledged:return fail("Station return has no acknowledged delivery mission")
	if not Cache.matches(packet.get("player_cache"),seed,int(rules.campaign_cursor)) or packet.player_cache!=Cache.station_arrival_cache(rules,seed,packet.player):return fail("Station return did not preserve current flight vitals")
	var lines:=_read_lines(bindings,library,rules.events)
	if lines.is_empty():return false
	var state:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language,
		"campaign_cursor":int(rules.campaign_cursor),"phase":"conversation","line_index":0,"loadout":seed,
		"source_ship_configuration":packet.source_ship_configuration,"display_ship_configuration":int(bindings.station_entry.display_ship_configuration),
		"source_marked_item_ids":bindings.station_entry.source_marked_item_ids.map(func(id):return int(id)),
		"progress":packet.progress.duplicate(true),"mission":packet.mission.duplicate(true),
		"cargo":packet.cargo.duplicate(true),"player_cache":packet.player_cache.duplicate(true),"arrival_player":packet.player.duplicate(true),
		"docking":packet.docking.duplicate(true),"flight_elapsed_ms":packet.world_elapsed_ms,
		"return_visit":true,"delivery_acknowledged":false,"acknowledged":false,"reward_credits":0,"mining_completed":false}
	_state=state;_lines=lines;_rules=bindings.station_entry.duplicate(true);_return_rules=rules.duplicate(true);_progress_rules=bindings.opening_handoff.duplicate(true)
	_equipment=null;_equipment_rules={};_equipment_lines=[]
	return true

func _read_lines(bindings: RefCounted, library: RefCounted, events: Array) -> Array:
	var lines:=[]
	for event in events:
		var id:=int(event.text_id)
		if id>=library.strings.size() or not library.strings[id] is String or library.strings[id].is_empty():fail("First-station text is unavailable in the selected language");return []
		var name: String=bindings.resolve_speaker_name(int(event.speaker_id),library)
		if not bindings.error.is_empty():fail(bindings.error);return []
		var text: String=library.strings[id]
		if "#KEY_" in text:fail("First-station instruction needs an unsupported input-key substitution");return []
		var desktop_id: int=bindings.desktop_text_id(id)
		if desktop_id<0 or desktop_id>=library.strings.size() or library.strings[desktop_id].is_empty():fail("Desktop station text is unavailable");return []
		lines.append({"speaker_id":int(event.speaker_id),"speaker_name":name,"text_id":id,"text":text,"desktop_text_id":desktop_id,"desktop_text":library.strings[desktop_id]})
	return lines

func acknowledge() -> bool:
	error=""
	if _state.is_empty() or _state.phase!="conversation":return fail("No station conversation awaits acknowledgement")
	if _state.line_index<_lines.size()-1:
		_state.line_index+=1
		return true
	if _state.get("equipment_conversation",false):
		_state.acknowledged=true;_state.equipment_acknowledged=true
		_state.phase="combat_departure_required"
		_advance_campaign(int(_equipment_rules.cursor_after_acknowledgement))
		_state.player_cache.campaign_cursor=_state.campaign_cursor
		_state.mission={"kind":int(_equipment_rules.next_mission_kind),"station_id":_state.loadout.station_id,"reward":0,"bonus":0,"source_parameter":int(_equipment_rules.next_mission_parameter)}
		return true
	_state.acknowledged=true
	_state.phase="ready_to_launch"
	_advance_campaign(int(_rules.mission.cursor_after_acknowledgement) if _return_rules.is_empty() else int(_return_rules.cursor_after_acknowledgement))
	var next_kind:=int(_rules.mission.next_kind) if _return_rules.is_empty() else int(_return_rules.next_mission_kind)
	var parameter:=int(_rules.mission.next_parameter) if _return_rules.is_empty() else int(_return_rules.next_mission_parameter)
	_state.mission={"kind":next_kind,"station_id":_state.loadout.station_id,"reward":0,"bonus":0,"source_parameter":parameter}
	if not _return_rules.is_empty():
		# Both constructors remove cargo after the final line. The second uses
		# list disposal, which retains cached used/free quantities at this point.
		# A later inventory operation owns their refresh; never retain the items.
		_state.cargo.entries=[]
		if _return_rules.get("refresh_cargo_after_acknowledgement",true):
			_state.cargo.used=0;_state.cargo.free_space=_state.cargo.capacity
		else:
			_state.cargo_cache_stale=true
			_state.phase="station_equipment_required"
		_state.player_cache.campaign_cursor=_state.campaign_cursor
		_state.delivery_acknowledged=true
	return true

func _advance_campaign(cursor: int) -> void:
	_state.campaign_cursor=cursor;_state.progress.campaign_cursor=cursor
	_state.progress.rank_score+=int(_progress_rules.cursor_weight)
	for i in _progress_rules.rank_thresholds.size():
		if _state.progress.rank_score>=int(_progress_rules.rank_thresholds[i]):_state.progress.rank=i

func open_equipment(bindings: RefCounted, catalogues: RefCounted, library: RefCounted) -> bool:
	error=""
	if _state.is_empty() or _state.phase!="station_equipment_required" or _state.get("hangar_open",false):return fail("The equipment hangar is unavailable")
	if _equipment==null:
		var candidate:=Equipment.new()
		if not candidate.configure(bindings,catalogues,_state):return fail(candidate.error)
		var lines:=_read_lines(bindings,library,bindings.station_equipment.events)
		if lines.is_empty():return false
		_equipment=candidate;_equipment_rules=bindings.station_equipment.duplicate(true);_equipment_lines=lines
	_state.hangar_open=true
	return true

func equipment_action(action: String, item_id: int) -> bool:
	error=""
	if _equipment==null or _state.phase!="station_equipment_required" or not _state.get("hangar_open",false):return fail("Open the equipment hangar first")
	var candidate: RefCounted=_equipment.fork()
	if not candidate.transact(action,item_id):return fail(candidate.error)
	var accepted: Dictionary=candidate.snapshot()
	_equipment=candidate
	_state.loadout=accepted.loadout;_state.cargo=accepted.cargo;_state.cargo_cache_stale=accepted.cargo_cache_stale
	return true

func equipment_owner() -> RefCounted:
	return null if _equipment==null else _equipment.fork()

func close_equipment() -> bool:
	error=""
	if _equipment==null or not _state.get("hangar_open",false):return fail("The equipment hangar is not open")
	_state.hangar_open=false
	if _equipment.requirements().satisfied:
		_state.phase="conversation";_state.equipment_conversation=true;_state.acknowledged=false;_state.line_index=0
		_lines=_equipment_lines.duplicate(true)
	return true

func previous() -> bool:
	error=""
	if _state.is_empty() or _state.phase!="conversation" or _state.line_index==0:return fail("No previous station line is available")
	_state.line_index-=1
	return true

func prepare_departure(bindings: RefCounted, catalogues: RefCounted) -> Dictionary:
	error=""
	# Preparation is read-only. The scene owner must obtain the source departure
	# confirmation and successfully prepare the flight before replacing station.
	if _state.is_empty() or _state.phase!="ready_to_launch" or not _state.acknowledged:
		fail("Acknowledge the station conversation before preparing departure");return {}
	if bindings==null or catalogues==null or not Departure.parameters(bindings.station_departure):
		fail("This pack has no supported first departure");return {}
	if bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id or catalogues.content_id!=_state.base_content_id or bindings.station_entry!=_rules or bindings.opening_handoff!=_progress_rules:
		fail("Departure belongs to another station or content identity");return {}
	var full_hold: bool=_state.campaign_cursor==4
	if full_hold and (not FullHoldDeparture.parameters(bindings.full_hold_departure) or _return_rules!=bindings.station_return or not ReturnDefinitions.parameters(_return_rules)):
		fail("This pack has no supported second mining departure");return {}
	var rules: Dictionary=bindings.full_hold_departure if full_hold else bindings.station_departure
	if _state.campaign_cursor!=int(rules.campaign_cursor) or _state.mining_completed or _state.reward_credits!=0:
		fail("Departure is outside the supported mining-station lifecycle");return {}
	if full_hold:
		if not _state.get("return_visit",false) or not _state.get("delivery_acknowledged",false) or not _state.get("cargo") is Dictionary:
			fail("Second departure requires the acknowledged mining delivery");return {}
		if _state.cargo.get("used")!=int(rules.initial_cargo_used) or _state.cargo.get("entries")!=[] or _state.cargo.get("capacity")!=int(rules.mission_parameter) or _state.cargo.get("free_space")!=int(rules.mission_parameter):
			fail("Second departure requires the source-cleared cargo hold");return {}
		if _state.mission!={"kind":int(rules.mission_kind),"station_id":int(rules.station_id),"reward":0,"bonus":0,"source_parameter":int(rules.mission_parameter)} or _state.progress.campaign_cursor!=int(rules.campaign_cursor):
			fail("Second departure changed the full-hold mission or progress");return {}
	var loadout:=Loadout.new()
	if not loadout.configure_station(bindings,catalogues,bindings.base_content_id):fail(loadout.error);return {}
	var seed:=loadout.snapshot()
	if seed!=_state.loadout:fail("Departure loadout differs from the station's replacement ship");return {}
	if full_hold and not Cache.matches(_state.get("player_cache"),seed,int(rules.campaign_cursor)):
		fail("Second departure lacks its retained arrival cache");return {}
	var player:=Player.new()
	if not player.configure_departure(bindings,catalogues,int(rules.campaign_cursor)):fail(player.error);return {}
	var state:=player.snapshot()
	var cache:=player.cache_snapshot()
	var reset:=Cache.departure_cache(bindings.opening_actors.player_initialization.flight_cache,rules,seed,state.max_hull,state.capacities,true)
	if reset.is_empty():fail("Departure could not clear the old ship's pools");return {}
	return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,"campaign_cursor":_state.campaign_cursor,
		"source_state":int(rules.source_state),"world_type":int(rules.world_type),"audio_selector":int(rules.audio_selector),
		"loadout":seed,"reset_cache":reset,"player_cache":cache,"player":state,
		"progress":_state.progress.duplicate(true),"mission":_state.mission.duplicate(true),
		"cargo_used":int(rules.initial_cargo_used),"source_ship_configuration":_state.source_ship_configuration,
		"confirmation_required":rules.confirmation_required,"confirmation_text_id":int(rules.confirmation_text_id)}

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true)
	if _state.phase=="station_equipment_required":result.boundary="station_equipment_required"
	if _state.phase=="combat_departure_required":result.boundary="combat_departure_required"
	if _equipment!=null:result.equipment=_equipment.snapshot()
	result.dialogue={"visible":_state.phase=="conversation","index":_state.line_index,"count":_lines.size(),"previous_available":_state.phase=="conversation" and _state.line_index>0}
	if result.dialogue.visible:result.dialogue.merge(_lines[_state.line_index].duplicate(true))
	return result

func clear() -> void:
	error="";_state={};_lines=[];_rules={};_progress_rules={};_return_rules={}
	_equipment=null;_equipment_rules={};_equipment_lines=[]

func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._state=_state.duplicate(true);result._lines=_lines.duplicate(true)
	result._rules=_rules.duplicate(true);result._progress_rules=_progress_rules.duplicate(true);result._return_rules=_return_rules.duplicate(true)
	result._equipment=_equipment.fork() if _equipment!=null else null
	result._equipment_rules=_equipment_rules.duplicate(true);result._equipment_lines=_equipment_lines.duplicate(true)
	return result

func fail(message: String) -> bool:
	error=message
	return false

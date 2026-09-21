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
const TrainingStory=preload("res://src/content/combat_training_story_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Contracts=preload("res://src/simulation/contract_session.gd")
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
const LoungeLifecycle=preload("res://src/content/lounge_lifecycle_definitions.gd")
const ContractStory=preload("res://src/content/lounge_story_definitions.gd")
const Alioth=preload("res://src/content/alioth_arrival_definitions.gd")
const AliothReturn=preload("res://src/content/alioth_return_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const FreeNavigation=preload("res://src/content/free_navigation_definitions.gd")
var error := ""
var _state := {}
var _lines := []
var _rules := {}
var _progress_rules := {}
var _return_rules := {}
var _equipment: RefCounted
var _equipment_rules:={}
var _equipment_lines:=[]
var _local_rules:={}
var _local_exchange: RefCounted
var _contracts: RefCounted
var _contract_followup: RefCounted

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

func configure_return(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, flight: RefCounted, location_settings: Dictionary={}, unix_seconds: Variant=null) -> bool:
	error=""
	if bindings==null or library==null or catalogues==null or flight==null or flight.get_script()!=Flight:return fail("Station return requires its supported live flight")
	if library.manifest.get("content_id")!=bindings.base_content_id or catalogues.content_id!=bindings.base_content_id:return fail("Station return belongs to another content identity")
	var current: Dictionary=flight.snapshot()
	if current.get("boundary")=="convoy_arrival_transition_required":return _configure_convoy_return(bindings,catalogues,library,flight,current,location_settings,unix_seconds)
	var packet: Dictionary=flight.prepare_station()
	if packet.is_empty():return fail(flight.error)
	if ContractWorld.supports(bindings,packet.get("campaign_cursor")) or (FreeFlight.Campaign.supported(bindings.mido_travel,packet.get("campaign_cursor")) and FreeFlight.available(bindings)):return _configure_contract_return(bindings,catalogues,library,flight,current,packet)
	var rules:=OrdinaryFlight.station_return(bindings,packet.get("campaign_cursor"))
	if rules.is_empty():return fail("This pack has no supported conversation for the accepted station return")
	if current.get("boundary")!="station_transition_required" or packet.get("base_content_id")!=bindings.base_content_id or packet.get("binding_id")!=bindings.binding_id or packet.get("campaign_cursor")!=int(rules.campaign_cursor) or packet.get("source_state")!=int(rules.source_state):return fail("Station return needs an accepted docking transition")
	var equipment: RefCounted=flight.equipment_owner()
	var training: bool=int(rules.campaign_cursor)==8
	var local_visit: bool=rules.get("local_visit",false)
	var alioth_return: bool=rules.get("alioth_return",false)
	var seed: Dictionary
	if training or local_visit or alioth_return:
		if equipment==null or not equipment.snapshot().get("training_inventory_released",false) or packet.get("equipment")!=equipment.snapshot() or current.get("equipment")!=equipment.snapshot():return fail("Training return lost its released inventory owner")
		seed=equipment.snapshot().loadout
	else:
		var loadout:=Loadout.new()
		if not loadout.configure_station(bindings,catalogues,bindings.base_content_id):return fail(loadout.error)
		seed=loadout.snapshot()
	if packet.get("loadout")!=seed or packet.get("source_ship_configuration")!=int(bindings.station_entry.source_ship_configuration):return fail("Station return changed its ship or equipment")
	for key in ["cargo","progress","mission","player"]:
		if packet.get(key)!=current.get(key):return fail("Station return differs from its accepted flight: "+key)
	var mission:={"kind":int(rules.mission_kind),"station_id":int(rules.station_id),"reward":0,"bonus":0}
	if local_visit or alioth_return:mission.source_parameter=0
	if packet.mission!=mission or (not local_visit and not current.get("combat_objective_acknowledged" if training or alioth_return else "cargo_objective_acknowledged",false)):return fail("Station return has no accepted mission")
	if local_visit and (seed.station_id!=int(rules.station_id) or not equipment.snapshot().get("prototype_drill_replaced",false) or packet.get("station_response_flags")!=current.get("station_response_flags")):return fail("Station visit lost its local inventory or response history")
	if not Cache.matches(packet.get("player_cache"),seed,int(rules.campaign_cursor)) or packet.player_cache!=Cache.station_arrival_cache(rules,seed,packet.player):return fail("Station return did not preserve current flight vitals")
	var retained: RefCounted;var followup: RefCounted;var exchanged: RefCounted
	if alioth_return:
		retained=flight.convoy_career_owner()
		if not AliothReturn.available(bindings) or retained==null or retained.snapshot()!=packet.get("contracts") or retained.snapshot().progress!=packet.progress or retained.snapshot().campaign_cursor!=int(rules.campaign_cursor) or seed.station_id!=int(rules.station_id):return fail("Alioth docking lost its acknowledged native career")
		if not location_settings.is_empty() and not retained.select_location(bindings,catalogues,library,int(rules.station_id),location_settings,current.random_state,unix_seconds):return fail(retained.error)
		followup=retained.fork();exchanged=equipment.fork()
		if not followup.advance_alioth_story(bindings,packet.progress,int(bindings.mido_travel.alioth_return.next_cursor)) or not exchanged.prepare_alioth_return(bindings):return fail(followup.error+exchanged.error)
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
	_equipment=equipment if training or local_visit or alioth_return else null;_equipment_rules={};_equipment_lines=[]
	_local_rules=bindings.mido_travel.alioth_return.duplicate(true) if alioth_return else {}
	_local_exchange=exchanged;_contracts=retained;_contract_followup=followup
	if alioth_return:
		_state.source_marked_item_ids=[];_state.alioth_return=true
		_state.completed_side_missions=retained.snapshot().completed_side_missions
	if training:
		_state.source_marked_item_ids=[];_state.training_return=true
	if local_visit:
		_state.source_marked_item_ids=[];_state.local_visit=true
		_state.station_response_flags=packet.station_response_flags.duplicate(true)
	return true

func _configure_convoy_return(bindings: RefCounted,catalogues: RefCounted,library: RefCounted,flight: RefCounted,current: Dictionary,location_settings: Dictionary,unix_seconds: Variant) -> bool:
	if not Alioth.available(bindings):return fail("This pack has no supported Alioth arrival")
	var packet: Dictionary=flight.prepare_convoy_station()
	if packet.is_empty():return fail(flight.error)
	var rules: Dictionary=bindings.mido_travel.alioth_arrival
	if packet.base_content_id!=bindings.base_content_id or packet.binding_id!=bindings.binding_id or packet.campaign_cursor!=int(rules.departing_cursor) or not Alioth.arrival_matches(bindings,packet.arrival):return fail("Alioth entry differs from the accepted capture")
	for key in ["player","player_cache","cargo","equipment","progress"]:
		if packet[key]!=current[key]:return fail("Alioth entry lost its retained flight: "+key)
	if not Cache.matches(packet.player_cache,packet.loadout,packet.campaign_cursor):return fail("Alioth entry lost its original flight cache")
	var equipment: RefCounted=flight.equipment_owner()
	var contracts: RefCounted=flight.convoy_career_owner()
	if equipment==null or contracts==null or equipment.snapshot()!=packet.equipment or contracts.snapshot()!=packet.contracts:return fail("Alioth entry has no retained native inventory or career")
	if not equipment.relocate_convoy_arrival(bindings,catalogues,packet.arrival):return fail(equipment.error)
	if not contracts.advance_capture_story(bindings,packet.progress,int(rules.campaign_cursor)):return fail(contracts.error)
	var lines:=_read_lines(bindings,library,rules.events)
	if lines.is_empty():return false
	var owned: Dictionary=equipment.snapshot();var career: Dictionary=contracts.snapshot()
	if not location_settings.is_empty():
		var locations: RefCounted=contracts.location_owner()
		if locations==null:return fail("The captured career lost its station cache")
		var context:={"station_id":int(rules.station_id),"campaign_cursor":int(rules.campaign_cursor),"rank":career.rank,"reputation":career.reputation}
		if not locations.select_location(bindings,catalogues,library,context,location_settings,current.random_state,unix_seconds):return fail(locations.error)
		if not contracts.retain_locations(locations):return fail(contracts.error)
		career=contracts.snapshot()
	var followup: RefCounted=contracts.fork()
	if not followup.advance_capture_story(bindings,career.progress,int(rules.next_cursor)):return fail(followup.error)
	# Capture queues state 5 directly. Unlike ordinary docking, it does not
	# overwrite the entry cache with the final live damage/charge values.
	var cached: Dictionary=packet.player_cache.duplicate(true)
	for key in Cache.IDENTITY_KEYS:cached[key]=owned.loadout[key]
	cached.campaign_cursor=int(rules.campaign_cursor)
	var state:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language,
		"campaign_cursor":int(rules.campaign_cursor),"phase":"conversation","line_index":0,"loadout":owned.loadout,
		"source_ship_configuration":packet.source_ship_configuration,"display_ship_configuration":int(bindings.station_entry.display_ship_configuration),
		"source_marked_item_ids":[],"progress":career.progress,"mission":{"kind":int(rules.mission_kind),"station_id":int(rules.station_id),"reward":0,"bonus":0,"source_parameter":0},
		"cargo":owned.cargo,"player_cache":cached,"arrival_player":packet.player,"flight_elapsed_ms":packet.world_elapsed_ms,
		"return_visit":true,"convoy_arrival":true,"acknowledged":false,"reward_credits":0,"mining_completed":false,
		"completed_side_missions":career.completed_side_missions}
	_state=state;_lines=lines;_rules=bindings.station_entry.duplicate(true);_progress_rules=bindings.opening_handoff.duplicate(true)
	_local_rules=rules.duplicate(true);_equipment=equipment;_contracts=contracts
	_return_rules={};_equipment_rules={};_equipment_lines=[];_local_exchange=null;_contract_followup=followup
	return true

func _configure_contract_return(bindings: RefCounted,catalogues: RefCounted,library: RefCounted,flight: RefCounted,current: Dictionary,packet: Dictionary) -> bool:
	if not LoungeLifecycle.available(bindings):return fail("This pack has no supported retained station contracts")
	var free_flight: bool=FreeFlight.Campaign.supported(bindings.mido_travel,packet.campaign_cursor)
	var equipment: RefCounted=flight.equipment_owner()
	var contracts: RefCounted=flight.contract_owner()
	if equipment==null or contracts==null:return fail("Station entry lost its retained inventory or contract career")
	var owned: Dictionary=equipment.snapshot()
	var seed: Dictionary=owned.loadout
	var rules:=FreeFlight.docking(bindings,int(seed.station_id),packet.campaign_cursor) if free_flight else ContractWorld.docking(bindings,int(seed.station_id),packet.campaign_cursor)
	if rules.is_empty() or current.get("boundary")!="station_transition_required" or packet.get("source_state")!=int(rules.source_state):return fail("Station contracts require actual accepted docking")
	if packet.get("base_content_id")!=bindings.base_content_id or packet.get("binding_id")!=bindings.binding_id or packet.get("contracts")!=contracts.snapshot():return fail("The station lost its accepted contract owner")
	if packet.get("equipment")!=owned or current.get("equipment")!=owned or packet.get("loadout")!=seed or packet.get("source_ship_configuration")!=int(bindings.station_entry.source_ship_configuration):return fail("Station contracts changed the arriving ship")
	for key in ["cargo","progress","mission","player","station_response_flags"]:
		if packet.get(key)!=current.get(key):return fail("Station entry differs from its accepted flight: "+key)
	var story_valid:=FreeNavigation.ordinary_departure_at(bindings,packet.campaign_cursor,packet.mission,int(seed.station_id)) if free_flight else Travel.navigation_mission(bindings.mido_travel,packet.campaign_cursor,packet.mission)
	var flags_valid:=FreeFlight.response_flags(bindings,packet.station_response_flags) if free_flight else ContractWorld.response_flags(bindings,packet.station_response_flags)
	if packet.progress!=contracts.snapshot().progress or not story_valid or not flags_valid:return fail("Station entry changed the retained story or career")
	if packet.docking.station_id!=seed.station_id or not Cache.matches(packet.get("player_cache"),seed,packet.campaign_cursor) or packet.player_cache!=Cache.station_arrival_cache(rules,seed,packet.player):return fail("Station entry changed current flight vitals or docking location")
	if not contracts.rebase_station(equipment,bindings if free_flight else null):return fail(contracts.error)
	var career: Dictionary=contracts.snapshot()
	var state:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language,
		"campaign_cursor":packet.campaign_cursor,"phase":"free_play_required" if free_flight else ("contracts_required" if packet.campaign_cursor==13 else "convoy_departure_required"),"line_index":0,"loadout":seed,
		"source_ship_configuration":packet.source_ship_configuration,"display_ship_configuration":int(bindings.station_entry.display_ship_configuration),
		"source_marked_item_ids":[],"progress":career.progress.duplicate(true),"mission":packet.mission.duplicate(true),
		"cargo":packet.cargo.duplicate(true),"player_cache":packet.player_cache.duplicate(true),"arrival_player":packet.player.duplicate(true),
		"docking":packet.docking.duplicate(true),"flight_elapsed_ms":packet.world_elapsed_ms,"station_response_flags":packet.station_response_flags.duplicate(true),
		"return_visit":true,"local_visit":true,"contract_station":true,"local_visit_acknowledged":true,
		"completed_side_missions":career.completed_side_missions,"acknowledged":true,"reward_credits":0,"mining_completed":false}
	if packet.campaign_cursor==14:state.contract_conversation_acknowledged=true
	if free_flight:state.alioth_return_acknowledged=true
	_state=state;_lines=[];_rules=bindings.station_entry.duplicate(true);_return_rules=rules;_progress_rules=bindings.opening_handoff.duplicate(true)
	_equipment=equipment;_contracts=contracts;_equipment_rules={};_equipment_lines=[];_local_rules={};_local_exchange=null;_contract_followup=null
	return true

func configure_reload(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, previous: RefCounted) -> bool:
	error=""
	if bindings==null or catalogues==null or library==null or previous==null or previous.get_script()!=get_script():return fail("Station reload requires the acknowledged station owner")
	var rules:=OrdinaryFlight.station_return(bindings,8)
	if rules.is_empty() or not rules.get("restart_station_after_acknowledgement",false):return fail("This pack has no supported station reload")
	var state: Dictionary=previous.snapshot()
	if library.manifest.get("content_id")!=bindings.base_content_id or catalogues.content_id!=bindings.base_content_id or state.get("base_content_id")!=bindings.base_content_id or state.get("binding_id")!=bindings.binding_id or state.get("language")!=library.active_language:return fail("Station reload belongs to another content identity")
	if previous._return_rules!=rules or previous._rules!=bindings.station_entry or previous._progress_rules!=bindings.opening_handoff:return fail("Station reload changed the accepted return definitions")
	if state.get("phase")!="station_reload_required" or state.get("campaign_cursor")!=int(rules.cursor_after_acknowledgement) or not state.get("training_return_acknowledged",false) or not state.get("acknowledged",false):return fail("Acknowledge the complete return conversation before reloading the station")
	var equipment: RefCounted=previous.equipment_owner()
	if equipment==null or not equipment.snapshot().get("training_inventory_released",false) or equipment.snapshot().loadout!=state.get("loadout") or equipment.snapshot().cargo!=state.get("cargo"):return fail("Station reload lost the retained training inventory")
	if not Cache.matches(state.get("player_cache"),state.loadout,int(rules.cursor_after_acknowledgement)) or state.progress.campaign_cursor!=state.campaign_cursor or state.mission!={"kind":int(rules.next_mission_kind),"station_id":int(rules.station_id),"reward":0,"bonus":0,"source_parameter":int(rules.next_mission_parameter)}:return fail("Station reload changed the accepted player or mission")
	_state=previous._state.duplicate(true)
	# The source reloads application state 5 after cursor 8's final line. The
	# following conversation has its own mission and must not be acknowledged here.
	_state.phase="station_followup_required";_state.station_reloaded=true
	_state.line_index=0;_state.acknowledged=false
	_lines=[];_rules=previous._rules.duplicate(true);_progress_rules=previous._progress_rules.duplicate(true)
	_return_rules=rules.duplicate(true);_equipment=equipment;_equipment_rules={};_equipment_lines=[]
	_local_rules={};_local_exchange=null;_contracts=null;_contract_followup=null
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

func begin_local_conversation(bindings: RefCounted, catalogues: RefCounted, library: RefCounted) -> bool:
	error=""
	# The application keeps its verified boundary until the entire travel path
	# is connected. This explicit operation prepares the next native station leg.
	if bindings==null or catalogues==null or library==null or not Travel.parameters(bindings.mido_travel):return fail("This pack has no supported Mido conversation")
	if _state.get("phase")!="station_followup_required" or not _state.get("station_reloaded",false) or _state.get("campaign_cursor")!=9 or _equipment==null:return fail("The local journey requires the acknowledged training return and station reload")
	if bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id or catalogues.content_id!=_state.base_content_id or library.manifest.get("content_id")!=_state.base_content_id or library.active_language!=_state.language:return fail("The local conversation belongs to another station or language")
	var rules: Dictionary=bindings.mido_travel.conversations[0]
	if _state.loadout.station_id!=int(rules.station_id) or _state.progress.campaign_cursor!=9 or _state.mission!={"kind":11,"station_id":78,"reward":0,"bonus":0,"source_parameter":0}:return fail("The local conversation changed the retained station objective")
	var owned: Dictionary=_equipment.snapshot()
	if owned.loadout!=_state.loadout or owned.cargo!=_state.cargo:return fail("The local conversation lost its retained inventory")
	var exchanged: RefCounted=_equipment.fork()
	if not exchanged.apply_station_exchange(bindings,catalogues,9):return fail(exchanged.error)
	var lines:=_read_lines(bindings,library,rules.events)
	if lines.is_empty():return false
	_local_rules=rules.duplicate(true);_local_exchange=exchanged;_lines=lines
	_state.phase="conversation";_state.line_index=0;_state.acknowledged=false;_state.local_conversation=true
	return true

func contract_story_ready() -> bool:
	return _contracts!=null and _state.get("phase")=="contracts_required" and _state.get("campaign_cursor")==13 and _state.mission.has("completed_contract_target") and _state.completed_side_missions>=_state.mission.completed_contract_target and _contracts.snapshot().get("pending_result",{}).is_empty()

func begin_contract_conversation(bindings: RefCounted,catalogues: RefCounted,library: RefCounted) -> bool:
	error=""
	if not ContractStory.available(bindings) or catalogues==null or library==null:return fail("The contract story continuation is unavailable")
	if _state.get("phase") not in ["contracts_required","convoy_departure_required"] or _contracts==null or _equipment==null:return fail("The story continuation requires the retained station")
	if bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id or catalogues.content_id!=_state.base_content_id or library.manifest.get("content_id")!=_state.base_content_id or library.active_language!=_state.language:return fail("The contract conversation belongs to another station or language")
	var career: Dictionary=_contracts.snapshot()
	if career.station_id!=_state.loadout.station_id or career.completed_side_missions!=_state.completed_side_missions or career.progress!=_state.progress:return fail("The station lost its earned contract career")
	var staged: RefCounted=_contracts.fork()
	if not staged.complete_story_wait(bindings,_state.mission):return fail(staged.error)
	var rules: Dictionary=bindings.mido_travel.contract_completion
	var lines:=_read_lines(bindings,library,rules.events)
	if lines.is_empty():return false
	_local_rules=rules.duplicate(true);_contract_followup=staged;_lines=lines
	_state.phase="conversation";_state.line_index=0;_state.acknowledged=false;_state.contract_conversation=true
	return true

func acknowledge() -> bool:
	error=""
	if _state.is_empty() or _state.phase!="conversation":return fail("No station conversation awaits acknowledgement")
	if _state.line_index<_lines.size()-1:
		_state.line_index+=1
		return true
	if _state.get("alioth_return",false):
		if _contracts==null or _contract_followup==null or _local_exchange==null or not AliothReturn.parameters(_local_rules):return fail("Alioth lost its prepared station continuation")
		_contracts=_contract_followup;_contract_followup=null
		_equipment=_local_exchange;_local_exchange=null
		_state.progress=_contracts.snapshot().progress.duplicate(true)
		_state.campaign_cursor=int(_local_rules.next_cursor);_state.player_cache.campaign_cursor=_state.campaign_cursor
		_state.mission={"kind":int(_local_rules.next_kind),"station_id":int(_local_rules.next_station_id),"reward":0,"bonus":0,"source_parameter":int(_local_rules.source_parameter)}
		_state.acknowledged=true;_state.alioth_return_acknowledged=true;_state.phase="free_play_required"
		return true
	if _state.get("convoy_arrival",false):
		if _contracts==null or _contract_followup==null or not Alioth.parameters(_local_rules):return fail("Alioth lost its retained story continuation")
		_contracts=_contract_followup;_contract_followup=null
		_state.progress=_contracts.snapshot().progress.duplicate(true)
		_state.campaign_cursor=int(_local_rules.next_cursor);_state.player_cache.campaign_cursor=_state.campaign_cursor
		_state.mission={"kind":int(_local_rules.next_kind),"station_id":int(_local_rules.next_station_id),"reward":0,"bonus":0,"source_parameter":0}
		_state.acknowledged=true;_state.alioth_conversation_acknowledged=true;_state.phase="alioth_departure_required"
		return true
	if _state.get("contract_conversation",false):
		if _contract_followup==null or not ContractStory.parameters(_local_rules):return fail("The contract story lost its prepared continuation")
		_contracts=_contract_followup;_contract_followup=null
		_state.progress=_contracts.snapshot().progress.duplicate(true)
		_state.campaign_cursor=int(_local_rules.next_cursor);_state.player_cache.campaign_cursor=_state.campaign_cursor
		_state.mission={"kind":int(_local_rules.next_kind),"station_id":int(_local_rules.next_station_id),"reward":int(_local_rules.reward),"bonus":int(_local_rules.bonus),"source_parameter":int(_local_rules.source_parameter)}
		_state.acknowledged=true;_state.contract_conversation_acknowledged=true;_state.phase="convoy_departure_required"
		return true
	if _state.get("local_conversation",false):
		if _local_rules.is_empty() or _local_exchange==null:return fail("The local conversation has no prepared equipment exchange")
		_equipment=_local_exchange.fork();_local_exchange=null
		var owned: Dictionary=_equipment.snapshot()
		_state.loadout=owned.loadout;_state.cargo=owned.cargo
		_state.acknowledged=true;_state.local_conversation_acknowledged=true;_state.phase="local_departure_required"
		_advance_campaign(int(_local_rules.next_cursor))
		# Station cache values remain the arrival values. Only their equipment
		# identity changes; the ordinary departure subsequently resets the pools.
		for key in Cache.IDENTITY_KEYS:_state.player_cache[key]=_state.loadout[key]
		_state.player_cache.campaign_cursor=_state.campaign_cursor
		_state.mission={"kind":int(_local_rules.next_kind),"station_id":int(_local_rules.next_station_id),"reward":0,"bonus":0,"source_parameter":0}
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
	_state.mission={"kind":next_kind,"station_id":int(_return_rules.get("next_station_id",_state.loadout.station_id)),"reward":0,"bonus":0,"source_parameter":parameter}
	if not _return_rules.is_empty():
		# Mining constructors remove cargo; the second retains cached quantities
		# until the next inventory operation. The training return keeps its cargo.
		if _return_rules.clear_cargo_after_acknowledgement:
			_state.cargo.entries=[]
			if _return_rules.get("refresh_cargo_after_acknowledgement",true):
				_state.cargo.used=0;_state.cargo.free_space=_state.cargo.capacity
			else:
				_state.cargo_cache_stale=true
				_state.phase="station_equipment_required"
		_state.player_cache.campaign_cursor=_state.campaign_cursor
		_state.delivery_acknowledged=true
		if _return_rules.get("restart_station_after_acknowledgement",false):
			_state.phase="station_reload_required";_state.training_return_acknowledged=true
		if _return_rules.get("local_visit",false):
			_state.phase="local_departure_required";_state.local_visit_acknowledged=true
			if _return_rules.has("contract_gate"):
				# Earlier supported story visits have never completed a side
				# mission. Retain the original wait objective without satisfying it.
				var gate: Dictionary=_return_rules.contract_gate
				_state.completed_side_missions=int(gate.initial_completed_count)
				_state.mission.completed_contract_target=_state.completed_side_missions+int(gate.additional_completions)
				_state.phase="contracts_required"
	return true

func _advance_campaign(cursor: int) -> void:
	_state.campaign_cursor=cursor;_state.progress.campaign_cursor=cursor
	_state.progress.rank_score+=int(_progress_rules.cursor_weight)
	for i in _progress_rules.rank_thresholds.size():
		if _state.progress.rank_score>=int(_progress_rules.rank_thresholds[i]):_state.progress.rank=i

func open_equipment(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, unix_seconds: Array=[]) -> bool:
	error=""
	if _state.is_empty() or _state.get("hangar_open",false):return fail("The equipment hangar is unavailable")
	if _state.phase=="free_play_required":
		if not _state.get("acknowledged",false) or _contracts==null or _equipment==null:return fail("Shopping requires the acknowledged station and retained inventory")
		var career: RefCounted=_contracts.fork()
		var inventory: RefCounted=career.open_shopping(bindings,catalogues,_equipment,unix_seconds,library)
		if inventory==null:return fail(career.error)
		_contracts=career;_retain_equipment(inventory);_state.hangar_open=true
		return true
	if _state.phase!="station_equipment_required":return fail("The equipment hangar is unavailable")
	if _equipment==null:
		var candidate:=Equipment.new()
		if not candidate.configure(bindings,catalogues,_state):return fail(candidate.error)
		var lines:=_read_lines(bindings,library,bindings.station_equipment.events)
		if lines.is_empty():return false
		_equipment=candidate;_equipment_rules=bindings.station_equipment.duplicate(true);_equipment_lines=lines
	_state.hangar_open=true
	return true

func equipment_action(action: String, item_id: int, bindings: RefCounted=null, catalogues: RefCounted=null, slot_index: int=-1) -> bool:
	error=""
	if _equipment==null or not _state.get("hangar_open",false):return fail("Open the equipment hangar first")
	if _state.phase=="free_play_required":
		if _contracts==null:return fail("Shopping lost its retained career")
		var career: RefCounted=_contracts.fork()
		var inventory: RefCounted=career.transact_shopping(bindings,catalogues,_equipment,action,item_id,slot_index)
		if inventory==null:return fail(career.error)
		_contracts=career;_retain_equipment(inventory)
		return true
	if _state.phase!="station_equipment_required":return fail("The equipment hangar is unavailable")
	var candidate: RefCounted=_equipment.fork()
	if not candidate.transact(action,item_id):return fail(candidate.error)
	_retain_equipment(candidate)
	return true

func _retain_equipment(candidate: RefCounted) -> void:
	var accepted: Dictionary=candidate.snapshot()
	_equipment=candidate
	_state.loadout=accepted.loadout;_state.cargo=accepted.cargo;_state.cargo_cache_stale=accepted.cargo_cache_stale

func equipment_owner() -> RefCounted:
	return null if _equipment==null else _equipment.fork()

func open_contracts(bindings: RefCounted,catalogues: RefCounted,difficulty: float=0.5) -> bool:
	error=""
	if _state.get("phase")!="contracts_required" or _equipment==null:return fail("The station has no available lounge introduction")
	if _contracts!=null:
		var retained: Dictionary=_contracts.snapshot()
		if bindings==null or catalogues==null or retained.base_content_id!=bindings.base_content_id or retained.binding_id!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id or difficulty!=float(retained.difficulty):return fail("The retained contracts belong to another career or difficulty")
		return true
	var inventory: RefCounted=_equipment.fork()
	if not inventory.prepare_contract_cargo(bindings):return fail(inventory.error)
	var contracts:=Contracts.new()
	if not contracts.configure(bindings,catalogues,_state,inventory,difficulty):return fail(contracts.error)
	_equipment=inventory;_contracts=contracts
	return true

func retain_contract_locations(cache: RefCounted) -> bool:
	error=""
	if _contracts==null or _state.get("phase") not in ["contracts_required","convoy_departure_required"]:return fail("Open the acknowledged contract session before attaching its locations")
	var candidate: RefCounted=_contracts.fork()
	if not candidate.retain_locations(cache):return fail(candidate.error)
	_contracts=candidate
	return true

func register_contract_offer(offer_id: int,offer: RefCounted) -> bool:
	error=""
	if _contracts==null:return fail("Open the available lounge before supplying its contacts")
	if not _contracts.register_offer(offer_id,offer):return fail(_contracts.error)
	return true

func populate_contracts(bindings: RefCounted,cat: RefCounted,library: RefCounted,random_state: Variant,history: Variant) -> bool:
	error=""
	if _contracts==null or _state.get("phase") not in ["contracts_required","convoy_departure_required"]:return fail("Open the available lounge before generating its contacts")
	if not _contracts.populate(bindings,cat,library,random_state,history):return fail(_contracts.error)
	return true

func contract_preview(offer_id: int,bindings: RefCounted=null) -> Dictionary:
	error=""
	if _contracts==null:fail("The lounge is not open");return {}
	var result: Dictionary=_contracts.preview(offer_id,_equipment,bindings)
	if result.is_empty():fail(_contracts.error)
	return result

func _contract_station(bindings: RefCounted) -> bool:
	return _state.get("phase") in ["contracts_required","convoy_departure_required"] or (_state.get("phase")=="free_play_required" and preload("res://src/content/ordinary_contracts_definitions.gd").available(bindings))

func accept_contract(offer_id: int,replace_current: bool=false,bindings: RefCounted=null) -> bool:
	error=""
	if _contracts==null or not _contract_station(bindings):return fail("The lounge is not open")
	var contracts: RefCounted=_contracts.fork()
	var inventory: RefCounted=contracts.accept(offer_id,_equipment,replace_current,bindings)
	if inventory==null:return fail(contracts.error)
	# Publish the independent side mission and its inventory in one operation.
	# The story wait, completed-contract count and career score are unchanged.
	var owned: Dictionary=inventory.snapshot()
	_equipment=inventory;_contracts=contracts
	_state.loadout=owned.loadout;_state.cargo=owned.cargo;_state.cargo_cache_stale=owned.cargo_cache_stale
	return true

func poll_contract_result(bindings: RefCounted=null) -> bool:
	error=""
	if _contracts==null or _equipment==null or not _contract_station(bindings):return fail("Station contracts are unavailable")
	var contracts: RefCounted=_contracts.fork()
	if not contracts.poll_station(_equipment,bindings):return fail(contracts.error)
	_contracts=contracts;_state.progress=contracts.snapshot().progress.duplicate(true)
	return true

func acknowledge_contract_result(serial: int,bindings: RefCounted=null) -> bool:
	error=""
	if _contracts==null or not _contract_station(bindings):return fail("No station contract result awaits acknowledgement")
	var pending: Dictionary=_contracts.snapshot().get("pending_result",{})
	if pending.is_empty() or pending.serial!=serial:return fail("This station result is no longer current")
	var contracts: RefCounted=_contracts.fork()
	var equipment: RefCounted=contracts.acknowledge_delivery_result(_equipment,bindings)
	if equipment==null:return fail(contracts.error)
	_contracts=contracts;_equipment=equipment
	var career: Dictionary=contracts.snapshot();var owned: Dictionary=equipment.snapshot()
	_state.progress=career.progress.duplicate(true);_state.completed_side_missions=career.completed_side_missions
	_state.loadout=owned.loadout;_state.cargo=owned.cargo;_state.cargo_cache_stale=owned.cargo_cache_stale
	return true

func close_equipment() -> bool:
	error=""
	if _equipment==null or not _state.get("hangar_open",false):return fail("The equipment hangar is not open")
	if _state.phase=="free_play_required":
		var candidate: RefCounted=_equipment.fork()
		if not candidate.close_ordinary_shopping():return fail(candidate.error)
		_retain_equipment(candidate);_state.hangar_open=false
		return true
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
	if _state.get("hangar_open",false):fail("Close the hangar before departing");return {}
	# Preparation is read-only. The scene owner must obtain the source departure
	# confirmation and successfully prepare the flight before replacing station.
	if _state.get("phase")=="combat_departure_required":return _prepare_combat_training(bindings,catalogues)
	if _state.get("phase")=="local_departure_required":return _prepare_local_departure(bindings,catalogues)
	if _state.get("phase")=="alioth_departure_required":return _prepare_alioth_departure(bindings,catalogues)
	if _state.get("phase")=="free_play_required":return _prepare_free_departure(bindings,catalogues)
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

func _prepare_combat_training(bindings: RefCounted, catalogues: RefCounted) -> Dictionary:
	if bindings==null or catalogues==null or TrainingStory.flight(bindings).is_empty() or not Departure.parameters(bindings.station_departure):fail("This pack has no supported training departure");return {}
	if not _state.get("acknowledged",false) or not _state.get("equipment_acknowledged",false) or _state.get("hangar_open",true) or _state.get("campaign_cursor")!=7 or not _equipment is Equipment:fail("Acknowledge the completed equipment tutorial before departure");return {}
	if bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id or catalogues.content_id!=_state.base_content_id or bindings.station_entry!=_rules or bindings.opening_handoff!=_progress_rules or bindings.station_equipment!=_equipment_rules:fail("Training departure belongs to another station or content identity");return {}
	var owned: Dictionary=_equipment.snapshot()
	if not _equipment.requirements().satisfied or owned.loadout!=_state.loadout or owned.cargo!=_state.cargo or owned.cargo_cache_stale:fail("Training departure requires the retained equipped ship and cargo");return {}
	if _state.mining_completed or _state.reward_credits!=0 or _state.progress.campaign_cursor!=7 or _state.mission!={"kind":4,"station_id":78,"reward":0,"bonus":0,"source_parameter":0}:fail("Training departure changed the earned mission or progress");return {}
	var player:=Player.new()
	if not player.configure_combat_training(bindings,catalogues,_equipment):fail(player.error);return {}
	var state:=player.snapshot();var seed: Dictionary=owned.loadout
	var reset:=Cache.combat_training_cache(bindings.opening_actors.player_initialization.flight_cache,bindings.combat_training_weapons,seed,state.max_hull,state.capacities,true)
	if reset.is_empty():fail("Training departure could not reset the previous flight pools");return {}
	return _equipment_departure_packet(bindings,player,reset)

func _prepare_alioth_departure(bindings: RefCounted,catalogues: RefCounted) -> Dictionary:
	if not AliothReturn.available(bindings) or catalogues==null or catalogues.content_id!=bindings.base_content_id or _contracts==null or _equipment==null or not Departure.parameters(bindings.station_departure):fail("The Alioth departure is unavailable");return {}
	if _state.get("campaign_cursor")!=16 or not _state.get("acknowledged",false) or not _state.get("alioth_conversation_acknowledged",false) or _local_rules!=bindings.mido_travel.alioth_arrival:fail("Acknowledge the Alioth conversation before departing");return {}
	var owned: Dictionary=_equipment.snapshot();var career: Dictionary=_contracts.snapshot()
	if _state.base_content_id!=bindings.base_content_id or _state.binding_id!=bindings.binding_id or owned.loadout!=_state.loadout or owned.cargo!=_state.cargo or career.progress!=_state.progress or career.campaign_cursor!=16 or owned.loadout.station_id!=98:fail("Alioth departure lost its retained inventory or career");return {}
	return _career_departure_packet(bindings,owned,career)

func _prepare_free_departure(bindings: RefCounted,catalogues: RefCounted) -> Dictionary:
	if not FreeFlight.available(bindings) or catalogues==null or catalogues.content_id!=bindings.base_content_id or not Departure.parameters(bindings.station_departure):fail("The ordinary departure is unavailable");return {}
	if not FreeFlight.Campaign.supported(bindings.mido_travel,_state.get("campaign_cursor")) or not _state.get("acknowledged",false) or not _state.get("alioth_return_acknowledged",false):fail("Acknowledge the complete Alioth return before ordinary departure");return {}
	if _contracts==null or _equipment==null:fail("Ordinary departure lost its retained career or equipment");return {}
	var career: Dictionary=_contracts.snapshot();var owned: Dictionary=_equipment.snapshot()
	var station_id: int=owned.loadout.station_id
	if owned.cargo.used>owned.cargo.capacity:fail("Cargo hold is overfilled. Sell cargo before departing.");return {}
	if FreeFlight.flight(bindings,station_id,_state.campaign_cursor).is_empty() or not FreeNavigation.ordinary_departure_at(bindings,_state.campaign_cursor,_state.get("mission",{}),station_id):fail("This station selects an unsupported story encounter");return {}
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key) or career.get(key)!=bindings.get(key):fail("Ordinary departure belongs to another content identity");return {}
	if _rules!=bindings.station_entry or _progress_rules!=bindings.opening_handoff or career.campaign_cursor!=_state.campaign_cursor or _state.progress!=career.progress or career.station_id!=station_id or owned.loadout!=_state.loadout or owned.cargo!=_state.cargo or owned.cargo_cache_stale:fail("Ordinary departure differs from its acknowledged career, location or inventory");return {}
	if _contracts.free_flight_context(bindings,station_id).is_empty():fail(_contracts.error);return {}
	if owned.get("ship_affiliation")!=int(bindings.mido_travel.alioth_return.next_player_ship_affiliation):fail("Ordinary departure lost the acknowledged ship affiliation");return {}
	if not FreeFlight.response_flags(bindings,_state.get("station_response_flags",{})):fail("Ordinary departure has unsupported station-response history");return {}
	var packet:=_career_departure_packet(bindings,owned,career)
	packet.station_response_flags=_state.get("station_response_flags",{}).duplicate(true)
	return packet

func _career_departure_packet(bindings: RefCounted,owned: Dictionary,career: Dictionary) -> Dictionary:
	# Confirmation compares retained state without generating a flight world.
	return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,"campaign_cursor":_state.campaign_cursor,
		"loadout":owned.loadout,"cargo":owned.cargo,"equipment":owned,"contracts":career,
		"mission":_state.mission.duplicate(true),"progress":_state.progress.duplicate(true),
		"confirmation_required":bindings.station_departure.confirmation_required,"confirmation_text_id":int(bindings.station_departure.confirmation_text_id)}

func prepare_contract_departure(bindings: RefCounted,catalogues: RefCounted) -> Dictionary:
	# Detached preparation is also used by the ordinary-world integration
	# checks. The application enables this path only when its frame is supported.
	error=""
	if not ContractWorld.available(bindings) or _state.get("phase") not in ["contracts_required","convoy_departure_required"] or _contracts==null or _equipment==null or not _state.get("acknowledged",false):fail("A contract departure requires the acknowledged lounge introduction and retained session");return {}
	var contracts: Dictionary=_contracts.snapshot()
	if catalogues==null or catalogues.content_id!=bindings.base_content_id or contracts.base_content_id!=bindings.base_content_id or contracts.binding_id!=bindings.binding_id or not ContractWorld.supports(bindings,_state.campaign_cursor) or contracts.campaign_cursor!=_state.campaign_cursor:fail("Contract departure belongs to another content identity");return {}
	if not contracts.get("pending_result",{}).is_empty() or contracts.has("flight"):fail("Resolve the current result or flight before departing");return {}
	var owned: Dictionary=_equipment.snapshot()
	if not _equipment.requirements().satisfied or owned.cargo_cache_stale or not owned.prototype_drill_replaced or owned.loadout!=_state.loadout or owned.cargo!=_state.cargo:fail("Contract departure lost its retained inventory");return {}
	if contracts.station_id!=owned.loadout.station_id or not Travel.navigation_mission(bindings.mido_travel,_state.campaign_cursor,_state.mission):fail("Contract departure lost its station or pending story objective");return {}
	var player:=Player.new()
	if not player.configure_local_travel(bindings,catalogues,_equipment,null,_state.campaign_cursor):fail(player.error);return {}
	var current: Dictionary=player.snapshot()
	var reset:=Cache.local_travel_cache(bindings.opening_actors.player_initialization.flight_cache,bindings.mido_travel,owned.loadout,current.max_hull,current.capacities,true,_state.campaign_cursor)
	if reset.is_empty():fail("Contract departure has no supported fresh cache");return {}
	var packet:=_equipment_departure_packet(bindings,player,reset)
	packet.progress=contracts.progress.duplicate(true)
	packet.contracts=contracts
	packet.station_response_flags=_state.get("station_response_flags",{}).duplicate(true)
	return packet

func contract_owner() -> RefCounted:return null if _contracts==null else _contracts.fork()
func has_contracts() -> bool:return _contracts!=null
func contract_locations_snapshot() -> Dictionary:return {} if _contracts==null else _contracts.locations_snapshot()

func _prepare_local_departure(bindings: RefCounted, catalogues: RefCounted) -> Dictionary:
	if bindings==null or catalogues==null or not Departure.parameters(bindings.station_departure):fail("This pack has no supported local departure");return {}
	var cursor: int=_state.campaign_cursor
	var trip:=Travel.journey(bindings.mido_travel,cursor)
	if trip.is_empty() or Travel.flight(bindings,int(trip.from_station_id),cursor).is_empty():fail("This mission has no supported departure world");return {}
	if not _state.get("acknowledged",false) or not _equipment is Equipment:fail("Acknowledge the complete local conversation before departure");return {}
	if bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id or catalogues.content_id!=_state.base_content_id or bindings.station_entry!=_rules or bindings.opening_handoff!=_progress_rules:fail("Local departure belongs to another station or content identity");return {}
	if cursor==10:
		if not _state.get("local_conversation_acknowledged",false) or bindings.mido_travel.conversations[0]!=_local_rules:fail("Local departure lost its station exchange conversation");return {}
	else:
		if not _state.get("local_visit_acknowledged",false) or _return_rules!=Travel.station_return(bindings,cursor-1) or not Travel.valid_response_flags(bindings.mido_travel,_state.get("station_response_flags"),cursor):fail("Local departure lost its acknowledged visit or station responses");return {}
	var owned: Dictionary=_equipment.snapshot()
	if not _equipment.requirements().satisfied or not owned.get("prototype_drill_replaced",false) or owned.loadout!=_state.loadout or owned.cargo!=_state.cargo or owned.cargo_cache_stale or owned.loadout.station_id!=int(trip.from_station_id):fail("Local departure lost its exchanged drill or retained cargo");return {}
	if _state.reward_credits!=0 or _state.progress.campaign_cursor!=cursor or _state.mission!={"kind":11,"station_id":int(trip.station_id),"reward":0,"bonus":0,"source_parameter":0}:fail("Local departure changed the earned progress or destination objective");return {}
	var player:=Player.new()
	if not player.configure_local_travel(bindings,catalogues,_equipment,null,cursor):fail(player.error);return {}
	var state:=player.snapshot()
	var reset:=Cache.local_travel_cache(bindings.opening_actors.player_initialization.flight_cache,bindings.mido_travel,owned.loadout,state.max_hull,state.capacities,true,cursor)
	if reset.is_empty():fail("Local departure could not reset the previous flight pools");return {}
	return _equipment_departure_packet(bindings,player,reset)

func _equipment_departure_packet(bindings: RefCounted, player: RefCounted, reset: Dictionary) -> Dictionary:
	var owned: Dictionary=_equipment.snapshot()
	var rules: Dictionary=bindings.station_departure
	var packet:={"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,"campaign_cursor":_state.campaign_cursor,
		"source_state":int(rules.source_state),"world_type":int(rules.world_type),"audio_selector":int(rules.audio_selector),
		"loadout":owned.loadout.duplicate(true),"reset_cache":reset,"player_cache":player.cache_snapshot(),"player":player.snapshot(),
		"progress":_state.progress.duplicate(true),"mission":_state.mission.duplicate(true),
		"cargo_used":int(owned.cargo.used),"cargo":owned.cargo.duplicate(true),"equipment":owned,
		"source_ship_configuration":_state.source_ship_configuration,
		"confirmation_required":rules.confirmation_required,"confirmation_text_id":int(rules.confirmation_text_id)}
	if _state.campaign_cursor in [11,12]:packet.station_response_flags=_state.station_response_flags.duplicate(true)
	return packet

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true)
	if _state.phase=="station_equipment_required":result.boundary="station_equipment_required"
	if _state.phase=="combat_departure_required":result.boundary="combat_departure_required"
	if _state.phase=="local_departure_required":result.boundary="local_departure_required"
	if _state.phase=="contracts_required":result.boundary="contracts_required"
	if _state.phase in ["station_reload_required","station_followup_required","convoy_departure_required","alioth_departure_required","free_play_required"]:result.boundary=_state.phase
	if _equipment!=null:result.equipment=_equipment.snapshot()
	if _contracts!=null:result.contracts=_contracts.snapshot()
	result.dialogue={"visible":_state.phase=="conversation","index":_state.line_index,"count":_lines.size(),"previous_available":_state.phase=="conversation" and _state.line_index>0}
	if result.dialogue.visible:result.dialogue.merge(_lines[_state.line_index].duplicate(true))
	return result

func clear() -> void:
	error="";_state={};_lines=[];_rules={};_progress_rules={};_return_rules={}
	_equipment=null;_equipment_rules={};_equipment_lines=[]
	_local_rules={};_local_exchange=null;_contracts=null;_contract_followup=null

func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._state=_state.duplicate(true);result._lines=_lines.duplicate(true)
	result._rules=_rules.duplicate(true);result._progress_rules=_progress_rules.duplicate(true);result._return_rules=_return_rules.duplicate(true)
	result._equipment=_equipment.fork() if _equipment!=null else null
	result._equipment_rules=_equipment_rules.duplicate(true);result._equipment_lines=_equipment_lines.duplicate(true)
	result._local_rules=_local_rules.duplicate(true);result._local_exchange=_local_exchange.fork() if _local_exchange!=null else null
	result._contracts=_contracts.fork() if _contracts!=null else null
	result._contract_followup=_contract_followup.fork() if _contract_followup!=null else null
	return result

func fail(message: String) -> bool:
	error=message
	return false

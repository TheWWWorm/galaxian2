extends RefCounted
## Prepares a detached supported mining world. Activation, entry-camera time,
## acknowledged briefing, manual flight and mining have separate native owners.
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const MiningFlight=preload("res://src/content/full_hold_flight_definitions.gd")
const Handoff=preload("res://src/content/opening_handoff_definitions.gd")
const Career=preload("res://src/simulation/opening_handoff.gd")
const MiningSession=preload("res://src/content/mining_session_definitions.gd")
const Location=preload("res://src/simulation/arrival_location.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Rig=preload("res://src/simulation/camera_rig.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Training=preload("res://src/content/combat_training_story_definitions.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const LocalTravel=preload("res://src/simulation/local_travel.gd")
const Transit=preload("res://src/content/convoy_transit_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
const Kappa=preload("res://src/content/kappa_population_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const Story=preload("res://src/content/story_encounter_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const FreeNavigation=preload("res://src/content/free_navigation_definitions.gd")
const Gates=preload("res://src/simulation/gate_environment.gd")
const Incoming=preload("res://src/simulation/local_arrival_environment.gd")
const GateTransit=preload("res://src/simulation/gate_transit.gd")
const GateArrival=preload("res://src/content/gate_arrival_definitions.gd")
var error:=""
var _state:={}
var _scenery: RefCounted
var _camera: RefCounted
var _player: RefCounted
var _equipment: RefCounted
var _contracts: RefCounted
var _selected_locations: RefCounted
var _void_environment: RefCounted

func prepare(bindings: RefCounted, catalogues: RefCounted, packet: Dictionary, environment_seconds: Variant, unix_seconds: Variant, large_display:=true, body_resources: RefCounted=null, effect_resources: RefCounted=null, equipment: RefCounted=null,contracts: RefCounted=null) -> bool:
	error=""
	if bindings==null or catalogues==null or not Handoff.parameters(bindings.opening_handoff):return reject("This pack has no supported mining-flight construction")
	var training: bool=packet.get("campaign_cursor")==7
	var contract_departure: bool=ContractWorld.supports(bindings,packet.get("campaign_cursor"))
	var local_departure: bool=packet.get("campaign_cursor") in [10,11,12] or ContractWorld.supports(bindings,packet.get("campaign_cursor"))
	var equipped:=training or local_departure
	var trip:=Travel.journey(bindings.mido_travel,packet.campaign_cursor) if local_departure else {}
	var data:=ContractWorld.flight(bindings,int(packet.get("loadout",{}).get("station_id",-1)),packet.campaign_cursor) if contract_departure else (Travel.flight(bindings,int(trip.get("from_station_id",-1)),packet.campaign_cursor) if local_departure else (Training.flight(bindings) if training else MiningFlight.flight(bindings,packet.get("campaign_cursor"))))
	if data.is_empty():return reject("This departure has no supported mining-flight construction")
	if contract_departure:
		if not is_instance_of(contracts,load("res://src/simulation/contract_session.gd")) or packet.get("contracts")!=contracts.snapshot():return reject("Contract departure requires its actual retained session")
		if contracts.flight_context(int(data.station_id)).is_empty():return reject(contracts.error)
	var player:=Player.new()
	var ready:=player.configure_local_travel(bindings,catalogues,equipment,null,packet.campaign_cursor) if local_departure else (player.configure_combat_training(bindings,catalogues,equipment) if training else player.configure_departure(bindings,catalogues,int(data.campaign_cursor)))
	if not ready:return reject(player.error)
	var location:=Location.new()
	var context:=location.resolve_combat_training(bindings,catalogues,equipment,player.cache_snapshot()) if training else location.resolve_departure(bindings,catalogues,packet.get("player_cache"),equipment if local_departure else null)
	if context.is_empty():return reject(location.error)
	if int(context.station_id)!=int(data.station_id):return reject("Departure construction belongs to another source station")
	if not _valid_packet(bindings,packet,context,player,equipment if equipped else null):return false
	if contract_departure and Transit.selected(bindings.mido_travel,packet.campaign_cursor,context.station_id,packet.mission):
		return _prepare_convoy_owned(bindings,catalogues,equipment,contracts,packet,environment_seconds,unix_seconds,large_display,body_resources,effect_resources)
	return _construct(bindings,catalogues,packet,data,player,context,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,equipment if equipped else null,contracts if contract_departure else null)

func prepare_convoy(bindings: RefCounted,catalogues: RefCounted,station: RefCounted,environment_seconds: Variant,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null) -> bool:
	error=""
	if not is_instance_of(station,load("res://src/simulation/station_entry.gd")):return reject("Convoy departure requires the acknowledged native station")
	var retained: Dictionary=station.snapshot()
	var data:=Convoy.flight(bindings,int(retained.get("loadout",{}).get("station_id",-1)))
	if data.is_empty():return reject("The convoy encounter starts at Kernstal; retain the current location until reaching it")
	if retained.get("phase")!="convoy_departure_required" or retained.get("campaign_cursor")!=14 or not retained.get("contract_conversation_acknowledged",false):return reject("Acknowledge the earned story conversation before the convoy")
	var contracts: RefCounted=station.contract_owner()
	var equipment: RefCounted=station.equipment_owner()
	if contracts==null or equipment==null:return reject("The convoy lost its earned career or equipment")
	var career: Dictionary=contracts.snapshot()
	var owned: Dictionary=equipment.snapshot()
	var mission:={"kind":int(data.mission_kind),"station_id":int(data.station_id),"reward":0,"bonus":0,"source_parameter":0}
	for key in ["base_content_id","binding_id"]:
		if retained.get(key)!=bindings.get(key) or career.get(key)!=bindings.get(key):return reject("The convoy belongs to another content identity")
	if retained.mission!=mission or career.campaign_cursor!=14 or retained.progress!=career.progress or career.station_id!=owned.loadout.station_id or owned.loadout!=retained.loadout or owned.cargo!=retained.cargo or owned.cargo_cache_stale:return reject("The convoy must retain the acknowledged career, location and inventory")
	return _prepare_convoy_owned(bindings,catalogues,equipment,contracts,retained,environment_seconds,unix_seconds,large_display,body_resources,effect_resources)

func _prepare_convoy_owned(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,contracts: RefCounted,retained: Dictionary,environment_seconds: Variant,unix_seconds: Variant,large_display: bool,body_resources: RefCounted,effect_resources: RefCounted,previous_cache: Variant=null) -> bool:
	var career: Dictionary=contracts.snapshot()
	var owned: Dictionary=equipment.snapshot()
	var data:=Convoy.flight(bindings,int(owned.loadout.station_id))
	var mission: Dictionary=retained.mission
	if data.is_empty() or career.campaign_cursor!=14 or career.station_id!=owned.loadout.station_id or mission!={"kind":4,"station_id":79,"reward":0,"bonus":0,"source_parameter":0}:return reject("The convoy requires the retained story at its actual target")
	var encounter:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":14,"station_id":int(data.station_id),"system_id":int(data.system_id),"mission_kind":int(data.mission_kind),"mission_story":true,"mission_completed":false,"rank":career.rank,"difficulty":career.difficulty}
	var conditions:={"companions_empty":true,"location_match":false,"special_placement":false}
	var scenery:=Scenery.new()
	if not scenery.configure_convoy(bindings,catalogues,equipment,encounter,conditions,unix_seconds,large_display,body_resources,effect_resources):return reject(scenery.error)
	var player:=Player.new()
	if not player.configure_convoy(bindings,catalogues,equipment,scenery.world_initialization_owner().npc_construction_owner(),previous_cache):return reject(player.error)
	var location:=Location.new()
	var context:=location.resolve_local_travel(bindings,catalogues,equipment,player.cache_snapshot())
	if context.is_empty():return reject(location.error)
	var packet:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":14,
		"loadout":owned.loadout.duplicate(true),"equipment":owned,"cargo":owned.cargo.duplicate(true),"cargo_used":int(owned.cargo.used),
		"progress":career.progress.duplicate(true),"mission":mission,"contracts":career,"player":player.snapshot(),"player_cache":player.cache_snapshot(),
		"station_response_flags":retained.get("station_response_flags",{}).duplicate(true),"source_ship_configuration":int(bindings.station_entry.source_ship_configuration)}
	return _construct(bindings,catalogues,packet,data,player,context,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,equipment,contracts,scenery)

func prepare_alioth(bindings: RefCounted,catalogues: RefCounted,station: RefCounted,environment_seconds: Variant,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null) -> bool:
	return _prepare_story_encounter(bindings,catalogues,station,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,false)

func prepare_kappa_rescue(bindings: RefCounted,catalogues: RefCounted,station: RefCounted,environment_seconds: Variant,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null) -> bool:
	return _prepare_story_encounter(bindings,catalogues,station,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,true)

func _prepare_story_encounter(bindings: RefCounted,catalogues: RefCounted,station: RefCounted,environment_seconds: Variant,unix_seconds: Variant,large_display: bool,body_resources: RefCounted,effect_resources: RefCounted,rescue: bool) -> bool:
	error=""
	if not is_instance_of(station,load("res://src/simulation/station_entry.gd")):return reject("Story departure requires its acknowledged native station")
	var retained: Dictionary=station.snapshot()
	var at:=int(retained.get("loadout",{}).get("station_id",-1))
	var data:=Kappa.flight(bindings,at) if rescue else Alioth.flight(bindings,at)
	var phase:="free_play_required" if rescue else "alioth_departure_required"
	var acknowledged: bool=retained.get("acknowledged",false) if rescue else retained.get("alioth_conversation_acknowledged",false)
	if data.is_empty() or retained.get("phase")!=phase or retained.get("campaign_cursor")!=int(data.campaign_cursor) or not acknowledged:return reject("Acknowledge the story's station conversation before departure")
	if rescue and station.prepare_departure(bindings,catalogues).is_empty():return reject(station.error)
	var contracts: RefCounted=station.contract_owner()
	var equipment: RefCounted=station.equipment_owner()
	if contracts==null or equipment==null:return reject("Story departure lost its retained career or inventory")
	var career: Dictionary=contracts.snapshot();var owned: Dictionary=equipment.snapshot()
	var mission:={"kind":int(data.mission_kind),"station_id":int(data.station_id),"reward":0,"bonus":0,"source_parameter":0}
	for key in ["base_content_id","binding_id"]:
		if retained.get(key)!=bindings.get(key) or career.get(key)!=bindings.get(key):return reject("Story departure belongs to another content identity")
	if retained.mission!=mission or career.campaign_cursor!=int(data.campaign_cursor) or retained.progress!=career.progress or career.station_id!=owned.loadout.station_id or owned.loadout!=retained.loadout or owned.cargo!=retained.cargo or not equipment.cargo_cache_valid():return reject("Story departure must retain the acknowledged career, location and inventory")
	var encounter:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor),"station_id":int(data.station_id),"system_id":int(data.system_id),"mission_kind":int(data.mission_kind),"mission_story":true,"mission_completed":false,"rank":career.rank,"difficulty":career.difficulty}
	var conditions:={"companions_empty":true,"location_match":false,"special_placement":false}
	var scenery:=Scenery.new()
	var position:=Vector3(data.player_position[0],data.player_position[1],data.player_position[2])
	var ready: bool=scenery.configure_kappa_rescue(bindings,catalogues,equipment,encounter,conditions,unix_seconds,large_display,body_resources,effect_resources) if rescue else scenery.configure_alioth(bindings,catalogues,equipment,encounter,position,conditions,unix_seconds,large_display,body_resources,effect_resources)
	if not ready:return reject(scenery.error)
	var player:=Player.new()
	ready=player.configure_kappa_rescue(bindings,catalogues,equipment,scenery.world_initialization_owner().npc_construction_owner()) if rescue else player.configure_alioth_attack(bindings,catalogues,equipment,scenery.world_initialization_owner().npc_construction_owner())
	if not ready:return reject(player.error)
	var location:=Location.new();var context:=location.resolve_local_travel(bindings,catalogues,equipment,player.cache_snapshot())
	if context.is_empty():return reject(location.error)
	var packet:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor),
		"loadout":owned.loadout.duplicate(true),"equipment":owned,"cargo":owned.cargo.duplicate(true),"cargo_used":int(owned.cargo.used),
		"progress":career.progress.duplicate(true),"mission":mission,"contracts":career,"player":player.snapshot(),"player_cache":player.cache_snapshot(),
		"station_response_flags":retained.get("station_response_flags",{}).duplicate(true),"source_ship_configuration":int(bindings.station_entry.source_ship_configuration)}
	if rescue:packet.kappa_context=encounter.duplicate(true)
	return _construct(bindings,catalogues,packet,data,player,context,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,equipment,contracts,scenery)

func prepare_free(bindings: RefCounted,catalogues: RefCounted,station: RefCounted,environment_seconds: Variant,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null) -> bool:
	error=""
	if not FreeFlight.available(bindings) or not is_instance_of(station,load("res://src/simulation/station_entry.gd")):return reject("Ordinary departure requires its acknowledged native station")
	var departure: Dictionary=station.prepare_departure(bindings,catalogues)
	if departure.is_empty() or not Campaign.supported(bindings.mido_travel,departure.get("campaign_cursor")):return reject(station.error if departure.is_empty() else "Ordinary departure requires its acknowledged native station")
	var contracts: RefCounted=station.contract_owner();var equipment: RefCounted=station.equipment_owner()
	return _prepare_free_owned(bindings,catalogues,equipment,contracts,departure.mission,departure.station_response_flags,environment_seconds,unix_seconds,large_display,body_resources,effect_resources)

func _prepare_free_owned(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,contracts: RefCounted,mission: Dictionary,flags: Dictionary,environment_seconds: Variant,unix_seconds: Variant,large_display: bool,body_resources: RefCounted,effect_resources: RefCounted,previous_cache: Variant=null,incoming: RefCounted=null,from_station_id: int=-1) -> bool:
	var career: Dictionary=contracts.snapshot();var owned: Dictionary=equipment.snapshot()
	var station_id: int=owned.loadout.station_id
	var cursor: int=career.campaign_cursor
	var rescue:=Campaign.rescue_at(bindings.mido_travel,cursor,station_id)
	var sahi:=Campaign.sahi_at(bindings.mido_travel,cursor,station_id)
	var accepted: Dictionary=contracts.campaign_flight_context(bindings,mission) if rescue or sahi else contracts.free_flight_context(bindings,station_id)
	if accepted.is_empty():return reject(contracts.error)
	if not FreeNavigation.destination_supported(bindings,cursor,mission,station_id):return reject("This destination selects an unsupported story encounter")
	if sahi:return _prepare_story_selected(bindings,catalogues,equipment,accepted,career.progress,flags,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,previous_cache,contracts,from_station_id,incoming)
	var data:=Kappa.flight(bindings,station_id) if rescue else FreeFlight.flight(bindings,station_id,cursor)
	if data.is_empty():return reject("This destination has no supported ordinary world")
	var context:={"campaign_cursor":cursor,"station_id":station_id,"system_id":int(data.system_id),"rank":career.rank,"difficulty":career.difficulty,
		"mission_kind":-1,"mission_completed":true,"mission_story":false,"companions_empty":true,"side_missions_empty":true,
		"station_response":flags.get(station_id,bool(bindings.mido_travel.traffic_combat.station_flag_initial))}
	context.merge((bindings.mido_travel.free_arrival.arrival_flags if incoming!=null else bindings.mido_travel.free_flight.departure_flags).duplicate(true))
	if not accepted.get("side_mission",{}).is_empty():
		context.side_missions_empty=false;context.side_mission=accepted.side_mission.duplicate(true)
		context.mission_kind=int(accepted.mission.get("kind",-1));context.mission_completed=accepted.mission.is_empty()
		context.player_position=Vector3(data.player_position[0],data.player_position[1],data.player_position[2])
	if Campaign.ordinary_story_at(bindings.mido_travel,cursor,station_id):
		context.mission_kind=int(mission.kind);context.mission_completed=false;context.mission_story=true
	if rescue:context=accepted.duplicate(true)
	if incoming!=null:context.player_position=incoming.snapshot().position
	var conditions:={"companions_empty":true,"location_match":false,"special_placement":false}
	var scenery:=Scenery.new()
	var ready: bool=scenery.configure_kappa_rescue(bindings,catalogues,equipment,context,conditions,unix_seconds,large_display,body_resources,effect_resources) if rescue else scenery.configure_free(bindings,catalogues,equipment,context,conditions,unix_seconds,large_display,body_resources,effect_resources)
	if not ready:return reject(scenery.error)
	var player:=Player.new()
	ready=player.configure_kappa_rescue(bindings,catalogues,equipment,scenery.world_initialization_owner().npc_construction_owner(),previous_cache) if rescue else player.configure_free(bindings,catalogues,equipment,scenery.world_initialization_owner().npc_construction_owner(),previous_cache)
	if not ready:return reject(player.error)
	var location:=Location.new();var place:=location.resolve_local_travel(bindings,catalogues,equipment,player.cache_snapshot())
	if place.is_empty():return reject(location.error)
	var packet:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":cursor,
		"loadout":owned.loadout.duplicate(true),"equipment":owned,"cargo":owned.cargo.duplicate(true),"cargo_used":int(owned.cargo.used),
		"progress":career.progress.duplicate(true),"mission":mission.duplicate(true),"contracts":career,
		"player":player.snapshot(),"player_cache":player.cache_snapshot(),"free_context":context,
		"station_response_flags":flags.duplicate(true),"source_ship_configuration":int(bindings.station_entry.source_ship_configuration)}
	if rescue:packet.erase("free_context");packet.kappa_context=context
	if incoming!=null:
		packet.arrival_environment=incoming.snapshot();packet.from_station_id=from_station_id
	return _construct(bindings,catalogues,packet,data,player,place,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,equipment,contracts,scenery,incoming)

## The second Void return resumes an ordinary selected visit. Its persistent
## portal never inserted a synthetic station into the retained location cache.
func prepare_portal_return(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,contracts: RefCounted,flags: Dictionary,environment_seconds: Variant,unix_seconds: Variant,large_display: bool,body_resources: RefCounted,effect_resources: RefCounted,previous_cache: Dictionary) -> bool:
	if not Campaign.expedition_available(bindings.mido_travel) or contracts==null or contracts.snapshot().get("campaign_cursor")!=30:return reject("The Dima return requires its acknowledged expedition career")
	var owned: Dictionary=equipment.snapshot()
	if owned.loadout.station_id!=91 or owned.loadout.system_id!=18 or not Cache.matches(previous_cache,owned.loadout,30):return reject("The Dima return lost its retained ship or recorded location")
	var incoming:=Incoming.new()
	if not incoming.configure(bindings,catalogues,91,contracts.location_owner(),30):return reject(incoming.error)
	return _prepare_free_owned(bindings,catalogues,equipment,contracts,Campaign.mission(bindings.mido_travel,30),flags,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,previous_cache,incoming,-1)

## Prepare the selected Sahi story world without authorizing station48 travel.
## Progress and optional career ownership are supplied by the already-earned
## caller; navigation remains separately guarded until the full transition works.
func prepare_sahi_selected(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,context: Dictionary,progress: Dictionary,station_response_flags: Dictionary,environment_seconds: Variant,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null,previous_cache: Variant=null,contracts: RefCounted=null,from_station_id: int=-1,locations: RefCounted=null) -> bool:
	if context.get("campaign_cursor")!=24:return reject("Sahi selection cannot advance the campaign")
	return _prepare_story_selected(bindings,catalogues,equipment,context,progress,station_response_flags,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,previous_cache,contracts,from_station_id,null,locations)

func prepare_dima_selected(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,context: Dictionary,progress: Dictionary,station_response_flags: Dictionary,environment_seconds: Variant,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null,previous_cache: Variant=null,contracts: RefCounted=null,from_station_id: int=-1,locations: RefCounted=null) -> bool:
	if context.get("campaign_cursor")!=28:return reject("Dima selection cannot advance the campaign")
	return _prepare_story_selected(bindings,catalogues,equipment,context,progress,station_response_flags,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,previous_cache,contracts,from_station_id,null,locations)

## The enclosing live portal transaction supplies the relocated equipment and
## actual ship cache. This does not authorize navigation or a fresh Void spawn.
func prepare_post_sahi_selected(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,context: Dictionary,progress: Dictionary,station_response_flags: Dictionary,environment_seconds: Variant,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null,previous_cache: Dictionary={},contracts: RefCounted=null,locations: RefCounted=null) -> bool:
	if context.get("campaign_cursor") not in [25,26,29] or previous_cache.is_empty():return reject("The Void entry requires its retained portal transition")
	return _prepare_story_selected(bindings,catalogues,equipment,context,progress,station_response_flags,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,previous_cache,contracts,48 if context.campaign_cursor==25 else 91 if context.campaign_cursor==29 else -1,null,locations)

func _prepare_story_selected(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,context: Dictionary,progress: Dictionary,station_response_flags: Dictionary,environment_seconds: Variant,unix_seconds: Variant,large_display: bool,body_resources: RefCounted,effect_resources: RefCounted,previous_cache: Variant,contracts: RefCounted,from_station_id: int,incoming: RefCounted=null,locations: RefCounted=null) -> bool:
	error=""
	if bindings==null or catalogues==null or not equipment is Equipment:return reject("Sahi construction requires retained equipped content")
	var data: Dictionary=Story.flight(bindings,context)
	if data.is_empty():return reject("Sahi construction requires its selected story world")
	if not Reputation.valid_state(progress.get("reputation")) or not Numbers.integer(progress.get("player_kills"),0,2147483647) or not Numbers.integer(progress.get("pirate_kills"),0,2147483647) or not Numbers.integer(progress.get("other_score"),-2147483648,2147483647):return reject("Sahi construction requires earned campaign progress")
	var expected:=Career.calculate_progress(bindings.opening_handoff,int(context.campaign_cursor),progress.player_kills,progress.pirate_kills,progress.other_score)
	if expected.is_empty():return reject("Sahi construction has unsupported career counters")
	expected.reputation=progress.reputation.duplicate(true)
	for key in ["debris_destroyed","capital_ship_kills"]:
		if not Numbers.integer(progress.get(key),0,2147483647):return reject("Sahi construction lost retained free-play progress")
		expected[key]=progress[key]
	if progress.has("cargo_recovered"):
		if not Numbers.integer(progress.cargo_recovered,0,2147483647):return reject("Story construction lost its recovered-cargo statistic")
		expected.cargo_recovered=progress.cargo_recovered
	if not MiningSession.retain_hint_history(progress,expected,bindings.mining_session) or progress!=expected or context.get("rank")!=progress.get("rank") or context.get("difficulty") not in [0.5,1.0]:return reject("Sahi construction changed earned rank, difficulty or hint history")
	if not FreeFlight.response_flags(bindings,station_response_flags):return reject("Sahi construction requires retained station responses")
	if contracts!=null:
		if not is_instance_of(contracts,load("res://src/simulation/contract_session.gd")) or contracts.snapshot().get("progress")!=progress:return reject("Sahi construction requires the matching retained career")
	elif locations!=null:
		if not is_instance_of(locations,load("res://src/simulation/lounge_cache.gd")):return reject("Selected story locations require the native cache owner")
		var retained: Dictionary=locations.snapshot()
		var retained_station:=91 if context.campaign_cursor in [28,29] else 48
		if retained.get("base_content_id")!=bindings.base_content_id or retained.get("binding_id")!=bindings.binding_id or retained.get("current_station_id")!=retained_station:return reject("Selected story locations lost their retained history")
	if context.campaign_cursor==26 and from_station_id==-1:
		incoming=Incoming.new()
		# Void selection bypasses the ordinary location cache. Selecting the
		# existing Sahi entry on return also leaves its insertion order intact.
		var history: RefCounted=contracts.location_owner() if contracts!=null else locations
		if not incoming.configure(bindings,catalogues,int(context.station_id),history,26):return reject(incoming.error)
	var environment:=_prepare_environment(bindings,data,environment_seconds,incoming)
	if environment.is_empty():return false
	if context.campaign_cursor==28:
		context=context.duplicate(true)
		context.portal_position=environment.position
	if incoming!=null:
		context=context.duplicate(true)
		context.player_pose=environment.player_pose
		context.player_position=context.player_pose.origin
	var conditions:=Story.entry_conditions(int(context.campaign_cursor))
	var scenery:=Scenery.new()
	if not scenery.configure_sahi(bindings,catalogues,equipment,context,conditions,unix_seconds,large_display,body_resources,effect_resources):return reject(scenery.error)
	var world:=scenery.world_initialization_owner()
	var population: RefCounted=null if world==null else world.npc_construction_owner()
	if population==null:return reject("Sahi construction lost its selected population")
	var player:=Player.new()
	if not player.configure_sahi(bindings,catalogues,equipment,population,previous_cache):return reject(player.error)
	var location:=Location.new();var place:=location.resolve_local_travel(bindings,catalogues,equipment,player.cache_snapshot())
	if place.is_empty() or place.station_id!=context.station_id or place.system_id!=context.system_id:return reject(location.error if not location.error.is_empty() else "Sahi construction selected another location")
	var owned: Dictionary=equipment.snapshot()
	var source_mission: Dictionary=load("res://src/content/post_sahi_definitions.gd").mission(bindings,int(context.campaign_cursor)) if int(context.campaign_cursor) in [25,26,29] else bindings.mido_travel.sahi_visit.mission
	if context.campaign_cursor==28:source_mission=bindings.mido_travel.thynome_expedition.mission28
	if source_mission.is_empty():return reject("Sahi construction lost its source mission")
	var mission:={}
	# Dialogue arrays and source selection metadata belong to their own owners,
	# not to the five scalar fields retained by an active flight mission.
	for key in ["kind","station_id","reward","bonus","source_parameter"]:mission[key]=int(source_mission[key])
	var packet:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(context.campaign_cursor),
		"loadout":owned.loadout.duplicate(true),"equipment":owned,"cargo":owned.cargo.duplicate(true),"cargo_used":int(owned.cargo.used),
		"progress":progress.duplicate(true),"mission":mission.duplicate(true),"player":player.snapshot(),"player_cache":player.cache_snapshot(),
		"sahi_context":context.duplicate(true),"station_response_flags":station_response_flags.duplicate(true),"from_station_id":from_station_id,
		"source_ship_configuration":int(bindings.station_entry.source_ship_configuration)}
	if contracts!=null:packet.contracts=contracts.snapshot()
	if incoming!=null:packet.arrival_environment=incoming.snapshot()
	if not _construct(bindings,catalogues,packet,data,player,place,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,equipment,contracts,scenery,incoming,environment):return false
	_selected_locations=locations.fork() if contracts==null and locations!=null else null
	_state.sahi_context=context.duplicate(true)
	for key in ["system_id","station_id","mission_kind","mission_story","mission_completed","mission_failed"]:_state[key]=context[key]
	return true

func prepare_local_arrival(bindings: RefCounted, catalogues: RefCounted, travel: RefCounted, source_player: RefCounted, equipment: RefCounted, environment_seconds: Variant, unix_seconds: Variant, large_display:=true, body_resources: RefCounted=null, effect_resources: RefCounted=null, objective: Dictionary={},contracts: RefCounted=null) -> bool:
	error=""
	if bindings==null or catalogues==null or not travel is LocalTravel or not source_player is Player or not equipment is Equipment:return reject("Local arrival requires the native travel, player and equipment owners")
	var packet: Dictionary=travel.prepare_arrival()
	if packet.is_empty():return reject(travel.error)
	return _prepare_arrival(bindings,catalogues,packet,source_player,equipment,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,objective,contracts,false)

func prepare_gate_arrival(bindings: RefCounted,catalogues: RefCounted,travel: RefCounted,source_player: RefCounted,equipment: RefCounted,environment_seconds: Variant,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null,objective: Dictionary={},contracts: RefCounted=null) -> bool:
	error=""
	if not travel is GateTransit or not source_player is Player or not equipment is Equipment:return reject("Gate arrival requires its native transit, player and equipment owners")
	var packet:=GateArrival.packet(bindings,catalogues,travel.arrival_request(),int(objective.get("campaign_cursor",-1)))
	if packet.is_empty():return reject("Finish the gate animation before constructing a supported destination")
	return _prepare_arrival(bindings,catalogues,packet,source_player,equipment,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,objective,contracts,true)

func _prepare_arrival(bindings: RefCounted,catalogues: RefCounted,packet: Dictionary,source_player: RefCounted,equipment: RefCounted,environment_seconds: Variant,unix_seconds: Variant,large_display: bool,body_resources: RefCounted,effect_resources: RefCounted,objective: Dictionary,contracts: RefCounted,gate_arrival: bool) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if objective.get(key)!=packet[key]:return reject("Local arrival requires the departing mission and career identity")
	var trip:=Travel.journey(bindings.mido_travel,packet.campaign_cursor)
	var contract_arrival: bool=ContractWorld.supports(bindings,packet.campaign_cursor)
	var free_arrival: bool=Travel.free_local_navigation(bindings.mido_travel,packet.campaign_cursor) and FreeFlight.available(bindings)
	if trip.is_empty() and not contract_arrival and not free_arrival:return reject("This mission has no supported arrival")
	var mission: Variant=objective.get("mission")
	if not mission is Dictionary or not Travel.navigation_mission(bindings.mido_travel,packet.campaign_cursor,mission):return reject("Local arrival changed the pending station visit")
	var progress: Variant=objective.get("progress")
	if not progress is Dictionary or not Reputation.valid_state(progress.get("reputation")):return reject("Local arrival requires the live career and reputation")
	if contract_arrival or free_arrival:
		# The retained career owns its validated counters, including recovery.
		# Arrival transfers that same observation without rebuilding an older subset.
		if not is_instance_of(contracts,load("res://src/simulation/contract_session.gd")) or contracts.snapshot().get("progress")!=progress:return reject("Local arrival requires its retained contract career")
	else:
		var expected:=Career.calculate_progress(bindings.opening_handoff,packet.campaign_cursor,progress.get("player_kills"),progress.get("pirate_kills"),progress.get("other_score"))
		if expected.is_empty():return reject("Local arrival has unsupported career counters")
		expected.reputation=progress.reputation.duplicate(true)
		if not MiningSession.retain_hint_history(progress,expected,bindings.mining_session) or progress!=expected:return reject("Local arrival career disagrees with its counters")
	var flags: Variant=objective.get("station_response_flags")
	var valid_flags: bool=FreeFlight.response_flags(bindings,flags) if free_arrival else (ContractWorld.response_flags(bindings,flags) if contract_arrival else Travel.valid_response_flags(bindings.mido_travel,flags,packet.campaign_cursor))
	if not valid_flags:return reject("Local arrival requires its retained station response")
	var destination: RefCounted=equipment.fork()
	var relocated: bool=destination.relocate_gate_arrival(bindings,catalogues,packet) if gate_arrival else destination.relocate_local_arrival(bindings,catalogues,packet)
	if not relocated:return reject(destination.error)
	var original: Dictionary=equipment.snapshot().loadout
	var departing: Dictionary=source_player.loadout()
	for key in Cache.IDENTITY_KEYS:
		if departing.get(key)!=original.get(key):return reject("Local arrival changed the departing equipped player")
	var cached:=Cache.capture_gate_arrival(bindings.mido_travel,original,destination.snapshot().loadout,source_player.snapshot()) if gate_arrival else Cache.capture_local_arrival(bindings.mido_travel,original,destination.snapshot().loadout,source_player.snapshot())
	if cached.is_empty():return reject("Local arrival requires the surviving player's current pools")
	if free_arrival:cached.campaign_cursor=packet.campaign_cursor
	if free_arrival:
		contracts=contracts.fork()
		var retained: bool=contracts.rebase_gate_arrival(bindings,catalogues,destination,packet) if gate_arrival else contracts.rebase_station(destination,bindings)
		if not retained:return reject(contracts.error)
		var incoming:=Incoming.new()
		if not incoming.configure(bindings,catalogues,int(packet.station_id),contracts.location_owner(),packet.campaign_cursor):return reject(incoming.error)
		var arrival_flags: Dictionary=flags.duplicate(true)
		arrival_flags[int(packet.station_id)]=bool(bindings.mido_travel.traffic_combat.station_flag_initial)
		return _prepare_free_owned(bindings,catalogues,destination,contracts,mission,arrival_flags,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,cached,incoming,int(packet.from_station_id))
	var player:=Player.new()
	if not player.configure_local_travel(bindings,catalogues,destination,cached,packet.campaign_cursor):return reject(player.error)
	var location:=Location.new()
	var context:=location.resolve_local_travel(bindings,catalogues,destination,player.cache_snapshot())
	if context.is_empty():return reject(location.error)
	var data:=ContractWorld.flight(bindings,int(context.station_id),packet.campaign_cursor) if contract_arrival else Travel.flight(bindings,int(context.station_id),packet.campaign_cursor)
	if data.is_empty():return reject("This local arrival has no supported world construction")
	var owned: Dictionary=destination.snapshot()
	var retained_flags: Dictionary=flags.duplicate(true)
	retained_flags[int(context.station_id)]=bool(bindings.mido_travel.traffic_combat.station_flag_initial)
	packet.merge({"player_cache":cached,"player":player.snapshot(),"loadout":owned.loadout.duplicate(true),
		"equipment":owned,"cargo":owned.cargo.duplicate(true),"cargo_used":int(owned.cargo.used),
		"progress":progress.duplicate(true),"mission":mission.duplicate(true),
		"station_response_flags":retained_flags,
		"source_ship_configuration":int(bindings.station_entry.source_ship_configuration)})
	if contract_arrival:
		contracts=contracts.fork()
		if not contracts.rebase_station(destination):return reject(contracts.error)
		packet.contracts=contracts.snapshot()
		if Transit.selected(bindings.mido_travel,packet.campaign_cursor,context.station_id,mission):
			return _prepare_convoy_owned(bindings,catalogues,destination,contracts,packet,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,cached)
	return _construct(bindings,catalogues,packet,data,player,context,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,destination,contracts if contract_arrival else null)

func _prepare_environment(bindings: RefCounted,data: Dictionary,environment_seconds: Variant,incoming: RefCounted=null) -> Dictionary:
	var random:=Random.new()
	if not Numbers.integer(environment_seconds,0,2147483647):reject("First flight requires explicit environment Unix seconds");return {}
	random.seed_from(environment_seconds)
	var input_random:=random.snapshot()
	if bindings.resolve(int(data.environment_object_resource_id),"mesh").is_empty():reject(bindings.error);return {}
	# The ordinary early-campaign environment reseeds from Unix seconds, then
	# places the wormhole before selecting yaw. Field construction reseeds again.
	var environment_position:=Vector3.ZERO
	var void_environment: RefCounted
	if int(data.campaign_cursor) in [25,29]:
		void_environment=load("res://src/simulation/void_environment.gd").new()
		if not void_environment.configure(bindings,input_random,int(data.campaign_cursor)) or not random.restore(void_environment.snapshot().random_state):reject(void_environment.error+random.error);return {}
	# The Void incoming gate consumes its two placement draws first. Its slot3
	# wormhole then uses the same source placement as other early story worlds.
	for axis in 3:environment_position[axis]=int(data.environment_object_position_offsets[axis])+random.next_int(int(data.environment_object_position_bounds[axis]))
	# Population places the Alioth portal after ordinary environment draws.
	if int(data.campaign_cursor)==16:environment_position=Vector3(bindings.mido_travel.alioth_attack.portal.position[0],bindings.mido_travel.alioth_attack.portal.position[1],bindings.mido_travel.alioth_attack.portal.position[2])
	if int(data.campaign_cursor)==28:
		var offset: Array=bindings.mido_travel.thynome_expedition.world28.portal.cast_position_offset_xyz
		environment_position+=Vector3(offset[0],offset[1],offset[2])
	var before_yaw:=random.snapshot()
	# Both portal entries retain the environment heading and bypass the normal
	# launch's random yaw. Void copies the incoming gate's position only.
	var retained_heading: bool=int(data.campaign_cursor) in [25,29] or (int(data.campaign_cursor) in [26,30] and incoming!=null)
	var units:=32768 if retained_heading else int(data.yaw_units)*(1 if random.next_int(2)==0 else -1)
	var yaw:=f32(f32(units*float(data.angle_fraction))*float(data.angle_tau))
	var pose:=Transform3D(Basis(Vector3.UP,yaw),Vector3(data.player_position[0],data.player_position[1],data.player_position[2]))
	if void_environment!=null:pose.origin=void_environment.snapshot().player_position
	if incoming!=null:
		var arrival_pose: Variant=incoming.player_pose(pose.basis)
		if not arrival_pose is Transform3D:reject(incoming.error);return {}
		pose=arrival_pose
	return {"player_pose":pose,"player_yaw_units":units,"input_random_state":input_random,
		"before_yaw_random_state":before_yaw,"yaw_random_state":random.snapshot(),
		"position":environment_position,"void_environment":void_environment}

func _construct(bindings: RefCounted, catalogues: RefCounted, packet: Dictionary, data: Dictionary, player: RefCounted, context: Dictionary, environment_seconds: Variant, unix_seconds: Variant, large_display: bool, body_resources: RefCounted, effect_resources: RefCounted, equipment: RefCounted,contracts: RefCounted=null,prepared_scenery: RefCounted=null,incoming: RefCounted=null,environment: Dictionary={}) -> bool:
	var training: bool=int(data.campaign_cursor)==7
	var local_entry: bool=int(data.campaign_cursor) in [10,11,12]
	if incoming!=null:
		if not incoming is Incoming or packet.get("arrival_environment")!=incoming.snapshot() or packet.get("sahi_context",packet.get("kappa_context",packet.get("free_context",{}))).get("player_position")!=incoming.snapshot().position:return reject("Local arrival pose differs from its generated scenery")
	if environment.is_empty():environment=_prepare_environment(bindings,data,environment_seconds,incoming)
	if environment.is_empty():return false
	var pose: Transform3D=environment.player_pose
	var void_environment: RefCounted=environment.void_environment
	var random:=Random.new()
	var conditions:=Story.entry_conditions(int(data.campaign_cursor)) if packet.has("sahi_context") else {"companions_empty":true,"location_match":false,"special_placement":false}
	var scenery: RefCounted=prepared_scenery if prepared_scenery!=null else Scenery.new()
	if prepared_scenery!=null:
		var sahi_story: bool=packet.has("sahi_context") and not Story.flight(bindings,packet.sahi_context).is_empty()
		if not prepared_scenery is Scenery or (int(data.campaign_cursor) not in [14,16,21] and not Campaign.supported(bindings.mido_travel,data.campaign_cursor) and not sahi_story):return reject("Unexpected prepared flight scenery")
		if sahi_story:
			if prepared_scenery.snapshot().world_initialization.npc_construction.get("sahi_context")!=packet.sahi_context:return reject("Sahi scenery differs from the selected story entry")
		elif packet.has("kappa_context"):
			if not Kappa.context_valid(bindings,packet.kappa_context) or prepared_scenery.snapshot().world_initialization.npc_construction.get("kappa_context")!=packet.kappa_context:return reject("Kappa scenery differs from its acknowledged departure")
		elif Campaign.supported(bindings.mido_travel,int(data.campaign_cursor)) and (not FreeFlight.available(bindings) or prepared_scenery.snapshot().world_initialization.npc_construction.get("free_context")!=packet.get("free_context")):return reject("Ordinary flight scenery differs from the acknowledged entry")
	elif contracts!=null:
		if not scenery.configure_contract(bindings,catalogues,equipment,contracts,player.cache_snapshot(),pose.origin,conditions,unix_seconds,large_display,body_resources,effect_resources):return reject(scenery.error)
	elif training:
		if not scenery.configure_combat_training(bindings,catalogues,equipment,pose.origin,conditions,unix_seconds,large_display,body_resources,effect_resources):return reject(scenery.error)
	elif local_entry:
		var trip:=Travel.journey(bindings.mido_travel,int(data.campaign_cursor))
		var ready: bool=scenery.configure_local_departure(bindings,catalogues,equipment,player.cache_snapshot(),conditions,unix_seconds,large_display,body_resources,effect_resources,0.5,int(data.campaign_cursor)) if int(context.station_id)==int(trip.from_station_id) else scenery.configure_local_arrival(bindings,catalogues,equipment,player.cache_snapshot(),conditions,unix_seconds,large_display,body_resources,effect_resources)
		if not ready:return reject(scenery.error)
	else:
		if not scenery.configure_departure(bindings,catalogues,packet.player_cache,conditions,unix_seconds,large_display,body_resources,effect_resources):return reject(scenery.error)
		if not scenery.complete_world_initialization(bindings,catalogues):return reject(scenery.error)
	var field: Dictionary=scenery.snapshot()
	if contracts!=null and prepared_scenery==null:
		var world: RefCounted=scenery.world_initialization_owner()
		if world.snapshot().contract_context.mission.get("kind",-1) in [4,7,12]:
			var contact_player:=Player.new()
			if not contact_player.configure_contract(bindings,catalogues,equipment,world.npc_construction_owner(),player.cache_snapshot()):return reject(contact_player.error)
			player=contact_player
	if not random.restore(field.random_state):return reject(random.error)
	var camera_input:=random.snapshot()
	var offset:=Vector3.ZERO
	for axis in 2:offset[axis]=int(data.camera_axis_base)+random.next_int(int(data.camera_axis_bound))
	offset.z=float(data.camera_z)
	for axis in 2:
		if random.next_int(2)==0:offset[axis]=-offset[axis]
	var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	var scene:=identity.duplicate();scene.player_pose=pose
	var shot:=identity.duplicate();shot.merge({"target":"player","mode":"follow"})
	var initial:=shot.duplicate();initial.merge({"mode":"fixed_eye","eye":pose*offset,"inherit_target_up":true},true)
	var camera:=Rig.new()
	if not camera.configure(bindings) or not camera.update(0,shot,scene,initial):return reject(camera.error)
	var state:=identity.duplicate()
	if (Campaign.supported(bindings.mido_travel,int(data.campaign_cursor)) or int(data.campaign_cursor)==26) and Gates.Definitions.available(bindings):
		var gates:=Gates.new()
		if not gates.configure(bindings,catalogues,int(context.station_id)):return reject(gates.error)
		state.gate_environment=gates.snapshot()
	state.merge({"campaign_cursor":int(data.campaign_cursor),"world_type":int(data.world_type),"location":context,
		"entry_conditions":conditions,"departure":packet.duplicate(true),"player_pose":pose,"player_yaw_units":environment.player_yaw_units,
		"camera_shot":shot,"camera_offset":offset,"input_random_state":environment.input_random_state,"before_yaw_random_state":environment.before_yaw_random_state,"yaw_random_state":environment.yaw_random_state,
		"environment_seconds":environment_seconds,"environment_object":{"resource_id":int(data.environment_object_resource_id),"position":environment.position},
		"camera_input_random_state":camera_input,"random_state":random.snapshot(),"unix_seconds":unix_seconds,
		"entry_released":false,"entry_elapsed_ms":0,"briefing_started":false,"activated":false})
	if void_environment!=null:
		state.void_environment=void_environment.snapshot()
		state.pending_station_id=state.void_environment.return_station_id
		state.pending_system_id=state.void_environment.return_system_id
	elif int(data.campaign_cursor)==26:
		state.pending_station_id=int(context.station_id);state.pending_system_id=int(context.system_id)
	# Commit only after every prospective owner accepts the complete entry.
	_state=state;_scenery=scenery;_camera=camera;_player=player;_void_environment=void_environment
	_equipment=equipment.fork() if equipment!=null else null
	_contracts=contracts.fork() if contracts!=null else null
	_selected_locations=null
	return true

func _valid_packet(bindings: RefCounted, packet: Dictionary, context: Dictionary, player: RefCounted, equipment: RefCounted=null) -> bool:
	var data: Dictionary=bindings.full_hold_departure if packet.get("campaign_cursor")==4 else bindings.station_departure
	var training: bool=packet.get("campaign_cursor")==7
	var local_departure: bool=packet.get("campaign_cursor") in [10,11,12] or ContractWorld.supports(bindings,packet.get("campaign_cursor"))
	var equipped:=training or local_departure
	if equipped:
		if not equipment is Equipment:return reject("Departure requires its native equipment owner")
		data=data.duplicate(true);data.campaign_cursor=packet.campaign_cursor if local_departure else 7;data.mission_kind=11 if local_departure else 4;data.mission_parameter=0
	if packet.size()!=(20 if ContractWorld.supports(bindings,packet.campaign_cursor) else ((19 if packet.campaign_cursor in [11,12] else 18) if equipped else 16)):return reject("First flight requires a complete departure packet")
	for key in ["base_content_id","binding_id"]:
		if packet.get(key)!=bindings.get(key):return reject("First-flight packet belongs to another content identity")
	for key in ["campaign_cursor","source_state","world_type","audio_selector","confirmation_required","confirmation_text_id"]:
		var expected: Variant=int(data[key]) if data[key] is float else data[key]
		if typeof(packet.get(key))!=typeof(expected) or packet[key]!=expected:return reject("First-flight departure field changed: "+key)
	var seed:=context.duplicate(true)
	for key in ["campaign_cursor","world_type","sky_index","sky_parameters","current_planet_texture_id"]:seed.erase(key)
	var actual: Dictionary=player.snapshot()
	var reset:=Cache.combat_training_cache(bindings.opening_actors.player_initialization.flight_cache,bindings.combat_training_weapons,seed,actual.max_hull,actual.capacities,true) if training else Cache.departure_cache(bindings.opening_actors.player_initialization.flight_cache,data,seed,actual.max_hull,actual.capacities,true)
	if local_departure:reset=Cache.local_travel_cache(bindings.opening_actors.player_initialization.flight_cache,bindings.mido_travel,seed,actual.max_hull,actual.capacities,true,packet.campaign_cursor)
	if packet.get("loadout")!=seed or packet.get("player")!=actual or packet.get("player_cache")!=player.cache_snapshot() or packet.get("reset_cache")!=reset:return reject("First flight disagrees with the fresh replacement ship")
	if equipped:
		var owned: Dictionary=equipment.snapshot()
		if packet.get("equipment")!=owned or packet.get("cargo")!=owned.cargo or packet.get("cargo_used")!=owned.cargo.used or owned.cargo_cache_stale or owned.cargo.used>owned.cargo.capacity:return reject("Training changed the earned spare equipment or cargo")
	elif packet.get("cargo_used")!=int(data.initial_cargo_used):return reject("First flight changed replacement cargo")
	if packet.get("source_ship_configuration")!=int(bindings.station_entry.source_ship_configuration):return reject("First flight changed the ship configuration")
	var progress: Variant=packet.get("progress")
	if not progress is Dictionary or not Numbers.integer(progress.get("player_kills"),0,2147483647 if local_departure else 3):return reject("First flight requires supported earned campaign progress")
	var rules: Dictionary=bindings.opening_handoff
	var kills:=int(progress.player_kills)
	var score:=kills*(int(rules.player_kill_weight)+int(rules.pirate_kill_weight))+int(data.campaign_cursor)*int(rules.cursor_weight)
	var rank:=0
	for i in rules.rank_thresholds.size():
		if score>=int(rules.rank_thresholds[i]):rank=i
	var expected_progress:={"campaign_cursor":int(data.campaign_cursor),"rank":rank,"rank_score":score,"player_kills":kills,"pirate_kills":kills,"other_score":int(rules.initial_other_score)}
	if local_departure:
		expected_progress=Career.calculate_progress(rules,data.campaign_cursor,progress.get("player_kills"),progress.get("pirate_kills"),progress.get("other_score"))
		if expected_progress.is_empty():return reject("Local departure has unsupported career counters")
	if Reputation.available(bindings):
		if not Reputation.valid_state(progress.get("reputation")):return reject("Departure lacks its actual retained reputation")
		expected_progress.reputation=progress.reputation.duplicate(true)
	if ContractWorld.supports(bindings,packet.campaign_cursor):
		if not Numbers.integer(progress.get("debris_destroyed"),0,2147483647):return reject("Contract departure lost its debris statistic")
		expected_progress.debris_destroyed=progress.debris_destroyed
	if not MiningSession.retain_hint_history(progress,expected_progress,bindings.mining_session) or progress!=expected_progress:return reject("First flight changed earned campaign progress")
	if ContractWorld.supports(bindings,packet.campaign_cursor):
		if not Travel.navigation_mission(bindings.mido_travel,packet.campaign_cursor,packet.mission) or packet.contracts.progress!=progress or not ContractWorld.response_flags(bindings,packet.station_response_flags):return reject("Contract departure changed the retained career, responses or pending story")
		return true
	var mission: Dictionary=bindings.station_entry.mission
	var mission_kind:=int(data.mission_kind) if int(data.campaign_cursor) in [4,7,10,11,12] else int(mission.next_kind)
	var mission_parameter:=int(data.mission_parameter) if int(data.campaign_cursor) in [4,7,10,11,12] else int(mission.next_parameter)
	var trip:=Travel.journey(bindings.mido_travel,int(data.campaign_cursor))
	if packet.get("mission")!={"kind":mission_kind,"station_id":int(trip.station_id) if local_departure else seed.station_id,"reward":0,"bonus":0,"source_parameter":mission_parameter}:return reject("Departure changed the source objective or granted a reward")
	if packet.campaign_cursor in [11,12] and not Travel.valid_response_flags(bindings.mido_travel,packet.get("station_response_flags"),packet.campaign_cursor):return reject("Local departure lost its station response history")
	return true

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true)
	result.scenery=_scenery.snapshot();result.camera_view=_camera.snapshot();result.player=_player.snapshot()
	return result

func scenery_owner() -> RefCounted:return null if _scenery==null else _scenery.fork_for_frame()
func camera_owner() -> RefCounted:return null if _camera==null else _camera.fork_for_frame()
func player_owner() -> RefCounted:return null if _player==null else _player.fork_for_frame()
func equipment_owner() -> RefCounted:return null if _equipment==null else _equipment.fork()
func contract_owner() -> RefCounted:return null if _contracts==null else _contracts.fork()
func selected_locations_owner() -> RefCounted:return null if _selected_locations==null else _selected_locations.fork()
func void_environment_owner() -> RefCounted:return null if _void_environment==null else _void_environment.fork()
func clear() -> void:error="";_state={};_scenery=null;_camera=null;_player=null;_equipment=null;_contracts=null;_selected_locations=null;_void_environment=null
static func f32(value: float) -> float:return PackedFloat32Array([value])[0]
func reject(message: String) -> bool:error=message;return false

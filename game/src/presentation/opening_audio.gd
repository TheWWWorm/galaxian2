extends Node3D
const LOCAL_CURSORS=[10,11,12,13,14,16,18,19]
const FACTION_CURSORS=[13,14,16,18,19]
## Audio side effects are committed only after the whole opening frame validates.
const Resources=preload("res://src/content/audio_resources.gd")
const Definitions=preload("res://src/content/audio_definitions.gd")
const Layered=preload("res://src/presentation/layered_audio.gd")
const ParameterLoop=preload("res://src/presentation/parameter_audio.gd")
const Streams=preload("res://src/presentation/audio_stream_control.gd")
const Sequence=preload("res://src/simulation/audio_sequence.gd")
const Death=preload("res://src/content/npc_destruction_definitions.gd")
const WeaponAudio=preload("res://src/content/weapon_audio_definitions.gd")
const RadioVoice=preload("res://src/content/radio_audio_definitions.gd")
const Dialogue=preload("res://src/content/dialogue_definitions.gd")
const EngineParameters=preload("res://src/simulation/engine_audio.gd")
const MiningFlight=preload("res://src/simulation/first_flight_frame.gd")
const Pirate=preload("res://src/content/full_hold_pirate_definitions.gd")
const PlayerDeath=preload("res://src/content/player_destruction_definitions.gd")
const Training=preload("res://src/content/combat_training_story_definitions.gd")
const TrainingControl=preload("res://src/content/combat_training_control_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
const LocalRadio=preload("res://src/simulation/local_traffic_radio.gd")
const PLAYER_ENGINE="player_engine"
var error := ""
var _resources: RefCounted
var _identity: RefCounted
var _revision := -1
var _players := {}
var _retiring: Array[Dictionary]=[]
var _music := -1
var _engine := -1
var _paused := false
var _listener := Transform3D.IDENTITY
var _history: Array[Dictionary]=[]
var _unsupported := {}
var _elapsed_ms := 0
var _viewport: Viewport
var _previous_listener:=false
var _seed_value:=0
var _start_serial:=0
var _random:=RandomNumberGenerator.new()
var _last_samples:={}
var _death_audio:={}
var _freighter_audio:={}
var _freighter_actors:=[]
var _debris_actors:=[]
var _debris_sound:=-1
var _notification_sound:=-1
var _notified_result_serial:=0
var _content_identity:={}
var _weapon_audio:={}
var _npc_weapon_sound:=-1
var _npc_weapon_sounds:=[]
var _npc_scan_sound:=-1
var _radio_voice:={}
var _local_radio_rules:={}
var _radio_identity:={}
var _voice_displayed: Array=[]
var _voice_serial:=0
var _engine_ids: Array=[]
var _arrival_engine_id:=-1
var _engine_generation:=-1
var _initial_engine_id:=-1
var _npc_count:=3
var _player_death_rules:={}
var _flight_identity: RefCounted
var _flight_serial:=-1
var _travel_sounds: Array[int]=[]
var _travel_attached:=false
var _travel_serial:=0

func configure(library: RefCounted, bindings: RefCounted, audio_seed: int=0, campaign_cursor: int=0, local_combat: Dictionary={}) -> bool:
	clear()
	var convoy: bool=(campaign_cursor==14 and local_combat.get("actors",[]).any(func(actor):return actor.get("convoy",false))) or campaign_cursor==16
	if campaign_cursor==4:
		if bindings==null or not Pirate.parameters(bindings.full_hold_pirate) or not PlayerDeath.parameters(bindings.player_destruction):return reject("Second-flight audio lacks its pirate and player destruction declarations")
		_npc_count=1;_player_death_rules=bindings.player_destruction.duplicate(true)
	if campaign_cursor==7:
		if bindings==null or not Training.parameters(bindings.combat_training_story) or not TrainingControl.parameters(bindings.combat_training_control) or not PlayerDeath.parameters(bindings.player_destruction):return reject("Training audio lacks its complete cast and player destruction declarations")
		_npc_count=4;_player_death_rules=bindings.player_destruction.duplicate(true)
		_npc_scan_sound=int(bindings.opening_staging.npc_scanner.acquisition_sound_id)
	if campaign_cursor in LOCAL_CURSORS:
		if bindings==null or not Travel.parameters(bindings.mido_travel) or not PlayerDeath.parameters(bindings.player_destruction):return reject("Local flight audio lacks its patrol and player destruction declarations")
		var actors: Variant=local_combat.get("actors")
		var empty_delivery: bool=ContractWorld.supports(bindings,campaign_cursor) and actors is Array and actors.is_empty() and local_combat.get("contract_encounter",{}).get("kind")==0
		if not OrdinaryFlight.combat_population(bindings,local_combat) and not empty_delivery:return reject("Local flight audio requires its generated population")
		for id in actors.size():
			if not actors[id] is Dictionary or actors[id].get("actor_id")!=id or (campaign_cursor not in FACTION_CURSORS and actors[id].get("actor_kind")!=3):return reject("Unsupported local sound owner")
		_npc_count=actors.size();_player_death_rules=bindings.player_destruction.duplicate(true)
		_npc_scan_sound=int(bindings.opening_staging.npc_scanner.acquisition_sound_id)
		_local_radio_rules={} if convoy else bindings.mido_travel.traffic_combat.radio.duplicate(true)
		if not convoy:_travel_sounds=[int(bindings.mido_travel.travel.acquisition_sound_id),int(bindings.mido_travel.travel.launch_sound_id)]
	if campaign_cursor in [11,12,13,14,16,18,19]:
		_freighter_actors=local_combat.actors.filter(func(actor):return actor.get("population_group") in ["freighter","capital"]).map(func(actor):return int(actor.actor_id))
		if not _freighter_actors.is_empty():_freighter_audio=bindings.freighter_destruction.duplicate(true)
	if campaign_cursor in FACTION_CURSORS and not convoy:
		_debris_actors=local_combat.actors.filter(func(actor):return actor.get("population_group")=="debris").map(func(actor):return int(actor.actor_id))
		_debris_sound=int(bindings.early_contracts.junk_lifecycle.sound_id)
		_notification_sound=int(bindings.early_contracts.delivery_results.notification_sound_id)
	_seed_value=audio_seed
	_random.seed=audio_seed
	_resources=Resources.new()
	if campaign_cursor in LOCAL_CURSORS and not convoy:
		if not _resources.configure_local_traffic(library,bindings):return reject(_resources.error)
	elif not _resources.configure(library,bindings,0 if campaign_cursor==4 else campaign_cursor):return reject(_resources.error)
	for id in [_npc_scan_sound,_debris_sound,_notification_sound]:
		if id>=0 and _resources.prepare(id).is_empty():return reject(_resources.error)
	for id in _travel_sounds:
		var clip: Dictionary=_resources.prepare(id)
		if clip.is_empty() or clip.has("unsupported"):return reject("Local travel sound is unsupported: "+str(id)+" "+str(clip.get("unsupported",_resources.error)))
	_content_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	for id in bindings.vehicle_response.get("audio",{}).get("event_ids",[]):_engine_ids.append(int(id))
	_arrival_engine_id=int(bindings.opening_staging.get("escape",{}).get("arrival_engine_sound_id",-1))
	_radio_voice=Dialogue.select(bindings,campaign_cursor).get("voice",{}) if campaign_cursor in [0,1,7] or convoy else {}
	if not _radio_voice.is_empty():
		if not RadioVoice.parameters(_radio_voice,Dialogue.select(bindings,campaign_cursor).events.size()):return reject("Invalid radio voice capability")
		_radio_voice=_radio_voice.duplicate(true)
		_radio_identity=_content_identity.duplicate();_radio_identity.language=library.active_language
		if campaign_cursor!=0:_radio_identity.campaign_cursor=campaign_cursor
		_voice_displayed.resize(_radio_voice.event_ids.size());_voice_displayed.fill(false)
		for id in _radio_voice.event_ids:
			if id>=0 and _resources.prepare(int(id)).is_empty():return reject(_resources.error)
	if not _local_radio_rules.is_empty():
		_radio_identity=_content_identity.duplicate();_radio_identity.language=library.active_language;_radio_identity.campaign_cursor=campaign_cursor
		_voice_displayed=[false,false]
		for id in _local_radio_rules.warning_voice_ids+_local_radio_rules.response_voice_ids:
			if _resources.prepare(int(id)).is_empty():return reject(_resources.error)
	_weapon_audio=bindings.weapon_parameters.get("audio",{}) if campaign_cursor in [0,4,7,10,11,12,13,14,16,18,19] else {}
	if not _weapon_audio.is_empty():
		if not WeaponAudio.parameters(_weapon_audio):return reject("Invalid weapon audio capability")
		_weapon_audio=_weapon_audio.duplicate(true)
		var kind: int=int(bindings.opening_actors.get("npc_initialization",{}).get("primary_weapon",{}).get("actor_kind",-1))
		if campaign_cursor==4:kind=int(bindings.full_hold_pirate.actor_kind)
		if campaign_cursor in LOCAL_CURSORS:kind=int(bindings.mido_travel.traffic_combat.actor_kind)
		if kind<0:return reject("Weapon audio requires its NPC owner")
		_npc_weapon_sound=int(_weapon_audio.npc_event_ids[kind]) if kind<_weapon_audio.npc_event_ids.size() else int(_weapon_audio.npc_default_event_id)
		for id in _npc_count:
			var actor_kind:=int(local_combat.actors[id].actor_kind) if campaign_cursor in FACTION_CURSORS else (int(bindings.combat_training_control.actor_kinds[id]) if campaign_cursor==7 else kind)
			if actor_kind<0:_npc_weapon_sounds.append(-1);continue
			var sound:=int(_weapon_audio.npc_event_ids[actor_kind]) if actor_kind<_weapon_audio.npc_event_ids.size() else int(_weapon_audio.npc_default_event_id)
			_npc_weapon_sounds.append(sound)
			if _resources.prepare(sound).is_empty():return reject(_resources.error)
	_death_audio=bindings.opening_actors.get("npc_initialization",{}).get("destruction_audio",{}) if campaign_cursor in [0,4,7,10,11,12,13,14,16,18,19] else {}
	if not _death_audio.is_empty():
		if not Death.audio_parameters(_death_audio):return reject("Invalid NPC destruction audio capability")
		_death_audio=_death_audio.duplicate(true)
		_death_audio.initial_source_id=int(_death_audio.initial_source_id)
		_death_audio.breakup_source_ids=[int(_death_audio.breakup_source_ids[0]),int(_death_audio.breakup_source_ids[1])]
		for id in [_death_audio.initial_source_id]+_death_audio.breakup_source_ids:
			if _resources.prepare(int(id)).is_empty():return reject(_resources.error)
	if campaign_cursor in [4,7,10,11,12,13,14,16,18,19]:
		if _weapon_audio.is_empty() or _death_audio.is_empty():return reject("Second-flight combat audio is unavailable")
		for id in [int(_player_death_rules.breakup_sound_base),int(_player_death_rules.breakup_sound_base)+1,int(_player_death_rules.failure_sound),_npc_weapon_sound,int(_death_audio.initial_source_id)]:
			var clip: Dictionary=_resources.prepare(id)
			if clip.is_empty() or clip.has("unsupported"):return reject("Unsupported second-flight sound: "+str(id)+" "+str(clip.get("unsupported",_resources.error)))
	_identity=RefCounted.new()
	_viewport=get_viewport()
	_previous_listener=_viewport.is_audio_listener_3d()
	_viewport.set_as_audio_listener_3d(true)
	var escape: Dictionary=bindings.opening_staging.get("escape",{}) if campaign_cursor==0 else {}
	if not escape.is_empty():
		var ids: Array=[escape.entry_music_id,escape.jump_music_id,escape.exit_sound_id,escape.arrival_sound_id,escape.arrival_engine_sound_id]
		ids.append_array(escape.drive_sound_ids)
		for id in ids:
			if _resources.prepare(int(id)).is_empty():return reject(_resources.error)
	return true

func configure_full_hold(library: RefCounted,bindings: RefCounted,world: RefCounted,audio_seed: int=0) -> bool:
	if not world is MiningFlight or world.destruction_owner()==null:return reject("Second-flight audio requires its native destruction owner")
	var state: Dictionary=world.snapshot()
	for key in ["base_content_id","binding_id"]:
		if bindings==null or state.get(key)!=bindings.get(key):return reject("Second-flight audio belongs to another content identity")
	if not state.get("flight_audio") is Dictionary or state.flight_audio.get("serial")!=0:return reject("Register second-flight audio before advancing its world")
	var cursor: int=world.destruction_owner().snapshot().departure_cursor
	if cursor not in [4,7,10,11,12,13,14,16,18,19] or state.campaign_cursor!=cursor:return reject("Register ordinary-flight sound in its initial mission")
	var travel: Variant=state.get("local_travel",{})
	if not travel is Dictionary or (not travel.is_empty() and (cursor not in LOCAL_CURSORS or travel.get("event_serial")!=0 or travel.get("events")!=[])):return reject("Register local travel audio before its first event")
	if not configure(library,bindings,audio_seed,cursor,state.get("encounter",{}).get("combat",{}) if cursor in LOCAL_CURSORS else {}):return false
	_notified_result_serial=int(state.get("contracts",{}).get("last_result",{}).get("serial",0))
	_travel_attached=not travel.is_empty()
	_flight_identity=world.destruction_owner().presentation_identity()
	return true

func prepare_full_hold(world: RefCounted) -> Dictionary:
	error=""
	if not world is MiningFlight or _flight_identity==null or world.destruction_owner()==null or world.destruction_owner().presentation_identity()!=_flight_identity:return fail("Second-flight audio follows one configured native world")
	var state: Dictionary=world.snapshot()
	for key in _content_identity:
		if state.get(key)!=_content_identity[key]:return fail("Second-flight audio frame changed content identity")
	var cues: Variant=state.get("flight_audio")
	var elapsed: Variant=state.get("encounter",{}).get("elapsed_ms")
	if not cues is Dictionary or cues.size()!=4 or not Definitions.integer(cues.get("serial"),maxi(0,_flight_serial),_flight_serial+1) or not Definitions.integer(elapsed,_elapsed_ms,0x7fffffff):return fail("Second-flight audio frame is out of sequence")
	var travel:=prepare_travel(state)
	if travel.is_empty():return {}
	var notification:=prepare_contract_notification(state)
	if notification.is_empty():return {}
	var repeated: bool=cues.serial==_flight_serial
	if repeated:
		if elapsed!=_elapsed_ms:return fail("Repeated second-flight sound frame changed its clock")
		if travel.operations.is_empty() and notification.serial==_notified_result_serial:return {"identity":_identity,"revision":_revision,"repeat":true}
		if not travel.operations.is_empty() and (travel.operations.size()!=1 or travel.operations[0].source_id!=_travel_sounds[1]):return fail("A manual travel action emitted a flight acquisition cue")
	var commands: Array[Dictionary]=[]
	if not repeated:
		for phase in ["player_tail","player_poll"]:
			var prepared:=prepare_player_death(cues.get(phase),phase)
			if prepared.is_empty():return {}
			commands.append_array(prepared.operations)
		if state.has("convoy_capture"):
			var capture: Dictionary=state.convoy_capture
			if capture.get("campaign_cursor")!=14:return fail("Capture audio belongs to another scene")
			for cue in capture.get("frame",{}).get("audio",[]):
				if cue.get("source_id")!=15 or cue.get("action") not in ["start","start_spatial"]:return fail("Capture requested an unsupported sound")
				commands.append(cue.duplicate(true))
			if capture.get("frame",{}).get("disable_player",false):commands.append({"action":"stop_player_engine"})
		for event in state.get("npc_scanner_events",[]):
			if not event is Dictionary or event.get("kind")!="sound" or event.get("source_id")!=_npc_scan_sound or not Definitions.integer(event.get("actor_id"),0,_npc_count-1):return fail("Invalid training acquisition sound")
			commands.append({"action":"start","source_id":_npc_scan_sound})
	var view:={"elapsed_ms":int(elapsed),"camera":{"view":state.camera_view},"escape":{"frame":{"audio":commands}}}
	if state.has("radio"):
		view.radio=state.radio;view.radio_changes=[] if repeated else state.radio_events
	var combat:={}
	if not repeated:
		combat=_content_identity.duplicate()
		for key in ["primary_fire","primaries"]:
			if state.encounter.has(key):combat[key]=state.encounter[key]
		combat.elapsed_ms=int(elapsed);combat.actor_events=cues.get("actors")
	var result:=prepare_frame(_revision+1,view,combat,travel.operations+notification.operations)
	if result.is_empty():return {}
	result.flight_serial=int(cues.serial)
	result.travel_serial=int(travel.serial)
	result.contract_result_serial=int(notification.serial)
	return result

func prepare_contract_notification(state: Dictionary) -> Dictionary:
	var result: Dictionary=state.get("contracts",{}).get("last_result",{})
	var operations: Array[Dictionary]=[]
	var serial:=int(result.get("serial",0))
	if serial==_notified_result_serial:return {"serial":serial,"operations":operations}
	if _notification_sound<0 or serial!=_notified_result_serial+1 or result.get("acknowledgement_required",true):return fail("Contract payment sound lost its acknowledged result")
	var id:=int(result.get("notification_sound_id",-1))
	if id>=0:
		if id!=_notification_sound or not result.get("completed",false):return fail("Contract result requested another payment sound")
		operations.append({"action":"start","source_id":id,"contract_result_serial":serial})
	return {"serial":serial,"operations":operations}

func prepare_travel(state: Dictionary) -> Dictionary:
	var operations: Array[Dictionary]=[]
	var travel: Variant=state.get("local_travel",{})
	if not travel is Dictionary:return fail("Invalid local travel audio owner")
	if (not travel.is_empty())!=_travel_attached:return fail("Local travel audio lost its configured world owner")
	if not _travel_attached:return {"serial":0,"operations":operations}
	for key in _content_identity:
		if travel.get(key)!=_content_identity[key]:return fail("Local travel sound changed its content identity")
	var serial: Variant=travel.get("event_serial");var events: Variant=travel.get("events")
	if _travel_sounds.size()!=2 or not Definitions.integer(serial,_travel_serial,_travel_serial+1) or not events is Array or events.size()>2:return fail("Local travel sound batch is out of sequence")
	var ids: Array[int]=[]
	for event in events:
		if not event is Dictionary or event.size()!=2 or event.get("kind")!="sound" or not Definitions.integer(event.get("source_id"),0,19999) or not _travel_sounds.has(int(event.source_id)):return fail("Invalid local travel sound event")
		ids.append(int(event.source_id))
	if ids.size()==2 and ids!=_travel_sounds:return fail("Local travel sounds changed their acquisition/launch order")
	if serial==_travel_serial:return {"serial":serial,"operations":operations}
	if ids.is_empty() or not Definitions.integer(travel.get("acquired_station_id"),0,2147483647):return fail("Local travel sound has no acquired destination")
	if travel.get("phase") not in ["flight","launch"] or (travel.phase=="launch" and ids.back()!=_travel_sounds[1]):return fail("Local travel sound is missing its departure transition")
	if ids.has(_travel_sounds[1]) and (travel.get("phase")!="launch" or travel.get("launch_ms")!=0 or travel.get("destination_station_id")!=travel.acquired_station_id):return fail("Local launch sound has no new departure")
	for id in ids:operations.append({"action":"start","source_id":id,"travel_serial":int(serial),"destination_station_id":int(travel.acquired_station_id)})
	return {"serial":int(serial),"operations":operations}

func prepare_player_death(events: Variant,phase: String) -> Dictionary:
	if not events is Dictionary:return fail("Invalid player destruction sound phase")
	var operations: Array[Dictionary]=[]
	if events.is_empty():return {"operations":operations}
	for flag in ["started","breakup","failed"]:
		if not events.get(flag) is bool:return fail("Invalid player destruction sound transition")
	if events.started and (phase!="player_poll" or events.breakup or events.failed):return fail("Player destruction started outside its poll")
	var ids: Variant=events.get("sound_events");var cues: Variant=events.get("audio_events")
	if not ids is Array or not cues is Array or ids.size()!=int(events.breakup)+int(events.failed) or cues.size()!=ids.size():return fail("Player sounds differ from their death transitions")
	for i in cues.size():
		var cue: Variant=cues[i]
		if not cue is Dictionary or cue.size()!=2 or not cue.has("position") or cue.get("source_id")!=ids[i]:return fail("Invalid player destruction sound cue")
		var breakup: bool=events.breakup and i==0
		if breakup:
			if not Definitions.integer(ids[i],int(_player_death_rules.breakup_sound_base),int(_player_death_rules.breakup_sound_base)+int(_player_death_rules.breakup_sound_bound)-1) or not cue.get("position") is Vector3 or not cue.position.is_finite():return fail("Invalid player breakup sound or position")
			if phase=="player_tail":operations.append({"action":"start_spatial","source_id":int(ids[i]),"position":cue.position,"actor_id":"player"})
		else:
			if ids[i]!=int(_player_death_rules.failure_sound) or cue.get("position")!=null:return fail("Invalid player failure sound")
			if phase=="player_poll":operations.append({"action":"start","source_id":int(ids[i]),"actor_id":"player"})
	if events.started:
		if events.get("stop_current_music")!=true or events.get("stop_current_engine_sound")!=true:return fail("Player death changed its current music/engine stops")
		var stops: Variant=events.get("stop_sound_ids")
		if not stops is Array or stops.size()!=_player_death_rules.stop_sound_ids.size():return fail("Player death changed its source sound stop extent")
		for i in stops.size():
			if not Definitions.integer(stops[i],int(_player_death_rules.stop_sound_ids[i]),int(_player_death_rules.stop_sound_ids[i])):return fail("Player death changed its source sound stop order")
		operations.append({"action":"stop_music"});operations.append({"action":"stop_player_engine"})
		for id in events.stop_sound_ids:operations.append({"action":"stop","source_id":int(id)})
	return {"operations":operations}

func prepare_frame(revision: int, state: Dictionary, world: Dictionary={}, following_audio: Array[Dictionary]=[]) -> Dictionary:
	error=""
	if _identity==null or revision<_revision or revision>_revision+1:return fail("Audio frame revision is out of sequence")
	if revision==_revision:return {"identity":_identity,"revision":revision,"repeat":true}
	var view: Variant=state.get("camera",{}).get("view",{}).get("pose",Transform3D.IDENTITY)
	if not view is Transform3D or not view.is_finite():return fail("Invalid audio listener pose")
	var elapsed: Variant=state.get("elapsed_ms")
	if not Definitions.integer(elapsed,_elapsed_ms,0x7fffffff):return fail("Invalid audio clock")
	var layer_frames: Array[Dictionary]=[]
	for record in _players.values()+_retiring:
		if record.node is Layered:
			var frame: Dictionary=record.node.prepare_step(int(elapsed)-_elapsed_ms)
			if frame.is_empty():return fail(record.node.error)
			layer_frames.append({"node":record.node,"frame":frame})
	var commands: Variant=state.get("escape",{}).get("frame",{}).get("audio",[])
	if not commands is Array or commands.size()>32:return fail("Invalid opening audio commands")
	commands=commands.duplicate(true)
	if (not _death_audio.is_empty() or not _weapon_audio.is_empty()) and not world.is_empty():
		var combat_frame:=prepare_combat(world,int(elapsed))
		if combat_frame.is_empty():return {}
		commands.append_array(combat_frame.operations)
	var radio_frame:=prepare_radio(state)
	if radio_frame.is_empty():return {}
	commands.append_array(radio_frame.operations)
	if following_audio.size()>2:return fail("Too many trailing flight sounds")
	commands.append_array(following_audio)
	var operations: Array[Dictionary]=[]
	for command in commands:
		if not command is Dictionary:return fail("Invalid opening audio operation")
		var action: Variant=command.get("action")
		if action not in ["replace_music","start","start_spatial","position","stop","stop_music","stop_player_engine","set_player_engine"]:return fail("Unsupported opening audio operation")
		var op: Dictionary=command.duplicate(true)
		if action not in ["stop_music","stop_player_engine"]:
			if not Definitions.integer(command.get("source_id"),0,19999):return fail("Invalid opening sound identifier")
			op.source_id=int(command.source_id)
		if action in ["start_spatial","position"]:
			if not command.get("position") is Vector3 or not command.position.is_finite():return fail("Invalid opening sound position")
		if command.has("pitch_raw") and (action!="start_spatial" or not Definitions.number(command.pitch_raw,0.0,1.0)):return fail("Invalid weapon sound pitch")
		if action in ["replace_music","start","start_spatial","set_player_engine"]:
			op.clip=_resources.prepare(op.source_id)
			if op.clip.is_empty():return fail(_resources.error)
			if op.clip.get("kind")=="parameter_loop" and not ParameterLoop.valid_context(op.get("position",Vector3.ZERO),view):return fail("Invalid engine sound spatial context")
		operations.append(op)
	for record in _players.values()+_retiring:
		if record.node is ParameterLoop and not ParameterLoop.valid_context(record.position,view):return fail("Invalid retained engine sound spatial context")
	var engine_frame:=prepare_engine(world,int(elapsed),view,operations)
	if engine_frame.is_empty():return {}
	return {"identity":_identity,"revision":revision,"repeat":false,"listener":view,"elapsed_ms":int(elapsed),"operations":operations,"layer_frames":layer_frames,"voice_displayed":radio_frame.displayed,"player_engine":engine_frame}

func prepare_engine(world: Dictionary,elapsed_ms: int,view: Transform3D,operations: Array) -> Dictionary:
	var state: Variant=world.get(PLAYER_ENGINE,{})
	if not state is Dictionary:return fail("Invalid retained player engine frame")
	if state.is_empty():
		if _engine_generation>=0:return fail("Retained player engine disappeared from its world")
		return {"present":false}
	for key in _content_identity:
		if state.get(key)!=_content_identity[key] or world.get(key)!=_content_identity[key]:return fail("Retained player engine belongs to another world")
	if world.get("elapsed_ms")!=elapsed_ms or state.get("elapsed_ms")!=elapsed_ms:return fail("Retained player engine clock differs from its world")
	if not Definitions.integer(state.get("initial_source_id"),0,19999) or state.initial_source_id not in _engine_ids:return fail("Invalid initial player engine selection")
	if not Definitions.integer(state.get("generation"),maxi(0,_engine_generation),mini(1,_engine_generation+1)) or not state.get("active") is bool:return fail("Invalid retained player engine lifetime")
	if _initial_engine_id>=0 and int(state.initial_source_id)!=_initial_engine_id:return fail("Initial player engine selection changed during flight")
	if not state.get("position") is Vector3 or not state.position.is_finite() or not state.get("source_commands") is Vector2 or not state.source_commands.is_finite():return fail("Invalid retained player engine position or controls")
	if absf(state.source_commands.x)>1 or absf(state.source_commands.y)>1:return fail("Retained player engine commands exceed normalized input")
	var expected: int=int(state.initial_source_id) if state.generation==0 else _arrival_engine_id
	if not Definitions.integer(state.get("source_id"),expected,expected) or expected<0:return fail("Player engine replacement differs from its source controller")
	if state.generation==0:
		if not EngineParameters.valid_parameters(state.get("parameters")):return fail("Invalid ordinary player engine parameters")
	elif not state.get("parameters") is Array or not state.parameters.is_empty():return fail("The arrival engine uses its own timed parameter")
	var replacements:=0
	for op in operations:
		if op.action=="set_player_engine":
			replacements+=1
			if state.generation!=1 or _engine_generation!=0 or op.source_id!=expected:return fail("Retained engine replacement lacks its controller transition")
		elif op.action in ["start","start_spatial","replace_music"] and op.source_id==expected:return fail("The player engine requires its retained instance")
	if replacements!=int(state.generation==1 and _engine_generation==0):return fail("Retained engine lifetime differs from its controller transition")
	var clip: Dictionary=_resources.prepare(expected)
	if clip.is_empty():return fail(_resources.error)
	if state.generation==0 and clip.get("kind")!="parameter_loop":return fail("The initial player engine has unsupported playback behavior")
	if state.generation==1 and clip.get("kind")!="layered":return fail("The arrival engine has unsupported playback behavior")
	if state.generation==0 and not ParameterLoop.valid_context(state.position,view):return fail("Invalid retained player engine listener")
	var result: Dictionary=state.duplicate(true);result.present=true;result.clip=clip
	return result

func prepare_radio(state: Dictionary) -> Dictionary:
	if not _local_radio_rules.is_empty():return prepare_local_radio(state)
	var displayed:=_voice_displayed.duplicate()
	var operations: Array[Dictionary]=[]
	if _radio_voice.is_empty() or (not state.has("radio") and not state.has("radio_changes")):return {"operations":operations,"displayed":displayed}
	var radio: Variant=state.get("radio")
	var changes: Variant=state.get("radio_changes")
	if not radio is Dictionary or not changes is Array or changes.size()>3:return fail("Invalid radio voice frame")
	for key in _radio_identity:
		if radio.get(key)!=_radio_identity[key]:return fail("Radio voice belongs to another content or text language")
	for key in ["started","finished"]:
		var rows: Variant=radio.get(key)
		if not rows is Array or rows.size()!=displayed.size():return fail("Invalid radio voice event extent")
		for value in rows:
			if not value is bool:return fail("Invalid radio voice event flag")
	if not Definitions.integer(radio.get("active_event"),-1,displayed.size()-1) or not radio.get("visible") is bool:return fail("Invalid active radio voice display")
	if radio.active_event>=0:
		if not radio.started[radio.active_event] or radio.get("text_id")!=_radio_voice.text_ids[radio.active_event]:return fail("Active radio voice differs from its text")
	elif radio.visible:return fail("Visible radio voice has no active event")
	var displayed_now:=-1
	for change in changes:
		if not change is Dictionary or change.get("kind") not in ["started","display","finished"] or not Definitions.integer(change.get("event"),0,displayed.size()-1):return fail("Invalid radio voice transition")
		if change.size()!=(3 if change.kind=="display" else 2):return fail("Invalid radio voice transition fields")
		if change.kind!="display":continue
		var event:=int(change.event)
		if displayed_now>=0 or displayed[event] or not radio.started[event] or change.get("text_id")!=_radio_voice.text_ids[event]:return fail("Radio voice repeated or differs from its text display")
		displayed_now=event;displayed[event]=true
		if _radio_voice.event_ids[event]>=0:
			operations.append({"action":"start","source_id":int(_radio_voice.event_ids[event]),"radio_event":event,"text_id":int(change.text_id)})
	if displayed_now>=0:
		var visible: bool=radio.get("visible")==true and radio.get("active_event")==displayed_now
		var finished: bool=radio.finished[displayed_now] and changes.any(func(change):return change.kind=="finished" and change.event==displayed_now)
		if not visible and not finished:return fail("Radio voice has no accepted display transition")
	return {"operations":operations,"displayed":displayed}

func prepare_local_radio(state: Dictionary) -> Dictionary:
	var radio: Variant=state.get("radio");var changes: Variant=state.get("radio_changes")
	if not radio is Dictionary or not changes is Array or changes.size()>3:return fail("Invalid local radio voice frame")
	for key in _radio_identity:
		if radio.get(key)!=_radio_identity[key]:return fail("Local voice belongs to another content or language")
	if not Definitions.integer(radio.get("last_serial"),0,2) or not Definitions.integer(radio.get("active_event"),-1,0) or not radio.get("visible") is bool:return fail("Invalid local voice lifetime")
	var message: Variant=radio.get("message")
	if not message is Dictionary:return fail("Local voice lost its message")
	if radio.active_event==0:
		if not LocalRadio.valid_payload(_local_radio_rules,message) or message.serial>radio.last_serial or radio.get("text_id")!=message.text_id or radio.get("speaker_id")!=message.speaker_id or radio.get("started")!=[true] or radio.get("finished")!=[false]:return fail("Local voice differs from its active text")
	elif radio.visible or not message.is_empty():return fail("Inactive local voice retained a visible message")
	var displayed:=_voice_displayed.duplicate();var operations: Array[Dictionary]=[]
	var displayed_now:=0;var transition_message:={};var previous_phase:=-1
	for change in changes:
		if not change is Dictionary or change.size()!=7 or change.get("event")!=0 or change.get("kind") not in ["started","display","finished"]:return fail("Invalid local voice transition")
		var phase: int=["started","display","finished"].find(change.kind)
		if phase<=previous_phase:return fail("Local voice transitions are out of order")
		previous_phase=phase
		var selected:={"serial":change.get("serial"),"kind":change.get("message_kind"),"speaker_id":change.get("speaker_id"),"text_id":change.get("text_id"),"voice_event_id":change.get("voice_event_id")}
		if not LocalRadio.valid_payload(_local_radio_rules,selected) or selected.serial>radio.last_serial:return fail("Local voice lost its source text and recording pair")
		if not transition_message.is_empty() and selected!=transition_message:return fail("Local voice changed message within one update")
		transition_message=selected
		if change.kind!="display":continue
		var index: int=selected.serial-1
		if displayed[index]:return fail("Local voice repeated an accepted display")
		displayed[index]=true;displayed_now=selected.serial
		operations.append({"action":"start","source_id":selected.voice_event_id,"radio_event":selected.serial,"text_id":selected.text_id})
	if not transition_message.is_empty():
		var finished: bool=changes[-1].kind=="finished"
		if finished:
			if radio.active_event!=-1 or not displayed[transition_message.serial-1]:return fail("Local voice finished without an accepted display")
		elif message!=transition_message:return fail("Local voice transition differs from the active transmission")
	if displayed_now>0 and radio.active_event==0 and not radio.visible:return fail("Local voice has no accepted text display")
	return {"operations":operations,"displayed":displayed}

func prepare_combat(world: Dictionary, elapsed_ms: int) -> Dictionary:
	for key in _content_identity:
		if world.get(key)!=_content_identity[key]:return fail("NPC audio belongs to another content identity")
	if world.get("elapsed_ms")!=elapsed_ms:return fail("NPC audio clock differs from its world")
	var events: Variant=world.get("actor_events")
	if not events is Array or events.size()>_npc_count:return fail("Invalid NPC audio event extent")
	var operations: Array[Dictionary]=[]
	if not _weapon_audio.is_empty():
		var primary:=prepare_primaries(world)
		if primary.is_empty():return {}
		operations.append_array(primary.operations)
	var previous:=-1
	for event in events:
		if not event is Dictionary or not Definitions.integer(event.get("actor_id"),previous+1,_npc_count-1):return fail("Invalid NPC audio actor order")
		previous=int(event.actor_id)
		if not _weapon_audio.is_empty():
			var firing:=prepare_npc_weapon(event,previous)
			if firing.is_empty():return {}
			operations.append_array(firing.operations)
		var death: Variant=event.get("destruction",{})
		if not death is Dictionary:return fail("Invalid NPC audio death frame")
		if death.is_empty() or _death_audio.is_empty():continue
		if previous in _debris_actors:
			var debris:=prepare_debris_audio(death,previous)
			if debris.is_empty():return {}
			operations.append_array(debris.operations);continue
		if previous in _freighter_actors:
			var freight:=prepare_freighter_audio(death,previous)
			if freight.is_empty():return {}
			operations.append_array(freight.operations);continue
		var cues: Variant=death.get("audio_events")
		var ids: Variant=death.get("sound_events")
		if not cues is Array or not ids is Array or cues.size()!=ids.size() or cues.size()>2 or not death.get("started") is bool or not death.get("breakup") is bool:return fail("Invalid NPC destruction audio events")
		if cues.size()!=int(death.started)+int(death.breakup):return fail("NPC sound events differ from their death transitions")
		for i in cues.size():
			var cue: Variant=cues[i]
			if not cue is Dictionary or not cue.get("position") is Vector3 or not cue.position.is_finite() or not Definitions.integer(cue.get("source_id"),0,19999) or cue.source_id!=ids[i]:return fail("Invalid NPC destruction sound position or identifier")
			if death.started and i==0:
				if cue.source_id!=_death_audio.initial_source_id:return fail("Wrong NPC death initialization sound")
			elif cue.source_id not in _death_audio.breakup_source_ids:return fail("Wrong NPC breakup sound")
			operations.append({"action":"start_spatial","source_id":int(cue.source_id),"position":cue.position,"actor_id":previous})
	return {"operations":operations}

func prepare_debris_audio(death: Dictionary,actor_id: int) -> Dictionary:
	var cues: Variant=death.get("audio_events")
	if not death.get("started",false) or death.get("sound_events")!=[_debris_sound] or not cues is Array or cues.size()!=1:return fail("Debris sound lost its destruction transition")
	var cue: Variant=cues[0]
	if not cue is Dictionary or cue.get("source_id")!=_debris_sound or not cue.get("position") is Vector3 or not cue.position.is_finite():return fail("Debris sound lost its source or position")
	return {"operations":[{"action":"start_spatial","source_id":_debris_sound,"position":cue.position,"actor_id":actor_id}]}

func prepare_freighter_audio(death: Dictionary, actor_id: int) -> Dictionary:
	if _freighter_audio.is_empty() or not death.get("started") is bool or not death.get("breakup") is bool:return fail("Freighter sound requires its native death transitions")
	var cues: Variant=death.get("audio_events")
	if not cues is Array or cues.size()!=2*int(death.started)+int(death.breakup):return fail("Freighter lost its initial or final explosion sounds")
	var operations: Array[Dictionary]=[]
	for index in cues.size():
		var cue: Variant=cues[index]
		if not cue is Dictionary or not cue.get("source_id") is int or not cue.get("position") is Vector3 or not cue.position.is_finite():return fail("Invalid freighter sound position or source")
		if death.started and index==0:
			if cue.source_id!=int(_freighter_audio.initial_sound_id):return fail("Wrong freighter initial sound")
		elif cue.source_id<int(_freighter_audio.effect_sound_base) or cue.source_id>=int(_freighter_audio.effect_sound_base)+int(_freighter_audio.effect_sound_bound):return fail("Wrong freighter explosion sound")
		operations.append({"action":"start_spatial","source_id":int(cue.source_id),"position":cue.position,"actor_id":actor_id})
	return {"operations":operations}

func prepare_primaries(world: Dictionary) -> Dictionary:
	var fire: Variant=world.get("primary_fire",{})
	if not fire is Dictionary:return fail("Invalid primary audio firing frame")
	var operations: Array[Dictionary]=[]
	if fire.is_empty():return {"operations":operations}
	var events: Variant=fire.get("weapons")
	var owner: Variant=world.get("primaries")
	if not owner is Dictionary:return fail("Invalid primary sound owner")
	var guns: Variant=owner.get("guns")
	if not events is Array or not guns is Array or events.size()!=guns.size() or guns.size()>255:return fail("Invalid primary sound owner extent")
	for i in guns.size():
		var event: Variant=events[i]
		var gun: Variant=guns[i]
		if not event is Dictionary or not gun is Dictionary:return fail("Invalid primary sound owner")
		if not gun.get("equipment") is Dictionary or not event.get("result") is Dictionary:return fail("Invalid primary sound equipment or result")
		var item: Variant=event.get("item_id")
		if not Definitions.integer(item,0,_weapon_audio.player_event_ids.size()-1) or item!=gun.get("equipment",{}).get("item_id") or event.get("slot")!=gun.get("equipment",{}).get("slot") or event.get("mount_id")!=gun.get("mount_id"):return fail("Primary sound belongs to another weapon")
		var entry: Variant=gun.get("audio")
		if not entry is Dictionary or not entry.get("enabled") is bool or entry.get("source_id")!=_weapon_audio.player_event_ids[int(item)] or not Definitions.number(entry.get("pitch_raw"),0.0,1.0):return fail("Invalid primary sound selection")
		var fired: Variant=event.get("result",{}).get("fired")
		var cues:=prepare_weapon_cues(event.get("audio_events"),fired,entry)
		if cues.is_empty():return {}
		for op in cues.operations:
			op.mount_id=event.mount_id;op.item_id=int(item);operations.append(op)
	return {"operations":operations}

func prepare_npc_weapon(event: Dictionary, actor_id: int) -> Dictionary:
	var firing: Variant=event.get("firing",{})
	if not firing is Dictionary:return fail("Invalid NPC firing audio frame")
	if firing.is_empty():return {"operations":[]}
	var death: Variant=event.get("destruction",{})
	if not death is Dictionary or not death.is_empty():return fail("NPC fired during a destruction transition")
	var rows: Variant=firing.get("actors")
	if not rows is Array or rows.size()!=1 or not rows[0] is Dictionary or rows[0].get("actor_id")!=actor_id:return fail("NPC sound belongs to another firing actor")
	if not rows[0].get("outcome") is Dictionary:return fail("Invalid NPC firing result")
	if _npc_weapon_sounds[actor_id]<0:return fail("An unarmed debris actor emitted weapon audio")
	var entry:={"enabled":true,"source_id":_npc_weapon_sounds[actor_id],"pitch_raw":0.0}
	var frame:=prepare_weapon_cues(rows[0].get("audio_events"),rows[0].get("outcome",{}).get("fired"),entry)
	if frame.is_empty():return {}
	for op in frame.operations:op.actor_id=actor_id
	return frame

func prepare_weapon_cues(cues: Variant, fired: Variant, entry: Dictionary) -> Dictionary:
	if not fired is bool or not cues is Array:return fail("Weapon sound lacks its launch result")
	var expected: int=int(fired and entry.enabled and int(entry.source_id)>=0)
	if cues.size()!=expected:return fail("Weapon sound differs from its successful launch and selection")
	var operations: Array[Dictionary]=[]
	for cue in cues:
		if not cue is Dictionary or cue.size()!=3 or cue.get("source_id")!=entry.source_id or not Definitions.number(cue.get("pitch_raw"),0.0,1.0) or cue.pitch_raw!=entry.pitch_raw or not cue.get("position") is Vector3 or not cue.position.is_finite():return fail("Invalid weapon sound identifier, position or pitch")
		operations.append({"action":"start_spatial","source_id":int(cue.source_id),"position":cue.position,"pitch_raw":float(cue.pitch_raw)})
	return {"operations":operations}

func commit_frame(frame: Dictionary) -> void:
	if frame.get("identity")!=_identity or frame.get("revision")!=_revision+1 or frame.get("repeat",true):return
	var delta_ms: int=frame.elapsed_ms-_elapsed_ms
	_elapsed_ms=frame.elapsed_ms;_revision=frame.revision;_listener=frame.listener
	if frame.has("flight_serial"):_flight_serial=int(frame.flight_serial)
	if frame.has("travel_serial"):_travel_serial=int(frame.travel_serial)
	if frame.has("contract_result_serial"):_notified_result_serial=int(frame.contract_result_serial)
	_voice_displayed=frame.voice_displayed.duplicate()
	for record in _players.values():record.age_ms+=delta_ms
	for record in _retiring.duplicate():
		record.remaining_ms=maxi(0,record.remaining_ms-delta_ms)
		if record.remaining_ms==0:
			record.node.stop();record.node.queue_free();_retiring.erase(record)
	for item in frame.layer_frames:
		if is_instance_valid(item.node) and not item.node.is_queued_for_deletion():item.node.commit_step(item.frame)
	if frame.player_engine.present and (frame.player_engine.generation==0 or frame.player_engine.generation==_engine_generation):commit_engine(frame.player_engine)
	for op in frame.operations:
		match op.action:
			"replace_music":
				stop_event(_music);_music=op.source_id;start_event(op)
			"start","start_spatial":start_event(op)
			"position":
				if _players.has(op.source_id):_players[op.source_id].position=op.position
			"stop":stop_event(op.source_id)
			"stop_music":stop_event(_music)
			"stop_player_engine":
				stop_event(_engine)
				if not frame.player_engine.present:_engine=-1
			"set_player_engine":
				if frame.player_engine.present:commit_engine(frame.player_engine)
				else:stop_event(_engine);_engine=op.source_id;start_event(op)
		var entry: Dictionary=op.duplicate();entry.erase("clip");entry["revision"]=_revision;_history.append(entry)
		if _history.size()>256:_history.pop_front()
	refresh_levels()

func commit_engine(state: Dictionary) -> void:
	if int(state.generation)!=_engine_generation:stop_event(PLAYER_ENGINE)
	_engine_generation=int(state.generation);_initial_engine_id=int(state.initial_source_id);_engine=int(state.source_id)
	if not state.active:stop_event(PLAYER_ENGINE);return
	start_event({"source_id":_engine,"clip":state.clip,"position":state.position},PLAYER_ENGINE)
	var record: Dictionary=_players[PLAYER_ENGINE]
	if record.node is ParameterLoop:record.node.set_parameters(state.parameters)

func start_event(op: Dictionary,key: Variant=null) -> void:
	if key==null:key=op.source_id
	if op.clip.has("unsupported"):
		_unsupported[op.source_id]=op.clip.unsupported
		return
	# The original wrapper retains one handle per event. Starting an audible
	# cached instance updates its position without resetting its sample or RNG.
	if _players.has(key):
		var old: Dictionary=_players[key]
		if old.node.playing or old.pending_resume:
			if op.has("position"):old.position=op.position
			apply_pitch(old,float(op.get("pitch_raw",0.0)))
			return
		old.node.stop();old.node.queue_free();_players.erase(key)
	for old in _retiring.duplicate():
		if old.clip.id==op.source_id:
			old.node.stop();old.node.queue_free();_retiring.erase(old)
	if op.clip.get("voice",false):reserve_voice()
	var node: Node
	var clip: Dictionary=op.clip
	var category: String="Music" if op.get("action")=="replace_music" else "Voice" if clip.get("voice",false) else "FX"
	if op.clip.get("kind")=="layered":
		node=Layered.new();node.category=category;node.configure(op.clip,_seed_value+_start_serial);_start_serial+=1
	elif op.clip.get("kind")=="parameter_loop":
		node=ParameterLoop.new();node.configure(op.clip)
	else:
		if clip.get("kind")=="playlist":
			var definition: Dictionary=clip.definition
			var last: int=_last_samples.get(op.source_id,-1) if definition.playlist_flags!=8 else -1
			var choice:=Sequence.sample(definition,_random,last)
			_last_samples[op.source_id]=choice.playlist_index
			clip=clip.duplicate();clip.merge(choice.sample);clip.gain*=choice.gain
			clip.pitch=choice.pitch;clip.playlist_index=choice.playlist_index
			node=Streams.player(clip.stream,clip.spatial,category);node.pitch_scale=choice.pitch
		else:node=Streams.player(clip.stream,clip.spatial,category)
	var record:={"node":node,"clip":clip,"age_ms":0,"position":op.get("position",Vector3.ZERO),"remaining_ms":0,"stop_gain":1.0,"pending_resume":false,"resume_position":0.0}
	if clip.get("voice",false):record.voice_serial=_voice_serial;_voice_serial+=1
	apply_pitch(record,float(op.get("pitch_raw",0.0)))
	add_child(node)
	_players[key]=record
	apply_level(record,1.0)
	if _paused:record.pending_resume=true
	else:node.play()

func reserve_voice() -> void:
	var voices: Array=[]
	for record in _players.values()+_retiring:
		if record.clip.get("voice",false) and (record.node.playing or record.pending_resume):voices.append(record)
	if voices.size()<2:return
	voices.sort_custom(func(a,b):return a.voice_serial<b.voice_serial)
	# Category flags0 select the oldest started instance. The source uses an
	# immediate stop for category stealing, independent of its normal stop fade.
	var oldest: Dictionary=voices[0]
	oldest.node.stop();oldest.node.queue_free()
	_players.erase(int(oldest.clip.id));_retiring.erase(oldest)

func apply_pitch(record: Dictionary, raw: float) -> void:
	# FMOD Designer raw pitch has four octaves per unit. Playlist pitch is an
	# independent sample variation; repeated cached starts retain that choice.
	if record.node is Layered:return
	record.node.pitch_scale=float(record.clip.get("pitch",1.0))*pow(2.0,4.0*raw)
	record.pitch_raw=raw

func stop_event(id: Variant) -> void:
	if not _players.has(id):return
	var record: Dictionary=_players[id];_players.erase(id)
	var fade: int=record.clip.fade_out_ms
	if fade==0:record.node.stop();record.node.queue_free();return
	record.remaining_ms=fade
	record.stop_gain=1.0 if record.clip.fade_in_ms==0 else minf(1.0,float(record.age_ms)/record.clip.fade_in_ms)
	_retiring.append(record)

func refresh_levels() -> void:
	for record in _players.values():
		var fade: float=1.0 if record.clip.fade_in_ms==0 else minf(1.0,float(record.age_ms)/record.clip.fade_in_ms)
		apply_level(record,fade)
	for record in _retiring:apply_level(record,record.stop_gain*float(record.remaining_ms)/record.clip.fade_out_ms)

func apply_level(record: Dictionary, fade: float) -> void:
	var gain: float=record.clip.gain*fade
	if record.clip.spatial:
		if record.node is ParameterLoop:record.node.set_spatial(record.position,_listener)
		else:record.node.position=record.position
		var distance: float=_listener.origin.distance_to(record.position)
		gain*=clampf((record.clip.max_distance-distance)/(record.clip.max_distance-record.clip.min_distance),0.0,1.0)
	record.node.volume_db=linear_to_db(gain) if gain>0 else -80.0

func set_paused(value: bool) -> void:
	_paused=value
	for record in _players.values():pause_record(record,value)
	for record in _retiring:pause_record(record,value)

func pause_record(record: Dictionary, value: bool) -> void:
	Streams.pause(record,value)


func snapshot() -> Dictionary:
	var active:={}
	for id in _players:
		var row: Dictionary=_players[id]
		active[id]={"name":row.clip.name,"position":row.position,"gain_db":row.node.volume_db,"paused":row.node.stream_paused or row.pending_resume,"playing":row.node.playing,"looping":row.clip.looping,"source_bank":row.clip.get("source_bank",""),"source_index":row.clip.get("source_index",-1)}
		if row.clip.get("kind")=="playlist":active[id].pitch=row.clip.pitch;active[id].playlist_index=row.clip.playlist_index
		if row.has("pitch_raw"):active[id].pitch_raw=row.pitch_raw;active[id].playback_pitch=row.node.pitch_scale
		if row.node is Layered:active[id].layers=row.node.snapshot()
		if row.node is ParameterLoop:active[id].parameter_loop=row.node.snapshot()
		if row.clip.get("voice",false):active[id].voice=true;active[id].voice_serial=row.voice_serial
	return {"revision":_revision,"elapsed_ms":_elapsed_ms,"music_id":_music,"engine_id":_engine,"engine_generation":_engine_generation,"active":active,"retiring":_retiring.size(),"paused":_paused,"history":_history.duplicate(true),"unsupported":_unsupported.duplicate(),"random_state":_random.state,"voice_displayed":_voice_displayed.duplicate()}

func clear() -> void:
	for child in get_children():
		child.stop();child.free()
	restore_listener()
	_resources=null;_identity=null;_revision=-1;_elapsed_ms=0;_players.clear();_retiring.clear();_history.clear();_unsupported.clear();_music=-1;_engine=-1;_paused=false;_start_serial=0;error=""
	_last_samples.clear();_random.seed=0
	_death_audio={};_freighter_audio={};_freighter_actors=[];_debris_actors=[];_debris_sound=-1;_notification_sound=-1;_notified_result_serial=0;_content_identity={};_weapon_audio={};_npc_weapon_sound=-1;_npc_weapon_sounds=[];_npc_scan_sound=-1
	_radio_voice={};_local_radio_rules={};_radio_identity={};_voice_displayed=[];_voice_serial=0
	_engine_ids=[];_arrival_engine_id=-1;_engine_generation=-1;_initial_engine_id=-1
	_npc_count=3;_player_death_rules={};_flight_identity=null;_flight_serial=-1
	_travel_sounds=[];_travel_attached=false;_travel_serial=0

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	error=message
	return {}

func restore_listener() -> void:
	if is_instance_valid(_viewport):_viewport.set_as_audio_listener_3d(_previous_listener)
	_viewport=null

func take_listener_from(previous: Node3D) -> bool:
	# A prepared replacement shares its viewport with the old scene. Transfer
	# restoration responsibility so disposing the old scene cannot disable it.
	if previous==null or previous.get_script()!=get_script() or _identity==null or previous._identity==null or not is_instance_valid(_viewport) or previous._viewport!=_viewport:return reject("Audio handoff requires two prepared owners in the same viewport")
	_previous_listener=previous._previous_listener
	previous._viewport=null
	_viewport.set_as_audio_listener_3d(true)
	return true

func _exit_tree() -> void:
	for child in get_children():child.stop()
	restore_listener()

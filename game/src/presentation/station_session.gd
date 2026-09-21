extends Node3D
## Station scene built from an accepted rescue or mining return. Loading and panel
## preparation precede activation; only explicit acknowledgement advances story.
const Transit=preload("res://src/content/convoy_transit_definitions.gd")
const World=preload("res://src/simulation/station_entry.gd")
const Motion=preload("res://src/simulation/station_camera.gd")
const Definitions=preload("res://src/content/station_presentation_definitions.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Clock=preload("res://src/simulation/frame_clock.gd")
const Geometry=preload("res://src/presentation/hangar_geometry.gd")
const Speech=preload("res://src/presentation/station_audio.gd")
const Conversations=preload("res://src/content/ordinary_flight_definitions.gd")
const Locations=preload("res://src/simulation/lounge_cache.gd")
const LoungeScene=preload("res://src/presentation/lounge_scene.gd")
const BOUNDARIES=["launch_required","station_reload_required","station_followup_required"]
var _polled_world: RefCounted
var error:=""
var status:="idle"
var camera: Camera3D
var geometry: Node3D
var audio: Node
var station_name:=""
var _world: RefCounted
var _motion: RefCounted
var _clock: RefCounted
var _pauses:={}
var _active:=false
var _generation:=0
var _dialogue_started:=false
var _dialogue_delay_ms:=0
var _locations: RefCounted
var _bindings: RefCounted
var _catalogues: RefCounted
var _library: RefCounted
var _lounge_open:=false
var lounge_scene: Node3D
var _visuals: RefCounted
var _environment: WorldEnvironment
var _hangar_environment: Environment
var _hangar_lights: Array[Light3D]=[]

static func supported(bindings: RefCounted) -> bool:
	return bindings!=null and Definitions.parameters(bindings.station_presentation)

func configure(library: RefCounted, bindings: RefCounted, visuals: RefCounted, packet: Dictionary, now_microseconds: int, camera_seed: int=0) -> bool:
	clear()
	if not supported(bindings):return fail("This pack has no supported first station scene")
	var cat:=Catalogues.new()
	if not cat.open(library):return fail(cat.error)
	_world=World.new()
	if not _world.configure(bindings,cat,library,packet):return fail(_world.error)
	return _build_scene(library,bindings,visuals,cat,now_microseconds,camera_seed)

func configure_return(library: RefCounted, bindings: RefCounted, visuals: RefCounted, flight: RefCounted, now_microseconds: int, camera_seed: int=0, location_settings: Dictionary={}, unix_seconds: Variant=null) -> bool:
	clear()
	if not supported(bindings):return fail("This pack has no supported station scene")
	var cat:=Catalogues.new()
	if not cat.open(library):return fail(cat.error)
	_world=World.new()
	if not _world.configure_return(bindings,cat,library,flight,location_settings,unix_seconds):return fail(_world.error)
	if not location_settings.is_empty():_locations=_world.contract_owner().location_owner()
	if Transit.available(bindings.mido_travel) and _world.contract_story_ready():
		if not _world.begin_contract_conversation(bindings,cat,library):return fail(_world.error)
	return _build_scene(library,bindings,visuals,cat,now_microseconds,camera_seed)

func configure_reload(library: RefCounted, bindings: RefCounted, visuals: RefCounted, previous: RefCounted, now_microseconds: int, camera_seed: int=0) -> bool:
	clear()
	if not supported(bindings):return fail("This pack has no supported station scene")
	var cat:=Catalogues.new()
	if not cat.open(library):return fail(cat.error)
	_world=World.new()
	if not _world.configure_reload(bindings,cat,library,previous):return fail(_world.error)
	if not Conversations.station_conversation(bindings,int(_world.snapshot().campaign_cursor)).is_empty():
		if not _world.begin_local_conversation(bindings,cat,library):return fail(_world.error)
	return _build_scene(library,bindings,visuals,cat,now_microseconds,camera_seed)

func configure_saved(library: RefCounted,bindings: RefCounted,visuals: RefCounted,data: Dictionary,now_microseconds: int,camera_seed: int=0) -> bool:
	clear()
	if not supported(bindings):return fail("This pack has no supported station scene")
	var cat:=Catalogues.new()
	if not cat.open(library):return fail(cat.error)
	var archive:=preload("res://src/simulation/station_archive.gd").new()
	_world=archive.restore(bindings,cat,library,data)
	if _world==null:return fail(archive.error)
	_locations=archive.restored_locations
	return _build_scene(library,bindings,visuals,cat,now_microseconds,camera_seed)

func _build_scene(library: RefCounted, bindings: RefCounted, visuals: RefCounted, cat: RefCounted, now_microseconds: int, camera_seed: int) -> bool:
	_bindings=bindings;_catalogues=cat;_library=library;_visuals=visuals
	var seed: Dictionary=_world.snapshot().loadout
	var view:=Definitions.select(bindings,int(seed.station_id),int(_world.snapshot().campaign_cursor))
	if view.is_empty():return fail("This station has no supported presentation")
	var selected: Dictionary=bindings.resolve_hangar(int(seed.station_id),cat)
	if selected.is_empty():return fail(bindings.error)
	if selected.row!=view.hangar_row:return fail("Station camera belongs to another hangar")
	selected.ship=bindings.resolve_hangar_ship(int(seed.ship_id))
	if selected.ship.is_empty():return fail(bindings.error)
	geometry=Geometry.new();add_child(geometry)
	if not geometry.build(selected,library,visuals,bindings):return fail(geometry.error)
	_motion=Motion.new()
	if not _motion.configure(view,camera_seed):return fail(_motion.error)
	_dialogue_delay_ms=int(view.dialogue.start_delay_ms)
	_clock=Clock.new()
	if not _clock.configure(bindings,bindings.base_content_id) or not _clock.rebase(now_microseconds):return fail(_clock.error)
	camera=Camera3D.new();add_child(camera)
	var projection: Array=view.camera.projection
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.set_perspective(rad_to_deg(projection[0]),projection[1],projection[2])
	camera.transform=_motion.snapshot().pose
	build_lighting(view.light)
	audio=Speech.new();add_child(audio)
	var state: Dictionary=_world.snapshot()
	var voice_ready: bool=true
	if not state.dialogue.visible:
		# A restored acknowledged station never replays the finished conversation.
		_dialogue_started=true
	elif state.get("equipment_conversation",false):
		voice_ready=audio.configure_station_equipment(library,bindings)
		_dialogue_started=not state.dialogue.visible
	else:
		voice_ready=audio.configure_station_return(library,bindings,int(state.campaign_cursor)) if state.get("return_visit",false) or state.get("local_conversation",false) else audio.configure(library,bindings)
	if not voice_ready:return fail(audio.error)
	station_name=cat.tables.stations[int(selected.station_id)].name
	status="running"
	return true

func build_lighting(data: Dictionary) -> void:
	# Source direction and ambient/diffuse colors adapted to Godot PBR. Original
	# station shader selection, inherited global/rim state remain unverified.
	var direction: Vector3=-(Basis(Vector3.UP,float(data.initial_camera_yaw)).z+Motion.vector(data.direction_bias)).normalized()
	var light:=DirectionalLight3D.new();add_child(light)
	_hangar_lights.append(light)
	light.basis=Basis.looking_at(-direction,Vector3.UP)
	light.light_color=Color(data.diffuse[0],data.diffuse[1],data.diffuse[2]).linear_to_srgb()
	light.light_energy=1;light.light_specular=float(data.specular[0]);light.shadow_enabled=false
	var ambient: Vector3=Motion.vector(data.ambient)*float(data.material_ambient)
	var energy: float=maxf(ambient.x,maxf(ambient.y,ambient.z))
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(ambient.x/energy,ambient.y/energy,ambient.z/energy).linear_to_srgb()
	environment.environment.ambient_light_energy=energy;add_child(environment)
	_environment=environment;_hangar_environment=environment.environment

func activate() -> bool:
	if status!="running" or _active:return reject("Station scene cannot be activated")
	_active=true;camera.make_current()
	return true

func step(now_microseconds: int, commands:=Vector2.ZERO, fire_primary:=false) -> bool:
	if status!="running" or not _active or commands!=Vector2.ZERO or fire_primary:return reject("Station scene cannot accept flight input")
	var clock: RefCounted=_clock.fork_for_frame()
	var world_state: Dictionary=_world.snapshot()
	var result_open: bool=not world_state.get("contracts",{}).get("pending_result",{}).is_empty()
	var milliseconds:=roundi(clock.sample(now_microseconds,is_paused() or result_open)*1000)
	if not clock.error.is_empty():return reject(clock.error)
	if is_paused() or result_open:_clock=clock;return true
	if _polled_world!=_world and _world.has_contracts() and (world_state.phase in ["contracts_required","convoy_departure_required"] or (world_state.phase=="free_play_required" and preload("res://src/content/ordinary_contracts_definitions.gd").available(_bindings))):
		var candidate: RefCounted=_world.fork()
		if not candidate.poll_contract_result(_bindings):return reject(candidate.error)
		_world=candidate
	# Station delivery results depend on the accepted inventory/career, which
	# user actions replace atomically. Camera animation does not change them.
	_polled_world=_world
	if _lounge_open:
		if not lounge_scene.advance(milliseconds):return reject(lounge_scene.error)
		_clock=clock;_generation+=1;return true
	var motion: RefCounted=_motion.fork()
	if not motion.advance(milliseconds):return reject(motion.error)
	var state: Dictionary=motion.snapshot()
	camera.transform=state.pose
	_motion=motion;_clock=clock;_generation+=1
	if not _dialogue_started and state.elapsed_ms>=_dialogue_delay_ms:
		_dialogue_started=true;audio.present(0)
	return true

func navigate(action: String, panel: Control) -> bool:
	error=""
	if status!="running" or not _active or not _dialogue_started or is_paused() or action not in ["next","previous"] or panel==null:return reject("Station conversation is inactive")
	var candidate: RefCounted=_world.fork()
	if not (candidate.acknowledge() if action=="next" else candidate.previous()):return reject(candidate.error)
	if candidate.snapshot().get("phase")=="contracts_required" and _locations!=null:
		if not candidate.open_contracts(_bindings,_catalogues) or not candidate.retain_contract_locations(_locations):return reject(candidate.error)
	var staged: Dictionary=candidate.snapshot()
	var voice_line: int=int(staged.dialogue.index) if staged.dialogue.visible else -1
	if not audio.valid_line(voice_line):return reject("Station speech is unavailable")
	if not panel.present(staged):return reject(panel.error)
	_world=candidate;_generation+=1
	if staged.get("boundary")=="station_reload_required":status="station_reload_required"
	audio.present(voice_line)
	return true

func prepare_departure(bindings: RefCounted, catalogues: RefCounted) -> Dictionary:
	error=""
	if status!="running" or not _active or not _dialogue_started or is_paused():
		reject("Station departure is inactive");return {}
	var packet: Dictionary=_world.prepare_contract_departure(bindings,catalogues) if _world.snapshot().campaign_cursor in [13,14] else _world.prepare_departure(bindings,catalogues)
	if packet.is_empty():reject(_world.error)
	var state: Dictionary=_world.snapshot()
	if packet.is_empty() and state.get("phase")=="free_play_required" and not state.get("hangar_open",false) and state.cargo.used>state.cargo.capacity and _library!=null and _library.strings.size()>193:reject(_library.strings[193])
	return packet

func contract_story_ready() -> bool:
	return _world!=null and Transit.available(_bindings.mido_travel) and not _lounge_open and _world.contract_story_ready()

func begin_contract_story(panel: Control) -> bool:
	if not contract_story_ready() or not _active or is_paused() or panel==null:return reject("The earned story conversation is not ready")
	var candidate: RefCounted=_world.fork()
	if not candidate.begin_contract_conversation(_bindings,_catalogues,_library):return reject(candidate.error)
	var speech:=Speech.new();add_child(speech)
	if not speech.configure_station_return(_library,_bindings,13) or not panel.present(candidate.snapshot()):
		var problem: String=speech.error+panel.error;speech.free();return reject(problem)
	audio.adopt_conversation(speech);speech.free()
	_world=candidate;_dialogue_started=false;_generation+=1
	return true

func contract_action(action: String,id: int,panel: Control) -> bool:
	error=""
	if status!="running" or not _active or is_paused() or _world.contract_owner()==null or _world.snapshot().get("hangar_open",false):return reject("The space lounge is unavailable")
	var candidate: RefCounted=_world.fork();var opened:=_lounge_open
	match action:
		"open":
			if candidate.snapshot().dialogue.visible:return reject("Acknowledge the story before opening the lounge")
			opened=true
		"close":opened=false
		"accept","replace":
			if not opened or not candidate.accept_contract(id,action=="replace",_bindings):return reject(candidate.error)
		"result_close":
			if not audio.prepare_contract_effect(_library,_bindings) or not candidate.acknowledge_contract_result(id,_bindings):return reject(audio.error+candidate.error)
		_:return reject("Unknown lounge action")
	var staged: Dictionary=candidate.snapshot();staged.lounge_open=opened
	staged.contract_previews=_contract_previews(candidate,opened)
	var prepared: Node3D
	if opened and lounge_scene==null:
		prepared=LoungeScene.new();prepared.visible=false;add_child(prepared)
		if not prepared.build(_library,_bindings,_visuals,_catalogues,staged,int(staged.loadout.station_id)):
			var problem: String=prepared.error;prepared.free();return reject(problem)
	if panel!=null and not panel.present(staged):
		if prepared!=null:prepared.free()
		return reject(panel.error)
	if prepared!=null:lounge_scene=prepared
	_world=candidate;_lounge_open=opened;_generation+=1
	if lounge_scene!=null:
		lounge_scene.visible=opened;geometry.visible=not opened
		for light in _hangar_lights:light.visible=not opened
		_environment.environment=lounge_scene.environment if opened else _hangar_environment
		if opened:lounge_scene.camera.make_current()
		else:camera.make_current()
		if panel!=null:panel.set_scene(lounge_scene if opened else null)
	if action=="result_close":
		var sound:=int(staged.contracts.last_result.notification_sound_id)
		if sound>=0:audio.play_equipment_effect(sound)
	return true

func _contract_previews(owner: RefCounted,opened: bool) -> Dictionary:
	var result:={}
	if not opened:return result
	var career: Dictionary=owner.snapshot().get("contracts",{})
	if not career.get("pending_result",{}).is_empty():return result
	for id in career.get("offers",{}):
		if not career.offers[id].consumed:
			result[id]=owner.contract_preview(id,_bindings)
			if result[id].is_empty():result[id]={"can_accept":false,"unsupported_reason":owner.error}
	return result

func contract_owner() -> RefCounted:return null if _world==null else _world.contract_owner()
func has_contracts() -> bool:return _world!=null and _world.has_contracts()

func location_owner() -> RefCounted:
	var contracts: RefCounted=contract_owner()
	return contracts.location_owner() if contracts!=null else (null if _locations==null else _locations.fork())

func equipment_action(action: String, item_id: int, library: RefCounted, bindings: RefCounted, panel: Control, hangar: Control, unix_seconds: Variant=null, slot_index: int=-1) -> bool:
	error=""
	if status!="running" or not _active or not _dialogue_started or is_paused() or _lounge_open or panel==null or hangar==null:return reject("Equipment controls are inactive")
	var candidate: RefCounted=_world.fork()
	if action=="open":
		var cat:=Catalogues.new()
		if not cat.open(library):return reject(cat.error)
		var now: Variant=int(Time.get_unix_time_from_system()) if unix_seconds==null else unix_seconds
		if not now is int or now<0:return reject("The station price timestamp is invalid")
		if not candidate.open_equipment(bindings,cat,library,[now,now,now]):return reject(candidate.error)
		if candidate.snapshot().phase=="station_equipment_required" or candidate.snapshot().equipment.has("fitting_support"):
			if not audio.prepare_equipment_effects(bindings.station_equipment,library,bindings):return reject(audio.error)
	elif action=="close":
		if not candidate.close_equipment():return reject(candidate.error)
	elif not candidate.equipment_action(action,item_id,bindings,_catalogues,slot_index):return reject(candidate.error)
	var staged: Dictionary=candidate.snapshot()
	var speech: Node=null
	if action=="close" and staged.get("equipment_conversation",false):
		speech=Speech.new();add_child(speech)
		if not speech.configure_station_equipment(library,bindings):
			var message: String=speech.error;speech.free();return reject(message)
	if not panel.present(staged) or not hangar.present(staged):
		if speech!=null:speech.free()
		panel.present(_world.snapshot());hangar.present(_world.snapshot())
		return reject("Equipment presentation could not accept the prepared inventory")
	_world=candidate;_generation+=1
	if action in ["unmount","replace"]:audio.play_equipment_effect(int(bindings.station_equipment.unmount_audio_id))
	if action in ["mount","replace"]:audio.play_equipment_effect(int(bindings.station_equipment.mount_audio_id))
	if speech!=null:
		audio.free();audio=speech;audio.present(0)
	return true

func set_pause(reason: String, paused: bool, now_microseconds: int) -> bool:
	if _clock==null or reason not in ["user","focus","hidden"] or now_microseconds<0:return reject("Invalid station pause")
	if _pauses.has(reason)==paused:return true
	if not _clock.rebase(now_microseconds):return reject(_clock.error)
	if paused:_pauses[reason]=true
	else:_pauses.erase(reason)
	if audio!=null:audio.set_paused(is_paused())
	return true

func rebase_time(now_microseconds: int) -> bool:
	if _clock==null:return reject("Station clock is unavailable")
	return _clock.rebase(now_microseconds)
func station_owner() -> RefCounted:return null if _world==null else _world.fork()
func retain_locations(locations: RefCounted) -> bool:
	error=""
	if _world==null or _active or not locations is Locations:return reject("Attach retained locations before activating the station")
	var state: Dictionary=_world.snapshot();var retained: Dictionary=locations.snapshot()
	for key in ["base_content_id","binding_id"]:
		if retained.get(key)!=state[key]:return reject("Station locations belong to another content identity")
	if retained.get("current_station_id")!=state.loadout.station_id or locations.location(state.loadout.station_id).is_empty():return reject("The station lost its selected location")
	_locations=locations.fork()
	return true
func equipment_owner() -> RefCounted:return null if _world==null else _world.equipment_owner()
func is_paused() -> bool:return not _pauses.is_empty()
func can_control() -> bool:return false
func flight_hud_visible(_state: Dictionary={}) -> bool:return false
func snapshot() -> Dictionary:
	if _world==null:return {}
	var state: Dictionary=_world.snapshot()
	state.camera=_motion.snapshot();state.generation=_generation
	state.conversation_started=_dialogue_started
	state.dialogue.visible=state.dialogue.visible and _dialogue_started
	var locations: Dictionary=_world.contract_locations_snapshot() if _world.has_contracts() else ({} if _locations==null else _locations.snapshot())
	if not locations.is_empty():state.locations=locations
	if _world.has_contracts():
		state.lounge_open=_lounge_open
		state.contract_previews=_contract_previews(_world,_lounge_open)
		if _lounge_open and lounge_scene!=null:state.lounge_scene=lounge_scene.snapshot()
	return state
func clear() -> void:
	for child in get_children():child.free()
	error="";status="idle";station_name="";camera=null;geometry=null;audio=null
	_world=null;_polled_world=null;_motion=null;_clock=null;_pauses={};_active=false;_generation=0
	_dialogue_started=false;_dialogue_delay_ms=0
	_locations=null;_bindings=null;_catalogues=null;_library=null;_lounge_open=false
	_visuals=null;lounge_scene=null;_environment=null;_hangar_environment=null;_hangar_lights=[]
func fail(message: String) -> bool:clear();status="error";error=message;return false
func reject(message: String) -> bool:error=message;return false

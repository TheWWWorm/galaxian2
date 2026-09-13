extends Node3D
## Playable mining trips. The native frame owns gameplay; this session owns the
## clock, acknowledged speech, accepted presentation and subsequent sound commit.
signal transition_rejected(message: String)
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Clock=preload("res://src/simulation/frame_clock.gd")
const Definitions=preload("res://src/content/station_return_definitions.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Speech=preload("res://src/presentation/station_audio.gd")
const FlightAudio=preload("res://src/presentation/opening_audio.gd")
const SecondReturn=preload("res://src/content/full_hold_return_definitions.gd")
const PlayerDeath=preload("res://src/content/player_destruction_definitions.gd")
const GameOver=preload("res://src/content/game_over_definitions.gd")
const Particles=preload("res://src/content/full_hold_particle_definitions.gd")
const BOUNDARIES=["station_transition_required","game_over_transition_required"]
var error:=""
var status:="idle"
var camera: Camera3D
var scene: Node3D
var briefing_audio: Node
var objective_audio: Node
var flight_audio: Node3D
var _world: RefCounted
var _clock: RefCounted
var _pauses:={}
var _active:=false
var _throttle:=1.0
var _generation:=0
var _presentation_ms:=0

static func supported(bindings: RefCounted,campaign_cursor: int=2) -> bool:
	if bindings==null:return false
	if campaign_cursor==2:return Definitions.parameters(bindings.station_return)
	return campaign_cursor==4 and bindings.source_architecture=="x86_64" and SecondReturn.parameters(bindings.full_hold_return) and PlayerDeath.parameters(bindings.player_destruction) and GameOver.parameters(bindings.game_over_presentation) and Particles.parameters(bindings.full_hold_particles) and not bindings.audio.is_empty()

func configure(library: RefCounted, bindings: RefCounted, visuals: RefCounted, packet: Dictionary, confirmed: bool, now_microseconds: int, environment_seconds: Variant=null, unix_seconds: Variant=null, mobile_layout:=false) -> bool:
	clear()
	if not packet.get("campaign_cursor") is int:return fail("Departure requires its native campaign cursor")
	var cursor: int=int(packet.get("campaign_cursor",-1))
	if not confirmed or not supported(bindings,cursor):return fail("Confirm departure with a supported mining trip")
	var cat:=Catalogues.new();var bodies:=Bodies.new();var effects:=Effects.new()
	if not cat.open(library) or not bodies.configure(library,bindings) or not effects.configure(library,bindings):return fail(cat.error+bodies.error+effects.error)
	var environment_seed: Variant=int(Time.get_unix_time_from_system()) if environment_seconds==null else environment_seconds
	var field_seed: Variant=int(Time.get_unix_time_from_system()) if unix_seconds==null else unix_seconds
	var construction:=Construction.new()
	# Mac Full HD uses its source large-display field composition.
	if not construction.prepare(bindings,cat,packet,environment_seed,field_seed,true,bodies,effects):return fail(construction.error)
	_world=Frame.new()
	var viewport_size:=Vector2i(get_viewport().get_visible_rect().size)
	if not _world.configure(bindings,cat,library,construction,"E",.5,viewport_size,mobile_layout,false,"P"):return fail(_world.error)
	_clock=Clock.new()
	if not _clock.configure(bindings,bindings.base_content_id) or not _clock.rebase(now_microseconds):return fail(_clock.error)
	scene=Scene.new();add_child(scene)
	if not scene.build(library,bindings,visuals,cat,_world):return fail(scene.error)
	scene.set_mobile_layout(mobile_layout);camera=scene.camera
	briefing_audio=Speech.new();add_child(briefing_audio)
	objective_audio=Speech.new();add_child(objective_audio)
	if not briefing_audio.configure_mining_briefing(library,bindings,cursor) or not objective_audio.configure_mining_objective(library,bindings,cursor):return fail(briefing_audio.error+objective_audio.error)
	if cursor==4:
		flight_audio=FlightAudio.new();add_child(flight_audio)
		if not flight_audio.configure_full_hold(library,bindings,_world,int(field_seed)):return fail(flight_audio.error)
		if scene.game_over==null:return fail("Second-trip continuation display is unavailable")
		scene.game_over.set_active(false)
		scene.game_over.continue_requested.connect(func():
			if not request_game_over_exit():transition_rejected.emit(error))
	scene.dialogue.next_requested.connect(func():navigate("next"))
	scene.dialogue.previous_requested.connect(func():navigate("previous"))
	scene.dialogue.set_active(false);status="running"
	return true

func activate() -> bool:
	if status!="running" or _active:return reject("This mining trip cannot be activated")
	var prepared:={}
	if flight_audio!=null:
		prepared=flight_audio.prepare_full_hold(_world)
		if prepared.is_empty():return reject(flight_audio.error)
	_active=true;camera.make_current();_sync_input()
	if flight_audio!=null:flight_audio.commit_frame(prepared)
	return true

func step(now_microseconds: int, commands:=Vector2.ZERO, _fire_primary:=false) -> bool:
	error=""
	if not _active or (status!="running" and status not in BOUNDARIES):return reject("Activate the mining trip before advancing it")
	if not commands.is_finite() or absf(commands.x)>1 or absf(commands.y)>1:return reject("Invalid mining trip controls")
	var clock: RefCounted=_clock.fork_for_frame()
	var blocked: bool=is_paused() or status!="running" or _world.dialogue_visible()
	var milliseconds:=roundi(clock.sample(now_microseconds,blocked)*1000)
	if not clock.error.is_empty():return reject(clock.error)
	if is_paused() or status!="running":_clock=clock;return true
	var drilling: bool=_world.drill_owner()!=null
	var world: RefCounted=_world.evaluate(milliseconds,Vector2.ZERO if drilling else commands,_throttle,false,Vector2i(camera.get_viewport().get_visible_rect().size),commands if drilling else Vector2.ZERO)
	if world==null:return reject(_world.error)
	if not _commit(world,true,floori(float(now_microseconds)/1000.0)):return false
	_clock=clock
	return true

func navigate(action: String) -> bool:
	error=""
	if not _active or status!="running" or is_paused():return reject("Mining conversation is inactive")
	var world: RefCounted=_world.navigate(action)
	if world==null:return reject(_world.error)
	return _commit(world,false)

func action(name: String) -> bool:
	error=""
	if not can_control() and not (can_stop_mining() and name in ["dock","fire"]):return reject("Mining controls are inactive")
	var world: RefCounted
	match name:
		"dock","fire":
			if _world.drill_owner()!=null:world=_world.stop_mining()
			elif _world.snapshot().mining_approach.phase!="idle":world=_world.cancel_mining()
			else:world=_world.start_mining()
		"autopilot":
			world=_world.cancel_station_autopilot() if _world.snapshot().station_autopilot.active else _world.start_station_autopilot()
		"throttle_up","throttle_down":
			_throttle=clampf(_throttle+(.1 if name=="throttle_up" else -.1),0,1)
			return true
		_:return reject("This action is unavailable in the mining trip")
	if world==null:return reject(_world.error)
	if not _commit(world,false):return false
	if name=="autopilot" and _world.snapshot().station_autopilot.active:_throttle=1.0
	return true

func _commit(world: RefCounted, advance_sun: bool, absolute_milliseconds: int=-1) -> bool:
	var state: Dictionary=world.snapshot()
	var briefing_line:=-1;var objective_line:=-1
	if state.dialogue.visible:
		if state.phase=="briefing":briefing_line=int(state.dialogue.index)
		elif state.phase=="return_instructions":objective_line=int(state.dialogue.index)
		else:return reject("Unsupported mining conversation")
	if not briefing_audio.valid_line(briefing_line) or not objective_audio.valid_line(objective_line):return reject("Mining speech is unavailable")
	var sound:={}
	if flight_audio!=null:
		sound=flight_audio.prepare_full_hold(world)
		if sound.is_empty():return reject(flight_audio.error)
	var presentation_time: int=_presentation_ms if absolute_milliseconds<0 else absolute_milliseconds
	if not scene.present(world,advance_sun,presentation_time):return reject(scene.error)
	_world=world;_generation+=1
	_presentation_ms=presentation_time
	briefing_audio.present(briefing_line);objective_audio.present(objective_line)
	if flight_audio!=null:flight_audio.commit_frame(sound)
	if state.get("boundary","") in BOUNDARIES:status=state.boundary
	_sync_input()
	return true

func request_game_over_exit() -> bool:
	error=""
	if not _active or status!="running" or is_paused():return reject("Game-over continuation is inactive")
	var world: RefCounted=_world.request_game_over_exit()
	if world==null:return reject(_world.error)
	return _commit(world,false)

func prepare_game_over() -> Dictionary:
	return _world.prepare_game_over() if _world!=null and status=="game_over_transition_required" else {}

func handle_game_over_event(event: InputEvent) -> bool:
	# Observe fire edges throughout flight, including before lethal contact.
	# The panel's active/readiness gates prevent acknowledgement during pauses.
	return _active and status=="running" and scene.game_over!=null and scene.game_over.handle_event(event)

func _sync_input() -> void:
	var enabled: bool=_active and status=="running" and not is_paused()
	scene.dialogue.set_active(enabled)
	if scene.game_over!=null:scene.game_over.set_active(enabled)

func present_current() -> bool:
	return scene!=null and scene.present(_world,false,_presentation_ms)

func set_pause(reason: String, paused: bool, now_microseconds: int) -> bool:
	if _clock==null or reason not in ["user","focus","hidden","transition"] or now_microseconds<0:return reject("Invalid mining pause")
	if _pauses.has(reason)==paused:return true
	if not _clock.rebase(now_microseconds):return reject(_clock.error)
	if paused:_pauses[reason]=true
	else:_pauses.erase(reason)
	briefing_audio.set_paused(is_paused());objective_audio.set_paused(is_paused())
	if flight_audio!=null:flight_audio.set_paused(is_paused())
	_sync_input()
	return true

func rebase_time(now_microseconds: int) -> bool:
	return _clock!=null and _clock.rebase(now_microseconds)
func is_paused() -> bool:return not _pauses.is_empty()
func can_control() -> bool:return _active and status=="running" and not is_paused() and not _world.death_active() and _world.snapshot().entry_released and not _world.dialogue_visible()
func can_stop_mining() -> bool:return _active and status=="running" and not is_paused() and not _world.game_over_waiting() and _world.drill_owner()!=null and not _world.dialogue_visible()
func flight_hud_visible(state: Dictionary={}) -> bool:
	if _world==null:return false
	if state.is_empty():state=_world.snapshot()
	return status=="running" and state.entry_released and not state.dialogue.visible and state.get("player_destruction",{}).get("hud_visible",true)
func flight_owner() -> RefCounted:return null if _world==null else _world.fork_for_frame()
func snapshot() -> Dictionary:
	if _world==null:return {}
	var state: Dictionary=_world.snapshot();state.session_generation=_generation;state.input_throttle=_throttle
	return state
func clear() -> void:
	for child in get_children():child.free()
	error="";status="idle";camera=null;scene=null;briefing_audio=null;objective_audio=null;flight_audio=null
	_world=null;_clock=null;_pauses={};_active=false;_throttle=1.0;_generation=0
	_presentation_ms=0
func fail(message: String) -> bool:clear();status="error";error=message;return false
func reject(message: String) -> bool:error=message;return false

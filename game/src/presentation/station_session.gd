extends Node3D
## Station scene built from an accepted rescue or mining return. Loading and panel
## preparation precede activation; only explicit acknowledgement advances story.
const World=preload("res://src/simulation/station_entry.gd")
const Motion=preload("res://src/simulation/station_camera.gd")
const Definitions=preload("res://src/content/station_presentation_definitions.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Clock=preload("res://src/simulation/frame_clock.gd")
const Geometry=preload("res://src/presentation/hangar_geometry.gd")
const Speech=preload("res://src/presentation/station_audio.gd")
const BOUNDARIES=["launch_required","station_reload_required","station_followup_required"]
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

func configure_return(library: RefCounted, bindings: RefCounted, visuals: RefCounted, flight: RefCounted, now_microseconds: int, camera_seed: int=0) -> bool:
	clear()
	if not supported(bindings):return fail("This pack has no supported station scene")
	var cat:=Catalogues.new()
	if not cat.open(library):return fail(cat.error)
	_world=World.new()
	if not _world.configure_return(bindings,cat,library,flight):return fail(_world.error)
	return _build_scene(library,bindings,visuals,cat,now_microseconds,camera_seed)

func configure_reload(library: RefCounted, bindings: RefCounted, visuals: RefCounted, previous: RefCounted, now_microseconds: int, camera_seed: int=0) -> bool:
	clear()
	if not supported(bindings):return fail("This pack has no supported station scene")
	var cat:=Catalogues.new()
	if not cat.open(library):return fail(cat.error)
	_world=World.new()
	if not _world.configure_reload(bindings,cat,library,previous):return fail(_world.error)
	return _build_scene(library,bindings,visuals,cat,now_microseconds,camera_seed)

func _build_scene(library: RefCounted, bindings: RefCounted, visuals: RefCounted, cat: RefCounted, now_microseconds: int, camera_seed: int) -> bool:
	var seed: Dictionary=_world.snapshot().loadout
	var selected: Dictionary=bindings.resolve_hangar(int(seed.station_id),cat)
	if selected.is_empty():return fail(bindings.error)
	if selected.row!=bindings.station_presentation.hangar_row:return fail("Station camera belongs to another hangar")
	selected.ship=bindings.resolve_hangar_ship(int(seed.ship_id))
	if selected.ship.is_empty():return fail(bindings.error)
	geometry=Geometry.new();add_child(geometry)
	if not geometry.build(selected,library,visuals,bindings):return fail(geometry.error)
	_motion=Motion.new()
	if not _motion.configure(bindings.station_presentation,camera_seed):return fail(_motion.error)
	_dialogue_delay_ms=int(bindings.station_presentation.dialogue.start_delay_ms)
	_clock=Clock.new()
	if not _clock.configure(bindings,bindings.base_content_id) or not _clock.rebase(now_microseconds):return fail(_clock.error)
	camera=Camera3D.new();add_child(camera)
	var projection: Array=bindings.station_presentation.camera.projection
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.set_perspective(rad_to_deg(projection[0]),projection[1],projection[2])
	camera.transform=_motion.snapshot().pose
	build_lighting(bindings.station_presentation.light)
	audio=Speech.new();add_child(audio)
	var state: Dictionary=_world.snapshot()
	var voice_ready: bool=true
	if state.phase=="station_followup_required":
		# No voice is scheduled for a conversation whose mission is unsupported.
		_dialogue_started=true
	elif state.get("equipment_conversation",false):
		voice_ready=audio.configure_station_equipment(library,bindings)
		_dialogue_started=not state.dialogue.visible
	else:
		voice_ready=audio.configure_station_return(library,bindings,int(state.campaign_cursor)) if state.get("return_visit",false) else audio.configure(library,bindings)
	if not voice_ready:return fail(audio.error)
	station_name=cat.tables.stations[int(selected.station_id)].name
	status="running"
	return true

func build_lighting(data: Dictionary) -> void:
	# Source direction and ambient/diffuse colors adapted to Godot PBR. Original
	# station shader selection, inherited global/rim state remain unverified.
	var direction: Vector3=-(Basis(Vector3.UP,float(data.initial_camera_yaw)).z+Motion.vector(data.direction_bias)).normalized()
	var light:=DirectionalLight3D.new();add_child(light)
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

func activate() -> bool:
	if status!="running" or _active:return reject("Station scene cannot be activated")
	_active=true;camera.make_current()
	return true

func step(now_microseconds: int, commands:=Vector2.ZERO, fire_primary:=false) -> bool:
	if status!="running" or not _active or commands!=Vector2.ZERO or fire_primary:return reject("Station scene cannot accept flight input")
	var clock: RefCounted=_clock.fork_for_frame()
	var milliseconds:=roundi(clock.sample(now_microseconds,is_paused())*1000)
	if not clock.error.is_empty():return reject(clock.error)
	if is_paused():_clock=clock;return true
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
	var packet: Dictionary=_world.prepare_departure(bindings,catalogues)
	if packet.is_empty():reject(_world.error)
	return packet

func equipment_action(action: String, item_id: int, library: RefCounted, bindings: RefCounted, panel: Control, hangar: Control) -> bool:
	error=""
	if status!="running" or not _active or not _dialogue_started or is_paused() or panel==null or hangar==null:return reject("Equipment controls are inactive")
	var candidate: RefCounted=_world.fork()
	if action=="open":
		var cat:=Catalogues.new()
		if not cat.open(library):return reject(cat.error)
		if not candidate.open_equipment(bindings,cat,library):return reject(candidate.error)
		if not audio.prepare_equipment_effects(bindings.station_equipment):return reject(audio.error)
	elif action=="close":
		if not candidate.close_equipment():return reject(candidate.error)
	elif not candidate.equipment_action(action,item_id):return reject(candidate.error)
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
	if action in ["mount","unmount"]:audio.play_equipment_effect(int(bindings.station_equipment.mount_audio_id if action=="mount" else bindings.station_equipment.unmount_audio_id))
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
	return state
func clear() -> void:
	for child in get_children():child.free()
	error="";status="idle";station_name="";camera=null;geometry=null;audio=null
	_world=null;_motion=null;_clock=null;_pauses={};_active=false;_generation=0
	_dialogue_started=false;_dialogue_delay_ms=0
func fail(message: String) -> bool:clear();status="error";error=message;return false
func reject(message: String) -> bool:error=message;return false

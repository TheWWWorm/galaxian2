extends Node3D
## Runs the Mac rescue from a prepared Opening packet with shared native scene
## resources. Station entry remains a boundary without rewards or save writes.
const World=preload("res://src/simulation/arrival_world_frame.gd")
const Definitions=preload("res://src/content/arrival_session_definitions.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Clock=preload("res://src/simulation/frame_clock.gd")
const Geometry=preload("res://src/presentation/opening_geometry.gd")
const Background=preload("res://src/presentation/opening_sky.gd")
const Planets=preload("res://src/presentation/opening_planet_geometry.gd")
const Sun=preload("res://src/presentation/opening_sun_geometry.gd")
const Lighting=preload("res://src/presentation/opening_lighting.gd")
const SceneryGeometry=preload("res://src/presentation/scenery_geometry.gd")
const BodyResources=preload("res://src/content/scenery_body_resources.gd")
const FlightProjection=preload("res://src/presentation/flight_camera.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
const BOUNDARIES=["station_transition_required"]
var error:=""
var status:="idle"
var radio_resources: RefCounted
var geometry: Node3D
var sky: Node3D
var planets: Node3D
var sun: Node3D
var scenery: Node3D
var camera: Camera3D
var audio: Node3D
var fade_overlay: ColorRect
var _world: RefCounted
var _clock: RefCounted
var _projection: RefCounted
var _pauses:={}

static func supported(bindings: RefCounted) -> bool:
	return bindings!=null and Definitions.parameters(bindings.arrival_session)

func configure(library: RefCounted, bindings: RefCounted, visuals: RefCounted, packet: Dictionary, now_microseconds: int, unix_seconds: Variant=null, large_display:=true) -> bool:
	clear()
	if not supported(bindings) or library==null or visuals==null:return fail("Prepare current Mac content, bindings and textures for the rescue")
	var cat:=Catalogues.new()
	if not cat.open(library):return fail(cat.error)
	radio_resources=RadioResources.new()
	if not radio_resources.prepare(library,bindings,visuals,1):return fail(radio_resources.error)
	var body_resources:=BodyResources.new()
	if not body_resources.configure(library,bindings):return fail(body_resources.error)
	var seed: Variant=int(Time.get_unix_time_from_system()) if unix_seconds==null else unix_seconds
	if not seed is int:return fail("Rescue requires integer Unix seconds for field construction")
	_world=World.new()
	if not _world.configure(bindings,cat,library,packet,radio_resources.line_counts,seed,large_display,body_resources):return fail(_world.error)
	_clock=Clock.new();_projection=FlightProjection.new()
	if not _clock.configure(bindings,bindings.base_content_id) or not _clock.rebase(now_microseconds):return fail(_clock.error)
	var message: String=_projection.configure(bindings.flight_projection,1,false)
	if not message.is_empty():return fail(message)
	camera=Camera3D.new();camera.current=true;add_child(camera)
	geometry=Geometry.new();add_child(geometry)
	if not geometry.build_arrival(library,visuals,bindings,cat,packet.player_cache,"high",true):return fail(geometry.error)
	sky=Background.new();add_child(sky)
	if not sky.build_arrival(library,visuals,bindings,cat,packet.player_cache):return fail(sky.error)
	planets=Planets.new();add_child(planets)
	if not planets.build_arrival(library,visuals,bindings,cat,packet.player_cache):return fail(planets.error)
	sun=Sun.new();add_child(sun)
	if not sun.build_arrival(library,visuals,bindings,cat,packet.player_cache):return fail(sun.error)
	var lights:=Lighting.new();add_child(lights)
	if not lights.build_arrival(bindings,cat,packet.player_cache):return fail(lights.error)
	scenery=SceneryGeometry.new();add_child(scenery)
	if not scenery.build(_world.snapshot().scenery,library,visuals,bindings,"high",true):return fail(scenery.error)
	var overlay:=CanvasLayer.new();overlay.layer=10;add_child(overlay)
	fade_overlay=ColorRect.new();fade_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.add_child(fade_overlay);fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	audio=Audio.new();add_child(audio)
	if not audio.configure(library,bindings,0,1):return fail(audio.error)
	if not present():return fail(error)
	status="running"
	return true

func step(now_microseconds: int, commands:=Vector2.ZERO, fire_primary:=false) -> bool:
	error=""
	if status!="running" and status not in BOUNDARIES:return reject("Start the rescue before advancing it")
	if commands!=Vector2.ZERO or fire_primary:return reject("Player flight is frozen during the rescue")
	if now_microseconds<0:return reject("Invalid rescue timestamp")
	var clock: RefCounted=_clock.fork_for_frame()
	var seconds: float=clock.sample(now_microseconds,is_paused() or status in BOUNDARIES)
	if not clock.error.is_empty():return reject(clock.error)
	if is_paused() or status in BOUNDARIES:_clock=clock;return true
	var world: RefCounted=_world.evaluate(roundi(seconds*1000.0))
	if world==null:return reject(_world.error)
	var previous:=_world
	_world=world
	if not present(true):
		var message:=error;_world=previous
		if not present():message+="; prior frame presentation: "+error
		return reject(message)
	_clock=clock
	var boundary: String=_world.snapshot().boundary
	if not boundary.is_empty():status=boundary;audio.set_paused(true)
	return true

func present(advance_sun:=false) -> bool:
	var state: Dictionary=_world.snapshot()
	var audio_frame: Dictionary=audio.prepare_frame(int(state.generation),state)
	if audio_frame.is_empty():return reject(audio.error)
	var prior: float=sun.frame.get("next_intensity" if advance_sun else "previous_intensity",0.0)
	var sun_frame: Dictionary=sun.prepare_frame(state.camera.view,Vector2i(camera.get_viewport().get_visible_rect().size),prior)
	if sun_frame.has("error"):return reject(sun.error)
	if not geometry.apply_arrival(state.staging,state.actor,state.ship_detail):return reject(geometry.error)
	var message: String=_projection.apply(camera,state.camera.view)
	if not message.is_empty():return reject(message)
	if not sky.apply_view(state.camera.view):return reject(sky.error)
	if not planets.apply_view(state.camera.view):return reject(planets.error)
	if not scenery.apply_state(state.scenery) or not scenery.apply_detail(state.scenery.detail):return reject(scenery.error)
	sun.commit_frame(sun_frame)
	fade_overlay.color=Color(0,0,0,float(state.fade.alpha_byte)/255.0)
	fade_overlay.visible=state.fade.alpha_byte>0
	# Playback starts only after every prospective scene resource accepts the frame.
	audio.commit_frame(audio_frame)
	return true

func set_pause(reason: String, paused: bool, now_microseconds: int) -> bool:
	error=""
	if _clock==null or reason not in ["user","focus","hidden"] or now_microseconds<0:return reject("Invalid rescue pause context")
	if _pauses.has(reason)==paused:return true
	if not _clock.rebase(now_microseconds):return reject(_clock.error)
	if paused:_pauses[reason]=true
	else:_pauses.erase(reason)
	if audio!=null:audio.set_paused(is_paused() or status in BOUNDARIES)
	return true

func rebase_time(now_microseconds: int) -> bool:
	if _clock==null:return reject("Rescue clock is unavailable")
	if not _clock.rebase(now_microseconds):return reject(_clock.error)
	return true

func is_paused() -> bool:return not _pauses.is_empty()
func can_control() -> bool:return false
func flight_hud_visible(_state: Dictionary={}) -> bool:return false
func prepare_station() -> Dictionary:
	error=""
	if _world==null or status!="station_transition_required":
		error="The rescue has not reached station entry"
		return {}
	var packet: Dictionary=_world.prepare_station()
	if packet.is_empty():error=_world.error
	return packet

func snapshot() -> Dictionary:return {} if _world==null else _world.snapshot()
func clear() -> void:
	for child in get_children():child.free()
	error="";status="idle";radio_resources=null;geometry=null;sky=null;planets=null;sun=null;scenery=null;camera=null;audio=null;fade_overlay=null
	_world=null;_clock=null;_projection=null;_pauses.clear()
func fail(message: String) -> bool:clear();status="error";error=message;return false
func reject(message: String) -> bool:error=message;return false

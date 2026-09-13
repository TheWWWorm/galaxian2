extends Node3D
## Runs the recovered fresh opening and optional ordinary encounter as one scene.
## Unsupported mission and player-death transitions stop without save progression.
const Audio=preload("res://src/presentation/opening_audio.gd")
const EscapeGeometry=preload("res://src/presentation/opening_escape_geometry.gd")
const EscapeFade=preload("res://src/simulation/opening_escape_fade.gd")
const Scenery = preload("res://src/simulation/opening_scenery.gd")
const ImpactGeometry = preload("res://src/presentation/ordinary_impact_geometry.gd")
const DamageGeometry=preload("res://src/presentation/opening_damage_geometry.gd")
const ProjectileGeometry = preload("res://src/presentation/projectile_geometry.gd")
const TargetFrame = preload("res://src/presentation/flight_target_frame.gd")
const NpcMarkers = preload("res://src/presentation/flight_npc_markers.gd")
const WorldFrame = preload("res://src/simulation/opening_world_frame.gd")
const SceneryGeometry = preload("res://src/presentation/scenery_geometry.gd")
const SceneryBodyResources = preload("res://src/content/scenery_body_resources.gd")
const SceneryEffectResources = preload("res://src/content/scenery_effect_resources.gd")
const NpcDeathResources = preload("res://src/content/npc_destruction_resources.gd")
const NpcDeathGeometry = preload("res://src/presentation/npc_destruction_geometry.gd")
const Reflection = preload("res://src/presentation/environment_reflection.gd")
const TargetInventory = preload("res://src/simulation/opening_target_inventory.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Timeline = preload("res://src/simulation/opening_detail_timeline.gd")
const Clock = preload("res://src/simulation/frame_clock.gd")
const Geometry = preload("res://src/presentation/opening_geometry.gd")
const Background = preload("res://src/presentation/opening_sky.gd")
const Planets = preload("res://src/presentation/opening_planet_geometry.gd")
const Sun = preload("res://src/presentation/opening_sun_geometry.gd")
const Lighting = preload("res://src/presentation/opening_lighting.gd")
const FlightProjection = preload("res://src/presentation/flight_camera.gd")
const RadioResources = preload("res://src/presentation/opening_radio_resources.gd")
const Handoff = preload("res://src/simulation/opening_handoff.gd")
var error := ""
var status := "idle"
var radio_resources: RefCounted
var geometry: Node3D
var scenery: Node3D
var _scenery: RefCounted
var _targets: RefCounted
var _world_frame: RefCounted
var projectiles: Node3D
var impacts: Node3D
var damage_particles: Node3D
var npc_deaths: Node3D
var sky: Node3D
var planets: Node3D
var sun: Node3D
var camera: Camera3D
var _timeline: RefCounted
var _clock: RefCounted
var _projection: RefCounted
var _pauses := {}
var _combat_event := -1
var interactive := false
var _postcombat_event := -1
var escape_sequence:=false
var hyperdrive: Node3D
var fade_overlay: ColorRect
var _fade: RefCounted
var audio: Node3D
var _audio_revision:=0
const BOUNDARIES := ["encounter_required","mission_transition_required","player_death_required","arrival_transition_required"]
# Explicit native preview preset. Source preference restoration and fogged
# variants remain separate work; these values do not claim automatic selection.
const EFFECT_RESPONSE := {"variant":"unfogged_two_light_cube","diffuse_bias":-1,"normal_bias":0}

# The preview explicitly selects the source Normal value. This is not saved
# difficulty restoration; a future game session must supply its selected value.
# The application enables escape when all of its connected owners are available.
# Explicit contributor sessions may still exercise earlier partial capabilities.
func configure(library: RefCounted, bindings: RefCounted, visuals: RefCounted, now_microseconds: int, difficulty: Variant = 0.5, scenery_unix_seconds: Variant = null, scenery_large_display := true, player_controls := false, with_escape := false) -> bool:
	clear()
	if library==null or bindings==null or visuals==null:return fail("Open content, bindings and prepared textures before starting the opening")
	if player_controls and not supports_player_controls(bindings):return fail("This binding pack lacks the supported opening encounter")
	if with_escape and (not player_controls or bindings.opening_staging.get("escape_camera",{}).is_empty()):return fail("Escape presentation requires the supported interactive opening and escape bindings")
	escape_sequence=with_escape
	interactive=player_controls
	if interactive:_postcombat_event=int(bindings.opening_staging.player_flight.postcombat_after_event_finished)
	var catalogues := Catalogues.new()
	if not catalogues.open(library):return fail(catalogues.error)
	radio_resources=RadioResources.new()
	if not radio_resources.prepare(library,bindings,visuals):return fail(radio_resources.error)
	for i in bindings.opening_dialogue.events.size():
		if int(bindings.opening_dialogue.events[i].condition)==9:
			_combat_event=i;break
	if _combat_event<=0:return fail("Opening has no recognized precombat boundary")
	_timeline=Timeline.new();_clock=Clock.new();_projection=FlightProjection.new()
	if not _timeline.configure(bindings,catalogues,library,radio_resources.line_counts,1.0,difficulty):return fail(_timeline.error)
	if escape_sequence:
		if not _timeline.configure_escape(bindings,library):return fail(_timeline.error)
		_fade=EscapeFade.new()
		if not _fade.configure(_timeline.escape_owner()):return fail(_fade.error)
	if not _clock.configure(bindings,library.manifest.content_id):return fail(_clock.error)
	if not _clock.rebase(now_microseconds):return fail(_clock.error)
	var projection_error: String = _projection.configure(bindings.flight_projection,0,false)
	if not projection_error.is_empty():return fail(projection_error)
	camera=Camera3D.new();camera.current=true;add_child(camera)
	geometry=Geometry.new();add_child(geometry)
	if not geometry.build(library,visuals,bindings,catalogues,"high",true):return fail(geometry.error)
	if escape_sequence:
		hyperdrive=EscapeGeometry.new();add_child(hyperdrive)
		if not hyperdrive.build(_timeline.escape_owner(),library,visuals,bindings):return fail(hyperdrive.error)
		var overlay:=CanvasLayer.new();overlay.layer=10;add_child(overlay)
		fade_overlay=ColorRect.new();fade_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
		overlay.add_child(fade_overlay);fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky=Background.new();add_child(sky)
	if not sky.build(library,visuals,bindings,catalogues,0,3,false,"high",escape_sequence):return fail(sky.error)
	if not bindings.opening_sky.get("planet_resources",{}).is_empty():
		planets=Planets.new();add_child(planets)
		if not planets.build(library,visuals,bindings,catalogues,"high",escape_sequence):return fail(planets.error)
	if not bindings.opening_sky.get("sun_flares",{}).is_empty():
		sun=Sun.new();add_child(sun)
		if not sun.build(library,visuals,bindings,catalogues):return fail(sun.error)
	var lights := Lighting.new();add_child(lights)
	if not lights.build(bindings,catalogues,library.manifest.content_id,0,3,false):return fail(lights.error)
	var seed_seconds: Variant = int(Time.get_unix_time_from_system()) if scenery_unix_seconds==null else scenery_unix_seconds
	var body_resources := SceneryBodyResources.new()
	if not body_resources.configure(library,bindings):return fail(body_resources.error)
	var effect_resources: RefCounted
	if not bindings.scenery_effects.is_empty():
		effect_resources=SceneryEffectResources.new()
		if not effect_resources.configure(library,bindings):return fail(effect_resources.error)
	_scenery=Scenery.new()
	if not _scenery.configure(bindings,catalogues,seed_seconds,scenery_large_display,body_resources,effect_resources):return fail(_scenery.error)
	if not bindings.opening_actors.get("npc_initialization",{}).get("world_initialization",{}).is_empty():
		if not _scenery.complete_world_initialization(bindings,catalogues):return fail(_scenery.error)
		var death_resources: RefCounted
		if not bindings.opening_actors.npc_initialization.get("destruction",{}).is_empty():
			death_resources=NpcDeathResources.new()
			if not death_resources.configure(library,bindings):return fail(death_resources.error)
		_world_frame=WorldFrame.new()
		if not _world_frame.configure(bindings,catalogues,_scenery,difficulty,death_resources):return fail(_world_frame.error)
		if not bindings.vehicle_response.get("audio",{}).is_empty() and not _world_frame.configure_engine_audio(bindings,catalogues,_timeline.snapshot().scene):return fail(_world_frame.error)
		if not bindings.damage_particles.get("owners",{}).is_empty() and not _world_frame.configure_damage_particles(bindings,_timeline.snapshot().combat,seed_seconds):return fail(_world_frame.error)
		if _world_frame.damage_particle_owner()!=null:
			damage_particles=DamageGeometry.new();add_child(damage_particles)
			if not damage_particles.build(_world_frame.damage_particle_owner(),library,visuals,bindings):return fail(damage_particles.error)
		if interactive and not _world_frame.configure_player_flight(bindings,catalogues,library,_scenery,1.0):return fail(_world_frame.error)
		if interactive and not bindings.opening_staging.get("player_aim",{}).is_empty() and not _world_frame.configure_player_aim(bindings):return fail(_world_frame.error)
		if interactive and not bindings.opening_staging.get("npc_scanner",{}).is_empty():
			var frame := TargetFrame.source_geometry(library,bindings)
			if frame.has("error"):return fail(frame.error)
			var scanner := NpcMarkers.source_geometry(library,bindings)
			if scanner.has("error"):return fail(scanner.error)
			if not _world_frame.configure_npc_scanner(bindings,catalogues,TargetFrame.logical_radii(frame.quarter_size,OS.has_feature("mobile")),scanner.frames):return fail(_world_frame.error)
		if death_resources!=null:
			npc_deaths=NpcDeathGeometry.new();add_child(npc_deaths)
			if not npc_deaths.build(_world_frame,library,visuals,bindings):return fail(npc_deaths.error)
	if _world_frame!=null and not bindings.opening_staging.get("projectile_visuals",{}).is_empty():
		if not _world_frame.configure_projectile_visuals(bindings,library):return fail(_world_frame.error)
		projectiles=ProjectileGeometry.new();add_child(projectiles)
		if not projectiles.build(_world_frame.projectile_visual_owner(),library,visuals,bindings,false):return fail(projectiles.error)
		if _world_frame.impact_visual_owner()!=null:
			impacts=ImpactGeometry.new();add_child(impacts)
			if not impacts.build(_world_frame.impact_visual_owner(),library,visuals,bindings):return fail(impacts.error)
	_targets=TargetInventory.new()
	if not _targets.configure(bindings,catalogues,_scenery.snapshot()):return fail(_targets.error)
	if not _targets.validate_owners(_timeline.snapshot().get("combat",{}),_scenery.snapshot().bodies):return fail(_targets.error)
	scenery=SceneryGeometry.new();add_child(scenery)
	if not scenery.build(_scenery.snapshot(),library,visuals,bindings,"high",true):return fail(scenery.error)
	if effect_resources!=null:
		var reflection := Reflection.new()
		if not reflection.build_opening(library,bindings,catalogues,0,3,false):return fail(reflection.error)
		if not scenery.prepare_destruction(_scenery.snapshot(),library,visuals,bindings,effect_resources,lights.state,reflection,EFFECT_RESPONSE):return fail(scenery.error)
	# Ships retain their current PBR presentation. Scenery uses the explicit
	# preset consistently for intact models, fragments and retained cargo.
	if _world_frame!=null:
		var initial: Dictionary=_world_frame.evaluate(_timeline,_scenery,0,true,1.0,Vector2.ZERO,false,Vector2i(camera.get_viewport().get_visible_rect().size))
		if initial.is_empty():return fail(_world_frame.error)
		_world_frame=initial.world_frame;_timeline=initial.timeline;_scenery=initial.scenery
	else:
		if not _timeline.update(0,true,false,false,1.0):return fail(_timeline.error)
		if not _scenery.update(0,Vector3.ZERO):return fail(_scenery.error)
	if not bindings.audio.is_empty():
		audio=Audio.new();add_child(audio)
		if not audio.configure(library,bindings):return fail(audio.error)
	if not present():return fail(error)
	status="running"
	return true

func set_pause(reason: String, paused: bool, now_microseconds: int) -> bool:
	error=""
	if _clock==null or reason not in ["user","focus","hidden"] or now_microseconds<0:return reject("Invalid opening pause context")
	if _pauses.has(reason)==paused:return true
	if not _clock.rebase(now_microseconds):return reject(_clock.error)
	if paused:_pauses[reason]=true
	else:_pauses.erase(reason)
	if audio!=null:audio.set_paused(is_paused() or status in BOUNDARIES)
	return true

func is_paused() -> bool:
	return not _pauses.is_empty()

func rebase_time(now_microseconds: int) -> bool:
	error=""
	if _clock==null:return reject("Opening clock is unavailable")
	if not _clock.rebase(now_microseconds):return reject(_clock.error)
	return true

static func supports_player_controls(bindings: RefCounted) -> bool:
	if bindings==null:return false
	return not bindings.opening_staging.get("player_flight",{}).is_empty() and not bindings.opening_staging.get("projectile_impacts",{}).is_empty() and not bindings.opening_actors.get("npc_initialization",{}).get("world_initialization",{}).is_empty() and not bindings.opening_actors.npc_initialization.get("destruction",{}).is_empty()

static func supports_escape(bindings: RefCounted) -> bool:
	if not supports_player_controls(bindings):return false
	# Capability checks preserve independently imported editions and older packs.
	# No version number implies that an absent owner has been implemented.
	for capability in [bindings.opening_staging.get("escape",{}),bindings.opening_staging.get("escape_camera",{}),
		bindings.opening_staging.get("player_aim",{}),bindings.opening_staging.get("npc_scanner",{}),
		bindings.opening_sky.get("planet_resources",{}),bindings.opening_sky.get("sun_flares",{}),
		bindings.damage_particles.get("owners",{}),bindings.audio,bindings.opening_dialogue.get("voice",{}),
		bindings.weapon_parameters.get("audio",{}),bindings.vehicle_response.get("audio",{}),
		bindings.opening_actors.npc_initialization.get("destruction_audio",{})]:
		if capability.is_empty():return false
	return true

func flight_hud_visible(state: Dictionary = {}) -> bool:
	if not interactive or _timeline==null or _world_frame==null:return false
	if state.is_empty():state=_timeline.snapshot()
	# The source enables the HUD on entering ordinary flight and clears it on
	# escape entry. Pauses retain the drawn HUD; destroyed ships do not.
	return int(state.camera.shot.phase)==4 and state.get("escape",{}).get("hud_visible",true) and status!="player_death_required"

func can_control() -> bool:
	return status=="running" and not is_paused() and flight_hud_visible()

func step(now_microseconds: int, commands := Vector2.ZERO, fire_primary := false) -> bool:
	error=""
	if status!="running" and status not in BOUNDARIES:return reject("Start the opening before advancing it")
	if not commands.is_finite() or absf(commands.x)>1.0 or absf(commands.y)>1.0:return reject("Invalid opening flight commands")
	if not interactive and (commands!=Vector2.ZERO or fire_primary):return reject("This opening has no connected player controls")
	if now_microseconds<0:return reject("Invalid opening timestamp")
	if status=="running" and not is_paused() and scenery.destruction==null and _scenery.has_pending_destruction():
		return reject("Scenery destruction requires its verified effect and lifecycle owner")
	var clock: RefCounted=_clock.fork_for_frame()
	var seconds: float = clock.sample(now_microseconds,is_paused() or status in BOUNDARIES)
	if not clock.error.is_empty():return reject(clock.error)
	if is_paused() or status in BOUNDARIES:_clock=clock;return true
	var timeline: RefCounted=_timeline.fork_for_frame()
	var scenery_owner: RefCounted=_scenery.fork_for_frame()
	var previous: Dictionary = _timeline.snapshot()
	var world_frame: RefCounted=_world_frame
	var fade: RefCounted=null if _fade==null else _fade.fork_for_frame()
	if fade!=null and not fade.advance(roundi(seconds*1000.0)):return reject(fade.error)
	if world_frame!=null:
		var result: Dictionary=world_frame.evaluate(timeline,scenery_owner,roundi(seconds*1000.0),true,1.0,commands,fire_primary,Vector2i(camera.get_viewport().get_visible_rect().size),true if fade==null else fade.is_active())
		if result.is_empty():return reject(world_frame.error)
		world_frame=result.world_frame;timeline=result.timeline;scenery_owner=result.scenery
	else:
		if not timeline.update(roundi(seconds*1000.0),true,false,false,1.0):return reject(timeline.error)
		var next: Dictionary = timeline.snapshot()
		var immediate_reference: Variant = next.scene.camera_position_parameter if next.scene.formation_revealed and not previous.scene.formation_revealed else null
		if not scenery_owner.update(roundi(seconds*1000.0),previous.detail_reference,1.0,immediate_reference):return reject(scenery_owner.error)
	if fade!=null and not fade.apply_escape(timeline.escape_owner()):return reject(fade.error)
	var old_fade:=_fade
	var old_clock := _clock;var old_timeline := _timeline;var old_scenery := _scenery
	var old_world_frame := _world_frame
	var old_audio_revision:=_audio_revision
	_audio_revision+=1
	_clock=clock;_timeline=timeline;_scenery=scenery_owner;_world_frame=world_frame;_fade=fade
	if not present(true):
		var message := error
		_audio_revision=old_audio_revision
		_clock=old_clock;_timeline=old_timeline;_scenery=old_scenery;_world_frame=old_world_frame;_fade=old_fade
		if not present():message+="; prior frame presentation: "+error
		return reject(message)
	var state: Dictionary = _timeline.snapshot()
	if interactive:
		if _world_frame.snapshot().player.vitals.hull<=0:status="player_death_required"
		elif escape_sequence:
			if state.escape.boundary=="arrival_transition_required":status="arrival_transition_required"
		elif state.radio.finished[_postcombat_event]:status="mission_transition_required"
	elif int(state.radio.active_event)==-1 and state.radio.finished.slice(0,_combat_event).all(func(done):return done) and int(state.camera.shot.phase)==4:
		status="encounter_required"
	if audio!=null and status in BOUNDARIES:audio.set_paused(true)
	return true

func present(advance_sun := false) -> bool:
	var state: Dictionary = _timeline.snapshot()
	var world_state: Dictionary={} if _world_frame==null else _world_frame.snapshot()
	var audio_frame:={}
	if audio!=null:
		audio_frame=audio.prepare_frame(_audio_revision,state,world_state)
		if audio_frame.is_empty():return reject(audio.error)
	var particle_frame:={}
	if damage_particles!=null:
		particle_frame=damage_particles.prepare_world(_world_frame.damage_particle_owner(),world_state,state.camera.view.get("pose",Transform3D.IDENTITY))
		if particle_frame.is_empty():return reject(damage_particles.error)
	var impact_frame:={}
	if impacts!=null:
		impact_frame=impacts.prepare_world(_world_frame.impact_visual_owner(),world_state,state.camera.view.get("pose",Transform3D.IDENTITY))
		if impact_frame.is_empty():return reject(impacts.error)
	var projectile_frame:={}
	if projectiles!=null:
		var projectile_camera: Transform3D=state.camera.view.get("pose",Transform3D.IDENTITY)
		projectile_frame=projectiles.prepare_world(_world_frame.projectile_visual_owner(),world_state,projectile_camera)
		if projectile_frame.is_empty():return reject(projectiles.error)
	var hyperdrive_frame:={}
	if hyperdrive!=null:
		hyperdrive_frame=hyperdrive.prepare_frame(_timeline.escape_owner())
		if hyperdrive_frame.is_empty():return reject(hyperdrive.error)
	if not geometry.apply_state(state.scene,{} if hyperdrive==null else state.escape):return reject(geometry.error)
	var view: Dictionary = state.camera.view
	# Fresh source renderers begin with an identity camera; the ordinary view
	# updater deliberately does nothing at zero elapsed frame time.
	if view.is_empty() and int(state.elapsed_ms)==0:view={"pose":Transform3D.IDENTITY}
	var sun_frame:={}
	if sun!=null:
		# An explicit zero is the native startup policy; the source constructor
		# leaves its first intensity unspecified. Replays retain the current
		# frame's input; only a successful new step consumes its output.
		var prior: float=sun.frame.get("next_intensity" if advance_sun else "previous_intensity",0.0)
		sun_frame=sun.prepare_frame(view,Vector2i(camera.get_viewport().get_visible_rect().size),prior)
		if sun_frame.has("error"):return reject(sun.error)
	var message: String = _projection.apply(camera,view)
	if not message.is_empty():return reject(message)
	if not sky.apply_view(view,state.escape if escape_sequence else {}):return reject(sky.error)
	if planets!=null and not planets.apply_view(view,state.escape if escape_sequence else {}):return reject(planets.error)
	var scenery_state: Dictionary = _scenery.snapshot()
	if not scenery.apply_state(scenery_state) or not scenery.apply_detail(scenery_state.detail):return reject(scenery.error)
	if scenery.destruction!=null and not scenery.apply_destruction(_scenery,camera.transform,PackedByteArray([255,255,255,255]),Vector4(1,1,1,1),1.0):return reject(scenery.error)
	if npc_deaths!=null:
		if not npc_deaths.apply_world(_world_frame,camera.transform,PackedByteArray([255,255,255,255]),Vector4(1,1,1,1),1.0):return reject(npc_deaths.error)
		for id in geometry.actors:
			geometry.actors[id].visible=state.scene.actors[id].visible and npc_deaths.body_visibility[id]
	if impacts!=null:impacts.commit_world(impact_frame)
	if damage_particles!=null:damage_particles.commit_world(particle_frame)
	if projectiles!=null:projectiles.commit_world(projectile_frame)
	if hyperdrive!=null:hyperdrive.commit_frame(hyperdrive_frame)
	if sun!=null:sun.commit_frame(sun_frame)
	if fade_overlay!=null:
		var alpha: int=_fade.snapshot().alpha_byte
		fade_overlay.color=Color(0,0,0,float(alpha)/255.0);fade_overlay.visible=alpha>0
	# Playback is the last operation: failed staging/presentation emits no audio.
	if audio!=null:audio.commit_frame(audio_frame)
	return true

func prepare_arrival(bindings: RefCounted, catalogues: RefCounted) -> Dictionary:
	error=""
	if status!="arrival_transition_required":reject("Opening has not reached its rescue transition");return {}
	var handoff:=Handoff.new()
	var result:=handoff.prepare(bindings,catalogues,snapshot())
	if result.is_empty():reject(handoff.error)
	return result

func snapshot() -> Dictionary:
	if _timeline==null:return {}
	var state: Dictionary = _timeline.snapshot()
	if _fade!=null:state.fade=_fade.snapshot()
	state.scenery={} if _scenery==null else _scenery.snapshot()
	state.target_inventory={} if _targets==null else _targets.snapshot()
	state.world_frame={} if _world_frame==null else _world_frame.snapshot()
	return state

func clear() -> void:
	for child in get_children():child.free()
	error="";status="idle";radio_resources=null;geometry=null;sky=null;planets=null;sun=null;camera=null
	_timeline=null;_scenery=null;_targets=null;scenery=null;_clock=null;_projection=null;_pauses.clear();_combat_event=-1
	_world_frame=null;npc_deaths=null;projectiles=null;impacts=null;damage_particles=null;interactive=false;_postcombat_event=-1
	hyperdrive=null;fade_overlay=null;_fade=null;escape_sequence=false;audio=null;_audio_revision=0

func fail(message: String) -> bool:
	clear();status="error";error=message
	return false

func reject(message: String) -> bool:
	error=message
	return false

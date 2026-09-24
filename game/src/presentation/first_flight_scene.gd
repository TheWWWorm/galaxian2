extends Node3D
## Shared native scene for the first mining world and its modal briefing.
## Flight time, input, speech and gameplay belong to the session. This renderer
## includes Alioth's animated portal; ordinary portal scenes remain open.
const Portal=preload("res://src/presentation/alioth_portal_geometry.gd")
const SahiPortal=preload("res://src/presentation/sahi_portal_geometry.gd")
const VoidPortal=preload("res://src/presentation/void_portal_geometry.gd")
const ProbeGeometry=preload("res://src/presentation/probe_geometry.gd")
const VoidEnvironment=preload("res://src/presentation/void_environment_geometry.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Geometry=preload("res://src/presentation/opening_geometry.gd")
const Background=preload("res://src/presentation/opening_sky.gd")
const Planets=preload("res://src/presentation/opening_planet_geometry.gd")
const Sun=preload("res://src/presentation/opening_sun_geometry.gd")
const Lighting=preload("res://src/presentation/opening_lighting.gd")
const Scenery=preload("res://src/presentation/scenery_geometry.gd")
const SceneryEffects=preload("res://src/content/scenery_effect_resources.gd")
const Reflection=preload("res://src/presentation/environment_reflection.gd")
const Station=preload("res://src/presentation/station_exterior_geometry.gd")
const Gates=preload("res://src/presentation/gate_geometry.gd")
const FlightProjection=preload("res://src/presentation/flight_camera.gd")
const Dialogue=preload("res://src/presentation/station_dialogue_panel.gd")
const TargetFrame=preload("res://src/presentation/flight_target_frame.gd")
const Reticle=preload("res://src/presentation/flight_aim_reticle.gd")
const ScanAnimation=preload("res://src/presentation/flight_scan_animation.gd")
const TargetProjection=preload("res://src/presentation/target_projection.gd")
const MiningPanel=preload("res://src/presentation/mining_panel.gd")
const NoticePanel=preload("res://src/presentation/flight_notice_panel.gd")
const EncounterGeometry=preload("res://src/presentation/full_hold_encounter_geometry.gd")
const TractorGeometry=preload("res://src/presentation/tractor_geometry.gd")
const DeathEffect=preload("res://src/presentation/npc_death_effect_geometry.gd")
const GameOver=preload("res://src/presentation/game_over_panel.gd")
const DamageParticles=preload("res://src/presentation/opening_damage_geometry.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
const RadioPanel=preload("res://src/presentation/radio_panel.gd")
const NpcMarkers=preload("res://src/presentation/flight_npc_markers.gd")
const WaypointMarker=preload("res://src/presentation/flight_waypoint_marker.gd")
const StationTargetOverlay=preload("res://src/presentation/station_target_overlay.gd")
var error:=""
var void_environment: Node3D
var portal: Node3D
var probe: Node3D
var geometry: Node3D
var sky: Node3D
var planets: Node3D
var sun: Node3D
var scenery: Node3D
var station: Node3D
var gates: Node3D
var camera: Camera3D
var dialogue: Control
var target_frame: Control
var reticle: Control
var scan_animation: Control
var mining_panel: Control
var notice_panel: Control
var _projection: RefCounted
var _last:={}
var _last_drill: RefCounted
var encounter: Node3D
var tractor: Node3D
var _last_tractor: RefCounted
var _last_scenery: RefCounted
var _last_encounter: RefCounted
var player_destruction: Node3D
var game_over: Control
var _last_death: RefCounted
var _last_absolute_ms:=0
var damage_particles: Node3D
var _last_particles: RefCounted
var engine_particles: Node3D
var _last_engines: RefCounted
var _last_gate_animation: RefCounted
var radio: Control
var _radio_resources: RefCounted
var npc_markers: Control
var waypoint_marker: Control
var station_target_overlay: Control
const EFFECT_RESPONSE:={"variant":"unfogged_two_light_cube","diffuse_bias":-1,"normal_bias":0}

func build(library: RefCounted,bindings: RefCounted,visuals: RefCounted,catalogues: RefCounted,flight: RefCounted,activate_camera:=true) -> bool:
	clear()
	if flight==null or flight.get_script()!=Frame:return fail("Prepare the first mining flight before building its scene")
	var state: Dictionary=flight.snapshot()
	if state.is_empty():return fail("Prepare the first mining flight before building its scene")
	_projection=FlightProjection.new()
	var message: String=_projection.configure(bindings.flight_projection,state.campaign_cursor,state.has("void_environment"))
	if not message.is_empty():return fail(message)
	camera=Camera3D.new();camera.current=activate_camera;add_child(camera)
	geometry=Geometry.new();add_child(geometry)
	if not geometry.build_departure(library,visuals,bindings,catalogues,state.player_cache,_player_geometry_state(state),"high",true,flight.equipment_owner()):return fail(geometry.error)
	var pirates: RefCounted=flight.encounter_owner()
	if pirates!=null:
		encounter=EncounterGeometry.new();add_child(encounter)
		if not encounter.build(pirates,library,visuals,bindings):return fail(encounter.error)
	var recovery: RefCounted=flight.tractor_owner()
	if recovery!=null:
		tractor=TractorGeometry.new();add_child(tractor)
		if not tractor.build(recovery,library,visuals,bindings):return fail(tractor.error)
	var death: RefCounted=flight.destruction_owner()
	if death!=null:
		player_destruction=DeathEffect.new();add_child(player_destruction)
		if not player_destruction.build(library,visuals,bindings,death):return fail(player_destruction.error)
	var engines: RefCounted=flight.engine_particle_owner()
	if engines!=null:
		engine_particles=DamageParticles.new();add_child(engine_particles)
		if not engine_particles.build(engines,library,visuals,bindings):return fail(engine_particles.error)
	var particles: RefCounted=flight.damage_particle_owner()
	if particles!=null:
		damage_particles=DamageParticles.new();add_child(damage_particles)
		if not damage_particles.build(particles,library,visuals,bindings):return fail(damage_particles.error)
	var scenery_lighting: Dictionary={}
	if state.has("void_environment"):
		void_environment=VoidEnvironment.new();add_child(void_environment)
		if not void_environment.build(library,visuals,bindings,flight.void_environment_owner(),flight.gate_animation_owner()):return fail(void_environment.error)
		sky=void_environment.sky;gates=void_environment.gates
	else:
		sky=Background.new();add_child(sky)
		if not sky.build_departure(library,visuals,bindings,catalogues,state.player_cache,"high",flight.equipment_owner()):return fail(sky.error)
		planets=Planets.new();add_child(planets)
		if not planets.build_departure(library,visuals,bindings,catalogues,state.player_cache,"high",flight.equipment_owner()):return fail(planets.error)
		sun=Sun.new();add_child(sun)
		if not sun.build_departure(library,visuals,bindings,catalogues,state.player_cache,"high",flight.equipment_owner()):return fail(sun.error)
		var lights:=Lighting.new();add_child(lights)
		if not lights.build_departure(bindings,catalogues,state.player_cache,flight.equipment_owner()):return fail(lights.error)
		scenery_lighting=lights.state
	scenery=Scenery.new();add_child(scenery)
	if not scenery.build(state.scenery,library,visuals,bindings,"high",true):return fail(scenery.error)
	if state.scenery.has("destruction") and not scenery_lighting.is_empty():
		var effects:=SceneryEffects.new()
		if not effects.configure(library,bindings):return fail(effects.error)
		var reflection:=Reflection.new()
		if not reflection.build(library,bindings,catalogues,int(scenery_lighting.system_id),false):return fail(reflection.error)
		if not scenery.prepare_destruction(state.scenery,library,visuals,bindings,effects,scenery_lighting,reflection,EFFECT_RESPONSE):return fail(scenery.error)
	if state.has("station_exterior"):
		station=Station.new();add_child(station)
		if not station.build(library,visuals,bindings,flight.station_owner()):return fail(station.error)
	if state.has("gate_environment"):
		gates=Gates.new();add_child(gates)
		if not gates.build(library,visuals,bindings,catalogues,state.gate_environment):return fail(gates.error)
	if state.has("alioth_portal"):
		portal=Portal.new();add_child(portal)
		if not portal.build(library,visuals,bindings):return fail(portal.error)
	elif state.has("sahi_portal"):
		portal=SahiPortal.new();add_child(portal)
		if not portal.build(library,visuals,bindings,state.player.sahi_context):return fail(portal.error)
	elif state.has("void_portal"):
		portal=VoidPortal.new();add_child(portal)
		var context: Dictionary=state.player.sahi_context.duplicate(true)
		context.current_station_id=state.location.station_id;context.void_station_id=-1
		if state.campaign_cursor==29:context.return_station_id=int(state.void_environment.get("return_station_id",-1))
		if not portal.build(library,visuals,bindings,context):return fail(portal.error)
	if state.has("void_probe_stage")!=state.has("void_probe") or (state.campaign_cursor==29)!=state.has("void_probe"):
		return fail("Probe presentation requires the selected mission29 stage and model together")
	if state.has("void_station_targeting")!=state.has("void_probe"):
		return fail("Probe presentation requires its native station targeting")
	if state.has("void_probe"):
		probe=ProbeGeometry.new();add_child(probe)
		if not probe.build(library,visuals,bindings):return fail(probe.error)
	var overlay:=CanvasLayer.new();overlay.layer=10;add_child(overlay)
	if state.has("player_route"):
		waypoint_marker=WaypointMarker.new();overlay.add_child(waypoint_marker);waypoint_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not waypoint_marker.prepare(library,bindings,visuals,int(state.player.campaign_cursor)):return fail(waypoint_marker.error)
	if state.has("radio"):
		_radio_resources=RadioResources.new()
		if state.radio.has("message"):
			if not _radio_resources.prepare_local_traffic(library,bindings,visuals,int(state.campaign_cursor)):return fail(_radio_resources.error)
		elif not _radio_resources.prepare(library,bindings,visuals,state.campaign_cursor):return fail(_radio_resources.error)
		radio=RadioPanel.new();overlay.add_child(radio);radio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not radio.configure(bindings.base_content_id,bindings.binding_id,library.active_language,_radio_resources.speakers,state.campaign_cursor) or not radio.configure_art(library,bindings,visuals):return fail(radio.error)
	if state.has("npc_scanner"):
		npc_markers=NpcMarkers.new();overlay.add_child(npc_markers);npc_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not npc_markers.prepare(library,bindings,visuals):return fail(npc_markers.error)
	if state.has("mining_targeting") or state.has("void_station_targeting") or state.has("station_targeting"):
		if bindings.mining_targeting.is_empty():return fail("Source scanner filmstrip is unavailable")
		target_frame=TargetFrame.new();overlay.add_child(target_frame);target_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not target_frame.prepare(library,bindings,visuals):return fail(target_frame.error)
		reticle=Reticle.new();overlay.add_child(reticle);reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not reticle.prepare(library,bindings,visuals):return fail(reticle.error)
		scan_animation=ScanAnimation.new();overlay.add_child(scan_animation);scan_animation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not scan_animation.prepare(library,bindings,visuals,bindings.mining_targeting):return fail(scan_animation.error)
	if state.has("station_targeting"):
		if not state.has("station_exterior"):return fail("Ordinary station lock requires its exterior")
		station_target_overlay=StationTargetOverlay.new();overlay.add_child(station_target_overlay);station_target_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not station_target_overlay.prepare(library,bindings,visuals,catalogues,state.station_exterior):return fail(station_target_overlay.error)
	if state.has("mining_session"):
		mining_panel=MiningPanel.new();overlay.add_child(mining_panel);mining_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not mining_panel.configure(library,bindings,visuals):return fail(mining_panel.error)
	if state.has("flight_notices"):
		notice_panel=NoticePanel.new();overlay.add_child(notice_panel);notice_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not notice_panel.configure(library,bindings,visuals):return fail(notice_panel.error)
	dialogue=Dialogue.new();overlay.add_child(dialogue);dialogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not dialogue.configure_flight(library,bindings,visuals,state):return fail(dialogue.error)
	if death!=null and not bindings.game_over_presentation.is_empty():
		game_over=GameOver.new();overlay.add_child(game_over);game_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not game_over.configure(library,bindings,visuals,death):return fail(game_over.error)
	if not present(flight):return fail(error)
	return true

func present(flight: RefCounted, advance_sun:=false, absolute_milliseconds: Variant=0, state: Dictionary={}) -> bool:
	error=""
	if _projection==null or flight==null or flight.get_script()!=Frame:return reject("Build a first-flight scene before presenting it")
	if not absolute_milliseconds is int or absolute_milliseconds<0:return reject("Flight presentation requires a nonnegative absolute clock")
	if state.is_empty():state=flight.snapshot()
	var drill: RefCounted=flight.drill_owner()
	var pirates: RefCounted=flight.encounter_owner()
	var death: RefCounted=flight.destruction_owner()
	var particles: RefCounted=flight.damage_particle_owner()
	var gate_animation: RefCounted=flight.gate_animation_owner()
	var engines: RefCounted=flight.engine_particle_owner()
	var prior: float=0.0 if sun==null else sun.frame.get("next_intensity" if advance_sun else "previous_intensity",0.0)
	var recovery: RefCounted=flight.tractor_owner()
	var scenery_world: RefCounted=flight.scenery_presentation_owner()
	if not _apply(state,prior,drill,pirates,death,absolute_milliseconds,particles,gate_animation,engines,recovery,scenery_world):
		var reason:=error
		if not _last.is_empty() and not _apply(_last,0.0 if sun==null else sun.frame.get("previous_intensity",0.0),_last_drill,_last_encounter,_last_death,_last_absolute_ms,_last_particles,_last_gate_animation,_last_engines,_last_tractor,_last_scenery):reason+="; previous scene: "+error
		return reject(reason)
	_last=state
	_last_drill=drill
	_last_encounter=pirates
	_last_death=death;_last_absolute_ms=absolute_milliseconds
	_last_particles=particles
	_last_engines=engines
	_last_tractor=recovery
	_last_scenery=scenery_world
	_last_gate_animation=gate_animation
	return true

func _apply(state: Dictionary, prior_intensity: float, drill: RefCounted, pirates: RefCounted, death: RefCounted, absolute_milliseconds: int, particles: RefCounted,gate_animation: RefCounted=null,engines: RefCounted=null,recovery: RefCounted=null,scenery_world: RefCounted=null) -> bool:
	if (encounter!=null)!=(pirates!=null):return reject("Pirate presentation support changed within this flight")
	if (player_destruction!=null)!=(death!=null):return reject("Player destruction support changed within this flight")
	if (damage_particles!=null)!=(particles!=null):return reject("Damage particle support changed within this flight")
	if (engine_particles!=null)!=(engines!=null):return reject("Player exhaust support changed within this flight")
	if (tractor!=null)!=(recovery!=null):return reject("Tractor presentation support changed within this flight")
	if (probe!=null)!=state.has("void_probe") or (probe!=null)!=state.has("void_probe_stage"):
		return reject("Probe presentation support changed within this flight")
	if (probe!=null)!=state.has("void_station_targeting"):
		return reject("Probe station targeting support changed within this flight")
	var probe_frame:={}
	var probe_stage: Dictionary={}
	if probe!=null:
		var candidate: Variant=state.void_probe_stage
		var probe_state: Variant=state.void_probe
		if not candidate is Dictionary or not probe_state is Dictionary:return reject("Probe presentation requires its native stage and model state")
		probe_stage=candidate
		for key in ["base_content_id","binding_id"]:
			if probe_stage.get(key)!=state.get(key):return reject("Probe stage belongs to another flight")
		if probe_stage.get("campaign_cursor")!=29 or not probe_stage.get("phase") is int or probe_stage.phase not in [0,1,2] or not probe_stage.get("hud_visible") is bool or not probe_stage.get("target_overlay_visible") is bool or probe_state.get("visible")!=(probe_stage.phase==1):
			return reject("Probe stage lost its source presentation flags")
		probe_frame=probe.prepare_state(probe_state)
		if probe_frame.is_empty():return reject(probe.error)
	var tractor_frame:={}
	if tractor!=null:
		tractor_frame=tractor.prepare_world(recovery)
		if tractor_frame.is_empty():return reject(tractor.error)
	if (void_environment!=null)!=state.has("void_environment"):return reject("Void presentation support changed within this flight")
	if (gates!=null)!=(state.has("gate_environment") or void_environment!=null):return reject("Gate presentation support changed within this flight")
	if state.has("gate_environment") and not gates.apply_state(state.gate_environment):return reject(gates.error)
	var gate_frame:={}
	if state.has("gate_animation"):
		if gates==null or gate_animation==null or gate_animation.snapshot()!=state.gate_animation:return reject("Gate geometry lost its current native clock")
		gate_frame=gates.prepare_animation(gate_animation)
		if gate_frame.is_empty():return reject(gates.error)
	var portal_frame:={}
	if portal!=null:
		portal_frame=portal.prepare_state(state.get("void_portal",state.get("sahi_portal",state.get("alioth_portal",{}))))
		if portal_frame.is_empty():return reject(portal.error)
	var engine_frame:={}
	if engine_particles!=null:
		var sample: Dictionary=state.get("engine_particles",{})
		var world:={"base_content_id":state.get("base_content_id"),"binding_id":state.get("binding_id"),"engine_particles":sample,"elapsed_ms":sample.get("elapsed_ms")}
		engine_frame=engine_particles.prepare_world(engines,world,state.camera_view.pose)
		if engine_frame.is_empty():return reject(engine_particles.error)
	var particle_frame:={}
	if damage_particles!=null:
		particle_frame=damage_particles.prepare_world(particles,state,state.camera_view.pose)
		if particle_frame.is_empty():return reject(damage_particles.error)
	var death_frame:={}
	if death!=null:
		var sample: Dictionary=death.snapshot()
		if sample!=state.get("player_destruction"):return reject("Player effects lost their current destruction owner")
		if sample.phase!="ready" and (sample.physical_pose!=state.player_pose or sample.statistics_pose!=state.player_statistics_pose or sample.rendered_model_basis!=state.player_model_basis):return reject("Player destruction lost its current flight poses")
		death_frame=player_destruction.prepare_effect(death,state.camera_view.pose,PackedByteArray([255,255,255,255]),Vector4.ONE,1.0)
		if death_frame.is_empty():return reject(player_destruction.error)
	var pirate_frame:={}
	if encounter!=null:
		if pirates.snapshot()!=state.get("encounter"):return reject("Pirate geometry lost its current encounter owner")
		pirate_frame=encounter.prepare_world(pirates,state.camera_view.pose,state.ship_detail)
		if pirate_frame.is_empty():return reject(encounter.error)
	if not geometry.apply_state(_player_geometry_state(state)):return reject(geometry.error)
	if (station!=null)!=state.has("station_exterior"):return reject("Station exterior support changed within a flight")
	if station!=null and not station.apply_state(state.station_exterior):return reject(station.error)
	var message: String=_projection.apply(camera,state.camera_view)
	if not message.is_empty():return reject(message)
	if not sky.apply_view(state.camera_view):return reject(sky.error)
	if planets!=null and not planets.apply_view(state.camera_view):return reject(planets.error)
	if not scenery.apply_state(state.scenery) or not scenery.apply_detail(state.scenery.detail):return reject(scenery.error)
	if state.scenery.has("bodies") and not scenery.apply_activity(state.scenery.bodies):return reject(scenery.error)
	if scenery.destruction!=null and not scenery.apply_destruction(scenery_world,camera.transform,PackedByteArray([255,255,255,255]),Vector4.ONE,1.0):return reject(scenery.error)
	var sun_frame: Dictionary={} if sun==null else sun.prepare_frame(state.camera_view,Vector2i(camera.get_viewport().get_visible_rect().size),prior_intensity)
	if sun_frame.has("error"):return reject(sun.error)
	if not dialogue.present(state):return reject(dialogue.error)
	if scan_animation!=null:
		var scan: Dictionary=_scan_sample(state)
		if scan.has("error"):return reject(scan.error)
		if not reticle.present(state.get("player_aim",{})):return reject(reticle.error)
		if not scan_animation.present(scan.sample):return reject(scan_animation.error)
		target_frame.set_active(state.get("player_aim",{}).get("visible",false))
	if station_target_overlay!=null and not station_target_overlay.present(state.get("station_targeting",{}),state.camera_view.pose,state.get("player_aim",{}).get("visible",false)):return reject(station_target_overlay.error)
	if npc_markers!=null and not npc_markers.present(state.get("npc_scanner",{})):return reject(npc_markers.error)
	if waypoint_marker!=null and not waypoint_marker.present(state.get("player_route",{}),state.camera_view.pose,Vector2i(get_viewport().get_visible_rect().size),state.get("player_aim",{}).get("visible",false)):return reject(waypoint_marker.error)
	if mining_panel!=null:
		if drill==null:mining_panel.clear()
		elif not mining_panel.present(drill,int(state.cargo.free_space),true):return reject(mining_panel.error)
	if notice_panel!=null and not notice_panel.present(state.get("flight_notices",{})):return reject(notice_panel.error)
	if state.dialogue.visible or not state.get("alioth_attack",{}).get("hud_visible",true) or not state.get("sahi_stage",{}).get("hud_visible",true) or not probe_stage.get("hud_visible",true) or (death!=null and not state.player_destruction.hud_visible):
		for control in [target_frame,reticle,scan_animation,mining_panel,notice_panel,npc_markers,waypoint_marker,station_target_overlay]:
			if control!=null:control.visible=false
	if not probe_stage.get("target_overlay_visible",true):
		for control in [target_frame,reticle,scan_animation,npc_markers,waypoint_marker,station_target_overlay]:
			if control!=null:control.visible=false
	if game_over!=null and not game_over.present(death,absolute_milliseconds):return reject(game_over.error)
	if portal!=null:portal.commit_state(portal_frame)
	if not gate_frame.is_empty():gates.commit_animation(gate_frame)
	if sun!=null:sun.commit_frame(sun_frame)
	if encounter!=null:encounter.commit_world(pirate_frame)
	if tractor!=null:tractor.commit_world(tractor_frame)
	if radio!=null:
		var transmission: Dictionary=state.get("radio",{}).duplicate(true)
		if state.dialogue.visible:transmission.visible=false
		var speaker:={}
		if transmission.has("message") and transmission.get("visible",false):
			speaker=_radio_resources.local_speaker(transmission)
			if speaker.is_empty():return reject(_radio_resources.error)
		if not radio.present(transmission,speaker):return reject(radio.error)
	if probe!=null and not probe.commit_state(probe_frame):return reject(probe.error)
	if engine_particles!=null:engine_particles.commit_world(engine_frame)
	if damage_particles!=null:damage_particles.commit_world(particle_frame)
	if death!=null:
		player_destruction.commit_effect(death_frame)
		geometry.player.visible=death_frame.body_visible
	if state.has("convoy_capture"):
		if not state.convoy_capture.ship_visible:geometry.player.visible=false
		if state.convoy_capture.input_blocked and geometry.player.engine_glow!=null:geometry.player.engine_glow.visible=false
	return true

func _scan_sample(state: Dictionary) -> Dictionary:
	var mining: Dictionary=state.get("mining_targeting",{})
	if not state.has("void_station_targeting") and not state.has("station_targeting"):return {"sample":mining}
	if state.has("void_station_targeting") and state.has("station_targeting"):return {"error":"Station scan has competing world owners"}
	var station: Variant=state.get("station_targeting",state.get("void_station_targeting",{}))
	if not station is Dictionary or station.get("base_content_id")!=state.get("base_content_id") or station.get("binding_id")!=state.get("binding_id"):
		return {"error":"Station scan belongs to another flight"}
	if state.has("void_station_targeting") and station.get("campaign_cursor")!=29:
		return {"error":"Void station scan lost mission29 ownership"}
	# The objective may advance its campaign cursor during this same ordinary
	# flight; the targeting owner remains bound to the departure and exterior.
	if state.has("station_targeting") and (not station.get("campaign_cursor") is int or station.campaign_cursor<0 or station.campaign_cursor==29):
		return {"error":"Ordinary station scan lost departure ownership"}
	if state.has("station_targeting") and (not state.has("station_exterior") or station.get("station_id")!=state.station_exterior.get("station_id")):
		return {"error":"Ordinary station scan differs from its exterior"}
	for key in ["found_index","aimed_index","locked_index"]:
		if not station.get(key) is int or station[key] not in [-1,0]:return {"error":"Invalid native station scan index"}
	if not station.get("elapsed_ms") is int or station.elapsed_ms<0 or not station.get("duration_ms") is int or station.duration_ms<1 or not station.get("mother_ship_locked") is bool or station.mother_ship_locked!=(station.locked_index==0):
		return {"error":"Invalid native station scan clock"}
	if station.aimed_index<0:
		if station.locked_index>=0:return {"error":"Station lock has no aimed target"}
		return {"sample":mining}
	if station.found_index!=0 or not station.get("station_pixels") is Vector2i or station.get("station_in_view")!=true or station.get("inner_window")!=true:
		return {"error":"Station scan lost its projected source target"}
	var aim: Variant=state.get("player_aim")
	if not aim is Dictionary or not aim.get("point") is Vector3 or not aim.point.is_finite() or not TargetProjection.safe_pixel(aim.point.x) or not TargetProjection.safe_pixel(aim.point.y) or not aim.get("visible") is bool:
		return {"error":"Station scan requires the shared player aim"}
	var frames: int=int(scan_animation.source().frames)
	if frames<1:return {"error":"Station scan has no original animation frames"}
	# The original shared scanner strip advances over the equipped acquisition
	# duration. Void29's completed lock enters the source-hidden probe phase.
	var active: bool=aim.visible and station.locked_index<0 and station.elapsed_ms>0
	var index: int=-1
	if active:
		var progress:=TargetProjection.single(TargetProjection.single(float(station.elapsed_ms))/TargetProjection.single(float(station.duration_ms)))
		index=mini(frames-1,int(TargetProjection.single(float(frames-1)*progress)))
	return {"sample":{"base_content_id":state.base_content_id,"binding_id":state.binding_id,
		"visible":active,"aim_pixels":Vector2i(int(aim.point.x),int(aim.point.y)),"animation_frame":index}}

static func _player_geometry_state(state: Dictionary) -> Dictionary:
	if not state.has("encounter"):return state
	# The pirate assembly has its own retained effect/cargo owners. Supply only
	# the player and its selection to the shared departure body renderer.
	var selected: Dictionary=state.duplicate()
	selected.actors=[];selected.ship_detail=state.ship_detail.duplicate()
	selected.ship_detail.selections={"player":state.ship_detail.selections.player}
	return selected

func set_display_active(value: bool) -> void:
	visible=value
	for child in get_children():
		if child is CanvasLayer:child.visible=value

func set_mobile_layout(value: bool) -> void:
	if dialogue!=null:dialogue.set_mobile_layout(value)
	for control in [target_frame,reticle,scan_animation,mining_panel,notice_panel,game_over,radio,npc_markers,waypoint_marker,station_target_overlay]:
		if control!=null:control.set_mobile_layout(value)
func clear() -> void:
	if is_instance_valid(portal):portal.free()
	portal=null;probe=null
	for child in get_children():child.free()
	error="";geometry=null;sky=null;planets=null;sun=null;scenery=null;camera=null;dialogue=null;_projection=null;_last={}
	target_frame=null;reticle=null;scan_animation=null
	mining_panel=null;_last_drill=null;notice_panel=null
	station=null;gates=null;void_environment=null
	encounter=null;_last_encounter=null
	tractor=null;_last_tractor=null
	_last_scenery=null
	player_destruction=null;game_over=null;_last_death=null;_last_absolute_ms=0
	damage_particles=null;_last_particles=null;_last_gate_animation=null
	engine_particles=null;_last_engines=null
	radio=null;_radio_resources=null;npc_markers=null;waypoint_marker=null;station_target_overlay=null
func fail(message: String) -> bool:clear();error=message;return false
func reject(message: String) -> bool:error=message;return false

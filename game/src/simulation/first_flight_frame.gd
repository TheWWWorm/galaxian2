extends RefCounted
## Live motion, scenery and acknowledged briefing for supported mining entries.
## Mining approach, drilling and cargo share one field and random stream.
## The first-flight session owns application input; collision response remains open.
## Cargo completion selects the return mission after explicit acknowledgement.
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Briefing=preload("res://src/simulation/mining_briefing.gd")
const Pilot=preload("res://src/simulation/pilot_motion.gd")
const Detail=preload("res://src/presentation/ship_detail_group.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
const Aim=preload("res://src/simulation/opening_aim.gd")
const Targeting=preload("res://src/simulation/mining_targeting.gd")
const TargetFrame=preload("res://src/presentation/flight_target_frame.gd")
const ScanAnimation=preload("res://src/presentation/flight_scan_animation.gd")
const Approach=preload("res://src/simulation/mining_approach.gd")
const Mining=preload("res://src/simulation/mining_session.gd")
const Notices=preload("res://src/simulation/flight_notices.gd")
const Objective=preload("res://src/simulation/mining_objective.gd")
const Station=preload("res://src/content/station_exterior_resources.gd")
const StationFlight=preload("res://src/content/station_flight_definitions.gd")
const Autopilot=preload("res://src/simulation/station_autopilot.gd")
const StationReturn=preload("res://src/content/station_return_definitions.gd")
const FullHoldReturn=preload("res://src/content/full_hold_return_definitions.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const MiningFlight=preload("res://src/content/full_hold_flight_definitions.gd")
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const Particles=preload("res://src/simulation/full_hold_particles.gd")
const Death=preload("res://src/simulation/player_destruction.gd")
var error:=""
var _entry:={}
var _pose:=Transform3D.IDENTITY
var _shot:={}
var _random:={}
var _reference:=Vector3.ZERO
var _briefing: RefCounted
var _player: RefCounted
var _scenery: RefCounted
var _camera: RefCounted
var _pilot: RefCounted
var _detail: RefCounted
var _cargo: RefCounted
var _aim: RefCounted
var _targeting: RefCounted
var _approach: RefCounted
var _mining: RefCounted
var _notices: RefCounted
var _objective: RefCounted
var _station: RefCounted
var _autopilot: RefCounted
var _preceding_commands:=Vector2.ZERO
var _return_rules:={}
var _station_contact:=false
var _station_packet:={}
var _model_basis:=Basis.IDENTITY
var _throttle:=1.0
var _viewport:=Vector2i(1280,720)
var _collision_enabled:=false
var _encounter: RefCounted
var _world_elapsed_ms:=0
var _unsupported_boundary:=""
var _death: RefCounted
var _particles: RefCounted
# Action-only forks retain this serial. The audio presenter commits each native
# pass once, after the corresponding scene has been accepted.
var _audio_frame:={}
var _statistics_pose:=Transform3D.IDENTITY
var _camera_follow_enabled:=true
var _game_over_packet:={}

func configure(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, construction: RefCounted, dock_key: String, sensitivity: float, viewport_size:=Vector2i(1280,720), mobile_layout:=false, hard_difficulty:=false, autopilot_key:="A") -> bool:
	error=""
	if construction==null or construction.get_script()!=Construction:return reject("First flight requires a prepared departure owner")
	if MiningFlight.flight(bindings,construction.snapshot().get("campaign_cursor")).is_empty():return reject("This departure has no supported mining world")
	var briefing:=Briefing.new()
	if not briefing.configure(bindings,library,construction,dock_key):return reject(briefing.error)
	var entry: Dictionary=construction.snapshot()
	var cargo:=Cargo.new()
	if not cargo.configure_departure(bindings,catalogues,construction):return reject(cargo.error)
	var player: RefCounted=construction.player_owner()
	var encounter: RefCounted
	if entry.campaign_cursor==4:
		encounter=Encounter.new()
		if not encounter.configure(bindings,catalogues,library,construction,1.0 if hard_difficulty else .5):return reject(encounter.error)
	var death: RefCounted
	if encounter!=null and not bindings.player_destruction.is_empty():
		death=Death.new()
		if not death.configure(bindings,encounter.destruction_resources(),construction):return reject(death.error)
	var particles: RefCounted
	if death!=null and not bindings.full_hold_particles.is_empty():
		particles=Particles.new()
		if not particles.configure(bindings,encounter.snapshot().combat,death,int(entry.unix_seconds)):return reject(particles.error)
	var pilot:=Pilot.new();var detail:=Detail.new()
	var loadout: Dictionary=entry.departure.loadout
	if not pilot.configure_vehicle(bindings,catalogues,bindings.base_content_id,int(loadout.ship_id),[],loadout.equipment_ids,sensitivity):return reject(pilot.error)
	if not player.set_permissions(true,false):return reject(player.error)
	var ships:={"player":int(loadout.ship_id)};var positions:={"player":entry.player_pose.origin}
	if encounter!=null:
		var actor: Dictionary=encounter.snapshot().combat.actors[0]
		ships[0]=int(actor.hull_catalogue_id);positions[0]=actor.position
	if not detail.configure(bindings,ships) or not detail.refresh(positions,Vector3.ZERO,1.0):return reject(detail.error)
	var camera: RefCounted=construction.camera_owner()
	var shot: Dictionary=entry.camera_shot.duplicate(true)
	shot.merge({"mode":"fixed_eye","eye":entry.camera_view.eye,"inherit_target_up":true},true)
	if not camera.update(0,shot,entry,shot):return reject(camera.error)
	var aim: RefCounted;var targeting: RefCounted
	if viewport_size.x<1 or viewport_size.y<1 or viewport_size.x>32767 or viewport_size.y>32767:return reject("Invalid first-flight viewport")
	if not bindings.mining_targeting.is_empty():
		var frame_art:=TargetFrame.source_geometry(library,bindings)
		if frame_art.has("error"):return reject(frame_art.error)
		var animation:=ScanAnimation.source_geometry(library,bindings,bindings.mining_targeting)
		if animation.has("error"):return reject(animation.error)
		aim=Aim.new();targeting=Targeting.new()
		if not aim.configure(bindings) or not aim.advance(entry.player_pose,camera.snapshot().pose,viewport_size) or not aim.sample_feedback(false,0,false):return reject(aim.error)
		if not targeting.configure(bindings,catalogues,construction,TargetFrame.logical_radii(frame_art.quarter_size,mobile_layout),animation.frames):return reject(targeting.error)
		if not targeting.advance(construction.scenery_owner(),entry.player_pose,camera.snapshot().pose,aim.snapshot(),0,false):return reject(targeting.error)
	var approach: RefCounted
	if not bindings.mining_approach.is_empty():
		approach=Approach.new()
		if not approach.configure(bindings,catalogues,construction):return reject(approach.error)
	var mining: RefCounted
	if not bindings.mining_session.is_empty():
		mining=Mining.new()
		if not mining.configure(bindings,catalogues,construction,hard_difficulty):return reject(mining.error)
	var notices: RefCounted
	if not bindings.flight_notices.is_empty():
		notices=Notices.new()
		if not notices.configure(bindings,library,construction,catalogues):return reject(notices.error)
	var objective: RefCounted
	if not bindings.mining_objective.is_empty():
		objective=Objective.new()
		if not objective.configure(bindings,library,construction,autopilot_key,dock_key):return reject(objective.error)
	var station: RefCounted
	if not bindings.station_exterior.is_empty():
		station=Station.new()
		if not station.configure(library,bindings,catalogues,construction):return reject(station.error)
	var autopilot: RefCounted
	if not bindings.station_flight.is_empty():
		if not StationFlight.parameters(bindings.station_flight) or notices==null:return reject("This departure has incomplete station flight declarations")
		autopilot=Autopilot.new()
		if not autopilot.configure(bindings,catalogues,construction,station):return reject(autopilot.error)
		if not pilot.set_response_factor(autopilot.snapshot().response_factor):return reject(pilot.error)
	if not bindings.station_return.is_empty() and (not StationReturn.parameters(bindings.station_return) or autopilot==null or objective==null):return reject("This departure has incomplete station return support")
	var return_rules:=FullHoldReturn.select(bindings,int(entry.campaign_cursor)+1)
	if entry.campaign_cursor==4 and not bindings.full_hold_return.is_empty() and (return_rules.is_empty() or autopilot==null or objective==null):return reject("This departure has incomplete second station return support")
	# Every mutable owner is detached from the station and construction. Failed
	# preparation cannot replace the current good flight.
	_entry=entry;_pose=entry.player_pose;_shot=shot;_random=entry.random_state.duplicate(true)
	_reference=Vector3.ZERO;_briefing=briefing;_player=player;_pilot=pilot;_detail=detail
	_scenery=construction.scenery_owner();_camera=camera;_collision_enabled=false
	_cargo=cargo
	_aim=aim;_targeting=targeting;_viewport=viewport_size
	_approach=approach;_model_basis=Basis.IDENTITY;_throttle=1.0
	_mining=mining;_notices=notices;_objective=objective
	_station=station
	_autopilot=autopilot;_preceding_commands=Vector2.ZERO
	_return_rules=return_rules
	_station_contact=false;_station_packet={};_encounter=encounter;_world_elapsed_ms=0
	_unsupported_boundary=""
	_death=death;_statistics_pose=entry.player_pose;_camera_follow_enabled=true;_game_over_packet={}
	_particles=particles
	_audio_frame={} if death==null else {"serial":0,"player_tail":{},"player_poll":{},"actors":[]}
	return true

func evaluate(milliseconds: Variant, commands:=Vector2.ZERO, throttle:=1.0, paused:=false, viewport_size:=Vector2i.ZERO, drill_command:=Vector2.ZERO) -> RefCounted:
	error=""
	if _briefing==null or not Numbers.integer(milliseconds,0,150) or not commands.is_finite() or absf(commands.x)>1.0 or absf(commands.y)>1.0 or not is_finite(throttle) or throttle<0.0 or throttle>1.0:
		reject("Invalid first-flight frame, command or throttle");return null
	if not drill_command.is_finite() or absf(drill_command.x)>1 or absf(drill_command.y)>1:reject("Invalid first-flight drilling command");return null
	var viewport:=_viewport if viewport_size==Vector2i.ZERO else viewport_size
	if viewport.x<1 or viewport.y<1 or viewport.x>32767 or viewport.y>32767:reject("Invalid first-flight viewport");return null
	var next:=fork_for_frame()
	if paused or not _station_packet.is_empty() or not _game_over_packet.is_empty() or not _unsupported_boundary.is_empty():return next
	if not next._audio_frame.is_empty():next._audio_frame={"serial":int(_audio_frame.serial)+1,"player_tail":{},"player_poll":{},"actors":[]}
	if dialogue_visible():
		# Source modal frames omit ordinary logic, but visit NPC/scenery with
		# zero time. Activation and retained per-pass state can still change.
		if not next._advance_world(0,_reference):reject(next.error);return null
		return next
	# Earlier packs keep their explicit pre-drill support boundary.
	if _mining==null and _approach!=null and _approach.snapshot().phase=="drill_required":return next
	next._viewport=viewport
	if not next._briefing.advance(milliseconds,false,true):reject(next._briefing.error);return null
	var delta_ms: int=next._briefing.simulation_delta_ms()
	var cues: Dictionary=next._briefing.snapshot()
	# The player moves with the preceding angular response. Input is consumed
	# after the entry controller; release may enable it on this very frame.
	# Modal UI owns input as soon as its panel opens. Player/camera logic may
	# already have elapsed, while the later world phase then receives zero.
	var alive: bool=_player.snapshot().vitals.hull>0
	var player_updates: bool=not death_active() or _death.player_updates_enabled()
	var player_tail:=player_updates
	var manual: bool=alive and cues.entry_released and not cues.dialogue.visible
	var active_throttle: float=(throttle if _briefing.snapshot().entry_released else 1.0) if alive else _throttle
	var ordinary_motion:=false
	var visual_response: Vector2=next._pilot.angular_units
	# Station contact uses the cached player position before movement. The later
	# arrival query uses the current station boxes after player/world updates.
	if not _return_rules.is_empty() and _collision_enabled and _player.snapshot().active:
		var length:=Autopilot.single(sqrt(Vectors.dot(_pose.origin,_pose.origin)))
		if not is_finite(length):reject("Station contact exceeds source coordinates");return null
		next._station_contact=length<float(_return_rules.contact_radius)
	if not player_updates:
		pass
	elif _mining!=null and _mining.has_active_drill():
		var operation: Dictionary=next._mining.evaluate(next._scenery,next._cargo,delta_ms,next._random,drill_command,false,false)
		if operation.is_empty():reject(next._mining.error);return null
		next._mining=operation.session;next._scenery=operation.scenery;next._cargo=operation.cargo;next._random=operation.random_state
		if not next._queue_notice_events(next._mining.snapshot().events):reject(next.error);return null
		if operation.release_approach:
			if not next._release_mining_approach():reject(next.error);return null
			ordinary_motion=operation.resume_motion
			player_tail=operation.outcome!="target_unavailable"
			# Automatic completion clears the movement gate within the player
			# update. Its remaining ordinary movement uses retained throttle.
			active_throttle=next._throttle
	elif _approach!=null and _approach.snapshot().phase!="idle":
		var index: int=_approach.snapshot().object_index
		if not next._approach.advance(next._scenery,delta_ms):reject(next._approach.error);return null
		var sample: Dictionary=next._approach.last_guidance_sample()
		if next._autopilot!=null and not sample.is_empty():
			if not next._autopilot.observe_mining_guidance(sample.before,sample.after):reject(next._autopilot.error);return null
		var approach: Dictionary=next._approach.snapshot()
		next._pose=approach.player_pose;next._model_basis=approach.model_basis;next._throttle=approach.throttle
		if approach.camera_update_enabled!=_approach.snapshot().camera_update_enabled:next._camera_follow_enabled=approach.camera_update_enabled
		if not next._scenery.set_spin_enabled(index,approach.spin_enabled):reject(next._scenery.error);return null
		if approach.phase=="idle":
			next._targeting.clear_selection();next._camera_follow_enabled=true;player_tail=false
		if approach.phase=="drill_required" and next._mining!=null:
			if not next._mining.begin(next._approach,next._scenery,next._cargo):reject(next._mining.error);return null
	elif _autopilot!=null and _autopilot.snapshot().active:
		if not next._autopilot.advance(delta_ms,next._pilot.angular_units.x,active_throttle):reject(next._autopilot.error);return null
		var guide: Dictionary=next._autopilot.snapshot()
		next._pose=guide.player_pose;next._model_basis=guide.model_basis;next._throttle=guide.throttle
		next._statistics_pose=next._pose*Transform3D(next._model_basis,Vector3.ZERO)
		if not next._pilot.accept_visual_response(guide.angular_units,float(delta_ms)/1000.0,_preceding_commands):reject(next._pilot.error);return null
		next._preceding_commands=Vector2.ZERO
	else:
		ordinary_motion=true
	if ordinary_motion:
		next._pose=next._pilot.advance(_pose,commands if manual else Vector2.ZERO,active_throttle,float(delta_ms)/1000.0)
		if not next._pilot.error.is_empty():reject(next._pilot.error);return null
		next._statistics_pose=next._pose*Transform3D(_model_basis,Vector3.ZERO)
		next._model_basis=Basis.IDENTITY;next._throttle=active_throttle
		if next._autopilot!=null:
			if not next._autopilot.observe_manual(next._pose,visual_response):reject(next._autopilot.error);return null
			next._model_basis=next._autopilot.snapshot().model_basis
			next._preceding_commands=commands if manual else Vector2.ZERO
	# Aim is retained during player motion, using the preceding camera. Targets
	# are projected only after this frame's scenery and camera have advanced.
	if player_updates:
		if next._aim!=null and not next._aim.advance(next._pose,_camera.snapshot().pose,viewport):reject(next._aim.error);return null
		if next._player.advance_recharge(delta_ms).is_empty() or next._player.advance_repair(delta_ms).is_empty():reject(next._player.error);return null
	if death_active():
		var destruction: Dictionary=next._death.advance(delta_ms,next._pose,next._random,false,next._statistics_pose,player_tail)
		if destruction.is_empty():reject(next._death.error);return null
		next._random=destruction.random_state;next._model_basis=destruction.state.rendered_model_basis
		next._audio_frame.player_tail=destruction.events.duplicate(true)
		if next._particles!=null and not next._particles.apply_player_tail(next._death):reject(next._particles.error);return null
		if next._approach!=null and next._approach.snapshot().phase!="idle":
			if not next._approach.accept_model_basis(next._model_basis):reject(next._approach.error);return null
	# Existing projectile slots contact the current player before advancing.
	# The later mission cue must not move their retained shooter/launch poses.
	if next._encounter!=null:
		var weapon_pass: Dictionary=next._encounter.evaluate_weapons(next._player,next._pose,delta_ms)
		if weapon_pass.is_empty():reject(next._encounter.error);return null
		next._encounter=weapon_pass.encounter;next._player=weapon_pass.player
		if next._player.snapshot().vitals.hull<=0 and next._death==null:
			# Retain the accepted lethal contact. The source player-death scene
			# needs its own owner before this application path can continue.
			next._unsupported_boundary="player_death_required"
			return next
	# Geometry managers run in the early weapon phase, using preceding NPC
	# roots and renderer reference. Scenery lifecycle belongs to the later pass.
	if next._particles!=null and not next._particles.advance(next._pose,delta_ms):reject(next._particles.error);return null
	var positions:={"player":next._pose.origin}
	if next._encounter!=null:
		var actor: Dictionary=next._encounter.snapshot().combat.actors[0]
		positions[0]=actor.get("body_pose",actor.pose).origin
	if not next._detail.update(delta_ms,positions,_reference,1.0,false):reject(next._detail.error);return null
	if next._death!=null and next._player.snapshot().vitals.hull<=0 and not next.death_active():
		if not next._death.start(next._player,next._pose,Vector3.ZERO,next._camera.snapshot().pose,int(next._objective.snapshot().campaign_cursor),next._model_basis,next._statistics_pose):reject(next._death.error);return null
		next._camera_follow_enabled=false
		if not next._player.set_permissions(false,next._player.snapshot().damage_allowed):reject(next._player.error);return null
		# Current commands were prepared before contact in the ordinary native
		# pilot owner. The source's later input gate now omits that preparation.
		if ordinary_motion:
			if not next._pilot.accept_visual_response(visual_response,float(delta_ms)/1000.0):reject(next._pilot.error);return null
			next._preceding_commands=Vector2.ZERO
	if next._particles!=null and not next._particles.apply_player_poll(next._death):reject(next._particles.error);return null
	if next.death_active():next._audio_frame.player_poll=next._death.snapshot().events
	if not next._return_rules.is_empty() and next._player.snapshot().vitals.hull>0:
		if not next._evaluate_station_return():reject(next.error);return null
		if not next._station_packet.is_empty():
			# Station transition exits before mission/camera logic and the later
			# NPC/scenery pass. Preserve current player pools and weapon contacts.
			return next
	var completion_opened:=false
	if next._objective!=null and next._briefing.mission_poll_due():
		if not next._objective.poll(next._cargo,next._scenery,next._player.snapshot().vitals.hull>0):reject(next._objective.error);return null
		completion_opened=next._objective.snapshot().dialogue.visible
	next._briefing.finish_mission_poll(completion_opened)
	if completion_opened:
		if ordinary_motion and next._autopilot!=null:
			# Ordinary movement already cleared its input flags. Its rendered
			# response settles, but opening a modal bypasses late commands.
			if not next._pilot.accept_visual_response(visual_response,float(delta_ms)/1000.0):reject(next._pilot.error);return null
			next._preceding_commands=Vector2.ZERO
		next._briefing.retire_dialogue()
		# Completion bypasses controller/camera/input; the later world phase
		# still visits its owners with zero time after the modal flag is set.
		if not next._advance_world(0,_reference):reject(next.error);return null
		return next
	if cues.entry_released:
		next._shot.mode="follow"
		next._collision_enabled=true
		if not next.death_active() and not next._player.set_permissions(true,true):reject(next._player.error);return null
	if next._encounter!=null:
		var cued: RefCounted=next._encounter.evaluate_cue(next._player,next._pose,int(next._objective.snapshot().campaign_cursor))
		if cued==null:reject(next._encounter.error);return null
		next._encounter=cued
	var scene:={"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"player_pose":next._pose}
	if next._camera_follow_enabled:
		if not next._camera.update(delta_ms,next._shot,scene):reject(next._camera.error);return null
	if next.death_active() and not next._death.sample_camera(next._camera.snapshot().pose,next._camera_follow_enabled):reject(next._death.error);return null
	if next._mining!=null and next._mining.has_active_drill() and next._player.snapshot().vitals.hull>0 and not cues.dialogue.visible:
		if not next._mining.set_command(drill_command):reject(next._mining.error);return null
	if delta_ms>0:next._reference=next._camera.snapshot().eye
	if not next._advance_world(0 if cues.dialogue.visible else delta_ms,_reference):reject(next.error);return null
	if next._targeting!=null:
		var hud_enabled: bool=not next.death_active() and cues.entry_released and not cues.dialogue.visible
		if not next._aim.sample_feedback(false,delta_ms,hud_enabled):reject(next._aim.error);return null
		var approaching: bool=next._approach!=null and next._approach.snapshot().phase!="idle"
		if not next._targeting.advance(next._scenery,next._pose,next._camera.snapshot().pose,next._aim.snapshot(),delta_ms,hud_enabled,approaching):reject(next._targeting.error);return null
		if not next._queue_notice_events(next._targeting.snapshot().events):reject(next.error);return null
	if next._notices!=null:
		if not next._notices.advance(delta_ms,next._mining!=null and next._mining.has_active_drill()):reject(next._notices.error);return null
	return next

func _advance_world(milliseconds: int, preceding_reference: Vector3) -> bool:
	if _encounter!=null:
		var before: Dictionary=_encounter.snapshot().combat
		var actors: Dictionary=_encounter.evaluate_world(_player,_pose,milliseconds,_random)
		if actors.is_empty():return reject(_encounter.error)
		if _particles!=null:
			var after: Dictionary=actors.encounter.snapshot()
			if not _particles.finish_npc_pass(before,after.combat,after.actor_events,milliseconds,1.0):return reject(_particles.error)
		_encounter=actors.encounter;_random=actors.random_state
		if not _audio_frame.is_empty():_audio_frame.actors=_encounter.snapshot().actor_events
	if not _scenery.update(milliseconds,preceding_reference,1.0,null,_random):return reject(_scenery.error)
	_random=_scenery.snapshot().random_state;_world_elapsed_ms+=milliseconds
	return true

func start_mining(paused:=false) -> RefCounted:
	error=""
	if game_over_waiting():reject("A completed game-over screen owns flight actions");return null
	if not _unsupported_boundary.is_empty():reject("This flight requires its player-death transition");return null
	if not _station_packet.is_empty():reject("This flight has reached the station");return null
	if _approach==null or _targeting==null or paused:reject("This active flight has no supported mining approach");return null
	if _autopilot!=null and _autopilot.snapshot().active:reject("Cancel station autopilot before selecting a mining approach");return null
	var cues: Dictionary=_briefing.snapshot()
	if not cues.entry_released or dialogue_visible():reject("Mining requires released flight input");return null
	var next:=fork_for_frame()
	if not next._approach.start(next._scenery,next._targeting,_pose,_model_basis,_throttle):reject(next._approach.error);return null
	if _cargo.snapshot().free_space<=0:
		if _notices==null:reject("The cargo hold has no space for mining");return null
		next=fork_for_frame()
		if not next._notices.enqueue(27):reject(next._notices.error);return null
	elif next._notices!=null and not next._notices.enqueue(11):reject(next._notices.error);return null
	return next

func start_station_autopilot(paused:=false) -> RefCounted:
	error=""
	if game_over_waiting():reject("A completed game-over screen owns flight actions");return null
	if not _unsupported_boundary.is_empty():reject("This flight requires its player-death transition");return null
	if not _station_packet.is_empty():reject("This flight has reached the station");return null
	if _autopilot==null or paused or dialogue_visible() or not _briefing.snapshot().entry_released:reject("Station autopilot requires released flight input");return null
	if _approach!=null and _approach.snapshot().phase!="idle":reject("Finish or cancel mining before selecting the station");return null
	var next:=fork_for_frame()
	if not next._autopilot.start(_pose):reject(next._autopilot.error);return null
	next._throttle=next._autopilot.snapshot().throttle
	if not next._queue_notice_events(next._autopilot.snapshot().events):reject(next.error);return null
	return next

func cancel_station_autopilot(paused:=false) -> RefCounted:
	error=""
	if game_over_waiting():reject("A completed game-over screen owns flight actions");return null
	if not _unsupported_boundary.is_empty():reject("This flight requires its player-death transition");return null
	if not _station_packet.is_empty():reject("This flight has reached the station");return null
	if _autopilot==null or paused or dialogue_visible():reject("No active station autopilot can be cancelled");return null
	var next:=fork_for_frame()
	if not next._autopilot.cancel():reject(next._autopilot.error);return null
	if not next._queue_notice_events(next._autopilot.snapshot().events):reject(next.error);return null
	return next

func cancel_mining(paused:=false) -> RefCounted:
	error=""
	if game_over_waiting():reject("A completed game-over screen owns flight actions");return null
	if not _unsupported_boundary.is_empty():reject("This flight requires its player-death transition");return null
	if _approach==null or paused or dialogue_visible():reject("No active mining approach can be cancelled");return null
	if _mining!=null and _mining.has_active_drill():reject("Use the mining stop action to finish an active drill");return null
	var next:=fork_for_frame()
	if not next._release_mining_approach():reject(next.error);return null
	if next._notices!=null and not next._notices.enqueue(6):reject(next._notices.error);return null
	return next

func stop_mining(paused:=false) -> RefCounted:
	error=""
	if game_over_waiting():reject("A completed game-over screen owns flight actions");return null
	if not _unsupported_boundary.is_empty():reject("This flight requires its player-death transition");return null
	if _mining==null or paused or dialogue_visible():reject("No active drilling input is available");return null
	var next:=fork_for_frame()
	var operation: Dictionary=next._mining.stop(next._scenery,next._cargo,next._random)
	if operation.is_empty():reject(next._mining.error);return null
	next._mining=operation.session;next._scenery=operation.scenery;next._cargo=operation.cargo;next._random=operation.random_state
	if not next._release_mining_approach():reject(next.error);return null
	return next

func _evaluate_station_return() -> bool:
	var volume:=int(_station.point_volume(_pose.origin))
	var selected: bool=_autopilot.snapshot().active
	var objective: Dictionary=_objective.snapshot()
	if objective.campaign_cursor==int(_return_rules.departing_cursor):
		if selected and volume>=0 and not _notices.enqueue(int(_return_rules.restricted_notice)):return reject(_notices.error)
		return true
	if not selected or (volume<0 and not _station_contact):return true
	if objective.campaign_cursor!=int(_return_rules.campaign_cursor) or not objective.cargo_objective_acknowledged or not objective.station_return_required or objective.dialogue.visible:return reject("Station return requires its acknowledged cargo instructions")
	if objective.mission!={"kind":int(_return_rules.mission_kind),"station_id":int(_return_rules.station_id),"reward":0,"bonus":0}:return reject("Station return mission does not match the current station")
	var held: Dictionary=_cargo.snapshot()
	if held.used<int(_return_rules.minimum_delivered_cargo) or _cargo.field_identity()!=_scenery.presentation_identity() or not _cargo.matches_mined_field(_scenery.snapshot()):return reject("Station return cargo disagrees with its mining field")
	var player: Dictionary=_player.snapshot()
	var seed: Dictionary=_entry.departure.loadout
	var cached:=Cache.station_arrival_cache(_return_rules,seed,player)
	if cached.is_empty():return reject("Station arrival cannot preserve the current player pools")
	_station_packet={"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,
		"campaign_cursor":int(_return_rules.campaign_cursor),"source_state":int(_return_rules.source_state),
		"loadout":seed.duplicate(true),"player":player,"player_cache":cached,"cargo":held,
		"progress":objective.progress.duplicate(true),"mission":objective.mission.duplicate(true),
		"source_ship_configuration":_entry.departure.source_ship_configuration,
		"world_elapsed_ms":_briefing.snapshot().world_elapsed_ms,
		"docking":{"station_id":int(_return_rules.station_id),"pre_motion_contact":_station_contact,"post_motion_volume_index":volume,"position":_pose.origin}}
	return true

func prepare_station() -> Dictionary:
	error=""
	if _return_rules.is_empty() or _station_packet.is_empty():reject("Reach the station with the acknowledged return mission before preparing entry");return {}
	return _station_packet.duplicate(true)

func _release_mining_approach() -> bool:
	var index: int=_approach.snapshot().object_index
	if not _approach.cancel():return reject(_approach.error)
	_camera_follow_enabled=true
	if death_active() and not _death.sample_camera(_camera.snapshot().pose,true):return reject(_death.error)
	if not _scenery.set_spin_enabled(index,true):return reject(_scenery.error)
	_targeting.clear_selection()
	return true

func _queue_notice_events(events: Array) -> bool:
	if _notices==null:return true
	for event in events:
		if event.get("kind")=="notification" and not _notices.enqueue(event.get("source_id")):return reject(_notices.error)
	return true

func drill_owner() -> RefCounted:return null if _mining==null else _mining.drill_owner()
func station_owner() -> RefCounted:return null if _station==null else _station.fork_for_frame()
func encounter_owner() -> RefCounted:return null if _encounter==null else _encounter.fork_for_frame()
func destruction_owner() -> RefCounted:return null if _death==null else _death.fork_for_frame()
func damage_particle_owner() -> RefCounted:return null if _particles==null else _particles.fork_for_frame()
func death_active() -> bool:return _death!=null and _death.snapshot().phase!="ready"
func game_over_waiting() -> bool:return death_active() and not _death.player_updates_enabled()

func request_game_over_exit(paused:=false) -> RefCounted:
	error=""
	if paused or not death_active() or not _game_over_packet.is_empty():reject("No active game-over acknowledgement is available");return null
	var next:=fork_for_frame()
	var packet: Dictionary=next._death.request_exit()
	if packet.is_empty():reject(next._death.error);return null
	next._game_over_packet=packet
	return next

func prepare_game_over() -> Dictionary:return _game_over_packet.duplicate(true)

func dialogue_visible() -> bool:
	return (_briefing!=null and _briefing.snapshot().dialogue.visible) or (_objective!=null and _objective.snapshot().dialogue.visible)

func navigate(action: String, paused:=false) -> RefCounted:
	error=""
	if game_over_waiting():reject("A completed game-over screen owns flight actions");return null
	if not _unsupported_boundary.is_empty():reject("This flight requires its player-death transition");return null
	if not _station_packet.is_empty():reject("This flight has reached the station");return null
	if _briefing==null or paused:reject("Mining briefing navigation requires the active flight");return null
	var next:=fork_for_frame()
	if _objective!=null and _objective.snapshot().dialogue.visible:
		if not next._objective.navigate(action):reject(next._objective.error);return null
	elif not next._briefing.navigate(action):reject(next._briefing.error);return null
	return next

func snapshot() -> Dictionary:
	if _briefing==null:return {}
	var state: Dictionary=_briefing.snapshot()
	var held: Dictionary=_cargo.snapshot()
	state.cargo_used=held.used
	state.merge({"world_type":_entry.world_type,"location":_entry.location.duplicate(true),"activated":true,
		"player_pose":_pose,"player":_player.snapshot(),"player_cache":_player.cache_snapshot(),"angular_units":_pilot.angular_units,
		"camera_shot":_shot.duplicate(true),"camera_view":_camera.snapshot(),"scenery":_scenery.snapshot(),
		"ship_detail":_detail.snapshot(),"detail_reference":_reference,"actors":[],"random_state":_random.duplicate(true),
		"cargo":held,
		"scenery_collision_enabled":_collision_enabled,"scenery_collision_supported":false,
		"environment_object":_entry.environment_object.duplicate(true)})
	state.world_phase_elapsed_ms=_world_elapsed_ms
	state.player_statistics_pose=_statistics_pose
	state.camera_follow_enabled=_camera_follow_enabled
	if _death!=null:state.player_destruction=_death.snapshot()
	if _particles!=null:state.damage_particles=_particles.snapshot()
	if not _audio_frame.is_empty():state.flight_audio=_audio_frame.duplicate(true)
	if _encounter!=null:
		state.encounter=_encounter.snapshot();state.actors=state.encounter.combat.actors.duplicate(true)
		state.station_return_supported=not _return_rules.is_empty()
	if _station!=null:
		state.station_exterior=_station.snapshot()
		state.station_volume_index=_station.point_volume(_pose.origin)
	if _autopilot!=null:state.station_autopilot=_autopilot.snapshot()
	if not _return_rules.is_empty():
		state.station_arrival={"pre_motion_contact":_station_contact,"ready":not _station_packet.is_empty()}
		state.boundary="station_transition_required" if not _station_packet.is_empty() else ""
	if not _unsupported_boundary.is_empty():state.boundary=_unsupported_boundary
	if not _game_over_packet.is_empty():state.boundary="game_over_transition_required"
	if _aim!=null:state.player_aim=_aim.snapshot()
	if _targeting!=null:state.mining_targeting=_targeting.snapshot()
	if _approach!=null:
		state.mining_approach=_approach.snapshot()
		state.mining_boundary="drill_required" if _mining==null and state.mining_approach.phase=="drill_required" else ""
	if _approach!=null or _autopilot!=null:state.player_model_basis=_model_basis
	if _mining!=null:state.mining_session=_mining.snapshot()
	if _notices!=null:state.flight_notices=_notices.snapshot()
	if _objective!=null:
		state.mining_objective=_objective.snapshot()
		if state.mining_objective.phase!="collecting":
			for key in ["campaign_cursor","progress","mission","dialogue","phase"]:state[key]=state.mining_objective[key]
		state.cargo_objective_satisfied=state.mining_objective.cargo_objective_satisfied
		state.cargo_objective_acknowledged=state.mining_objective.cargo_objective_acknowledged
		state.station_return_required=state.mining_objective.station_return_required
	return state

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._entry=_entry;copy._pose=_pose;copy._shot=_shot.duplicate(true);copy._random=_random.duplicate(true);copy._reference=_reference
	copy._briefing=_briefing.fork();copy._player=_player.fork_for_frame();copy._scenery=_scenery.fork_for_frame()
	copy._camera=_camera.fork_for_frame();copy._pilot=_pilot.fork_for_frame();copy._detail=_detail.fork_for_frame()
	copy._collision_enabled=_collision_enabled
	copy._cargo=_cargo.fork_for_frame()
	copy._viewport=_viewport
	if _aim!=null:copy._aim=_aim.fork_for_frame()
	if _targeting!=null:copy._targeting=_targeting.fork_for_frame()
	if _approach!=null:copy._approach=_approach.fork_for_frame()
	if _mining!=null:copy._mining=_mining.fork_for_frame()
	if _notices!=null:copy._notices=_notices.fork_for_frame()
	if _objective!=null:copy._objective=_objective.fork_for_frame()
	if _station!=null:copy._station=_station.fork_for_frame()
	if _autopilot!=null:copy._autopilot=_autopilot.fork_for_frame()
	copy._preceding_commands=_preceding_commands
	copy._return_rules=_return_rules;copy._station_contact=_station_contact;copy._station_packet=_station_packet.duplicate(true)
	copy._model_basis=_model_basis;copy._throttle=_throttle
	if _encounter!=null:copy._encounter=_encounter.fork_for_frame()
	copy._world_elapsed_ms=_world_elapsed_ms
	copy._unsupported_boundary=_unsupported_boundary
	copy._statistics_pose=_statistics_pose;copy._camera_follow_enabled=_camera_follow_enabled
	copy._game_over_packet=_game_over_packet.duplicate(true)
	if _death!=null:copy._death=_death.fork_for_frame()
	if _particles!=null:copy._particles=_particles.fork_for_frame()
	copy._audio_frame=_audio_frame.duplicate(true)
	return copy

func clear() -> void:
	error="";_entry={};_pose=Transform3D.IDENTITY;_shot={};_random={};_reference=Vector3.ZERO
	_briefing=null;_player=null;_scenery=null;_camera=null;_pilot=null;_detail=null;_collision_enabled=false
	_cargo=null
	_aim=null;_targeting=null;_viewport=Vector2i(1280,720)
	_approach=null;_model_basis=Basis.IDENTITY;_throttle=1.0
	_mining=null;_notices=null;_objective=null
	_station=null
	_autopilot=null;_preceding_commands=Vector2.ZERO
	_return_rules={};_station_contact=false;_station_packet={}
	_encounter=null;_world_elapsed_ms=0
	_unsupported_boundary=""
	_death=null;_statistics_pose=Transform3D.IDENTITY;_camera_follow_enabled=true;_game_over_packet={}
	_particles=null;_audio_frame={}
func reject(message: String) -> bool:error=message;return false

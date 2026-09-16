extends RefCounted
## Live motion, scenery and entry control for supported early ordinary flights.
## Mining approach, drilling and cargo share one field and random stream.
## The first-flight session owns application input; collision response remains open.
## Cargo completion selects the return mission after explicit acknowledgement.
const Alioth=preload("res://src/simulation/alioth_attack.gd")
const Portal=preload("res://src/simulation/alioth_portal.gd")
const Capture=preload("res://src/simulation/convoy_capture.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Briefing=preload("res://src/simulation/mining_briefing.gd")
const Route=preload("res://src/simulation/npc_route.gd")
const TrainingStory=preload("res://src/content/combat_training_story_definitions.gd")
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
const ContractObjective=preload("res://src/simulation/contract_flight_objective.gd")
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const DeathResources=preload("res://src/content/npc_destruction_resources.gd")
const Station=preload("res://src/content/station_exterior_resources.gd")
const StationFlight=preload("res://src/content/station_flight_definitions.gd")
const Autopilot=preload("res://src/simulation/station_autopilot.gd")
const StationReturn=preload("res://src/content/station_return_definitions.gd")
const FullHoldReturn=preload("res://src/content/full_hold_return_definitions.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const Particles=preload("res://src/simulation/full_hold_particles.gd")
const Death=preload("res://src/simulation/player_destruction.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const LocalRadio=preload("res://src/simulation/local_traffic_radio.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
const Scanner=preload("res://src/simulation/opening_npc_scanner.gd")
const LocalTravel=preload("res://src/simulation/local_travel.gd")
const GateAnimation=preload("res://src/simulation/gate_animation.gd")
const GateTransit=preload("res://src/simulation/gate_transit.gd")
const GateArrival=preload("res://src/content/gate_arrival_definitions.gd")
const SystemNavigation=preload("res://src/simulation/system_navigation.gd")
var error:=""
var _entry:={}
var _pose:=Transform3D.IDENTITY
var _shot:={}
var _random:={}
var _reference:=Vector3.ZERO
var _briefing: RefCounted
var _route: RefCounted
var _navigation:={}
var _world_path:=[]
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
var _equipment: RefCounted
var _radio: RefCounted
var _radio_events:=[]
var _scanner: RefCounted
var _scanner_events:=[]
# Action-only forks retain this serial. The audio presenter commits each native
# pass once, after the corresponding scene has been accepted.
var _audio_frame:={}
var _statistics_pose:=Transform3D.IDENTITY
var _camera_follow_enabled:=true
var _game_over_packet:={}
var _local_travel: RefCounted
var _station_response_flags:={}
var _alioth: RefCounted
var _portal: RefCounted
var _alioth_camera:={}
var _convoy: RefCounted
var _convoy_camera:={}
var _convoy_career: RefCounted
var _story_bindings: RefCounted
var _gate_animation: RefCounted
var _gate_transit: RefCounted
var _gate_destinations:=[]
var _gate_cruise_speed:=0.0

func configure(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, construction: RefCounted, dock_key: String, sensitivity: float, viewport_size:=Vector2i(1280,720), mobile_layout:=false, hard_difficulty:=false, autopilot_key:="A", primary_key:="Space") -> bool:
	error=""
	if construction==null or construction.get_script()!=Construction:return reject("First flight requires a prepared departure owner")
	var entry: Dictionary=construction.snapshot()
	var ordinary_world:=ContractWorld.ordinary_entry(bindings,entry)
	var free_world:=FreeFlight.ordinary_entry(bindings,entry)
	if OrdinaryFlight.for_departure(bindings,entry).is_empty():return reject("This construction has no supported ordinary departure")
	var briefing:=Briefing.new()
	if not briefing.configure(bindings,library,construction,primary_key if construction.snapshot().campaign_cursor==7 else dock_key):return reject(briefing.error)
	var cargo:=Cargo.new()
	if not cargo.configure_departure(bindings,catalogues,construction):return reject(cargo.error)
	var player: RefCounted=construction.player_owner()
	var equipment: RefCounted=construction.equipment_owner()
	if entry.campaign_cursor==7 and equipment!=null and not equipment.prepare_training_completion(bindings,catalogues):return reject(equipment.error)
	var encounter: RefCounted
	var route: RefCounted
	var navigation:={}
	if entry.campaign_cursor==7:
		navigation=TrainingStory.navigation(bindings)
		if not navigation.is_empty():
			route=Route.new()
			if not route.configure_training_player(bindings):return reject(route.error)
		encounter=Encounter.new()
		if not encounter.configure_combat_training(bindings,catalogues,library,player,construction.scenery_owner(),int(entry.departure.progress.rank),1.0 if hard_difficulty else .5):return reject(encounter.error)
	elif entry.campaign_cursor==4:
		encounter=Encounter.new()
		if not encounter.configure(bindings,catalogues,library,construction,1.0 if hard_difficulty else .5):return reject(encounter.error)
	elif entry.campaign_cursor in [10,11,12]:
		encounter=Encounter.new()
		if not encounter.configure_local_traffic(bindings,catalogues,library,construction,1.0 if hard_difficulty else .5):return reject(encounter.error)
	elif ordinary_world:
		encounter=Encounter.new()
		if not encounter.configure_contract_world(bindings,catalogues,library,construction) or not encounter.sample_contract_clock(0,0):return reject(encounter.error)
	elif entry.campaign_cursor==14 and not ordinary_world:
		encounter=Encounter.new()
		if not encounter.configure_convoy(bindings,catalogues,library,construction):return reject(encounter.error)
	elif entry.campaign_cursor==16:
		encounter=Encounter.new()
		if not encounter.configure_alioth(bindings,catalogues,library,construction):return reject(encounter.error)
	elif free_world:
		encounter=Encounter.new()
		if not encounter.configure_free(bindings,catalogues,library,construction) or not encounter.sample_contract_clock(0,0):return reject(encounter.error)
	var alioth: RefCounted;var portal: RefCounted
	if entry.campaign_cursor==16:
		alioth=Alioth.new();portal=Portal.new()
		if not alioth.configure(bindings) or not portal.configure(bindings,entry,library):return reject(alioth.error+portal.error)
	var convoy: RefCounted
	if entry.campaign_cursor==14 and not ordinary_world:
		convoy=Capture.new()
		if not convoy.configure(bindings):return reject(convoy.error)
	var death: RefCounted
	if encounter!=null and not bindings.player_destruction.is_empty():
		death=Death.new()
		var resources: RefCounted=encounter.destruction_resources()
		if entry.campaign_cursor in [13,14,16,18,19]:
			resources=DeathResources.new()
			if not resources.configure(library,bindings):return reject(resources.error)
		if not death.configure(bindings,resources,construction,catalogues):return reject(death.error)
	var particles: RefCounted
	if death!=null and not bindings.full_hold_particles.is_empty():
		particles=Particles.new()
		if not particles.configure(bindings,encounter.snapshot().combat,death,int(entry.unix_seconds)):return reject(particles.error)
	var radio: RefCounted
	if entry.campaign_cursor in [7,16] or (entry.campaign_cursor==14 and not ordinary_world):
		var resources:=RadioResources.new();radio=Radio.new()
		if not resources.prepare(library,bindings,null,int(entry.campaign_cursor)) or not radio.configure(bindings,library,resources.line_counts,int(entry.campaign_cursor)):return reject(resources.error+radio.error)
	elif entry.campaign_cursor in [10,11,12] or ordinary_world or free_world:
		var resources:=RadioResources.new();radio=LocalRadio.new()
		var layout:=resources.prepare_layout(library,bindings)
		if layout==null or not radio.configure(bindings,library,layout,int(entry.campaign_cursor)):return reject(resources.error+radio.error)
	var pilot:=Pilot.new();var detail:=Detail.new()
	var loadout: Dictionary=entry.departure.loadout
	if not pilot.configure_vehicle(bindings,catalogues,bindings.base_content_id,int(loadout.ship_id),[],loadout.equipment_ids,sensitivity):return reject(pilot.error)
	if not player.set_permissions(true,false):return reject(player.error)
	var ships:={"player":int(loadout.ship_id)};var positions:={"player":entry.player_pose.origin};var freighters:=[];var assemblies:={}
	if encounter!=null:
		for actor in encounter.snapshot().combat.actors:
			if actor.get("population_group")=="debris":continue
			ships[actor.actor_id]=int(actor.hull_catalogue_id);positions[actor.actor_id]=actor.position
			if actor.get("population_group") in ["freighter","capital"]:
				freighters.append(actor.actor_id);assemblies[actor.actor_id]=encounter.freighter_assembly(actor.actor_id)
	if not detail.configure(bindings,ships,freighters,assemblies) or not detail.refresh(positions,Vector3.ZERO,1.0):return reject(detail.error)
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
	var scanner: RefCounted
	if equipment!=null:
		var art:=TargetFrame.source_geometry(library,bindings)
		var strip:=ScanAnimation.source_geometry(library,bindings,bindings.opening_staging.npc_scanner)
		if art.has("error") or strip.has("error"):return reject("Training NPC acquisition art is unavailable")
		scanner=Scanner.new()
		if not scanner.configure(bindings,catalogues,TargetFrame.logical_radii(art.quarter_size,mobile_layout),int(strip.frames),equipment,encounter.snapshot().combat if entry.campaign_cursor in [10,11,12,13,14,16,18,19] else {}):return reject(scanner.error)
		if not scanner.advance(encounter.snapshot().combat,entry.player_pose,camera.snapshot().pose,aim.snapshot(),0,false):return reject(scanner.error)
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
	if ordinary_world or free_world:
		objective=ContractObjective.new()
		if not objective.configure(bindings,construction,encounter,library):return reject(objective.error)
	elif not bindings.mining_objective.is_empty():
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
	var local_travel: RefCounted
	var trip:=Travel.journey(bindings.mido_travel,int(entry.campaign_cursor))
	if not trip.is_empty() and entry.location.station_id==int(trip.from_station_id):
		local_travel=LocalTravel.new()
		if aim==null or autopilot==null or not local_travel.configure_flight(bindings,catalogues,equipment,entry):return reject(local_travel.error)
		if not local_travel.sample_frame(camera.snapshot().pose,aim.snapshot(),0,-1,false):return reject(local_travel.error)
	elif ordinary_world or (free_world and Travel.free_local_navigation(bindings.mido_travel,int(entry.campaign_cursor))):
		local_travel=LocalTravel.new()
		if aim==null or autopilot==null or not local_travel.configure_flight(bindings,catalogues,equipment,entry):return reject(local_travel.error)
		if not local_travel.sample_frame(camera.snapshot().pose,aim.snapshot(),0,-1,false):return reject(local_travel.error)
	var return_rules:=OrdinaryFlight.docking(bindings,int(entry.campaign_cursor)+1)
	var gate_animation: RefCounted;var gate_transit: RefCounted;var gate_destinations:=[]
	if free_world and GateArrival.available(bindings):
		gate_animation=GateAnimation.new()
		if not gate_animation.configure(bindings,catalogues,library,int(entry.location.station_id)):return reject(gate_animation.error)
		if gate_animation.snapshot().layout.objects.any(func(gate):return gate.index==1 and gate.interactive):
			var system_navigation:=SystemNavigation.new()
			var career: Dictionary=construction.contract_owner().snapshot()
			if not system_navigation.configure(bindings,catalogues,career.get("lounges",{}).get("system_availability")):return reject(system_navigation.error)
			gate_transit=GateTransit.new()
			if not gate_transit.configure(bindings,gate_animation,system_navigation):return reject(gate_transit.error)
			for world in GateArrival.Worlds.SYSTEMS.values():
				for destination in world.station_ids:
					if not GateArrival.packet(bindings,catalogues,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"from_station_id":entry.location.station_id,"destination_station_id":destination},entry.campaign_cursor).is_empty() and load("res://src/content/free_navigation_definitions.gd").ordinary_departure_at(bindings,entry.campaign_cursor,entry.departure.mission,destination):gate_destinations.append(destination)
			gate_animation=null # Transit now owns the one animation clock.
	if not trip.is_empty():
		return_rules=OrdinaryFlight.docking(bindings,int(entry.campaign_cursor)) if entry.location.station_id==int(trip.station_id) else {}
	elif ordinary_world:return_rules=ContractWorld.docking(bindings,int(entry.location.station_id),entry.campaign_cursor)
	elif free_world:return_rules=FreeFlight.docking(bindings,int(entry.location.station_id),entry.campaign_cursor)
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
	_particles=particles;_equipment=equipment
	_radio=radio;_radio_events=[]
	_scanner=scanner;_scanner_events=[]
	_route=route;_navigation=navigation
	_world_path=entry.scenery.world_initialization.npc_construction.get("contract_encounter",{}).get("path",[]).duplicate(true) if ordinary_world else []
	_audio_frame={} if death==null else {"serial":0,"player_tail":{},"player_poll":{},"actors":[]}
	_local_travel=local_travel
	_station_response_flags=entry.departure.get("station_response_flags",{}).duplicate(true)
	_alioth=alioth;_portal=portal;_alioth_camera={}
	_convoy=convoy;_convoy_camera={}
	_convoy_career=construction.contract_owner() if convoy!=null or alioth!=null else null
	_story_bindings=bindings if free_world or return_rules.get("alioth_return",false) else null
	_gate_animation=gate_animation;_gate_transit=gate_transit;_gate_destinations=gate_destinations
	_gate_cruise_speed=float(bindings.cruise.speed_units_per_millisecond)
	return true

func evaluate(milliseconds: Variant, commands:=Vector2.ZERO, throttle:=1.0, paused:=false, viewport_size:=Vector2i.ZERO, drill_command:=Vector2.ZERO, primary_fire:=false) -> RefCounted:
	error=""
	if _briefing==null or not Numbers.integer(milliseconds,0,150) or not commands.is_finite() or absf(commands.x)>1.0 or absf(commands.y)>1.0 or not is_finite(throttle) or throttle<0.0 or throttle>1.0:
		reject("Invalid first-flight frame, command or throttle");return null
	if not drill_command.is_finite() or absf(drill_command.x)>1 or absf(drill_command.y)>1:reject("Invalid first-flight drilling command");return null
	var viewport:=_viewport if viewport_size==Vector2i.ZERO else viewport_size
	if viewport.x<1 or viewport.y<1 or viewport.x>32767 or viewport.y>32767:reject("Invalid first-flight viewport");return null
	var next:=fork_for_frame()
	if paused or not _station_packet.is_empty() or not _game_over_packet.is_empty() or not _unsupported_boundary.is_empty():return next
	if contract_result_pending() or convoy_arrival_required():return next
	if gate_modal() or not prepare_gate_arrival().is_empty():return next
	if _local_travel!=null and _local_travel.snapshot().phase=="arrival_required" and not death_active():return next
	next._radio_events=[];next._scanner_events=[]
	if next._convoy!=null:next._convoy.clear_frame_cues()
	if next._alioth!=null:next._alioth.clear_frame_cues()
	if not next._audio_frame.is_empty():next._audio_frame={"serial":int(_audio_frame.serial)+1,"player_tail":{},"player_poll":{},"actors":[]}
	if dialogue_visible():
		# Source modal frames omit ordinary logic, but visit NPC/scenery with
		# zero time. Activation and retained per-pass state can still change.
		if not next._advance_world(0,_reference):reject(next.error);return null
		if not next._observe_radio():reject(next.error);return null
		return next
	# Earlier packs keep their explicit pre-drill support boundary.
	if _mining==null and _approach!=null and _approach.snapshot().phase=="drill_required":return next
	next._viewport=viewport
	if not next._briefing.advance(milliseconds,false,true):reject(next._briefing.error);return null
	var delta_ms: int=next._briefing.simulation_delta_ms()
	if _objective is ContractObjective:
		var timing: Dictionary=next._briefing.snapshot()
		if not next._encounter.sample_contract_clock(int(timing.world_elapsed_ms),int(timing.hud_elapsed_ms)):reject(next._encounter.error);return null
	# The world traffic clock precedes player and weapon phases.
	if next._encounter!=null:
		var world_logic: Dictionary=next._encounter.evaluate_world_logic(delta_ms,next._random)
		if world_logic.is_empty():reject(next._encounter.error);return null
		next._encounter=world_logic.encounter;next._random=world_logic.random_state
	var cues: Dictionary=next._briefing.snapshot()
	# The player moves with the preceding angular response. Input is consumed
	# after the entry controller; release may enable it on this very frame.
	# Modal UI owns input as soon as its panel opens. Player/camera logic may
	# already have elapsed, while the later world phase then receives zero.
	var alive: bool=_player.snapshot().vitals.hull>0
	var player_updates: bool=(not death_active() or _death.player_updates_enabled()) and not (_alioth!=null and _alioth.snapshot().player_update_suspended and not death_active())
	var player_tail:=player_updates
	var manual: bool=alive and cues.entry_released and not cues.dialogue.visible and not local_departing() and not cinematic_input_blocked()
	var active_throttle: float=(throttle if _briefing.snapshot().entry_released else 1.0) if alive else _throttle
	if convoy_input_blocked():active_throttle=0.0
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
	elif gate_departing():
		if not next._gate_transit.advance(delta_ms):reject(next._gate_transit.error);return null
		next._pose=next._gate_transit.snapshot().player_pose;next._model_basis=Basis.IDENTITY;next._statistics_pose=next._pose
		next._shot.eye=next._gate_transit.snapshot().camera_position
	elif local_departing():
		# Ordinary launch bypasses steering and moves along the retained root
		# forward axis. HUD acquisition began it at the end of the prior frame.
		var speed:=float(_local_travel.snapshot().launch_speed_per_ms)
		next._pose.origin=Vectors.added(_pose.origin,Vectors.scaled(Vectors.normalized(_pose.basis.z),Autopilot.single(float(delta_ms)*speed)))
		next._statistics_pose=next._pose*Transform3D(_model_basis,Vector3.ZERO)
		if not next._local_travel.advance_launch(delta_ms):reject(next._local_travel.error);return null
	elif _mining!=null and _mining.has_active_drill():
		var operation: Dictionary=next._mining.evaluate(next._scenery,next._cargo,delta_ms,next._random,drill_command,false,false)
		if operation.is_empty():reject(next._mining.error);return null
		next._mining=operation.session;next._scenery=operation.scenery;next._cargo=operation.cargo;next._random=operation.random_state
		if next._equipment!=null and not next._equipment.retain_flight_cargo(next._cargo.snapshot()):reject(next._equipment.error);return null
		if not next._queue_notice_events(next._mining.snapshot().events):reject(next.error);return null
		if operation.release_approach:
			if not next._release_mining_approach():reject(next.error);return null
			ordinary_motion=operation.resume_motion and not convoy_input_blocked()
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
	elif convoy_input_blocked():
		# Source capture gates ordinary flight through the movement flag. The
		# earlier approach/drill branch still runs with its retained command.
		pass
	elif _alioth!=null and _alioth.snapshot().input_blocked:
		next._pose=next._pilot.coast(_pose,_throttle,float(delta_ms)/1000.0)
		if not next._pilot.error.is_empty():reject(next._pilot.error);return null
		next._statistics_pose=next._pose*Transform3D(_model_basis,Vector3.ZERO)
		if next._autopilot!=null and not next._autopilot.observe_scripted_pose(next._pose):reject(next._autopilot.error);return null
	elif gate_coasting():
		var speed: float=_gate_transit.snapshot().speed
		next._pose.origin=Vectors.added(_pose.origin,Vectors.scaled(Vectors.normalized(_pose.basis.z),float(delta_ms)*speed))
		next._statistics_pose=next._pose*Transform3D(_model_basis,Vector3.ZERO)
		if not next._autopilot.observe_scripted_pose(next._pose):reject(next._autopilot.error);return null
	elif _autopilot!=null and _autopilot.snapshot().active:
		if _local_travel!=null and _autopilot.snapshot().target_kind=="planet":
			var destination: Variant=_local_travel.target_position(int(_autopilot.snapshot().station_id))
			if destination==null or not next._autopilot.refresh_planet_position(destination):reject(_local_travel.error+next._autopilot.error);return null
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
	if _gate_transit!=null and not gate_departing():
		if not next._gate_transit.advance(delta_ms):reject(next._gate_transit.error);return null
	elif _gate_animation!=null:
		if not next._gate_animation.advance(delta_ms):reject(next._gate_animation.error);return null
	# Aim is retained during player motion, using the preceding camera. Targets
	# are projected only after this frame's scenery and camera have advanced.
	if player_updates:
		if player_tail and next._route!=null:
			# The source caches this root position at the start of its player pass.
			var arrival: Dictionary=next._route.advance(_pose.origin)
			if arrival.is_empty():reject(next._route.error);return null
			if arrival.arrived and next._notices!=null:
				if not next._notices.enqueue(int(_navigation.progress_notice.source_id)):reject(next._notices.error);return null
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
		var weapon_pass: Dictionary=next._encounter.evaluate_weapons(next._player,next._pose,delta_ms,next._scenery if _equipment!=null else null,next._random)
		if weapon_pass.is_empty():reject(next._encounter.error);return null
		next._encounter=weapon_pass.encounter;next._player=weapon_pass.player
		if weapon_pass.has("scenery"):next._scenery=weapon_pass.scenery
		if weapon_pass.has("random_state"):next._random=weapon_pass.random_state
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
		for actor in next._encounter.snapshot().combat.actors:
			if actor.get("population_group")=="debris":continue
			positions[actor.actor_id]=actor.get("body_pose",actor.pose).origin
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
	if not next.prepare_gate_arrival().is_empty():
		if not next._objective.observe_combat(next._encounter):reject(next._objective.error);return null
		return next
	if next._local_travel!=null and next._local_travel.snapshot().phase=="arrival_required" and not next.death_active():
		if not next._objective.observe_combat(next._encounter):reject(next._objective.error);return null
		return next
	if not next._return_rules.is_empty() and next._player.snapshot().vitals.hull>0:
		if not next._evaluate_station_return():reject(next.error);return null
		if not next._station_packet.is_empty():
			# Station transition exits before mission/camera logic and the later
			# NPC/scenery pass. Preserve current player pools and weapon contacts.
			return next
	var completion_opened:=false
	if next._objective is ContractObjective:
		var radio_active: bool=next._radio!=null and next._radio.snapshot().get("visible",false)
		if not next._objective.poll_contract(next._cargo,next._scenery,next._encounter,next._player.snapshot().vitals.hull>0,radio_active,next._briefing.mission_poll_due()):reject(next._objective.error);return null
		var visit_clock: Dictionary=next._briefing.snapshot()
		if not next._objective.poll_visit(int(visit_clock.world_elapsed_ms),int(visit_clock.hud_elapsed_ms),not next._briefing.mission_poll_due() or next.death_active() or next.contract_result_pending()):reject(next._objective.error);return null
		completion_opened=next.contract_result_pending() or next._objective.snapshot().dialogue.visible
	elif next._objective!=null and next._briefing.mission_poll_due():
		if not next._objective.poll(next._cargo,next._scenery,next._player.snapshot().vitals.hull>0,next._encounter,next._radio):reject(next._objective.error);return null
		completion_opened=next._objective.snapshot().dialogue.visible
	next._briefing.finish_mission_poll(completion_opened)
	if completion_opened:
		if ordinary_motion and next._autopilot!=null:
			# Ordinary movement already cleared its input flags. Its rendered
			# response settles, but opening a modal bypasses late commands.
			if not next._pilot.accept_visual_response(visual_response,float(delta_ms)/1000.0):reject(next._pilot.error);return null
			next._preceding_commands=Vector2.ZERO
		next._briefing.retire_dialogue()
		if next.contract_result_pending():return next
		# Completion bypasses controller/camera/input; the later world phase
		# still visits its owners with zero time after the modal flag is set.
		if not next._advance_world(0,_reference):reject(next.error);return null
		if not next._observe_radio():reject(next.error);return null
		return next
	if next._alioth!=null and not next.death_active() and not cues.dialogue.visible:
		if not next._advance_alioth(delta_ms):reject(next.error);return null
		if ordinary_motion and next.cinematic_input_blocked():
			if not next._pilot.accept_visual_response(visual_response,float(delta_ms)/1000.0):reject(next._pilot.error);return null
			next._preceding_commands=Vector2.ZERO
	if next._convoy!=null and not next.death_active() and not cues.dialogue.visible:
		if not next._advance_convoy(delta_ms):reject(next.error);return null
		if next.convoy_arrival_required():return next
	if cues.entry_released and not next.local_departing() and not next.cinematic_input_blocked():
		next._shot.mode="follow"
		next._collision_enabled=true
		if not next.death_active() and not next._player.set_permissions(true,true):reject(next._player.error);return null
	if next._encounter!=null and _equipment==null:
		var cued: RefCounted=next._encounter.evaluate_cue(next._player,next._pose,int(next._objective.snapshot().campaign_cursor))
		if cued==null:reject(next._encounter.error);return null
		next._encounter=cued
	var scene:={"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"player_pose":next._pose}
	if next.gate_departing():
		# The original translation setter forces a positive fixed-eye refresh.
		# Rebuild the view directly, without advancing a synthetic camera clock.
		if not next._camera.update(0,next._shot,scene,next._shot):reject(next._camera.error);return null
	if next._camera_follow_enabled and not next.cinematic_input_blocked():
		if not next._camera.update(delta_ms,next._shot,scene):reject(next._camera.error);return null
	if next.death_active() and not next._death.sample_camera(next._camera.snapshot().pose,next._camera_follow_enabled):reject(next._death.error);return null
	if next._mining!=null and next._mining.has_active_drill() and next._player.snapshot().vitals.hull>0 and not cues.dialogue.visible and not next.cinematic_input_blocked():
		if not next._mining.set_command(drill_command):reject(next._mining.error);return null
	if next._equipment!=null:
		var fired: Dictionary=next._encounter.evaluate_primary_fire(next._player,next._pose,primary_fire,cues.entry_released and not cues.dialogue.visible and not next.death_active() and not next.local_departing() and not next.cinematic_input_blocked(),next._random)
		if fired.is_empty():reject(next._encounter.error);return null
		next._encounter=fired.encounter;next._random=fired.random_state
	if delta_ms>0:next._reference=next._camera.snapshot().eye
	if not next._advance_world(0 if cues.dialogue.visible else delta_ms,_reference):reject(next.error);return null
	if next._gate_transit!=null and not next.gate_departing() and not next.death_active() and cues.entry_released:
		var guide: Dictionary=next._autopilot.snapshot()
		var target_is_gate: bool=guide.active and guide.target_kind=="gate"
		if not next._gate_transit.observe_contact(next._pose,next._gate_cruise_speed*next._throttle,guide.active,target_is_gate,{"kind":-1,"completed":true}):reject(next._gate_transit.error);return null
		if next.gate_modal() and not next._autopilot.clear_target():reject(next._autopilot.error);return null
	if next._local_travel!=null:
		var selected_planet:=-1
		if next._autopilot.snapshot().active and next._autopilot.snapshot().target_kind=="planet":selected_planet=int(next._autopilot.snapshot().station_id)
		var planet_hud: bool=not next.death_active() and cues.entry_released and not cues.dialogue.visible and not next.local_departing() and not next.cinematic_input_blocked()
		var mining_selected: bool=next._targeting!=null and next._targeting.snapshot().selected_object_index>=0
		if not next._local_travel.sample_frame(next._camera.snapshot().pose,next._aim.snapshot(),delta_ms,selected_planet,planet_hud,mining_selected):reject(next._local_travel.error);return null
		if not local_departing() and next.local_departing():
			if not next._begin_local_departure():reject(next.error);return null
	if next._targeting!=null:
		var hud_enabled: bool=not next.death_active() and cues.entry_released and not cues.dialogue.visible and not next.cinematic_input_blocked()
		var contact:=false
		if next._equipment!=null:
			for weapon in next._encounter.snapshot().primary_contacts:
				for hit in weapon.contacts:
					if hit.target.group=="npc":contact=true
		if not next._aim.sample_feedback(contact,delta_ms,hud_enabled):reject(next._aim.error);return null
		if next._scanner!=null:
			if not next._scanner.advance(next._encounter.snapshot().combat,next._pose,next._camera.snapshot().pose,next._aim.snapshot(),delta_ms,hud_enabled):reject(next._scanner.error);return null
			next._scanner_events=next._scanner.snapshot().events
		var approaching: bool=next._approach!=null and next._approach.snapshot().phase!="idle"
		if not next._targeting.advance(next._scenery,next._pose,next._camera.snapshot().pose,next._aim.snapshot(),delta_ms,hud_enabled,approaching):reject(next._targeting.error);return null
		if not next._queue_notice_events(next._targeting.snapshot().events):reject(next.error);return null
	if next._notices!=null:
		if not next._notices.advance(delta_ms,next._mining!=null and next._mining.has_active_drill()):reject(next._notices.error);return null
	if not next._observe_radio():reject(next.error);return null
	return next

func cinematic_input_blocked() -> bool:
	return convoy_input_blocked() or (_alioth!=null and _alioth.snapshot().input_blocked) or gate_modal() or gate_coasting() or gate_departing()

func _advance_alioth(delta_ms: int) -> bool:
	var actors: Dictionary=_encounter.combat_owner().alioth_actor_context()
	if not _alioth.advance(delta_ms,_radio.snapshot(),actors,_pose,_portal.snapshot().pose,_random):return reject(_alioth.error)
	if not _encounter.apply_alioth_sequence(_alioth,_random) or not _portal.apply_sequence(_alioth):return reject(_encounter.error+_portal.error)
	var state: Dictionary=_alioth.snapshot();var frame: Dictionary=state.frame
	_random=frame.random_state.duplicate(true)
	# The source disables special body/drive actions and late input. It retains
	# existing mining and guidance owners; the ordinary player phase gates them.
	for op in frame.camera_operations:
		match op.action:
			"follow_player":
				_shot={"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"mode":"follow","target":"player"}
				_alioth_camera={};_camera_follow_enabled=true
			"follow_actor":_alioth_camera={"target":"actor","actor_id":int(op.actor_id)}
			"follow_environment":_alioth_camera={"target":"environment","slot":int(op.slot)}
			"set_eye":_alioth_camera.eye=op.position
			"offset":_alioth_camera.eye=Vectors.added(_alioth_camera.eye,op.delta)
	if not _alioth_camera.is_empty():
		_shot={"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"mode":"fixed_eye","target":_alioth_camera.target,"eye":_alioth_camera.eye,"inherit_target_up":true}
		if _alioth_camera.target=="actor":_shot.actor_id=_alioth_camera.actor_id
		else:_shot.slot=_alioth_camera.slot
		var scene:={"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"player_pose":_pose,
			"actors":_encounter.snapshot().combat.actors.map(func(actor):return {"actor_id":actor.actor_id,"pose":actor.body_pose}),
			"environment":{int(_portal.snapshot().slot):_portal.snapshot().pose}}
		if not _camera.update(delta_ms,_shot,scene,_shot):return reject(_camera.error)
	return true

func convoy_input_blocked() -> bool:return _convoy!=null and _convoy.snapshot().input_blocked
func convoy_arrival_required() -> bool:return _convoy!=null and not death_active() and _convoy.snapshot().phase==Capture.Stage.ARRIVAL_REQUIRED

func _advance_convoy(delta_ms: int) -> bool:
	var actors: Array=_encounter.snapshot().combat.actors
	if not _convoy.advance(delta_ms,_radio.snapshot(),_pose,actors[6].body_pose):return reject(_convoy.error)
	if not _encounter.apply_convoy_capture(_convoy):return reject(_encounter.error)
	if _particles!=null and _particles.has_convoy_emp() and not _particles.apply_convoy_capture(_convoy):return reject(_particles.error)
	var state: Dictionary=_convoy.snapshot();var frame: Dictionary=state.frame
	if not state.input_blocked:return true
	if frame.disable_player:
		if not _player.set_permissions(false,_player.snapshot().damage_allowed):return reject(_player.error)
		_throttle=0.0;_preceding_commands=Vector2.ZERO
		_pilot.angular_units=Vector2.ZERO
		_model_basis=(_model_basis*Basis(Vector3.UP,frame.model_rotation_delta.y)).orthonormalized()
		_statistics_pose=_pose*Transform3D(_model_basis,Vector3.ZERO)
		if _approach!=null and _approach.snapshot().phase!="idle" and not _approach.accept_model_basis(_model_basis):return reject(_approach.error)
	for operation in frame.camera_operations:
		if operation.action in ["follow_player","follow_actor"]:
			_convoy_camera={"target":("player" if operation.action=="follow_player" else "actor"),"actor_id":int(operation.get("actor_id",-1)),"offset":Vector3.ZERO}
		elif operation.action=="offset":_convoy_camera.offset+=operation.delta
	if _convoy_camera.is_empty():return reject("Disabled convoy lost its source camera")
	var target: Transform3D=_pose if _convoy_camera.target=="player" else actors[_convoy_camera.actor_id].body_pose
	_shot={"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"mode":"fixed_eye","target":_convoy_camera.target,"eye":target.origin+_convoy_camera.offset,"inherit_target_up":true}
	if _convoy_camera.target=="actor":_shot.actor_id=_convoy_camera.actor_id
	var scene:={"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"player_pose":_pose,"actors":actors.map(func(actor):return {"actor_id":actor.actor_id,"pose":actor.body_pose})}
	if not _camera.update(delta_ms,_shot,scene,_shot):return reject(_camera.error)
	return _objective.observe_combat(_encounter)

func _observe_radio() -> bool:
	if _radio==null:return true
	if _radio is LocalRadio:
		var reaction: Dictionary=_encounter.snapshot().combat.get("provocation",{})
		if reaction.is_empty():return true
		var result: Dictionary=_radio.evaluate(int(_briefing.snapshot().world_elapsed_ms),reaction,_random)
		if result.is_empty():return reject(_radio.error)
		_radio=result.radio;_radio_events=result.events;_random=result.random_state
		return true
	if _alioth!=null:
		_radio_events=_radio.step_alioth_attack(int(_briefing.snapshot().world_elapsed_ms),_encounter.combat_owner().alioth_actor_context())
	elif _convoy!=null:
		var targets:={"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"campaign_cursor":14,"player_targets":_encounter.snapshot().combat.actors.map(func(actor):return {"scenery":false,"current_hull":int(actor.vitals.hull)})}
		_radio_events=_radio.step_convoy(int(_briefing.snapshot().world_elapsed_ms),targets)
	else:_radio_events=_radio.step_combat_training(int(_briefing.snapshot().world_elapsed_ms),_encounter.combat_owner())
	return true if _radio.error.is_empty() else reject(_radio.error)

func _advance_world(milliseconds: int, preceding_reference: Vector3) -> bool:
	if _encounter!=null:
		var before: Dictionary=_encounter.snapshot().combat
		var actors: Dictionary=_encounter.evaluate_world(_player,_pose,milliseconds,_random)
		if actors.is_empty():return reject(_encounter.error)
		if _particles!=null:
			var after: Dictionary=actors.encounter.snapshot()
			if not _particles.finish_npc_pass(before,after.combat,after.actor_events,milliseconds,1.0):return reject(_particles.error)
		_encounter=actors.encounter;_random=actors.random_state
		if not _objective.observe_combat(_encounter):return reject(_objective.error)
		if not _audio_frame.is_empty():_audio_frame.actors=_encounter.snapshot().actor_events
	if not _scenery.update(milliseconds,preceding_reference,1.0,null,_random):return reject(_scenery.error)
	if _portal!=null and not _portal.advance(milliseconds,_camera.snapshot().pose):return reject(_portal.error)
	_random=_scenery.snapshot().random_state;_world_elapsed_ms+=milliseconds
	return true

func start_mining(paused:=false) -> RefCounted:
	error=""
	if cinematic_input_blocked():reject("The capture sequence owns flight controls");return null
	if local_departing():reject("Planet departure owns flight actions");return null
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
	if cinematic_input_blocked():reject("The capture sequence owns flight controls");return null
	if local_departing():reject("Planet departure owns flight actions");return null
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
	if cinematic_input_blocked():reject("The cinematic owns flight controls");return null
	if local_departing():reject("Planet departure owns flight actions");return null
	if game_over_waiting():reject("A completed game-over screen owns flight actions");return null
	if not _unsupported_boundary.is_empty():reject("This flight requires its player-death transition");return null
	if not _station_packet.is_empty():reject("This flight has reached the station");return null
	if _autopilot==null or paused or dialogue_visible():reject("No active station autopilot can be cancelled");return null
	var next:=fork_for_frame()
	if not next._autopilot.cancel():reject(next._autopilot.error);return null
	if not next._queue_notice_events(next._autopilot.snapshot().events):reject(next.error);return null
	return next

func select_planet(station_id: int, paused:=false) -> RefCounted:
	error=""
	if cinematic_input_blocked() or local_departing():reject("Finish the current departure before selecting another planet");return null
	if _local_travel==null or paused or death_active() or dialogue_visible() or not _briefing.snapshot().entry_released:reject("Planet selection requires released local flight input");return null
	if _approach!=null and _approach.snapshot().phase!="idle":reject("Finish or cancel mining before selecting a planet");return null
	var destination: Variant=_local_travel.target_position(station_id)
	if destination==null:reject(_local_travel.error);return null
	var next:=fork_for_frame()
	if not next._autopilot.start_planet(station_id,destination,_pose):reject(next._autopilot.error);return null
	next._throttle=next._autopilot.snapshot().throttle
	return next

func launch_planet(paused:=false) -> RefCounted:
	error=""
	if cinematic_input_blocked():reject("The cinematic owns flight controls");return null
	if _local_travel==null or paused or death_active() or dialogue_visible() or not _briefing.snapshot().entry_released:reject("Planet departure requires released local flight input");return null
	if _approach!=null and _approach.snapshot().phase!="idle":reject("Finish or cancel mining before departing");return null
	var next:=fork_for_frame()
	if not next._local_travel.launch_acquired():reject(next._local_travel.error);return null
	if not next._begin_local_departure():reject(next.error);return null
	return next

func _begin_local_departure() -> bool:
	# Source launch fixes the camera eye, but the next positive camera update
	# still looks at the moving ship. Acquisition runs after this frame's camera;
	# changing the shot must not recompute or move the already accepted view.
	_shot.merge({"mode":"fixed_eye","eye":_camera.snapshot().eye,"inherit_target_up":true},true)
	_collision_enabled=false
	# Reset the installed primary timers, preserving live projectiles and their
	# handles. The source category reset does not destroy bullets already fired.
	if not _encounter.reset_primary_fire_intervals():return reject(_encounter.error)
	return true

func local_departing() -> bool:
	return _local_travel!=null and _local_travel.snapshot().phase!="flight"

func gate_coasting() -> bool:
	return _gate_transit!=null and _gate_transit.snapshot().phase=="flight" and _gate_transit.snapshot().coasting

func gate_modal() -> bool:
	return _gate_transit!=null and _gate_transit.snapshot().phase in ["confirmation","map"]

func gate_departing() -> bool:
	return _gate_transit!=null and _gate_transit.snapshot().phase in ["departing","ready"]

func control_throttle() -> float:return _throttle

func gate_animation_owner() -> RefCounted:
	return _gate_transit.animation() if _gate_transit!=null else (_gate_animation.fork_for_frame() if _gate_animation!=null else null)

func _gate_input_available(paused: bool) -> bool:
	if _gate_transit==null or paused or death_active() or dialogue_visible() or not _briefing.snapshot().entry_released or local_departing():return reject("Gate selection requires released ordinary flight")
	if not _station_packet.is_empty() or not _unsupported_boundary.is_empty():return reject("Finish the current flight transition before selecting the gate")
	if _approach!=null and _approach.snapshot().phase!="idle":return reject("Finish or cancel mining before selecting the gate")
	return true

func start_gate_autopilot(paused:=false) -> RefCounted:
	error=""
	if not _gate_input_available(paused):return null
	if cinematic_input_blocked():reject("The cinematic owns flight controls");return null
	var next:=fork_for_frame()
	if not next._autopilot.start_gate(_pose):reject(next._autopilot.error);return null
	next._throttle=next._autopilot.snapshot().throttle
	return next

func select_gate_destination(station_id: int,paused:=false) -> RefCounted:
	error=""
	if not _gate_input_available(paused):return null
	if cinematic_input_blocked():reject("The cinematic owns flight controls");return null
	if not _gate_destinations.has(station_id):reject("This destination does not yet have a supported ordinary world");return null
	var next:=start_gate_autopilot(paused)
	if next==null:return null
	if not next._gate_transit.set_course(station_id):reject(next._gate_transit.error);return null
	return next

func choose_gate_confirmation(result: int,paused:=false) -> RefCounted:
	error=""
	if not _gate_input_available(paused):return null
	var next:=fork_for_frame()
	if not next._gate_transit.choose_confirmation(result):reject(next._gate_transit.error);return null
	if next.gate_departing() and not next._begin_gate_departure():reject(next.error);return null
	return next

func close_gate_map(accepted: bool,destination: int=-1,paused:=false) -> RefCounted:
	error=""
	if not _gate_input_available(paused) or _gate_transit.snapshot().phase!="map":reject("No gate map awaits a choice");return null
	var next:=fork_for_frame()
	if accepted:
		if not _gate_destinations.has(destination):reject("This destination does not yet have a supported ordinary world");return null
		if not next._gate_transit.set_course(destination):reject(next._gate_transit.error);return null
	if not next._gate_transit.close_map(accepted):reject(next._gate_transit.error);return null
	if accepted:
		if not next._begin_gate_departure():reject(next.error);return null
	else:
		next._pose=next._gate_transit.snapshot().player_pose;next._statistics_pose=next._pose*Transform3D(next._model_basis,Vector3.ZERO)
		next._throttle=next._gate_transit.snapshot().speed/next._gate_cruise_speed
		if not next._autopilot.clear_target():reject(next._autopilot.error);return null
	return next

func _begin_gate_departure() -> bool:
	var gate: Dictionary=_gate_transit.snapshot()
	if not gate_departing() or not gate.has("departure_permissions"):return reject("Gate departure requires its original player permissions")
	if not _autopilot.clear_target() or not _player.set_permissions(true,gate.departure_permissions.damage_allowed):return reject(_autopilot.error+_player.error)
	if gate.reset_primary_fire_intervals and not _encounter.reset_primary_fire_intervals():return reject(_encounter.error)
	_pose=gate.player_pose;_statistics_pose=_pose;_model_basis=Basis.IDENTITY;_throttle=gate.speed/_gate_cruise_speed
	_collision_enabled=gate.departure_permissions.collision_enabled;_camera_follow_enabled=true
	_shot.merge({"mode":"fixed_eye","eye":gate.camera_position,"inherit_target_up":false},true)
	return true

func prepare_gate_arrival() -> Dictionary:
	return {} if _gate_transit==null or death_active() else _gate_transit.arrival_request()

func prepare_local_arrival() -> Dictionary:
	if _local_travel==null or death_active():return {}
	return _local_travel.prepare_arrival()

func construct_local_arrival(bindings: RefCounted, catalogues: RefCounted, environment_seconds: Variant, unix_seconds: Variant, large_display:=true, body_resources: RefCounted=null, effect_resources: RefCounted=null,location_settings: Dictionary={},location_library: RefCounted=null) -> RefCounted:
	error=""
	if prepare_local_arrival().is_empty() or _objective==null or _equipment==null:reject("Complete the surviving local flight before constructing arrival");return null
	return _construct_arrival(bindings,catalogues,prepare_local_arrival(),environment_seconds,unix_seconds,large_display,body_resources,effect_resources,location_settings,location_library,false)

func construct_gate_arrival(bindings: RefCounted,catalogues: RefCounted,environment_seconds: Variant,unix_seconds: Variant,large_display:=true,body_resources: RefCounted=null,effect_resources: RefCounted=null,location_settings: Dictionary={},location_library: RefCounted=null) -> RefCounted:
	error=""
	if not _objective is ContractObjective or _equipment==null:reject("Complete the surviving gate flight before constructing arrival");return null
	var packet:=GateArrival.packet(bindings,catalogues,prepare_gate_arrival(),int(_objective.snapshot().campaign_cursor))
	if packet.is_empty():reject("Complete the surviving gate flight before constructing arrival");return null
	return _construct_arrival(bindings,catalogues,packet,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,location_settings,location_library,true)

func _construct_arrival(bindings: RefCounted,catalogues: RefCounted,packet: Dictionary,environment_seconds: Variant,unix_seconds: Variant,large_display: bool,body_resources: RefCounted,effect_resources: RefCounted,location_settings: Dictionary,location_library: RefCounted,gate: bool) -> RefCounted:
	var result:=Construction.new()
	var objective: Dictionary=_objective.snapshot()
	objective.station_response_flags=station_response_flags()
	var contracts: RefCounted
	if _objective is ContractObjective:
		contracts=_objective.retained_for_arrival(_encounter)
		if contracts==null:reject(_objective.error);return null
		if not location_settings.is_empty() and not contracts.select_location(bindings,catalogues,location_library,int(packet.station_id),location_settings,_random,unix_seconds):reject(contracts.error);return null
		objective.progress=contracts.snapshot().progress
	var prepared: bool=result.prepare_gate_arrival(bindings,catalogues,_gate_transit,_player,_equipment,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,objective,contracts) if gate else result.prepare_local_arrival(bindings,catalogues,_local_travel,_player,_equipment,environment_seconds,unix_seconds,large_display,body_resources,effect_resources,objective,contracts)
	if not prepared:reject(result.error);return null
	return result

func station_response_flags() -> Dictionary:
	var flags:=_station_response_flags.duplicate()
	if _encounter!=null and (_entry.campaign_cursor in [10,11,12] or _objective is ContractObjective):
		var reaction: Dictionary=_encounter.snapshot().combat.get("provocation",{})
		if not reaction.is_empty():flags[int(reaction.station_id)]=bool(reaction.station_response_flag)
	return flags

func local_travel_owner() -> RefCounted:return null if _local_travel==null else _local_travel.fork()

func cancel_mining(paused:=false) -> RefCounted:
	error=""
	if cinematic_input_blocked():reject("Capture owns flight actions");return null
	if local_departing():reject("Planet departure owns flight actions");return null
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
	if cinematic_input_blocked():reject("Capture owns flight actions");return null
	if local_departing():reject("Planet departure owns flight actions");return null
	if game_over_waiting():reject("A completed game-over screen owns flight actions");return null
	if not _unsupported_boundary.is_empty():reject("This flight requires its player-death transition");return null
	if _mining==null or paused or dialogue_visible():reject("No active drilling input is available");return null
	var next:=fork_for_frame()
	var operation: Dictionary=next._mining.stop(next._scenery,next._cargo,next._random)
	if operation.is_empty():reject(next._mining.error);return null
	next._mining=operation.session;next._scenery=operation.scenery;next._cargo=operation.cargo;next._random=operation.random_state
	if next._equipment!=null and not next._equipment.retain_flight_cargo(next._cargo.snapshot()):reject(next._equipment.error);return null
	if not next._release_mining_approach():reject(next.error);return null
	return next

func _evaluate_station_return() -> bool:
	var volume:=int(_station.point_volume(_pose.origin))
	var selected: bool=_autopilot.snapshot().active and _autopilot.snapshot().target_kind=="station"
	var objective: Dictionary=_objective.snapshot()
	var local_visit: bool=_return_rules.get("local_visit",false)
	var contract_station: bool=_return_rules.get("contract_station",false)
	if not local_visit and objective.campaign_cursor==int(_return_rules.departing_cursor):
		if selected and volume>=0 and not _notices.enqueue(int(_return_rules.restricted_notice)):return reject(_notices.error)
		return true
	if not selected or (volume<0 and not _station_contact):return true
	if objective.campaign_cursor!=int(_return_rules.campaign_cursor) or objective.dialogue.visible:return reject("Station arrival changed its current mission")
	if not local_visit and (not objective.get("combat_objective_acknowledged",objective.cargo_objective_acknowledged) or not objective.station_return_required):return reject("Station return requires its acknowledged cargo instructions")
	var contracts: RefCounted
	if contract_station:
		if not _objective is ContractObjective or contract_result_pending():return reject("The station requires the retained contract flight")
		contracts=_objective.retained_for_arrival(_encounter)
		if contracts==null:return reject(_objective.error)
		objective.progress=contracts.snapshot().progress
	elif _return_rules.get("alioth_return",false):
		if _convoy_career==null or _story_bindings==null:return reject("Alioth docking lost its retained career")
		contracts=_convoy_career.fork()
		if not contracts.retain_alioth_return_progress(_story_bindings,objective.progress):return reject(contracts.error)
		if objective.mission!={"kind":int(_return_rules.mission_kind),"station_id":int(_return_rules.station_id),"reward":0,"bonus":0,"source_parameter":0}:return reject("Alioth docking lost its acknowledged return mission")
	else:
		var mission:={"kind":int(_return_rules.mission_kind),"station_id":int(_return_rules.station_id),"reward":0,"bonus":0}
		if local_visit or _return_rules.get("alioth_return",false):mission.source_parameter=0
		if objective.mission!=mission:return reject("Station return mission does not match the current station")
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
	if _equipment!=null:_station_packet.equipment=_equipment.snapshot()
	if local_visit:_station_packet.station_response_flags=station_response_flags()
	if contracts!=null:_station_packet.contracts=contracts.snapshot()
	if _return_rules.get("alioth_return",false):_convoy_career=contracts
	return true

func prepare_station() -> Dictionary:
	error=""
	if _return_rules.is_empty() or _station_packet.is_empty():reject("Reach the station with the acknowledged return mission before preparing entry");return {}
	return _station_packet.duplicate(true)

func prepare_convoy_station() -> Dictionary:
	error=""
	if not convoy_arrival_required() or _convoy_career==null or _equipment==null or _objective==null:return _reject_convoy_station("Finish the surviving capture before entering Alioth")
	var held: Dictionary=_cargo.snapshot()
	if not _cargo.matches_mined_field(_scenery.snapshot()) or held!=_equipment.snapshot().cargo:return _reject_convoy_station("The capture lost its actual mining cargo")
	var state:=snapshot()
	return {"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"campaign_cursor":14,
		"arrival":_convoy.snapshot().arrival.duplicate(true),"loadout":_equipment.snapshot().loadout,
		"equipment":_equipment.snapshot(),"cargo":held,"player":_player.snapshot(),
		"player_cache":_player.cache_snapshot(),"progress":state.progress.duplicate(true),
		"contracts":_convoy_career.snapshot(),"world_elapsed_ms":state.world_elapsed_ms,
		"source_ship_configuration":_entry.departure.source_ship_configuration}

func _reject_convoy_station(message: String) -> Dictionary:
	reject(message);return {}

func convoy_career_owner() -> RefCounted:
	return null if _convoy_career==null else _convoy_career.fork()

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

func equipment_owner() -> RefCounted:return null if _equipment==null else _equipment.fork()

func contract_owner() -> RefCounted:
	if not _objective is ContractObjective:return null
	return _objective.retained_for_arrival(_encounter) if not _station_packet.is_empty() else _objective.contract_owner()

func contract_result_pending() -> bool:
	return _objective is ContractObjective and not _objective.snapshot().contract_result.is_empty()

func acknowledge_contract_result(serial: int,paused:=false) -> RefCounted:
	error=""
	if paused or not contract_result_pending() or not _station_packet.is_empty():reject("No active contract result awaits acknowledgement");return null
	var next:=fork_for_frame()
	var result: Dictionary=next._objective.acknowledge(next._encounter,serial)
	if result.is_empty():reject(next._objective.error);return null
	if result.clear_player_control:
		next._route=null
	if result.clear_world_path:
		# Contract routes are copied into each actor at construction. Clearing
		# the shared path does not destroy their retained individual routes.
		next._world_path=[]
	return next

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
	return contract_result_pending() or (_briefing!=null and _briefing.snapshot().dialogue.visible) or (_objective!=null and _objective.snapshot().dialogue.visible)

func navigate(action: String, paused:=false) -> RefCounted:
	error=""
	if game_over_waiting():reject("A completed game-over screen owns flight actions");return null
	if not _unsupported_boundary.is_empty():reject("This flight requires its player-death transition");return null
	if not _station_packet.is_empty():reject("This flight has reached the station");return null
	if _briefing==null or paused:reject("Mining briefing navigation requires the active flight");return null
	var next:=fork_for_frame()
	if _objective!=null and _objective.snapshot().dialogue.visible:
		if next._objective is ContractObjective:
			if not next._objective.navigate(action,next._encounter):reject(next._objective.error);return null
			var state: Dictionary=next._objective.snapshot()
			if state.campaign_cursor!=_objective.snapshot().campaign_cursor:
				if next._local_travel==null or not next._local_travel.rebase_campaign(_story_bindings,state.campaign_cursor,state.mission):reject("Campaign navigation: "+str(next._local_travel.error if next._local_travel!=null else "missing travel"));return null
				var guidance: Dictionary=next._autopilot.snapshot()
				if guidance.active and guidance.target_kind=="planet" and not next._local_travel.supports_destination(guidance.station_id):
					if not next._autopilot.clear_target():reject(next._autopilot.error);return null
				next._return_rules=FreeFlight.docking(_story_bindings,int(_entry.location.station_id),state.campaign_cursor)
		elif not next._objective.navigate(action):reject(next._objective.error);return null
		if _entry.campaign_cursor==7 and _equipment!=null and next._objective.snapshot().combat_objective_acknowledged and not _objective.snapshot().combat_objective_acknowledged:
			if not next._equipment.complete_training(next._cargo.snapshot()):reject(next._equipment.error);return null
			if not _navigation.is_empty() and _navigation.clear_on_completion_acknowledgement:next._route=null
		if _alioth!=null and _story_bindings!=null and next._objective.snapshot().combat_objective_acknowledged and not _objective.snapshot().combat_objective_acknowledged:
			if _convoy_career==null:reject("Alioth completion lost its retained career");return null
			next._convoy_career=_convoy_career.fork()
			if not next._convoy_career.advance_alioth_story(_story_bindings,_objective.snapshot().progress,int(next._objective.snapshot().campaign_cursor)):reject(next._convoy_career.error);return null
			if next._convoy_career.snapshot().progress!=next._objective.snapshot().progress:reject("Alioth completion changed the earned career");return null
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
		"cargo":held,"arrival_from_station_id":int(_entry.departure.get("from_station_id",-1)),
		"scenery_collision_enabled":_collision_enabled,"scenery_collision_supported":false,
		"environment_object":_entry.environment_object.duplicate(true)})
	state.world_phase_elapsed_ms=_world_elapsed_ms
	state.player_statistics_pose=_statistics_pose
	state.camera_follow_enabled=_camera_follow_enabled
	if _entry.has("gate_environment"):state.gate_environment=_entry.gate_environment.duplicate(true)
	var gate_animation: RefCounted=gate_animation_owner()
	if gate_animation!=null:state.gate_animation=gate_animation.snapshot()
	if _gate_transit!=null:
		state.gate_transit=_gate_transit.snapshot();state.gate_destinations=_gate_destinations.duplicate()
		if gate_modal():state.boundary="gate_confirmation_required" if state.gate_transit.phase=="confirmation" else "gate_map_required"
		elif not prepare_gate_arrival().is_empty():state.boundary="gate_arrival_transition_required"
	if _alioth!=null:
		state.alioth_attack=_alioth.snapshot();state.alioth_portal=_portal.snapshot();state.alioth_camera=_alioth_camera.duplicate(true)
	if _convoy!=null:
		state.convoy_capture=_convoy.snapshot()
		state.convoy_camera=_convoy_camera.duplicate(true)
		if convoy_arrival_required():state.boundary="convoy_arrival_transition_required"
	if _death!=null:state.player_destruction=_death.snapshot()
	if _particles!=null:state.damage_particles=_particles.snapshot()
	if _radio!=null:state.radio=_radio.snapshot();state.radio_events=_radio_events.duplicate(true)
	if _scanner!=null:state.npc_scanner=_scanner.snapshot();state.npc_scanner_events=_scanner_events.duplicate(true)
	if _local_travel!=null:
		state.local_travel=_local_travel.snapshot()
		if state.local_travel.phase=="arrival_required" and not death_active():state.boundary="local_arrival_transition_required"
	if not _navigation.is_empty():state.player_route={} if _route==null else _route.snapshot()
	if _objective is ContractObjective:state.world_path=_world_path.duplicate(true)
	if not _audio_frame.is_empty():state.flight_audio=_audio_frame.duplicate(true)
	if _encounter!=null:
		state.encounter=_encounter.snapshot();state.actors=state.encounter.combat.actors.duplicate(true)
		state.station_return_supported=not _return_rules.is_empty()
	if _entry.campaign_cursor in [10,11,12] or _objective is ContractObjective:state.station_response_flags=station_response_flags()
	if _station!=null:
		state.station_exterior=_station.snapshot()
		state.station_volume_index=_station.point_volume(_pose.origin)
	if _autopilot!=null:state.station_autopilot=_autopilot.snapshot()
	if not _return_rules.is_empty():
		state.station_arrival={"pre_motion_contact":_station_contact,"ready":not _station_packet.is_empty()}
		if not _station_packet.is_empty():state.boundary="station_transition_required"
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
		if _objective is ContractObjective:
			state.contracts=state.mining_objective.contracts;state.contract_result=state.mining_objective.contract_result
			state.campaign_cursor=state.mining_objective.campaign_cursor;state.mission=state.mining_objective.mission.duplicate(true)
		if _equipment!=null:
			state.progress=state.mining_objective.progress
			state.combat_objective_satisfied=state.mining_objective.combat_objective_satisfied
			state.combat_objective_acknowledged=state.mining_objective.combat_objective_acknowledged
			state.equipment=_equipment.snapshot()
		if state.mining_objective.phase!="collecting":
			for key in ["campaign_cursor","progress","mission","dialogue","phase"]:state[key]=state.mining_objective[key]
		state.cargo_objective_satisfied=state.mining_objective.cargo_objective_satisfied
		state.cargo_objective_acknowledged=state.mining_objective.cargo_objective_acknowledged
		state.station_return_required=state.mining_objective.station_return_required
	return state

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._entry=_entry;copy._pose=_pose;copy._shot=_shot.duplicate(true);copy._random=_random.duplicate(true);copy._reference=_reference
	copy._station_response_flags=_station_response_flags.duplicate(true)
	if _alioth!=null:copy._alioth=_alioth.fork_for_frame();copy._portal=_portal.fork_for_frame()
	copy._alioth_camera=_alioth_camera.duplicate(true)
	if _convoy!=null:copy._convoy=_convoy.fork_for_frame()
	copy._convoy_camera=_convoy_camera.duplicate(true)
	copy._convoy_career=_convoy_career # immutable departure owner; public access forks it
	copy._story_bindings=_story_bindings
	if _gate_animation!=null:copy._gate_animation=_gate_animation.fork_for_frame()
	if _gate_transit!=null:copy._gate_transit=_gate_transit.fork_for_frame()
	copy._gate_destinations=_gate_destinations.duplicate();copy._gate_cruise_speed=_gate_cruise_speed
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
	if _equipment!=null:copy._equipment=_equipment.fork()
	if _radio!=null:copy._radio=_radio.fork_for_frame()
	copy._radio_events=_radio_events.duplicate(true)
	if _scanner!=null:copy._scanner=_scanner.fork_for_frame()
	copy._scanner_events=_scanner_events.duplicate(true)
	if _route!=null:copy._route=_route.fork_for_frame()
	copy._navigation=_navigation
	copy._world_path=_world_path.duplicate(true)
	copy._audio_frame=_audio_frame.duplicate(true)
	if _local_travel!=null:copy._local_travel=_local_travel.fork()
	return copy

func clear() -> void:
	error="";_entry={};_pose=Transform3D.IDENTITY;_shot={};_random={};_reference=Vector3.ZERO
	_alioth=null;_portal=null;_alioth_camera={}
	_convoy=null;_convoy_camera={};_convoy_career=null
	_story_bindings=null
	_gate_animation=null;_gate_transit=null;_gate_destinations=[];_gate_cruise_speed=0.0
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
	_particles=null;_audio_frame={};_equipment=null;_radio=null;_radio_events=[]
	_route=null;_navigation={};_world_path=[]
	_scanner=null;_scanner_events=[]
	_local_travel=null;_station_response_flags={}
func reject(message: String) -> bool:error=message;return false

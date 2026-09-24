extends SceneTree
## Source player9/world11 effects for the earned first mining departure. The
## first mining world has neither player smoke/fire nor an NPC particle owner.
const Particles=preload("res://src/simulation/full_hold_particles.gd")
const Smoke=preload("res://src/simulation/opening_damage_particles.gd")
const Death=preload("res://src/simulation/player_destruction.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const ROOT=Transform3D(Basis.IDENTITY,Vector3(100,-50,70))
const CAMERA=Transform3D(Basis.IDENTITY,Vector3(0,600,-1338))
const SEED_SECONDS=1789100000
const INITIAL_RNG={"state":25214903917}
var checks:=0
var failures:=0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("First mining particles: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new();var bodies:=Bodies.new()
	if not library.open(args[0]) or not library.select_language("gb") or not bindings.open(args[1],library.manifest) or not catalogues.open(library) or not bodies.configure(library,bindings):
		check(false,library.error+bindings.error+catalogues.error+bodies.error);return
	check(bindings.source_architecture=="x86_64" and not bindings.full_hold_particles.is_empty(),"First mining sprite test requires verified Mac presets")
	# The source-accepted Mido destination has no actors. Its ordinary pass still
	# commits an empty update; only the cursor-two mining world has no NPC pass.
	var trip: Dictionary=Travel.journey(bindings.mido_travel,10)
	var quiet_combat:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":10,"provocation":{"station_id":int(trip.get("station_id",-1))},"actors":[]}
	check(not trip.is_empty() and OrdinaryFlight.combat_population(bindings,quiet_combat),"Mido destination lost its source-accepted empty combat population")
	var quiet:=Smoke.new()
	check(quiet.configure_local_traffic(bindings,quiet_combat,SEED_SECONDS),quiet.error)
	var quiet_before: Dictionary=quiet.snapshot()
	check(quiet.finish_npc_pass(quiet_combat,quiet_combat,[],1,1.0) and quiet.snapshot()==quiet_before,"Empty ordinary NPC pass was rejected or changed particle state")
	var empty:=Smoke.new()
	check(empty.configure_first_mining(bindings,SEED_SECONDS),empty.error)
	check(empty.snapshot().owners.is_empty() and empty.snapshot().births.is_empty(),"First mining invented smoke/fire owners")
	check(empty.advance(ROOT,11) and empty.snapshot().elapsed_ms==11 and empty.snapshot().manager_ms==0,"Empty smoke/fire managers lost their source clock")
	var empty_before: Dictionary=empty.snapshot()
	check(not empty.finish_npc_pass({}, {}, [],1,1.0) and empty.snapshot()==empty_before,"First mining accepted an NPC smoke/fire pass")
	var fork: RefCounted=empty.fork_for_frame()
	check(fork.advance(ROOT,9) and empty.snapshot()==empty_before and fork.snapshot().elapsed_ms==20,"Empty manager fork shared a clock")
	if failures:return
	var initial_player:=Player.new();var handoff:=Handoff.new()
	if not initial_player.configure(bindings,catalogues):check(false,initial_player.error);return
	var packet: Dictionary=handoff.prepare(bindings,catalogues,Fixture.completed(bindings,initial_player,3))
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,catalogues,library,packet,[1,1,1],SEED_SECONDS):check(false,arrival.error);return
	for tick in 500:
		var next: RefCounted=arrival.evaluate(100)
		if next==null:check(false,arrival.error);return
		arrival=next
		if not arrival.snapshot().boundary.is_empty():break
	check(not arrival.snapshot().boundary.is_empty(),"Rescue fixture did not earn first station")
	if failures:return
	var station:=Station.new()
	if not station.configure(bindings,catalogues,library,arrival.prepare_station()):check(false,station.error);return
	for page in 19:station.acknowledge()
	var construction:=Construction.new()
	if not construction.prepare(bindings,catalogues,station.prepare_departure(bindings,catalogues),4096,SEED_SECONDS,true,bodies):check(false,construction.error);return
	var resources:=Resources.new()
	if not resources.configure(library,bindings):check(false,resources.error);return
	var death:=Death.new()
	if not death.configure(bindings,resources,construction,catalogues):check(false,death.error);return
	check(death.snapshot().phase=="ready" and death.snapshot().departure_cursor==2 and death.snapshot().equipment_ids==[90,81],"First mining death owner changed the source Betty loadout")
	var particles:=Particles.new()
	if not particles.configure_first_mining(bindings,death,SEED_SECONDS):check(false,particles.error);return
	var initial: Dictionary=particles.snapshot()
	check(initial.owners.keys()==["player","world"] and initial.smoke_fire_births.is_empty() and initial.burst_count==0,"First mining registered an NPC or player smoke/fire emitter")
	check(not initial.owners.player.trail.enabled and initial.owners.player.trail.visible and initial.owners.world.burst.enabled,"First mining general sprite flags changed")
	check(particles.matches_death(death) and particles.presentation_identity()!=death.presentation_identity(),"Particle owner lost the real death identity or borrowed its presentation token")
	var wrong_death:=death.fork_for_frame()
	check(particles.matches_death(wrong_death),"A fork of the retained death owner lost its presentation identity")
	var unrelated:=Death.new()
	check(unrelated.configure(bindings,resources,construction,catalogues) and not particles.matches_death(unrelated),"Another death owner reused the configured particle identity")
	var player: RefCounted=construction.player_owner()
	player._state.vitals.hull=0
	check(death.start(player,ROOT,Vector3.ZERO,CAMERA,2),death.error)
	check(particles.apply_player_poll(death),particles.error)
	check(particles.snapshot().owners.player.trail.enabled,"Death entry poll did not enable player trail")
	var moved:=ROOT;moved.origin.z+=125
	check(particles.advance(ROOT,1) and particles.advance(moved,125),particles.error)
	check(particles.snapshot().births.player==1 and particles.snapshot().smoke_fire_births.is_empty(),"General sprite pass created smoke/fire or lost player trail birth")
	var held: Dictionary=particles.snapshot()
	check(particles.advance(moved,0) and particles.snapshot()==held,"Zero-time particle manager changed state")
	var candidate: RefCounted=particles.fork_for_frame()
	check(candidate.advance(moved,100) and particles.snapshot()==held and candidate.snapshot().elapsed_ms==held.elapsed_ms+100,"First mining particle fork changed the accepted owner")
	var rng: Dictionary=INITIAL_RNG.duplicate(true)
	for tick in 29:
		var result: Dictionary=death.advance(100,ROOT,rng)
		if result.is_empty():check(false,death.error);return
		rng=result.random_state
		if not particles.apply_player_tail(death) or not particles.advance(ROOT,100) or not particles.apply_player_poll(death):check(false,particles.error);return
	var near: Dictionary=death.advance(99,ROOT,rng)
	if near.is_empty():check(false,death.error);return
	rng=near.random_state
	check(particles.apply_player_tail(death) and particles.advance(ROOT,99) and particles.apply_player_poll(death),particles.error)
	check(death.snapshot().elapsed_ms==2999 and particles.snapshot().burst_count==0,"Player breakup occurred before the source threshold")
	var before_breakup: Dictionary=particles.snapshot()
	var crossing: Dictionary=death.advance(1,moved,rng)
	if crossing.is_empty():check(false,death.error);return
	check(crossing.events.breakup and crossing.events.particle_events==[{"emitting":false,"drawing":false,"impact_requested":true},{"emitting":true}],"Player death lost early breakup and later poll cues")
	check(particles.apply_player_tail(death),particles.error)
	var burst: Dictionary=particles.snapshot()
	check(burst.burst_count==1 and not burst.owners.player.trail.enabled and not burst.owners.player.trail.visible and burst.owners.world.burst.slots[0].position==death.snapshot().statistics_pose.origin,"Early breakup did not hide trail or emit one statistics-position burst")
	check(burst.owners.world.burst.slots[0].appearance.age_ms==0 and before_breakup.burst_count==0,"Burst was aged before the general manager pass")
	check(particles.advance(moved,1),particles.error)
	check(particles.snapshot().owners.world.burst.slots[0].appearance.age_ms==1,"General manager did not age the new burst")
	check(particles.apply_player_poll(death),particles.error)
	var after_poll: Dictionary=particles.snapshot()
	check(after_poll.owners.player.trail.enabled and not after_poll.owners.player.trail.visible and after_poll.burst_count==1,"Later death poll restored drawing or replayed burst")
	check(particles.apply_player_tail(death) and particles.snapshot()==after_poll,"Action-only breakup replayed its world sprite")
	check(particles.advance(moved,125) and particles.snapshot().births.player==0,"Hidden enabled trail emitted after breakup")
	check(particles.snapshot().smoke_fire_births.is_empty() and particles._smoke.snapshot().elapsed_ms==particles.snapshot().elapsed_ms,"Empty smoke/fire managers lost general-manager ordering")
	var duplicate: RefCounted=particles.fork_for_frame()
	var saved: Dictionary=particles.snapshot()
	check(duplicate.advance(moved,125) and particles.snapshot()==saved and duplicate.snapshot()!=saved,"Particle fork shared hidden trail or burst state")
	var invalid:=Particles.new()
	check(not invalid.configure_first_mining(bindings,unrelated,SEED_SECONDS+0.5) and invalid.snapshot().is_empty(),"Noninteger first mining seed was accepted")
	check(not invalid.configure_first_mining(bindings,RefCounted.new(),SEED_SECONDS) and invalid.snapshot().is_empty(),"First mining accepted an invented death owner")

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

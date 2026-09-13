extends SceneTree
const Death = preload("res://src/simulation/npc_destruction.gd")
const Resources = preload("res://src/content/npc_destruction_resources.gd")
const Definitions = preload("res://src/content/npc_destruction_definitions.gd")
const Construction = preload("res://src/simulation/opening_npc_construction.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const NpcControl = preload("res://src/simulation/opening_npc_control.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Weapons = preload("res://src/simulation/opening_npc_weapons.gd")
var failures := 0
# Independent integer LCG and analytic Rx*Ry*Rz fixtures. The initial pose is
# a quarter-turn about Y; these values do not use the native clock/rotation code.
const FIXTURES := [
	{"input":25214903917,"delay":1860,"spin":Vector3(0.023817306384444237,-0.035229768604040146,-0.026298275217413902),
	 "initial_rng":170671006977345,"breakup_rng":168194043956028,"drift_speed":50.029998779296875,
	 "drift":Vector3(-0.13948878645896912,0.94542396068573,0.29447633028030396),
	 "basis":Basis(Vector3(0.03457409515976906,-0.02712632156908512,-0.9990339279174805),Vector3(0.024732740595936775,0.9993486404418945,-0.02627892792224884),Vector3(0.9990960359573364,-0.023800278082489967,0.035222481936216354))},
	{"input":25214899796,"delay":2251,"spin":Vector3(-0.010503065772354603,-0.030984044075012207,-0.0378110371530056),
	 "initial_rng":258144839677080,"breakup_rng":66294055135991,"drift_speed":50.34000015258789,
	 "drift":Vector3(0.6077308654785156,-0.7941016554832458,0.008103078231215477),
	 "basis":Basis(Vector3(0.031352266669273376,-0.03747480735182762,-0.9988056421279907),Vector3(-0.009324357844889164,0.9992424249649048,-0.03778388351202011),Vector3(0.9994649291038513,0.010497831739485264,0.030979087576270103))}]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("NPC destruction checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, binding_path: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(binding_path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var resources := Resources.new();var death := Death.new()
	if bindings.opening_actors.npc_initialization.get("destruction",{}).is_empty():
		check(not resources.configure(library,bindings) and resources.snapshot().is_empty(),"Legacy pack invented NPC death resources")
		check(not death.configure(bindings,resources,0,Transform3D.IDENTITY,1.0,[]),"Legacy pack invented NPC destruction")
		return
	if not resources.configure(library,bindings): check(false,resources.error);return
	var metadata := resources.snapshot()
	check(metadata.duration_ms==4500 and metadata.models.size()==3,"Actual explosion resource range changed")
	for i in 3:
		check(metadata.models[i].model_id==[16821,16820,14292][i] and metadata.models[i].resource==Resources.PATHS[i],"Source model order changed")
		check(metadata.models[i].start_ms==33 and metadata.models[i].end_ms==4500,"Actual positive animation range changed")
	var detached := resources.snapshot();detached.models.clear()
	check(resources.snapshot()==metadata,"Explosion metadata aliases resource owner")
	check_definitions(bindings,"armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64")
	var constructor := Construction.new()
	if not constructor.configure(bindings,catalogues): check(false,constructor.error);return
	var constructed := constructor.generate({"state":280936762154123})
	if constructed.is_empty(): check(false,constructor.error);return
	var fragments: Array=constructed.actors[0].fragments
	var pose := Transform3D(Basis(Vector3(0,0,-1),Vector3.UP,Vector3.RIGHT),Vector3(100,-50,70))
	for fixture in FIXTURES: check_lifetime(bindings,resources,fragments,pose,fixture)
	check_failures(bindings,resources,fragments,pose)
	check_controller(bindings,catalogues,resources,constructor,constructed)
	for unrelated in [null,RefCounted.new()]:
		check(not resources.configure(unrelated,bindings) and resources.snapshot().is_empty(),"Unrelated library retained resources")
		check(not resources.configure(library,unrelated) and resources.snapshot().is_empty(),"Unrelated bindings retained resources")
	var saved_id: String=bindings.base_content_id;bindings.base_content_id="0".repeat(64)
	check(not resources.configure(library,bindings) and resources.snapshot().is_empty(),"Cross-content library accepted")
	bindings.base_content_id=saved_id
	print(library.manifest.profile.edition,": retained fragments, nine RNG draws, local tumble and strict lifetime boundaries verified")

func check_lifetime(bindings: RefCounted, resources: RefCounted, fragments: Array, pose: Transform3D, fixture: Dictionary) -> void:
	var death := Death.new()
	check(death.configure(bindings,resources,0,pose,0.375,fragments),death.error)
	var fresh := death.snapshot()
	check(fresh.phase=="ready" and not fresh.effect.active and fresh.effect.position==null,"Configured death is not inert")
	check(fresh.fragments==fragments and fresh.effect.models.size()==2+fragments.size(),"Retained fragment population changed")
	var result := death.advance(0,{"state":fixture.input})
	if result.is_empty(): check(false,death.error);return
	var started := death.snapshot()
	check(not death.capture(pose,2.0) and death.snapshot()==started,"Started death accepted a new motion capture")
	check(result.started and not result.breakup and result.sound_events==[20],"Death initialization events changed")
	check(result.audio_events==[{"source_id":20,"position":pose.origin}],"Initial death sound lost the captured ship position")
	check(started.mode==3 and started.phase=="tumble" and started.countdown_ms==fixture.delay,"Death delay draw changed")
	check(started.spin==fixture.spin and started.forward==Vector3.RIGHT and started.pose==pose,"Initial spin or captured pose changed")
	check(result.random_state=={"state":fixture.initial_rng},"Initialization did not consume four source draws")
	var input_rng: Dictionary=result.random_state.duplicate()
	var fork: RefCounted=death.fork_for_frame()
	var longer: RefCounted=death.fork_for_frame()
	check(not fork.advance(1,input_rng).is_empty(),fork.error)
	check(not longer.advance(50,input_rng).is_empty(),longer.error)
	check(basis_near(fork.snapshot().pose.basis,fixture.basis),"Local XYZ multiplication disagrees with analytic matrix")
	check(fork.snapshot().pose.basis==longer.snapshot().pose.basis,"Spin incorrectly depends on frame duration")
	check(fork.snapshot().pose.origin==Vector3(100.375,-50,70) and longer.snapshot().pose.origin==Vector3(118.75,-50,70),"Tumble lost fractional travel or captured forward")
	check(death.snapshot()==started and input_rng=={"state":fixture.initial_rng},"Speculative update mutated original state or RNG")
	# Countdown equality is still tumble; its next positive tick triggers an
	# explosion at the preceding position, with no lifetime increment that tick.
	advance(death,fixture.delay,input_rng)
	var equal := death.snapshot()
	check(equal.countdown_ms==0 and equal.phase=="tumble" and not equal.effect.active,"Countdown transitioned at equality")
	check(equal.forward==Vector3.RIGHT and equal.pose.origin==Vector3(100+fixture.delay*0.375,-50,70),"Rotating basis changed retained travel direction")
	result=death.advance(1,input_rng)
	if result.is_empty(): check(false,death.error);return
	var breakup := death.snapshot()
	check(result.breakup and not result.started and result.sound_events==[19],"Breakup dispatch order changed")
	check(result.audio_events==[{"source_id":19,"position":equal.pose.origin}],"Breakup sound used the moved ship instead of its preceding position")
	check(result.random_state=={"state":fixture.breakup_rng},"Breakup did not consume sound, scalar, then XYZ draws")
	check(breakup.drift_speed==fixture.drift_speed and breakup.drift_direction==fixture.drift,"Breakup scalar or direction changed")
	check(breakup.phase=="explosion" and breakup.mode==4 and breakup.countdown_ms==0 and breakup.cleanup_elapsed_ms==0,"Breakup leaked countdown overshoot")
	check(breakup.effect.active and breakup.effect.elapsed_ms==0 and breakup.effect.position==equal.pose.origin,"Breakup captured post-motion position or advanced on its trigger frame")
	check(breakup.pose.origin==equal.pose.origin+Vector3(0.375,0,0),"Transition frame omitted tumble translation")
	for model in breakup.effect.models: check(model.time_ms==33 and model.playing,"Breakup did not start every retained model")
	input_rng=result.random_state.duplicate()
	advance(death,4467,input_rng)
	for model in death.snapshot().effect.models: check(model.time_ms==4500 and model.playing,"Animation stopped at exact end time")
	result=death.advance(1,input_rng)
	for model in death.snapshot().effect.models: check(model.time_ms==4500 and not model.playing,"Animation did not clamp after end time")
	advance(death,32,input_rng)
	check(death.snapshot().effect.elapsed_ms==4500 and death.snapshot().effect.active,"Effect expired at lifetime equality")
	check(death.snapshot().pose==breakup.pose,"Explosion phase kept moving the ship")
	result=death.advance(1,input_rng)
	var expired := death.snapshot()
	check(result.expired and not result.retired_now and expired.phase=="explosion" and not expired.effect.active and expired.effect.elapsed_ms==0,"Expiry prematurely retired the actor")
	check(expired.cleanup_elapsed_ms==4501,"Cleanup clock lost unscaled elapsed time")
	for model in expired.effect.models: check(model.time_ms==33 and model.playing,"Expiry failed to rewind a retained model")
	result=death.advance(0,input_rng)
	check(result.retired_now and death.snapshot().phase=="retired" and death.snapshot().cleanup_elapsed_ms==4501,"No-cargo retirement waited an extra positive tick")
	check(result.random_state==input_rng and result.sound_events.is_empty(),"Retirement consumed unrelated random or sound events")
	var retired := death.snapshot()
	result=death.advance(100,input_rng)
	check(death.snapshot()==retired and not result.retired_now and result.random_state==input_rng,"Retired actor continued its lifecycle")
	var leaked := death.snapshot();leaked.fragments.clear();leaked.effect.models[0].time_ms=999
	check(death.snapshot()==retired,"Snapshot aliases actor lifetime")

func check_failures(bindings: RefCounted, resources: RefCounted, fragments: Array, pose: Transform3D) -> void:
	var death := Death.new();var rng := {"state":FIXTURES[0].input}
	check(death.advance(0,rng).is_empty(),"Unconfigured death advanced")
	check(death.configure(bindings,resources,0,pose,1.0,fragments),death.error)
	var previous := death.snapshot()
	check(not death.capture(pose,-1) and death.snapshot()==previous,"Invalid motion capture changed state")
	for delta in [-1,0.5,true,null,"16",INF,NAN,int(bindings.frame_clock.max_frame_milliseconds)+1]:
		check(death.advance(delta,rng).is_empty() and death.snapshot()==previous,"Invalid frame partly changed death state")
	for invalid in [null,{},0,{"state":-1},{"state":true},{"state":281474976710656}]:
		check(death.advance(0,invalid).is_empty() and death.snapshot()==previous,"Invalid random state partly initialized death")
	for unrelated in [null,RefCounted.new()]:
		check(not death.configure(unrelated,resources,0,pose,1,fragments) and death.snapshot().is_empty(),"Unrelated bindings accepted")
		check(not death.configure(bindings,unrelated,0,pose,1,fragments) and death.snapshot().is_empty(),"Unrelated resources accepted")
	for id in [-1,3,true,0.5,null]: check(not death.configure(bindings,resources,id,pose,1,fragments),"Invalid actor accepted")
	for speed in [-1,true,null,"1",NAN,INF,1e100]: check(not death.configure(bindings,resources,0,pose,speed,fragments),"Invalid speed accepted")
	var invalid_pose := pose;invalid_pose.basis.x*=2
	check(not death.configure(bindings,resources,0,invalid_pose,1,fragments),"Scaled ship pose accepted")
	for bad in [[],[{}],fragments+fragments+fragments+fragments]:
		check(not death.configure(bindings,resources,0,pose,1,bad),"Invalid fragment count accepted")
	for field in ["resource_id","rotation_radians","scale"]:
		var bad := fragments.duplicate(true);bad[0][field]=null
		check(not death.configure(bindings,resources,0,pose,1,bad),"Malformed retained fragment accepted")
	var saved: String=bindings.binding_id;bindings.binding_id="0".repeat(64)
	check(not death.configure(bindings,resources,0,pose,1,fragments),"Cross-binding resources accepted")
	bindings.binding_id=saved
	check(death.configure(bindings,resources,0,pose,3e38,fragments),death.error)
	previous=death.snapshot()
	check(death.advance(100,rng).is_empty() and death.snapshot()==previous,"Overflow partly consumed the death frame")
	death.clear()
	check(death.snapshot().is_empty() and death.fork_for_frame().snapshot().is_empty(),"Clear or empty fork retained death state")

func check_controller(bindings: RefCounted, catalogues: RefCounted, resources: RefCounted, constructor: RefCounted, constructed: Dictionary) -> void:
	var control := NpcControl.new();var combat := Combat.new();var guns := Weapons.new()
	check(control.configure(bindings,catalogues,0.5) and combat.configure(bindings,catalogues,0.5) and guns.configure(bindings,catalogues),control.error+combat.error+guns.error)
	for id in 3: check(control.set_initial_route(id,constructor.route(id)),control.error)
	var wrong := constructed.duplicate(true);wrong.actors[2].cargo=[{"item_id":1,"quantity":1}]
	var initial: Dictionary=control.snapshot()
	check(not control.set_initial_destruction(resources,wrong) and control.snapshot()==initial,"Late fragment failure partly prepared controller")
	check(control.set_initial_destruction(resources,constructed),control.error)
	check(not control.set_initial_destruction(resources,constructed),"Controller replaced initial fragments")
	var flags := [];flags.resize(bindings.opening_dialogue.events.size());flags.fill(false);flags[7]=true
	check(combat.update(combat.snapshot(),3,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"finished":flags}),combat.error)
	var player := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"pose":Transform3D(Basis.IDENTITY,Vector3(0,0,10000)),"active":true,"hull":9999999,"special_flight":false,"targeting_blocked":true}
	for id in 3: combat.set_pose(id,Transform3D(Basis.IDENTITY,Vector3(0,0,-1000*id)))
	var rng := {"state":25214903917}
	# Start living flight owners first, then apply real lethal normal hits.
	var frame: Dictionary=control.evaluate(combat,guns,0,player,rng)
	if frame.is_empty(): check(false,control.error);return
	control=frame.controller;combat=frame.combat;guns=frame.weapons
	check(frame.random_state==rng,"Zero-time fresh flight consumed RNG")
	var accounting: bool=control.snapshot().has("death_accounting")
	for id in 3:
		check(combat.normal_hit(id,150,accounting and id==1).destroyed_now,"Fixture did not exhaust source hull")
		control._guidance[id]._state.selection_elapsed_ms=5000
		control._guidance[id]._state.boost_elapsed_ms=6001
	var before: Dictionary=control.snapshot();var bodies: Dictionary=combat.snapshot();var weapons: Dictionary=guns.snapshot()
	var skipped: Dictionary=before.actors[0].destruction.duplicate(true)
	skipped.phase="retired";skipped.mode=4
	check(not combat.apply_destruction(0,skipped) and combat.snapshot()==bodies,"Combat body skipped tumble and explosion")
	# Actor zero and one would initialize deaths before the final invalid actor.
	var invalid_combat: RefCounted=combat.fork_for_frame()
	invalid_combat._actors[2]._state.pose.origin.x=INF
	check(control.evaluate(invalid_combat,guns,1,player,rng).is_empty(),"Late invalid death actor was accepted")
	check(control.snapshot()==before and combat.snapshot()==bodies and guns.snapshot()==weapons,"Failed death pass mutated input owners")
	frame=control.evaluate(combat,guns,1,player,rng)
	if frame.is_empty(): check(false,control.error);return
	check(control.snapshot()==before and combat.snapshot()==bodies and guns.snapshot()==weapons,"Death candidate mutated input owners")
	# Independently calculated first pass: each actor consumes selection(100,100)
	# before death(1500,200,200,200). Overdue boosts must not draw or change speed.
	check(frame.random_state=={"state":6496960623295},"Death initialization interleaved selection and actor draws incorrectly")
	if accounting:
		var credit: Dictionary=frame.controller.snapshot().death_accounting
		check(credit.events.size()==3 and credit.counter_deltas=={"hostile_remaining":-3,"hostile_deaths":3,"world_player_kills":2,"world_other_kills":1,"player_kills":2,"pirate_kills":2},"Death frame discarded or misattributed counter changes")
		check(before.death_accounting.events.is_empty(),"Kill credit preceded death initialization")
	var delays := [2028,1718,1594]
	for id in 3:
		var row: Dictionary=frame.actors[id]
		var state: Dictionary=frame.controller.snapshot().actors[id]
		check(row.destruction.started and row.destruction.sound_events==[20] and row.firing.is_empty() and row.movement.is_empty(),"Lethal actor fired or used live flight")
		if accounting: check(row.death_accounting.actor_id==id and row.death_accounting.nonplayer_kill==(id==1),"Death event lost its source attribution")
		check(state.destruction.countdown_ms==delays[id] and state.destruction.speed==2 and state.destruction.pose.origin==bodies.actors[id].pose.origin+Vector3(0,0,2),"Death failed to capture retained speed/pose in its lethal frame")
		check(state.guidance.previous_hull==before.actors[id].guidance.previous_hull and state.guidance.damage_accumulated==0 and not state.guidance.boost_active and state.guidance.boost_elapsed_ms==6002,"Death incorrectly ran damage boost logic")
		check(state.guidance.route==before.actors[id].guidance.route and state.flight.is_empty(),"Death advanced a route or retained live flight authority")
		check(not frame.combat.collision_context(id).eligible,"Dying hull remained a collision target")
	var retirements := 0;var breakups := 0;var checked_early := false
	for tick in 100:
		control=frame.controller;combat=frame.combat;guns=frame.weapons;rng=frame.random_state
		var prior: Dictionary=control.snapshot()
		var retiring := []
		for id in 3:
			var life: Dictionary=prior.actors[id].destruction
			if life.phase=="explosion" and not life.effect.active:
				retiring.append(id)
				# If the early exit is misplaced, hostility would flip this flag.
				combat._actors[id]._state.hostile=false
		frame=control.evaluate(combat,guns,100,player,rng)
		if frame.is_empty(): check(false,"Repeated NPC destruction pass: "+control.error);return
		for row in frame.actors:
			check(row.firing.is_empty() and row.movement.is_empty() and not row.destruction.started,"Dying actor restarted, fired or moved through live flight")
			check(not row.has("death_accounting"),"Later destruction frame issued kill credit twice")
			if row.destruction.breakup: breakups+=1
			if row.destruction.retired_now: retirements+=1
		for id in retiring:
			checked_early=true
			check(frame.controller.snapshot().actors[id].guidance==prior.actors[id].guidance and not frame.combat.snapshot().actors[id].hostile,"Retirement ran timers, selection or hostility refresh")
		if retirements==3: break
	check(breakups==3 and retirements==3 and checked_early,"Three actors did not each break up and retire once")
	if accounting:
		check(frame.controller.snapshot().death_accounting.events.size()==3 and frame.controller.snapshot().death_accounting.counter_deltas.player_kills==2,"Retirement repeated kill accounting")
	for actor in frame.combat.snapshot().actors: check(not actor.active and actor.actor_mode==4 and actor.vitals.hull==0,"Retirement did not deactivate the exhausted body")
	var completed: Dictionary=frame.controller.snapshot()
	var last: Dictionary=frame.controller.evaluate(frame.combat,frame.weapons,100,player,frame.random_state)
	check(not last.is_empty(),frame.controller.error)
	if not last.is_empty(): check(last.controller.snapshot()==completed and last.random_state==frame.random_state,"Retired population continued selection or random work")

func check_definitions(bindings: RefCounted, architecture: String) -> void:
	var npc: Dictionary=bindings.opening_actors.npc_initialization
	var data: Dictionary=npc.destruction
	var extent := 0
	for span in data.provenance.values(): extent=maxi(extent,int(span.offset)+int(span.bytes))
	check(Definitions.validate(data,extent,architecture,npc).is_empty(),"Destruction source spans rejected")
	var audio: Dictionary=npc.get("destruction_audio",{})
	check(Definitions.validate_audio(audio,extent,architecture,npc).is_empty(),"Destruction audio source spans rejected")
	if not audio.is_empty():
		for key in audio.provenance:
			var invalid: Dictionary=audio.duplicate(true);invalid.provenance[key].offset+=1
			check(not Definitions.validate_audio(invalid,extent,architecture,npc).is_empty(),"Detached death audio evidence accepted")
		var invalid: Dictionary=audio.duplicate(true);invalid.initial_source_id=19
		check(not Definitions.audio_parameters(invalid),"Breakup sound accepted as death initialization")
	for key in data:
		var bad := data.duplicate(true);bad.erase(key)
		check(not Definitions.parameters(bad),"Incomplete declaration accepted: "+key)
	for key in data.provenance:
		var bad := data.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,extent,architecture,npc).is_empty(),"Detached evidence span accepted")
	for value in [true,null,0.5,NAN,INF]:
		var bad := data.duplicate(true);bad.delay_base_ms=value
		check(not Definitions.parameters(bad),"Invalid numeric declaration accepted")
	for value in [null,{},0]:
		var bad := npc.duplicate(true);bad.guidance=value
		check(not Definitions.validate(data,extent,architecture,bad).is_empty(),"Missing guidance evidence accepted")
	var bad := npc.duplicate(true);bad.guidance.provenance.selection.offset+=4
	check(not Definitions.validate(data,extent,architecture,bad).is_empty(),"Moved guidance anchor accepted")

func advance(death: RefCounted, milliseconds: int, rng: Dictionary) -> void:
	var remaining := milliseconds
	while remaining>0:
		var delta := mini(100,remaining)
		var result: Dictionary=death.advance(delta,rng)
		if result.is_empty(): check(false,death.error);return
		check(result.random_state==rng and result.sound_events.is_empty(),"Ordinary death frame consumed unexpected events")
		remaining-=delta

func basis_near(actual: Basis, expected: Basis) -> bool:
	if not actual.is_finite(): return false
	for i in 3:
		if actual[i].distance_to(expected[i])>0.000001: return false
	return true

func check(condition: bool, message: String) -> void:
	if not condition: failures+=1;push_error(message)

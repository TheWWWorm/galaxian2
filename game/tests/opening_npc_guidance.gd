extends SceneTree
const Guidance = preload("res://src/simulation/opening_npc_guidance.gd")
const Definitions = preload("res://src/content/opening_npc_guidance_definitions.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Flight = preload("res://src/simulation/npc_flight.gd")
const Guns = preload("res://src/simulation/opening_npc_weapons.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("Opening NPC guidance checks: %d failures" % failures)
	quit(1 if failures else 0)

func active_group(bindings: RefCounted, catalogues: RefCounted, difficulty := 0.5) -> RefCounted:
	var combat := Combat.new()
	if not combat.configure(bindings,catalogues,difficulty):
		check(false,combat.error)
		return combat
	var scene := combat.snapshot()
	for actor in scene.actors:
		actor.pose=Transform3D.IDENTITY
		actor.position=Vector3.ZERO
	var flags := []
	flags.resize(bindings.opening_dialogue.events.size());flags.fill(false);flags[7]=true
	check(combat.update(scene,3,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"finished":flags}),combat.error)
	return combat

func player_for(bindings: RefCounted, position: Vector3) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"pose":Transform3D(Basis.IDENTITY,position),"active":true,"hull":10000,
		"special_flight":false,"targeting_blocked":false}

func check_profile(content: String, bindings_path: String) -> void:
	var library := Library.new()
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(bindings_path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error)
		return
	var guidance := Guidance.new()
	var data: Dictionary = bindings.opening_actors.npc_initialization.get("guidance",{})
	if data.is_empty():
		check(not guidance.configure(bindings,catalogues,0,0.5) and guidance.snapshot().is_empty(),"Legacy pack invented NPC guidance")
		return
	if not guidance.configure(bindings,catalogues,0,0.5):
		check(false,guidance.error)
		return
	var original_population: Array = bindings.opening_actors.actors
	for field in ["actor_kind","hull_catalogue_id"]:
		bindings.opening_actors.actors=original_population.duplicate(true)
		bindings.opening_actors.actors[1][field]=2
		check(not guidance.configure(bindings,catalogues,0,0.5) and guidance.snapshot().is_empty(),"Changed NPC target membership accepted: "+field)
	bindings.opening_actors.actors=original_population.duplicate(true)
	bindings.opening_actors.actors.pop_back()
	check(not guidance.configure(bindings,catalogues,0,0.5),"Incomplete NPC target membership accepted")
	bindings.opening_actors.actors=original_population
	check(guidance.configure(bindings,catalogues,0,0.5),guidance.error)
	var architecture := "armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	var extent := 0
	for span in data.provenance.values(): extent=maxi(extent,int(span.offset)+int(span.bytes))
	check(Definitions.validate(data,extent,architecture).is_empty(),"NPC guidance provenance rejected")
	for key in data:
		var bad := data.duplicate(true);bad.erase(key)
		check(not Definitions.parameters(bad),"Missing guidance field accepted: "+key)
	for key in data.provenance:
		var bad := data.duplicate(true);bad.provenance[key].bytes+=1
		check(not Definitions.validate(bad,extent,architecture).is_empty(),"Changed guidance extent accepted: "+key)
	var combat := active_group(bindings,catalogues)
	var actor: Dictionary = combat.snapshot().actors[0]
	var player := player_for(bindings,Vector3(0,0,10000))
	var random := Random.new();random.seed_from(4)
	var seed := random.snapshot()
	check(guidance.snapshot().maximum_hull==150 and guidance.snapshot().previous_hull==(20 if architecture=="x86_64" else 34),"Opening hull override replaced the constructor damage sample")
	var result := guidance.update(0,actor,Transform3D.IDENTITY,player,seed)
	if result.is_empty():
		check(false,guidance.error)
		return
	check(result.fire_requested and result.target_kind=="player" and result.speed==2 and result.steering_enabled,"First active player acquisition changed")
	check(result.random_state==seed,"Ordinary acquisition consumed random values")
	player.pose.origin=Vector3(100,0,20000)
	check(guidance.update(0,actor,Transform3D.IDENTITY,player,seed).fire_requested,"Aligned distant target rejected")
	player.pose.origin=Vector3(200,0,20000)
	check(not guidance.update(0,actor,Transform3D.IDENTITY,player,seed).fire_requested,"Target outside local aim tolerance accepted")
	# No forward-Z gate exists in the source firing test.
	player.pose.origin=Vector3(0,0,-10000)
	result=guidance.update(0,actor,Transform3D.IDENTITY,player,seed)
	check(result.fire_requested and result.local_aim.z<0,"NPC invented a positive-forward aim requirement")
	player.pose.origin=Vector3(7999,0,0)
	result=guidance.update(0,actor,Transform3D.IDENTITY,player,seed)
	check(result.fire_requested and result.close_heading_preserved and result.direction==Vector3(0,0,1),"Close target did not preserve the current heading")
	player.pose.origin=Vector3(8000,0,0)
	result=guidance.update(0,actor,Transform3D.IDENTITY,player,seed)
	check(not result.fire_requested and not result.close_heading_preserved,"Close-range equality was accepted")
	player.pose.origin=Vector3(0,0,35000)
	check(not guidance.update(0,actor,Transform3D.IDENTITY,player,seed).fire_requested,"Fire range equality was accepted")
	player.pose.origin=Vector3(0,0,34999)
	check(guidance.update(0,actor,Transform3D.IDENTITY,player,seed).fire_requested,"Target inside fire range was rejected")
	player.targeting_blocked=true
	check(not guidance.update(0,actor,Transform3D.IDENTITY,player,seed).fire_requested and not guidance.snapshot().fire_desired,"Blocked target retained firing desire")
	player.targeting_blocked=false;player.special_flight=true;player.pose.origin=Vector3(0,1000,10000)
	result=guidance.update(0,actor,Transform3D.IDENTITY,player,seed)
	check(result.close_heading_preserved and not result.fire_requested and not guidance.snapshot().fire_desired,"Special-flight height condition changed")
	player=player_for(bindings,Vector3(0,0,10000))
	guidance.configure(bindings,catalogues,0,0.5)
	player.pose.origin=Vector3(0,0,50000)
	var unacquired: Dictionary = guidance.snapshot()
	check(guidance.update(0,actor,Transform3D.IDENTITY,player,seed).is_empty() and guidance.snapshot()==unacquired,"Missing route fallback was replaced with player pursuit")
	player.pose.origin=Vector3(0,0,49999)
	guidance.update(0,actor,Transform3D.IDENTITY,player,seed)
	check(guidance.snapshot().fire_desired,"Target inside engagement range was not acquired")
	player.pose.origin=Vector3(0,0,50000)
	check(not guidance.update(0,actor,Transform3D.IDENTITY,player,seed).is_empty(),"Existing acquired target was discarded before refresh")
	unacquired=guidance.snapshot()
	check(guidance.update(5001,actor,Transform3D.IDENTITY,player,seed).is_empty() and guidance.snapshot()==unacquired,"Out-of-range refresh invented a route")
	guidance.configure(bindings,catalogues,0,0.5)
	player.pose.origin=Vector3(0,0,10000)
	result=guidance.update(5001,actor,Transform3D.IDENTITY,player,seed)
	check(not result.fire_requested and not guidance.snapshot().fire_desired,"Selection refresh invented immediate acquisition")
	check(guidance.update(0,actor,Transform3D.IDENTITY,player,result.random_state).fire_requested,"Refresh did not allow acquisition on the following update")
	guidance.configure(bindings,catalogues,0,0.5)
	result=guidance.update(5000,actor,Transform3D.IDENTITY,player,seed)
	check(result.random_state==seed and not guidance.snapshot().boost_active,"Random refresh ran at exact period equality")
	result=guidance.update(1,actor,Transform3D.IDENTITY,player,result.random_state)
	# Java-compatible source generator seed 4 yields 62,52,3,1558 for these bounds.
	check(random.next_int(100)==62 and random.next_int(100)==52 and random.next_int(100)==3 and random.next_int(3000)==1558,"Source RNG fixture changed")
	check(result.random_state==random.snapshot() and guidance.snapshot().boost_duration_ms==6558 and guidance.snapshot().boost_active,"Selection/boost draw order or duration changed")
	check(result.speed==Vitals.single(2.0*float(data.speed_increase)),"Boost did not apply its per-update multiplier")
	var speed: float = result.speed
	result=guidance.update(0,actor,Transform3D.IDENTITY,player,result.random_state)
	check(result.speed==Vitals.single(speed*float(data.speed_increase)),"Zero-time source boost update was incorrectly suppressed")
	for i in 40: result=guidance.update(0,actor,Transform3D.IDENTITY,player,result.random_state)
	check(result.speed==5.5 and guidance.snapshot().speed_target==0 and guidance.snapshot().boost_active,"NPC boost failed to hold its capped speed")
	result=guidance.update(6558,actor,Transform3D.IDENTITY,player,result.random_state)
	check(result.speed==5.5,"Boost expired at duration equality")
	result=guidance.update(1,actor,Transform3D.IDENTITY,player,result.random_state)
	check(result.speed<5.5 and result.speed>2,"NPC boost did not begin its return to cruise")
	for i in 40: result=guidance.update(0,actor,Transform3D.IDENTITY,player,result.random_state)
	check(result.speed==2 and not guidance.snapshot().boost_active,"NPC boost failed to settle at cruise")
	guidance.configure(bindings,catalogues,0,0.5)
	guidance._state.straight=true;guidance._state.selection_elapsed_ms=5000
	random.seed_from(4);random.next_int(100)
	result=guidance.update(1,actor,Transform3D.IDENTITY,player,seed)
	check(result.steering_enabled and result.random_state==random.snapshot(),"Straight interval did not clear without a new probability draw")
	# Authored hull override and the constructor sample remain different inputs.
	var damaged := actor.duplicate(true);damaged.vitals.hull=1
	guidance.configure(bindings,catalogues,0,0.5)
	result=guidance.update(0,damaged,Transform3D.IDENTITY,player,seed)
	check(result.random_state==seed and not guidance.snapshot().boost_active and guidance.snapshot().damage_accumulated==(19 if architecture=="x86_64" else 33),"Damage boost used current opening hull as its constructor sample")
	var medium_difficulty:=4.5 if architecture=="x86_64" else 2.5
	var medium := active_group(bindings,catalogues,medium_difficulty)
	var threshold: Dictionary = medium.snapshot().actors[0]
	guidance.configure(bindings,catalogues,0,medium_difficulty)
	threshold.vitals.hull=40 if architecture=="x86_64" else 42 # Factory sample minus 60: exactly 40% of maximum 150.
	result=guidance.update(0,threshold,Transform3D.IDENTITY,player,seed)
	check(not guidance.snapshot().boost_active and result.random_state==seed,"Damage boost triggered at exact percentage equality")
	threshold.vitals.hull-=1
	result=guidance.update(0,threshold,Transform3D.IDENTITY,player,seed)
	check(guidance.snapshot().boost_active and guidance.snapshot().damage_boost,"Damage above the strict percentage did not trigger boost")
	var hard := active_group(bindings,catalogues,10.0)
	guidance.configure(bindings,catalogues,0,10.0)
	check(guidance.snapshot().maximum_hull==(210 if architecture=="x86_64" else 357) and guidance.snapshot().previous_hull==(210 if architecture=="x86_64" else 357),"Source difficulty hull scale changed")
	random.seed_from(4);random.next_int(3000)
	var hard_actor: Dictionary=hard.snapshot().actors[0]
	if architecture=="x86_64":
		result=guidance.update(0,hard_actor,Transform3D.IDENTITY,player,seed)
		check(not result.is_empty() and not guidance.snapshot().boost_active and result.random_state==seed,"Opening override falsely triggered damage boost at difficulty10")
		hard_actor.vitals.hull=125 # 85 accumulated damage exceeds 40% of factory/max210.
	result=guidance.update(0,hard_actor,Transform3D.IDENTITY,player,seed)
	check(guidance.snapshot().boost_active and guidance.snapshot().damage_boost and result.random_state==random.snapshot(),"Damage-triggered boost consumed a probability draw or lost the hull override")
	check_rollback(guidance,bindings,catalogues,actor,player,seed)
	check_composition(bindings,catalogues,combat,player,seed)
	print(library.manifest.profile.edition,": targeting, aim, random cadence, boost and pre-motion firing verified")

func check_rollback(guidance: RefCounted, bindings: RefCounted, catalogues: RefCounted, actor: Dictionary, player: Dictionary, seed: Dictionary) -> void:
	guidance.configure(bindings,catalogues,0,0.5)
	var saved: Dictionary = guidance.snapshot()
	for delta in [-1,1.0,true]:
		check(guidance.update(delta,actor,Transform3D.IDENTITY,player,seed).is_empty() and guidance.snapshot()==saved,"Invalid NPC duration mutated guidance")
	for key in ["hull","active","special_flight","targeting_blocked","pose","binding_id"]:
		var bad := player.duplicate(true);bad.erase(key)
		check(guidance.update(5001,actor,Transform3D.IDENTITY,bad,seed).is_empty() and guidance.snapshot()==saved,"Incomplete player state partly advanced guidance: "+key)
	var far := player.duplicate(true);far.pose.origin=Vector3(1.0e30,0,0)
	check(guidance.update(5001,actor,Transform3D.IDENTITY,far,seed).is_empty() and guidance.snapshot()==saved,"Unsupported distant route retained random or speed changes")
	check(guidance.update(1,actor,Transform3D.IDENTITY,player,{}).is_empty() and guidance.snapshot()==saved,"Invalid shared RNG state accepted")
	var fork: RefCounted = guidance.fork_for_frame()
	check(not fork.update(5001,actor,Transform3D.IDENTITY,player,seed).is_empty() and guidance.snapshot()==saved,"NPC guidance fork shares mutable state")
	guidance._state.selection_elapsed_ms=2147483647
	saved=guidance.snapshot()
	check(guidance.update(1,actor,Transform3D.IDENTITY,player,seed).is_empty() and guidance.snapshot()==saved,"Guidance timer overflow partly committed")
	check(not guidance.configure(null,catalogues,0,0.5) and guidance.snapshot().is_empty(),"Failed guidance configuration retained state")

func check_composition(bindings: RefCounted, catalogues: RefCounted, combat: RefCounted, player: Dictionary, seed: Dictionary) -> void:
	var guidance := Guidance.new();guidance.configure(bindings,catalogues,0,0.5)
	var flight := Flight.new();flight.configure(bindings,Transform3D.IDENTITY)
	var guns := Guns.new();check(guns.configure(bindings,catalogues),guns.error)
	guns.advance(1)
	player=player.duplicate(true);player.pose.origin=Vector3(0,0,10000)
	var actor: Dictionary = combat.snapshot().actors[0]
	var decision := guidance.update(16,actor,flight.snapshot().root_pose,player,seed)
	check(decision.fire_requested,guidance.error)
	var fired := guns.fire(combat,[0] if decision.fire_requested else [])
	check(fired.actors[0].outcome.fired,guns.error)
	var shot: Dictionary = fired.actors[0].outcome.projectile
	var moved := flight.advance(16,decision.direction,decision.speed,decision.steering_enabled)
	check(shot.position==Vector3.ZERO and moved.root_pose.origin==Vector3(0,0,32),"NPC shot used its post-motion muzzle")
	check(shot.velocity==Vector3(0,0,16),"NPC guidance changed the source primary launch vector")
	check(guns.snapshot().actors[1].projectiles.slots.all(func(value):return value==null),"One NPC decision fired an ally's weapon")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)

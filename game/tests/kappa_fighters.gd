extends SceneTree
## Detached encounter construction and frame checks; no earned campaign state.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Rules=preload("res://src/content/kappa_population_definitions.gd")
const Fighters=preload("res://src/content/kappa_fighters_definitions.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const Route=preload("res://src/simulation/npc_route.gd")
const Actor=preload("res://src/simulation/opening_combat_actor.gd")
const Guidance=preload("res://src/simulation/opening_npc_guidance.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Weapons=preload("res://src/simulation/opening_npc_weapons.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const Rescue=preload("res://src/simulation/kappa_rescue.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
const Bombs=preload("res://src/simulation/emp_bombs.gd")
const CONDITIONS={"companions_empty":true,"location_match":false,"special_placement":false}
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected explicit content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Kappa fighters: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var seed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":55,"system_id":11,"ship_id":0,"equipment_ids":[22,86,81,55]}
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":21,"station_id":55,"system_id":11,"rank":0,"difficulty":0.5,"mission_kind":4,"mission_story":true,"mission_completed":false}
	if not Rules.available(bindings):
		check(not Construction.new().configure_kappa_rescue(bindings,cat,seed,context),"Legacy content enabled Kappa fighters")
		check(Fighters.systems(bindings,0).is_empty(),"Legacy content enabled Kappa systems initialization")
		return
	var invalids:={"campaign_cursor":20,"station_id":56,"system_id":19,"rank":21,"difficulty":0.75,"mission_kind":11,"mission_story":false,"mission_completed":true,"binding_id":"foreign"}
	for key in invalids:
		var invalid:=context.duplicate();invalid[key]=invalids[key]
		check(not Construction.new().configure_kappa_rescue(bindings,cat,seed,invalid),"Kappa accepted a mismatched context: "+key)
	for key in ["station_id","ship_id","equipment_ids"]:
		var invalid:=seed.duplicate(true);invalid[key]={"station_id":56,"ship_id":10,"equipment_ids":[-1]}[key]
		check(not Construction.new().configure_kappa_rescue(bindings,cat,invalid,context),"Kappa accepted an unsupported loadout: "+key)
	for id in [-1,4]:check(not Route.new().configure_kappa_generated(bindings,id),"Kappa accepted an absent route owner")
	var vectors: Variant=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("GOF2_KAPPA_VECTORS")))
	if not vectors is Array or vectors.size()!=5:check(false,"Supply five independent vectors in GOF2_KAPPA_VECTORS");return
	for vector in vectors:
		var owner:=Construction.new()
		if not owner.configure_kappa_rescue(bindings,cat,seed,context):check(false,owner.error);return
		var retained_seed:=seed.duplicate(true);var before:=owner.snapshot()
		check(owner.generate({"state":-1}).is_empty() and owner.snapshot()==before,"Bad RNG partially constructed the rescue")
		var state:=owner.generate({"state":int(vector.input_state)})
		if state.is_empty():check(false,owner.error);return
		check(state.actors.size()==4 and state.kappa_context==context and state.random_state.state==int(vector.random_state),"Kappa cast order changed factory RNG")
		for id in 4:
			var actor: Dictionary=state.actors[id];var expected: Dictionary=vector.actors[id]
			check(actor.actor_id==id and actor.actor_kind==0 and actor.subtype==0 and actor.hull_catalogue_id==(17 if id==0 else 5),"Kappa changed authored cast order")
			check(actor.factory_position==point(expected.factory_position) and actor.body_pose.origin==point(expected.position) and actor.body_pose==actor.statistics_pose,"Kappa changed factory or authored placement")
			check(actor.body_pose.basis.is_equal_approx(Basis.from_euler(Vector3(0,PI,0),EULER_ORDER_XYZ)),"Kappa lost its authored facing")
			check(actor.cargo==expected.cargo.map(item) and actor.discarded_cargo.is_empty(),"Kappa changed original cargo draws")
			check(actor.discarded_route.waypoints==expected.discarded_route.map(point) and actor.fragments.size()==expected.fragments.size(),"Kappa skipped generated patrol or breakup draws")
			check(actor.script_hostile==(id==0) and not actor.permanent_friendly and actor.mode==5 and not actor.active,"Kappa changed initial mission flags")
			var route: RefCounted=owner.route(id)
			check(route.snapshot()==actor.route and actor.route.loop and actor.route.waypoints==[point(expected.waypoint)],"Kappa patrol lost its independent single looping point")
			var edge: Dictionary=route.advance(point(expected.waypoint)+Vector3(2000,0,0))
			check(not edge.arrived and route.advance(point(expected.waypoint)).wrapped and owner.route(id).snapshot()==actor.route,"Route fork changed its owner or strict arrival boundary")
		check(owner.generate({"state":42}).is_empty() and owner.snapshot()==state and seed==retained_seed,"Construction repeated or changed its caller's inventory")
		var world:=World.new()
		if not world.configure_kappa_rescue(bindings,cat,seed,context,CONDITIONS):check(false,world.error);return
		var generated:=world.generate({"state":int(vector.input_state)})
		if generated.is_empty():check(false,world.error);return
		check(generated.npc_construction==state and generated.random_state.state==int(vector.world_random_state),"Kappa weapon allocation changed actor construction order")
		for id in 4:
			var effect: Dictionary=generated.weapon_effects[id]
			check(effect.discarded_default.flipped==vector.effects[id][0] and effect.primary.flipped==vector.effects[id][1],"Weapon effect pools changed actor-list RNG order")
			check(effect.primary.item_id==0 and effect.primary.resource_id==14600,"Kappa lost original Terran weapon art")
	var player_route:=Route.new()
	if not player_route.configure_kappa_player(bindings):check(false,player_route.error);return
	check(player_route.snapshot().waypoints==[Vector3(40000,-40000,120000),Vector3(-10000,20000,190000)] and not player_route.snapshot().loop,"Player lost the original nonlooping two-point rescue route")
	check(player_route.advance(Vector3(40000,-40000,120000)).index==1 and player_route.advance(Vector3(-10000,20000,190000)).completed,"Player rescue route did not reach its actual end")
	verify_bodies(bindings,cat,seed,context,library)

func verify_bodies(bindings: RefCounted,cat: RefCounted,seed: Dictionary,context: Dictionary,library: RefCounted) -> void:
	for sample in [[0,0.5,104,40,3],[0,1.0,156,40,3],[8,0.5,216,80,7],[8,1.0,324,80,9],[20,0.5,384,140,18],[20,1.0,576,140,24]]:
		var selected:=context.duplicate();selected.rank=sample[0];selected.difficulty=sample[1]
		var owner:=Construction.new()
		if not owner.configure_kappa_rescue(bindings,cat,seed,selected) or owner.generate({"state":42}).is_empty():check(false,owner.error);return
		var weapons:=Weapons.new()
		if not weapons.configure_kappa_rescue(bindings,cat,owner):check(false,weapons.error);return
		var targets:=Rules.combat(bindings,owner.snapshot())
		check(targets.target_memberships==[[-1],[-1],[-1],[-1]] and targets.player_weapon_targets==[0,1,2,3],"Kappa target membership changed")
		for id in 4:
			var actor:=Actor.new()
			if not actor.configure_kappa_rescue(bindings,cat,owner,id):check(false,actor.error);return
			var state:=actor.snapshot()
			check(state.factory_hull==sample[2] and state.max_hull==sample[2] and state.vitals.hull==sample[2] and state.hull_percent==100,"Kappa rank/difficulty hull scaling changed")
			check(state.systems.capacity==sample[3] and state.systems.integrity==sample[3] and state.systems.recovery_ms==15000 and not state.systems_disabled,"Kappa systems initialization changed")
			check(not state.active and state.actor_mode==5 and not state.permanent_friendly and state.script_hostile==(id==0) and state.hostile==(id==0),"Kappa dormant or persistent flags changed")
			check(state.vitals.armor==0 and state.vitals.shield==0.0 and not actor.collision_context().eligible,"Dormant Kappa actor gained invented pools or collision eligibility")
			var gun: Dictionary=weapons.snapshot().actors[id]
			check(gun.definition.damage==sample[4] and gun.definition.interval_ms==558 and gun.definition.projectile_capacity==4 and gun.definition.lifetime_ms==3000,"Kappa gun scaling or timing changed")
			check(gun.definition.item_id==0 and gun.definition.model_resource_id==6754 and not gun.audio.is_empty(),"Kappa gun lost its original resources")
		if sample[0]==0 and sample[1]==0.5:verify_frames(bindings,cat,owner,library)

func verify_frames(bindings: RefCounted,cat: RefCounted,owner: RefCounted,library: RefCounted) -> void:
	var actors:=[];var ai:=[]
	for id in 4:
		var actor:=Actor.new();var guidance:=Guidance.new()
		if not actor.configure_kappa_rescue(bindings,cat,owner,id) or not guidance.configure_kappa_rescue(bindings,cat,owner,id):check(false,actor.error+guidance.error);return
		actors.append(actor);ai.append(guidance)
	var state: Dictionary=actors[0].snapshot()
	check(not actors[0].systems_hit(80).accepted and actors[0].snapshot()==state,"EMP damaged a dormant actor")
	var player:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,"pose":Transform3D.IDENTITY,"active":true,"hull":150,"special_flight":false,"targeting_blocked":true,"alternate_position":null}
	var random_state: Dictionary=owner.snapshot().random_state
	# A neutral guard cannot proximity-activate, but its unblocked target can
	# activate it in mode dispatch; movement waits until the following frame.
	player.pose.origin=actors[1].snapshot().pose.origin+Vector3(1000,0,0)
	var guard: Dictionary=actors[1].snapshot()
	var decision: Dictionary=ai[1].update(16,guard,guard.body_pose,player,random_state,observations(actors))
	if decision.is_empty():check(false,ai[1].error);return
	check(decision.holding and decision.activation=="" and not decision.travel_enabled and decision.node_draw_requested and actors[1].apply_kappa_guidance(decision),"Neutral guard acquired hostile proximity activation or became hidden")
	player.targeting_blocked=false
	decision=ai[1].update(16,guard,guard.body_pose,player,decision.random_state,observations(actors))
	if decision.is_empty():check(false,ai[1].error);return
	check(decision.activation=="target" and decision.holding and not decision.travel_enabled and not decision.fire_requested and actors[1].apply_kappa_guidance(decision),"Target activation moved or fired during dormant mode dispatch")
	check(actors[1].snapshot().active and actors[1].snapshot().actor_mode==1 and not actors[1].snapshot().hostile,"Neutral guard activation changed faction standing")
	# The hostile target uses strict proximity, independently of blocked targeting.
	player.targeting_blocked=true;player.pose.origin=state.pose.origin+Vector3(25000,0,0)
	decision=ai[0].update(16,state,state.body_pose,player,random_state,observations(actors))
	if decision.is_empty():check(false,ai[0].error);return
	check(decision.holding and decision.activation=="","Proximity activated at the strict boundary")
	player.pose.origin=state.pose.origin+Vector3(24999,0,0)
	decision=ai[0].update(16,state,state.body_pose,player,decision.random_state,observations(actors))
	if decision.is_empty():check(false,ai[0].error);return
	check(decision.activation=="proximity" and not decision.holding and decision.travel_enabled and actors[0].apply_kappa_guidance(decision),"Hostile proximity failed same-frame activation")
	var target: RefCounted=actors[0]
	state=target.snapshot()
	var fork: RefCounted=target.fork_for_frame()
	var hit: Dictionary=fork.systems_hit(40)
	check(hit.accepted and hit.disabled_now and fork.snapshot().systems.disabled and not fork.snapshot().systems_disabled and target.snapshot()==state,"Systems pulse mutated its parent or projected the radio flag too early")
	check(fork.snapshot().vitals==state.vitals and fork.snapshot().firing_allowed==state.firing_allowed,"EMP changed ordinary pools or firing permission")
	check(fork.advance_systems(0) and fork.snapshot().systems_disabled,"Actor update failed to project its disabled systems flag")
	var flight:=Flight.new()
	if not flight.configure(bindings,state.body_pose):check(false,flight.error);return
	var before:=flight.snapshot()
	var moved:=flight.advance_with_systems(16,Vector3.RIGHT,4.0,true,true,fork.systems_for_frame())
	if moved.is_empty():check(false,flight.error);return
	check(moved.root_pose==before.root_pose and moved.statistics_pose==before.pose and moved.travel_units==0 and moved.history_cursor!=before.history_cursor and moved.bank!=before.bank,"EMP did not preserve root/statistics motion while advancing bank history")
	var first_disabled:=moved.duplicate(true)
	moved=flight.advance_with_systems(16,Vector3.RIGHT,4.0,true,true,fork.systems_for_frame())
	check(moved.statistics_pose==before.pose and moved.pose!=first_disabled.pose and moved.root_pose==before.root_pose,"Repeated disabled banking changed collision pose")
	player.targeting_blocked=false;player.pose.origin=state.pose.origin+state.pose.basis.z*10000
	var disabled_actors:=observations(actors);disabled_actors[0]=fork.snapshot()
	decision=ai[0].update(16,fork.snapshot(),state.body_pose,player,decision.random_state,disabled_actors)
	check(not decision.is_empty() and decision.fire_requested,"Systems disable invented a weapon-fire suppression gate")
	check(fork.advance_systems(15000) and fork.snapshot().systems_disabled and fork.snapshot().systems.integrity==40,"Systems recovered before the strict integer boundary")
	check(fork.advance_systems(400) and not fork.snapshot().systems_disabled,"Systems failed to recover beyond full capacity")
	moved=flight.advance_with_systems(16,Vector3.RIGHT,4.0,true,true,fork.systems_for_frame())
	check(not moved.is_empty() and moved.root_pose!=before.root_pose and moved.statistics_pose==moved.pose and moved.travel_units==64,"Recovered fighter remained immobilized")
	before=fork.snapshot()
	check(fork.systems_hit(-1).is_empty() and not fork.advance_systems(-1) and fork.snapshot()==before,"Rejected systems input changed actor state")
	var bombs:=Bombs.new()
	if not bombs.configure(bindings,cat,41,[22,86,81,55,41]):check(false,bombs.error);return
	var candidates:=observations(actors).map(func(row):return {"actor_id":row.actor_id,"position":row.position,"active":row.active,"emp_immune":row.scenery})
	var muzzle:=Transform3D(Basis.IDENTITY,state.position-Vector3(0,0,400))
	check(not bombs.advance(1,candidates).is_empty() and bombs.trigger(muzzle,1,candidates).get("action")=="launched","Installed EMP component did not launch")
	var pulse:=bombs.trigger(muzzle,0,candidates)
	if pulse.is_empty():check(false,bombs.error);return
	check(pulse.action=="detonated" and pulse.blast.hits.size()==1 and pulse.blast.hits[0].actor_id==0 and pulse.blast.hits[0].system_damage==80,"Original EMP pulse missed the constructed target or hit dormant escorts")
	hit=target.systems_hit(pulse.blast.hits[0].system_damage)
	check(hit.accepted and hit.disabled_now and target.snapshot().vitals==state.vitals and target.advance_systems(0) and target.snapshot().systems_disabled,"EMP pulse did not disable the actual fighter without hull damage")

	verify_radio(bindings,cat,library,actors)

func verify_radio(bindings: RefCounted,cat: RefCounted,library: RefCounted,actors: Array) -> void:
	if not library.select_language("gb"):check(false,library.error);return
	var resources:=RadioResources.new();var radio:=Radio.new();var rescue:=Rescue.new();var route:=Route.new()
	if not resources.prepare(library,bindings,null,21) or not radio.configure(bindings,library,resources.line_counts,21) or not rescue.configure(bindings) or not route.configure_kappa_player(bindings):check(false,resources.error+radio.error+rescue.error+route.error);return
	if route.advance(Vector3(40000,-40000,120000)).is_empty():check(false,route.error);return
	var activated:=false;var pulsed:=false
	var bombs:=Bombs.new()
	if not bombs.configure(bindings,cat,41,[22,86,81,55,41]) or not actors[0].advance_systems(15400):check(false,bombs.error+actors[0].error);return
	for now in range(0,90001,500):
		for actor in actors:
			if not actor.advance_systems(500):check(false,actor.error);return
		# Repeat the actual EMP action after the kidnapper's demand. Recovery
		# continues with the radio clock, so the earlier pulse cannot stand in
		# for a freshly disabled ship at the last transmission.
		if radio.snapshot().finished[3] and not pulsed:
			var victim: Dictionary=actors[0].snapshot()
			var candidates:=[{"actor_id":0,"position":victim.position,"active":victim.active,"emp_immune":victim.scenery}]
			var pose:=Transform3D(Basis.IDENTITY,victim.position-Vector3(0,0,400))
			if bombs.advance(1,candidates).is_empty() or bombs.trigger(pose,1,candidates).get("action")!="launched":check(false,bombs.error);return
			var pulse:=bombs.trigger(pose,0,candidates)
			if pulse.is_empty() or pulse.blast.hits.is_empty():check(false,bombs.error);return
			var hit: Dictionary=actors[0].systems_hit(pulse.blast.hits[0].system_damage)
			check(hit.get("disabled_now",false) and actors[0].advance_systems(0),"Radio rescue did not receive a fresh EMP disable")
			pulsed=true
		var rows:=observations(actors)
		var targets:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":21,"route_index":int(route.snapshot().index),
			"player_targets":rows.map(func(row):return {"scenery":row.scenery,"active":row.active,"friendly":row.permanent_friendly,"systems_disabled":row.systems_disabled,"current_hull":row.vitals.hull})}
		radio.step_kappa_rescue(now,targets)
		var combat:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":21,"actors":rows}
		if not radio.error.is_empty() or not rescue.advance(radio,combat):check(false,radio.error+rescue.error);return
		if not rescue.snapshot().force_hostile_actor_ids.is_empty():
			check(rescue.snapshot().force_hostile_actor_ids==[1,2,3] and not activated,"Rescue changed or repeated its authored escort cue")
			activated=true
		for actor in actors:
			if not actor.apply_kappa_hostile_cue(rescue) or not actor.refresh_hostility():check(false,actor.error);return
		if rescue.snapshot().completion_ready:break
	check(activated and pulsed and rescue.snapshot().completion_ready and not rescue.snapshot().failure_ready,"Actual generated targets, waypoint and EMP did not satisfy the rescue radio")
	check(radio.snapshot().finished==[true,true,true,true,true],"The rescue skipped an original radio event")
	check(actors.all(func(actor):return actor.snapshot().script_hostile and actor.snapshot().hostile and not actor.snapshot().permanent_friendly),"Mission hostility did not persist after the cue")

func observations(actors: Array) -> Array:return actors.map(func(actor):return actor.snapshot())
func point(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
func item(value: Array) -> Dictionary:return {"item_id":int(value[0]),"quantity":int(value[1])}
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

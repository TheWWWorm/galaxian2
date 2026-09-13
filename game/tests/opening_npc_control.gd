extends SceneTree
const NpcControl = preload("res://src/simulation/opening_npc_control.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Guns = preload("res://src/simulation/opening_npc_weapons.gd")
const Holding = preload("res://src/content/npc_holding_definitions.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("Opening NPC control checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, path: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var control := NpcControl.new()
	var definition: Dictionary = bindings.opening_actors.npc_initialization.get("holding",{})
	if definition.is_empty():
		check(not control.configure(bindings,catalogues,0.5) and control.snapshot().is_empty(),"Legacy pack invented holding control")
		return
	check(control.configure(bindings,catalogues,0.5),control.error)
	var architecture := "armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	var extent := 0
	for span in definition.provenance.values(): extent=maxi(extent,int(span.offset)+int(span.bytes))
	check(Holding.validate(definition,extent,architecture).is_empty(),"Holding provenance rejected")
	for key in definition:
		var bad := definition.duplicate(true);bad.erase(key)
		check(not Holding.parameters(bad),"Missing holding parameter accepted: "+key)
	for key in definition.provenance:
		var bad := definition.duplicate(true);bad.provenance[key].bytes+=1
		check(not Holding.validate(bad,extent,architecture).is_empty(),"Changed holding extent accepted")
	var combat := Combat.new();check(combat.configure(bindings,catalogues,0.5),combat.error)
	var weapons := Guns.new();check(weapons.configure(bindings,catalogues),weapons.error)
	var poses := []
	for id in 3:
		poses.append(Transform3D(Basis.IDENTITY,Vector3(0,0,-1000*id)))
		check(combat.set_pose(id,poses[id]),combat.error)
	var player := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"pose":Transform3D(Basis.IDENTITY,Vector3(0,0,10000)),"active":true,"hull":9999999,
		"special_flight":false,"targeting_blocked":true}
	var random := Random.new();random.seed_from(4)
	var seed := random.snapshot()
	var original: Dictionary = control.snapshot()
	var original_bodies: Dictionary = combat.snapshot()
	var original_guns: Dictionary = weapons.snapshot()
	var frame := control.evaluate(combat,weapons,5000,player,seed)
	if frame.is_empty(): check(false,control.error);return
	check(control.snapshot()==original and combat.snapshot()==original_bodies and weapons.snapshot()==original_guns,"Evaluation mutated its input owners")
	for row in frame.actors:
		check(row.decision.holding and not row.decision.fire_requested and not row.decision.travel_enabled and row.movement.is_empty(),"Holding NPC moved or fired")
		check(frame.controller.snapshot().actors[row.actor_id].guidance.fire_desired,"Holding selection was incorrectly suppressed by player targeting state")
	var expected_bodies := original_bodies.duplicate(true)
	if not bindings.opening_actors.npc_initialization.get("hostility",{}).is_empty():
		for actor in expected_bodies.actors: actor.hostile=true
	check(frame.random_state==seed and frame.combat.snapshot()==expected_bodies and frame.weapons.snapshot()==original_guns,"Holding changed state beyond its source hostility refresh")
	control=frame.controller;combat=frame.combat;weapons=frame.weapons
	frame=control.evaluate(combat,weapons,1,player,frame.random_state)
	check(not frame.is_empty(),control.error)
	for _id in 3: random.next_int(100);random.next_int(100)
	check(frame.random_state==random.snapshot(),"Holding RNG did not run in three-actor selection order")
	for row in frame.controller.snapshot().actors:
		check(row.guidance.selection_elapsed_ms==0 and row.guidance.boost_elapsed_ms==5001 and row.guidance.speed==2 and not row.guidance.boost_active,"Holding reset or applied the accumulated boost timer")
	control=frame.controller;combat=frame.combat;weapons=frame.weapons;seed=frame.random_state
	var unsupported := player.duplicate(true);unsupported.targeting_blocked=false
	check(control.evaluate(combat,weapons,1,unsupported,seed).is_empty(),"Unowned holding self-activation was silently simulated")
	# Cinematic placement can change while held; flight begins at the final pose.
	for id in 3: combat.set_pose(id,Transform3D(Basis.IDENTITY,Vector3(0,0,100-1000*id)))
	activate(combat,bindings)
	var before_activation: Dictionary = control.snapshot()
	frame=control.evaluate(combat,weapons,0,player,seed)
	check(not frame.is_empty(),control.error)
	for row in frame.actors:
		check(not row.decision.holding and not row.decision.fire_requested,"Activated source suppression was ignored")
		check(row.movement.root_pose.origin==combat.snapshot().actors[row.actor_id].pose.origin,"Flight started at a stale cinematic pose")
	for row in before_activation.actors:
		check(row.guidance.boost_elapsed_ms==5001,"Activation reset precombat state")
	# Independent source draws: selection consumed six values, then each NPC
	# checks its already-overdue boost on the zero-duration activation pass.
	for _id in 3:
		if random.next_int(100)<5: random.next_int(3000)
	check(frame.random_state==random.snapshot(),"Activation boost did not continue the shared generator")
	control=frame.controller;combat=frame.combat;weapons=frame.weapons;seed=frame.random_state
	player.targeting_blocked=false
	weapons.advance(1) # The world weapon pass occurs before this actor pass.
	var before: Dictionary = combat.snapshot()
	frame=control.evaluate(combat,weapons,16,player,seed)
	check(not frame.is_empty(),control.error)
	for row in frame.actors:
		check(row.firing.actors[0].outcome.fired,"Acquired NPC did not fire")
		var shot: Dictionary = row.firing.actors[0].outcome.projectile
		check(shot.position==before.actors[row.actor_id].pose.origin,"NPC fired after moving")
		check(row.movement.root_pose.origin.z>shot.position.z,"NPC did not travel after firing")
		check(frame.weapons.snapshot().actors[row.actor_id].projectiles.slots[0].position==shot.position,"Actor pass advanced projectiles a second time")
	# Continue the returned owners across multiple selection/weapon intervals.
	for tick in 600:
		control=frame.controller;combat=frame.combat;weapons=frame.weapons;seed=frame.random_state
		check(not weapons.advance(16).is_empty(),weapons.error)
		frame=control.evaluate(combat,weapons,16,player,seed)
		if frame.is_empty(): check(false,"Repeated actor pass: "+control.error);return
		for row in frame.controller.snapshot().actors:
			check(row.flight.pose==frame.combat.snapshot().actors[row.actor_id].pose,"Flight/combat poses diverged during repeated actor passes")
	var held_again := Combat.new();held_again.configure(bindings,catalogues,0.5)
	for id in 3: held_again.set_pose(id,frame.combat.snapshot().actors[id].pose)
	check(frame.controller.evaluate(held_again,frame.weapons,0,player,frame.random_state).is_empty(),"Active controller accepted a stale holding owner")
	check_rollback(bindings,catalogues,player,seed)
	print(library.manifest.profile.edition,": holding clocks, ordered RNG, activation, old-pose firing and atomic actor pass verified")

func activate(combat: RefCounted, bindings: RefCounted) -> void:
	var flags := [];flags.resize(bindings.opening_dialogue.events.size());flags.fill(false);flags[7]=true
	check(combat.update(combat.snapshot(),3,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"finished":flags}),combat.error)

func check_rollback(bindings: RefCounted, catalogues: RefCounted, player: Dictionary, seed: Dictionary) -> void:
	var control := NpcControl.new();control.configure(bindings,catalogues,0.5)
	var combat := Combat.new();combat.configure(bindings,catalogues,0.5)
	var weapons := Guns.new();weapons.configure(bindings,catalogues);weapons.advance(1)
	for id in 3: combat.set_pose(id,Transform3D(Basis.IDENTITY,Vector3(0,10000,-10000-id*1000) if id<2 else Vector3.ZERO))
	activate(combat,bindings)
	control._guidance[2]._state.selection_elapsed_ms=4000
	player=player.duplicate(true);player.pose.origin=Vector3(0,10000,0)
	var saved: Dictionary = control.snapshot();var bodies: Dictionary = combat.snapshot();var guns: Dictionary = weapons.snapshot()
	# The last actor snaps vertically onto its old up axis after the prior two
	# have fired/moved and its selection consumed RNG. Degenerate flight fails.
	check(control.evaluate(combat,weapons,2000,player,seed).is_empty(),"Singular final-actor motion was accepted")
	check(control.snapshot()==saved and combat.snapshot()==bodies and weapons.snapshot()==guns,"Late actor failure retained earlier motion, firing or clocks")
	check(not combat.set_pose(99,Transform3D.IDENTITY) and combat.snapshot()==bodies,"Unknown actor pose mutated combat")
	check(control.evaluate(combat,weapons,-1,player,seed).is_empty(),"Negative actor time accepted")
	check(control.evaluate(combat,weapons,1,player,{}).is_empty(),"Invalid shared RNG accepted")
	check(not control.configure(null,catalogues,0.5) and control.snapshot().is_empty(),"Failed control configuration retained owners")

func check(condition: bool, message: String) -> void:
	if not condition: failures+=1;push_error(message)

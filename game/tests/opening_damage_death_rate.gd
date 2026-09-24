extends SceneTree
## Source-generated opening wreck and genuine particle owners at 1 ms frames.
## The connected opening-session test covers the player contact and presentation.
const Bindings=preload("res://src/content/resource_bindings.gd")
const Library=preload("res://src/content/library.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Death=preload("res://src/simulation/npc_destruction.gd")
const Particles=preload("res://src/simulation/opening_damage_particles.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if args.size()!=3 or not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):
		printerr("setup: ",lib.error," ",bindings.error," ",cat.error);quit(1);return
	var source:=Construction.new();var resources:=Resources.new()
	if not source.configure(bindings,cat) or not resources.configure(lib,bindings):
		printerr("sources: ",source.error," ",resources.error);quit(1);return
	var constructed: Dictionary=source.generate({"state":280936762154123})
	if constructed.is_empty():printerr("construction: ",source.error);quit(1);return
	var death:=Death.new()
	if not death.configure(bindings,resources,0,Transform3D.IDENTITY,0.375,constructed.actors[0].fragments):
		printerr("death: ",death.error);quit(1);return
	var combat:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"actors":[]}
	for id in 3:combat.actors.append({"actor_id":id,"pose":Transform3D.IDENTITY,"actor_mode":5,"max_hull":100,"vitals":{"hull":100}})
	var particles:=Particles.new()
	if not particles.configure(bindings,combat,42):printerr("particles: ",particles.error);quit(1);return
	var invalid: Dictionary=combat.duplicate(true)
	var scaled:=Transform3D.IDENTITY;scaled.basis.x*=2.0
	invalid.actors[0].pose=scaled
	var quiet:=[]
	for id in 3:quiet.append({"actor_id":id,"decision":{"holding":true},"movement":{}})
	var initial: Dictionary=particles.snapshot()
	if particles.finish_npc_pass(invalid,invalid,quiet,0,1.0) or particles.snapshot()!=initial:
		printerr("Scaled combat pose bypassed the rigid particle boundary");quit(1);return
	combat.actors[0].actor_mode=1;combat.actors[0].vitals.hull=0
	var rng:={"state":25214903917}
	var broke_up:=false
	for tick in 4000:
		var before: Dictionary=combat.duplicate(true)
		var delta:=0 if tick==0 else 1
		if not particles.advance(Transform3D.IDENTITY,delta):printerr("particle manager ",tick,": ",particles.error);quit(1);return
		var death_step: Dictionary=death.advance(delta,rng)
		if death_step.is_empty():printerr("death step ",tick,": ",death.error);quit(1);return
		rng=death_step.random_state
		if not Flight.rigid_pose(death_step.state.pose):printerr("death pose lost orthogonality at step ",tick);quit(1);return
		combat.actors[0].pose=death_step.state.pose
		combat.actors[0].actor_mode=death_step.state.mode
		var events:=[]
		for id in 3:
			events.append({"actor_id":id,"decision":{"dying":id==0},"movement":{},"destruction":death_step if id==0 else {}})
		if not particles.finish_npc_pass(before,combat,events,delta,1.0):
			printerr("particle step ",tick,": ",particles.error," mode ",combat.actors[0].actor_mode," determinant ",combat.actors[0].pose.basis.determinant()," rigid ",Flight.rigid_pose(combat.actors[0].pose)," root determinant ",particles.npc_root(0).basis.determinant()," root rigid ",Flight.rigid_pose(particles.npc_root(0)))
			quit(1);return
		if not Flight.rigid_pose(particles.npc_root(0)):printerr("trail root lost orthogonality at step ",tick);quit(1);return
		if death_step.state.phase=="explosion":
			broke_up=death_step.breakup and tick==1861
			break
	if not broke_up:printerr("High-rate opening wreck did not reach its single original breakup");quit(1);return
	print("Opening damage high-rate death: pass")
	quit(0)

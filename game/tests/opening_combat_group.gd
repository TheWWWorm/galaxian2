extends SceneTree
const Group = preload("res://src/simulation/opening_combat_group.gd")
const Timeline = preload("res://src/simulation/opening_timeline.gd")
const Definitions = preload("res://src/content/npc_activation_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	var group := Group.new()
	check(not group.update({},0,{}) and group.snapshot().is_empty(),"Unconfigured group updated")
	check(not group.configure(null,null,0.5),"Missing content accepted")
	check(not group.record_contact(0,Vector3.ONE),"Unconfigured group accepted contact metadata")
	var data := {"after_event_finished":7,"phase":3,"actor_ids":[0,1,2],"active":true,"actor_mode":1,"spatial_half_extent":50000}
	check(Definitions.parameters(data),"Valid activation rejected")
	for key in data:
		var bad := data.duplicate(true)
		bad.erase(key)
		check(not Definitions.parameters(bad),"Missing activation field accepted: "+key)
	for ids in [[],[0,0],[true],[32],[-1],[1.5]]:
		var bad := data.duplicate(true)
		bad.actor_ids=ids
		check(not Definitions.parameters(bad),"Invalid activation actor set accepted")
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3): check_profile(args[index],args[index+1])
	print("Opening combat group checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, binding_path: String) -> void:
	var library := Library.new()
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(binding_path,library.manifest) or not catalogues.open(library) or not library.select_language("gb"):
		check(false,library.error+bindings.error+catalogues.error);return
	var counts := []
	counts.resize(23);counts.fill(1)
	var timeline := Timeline.new()
	check(timeline.configure(bindings,catalogues,library,counts,0.5),timeline.error)
	if timeline.snapshot().is_empty():return
	var group := Group.new()
	if bindings.opening_actors.get("npc_initialization",{}).get("activation",{}).is_empty():
		check(not group.configure(bindings,catalogues,0.5),"Legacy pack invented activation")
		check(not timeline.snapshot().has("combat"),"Legacy timeline invented combat")
		print(library.manifest.profile.edition,": legacy timeline preserved without activation")
		return
	var activation: Dictionary = bindings.opening_actors.npc_initialization.activation
	var architecture := "armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	check(Definitions.validate(activation,64000000,architecture).is_empty(),"Source activation provenance rejected")
	for key in activation.provenance:
		var bad: Dictionary = activation.duplicate(true)
		bad.provenance[key].bytes+=1
		check(not Definitions.validate(bad,64000000,architecture).is_empty(),"Malformed activation extent accepted")
	check(group.configure(bindings,catalogues,0.5),group.error)
	var first: Dictionary = timeline.snapshot()
	check(group.update(first.scene,0,first.radio),group.error)
	check(not group.normal_hit(0,1).accepted,"Initial inactive actor accepted damage")
	var before: Dictionary = group.snapshot()
	check(not group.update(first.scene,3,first.radio) and group.snapshot()==before,"Activation bypassed radio completion or partially committed")
	var radio: Dictionary = first.radio.duplicate(true)
	radio.finished[7]=true
	# An invalid final actor must not move or activate earlier actors.
	var bad_scene: Dictionary = first.scene.duplicate(true)
	bad_scene.actors[0].position=Vector3.ZERO
	bad_scene.actors[2].position=Vector3(INF,0,0)
	check(not group.update(bad_scene,3,radio) and group.snapshot()==before,"Failed group update partially committed")
	check(group._actors[0].set_permissions(false,false,false),"Could not set explicit permissions")
	check(group.update(first.scene,3,radio),group.error)
	var active: Dictionary = group.snapshot()
	check(active.activated and active.actors[0].active and not active.actors[0].damage_allowed and not active.actors[0].firing_allowed,"Activation overwrote independent permissions")
	for actor in active.actors:
		check(actor.active and actor.actor_mode==1 and actor.spatial_half_extent==50000,"Source activation fields lost")
	check(group._actors[0].set_permissions(false,true,true),"Could not deactivate actor after cue")
	check(group.update(first.scene,4,radio) and not group.snapshot().actors[0].active,"Repeated phase update replayed activation")
	var fork: RefCounted = group.fork_for_frame()
	check(fork.record_contact(1,Vector3(1,2,30)),fork.error)
	check(fork.snapshot().actors[1].contact and fork.snapshot().actors[1].impact_vector==Vector3(-1,-2,-30),"Group lost actor contact metadata")
	check(not group.snapshot().actors[1].contact and group.snapshot().actors[1].impact_vector==Vector3.ZERO,"Group fork leaked contact metadata")
	check(fork.normal_hit(1,150).destroyed_now and group.snapshot().actors[1].vitals.hull==150,"Fork leaked damage")
	check(fork.update(first.scene,4,radio) and fork.snapshot().actors[1].vitals.hull==0,"Scene sync resurrected actor")
	check(fork.snapshot().actors[1].contact and fork.snapshot().actors[1].impact_vector==Vector3(-1,-2,-30),"Group scene sync erased contact metadata")
	var contact_snapshot: Dictionary = fork.snapshot()
	for id in [-1,3,true,1.0,null]:
		check(not fork.record_contact(id,Vector3.ZERO) and fork.snapshot()==contact_snapshot,"Invalid actor ID changed group contact state")
	check(not fork.record_contact(1,Vector3.INF) and fork.snapshot()==contact_snapshot,"Invalid velocity changed group contact state")
	before=group.snapshot()
	check(not group.update(first.scene,2,radio) and group.snapshot()==before,"Regressing phase changed group")
	radio.binding_id="d".repeat(64)
	check(not group.update(first.scene,4,radio) and group.snapshot()==before,"Cross-binding radio activated actors")
	var phases := {}
	var activation_count := 0
	for frame in 700:
		var previous: Dictionary = timeline.snapshot()
		if previous.radio.finished[7] and not previous.combat.activated:
			check(timeline.update(100,true,true),timeline.error)
			check(timeline.snapshot().combat==previous.combat and timeline.snapshot().elapsed_ms==previous.elapsed_ms,"Paused frame activated or moved combat")
		check(timeline.update(100,true,false),timeline.error)
		var state: Dictionary = timeline.snapshot()
		phases[state.camera.shot.phase]=true
		if state.combat.activated and not previous.combat.activated:
			activation_count+=1
			check(previous.radio.finished[7] and state.camera.shot.phase==3,"Activation used same-frame completion or wrong phase")
			check(timeline._sequence._combat.normal_hit(0,6).accepted,"Active timeline actor refused ordinary damage")
		for id in 3:
			var actor: Dictionary = timeline.snapshot().combat.actors[id]
			check(actor.active==state.combat.activated,"Group activity diverged")
			check(actor.position==state.scene.actors[id].position,"Combat placement diverged from source scene")
			var hull := 144 if id==0 and state.combat.activated else 150
			check(actor.vitals.hull==hull and timeline.snapshot().scene.actors[id].current_hull==hull,"Live hull lost between combat and scene")
		if state.radio.finished[8] and state.camera.shot.phase==4:break
	check(phases.size()==5 and activation_count==1 and not timeline.snapshot().radio.started[9],"Opening activation changed supported boundary")
	print(library.manifest.profile.edition,": source activation once after radio 7; paused/atomic frames, live hull and five phases verified")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)

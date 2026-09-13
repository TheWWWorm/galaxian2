extends SceneTree
const Actor = preload("res://src/simulation/opening_combat_actor.gd")
const Geometry = preload("res://src/simulation/ordinary_hit_geometry.gd")
const Timeline = preload("res://src/simulation/opening_timeline.gd")
const Definitions = preload("res://src/content/npc_initialization_definitions.gd")
const InitialFixture = preload("res://tests/opening_actor_fixture.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func definition() -> Dictionary:
	return {"ordinary_half_extent":900,"special_half_extent":600,"special_difficulty":2.5,
		"initial_armor":0,"initial_shield":0.0,"initial_active":true,"initial_damage_allowed":true,
		"initial_firing_allowed":true,"is_player":false,"initial_special_impact_state":false,
		"initial_collision_enabled":true,"initial_point_geometry":false}

func setup() -> Dictionary:
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	bindings.base_content_id = "a".repeat(64)
	bindings.binding_id = "b".repeat(64)
	catalogues.content_id = bindings.base_content_id
	catalogues.tables = {"ships":[{},{}]}
	bindings.ship_model_resources = [100,101]
	for id in [100,101]:
		var path := "resources/data/meshes/example%d.aem" % id
		bindings.records[id] = [{"resource":path,"kind":"mesh","registration_type":4}]
		bindings.base_files[path] = {"kind":"mesh"}
	bindings.opening_actors = InitialFixture.definition()
	bindings.opening_actors.npc_initialization = definition()
	return {"bindings":bindings,"catalogues":catalogues}

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3): check_profile(args[index],args[index+1])
	print("Opening combat actor checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_synthetic() -> void:
	var fixture := setup()
	var actor := Actor.new()
	check(actor.snapshot().is_empty() and actor.normal_hit(1).is_empty() and actor.collision_context().is_empty(),"Unconfigured actor accepted combat work")
	check(not actor.record_contact(Vector3.ONE),"Unconfigured actor accepted contact metadata")
	check(actor.configure(fixture.bindings,fixture.catalogues,1,2.5),actor.error)
	var initial: Dictionary = actor.snapshot()
	check(initial.hull_catalogue_id==1 and initial.vitals=={"hull":321,"armor":0,"shield":0.0} and initial.half_extent==600,"Source actor initialization or difficulty lost")
	check(initial.pose==Transform3D(Basis.IDENTITY,initial.position),"Fresh statistics lost their default identity basis")
	check(not initial.has("max_hull"),"Unverified maximum hull inferred")
	check(not initial.contact and initial.impact_vector==Vector3.ZERO,"Fresh NPC contact metadata is not clear")
	initial.vitals.hull=0
	check(actor.snapshot().vitals.hull==321,"Snapshot changed actor hull")
	check(actor.configure(fixture.bindings,fixture.catalogues,1,2.50000001) and actor.snapshot().half_extent==600,"Difficulty comparison ignored source float rounding")
	check(actor.configure(fixture.bindings,fixture.catalogues,1,2.5001) and actor.snapshot().half_extent==900,"Difficulty selector used approximate equality")
	var pose := Transform3D(Basis(Vector3.UP,Vector3.BACK,Vector3.RIGHT),Vector3(100,200,300))
	check(actor.set_pose(pose),actor.error)
	check(actor.snapshot().pose==pose and actor.collision_context().center==pose.origin,"Pose and collision center diverged")
	var context: Dictionary = actor.collision_context()
	check(context.eligible,"Living active NPC ineligible")
	check(actor.set_permissions(false,true,true),actor.error)
	var denied: Dictionary = actor.normal_hit(321)
	check(not denied.accepted and actor.snapshot().vitals.hull==321 and not actor.collision_context().eligible,"Inactive target accepted damage or collision")
	check(actor.set_permissions(true,false,false),actor.error)
	check(actor.collision_context().eligible and not actor.normal_hit(321).accepted,"Damage gate incorrectly removed geometry or allowed damage")
	check(not actor.snapshot().firing_allowed,"Explicit firing permission lost")
	check(actor.set_permissions(true,true,true),actor.error)
	var lethal: Dictionary = actor.normal_hit(321)
	check(lethal.destroyed_now and not actor.normal_hit(321).accepted and not actor.collision_context().eligible,"Repeated death or dead-target eligibility")
	check(not actor.snapshot().contact,"Damage accounting invented a geometry contact")
	check(actor.record_contact(Vector3(0.0,-0.0,25.0)),actor.error)
	var impact: Dictionary = actor.snapshot()
	check(impact.contact and impact.impact_vector==Vector3(0,0,-25) and impact.vitals.hull==0,"Postcontact metadata changed dead pools or normalized velocity")
	var impact_bits := PackedFloat32Array([impact.impact_vector.x,impact.impact_vector.y]).to_byte_array()
	check(impact_bits.decode_u32(0)==0x80000000 and impact_bits.decode_u32(4)==0,"Contact did not negate signed zero")
	var contact_copy: RefCounted = actor.fork_for_frame()
	check(contact_copy.snapshot()==impact and contact_copy.record_contact(Vector3.ONE),"Fork lost NPC contact state")
	check(actor.snapshot()==impact and contact_copy.snapshot().impact_vector==-Vector3.ONE,"Fork contact metadata aliases its source")
	impact.contact=false;impact.impact_vector=Vector3.INF
	check(actor.snapshot().contact and actor.snapshot().impact_vector==Vector3(0,0,-25),"Contact snapshot aliases live metadata")
	check(context.eligible and context.center==pose.origin,"Death changed the detached target context captured for the current slot loop")
	var geometry := Geometry.new()
	check(geometry.bounds(Vector3(100,200,300),Vector3.ZERO,context.center,context.half_extent).hit,"Captured target geometry unavailable for later projectile impact")
	var dead: Dictionary = actor.snapshot()
	for velocity in [null,Vector2.ZERO,[0,0,0],Vector3.INF,Vector3(NAN,0,0)]:
		check(not actor.record_contact(velocity) and actor.snapshot()==dead,"Invalid contact changed NPC metadata")
	for bad in [-1,1.5,true,null]:
		check(actor.normal_hit(bad).is_empty() and actor.snapshot()==dead,"Invalid damage changed body")
	check(not actor.set_permissions(true,1,true) and actor.snapshot()==dead,"Implicit permission changed body")
	check(not actor.set_pose(null) and actor.snapshot()==dead,"Invalid pose changed body")
	check(not actor.set_pose(Transform3D(Basis.IDENTITY,Vector3(INF,0,0))) and actor.snapshot()==dead,"Nonfinite pose accepted")
	var scene := {"base_content_id":fixture.bindings.base_content_id,"binding_id":fixture.bindings.binding_id,
		"actors":[{"actor_id":1,"position":Vector3.ONE}]}
	check(actor.apply_scene(scene) and actor.snapshot().vitals.hull==0,"Scene sync resurrected a dead body")
	var synced: Dictionary = actor.snapshot()
	check(synced.pose.origin==Vector3.ONE,"Position-only scene lost retained orientation")
	check(synced.contact and synced.impact_vector==dead.impact_vector,"Scene synchronization erased live contact metadata")
	for mutation in ["identity","binding","missing","duplicate","position","pose"]:
		var bad := scene.duplicate(true)
		match mutation:
			"identity": bad.base_content_id="d".repeat(64)
			"binding": bad.binding_id="d".repeat(64)
			"missing": bad.actors=[]
			"duplicate": bad.actors.append(bad.actors[0].duplicate(true))
			"position": bad.actors[0].position=Vector3(INF,0,0)
			"pose": bad.actors[0].pose=Transform3D.IDENTITY
		check(not actor.apply_scene(bad) and actor.snapshot()==synced,"Invalid scene partially changed actor: "+mutation)
	for difficulty in [-1,11,NAN,INF,null,true,"normal"]:
		check(not actor.configure(fixture.bindings,fixture.catalogues,0,difficulty) and actor.snapshot().is_empty(),"Invalid difficulty retained actor")
	for id in [-1,2,true,null,1.5]:
		check(not actor.configure(fixture.bindings,fixture.catalogues,id,0.5),"Invalid source actor ID accepted")
	for key in ["is_player","initial_point_geometry","initial_special_impact_state"]:
		fixture.bindings.opening_actors.npc_initialization=definition()
		fixture.bindings.opening_actors.npc_initialization[key]=true
		check(not actor.configure(fixture.bindings,fixture.catalogues,0,0.5),"Unsupported actor path accepted: "+key)
	fixture.bindings.opening_actors.npc_initialization=[]
	check(not actor.configure(fixture.bindings,fixture.catalogues,0,0.5),"Invalid declaration type accepted")
	fixture.bindings.opening_actors.erase("npc_initialization")
	check(not actor.configure(fixture.bindings,fixture.catalogues,0,0.5),"Legacy content invented NPC defaults")
	fixture.bindings.opening_actors.npc_initialization=definition()
	check(actor.configure(fixture.bindings,fixture.catalogues,1,0.5) and not actor.snapshot().contact and actor.snapshot().impact_vector==Vector3.ZERO,"Reconfiguration retained old contact metadata")
	fixture.bindings.base_content_id="c".repeat(64)
	check(not actor.configure(fixture.bindings,fixture.catalogues,0,0.5),"Cross-content actor initialized")
	check_definitions()

func check_definitions() -> void:
	for key in definition():
		var bad := definition()
		bad.erase(key)
		check(not Definitions.parameters(bad),"Missing NPC parameter accepted: "+key)
	for bad_value in [-1,0,1.5,true,10000001]:
		var bad := definition()
		bad.ordinary_half_extent=bad_value
		check(not Definitions.parameters(bad),"Invalid NPC extent accepted")

func check_profile(content: String, binding_path: String) -> void:
	var library := Library.new()
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(binding_path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error); return
	if not bindings.opening_actors.has("npc_initialization"):
		var unsupported := Actor.new()
		check(not unsupported.configure(bindings,catalogues,0,0.5) and unsupported.snapshot().is_empty(),"Legacy pack invented NPC initialization")
		print(library.manifest.profile.edition,": legacy precombat pack loads and reports NPC combat initialization unavailable")
		return
	var data: Dictionary = bindings.opening_actors.npc_initialization
	var architecture: String = "armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	check(Definitions.validate(data,64000000,architecture).is_empty(),"Source initialization provenance rejected")
	for key in data.provenance:
		var bad: Dictionary = data.duplicate(true)
		bad.provenance[key].bytes+=1
		check(not Definitions.validate(bad,64000000,architecture).is_empty(),"Invalid source initialization span accepted")
	for difficulty in [0.0,0.5,1.0,1.5]:
		var actors := []
		for id in 3:
			var actor := Actor.new()
			check(actor.configure(bindings,catalogues,id,difficulty),actor.error)
			if actor.snapshot().is_empty(): continue
			var state: Dictionary = actor.snapshot()
			check(state.vitals=={"hull":150,"armor":0,"shield":0.0},"Source opening NPC pools changed")
			check(state.half_extent==(650 if difficulty==1.5 else 1000),"Source NPC difficulty bounds changed")
			check(state.position==Vector3(50000,50000,50000),"Initial source position changed")
			check(not actor.collision_context().eligible and not state.active and state.firing_allowed,"Opening deactivation or constructor permission lost")
			check(not state.contact and state.impact_vector==Vector3.ZERO,"Source NPC initial contact metadata changed")
			check(not actor.normal_hit(1).accepted,"Opening inactive NPC accepted damage")
			actors.append(actor)
		if actors.size()!=3: continue
		check(actors[0].set_permissions(true,true,true),actors[0].error)
		var result: Dictionary = actors[0].normal_hit(150)
		check(result.destroyed_now and actors[1].snapshot().vitals.hull==150 and actors[2].snapshot().vitals.hull==150,"Damage leaked across source actors")
	print(library.manifest.profile.edition,": three source NPCs initialized across four difficulty values; isolated damage and bounds verified")
	check_timeline(bindings,catalogues,library)

func check_timeline(bindings: RefCounted, catalogues: RefCounted, library: RefCounted) -> void:
	check(library.select_language("gb"),library.error)
	var timeline := Timeline.new()
	var counts := []
	counts.resize(23)
	counts.fill(1)
	check(timeline.configure(bindings,catalogues,library,counts),timeline.error)
	var actors := []
	for id in 3:
		var actor := Actor.new()
		check(actor.configure(bindings,catalogues,id,0.5),actor.error)
		actors.append(actor)
	var phases := {}
	var damage_applied := false
	for frame in 700:
		check(timeline.update(100,true,false),timeline.error)
		var state: Dictionary = timeline.snapshot()
		phases[state.camera.shot.phase]=true
		for id in 3:
			check(actors[id].apply_scene(state.scene),actors[id].error)
			check(actors[id].collision_context().center==state.scene.actors[id].position,"Combat center detached from opening drift/reveal")
			if state.scene.actors[id].has("pose"):
				check(actors[id].snapshot().pose==state.scene.actors[id].pose,"Combat orientation detached from source formation")
		if state.camera.shot.phase==3 and not damage_applied:
			# This explicit test owner supplies the activation; the body does not
			# infer permissions from visibility or camera state.
			check(actors[0].set_permissions(true,true,true),actors[0].error)
			actors[0].normal_hit(6)
			damage_applied=true
		check(actors[0].snapshot().vitals.hull==(144 if damage_applied else 150),"Placement sync overwrote live damage")
		if state.radio.finished[8] and state.camera.shot.phase==4: break
	check(phases.size()==5 and not timeline.snapshot().radio.started[9],"Combat preparation changed precombat phase or radio gates")
	print(library.manifest.profile.edition,": combat bodies follow all five opening phases; scene sync preserves live damage")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)

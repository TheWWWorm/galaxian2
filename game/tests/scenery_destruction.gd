extends SceneTree
const Lifecycle = preload("res://src/simulation/scenery_destruction.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Resources = preload("res://src/content/scenery_effect_resources.gd")
# Independently calculated 48-bit state vectors: seed, seeded state, after one
# bounded draw (19, except seed 65 gives 20), after two draws, quantity.
const RANDOM_CASES := [[54,25214903899,205295271270090,189720021168141,3],
	[65,25214903852,204110170785991,89659670922950,0],
	[108,25214903809,203025929917560,249645925418787,2],
	[137,25214904036,208749713106719,229854467162686,1]]
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1])
	print("Scenery destruction checks: %d failures" % failures)
	quit(1 if failures else 0)

func body_state(bindings: RefCounted, descriptor: Dictionary, item: int, size_class: int, scale := 0.5) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"objects":[{
		"index":0,"item_id":item,"model_id":descriptor.base_model_id,"source_size_value":size_class,"scale":scale,
		"position":Vector3(13,-9,-40),"active":true,"motion_scalar":0.0,"vitals":{"hull":80}}]}

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new();var resources := Resources.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library) or not resources.configure(library,bindings):
		check(false,library.error+bindings.error+catalogues.error+resources.error);return
	for variant in bindings.scenery_effects.variants:
		var descriptor := resources.effect_for_model(int(variant.base_model_id))
		for size_class in [4,5,6,7]:
			for vector in RANDOM_CASES:check_drop(bindings,catalogues,descriptor,size_class,vector)
		check_lifetime(bindings,catalogues,descriptor)
		check_failure(bindings,catalogues,descriptor)
	print(library.manifest.profile.edition,": four effect types, all source classes, exact drop RNG consumption and delayed retirement verified")

func check_drop(bindings: RefCounted, catalogues: RefCounted, descriptor: Dictionary, size_class: int, vector: Array) -> void:
	for item in [int(bindings.scenery_resources.ore_item_ids[0]),164,217]:
		var body := body_state(bindings,descriptor,item,size_class)
		var lifecycle := Lifecycle.new()
		if not lifecycle.configure(bindings,catalogues,body,0,descriptor):check(false,lifecycle.error);return
		var random := {"state":vector[1]}
		var pose := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*0.5),body.objects[0].position)
		body.objects[0].vitals.hull=0
		var before := lifecycle.snapshot()
		var zero := lifecycle.update(0,body,pose,random)
		check(not zero.is_empty() and zero.events.is_empty() and zero.random_state==random and lifecycle.snapshot()==before,"Zero-time update triggered destruction or consumed RNG")
		var original_body: Dictionary=body.duplicate(true)
		var result := lifecycle.update(100,body,pose,random)
		if result.is_empty():check(false,lifecycle.error);return
		check(body==original_body and random.state==vector[1],"Lifecycle mutated its caller's body or RNG state")
		check(result.skip_motion and result.statistics_active,"Trigger tick ran spin or deactivated statistics")
		var snapshot := lifecycle.snapshot()
		check(snapshot.lifecycle.actor_state==3 and snapshot.effect.active and snapshot.effect.elapsed_ms==0,"Trigger consumed effect time or selected the wrong state")
		check(snapshot.effect.pose==pose,"Trigger lost the intact model transform")
		check(result.events.size()==1 and result.events[0].world_scenery_count_delta==-1 and result.events[0].destruction_count_delta==1,"Destruction accounting was lost")
		var cargo: Dictionary=result.events[0].cargo
		if vector[4]==0:
			check(cargo.is_empty() and not snapshot.lifecycle.drop_allowed,"Roll 20 was accepted as cargo")
			check(result.random_state.state==vector[2],"Failed drop consumed a quantity draw")
		else:
			var expected_item: int=(218 if item==217 else item+11) if size_class==7 else item
			check(cargo.item_id==expected_item and cargo.quantity==(1 if size_class==7 else vector[4]),"Source cargo item or quantity changed")
			check(cargo.model_id==(16927 if item==164 else 16926) and cargo.resource==Lifecycle.CargoPaths[1 if item==164 else 0],"Cargo model binding changed")
			check(cargo.pose==Transform3D(Basis.IDENTITY,pose.origin),"Cargo inherited asteroid scale or rotation")
			check(result.random_state.state==vector[2 if size_class==7 else 3],"Cargo branch consumed the wrong number of random draws")
			check(snapshot.lifecycle.drop_allowed,"Successful drop incorrectly cleared source eligibility")
			cargo.quantity=999
			check(lifecycle.snapshot().lifecycle.cargo.quantity!=999,"Event cargo aliases actor-owned cargo")
		var next := lifecycle.update(100,body,pose,result.random_state)
		check(not next.is_empty() and not next.skip_motion and next.events.is_empty() and next.random_state==result.random_state,"Later destruction update repeated accounting, consumed RNG or incorrectly stopped intact-model spin")

func check_lifetime(bindings: RefCounted, catalogues: RefCounted, descriptor: Dictionary) -> void:
	for scale in [0.3,0.5,1.0,2.0]:
		var body := body_state(bindings,descriptor,217,7,scale)
		var lifecycle := Lifecycle.new()
		check(lifecycle.configure(bindings,catalogues,body,0,descriptor),lifecycle.error)
		lifecycle.disable_drop()
		var pose := Transform3D(Basis.from_euler(Vector3(0.2,0.4,-0.3)).scaled(Vector3.ONE*scale),body.objects[0].position)
		var random := {"state":RANDOM_CASES[0][1]}
		var intact := lifecycle.update(100,body,pose,random)
		check(intact.events.is_empty() and not intact.skip_motion and intact.random_state==random,"Intact actor consumed destruction work")
		body.objects[0].vitals.hull=0
		var triggered := lifecycle.update(100,body,pose,random)
		check(triggered.random_state==random and triggered.events[0].cargo.is_empty(),"Disabled drop consumed RNG or created cargo")
		var duration: int=lifecycle.snapshot().effect.duration_ms
		var remaining := duration
		var identity: RefCounted=lifecycle.presentation_clock().presentation_identity()
		while remaining>0:
			var delta := mini(remaining,100);remaining-=delta
			var previous := lifecycle.snapshot()
			var candidate: RefCounted=lifecycle.fork_for_frame()
			var result: Dictionary=candidate.update(delta,body,pose,random)
			check(not result.is_empty() and lifecycle.snapshot()==previous,"Frame candidate changed the accepted lifecycle")
			lifecycle=candidate
			check(result.events.is_empty() and result.statistics_active and not result.skip_motion,"Playback changed accounting, statistics or spin ordering")
			check(lifecycle.presentation_clock().presentation_identity()==identity,"Frame candidate changed logical effect identity")
		check(lifecycle.snapshot().effect.active and lifecycle.snapshot().lifecycle.actor_state==3,"Effect expired at duration equality")
		var before := lifecycle.snapshot()
		lifecycle.update(0,body,pose,random)
		check(lifecycle.snapshot()==before,"Zero-time boundary update changed playback")
		var expired := lifecycle.update(1,body,pose,random)
		check(not lifecycle.snapshot().effect.active and lifecycle.snapshot().lifecycle.actor_state==4 and expired.statistics_active and not expired.skip_motion,"Effect expiry collapsed the later retirement steps")
		var disabled := lifecycle.update(1,body,pose,random)
		check(not disabled.statistics_active and not disabled.skip_motion and lifecycle.snapshot().lifecycle.update_enabled,"Statistics retirement cleared the actor on the same tick")
		body.objects[0].active=disabled.statistics_active
		var retired := lifecycle.update(1,body,pose,random)
		check(retired.skip_motion and not lifecycle.snapshot().lifecycle.update_enabled,"Inactive spent actor was not retired on the following update")
		check(retired.events.is_empty() and retired.random_state==random,"Retirement repeated accounting or used RNG")
		body.objects[0].active=true
		var before_reactivation := lifecycle.snapshot()
		check(lifecycle.update(1,body,pose,random).is_empty() and lifecycle.snapshot()==before_reactivation,"Retired actor was resurrected")
		var presentation: RefCounted=lifecycle.presentation_clock()
		presentation.clear()
		check(not lifecycle.snapshot().is_empty() and lifecycle.presentation_clock().presentation_identity()==identity,"Presentation mutated the simulation's effect clock")

func check_failure(bindings: RefCounted, catalogues: RefCounted, descriptor: Dictionary) -> void:
	var body := body_state(bindings,descriptor,217,7)
	var lifecycle := Lifecycle.new();check(lifecycle.configure(bindings,catalogues,body,0,descriptor),lifecycle.error)
	var pose := Transform3D(Basis.IDENTITY,body.objects[0].position)
	var random := {"state":RANDOM_CASES[0][1]}
	body.objects[0].vitals.hull=0
	var before := lifecycle.snapshot()
	for key in ["identity","hull","ore","impact","position"]:
		var invalid: Dictionary=body.duplicate(true)
		if key=="identity":invalid.binding_id="c".repeat(64)
		elif key=="hull":invalid.objects[0].vitals.hull=-1
		elif key=="ore":invalid.objects[0].item_id=0
		elif key=="impact":invalid.objects[0].motion_scalar=1.0
		else:invalid.objects[0].position=Vector3(INF,0,0)
		check(lifecycle.update(100,invalid,pose,random).is_empty() and lifecycle.snapshot()==before,"Invalid destruction input changed lifecycle: "+key)
	for bad in [-1,int(bindings.frame_clock.max_frame_milliseconds)+1,null,true,"1",NAN]:
		check(lifecycle.update(bad,body,pose,random).is_empty() and lifecycle.snapshot()==before,"Invalid frame duration changed lifecycle")
	check(lifecycle.update(100,body,pose,{}).is_empty() and lifecycle.snapshot()==before,"Missing shared RNG state changed lifecycle")
	var item_count: int=lifecycle._item_count
	lifecycle._item_count=218
	check(lifecycle.update(100,body,pose,random).is_empty() and lifecycle.snapshot()==before,"Failed cargo validation committed the triggered effect or RNG draw")
	lifecycle._item_count=item_count
	check(not lifecycle.update(100,body,pose,random).is_empty(),lifecycle.error)
	check(not lifecycle.configure(bindings,catalogues,body,3,descriptor) and lifecycle.snapshot().is_empty(),"Invalid reconfiguration retained lifecycle state")

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)

extends SceneTree
const Bodies = preload("res://src/simulation/scenery_bodies.gd")
const Resources = preload("res://src/content/scenery_body_resources.gd")
const Fixture = preload("res://tests/scenery_fixture.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Opening = preload("res://src/simulation/opening_scenery.gd")
var failures := 0

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3): check_profile(args[index],args[index+1])
	print("Scenery body checks: %d failures" % failures)
	quit(1 if failures else 0)

func source(radius := 17.0, scale := 0.3) -> Array:
	var bindings: RefCounted = Fixture.make()[0]
	bindings.weapon_parameters={"ordinary_hit_policy":{"additional_damage_property":10,"missing_additional_damage":-1,"nonplayer_damage_scale":1.0,"provenance":{}}}
	var resources := Resources.new()
	resources._state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"radii":{400:radius}}
	var field := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"objects":[{"index":0,"item_id":0,"model_variant":0,"model_id":400,"source_size_value":4,
		"position":Vector3(12,-15,43),"large":false,"scale":scale}]}
	return [bindings,field,resources]

func weapon(pair: Array, damage: int) -> Dictionary:
	return {"base_content_id":pair[0].base_content_id,"binding_id":pair[0].binding_id,
		"item_id":1,"category":0,"kind":0,"damage":damage,"launch_mode":"ordinary",
		"ordinary_hit_policy":{"additional_damage_required":false,"additional_damage":-1,"nonplayer_damage":damage}}

func check_synthetic() -> void:
	var bodies := Bodies.new()
	check(not bodies.configure(null,{},null) and bodies.snapshot().is_empty(),"Missing source accepted")
	check(bodies.collision_context(0).is_empty() and bodies.normal_hit(0,0).is_empty(),"Unconfigured body accepted collision or damage")
	# Independent binary32 reference values; the last case is at an integer
	# boundary where retaining the source rounding stages matters.
	for vector in [[17.0,0.3,3,60],[17.0,0.99999999,11,130],[2001.5699462890625,0.69,966,99],
		[6000.330078125,2.19,9198,249],[3333.300048828125,0.7,1633,100],[14.285715103149414,1.0,10,130]]:
		var pair := source(vector[0],vector[1])
		check(bodies.configure(pair[0],pair[1],pair[2]),bodies.error)
		var row: Dictionary = bodies.snapshot().objects[0]
		check(row.half_extent==vector[2] and row.initial_hull==vector[3],"Source radius/hull rounding changed")
	var pair := source()
	check(bodies.configure(pair[0],pair[1],pair[2]),bodies.error)
	var row: Dictionary = bodies.snapshot().objects[0]
	check(row.vitals=={"hull":60,"armor":0,"shield":0.0} and row.active and row.damage_allowed and row.collision_enabled,"Initial scenery pools or flags changed")
	check(not row.contact and not row.damaged and row.impact_vector==Vector3.ZERO and row.motion_scalar==0.0 and row.hit_feedback==0.0,"Initial scenery feedback changed")
	var before := bodies.snapshot()
	var detached := bodies.snapshot();detached.objects[0].hit_layers.hull=true;detached.objects.clear()
	pair[1].objects[0].position=Vector3.ZERO;pair[2]._state.radii[400]=9999
	check(bodies.snapshot()==before,"Scenery body ownership leaked to input or snapshot")
	check(bodies.collision_context(0).center==Vector3(12,-15,43) and bodies.collision_context(0).half_extent==3,"Scenery collision does not retain authored bounds")
	for amount in [-1,1.5,true,NAN]:
		check(bodies.normal_hit(0,amount).is_empty() and bodies.snapshot()==before,"Invalid damage mutated scenery")
	for id in [-1,1,true,0.0,null]:
		check(bodies.collision_context(id).is_empty() and bodies.weapon_hit(id,weapon(pair,1)).is_empty() and bodies.snapshot()==before,"Invalid scenery identity changed state")
	var wrong := weapon(pair,1);wrong.binding_id="d".repeat(64)
	check(bodies.weapon_hit(0,wrong).is_empty() and bodies.snapshot()==before,"Cross-binding damage accepted")
	wrong=weapon(pair,1);wrong.ordinary_hit_policy.additional_damage_required=true
	check(bodies.weapon_hit(0,wrong).is_empty() and bodies.snapshot()==before,"Unsupported weapon damage accepted")
	check(bodies.set_permissions(0,true,false),bodies.error)
	bodies._rows[0].motion_scalar=7.0
	var denied := bodies.weapon_hit(0,weapon(pair,60))
	check(not denied.accepted and denied.motion_scalar_before==7.0 and denied.motion_scalar_after==0.0,"Denied scenery contact skipped motion prelude")
	check(bodies.collision_context(0).eligible and bodies.snapshot().objects[0].hit_feedback==0.0,"Damage permission incorrectly suppressed geometry or emitted damage feedback")
	check(bodies.record_contact(0,Vector3(1,-2,3)),bodies.error)
	check(bodies.snapshot().objects[0].contact and bodies.snapshot().objects[0].impact_vector==Vector3(-1,2,-3),"Denied contact lost signed unnormalized impact")
	before=bodies.snapshot()
	check(not bodies.record_contact(0,Vector3(INF,0,0)) and bodies.snapshot()==before,"Invalid contact mutated body")
	check(bodies.set_permissions(0,true,true),bodies.error)
	for iteration in 1000: check(bodies.normal_hit(0,0).accepted,"Zero damage rejected")
	row=bodies.snapshot().objects[0]
	check(row.hit_feedback==64.99945068359375 and row.hit_layers.shield and not row.hit_layers.hull and row.damaged,"Accumulated float32 feedback or zero-damage layer changed")
	var fork: RefCounted = bodies.fork_for_frame()
	var killed: Dictionary = fork.weapon_hit(0,weapon(pair,1000))
	check(killed.destroyed_now and fork.has_pending_destruction() and not fork.collision_context(0).eligible,"Zero hull did not establish pending destruction")
	check(fork.snapshot().objects[0].hit_layers.shield and fork.snapshot().objects[0].hit_layers.hull,"New hit cleared an earlier pool marker")
	check(not bodies.has_pending_destruction() and bodies.snapshot().objects[0].vitals.hull==60,"Forked damage changed the original field")
	var pending: Dictionary = fork.snapshot()
	check(not fork.normal_hit(0,1).accepted and fork.snapshot()==pending,"Repeated dead-body hit emitted damage or progressed destruction")
	for invalid in ["identity","order","item","variant","model","size","position","scale","overflow","missing"]:
		pair=source()
		match invalid:
			"identity":pair[1].binding_id="d".repeat(64)
			"order":pair[1].objects[0].index=1
			"item":pair[1].objects[0].item_id=-1
			"variant":pair[1].objects[0].model_variant=4
			"model":pair[1].objects[0].model_id=401
			"size":pair[1].objects[0].source_size_value=8
			"position":pair[1].objects[0].position=Vector3(INF,0,0)
			"scale":pair[1].objects[0].scale=0.0
			"overflow":pair[1].objects[0].scale=1e30
			"missing":pair[2].clear()
		check(not bodies.configure(pair[0],pair[1],pair[2]) and bodies.snapshot().is_empty(),"Invalid configuration retained bodies: "+invalid)

func check_profile(content: String, binding_path: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(binding_path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var resources := Resources.new();var opening := Opening.new();var bodies := Bodies.new()
	if not resources.configure(library,bindings) or not opening.configure(bindings,catalogues,1789100000):
		check(false,resources.error+opening.error);return
	var field := opening.snapshot()
	check(bodies.configure(bindings,field,resources),bodies.error)
	var first := bodies.snapshot()
	check(first.objects.size()==field.objects.size(),"Actual field omitted body targets")
	for index in field.objects.size():
		var context := bodies.collision_context(index)
		check(context.eligible and context.center==field.objects[index].position and context.half_extent>0,"Actual body has wrong center or eligibility")
		check(bodies.normal_hit(index,1).accepted,"Actual intact body rejected ordinary damage")
	check(opening.update(100,Vector3(9000,200,1000)),opening.error)
	check(opening.snapshot().objects[0].position==field.objects[0].position,"Intact spin moved collision center")
	for index in first.objects.size():
		check(bodies.snapshot().objects[index].vitals.hull==first.objects[index].initial_hull-1,"Actual body lost individual damage")
	check(opening.configure(bindings,catalogues,1789100000,true,resources),opening.error)
	check(opening.snapshot().bodies.objects.size()==first.objects.size(),"Opening failed to retain body ownership")
	check(opening._bodies.normal_hit(0,2147483647).destroyed_now,"Opening destruction guard fixture failed")
	var pending := opening.snapshot()
	check(not opening.update(100,Vector3.ZERO) and opening.snapshot()==pending,"Unsupported destruction advanced scenery motion or LOD")
	check(opening.has_pending_destruction(),"Opening lost destruction boundary")
	opening.clear()
	check(opening.snapshot().is_empty() and not opening.has_pending_destruction(),"Opening clear retained bodies")
	print(library.manifest.profile.edition,": ",first.objects.size()," source-bound intact bodies, independent collision and vitals verified")

func check(condition: bool, message: String) -> void:
	if not condition: failures+=1;push_error(message)

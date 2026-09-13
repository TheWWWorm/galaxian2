extends SceneTree
const Detail = preload("res://src/presentation/geometry_detail.gd")
const Group = preload("res://src/presentation/scenery_detail_group.gd")
const SharedGroup = preload("res://src/presentation/ship_detail_group.gd")
const Fixture = preload("res://tests/scenery_fixture.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
var failures := 0

func _initialize() -> void:
	check_selector()
	var bindings: RefCounted = Fixture.make()[0]
	bindings.ship_lod={"threshold_comparison":"greater","maximum_comparison":"greater_or_equal","body_resource_ids":[[1,2]],"child_resource_ids":[[65535,65535]],"distances":[100,200],"maximum_distance":1000,"detail_boundaries":[],"squared_distance_factors":[1.0]}
	bindings.lod_refresh={"initial_milliseconds":1001,"refresh_at_milliseconds":1001,"reset_milliseconds":0,"time_unit":"milliseconds","forced_refresh_resets_clock":false}
	bindings.frame_clock={"time_unit":"milliseconds","max_frame_milliseconds":150}
	check_group(bindings)
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visual triples")
	for index in range(0,args.size()-2,3):
		var library := Library.new();var original := Bindings.new()
		if not library.open(args[index]) or not original.open(args[index+1],library.manifest):
			check(false,library.error+original.error);continue
		check_group(original)
		print(library.manifest.profile.edition+": shared scenery detail scheduling checked")
	print("Scenery detail checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_selector() -> void:
	var selector := Detail.new()
	check(selector.select(0,1).is_empty(),"Unconfigured selector accepted")
	var distances := [100,200,300]
	check(selector.configure(distances,3,0,[],[1.0]),selector.error)
	for index in distances.size():
		var squared: int = distances[index]*distances[index]
		check(selector.select(squared,1)=={"visible":true,"level":index},"Scenery strict threshold equality changed")
		check(selector.select(squared+1,1)=={"visible":true,"level":index+1},"Scenery strict threshold crossing changed")
	check(selector.select(1000000000000,1)=={"visible":true,"level":3},"Scenery acquired a maximum-distance cull")
	distances[0]=1
	check(selector.select(10000,1).level==0,"Selector aliases caller thresholds")
	var copy := selector.fork_for_frame()
	check(selector.configure([10,20,30],2,100,[],[1.0]) and selector.select(10000,1)=={"visible":false,"level":-1},"Optional maximum-distance equality changed")
	check(copy.select(10000,1).level==0,"Forked selector changed with original")
	check(selector.configure([100,200,300],3,0,[0.25,0.5],[0.25,0.5,1.0]),selector.error)
	check(selector.select(4000,0.25).level==1 and selector.select(4000,0.2501).level==0,"Shared detail band equality changed")
	check(selector.select(7000,0.5).level==1 and selector.select(7000,0.5001).level==0,"Shared upper detail band changed")
	for invalid in [[-1,1],[NAN,1],[true,1],[0,INF],[0,true],[0,1e100]]:check(selector.select(invalid[0],invalid[1]).is_empty(),"Invalid distance or detail accepted")
	for invalid in [[],[0,1],[2,1],[1,1],[1,true],[1,NAN],[1,1000001]]:
		check(not selector.configure(invalid,0,0,[],[1.0]) and not selector.is_configured(),"Invalid geometry thresholds retained configuration")
	for invalid in [-1,1,300,1000001]:check(not selector.configure([100,200,300],3,invalid,[],[1.0]),"Invalid geometry maximum accepted")
	for invalid in [-1,4]:check(not selector.configure([100,200,300],invalid,0,[],[1.0]),"Invalid alternate count accepted")
	for invalid in [[[],[]],[[0.5],[1.0]],[[0.5,0.4],[0.25,0.5,1.0]],[[NAN],[0.5,1.0]],[[],[true]],[[],[0.0]]]:
		check(not selector.configure([100],1,0,invalid[0],invalid[1]),"Invalid shared detail bands accepted")

func make_field(bindings: RefCounted) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"large_count":1,"objects":[
		{"index":0,"large":true,"position":Vector3(70000,0,0),"model_variant":0,"model_id":int(bindings.scenery_resources.model_ids[0])},
		{"index":1,"large":false,"position":Vector3(70000,0,0),"model_variant":3,"model_id":int(bindings.scenery_resources.model_ids[3])}]}

func check_group(bindings: RefCounted) -> void:
	var group := Group.new();var field := make_field(bindings)
	check(group.configure(bindings,field,false),group.error)
	check(group.snapshot().counter_ms==1001 and group.snapshot().selections.is_empty(),"Source initial detail clock changed")
	var before := group.snapshot()
	check(group.update(150,null,null,true) and group.snapshot()==before,"Suppressed scenery advanced detail clock")
	check(not group.update(0,null,1,false) and group.snapshot()==before,"Failed first refresh changed clock")
	check(group.update(0,Vector3.ZERO,1,false),group.error)
	check(group.snapshot().counter_ms==0 and group.snapshot().selections[0].level==1 and group.snapshot().selections[1].level==1,"Large/small threshold contexts changed")
	check(group.refresh(Vector3(-1000,0,0),1) and group.snapshot().selections[0].level==1 and group.snapshot().selections[1].level==2,"Small scenery threshold did not differ from large")
	for index in 10:check(group.update(100,Vector3(70000,0,0),1,false),group.error)
	check(group.snapshot().counter_ms==1000 and group.snapshot().selections[1].level==2,"Scenery detail refreshed before1001ms")
	check(group.update(1,Vector3(70000,0,0),1,false) and group.snapshot().counter_ms==0 and group.snapshot().selections[1].level==0,"Scenery detail missed1001ms refresh")
	check(group.update(150,null,null,false) and group.refresh(Vector3(-1000000,0,0),1) and group.snapshot().counter_ms==150,"Forced scenery refresh reset timer")
	check(group.snapshot().selections[0]=={"visible":true,"level":3} and group.snapshot().selections[1]=={"visible":true,"level":3},"Final scenery threshold became visibility limit")
	before=group.snapshot()
	check(not group.refresh(Vector3.INF,1) and group.snapshot()==before,"Invalid reference changed scenery selections")
	check(not group.update(151,Vector3.ZERO,1,false) and group.snapshot()==before,"Invalid frame changed scenery clock")
	var detached := group.snapshot();detached.selections[0].level=0
	check(group.snapshot()==before,"Scenery detail snapshot aliases state")
	var forked := group.fork_for_frame()
	field.objects[0].position=Vector3.ZERO
	check(group.refresh(Vector3.ZERO,1) and group.snapshot().selections[0].level==1,"Scenery group aliases field positions")
	check(forked.snapshot()==before,"Scenery group fork shares clock or selections")
	field=make_field(bindings)
	check(group.configure(bindings,field,true) and group.refresh(Vector3.ZERO,1),group.error)
	check(group.snapshot().selections[0].level==0 and group.snapshot().selections[1].level==0,"Large display distances did not apply to every object")
	check(group.refresh(Vector3(-80001,0,0),1) and group.snapshot().selections[0].level==3,"Large display third LOD missing")
	for invalid in ["identity","count","index","large","position","model","variant"]:
		var changed := make_field(bindings)
		match invalid:
			"identity":changed.binding_id="c".repeat(64)
			"count":changed.large_count=3
			"index":changed.objects[0].index=1
			"large":changed.objects[1].large=true
			"position":changed.objects[0].position=Vector3.INF
			"model":changed.objects[0].model_id=-1
			"variant":changed.objects[0].model_variant=true
		check(not group.configure(bindings,changed,false) and group.snapshot().is_empty(),"Invalid scenery configuration retained old group: "+invalid)
	var selector := Detail.new();var shared := SharedGroup.new()
	check(selector.configure([100],1,0,[],[1.0]) and shared.configure_selectors(bindings,{0:selector}),shared.error)
	selector.clear()
	check(shared.refresh({0:Vector3(101,0,0)},Vector3.ZERO,1) and shared.snapshot().selections[0].level==1,"Shared manager aliases external selector")
	check(not shared.configure_selectors(bindings,{0:selector}) and shared.snapshot().is_empty(),"Unconfigured selector registered")
	check(selector.configure([100],0,0,[],[1.0]) and not shared.configure_selectors(bindings,{0:selector}),"Zero-alternate model registered")

func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)

extends SceneTree
const Group = preload("res://src/presentation/ship_detail_group.gd")
const Geometry = preload("res://src/presentation/ship_geometry.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): verify_source(args[i],args[i+1],args[i+2])
	print("Ship detail group checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String, pack: String, texture_pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var visuals := Visuals.new()
	check(library.open(content),library.error)
	check(bindings.open(pack,library.manifest),bindings.error)
	check(visuals.open(texture_pack,library.manifest),visuals.error)
	var group := Group.new()
	check(group.configure(bindings,{"player":10,0:2,1:23}),group.error)
	if group.snapshot().is_empty(): return
	check(group.snapshot().counter_ms==1001 and group.snapshot().selections.is_empty(),"Initial clock or unevaluated selection mismatch")
	var near := {"player":Vector3.ZERO,0:Vector3(100,0,0),1:Vector3(0,0,100)}
	var far := {"player":Vector3(0,0,20000),0:Vector3(80000,0,0),1:Vector3(0,0,6000)}
	var original := group.snapshot()
	check(group.update(150,{},null,null,true) and group.snapshot()==original,"Suppression changed clock or demanded unused positions")
	check(not group.update(0,near,null,1,false) and group.snapshot()==original,"Missing initial camera reference was guessed")
	check(group.update(0,near,Vector3.ZERO,1,false),group.error)
	check(group.snapshot().counter_ms==0 and group.snapshot().selections.player.level==0,"First periodic refresh was delayed")
	var geometry := Geometry.new();root.add_child(geometry)
	check(geometry.build(10,library,visuals,bindings),geometry.error)
	for i in 10: check(group.update(100,far,Vector3.ZERO,1,false),group.error)
	check(group.snapshot().counter_ms==1000 and group.snapshot().selections.player.level==0,"LOD updated before the source threshold")
	check(geometry.apply_selection(group.snapshot().selections.player) and geometry.levels[0].visible,"Held detail did not reach geometry")
	check(group.update(1,far,Vector3.ZERO,1,false),group.error)
	var selected: Dictionary = group.snapshot().selections
	check(group.snapshot().counter_ms==0 and selected.player.level==1 and not selected[0].visible and selected[1].level==1,"Periodic distance selection mismatch")
	check(geometry.apply_selection(selected.player) and geometry.levels[1].visible and not geometry.levels[0].visible,"Scheduled detail did not switch geometry")
	selected.player.level=0
	check(group.snapshot().selections.player.level==1 and geometry.selection.level==1,"Snapshot mutation escaped into state")
	for i in 7: check(group.update(150,near,Vector3.ZERO,1,false),group.error)
	check(group.snapshot().counter_ms==0 and group.snapshot().selections.player.level==0,"Refresh retained overshoot instead of resetting to zero")
	check(group.update(150,far,Vector3.ZERO,1,false),group.error)
	check(group.refresh(far,Vector3.ZERO,1) and group.snapshot().counter_ms==150 and group.snapshot().selections.player.level==1,"Forced refresh reset the periodic timer")
	original=group.snapshot()
	for invalid in [{}, {"player":Vector3.ZERO,0:Vector3.INF,1:Vector3.ZERO}]:
		check(not group.refresh(invalid,Vector3.ZERO,1) and group.snapshot()==original,"Invalid batch partially changed selections")
	for i in 5: check(group.update(150,near,Vector3.ZERO,1,false),group.error)
	original=group.snapshot()
	check(not group.update(150,{},Vector3.ZERO,1,false) and group.snapshot()==original,"Failed periodic refresh advanced clock")
	for delta in [-1,151,true,NAN]:
		check(not group.update(delta,near,Vector3.ZERO,1,false) and group.snapshot()==original,"Invalid frame changed group")
	check(group.refresh(far,Vector3(0,0,20000),1) and group.snapshot().selections.player.level==0,"Supplied reference was ignored")
	var before := geometry.selection.duplicate(true)
	for invalid in [{},{"visible":true,"level":99},{"visible":false,"level":0},{"visible":true,"level":true}]:
		check(not geometry.apply_selection(invalid) and geometry.selection==before and geometry.levels[1].visible,"Invalid selection changed geometry")
	check(geometry.apply_selection({"visible":false,"level":-1}),geometry.error)
	for level in geometry.levels: check(not level.visible,"Batch culling left a visible level")
	check(not group.configure(bindings,{0:37}) and group.snapshot().is_empty(),"Unregistered non-LOD ship acquired a culling policy")
	var saved := bindings.lod_refresh.duplicate(true)
	bindings.lod_refresh.initial_milliseconds=0;bindings.lod_refresh.refresh_at_milliseconds=71
	check(group.configure(bindings,{0:2}),group.error)
	check(group.update(70,{},null,null,false) and group.snapshot().selections.is_empty(),"Changed imported threshold ignored")
	check(group.update(1,{0:Vector3.ZERO},Vector3.ZERO,1,false) and group.snapshot().selections[0].level==0,"Changed threshold failed to refresh")
	bindings.lod_refresh=saved
	geometry.free()
	print(library.manifest.profile.edition+": scheduled and forced selections, suppression, atomic failures and renderer handoff verified")

func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)

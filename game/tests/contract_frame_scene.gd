extends "res://tests/contract_frame.gd"
## Original resources rendered from actual ordinary worlds. Local construction
## and direct Junk hits are disclosed fixtures; no application unlock is claimed.
const View=preload("res://src/presentation/first_flight_scene.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var scenes:={}
var scene_count:=0

func _initialize() -> void:call_deferred("run")

func verify_world(bindings: RefCounted,cat: RefCounted,library: RefCounted,construction: RefCounted) -> void:
	var entry: Dictionary=construction.snapshot()
	var kind: int=entry.scenery.world_initialization.contract_context.mission.get("kind",-1)
	if not scenes.has(kind):scenes[kind]={"bindings":bindings,"cat":cat,"library":library,"construction":construction}
	worlds_verified+=1

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:verify(args.slice(0,3))
	if failures==0:
		root.content_scale_size=Vector2i(1280,720)
		root.size=Vector2i(1280,720)
		for kind in scenes:
			await verify_scene(kind,scenes[kind],args)
			if failures:break
	check(scene_count==5,"The scene check did not render mixed traffic, Courier, Junk, Pirate and Challenge")
	print("Contract frame scenes: %d checks; %d original scenes; %d failures"%[checks,scene_count,failures])
	quit(1 if failures else 0)

func verify_scene(kind: int,entry: Dictionary,args: PackedStringArray) -> void:
	var visuals:=Visuals.new()
	if not visuals.open(args[2],entry.library.manifest):check(false,visuals.error);return
	var frame:=LiveFrame.new()
	if not frame.configure(entry.bindings,entry.cat,entry.library,entry.construction,"D",1.0):check(false,frame.error);return
	var scene:=View.new();root.add_child(scene)
	if not scene.build(entry.library,entry.bindings,visuals,entry.cat,frame):check(false,scene.error);scene.free();return
	frame=release(frame)
	if frame==null:scene.free();return
	for tick in 30:
		var next: RefCounted=frame.evaluate(100)
		if next==null:check(false,frame.error);scene.free();return
		frame=next
	if not scene.present(frame,true,10001):check(false,scene.error);scene.free();return
	var state: Dictionary=frame.snapshot()
	check(scene.encounter.actors.size()==state.encounter.combat.actors.size(),"The rendered encounter omitted source actors")
	check(scene.station!=null and scene.geometry.player!=null and scene.sky!=null and scene.radio!=null,"The ordinary world omitted its source station, ship, sky or radio")
	if kind==7:
		check(scene.encounter.actors.all(func(row):return row.debris and row.engine==null and row.explosion==null),"Junk was rendered with ship engines or explosions")
		var combat: RefCounted=frame._encounter._combat
		if not combat.begin_contact_pass(state.random_state,true):check(false,combat.error);scene.free();return
		for actor in combat.snapshot().actors:
			if combat.normal_hit(actor.actor_id,1).is_empty():check(false,combat.error);scene.free();return
		var destroyed: RefCounted=frame.evaluate(0)
		if destroyed==null:check(false,frame.error);scene.free();return
		frame=destroyed
		if not scene.present(frame,false,10001):check(false,scene.error);scene.free();return
		for id in scene.encounter.actors.size():
			var actor: Dictionary=scene.encounter.actors[id]
			var cargo: Dictionary=frame.snapshot().encounter.controller.destruction[id].cargo
			check(not actor.hull.visible and actor.cargo.visible==cargo.model_exists,"Junk body/container visibility differs from its actual destruction")
		check(scene.damage_particles.items.any(func(item):return item.kind=="junk_burst" and item.node.get_meta("source_material_id")==int(entry.bindings.early_contracts.junk_lifecycle.burst_preset.material_id)),"The scene omitted the original Junk particle material")
	if args.size()==4:await capture_scene(args[3],"contract-kind-%d-desktop"%kind)
	if kind==7:
		root.content_scale_size=Vector2i(960,540);root.size=Vector2i(960,540);scene.set_mobile_layout(true)
		check(root.content_scale_size.x>root.content_scale_size.y,"Mobile presentation lost its horizontal viewport")
		if args.size()==4:await capture_scene(args[3],"contract-junk-mobile-landscape")
		root.content_scale_size=Vector2i(1280,720)
		root.size=Vector2i(1280,720)
	scene_count+=1;scene.free()
	print("Contract original scene: active kind %d"%kind)

func capture_scene(directory: String,label: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK,"Could not retain the private scene capture")

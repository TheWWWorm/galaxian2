extends SceneTree
## Source models with retained native states. Close camera and lethal damage
## are deliberate visual fixtures, not an original-runtime fidelity comparison.
const Fixture=preload("res://tests/full_hold_world.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var checks:=0
var failures:=0
var scene: Node3D
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	if is_instance_valid(scene):scene.free()
	print("Full-hold world render: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not cat.open(lib) or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	var fixture:=Fixture.new();fixture.verify(args.slice(0,3))
	check(fixture.failures==0 and fixture.world!=null,"Native second-trip fixture failed")
	var world: RefCounted=fixture.world;fixture.free()
	if world==null:return
	root.size=Vector2i(1280,720)
	scene=Scene.new();root.add_child(scene)
	if not scene.build(lib,bindings,visuals,cat,world):check(false,scene.error);return
	check(scene.encounter.hull.visible and scene.encounter.engine.visible and not scene.encounter.cargo.visible,"Living pirate model/engine/cargo flags disagree")
	check(scene.encounter.hull.transform==world.snapshot().actors[0].pose,"Pirate hull did not use source statistics pose")
	if args.size()==4:await capture(args[3],"second-trip-cue")
	var close: RefCounted=world.fork_for_frame()
	var actor: Dictionary=close.snapshot().actors[0]
	var eye: Vector3=actor.pose.origin+Vector3(650,400,-950)
	var target: Vector3=actor.pose.origin
	var camera_pose:=Transform3D.IDENTITY.looking_at(target-eye,Vector3.UP);camera_pose.origin=eye
	set_camera(close,camera_pose,target)
	check(scene.present(close),scene.error)
	if args.size()==4:await capture(args[3],"second-trip-pirate-close")
	var original_pose: Transform3D=scene.encounter.hull.transform
	var broken: RefCounted=close.fork_for_frame();broken._encounter._combat._actors[0]._state.hull_resource="missing"
	check(not scene.present(broken) and scene.encounter.hull.transform==original_pose and scene.geometry.player.transform==close.snapshot().player_pose*Transform3D(close.snapshot().player_model_basis,Vector3.ZERO),"Rejected pirate rendering changed the accepted scene")
	check(scene.present(close),scene.error)
	# The starter has no gun. A lethal fixture verifies the source body, engine,
	# explosion and retained container presentation without inventing equipment.
	close._encounter._combat.normal_hit(0,50)
	var next: RefCounted=close.evaluate(0)
	if next==null:check(false,close.error);return
	close=next;set_camera(close,camera_pose,target)
	check(scene.present(close) and scene.encounter.hull.visible and not scene.encounter.engine.visible,"Death entry hid the hull or left its engine on: "+scene.error)
	if args.size()==4:await capture(args[3],"second-trip-pirate-tumble")
	var saw_cargo:=false;var saw_effect:=false
	for i in 110:
		next=close.evaluate(100)
		if next==null:check(false,close.error);return
		close=next
		var life: Dictionary=close.snapshot().encounter.controller.actors[0].destruction
		target=life.cargo.pose.origin if life.cargo.model_exists else life.pose.origin
		camera_pose.origin=target+Vector3(650,400,-950)
		set_camera(close,camera_pose,target)
		if not scene.present(close):check(false,scene.error);return
		if scene.encounter.explosion.visible:saw_effect=true
		if scene.encounter.cargo.visible and life.effect.elapsed_ms>=200:
			saw_cargo=true
			check(scene.encounter.cargo.transform==life.cargo.pose and scene.encounter.hull.transform==close.snapshot().actors[0].pose,"Cargo or dying hull lost its independently retained pose")
			if args.size()==4:await capture(args[3],"second-trip-cargo-explosion")
			break
	check(saw_effect and saw_cargo,"Source cargo-bearing explosion was not presented")
	next=close.evaluate(100)
	if next==null:check(false,close.error);return
	close=next
	var container: Dictionary=close.snapshot().encounter.controller.actors[0].destruction.cargo
	camera_pose.origin=container.pose.origin+Vector3(650,400,-950)
	set_camera(close,camera_pose,container.pose.origin)
	check(scene.present(close) and not scene.encounter.hull.visible and not scene.encounter.engine.visible and scene.encounter.cargo.visible,"Mode4 at 300 ms did not hide the hull independently of its cargo")
	if args.size()==4:await capture(args[3],"second-trip-container")
	var before: Dictionary=close.snapshot()
	check(scene.present(close) and close.snapshot()==before,"Rendering advanced retained gameplay or lifetime clocks")

func set_camera(world: RefCounted, pose: Transform3D, target: Vector3):
	world._camera._state.pose=pose;world._camera._state.eye=pose.origin;world._camera._state.look=target
	world._reference=pose.origin
	# The fixture moves the camera outside the ordinary follow controller;
	# refresh its matching LOD reference explicitly so it can inspect the hull.
	var actor: Dictionary=world.snapshot().actors[0]
	world._detail.refresh({"player":world._pose.origin,0:actor.get("body_pose",actor.pose).origin},pose.origin,1.0)
func capture(directory: String, name: String):
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Cannot save "+name)
func check(value: bool, message: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL ",checks,": ",message)

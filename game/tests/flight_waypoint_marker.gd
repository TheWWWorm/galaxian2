extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Marker=preload("res://src/presentation/flight_waypoint_marker.gd")
const Route=preload("res://src/simulation/npc_route.gd")
const Atlas=preload("res://src/content/atlas_region.gd")
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected content, binding and visual packs")
	if args.size() in [3,4]:await verify(args)
	print("Flight waypoint marker: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)
func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+visuals.error);return
	var canvas:=SubViewport.new();canvas.size=Vector2i(1280,720);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var hud:=Marker.new();canvas.add_child(hud);hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not bindings.combat_training_story.has("navigation"):
		check(not hud.prepare(library,bindings,visuals),"Earlier pack invented waypoint presentation");canvas.free();return
	check(hud.prepare(library,bindings,visuals),hud.error)
	if not hud.error.is_empty():canvas.free();return
	var player:=Route.new();var companion:=Route.new()
	check(player.configure_training_player(bindings) and companion.configure_training_authored(bindings),player.error+companion.error)
	var initial:=player.snapshot();var point: Vector3=initial.waypoints[0]
	check(initial.owner=="player" and not initial.has("actor_id") and initial.index==0 and not initial.loop,"Player route inherited NPC ownership or a looping patrol")
	for axis in 3:
		for sign_value in [-1,1]:
			var offset:=Vector3.ZERO;offset[axis]=sign_value*2000
			check(not player.advance(point+offset).arrived and player.snapshot().index==0,"Waypoint boundary was inclusive")
	var detached: RefCounted=player.fork_for_frame()
	check(detached.advance(point+Vector3(1999,1999,1999)).arrived and detached.snapshot().index==1 and player.snapshot()==initial and companion.snapshot().index==0,"Waypoint box became spherical or changed another route")
	check(detached.advance(initial.waypoints[1]).completed and detached.snapshot().index==2,"Authored route did not exhaust")
	check(not detached.advance(point).arrived and detached.snapshot().index==2,"Completed route wrapped to the first waypoint")
	for row in [[0,0,"0m"],[127,0,"0m"],[128,8,"8m"],[15999,992,"992m"],[16000,1000,"1.0km"],[17599,1096,"1.0km"],[17664,1104,"1.1km"],[2560000,160000,"160.0km"]]:
		var meters:=hud.distance_meters(Vector3(row[0],0,0),Vector3.ZERO)
		check(meters==row[1] and hud.distance_text(meters)==row[2],"Waypoint source distance quantization/format changed at %d"%row[0])
	var source: Image=visuals.load_image("resources/data/textures/gof2_interface2_ipad.aei")
	for name in ["in_view","outside"]:
		var texture: AtlasTexture=hud._textures[name]
		check(texture.get_image().get_data()==source.get_region(Rect2i(texture.region)).get_data(),"Waypoint image altered original pixels")
	for mobile in [false,true]:
		canvas.size=Vector2i(420,800) if mobile else Vector2i(1280,720);hud.set_mobile_layout(mobile)
		var camera:=Transform3D(Basis.IDENTITY,point+Vector3(0,0,16000))
		check(hud.present(initial,camera,canvas.size,true),hud.error)
		check(hud.visible and hud.snapshot().in_view and hud.snapshot().pixels==canvas.size/2 and hud.snapshot().distance_text=="1.0km","Centered waypoint did not use the current camera")
		if args.size()==4 and DisplayServer.get_name()!="headless":
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			check(canvas.get_texture().get_image().save_png(args[3].path_join("waypoint-%s.png"%("phone" if mobile else "desktop")))==OK,"Waypoint capture failed")
		camera.origin=point+Vector3(100000,0,0)
		check(hud.present(initial,camera,canvas.size,true) and hud.visible and not hud.snapshot().in_view,"Offscreen waypoint lost the center-frame ellipse marker")
		var accepted:=hud.snapshot();var bad:=initial.duplicate(true);bad.binding_id="0".repeat(64)
		check(not hud.present(bad,camera,canvas.size,true) and hud.snapshot()==accepted,"Foreign route replaced an accepted waypoint")
		check(hud.present(initial,camera,canvas.size,false) and not hud.visible and player.snapshot()==initial,"Hidden waypoint advanced the route")
	check(hud.present(detached.snapshot(),Transform3D.IDENTITY,canvas.size,true) and not hud.visible,"Exhausted route retained a marker")
	check(hud.present({},Transform3D.IDENTITY,canvas.size,true) and hud.snapshot().is_empty() and not hud.visible,"Cleared route retained a marker")
	canvas.free()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

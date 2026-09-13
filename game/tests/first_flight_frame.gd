extends SceneTree
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Pilot=preload("res://src/simulation/pilot_motion.gd")
const Layout=preload("res://src/simulation/opening_planet_layout.gd")
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:await verify(args)
	print("First flight frame: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: Array):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new();var bodies:=Bodies.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not visuals.open(args[2],lib.manifest) or not bodies.configure(lib,bindings):check(false,lib.error+bindings.error+cat.error+visuals.error+bodies.error);return
	var flight:=Frame.new()
	check(flight.snapshot().is_empty() and flight.evaluate(0)==null,"Unprepared first flight advanced")
	if bindings.mining_briefing.is_empty():
		check(not flight.configure(bindings,cat,lib,Construction.new(),"E",0.5),"Legacy pack invented live mining entry");return
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var packet:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3))
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,packet,[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Could not prepare rescue fixture");return
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new();check(station.configure(bindings,cat,lib,arrival.prepare_station()),station.error)
	for i in 19:station.acknowledge()
	var departure:=station.prepare_departure(bindings,cat)
	var construction:=Construction.new()
	if not construction.prepare(bindings,cat,departure,4096,1789100000,true,bodies):check(false,construction.error);return
	var prepared:=construction.snapshot()
	if not flight.configure(bindings,cat,lib,construction,"E",0.5):check(false,flight.error);return
	var initial:=flight.snapshot();var captures:={"entry-0":flight}
	check(initial.activated and initial.camera_shot.mode=="fixed_eye" and initial.camera_view.mode=="fixed_eye","Live entry did not retain the fixed camera")
	check(initial.player.active and not initial.player.damage_allowed and not initial.scenery_collision_enabled,"Entry confused movement, damage and collision permissions")
	check(initial.player.vitals.hull==95 and initial.actors.is_empty() and initial.cargo_used==0,"First flight restored the wrong ship or mission state")
	for bad in [-1,151,0.5,"1"]:check(flight.evaluate(bad)==null and flight.snapshot()==initial,"Invalid frame changed live entry")
	check(flight.evaluate(100,Vector2(INF,0))==null and flight.evaluate(100,Vector2(2,0))==null and flight.evaluate(100,Vector2.ZERO,-1)==null and flight.snapshot()==initial,"Invalid controls altered flight")
	check(not flight.configure(bindings,cat,lib,construction,"E",INF) and flight.snapshot()==initial,"Failed configuration replaced a good flight")
	check(flight.evaluate(100,Vector2.ONE,0.0,true).snapshot()==initial,"Pause advanced the first entry")
	check(flight.navigate("next")==null,"Entry acknowledged an unseen instruction")
	for i in 70:
		var next: RefCounted=flight.evaluate(100,Vector2.ONE,0.0)
		if next==null:check(false,flight.error);return
		flight=next
		if i==34:captures["entry-3500"]=flight
	var before:=flight.snapshot();captures["entry-7000"]=flight
	var expected: Vector3=initial.player_pose.origin+initial.player_pose.basis.z*14000.0
	check(before.player_pose.origin.distance_to(expected)<0.1,"Entry travel is not source cruise (2 units per ms)")
	check(before.player_pose.basis.is_equal_approx(initial.player_pose.basis) and before.angular_units==Vector2.ZERO,"Entry accepted pilot commands")
	check(before.camera_view.eye==initial.camera_view.eye and before.camera_view.look==before.player_pose.origin,"Entry camera moved its eye or lost the moving target")
	check(not before.entry_released and not before.player.damage_allowed and before.entry_elapsed_ms==7000,"Entry released before 7001 ms")
	var release: RefCounted=flight.evaluate(1,Vector2(0,1),0.0)
	if release==null:check(false,flight.error);return
	var released: Dictionary=release.snapshot();captures["release-7001"]=release
	check(released.entry_released and released.briefing_pending and not released.dialogue.visible,"HUD and controller release were reordered")
	check(released.player.active and released.player.damage_allowed and released.scenery_collision_enabled and not released.scenery_collision_supported,"Release protection or collision support is misreported")
	check(released.camera_view.mode=="follow" and released.camera_view.eye!=before.camera_view.eye,"Release did not update the follow camera on the same frame")
	check(released.player_pose.basis.is_equal_approx(before.player_pose.basis) and released.angular_units.y>0,"Release lost the delayed pilot response")
	check(released.player_pose.origin.distance_to(before.player_pose.origin+before.player_pose.basis.z*2.0)<0.01,"Release consumed a throttle change before player movement")
	flight=release
	for i in 49:
		flight=flight.evaluate(100)
		if flight==null:check(false,"Entry follow frame failed");return
	var before_open: Dictionary=flight.snapshot()
	check(before_open.hud_elapsed_ms==5000 and not before_open.dialogue.visible,"Briefing ignored the held departure clock")
	var opening: RefCounted=flight.evaluate(1)
	if opening==null:check(false,"Briefing opening frame failed: "+flight.error);return
	flight=opening
	var opened:=flight.snapshot();captures["briefing"]=flight
	check(opened.dialogue.visible and opened.world_elapsed_ms==11902 and opened.player_pose!=before_open.player_pose and opened.camera_view!=before_open.camera_view,"Briefing opening frame lost simulation time")
	check(opened.player_pose.basis!=released.player_pose.basis,"Previous release-frame steering never moved the ship")
	for i in 10:check(flight.evaluate(150,Vector2.ONE,0.0).snapshot()==opened,"Modal briefing advanced world, camera or controls")
	check(flight.navigate("next",true)==null and flight.snapshot()==opened,"Pause acknowledged a briefing")
	var branch: RefCounted=flight.navigate("next")
	check(branch.snapshot().dialogue.index==1 and flight.snapshot()==opened,"Prospective acknowledgement mutated the old frame")
	check(branch.navigate("previous").snapshot()==opened,"Previous instruction changed the world")
	for i in 5:flight=flight.navigate("next")
	var acknowledged:=flight.snapshot()
	check(acknowledged.acknowledged and acknowledged.phase=="flight" and not acknowledged.briefing_pending,"Briefing completion did not resume flight")
	for key in ["player_pose","camera_view","scenery","random_state","world_elapsed_ms"]:check(acknowledged[key]==opened[key],"Acknowledgement changed simulation state: "+key)
	var pilot:=Pilot.new();check(pilot.configure_vehicle(bindings,cat,bindings.base_content_id,0,[],[90,81],0.5),pilot.error)
	if not bindings.station_flight.is_empty():check(pilot.set_response_factor(acknowledged.station_autopilot.response_factor),pilot.error)
	pilot.angular_units=acknowledged.angular_units
	var expected_pose:=pilot.advance(acknowledged.player_pose,Vector2(-0.5,0.75),0.6,0.1)
	flight=flight.evaluate(100,Vector2(-0.5,0.75),0.6)
	if flight==null:check(false,"Manual first-flight frame failed");return
	var moved:=flight.snapshot();captures["manual"]=flight
	check(moved.player_pose.is_equal_approx(expected_pose) and moved.angular_units==pilot.angular_units,"Post-briefing flight diverged from the shared ordinary motion owner")
	for key in ["mission","progress","cargo_used","campaign_cursor","mining_completed","reward_credits"]:check(moved[key]==initial[key],"Flight created unearned progress: "+key)
	check(moved.random_state==prepared.random_state and moved.environment_object==prepared.environment_object,"Live flight repeated construction RNG")
	check(construction.snapshot()==prepared and station.prepare_departure(bindings,cat)==departure,"Live flight mutated its departure source")
	var rejected: RefCounted=flight.fork_for_frame();rejected._shot.target="unsupported"
	var held: Dictionary=rejected.snapshot()
	check(rejected.evaluate(100)==null and rejected.snapshot()==held and flight.snapshot()==moved,"Rejected prospective frame partially mutated the old world")
	var independent: RefCounted=pilot.fork_for_frame()
	check(independent.set_response_factor(99),independent.error)
	independent.clear()
	var reference:=Pilot.new();reference.configure_vehicle(bindings,cat,bindings.base_content_id,0,[],[90,81],0.5);reference.angular_units=pilot.angular_units
	if not bindings.station_flight.is_empty():reference.set_response_factor(acknowledged.station_autopilot.response_factor)
	check(pilot.advance(expected_pose,Vector2.ONE,1.0,0.1)==reference.advance(expected_pose,Vector2.ONE,1.0,0.1),"Fork clear or vehicle response changed the original pilot")
	var layout:=Layout.new();var planets:=layout.for_departure(bindings,cat,departure.player_cache)
	check(not planets.is_empty() and planets.campaign_cursor==2 and planets.station_id==78 and planets.system_id==15,"Departure layout used a rescue or Opening context")
	var current: Dictionary=planets.entries[planets.selected_index]
	check(current.current and current.texture_id==initial.location.current_planet_texture_id,"Departure planet used the Opening texture")
	check(layout.for_arrival(bindings,cat,departure.player_cache).is_empty(),"Departure layout was accepted as rescue")
	if args.size()==4:await render(args[3],lib,bindings,visuals,cat,captures)
	flight.clear();check(flight.snapshot().is_empty(),"Clear retained first flight")

func render(directory: String,lib: RefCounted,bindings: RefCounted,visuals: RefCounted,cat: RefCounted,captures: Dictionary):
	var canvas:=SubViewport.new();canvas.size=Vector2i(1280,720);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var scene:=Scene.new();canvas.add_child(scene)
	if not scene.build(lib,bindings,visuals,cat,captures["entry-0"]):check(false,scene.error);canvas.free();return
	check(scene.geometry.actors.is_empty() and scene.geometry.player.get_meta("source_ship_id")==0,"Departure renderer invented actors or reused the rescue hull")
	check(scene.sky.selection.campaign_cursor==2 and scene.planets.selection.campaign_cursor==2,"Departure environment lost its explicit context")
	for label in captures:
		var flight: RefCounted=captures[label]
		if not scene.present(flight,true):check(false,scene.error);break
		check(scene.geometry.player.transform.is_equal_approx(flight.snapshot().player_pose*Transform3D(flight.snapshot().get("player_model_basis",Basis.IDENTITY),Vector3.ZERO)) and scene.camera.global_transform.is_equal_approx(flight.snapshot().camera_view.pose),"Renderer did not consume the live ship/camera: "+label)
		for i in 3:await process_frame
		var capture:=canvas.get_texture().get_image()
		check(capture.get_size()==canvas.size and capture.save_png(directory.path_join(label+".png"))==OK,"Could not save flight capture")
		if label=="briefing":
			canvas.size=Vector2i(420,800);scene.set_mobile_layout(true);check(scene.present(flight),scene.error)
			for i in 3:await process_frame
			check(Rect2(Vector2.ZERO,canvas.size).encloses(scene.dialogue._panel.get_rect()),"Live phone briefing extends beyond viewport")
			canvas.get_texture().get_image().save_png(directory.path_join("briefing-phone.png"))
			canvas.size=Vector2i(1280,720);scene.set_mobile_layout(false)
	check(scene.present(captures.manual),scene.error)
	var original: Transform3D=scene.geometry.player.transform
	var foreign: RefCounted=captures.manual.fork_for_frame();foreign._briefing._state.binding_id="foreign"
	check(not scene.present(foreign) and scene.geometry.player.transform==original,"Foreign frame changed the visible scene")
	canvas.free()

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)

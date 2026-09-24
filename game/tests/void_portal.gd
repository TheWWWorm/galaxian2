extends SceneTree
## Isolated source-bound component observations do not earn a campaign save.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Owner=preload("res://src/simulation/void_portal.gd")
const Geometry=preload("res://src/presentation/void_portal_geometry.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Frames=preload("res://src/simulation/frame_clock.gd")
var failures:=0
var checks:=0
var library: RefCounted
var bindings: RefCounted
var camera:=Transform3D(Basis.IDENTITY,Vector3(0,0,40000))

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<3 or args.size()>4:check(false,"Expected content, bindings, visuals and optional capture folder");quit(1);return
	library=Library.new();bindings=Bindings.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest):check(false,library.error+bindings.error);quit(1);return
	var absent:=Owner.new()
	if not bindings.mido_travel.has("void_portal"):
		check(not absent.configure(bindings,entry(),library) and absent.snapshot().is_empty(),"Older pack invented a returning portal")
		print("Void portal: %d checks; %d failures (missing capability guard only)"%[checks,failures]);quit(1 if failures else 0);return
	verify_admission()
	verify_clock_and_random()
	verify_contact()
	if failures==0:await verify_geometry(args[2],args[3] if args.size()==4 else OS.get_environment("GOF2_CAPTURE_DIR"))
	print("Void portal: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func entry() -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":25,"system_id":-1,"station_id":-1,"mission_kind":156,
		"mission_story":true,"mission_completed":false,"mission_failed":false,
		"current_station_id":-1,"void_station_id":-1,
		"environment_object":{"resource_id":16994,"position":Vector3(0,0,60000)}}
func fresh() -> RefCounted:
	var owner:=Owner.new();check(owner.configure(bindings,entry(),library),owner.error);return owner
func rng() -> RefCounted:
	var random:=Random.new();random.seed_from(25);return random
func until(owner: RefCounted,random: RefCounted,milliseconds: int) -> bool:
	while milliseconds>0:
		var step:=mini(milliseconds,150)
		if not owner.advance(step,camera,random):check(false,owner.error);return false
		milliseconds-=step
	return true

func verify_admission() -> void:
	var owner:=fresh();var accepted: Dictionary=owner.portal_snapshot()
	for changes in [{"campaign_cursor":24},{"station_id":49},{"current_station_id":6},{"void_station_id":6},
		{"mission_kind":4},{"mission_completed":true},{"mission_failed":true},{"mission_story":false},
		{"binding_id":"foreign"},{"environment_object":{"resource_id":16995,"position":Vector3.ZERO}},
		{"environment_object":{"resource_id":16994,"position":Vector3(INF,0,0)}}]:
		var bad:=entry();bad.merge(changes,true)
		check(not owner.configure(bindings,bad,library) and owner.portal_snapshot()==accepted,"Rejected Void entry changed its accepted state: "+str(changes))
	var random:=rng();var random_before: Dictionary=random.snapshot()
	for milliseconds in [-1,Frames.simulation_limit(bindings,150)+1,150.0]:
		check(not owner.advance(milliseconds,camera,random) and owner.portal_snapshot()==accepted and random.snapshot()==random_before,"Rejected frame changed the portal or world random stream")
	check(not owner.advance(1,Transform3D(Basis.IDENTITY,Vector3(INF,0,0)),random),"Nonfinite camera entered the world clock")
	check(not owner.advance(1,camera,Random.new()),"An unseeded world changed the portal")
	check(not owner.transition_ready(100),"An untouched portal authorized a campaign transition")

func verify_clock_and_random() -> void:
	var owner:=fresh();var random:=rng();var start_random: Dictionary=random.snapshot()
	if not until(owner,random,60000):return
	check(owner.portal_snapshot().elapsed_ms==60000 and owner.portal_snapshot().extent==4096,"Return portal closed at the inclusive lifetime boundary")
	check(random.snapshot()==start_random,"Open portal consumed the world random stream")
	if not until(owner,random,3000):return
	check(owner.portal_snapshot().visible and owner.portal_snapshot().extent==0 and random.snapshot()==start_random,"Return portal relocated at the inclusive closing boundary")
	var retained: Dictionary=owner.portal_snapshot();var fork: RefCounted=owner.fork_for_frame();var fork_random: RefCounted=random.fork()
	check(fork.advance(1,camera,fork_random),fork.error)
	check(owner.portal_snapshot()==retained and random.snapshot()==start_random,"A discarded candidate changed retained portal/random state")
	check(owner.advance(1,camera,random),owner.error)
	var reopened: Dictionary=owner.portal_snapshot()
	check(reopened==fork.portal_snapshot() and random.snapshot()==fork_random.snapshot(),"Retry changed the deterministic relocation")
	check(reopened.position==Vector3(-77981,34947,-75738),"Void portal relocation lost the original draw order or signed coordinates")
	check(reopened.elapsed_ms==-3000 and reopened.extent==-1 and reopened.visible,"Relocation hid the portal or replaced its retained closing extent")
	check(reopened.pose.origin==reopened.position and Flight.rigid_pose(reopened.pose),"Relocated portal faced from its previous position")
	check(owner.snapshot().frame=={"relocated":true,"cancel_autopilot":true},"Relocation omitted the flight autopilot cue")
	check(not owner.transition_ready(100),"Relocation earned a portal entry")
	check(owner.advance(150,camera,random) and owner.portal_snapshot().extent==205 and owner.snapshot().frame.is_empty(),"Next opening frame replayed relocation or changed source extent")
	if not until(owner,random,2850):return
	check(owner.portal_snapshot().elapsed_ms==0 and owner.portal_snapshot().extent==3892,"Opening zero boundary discarded the retained source extent")
	if not until(owner,random,63001):return
	check(owner.portal_snapshot().position==Vector3(57397,37595,-86437) and random.snapshot()=={"state":91192877033276},"Second opening stopped recurring or consumed extra random draws")
	var detached: Dictionary=owner.portal_snapshot();detached.animation.clear()
	check(not owner.portal_snapshot().animation.is_empty(),"Published portal snapshot exposed mutable owner state")

func observation(owner: RefCounted,offset: Vector3,enabled:=true,mining:=false) -> Dictionary:
	return {"player_pose":Transform3D(Basis.IDENTITY,owner.portal_snapshot().position+offset),"environment_contact_enabled":enabled,"mining_active":mining}
func verify_contact() -> void:
	var owner:=fresh();var random:=rng()
	for offset in [Vector3(40000,0,0),Vector3(0,-40000,0),Vector3(30000,30000,0)]:
		check(owner.observe_contact(observation(owner,offset)) and owner.snapshot().contact.is_empty(),"Portal pulled from outside its sphere/cube")
	check(owner.observe_contact(observation(owner,Vector3(1000,0,0))) and owner.snapshot().contact.pull_distance==152 and not owner.snapshot().portal_entered,"Pull radius incorrectly entered the portal at 1000 units")
	check(owner.observe_contact(observation(owner,Vector3.ZERO,false)) and owner.snapshot().contact.is_empty(),"Disabled environment contact earned entry")
	check(owner.observe_contact(observation(owner,Vector3.ZERO,true,true)) and owner.snapshot().contact.is_empty(),"Active mining earned portal entry")
	if not until(owner,random,60001):return
	check(owner.observe_contact(observation(owner,Vector3.ZERO)) and not owner.transition_ready(1),"A closing portal allowed return")
	if not until(owner,random,3000):return
	check(owner.observe_contact(observation(owner,Vector3(999,0,0))) and owner.transition_ready(1),"Reopened portal lost the living entry boundary")
	check(not owner.transition_ready(0) and not owner.transition_ready(-1) and not owner.transition_ready(1.0),"Dead or malformed hull authorized a return")
	var before: Dictionary=owner.snapshot()
	check(not owner.observe_contact({}) and owner.snapshot()==before,"Invalid contact erased the earned entry")

func verify_geometry(path: String,captures: String) -> void:
	var visuals:=Visuals.new()
	if not visuals.open(path,library.manifest):check(false,visuals.error);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var view:=Camera3D.new();viewport.add_child(view);view.current=true;view.near=10;view.far=100000
	view.look_at_from_position(camera.origin,Vector3(0,0,60000))
	var owner:=fresh();var geometry:=Geometry.new();viewport.add_child(geometry);var random:=rng()
	if not geometry.build(library,visuals,bindings,entry()) or not owner.advance(150,camera,random):check(false,geometry.error+owner.error);viewport.free();return
	var frame: Dictionary=geometry.prepare_state(owner.portal_snapshot())
	if frame.is_empty():check(false,geometry.error);viewport.free();return
	geometry.commit_state(frame)
	check(geometry.model.instances.size()==2 and geometry.model.instances.all(func(node):return node.is_visible_in_tree()),"Returning portal lost an original additive surface")
	var invalid: Dictionary=owner.portal_snapshot();invalid.binding_id="foreign"
	check(geometry.prepare_state(invalid).is_empty(),"Portal rendering accepted another content identity")
	if DisplayServer.get_name()!="headless":
		await process_frame;await RenderingServer.frame_post_draw
		var picture:=viewport.get_texture().get_image();var background:=picture.get_pixel(0,0);var pixels:=0
		for y in range(0,picture.get_height(),3):
			for x in range(0,picture.get_width(),3):
				var pixel:=picture.get_pixel(x,y)
				if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>.09:pixels+=1
		check(pixels>100,"Returning portal failed to render")
		if not captures.is_empty():
			DirAccess.make_dir_recursive_absolute(captures)
			check(picture.save_png(captures.path_join("void-return-portal.png"))==OK,"Returning portal capture failed")
	viewport.free()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

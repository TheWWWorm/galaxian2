extends SceneTree
const Autopilot=preload("res://src/simulation/station_autopilot.gd")
const Guidance=preload("res://src/simulation/player_guidance.gd")
const Definitions=preload("res://src/content/station_autopilot_definitions.gd")
const Resources=preload("res://src/content/station_exterior_resources.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var checks:=0
var failures:=0
var bindings:=Bindings.new()
var cat:=Catalogues.new()
var construction:=Construction.new()
var resources:=Resources.new()
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:await verify(args)
	print("Station autopilot: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func fresh() -> RefCounted:
	var owner:=Autopilot.new();check(owner.configure(bindings,cat,construction,resources),owner.error);return owner

func verify(args: PackedStringArray):
	var lib:=Library.new();var bodies:=Bodies.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not bodies.configure(lib,bindings):check(false,lib.error+bindings.error+cat.error+bodies.error);return
	if bindings.station_autopilot.is_empty():check(not Autopilot.new().configure(bindings,cat,construction,resources),"Legacy pack invented station guidance");return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(header.architecture=="x86_64","This verification is scoped to the Mac profile")
	check(Definitions.validate(bindings.station_autopilot,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Valid autopilot declarations were refused")
	for key in Definitions.VALUES:
		var bad: Dictionary=bindings.station_autopilot.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed autopilot parameter accepted: "+key)
	for key in Definitions.SPANS:
		var bad: Dictionary=bindings.station_autopilot.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Detached autopilot provenance accepted: "+key)
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var packet:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3));var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,packet,[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Could not prepare rescue fixture");return
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new();check(station.configure(bindings,cat,lib,arrival.prepare_station()),station.error)
	for i in 19:station.acknowledge()
	if not construction.prepare(bindings,cat,station.prepare_departure(bindings,cat),4096,1789100000,true,bodies) or not resources.configure(lib,bindings,cat,construction):check(false,construction.error+resources.error);return
	var unchanged:=[construction.snapshot(),resources.snapshot(),station.snapshot()]
	var owner:=fresh();var original: Dictionary=owner.snapshot()
	check(not owner.start() and owner.snapshot()==original,"Guidance started without a preceding manual sample")
	var start_pose:=Transform3D(Basis.IDENTITY,Vector3(-20000,0,-20000))
	check(owner.observe_manual(start_pose,Vector2.ZERO) and owner.start(),owner.error)
	var started: Dictionary=owner.snapshot()
	check(started.player_pose==start_pose and started.active and started.throttle==1 and started.events==[{"kind":"notification","source_id":10}],"Selecting a station moved the ship or omitted the source start event")
	check(started.guidance_gain==f32(3.9795455932617188) and started.response_factor==f32(25.590911865234375) and started.bank_limit==f32(365.58447265625),"Handling, pilot response and bank scale were conflated")
	check(owner.advance(100,0.0,0,true) and owner.snapshot()==started,"Paused guidance changed pose or history")
	check(not owner.advance(151,0.0) and not owner.advance(-1,0.0) and not owner.advance(0.5,0.0) and not owner.advance(100,0.0,INF) and not owner.advance(100,0.0,-1) and owner.snapshot()==started,"Invalid guidance frame mutated its owner")
	var clone: RefCounted=owner.fork_for_frame();clone.clear();check(owner.snapshot()==started,"Clearing guidance clone changed the original")
	var detached: Dictionary=owner.snapshot();detached.history[0]=99;detached.events.clear();check(owner.snapshot()==started,"Guidance snapshot exposed mutable state")
	var capture_owners:={"autopilot-start":owner.fork_for_frame()}
	# Independent analytic reference: 100 ms frames, target at zero, start at
	# (-20000,0,-20000), forward +Z. Warm-up and wrapped means differ at frame 5/6.
	var golden:={
		1:[Vector3(0.0703631117939949,0.0,0.9975214600563049),Vector3(-19985.927734375,0.0,-19800.49609375),31.593719482421875,365.58447265625],
		2:[Vector3(0.13536794483661652,0.0,0.990795373916626),Vector3(-19958.853515625,0.0,-19602.337890625),63.18743896484375,365.58447265625],
		5:[Vector3(0.29878637194633484,0.0,0.9543200135231018),Vector3(-19810.216796875,0.0,-19021.634765625),157.96859741210938,348.7641296386719],
		6:[Vector3(0.343473345041275,0.0,0.9391624331474304),Vector3(-19741.521484375,0.0,-18833.802734375),189.56231689453125,310.15478515625],
		10:[Vector3(0.48206809163093567,0.0,0.8761337399482727),Vector3(-19393.779296875,0.0,-18114.068359375),220.9320831298828,220.9320831298828],
		20:[Vector3(0.6521215438842773,0.0,0.7581144571304321),Vector3(-18213.087890625,0.0,-16503.716796875),88.70319366455078,88.70319366455078],
		40:[Vector3(0.7342114448547363,0.0,0.6789208650588989),Vector3(-15381.427734375,0.0,-13681.166015625),13.776895523071289,13.776895523071289]}
	for frame in range(1,41):
		check(owner.advance(100,0.0),owner.error)
		var state: Dictionary=owner.snapshot()
		check(state.history_cursor==frame%5 and state.history_wrapped==(frame>=5),"Turn history wrap differs")
		check(state.player_pose.origin==state.presentation_pose.origin and state.player_pose.basis.y.y==1 and state.model_basis.x.y<0,"Right turn bank moved the root or banked the camera target")
		if golden.has(frame):
			var expected: Array=golden[frame]
			check(state.player_pose.basis.z.is_equal_approx(expected[0]) and state.player_pose.origin.distance_to(expected[1])<.01,"Guidance trajectory differs from independent reference at %d"%frame)
			check(absf(state.bank-expected[2])<.003 and absf(state.target_bank-expected[3])<.003,"Guidance bank/filter differs from independent reference at %d"%frame)
		if frame in [6,10,40]:capture_owners["autopilot-"+str(frame)]=owner.fork_for_frame()
	var moving: Dictionary=owner.snapshot();var cancelled: RefCounted=owner.fork_for_frame()
	check(cancelled.cancel(),cancelled.error)
	var stopped: Dictionary=cancelled.snapshot()
	check(not stopped.active and stopped.history_cursor==0 and not stopped.history_wrapped and stopped.history==moving.history and stopped.bank==moving.bank and stopped.model_basis==moving.model_basis and stopped.player_pose==moving.player_pose,"Cancel discarded retained bank/history or changed position")
	check(stopped.events==[{"kind":"notification","source_id":6}] and not cancelled.advance(100,0.0),"Cancel event or subsequent active-frame gate differs")
	var restart: RefCounted=cancelled.fork_for_frame();check(restart.start() and restart.snapshot().bank==moving.bank and restart.snapshot().player_pose==moving.player_pose,"Immediate restart discarded the established manual bank sample")
	check(cancelled.observe_manual(stopped.player_pose,Vector2(20,-100)) and cancelled.start() and cancelled.snapshot().bank==-100,"Restart ignored the preceding ordinary response")
	check(cancelled.advance(100,0.0),cancelled.error)
	var held:=fresh();check(held.observe_manual(start_pose,Vector2.ZERO) and held.start() and held.advance(100,0.0,0),held.error)
	check(held.snapshot().player_pose.origin==start_pose.origin and held.snapshot().player_pose.basis.z.x>0,"Zero throttle disabled steering or moved the ship")
	check(held.advance(100,80,0) and held.snapshot().angular_units.x==80,"Guidance lost the caller's current pitch response")
	var pitched: Dictionary=held.snapshot();var pitch:=f32(80.0/16384.0*f32(6.2831854820251465))
	check(absf(pitched.model_basis.z.y+sin(pitch))<.00001 and absf(pitched.model_basis.z.z-cos(pitch))<.00001,"Local pitch/roll matrix used the wrong axis or transpose")
	check(not held.advance(100,NAN) and held.snapshot()==pitched,"Invalid pitch response changed active guidance")
	var left:=fresh();check(left.observe_manual(Transform3D(Basis.IDENTITY,Vector3(20000,0,-20000)),Vector2.ZERO) and left.start() and left.advance(100,0.0),left.error)
	check(left.snapshot().bank<0 and left.snapshot().model_basis.x.y>0 and left.snapshot().player_pose.basis.z.x<0,"Mirrored approach has the wrong bank sign")
	var straight:=fresh();check(straight.observe_manual(Transform3D(Basis.IDENTITY,Vector3(0,0,-20000)),Vector2.ZERO) and straight.start() and straight.advance(0,0.0),straight.error)
	check(not straight.snapshot().near_target and straight.snapshot().history_cursor==1 and straight.snapshot().bank==0,"Zero-time guidance lost its source history step or included the strict near boundary")
	check(straight.advance(1,0.0) and not straight.snapshot().near_target and straight.advance(0,0.0) and straight.snapshot().near_target,"Near flag did not sample distance before movement")
	var invalid:=resources.fork_for_frame();invalid._state.station_id=79
	check(not owner.configure(bindings,cat,construction,invalid) and owner.snapshot()==moving,"Wrong station replaced a good guidance owner")
	var bad_pose:=Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)
	check(not held.observe_manual(bad_pose,Vector2.ZERO),"Active guidance accepted a manual pose")
	check(not Autopilot.new().advance(1,0.0) and not Autopilot.new().cancel(),"Unconfigured guidance accepted an operation")
	check(not moving.docking_transition_supported and not moving.avoidance_supported and unchanged==[construction.snapshot(),resources.snapshot(),station.snapshot()],"Guidance granted arrival, changed persistent content or overstated collision support")
	if args.size()==4 and failures==0:await render(args,lib,capture_owners)
	print("Guidance sample: gain ",started.guidance_gain,"; bank limit ",started.bank_limit,"; final bank ",moving.bank)

func render(args: PackedStringArray,lib: RefCounted,captures: Dictionary):
	var visuals:=Visuals.new();check(visuals.open(args[2],lib.manifest),visuals.error)
	var flight:=Frame.new();if not flight.configure(bindings,cat,lib,construction,"E",.5,Vector2i(960,720)):check(false,flight.error);return
	for i in 71:flight=flight.evaluate(100)
	var baseline:=flight.snapshot()
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var scene:=Scene.new();canvas.add_child(scene)
	if not scene.build(lib,bindings,visuals,cat,flight):check(false,scene.error);canvas.free();return
	# Component QA adapter: source scene and camera, synthetic initial pose. It
	# deliberately does not represent an application launch or docking session.
	for label in captures:
		var guide: Dictionary=captures[label].snapshot();var staged: RefCounted=flight.fork_for_frame()
		staged._pose=guide.player_pose;staged._model_basis=guide.model_basis
		var shot: Dictionary=staged._shot.duplicate(true);shot.mode="fixed_eye";shot.eye=guide.player_pose*Vector3(0,650,-1600);shot.inherit_target_up=true
		check(staged._camera.update(1,shot,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"player_pose":guide.player_pose},shot),staged._camera.error)
		check(scene.present(staged),scene.error)
		check(scene.geometry.player.transform.is_equal_approx(guide.presentation_pose) and scene.camera.global_transform.is_equal_approx(staged.snapshot().camera_view.pose),"Guidance body/camera presentation differs")
		for i in 3:await process_frame
		check(canvas.get_texture().get_image().save_png(args[3].path_join(label+".png"))==OK,"Could not save guidance view")
		check(flight.snapshot()==baseline,"Guidance preview mutated the live flight")
	canvas.free()

static func f32(value: float) -> float:return Guidance.single(value)
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)

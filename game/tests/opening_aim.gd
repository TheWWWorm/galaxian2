extends SceneTree
const Aim=preload("res://src/simulation/opening_aim.gd")
const Definitions=preload("res://src/content/player_aim_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const ProjectionFixture=preload("res://tests/flight_projection_fixture.gd")
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Opening aim checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify(content: String, pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var aim:=Aim.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	if bindings.opening_staging.get("player_aim",{}).is_empty():
		check(not aim.configure(bindings) and aim.snapshot().is_empty(),"Legacy bindings invented a retained aim capability");return
	var definition: Dictionary=bindings.opening_staging.player_aim
	var architecture: String="armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	check(Definitions.validate(definition,10000000,architecture,bindings.opening_staging).is_empty(),"Source aim declaration rejected")
	for key in definition.provenance:
		var bad: Dictionary=definition.duplicate(true);bad.provenance[key].offset+=2
		check(not Definitions.validate(bad,10000000,architecture,bindings.opening_staging).is_empty(),"Disconnected aim provenance accepted")
	bindings.flight_projection=ProjectionFixture.definition(true)
	bindings.flight_projection.vertical_fov_radians=PI/2.0
	check(aim.configure(bindings),aim.error)
	check(aim.snapshot().point==Vector3.ZERO and aim.snapshot().contact_ms==0 and not aim.snapshot().contact_active,"Aim did not start from the source zero state")
	var player:=Transform3D(Basis(Vector3.LEFT,Vector3.UP,Vector3.FORWARD),Vector3.ZERO)
	check(aim.advance(player,Transform3D.IDENTITY,Vector2i(800,600)),aim.error)
	check(aim.snapshot().point.is_equal_approx(Vector3(80,60,-4400)),"First aim sample did not use 0.2 of the projected forward point")
	var detached: RefCounted=aim.fork_for_frame()
	check(detached.advance(player,Transform3D.IDENTITY,Vector2i(800,600)),detached.error)
	check(detached.snapshot().point.is_equal_approx(Vector3(144,108,-7920)) and aim.snapshot().point.is_equal_approx(Vector3(80,60,-4400)),"Repeated zero-time sample or detached state lost source smoothing")
	check(detached.advance(player,Transform3D.IDENTITY,Vector2i(1600,1200)),detached.error)
	check(detached.snapshot().point.is_equal_approx(Vector3(275.2,206.4,-10736)),"Resize reset or rescaled retained aim history")
	check(aim.advance(Transform3D.IDENTITY,Transform3D.IDENTITY,Vector2i(800,600)),aim.error)
	check(aim.snapshot().point==Vector3(0,0,22000),"Positive depth was smoothed or forced to screen center")
	# Rear/early rejection exposes raw camera X/Y; no marker ellipse is applied.
	player.origin=Vector3(2200,0,44000)
	check(aim.advance(player,Transform3D.IDENTITY,Vector2i(800,600)),aim.error)
	check(aim.snapshot().point==Vector3(2200,0,22000),"Aim reused target-marker clamping")
	var before:=aim.snapshot()
	check(not aim.advance(player,Transform3D.IDENTITY,Vector2i.ZERO) and aim.snapshot()==before,"Invalid viewport consumed aim history")
	check(not aim.advance(Transform3D(Basis.IDENTITY,Vector3(NAN,0,0)),Transform3D.IDENTITY,Vector2i(800,600)) and aim.snapshot()==before,"Invalid player pose consumed aim history")
	check(aim.sample_feedback(true,200,true),aim.error)
	check(aim.snapshot().contact_flash and aim.snapshot().contact_active and aim.snapshot().contact_ms==200 and aim.snapshot().image_id==1230,"First NPC contact did not show the alternate image")
	check(aim.sample_feedback(true,1,true),aim.error)
	check(aim.snapshot().contact_flash and not aim.snapshot().contact_active and aim.snapshot().contact_ms==201,"Repeated contact restarted timer or expiry hid its final image")
	check(aim.sample_feedback(true,0,true),aim.error)
	check(aim.snapshot().contact_flash and not aim.snapshot().contact_active and aim.snapshot().contact_ms==201,"Contact without an idle draw lost retained expiry")
	check(aim.sample_feedback(false,0,true),aim.error)
	check(not aim.snapshot().contact_flash and aim.snapshot().contact_ms==0 and aim.snapshot().image_id==1216,"Idle draw failed to reset contact feedback")
	check(aim.sample_feedback(true,150,false),aim.error)
	check(aim.snapshot().contact_active and aim.snapshot().contact_ms==0 and not aim.snapshot().visible,"Hidden cinematic draw consumed contact feedback")
	check(aim.sample_feedback(false,100,true),aim.error)
	check(aim.snapshot().contact_flash and aim.snapshot().contact_ms==100,"Visible draw lost pending contact")
	before=aim.snapshot()
	for value in [-1,0.5,true,null,2147483648]:check(not aim.sample_feedback(false,value,true) and aim.snapshot()==before,"Invalid feedback duration changed state")
	check(not aim.configure(null) and aim.snapshot().is_empty(),"Failed configuration retained old profile aim")
	print(library.manifest.profile.edition,": raw projection, lag, resize history, contact expiry and rejected-frame retention verified")

func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)

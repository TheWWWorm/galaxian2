extends SceneTree
const Camera=preload("res://src/simulation/opening_escape_camera.gd")
const View=preload("res://src/simulation/camera_view.gd")
const Definitions=preload("res://src/content/opening_escape_camera_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Opening escape camera checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify(content: String, pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var camera:=Camera.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	if bindings.opening_staging.get("escape_camera",{}).is_empty():
		check(not camera.configure(bindings),"Legacy pack acquired escape shake");return
	if not camera.configure(bindings):check(false,camera.error);return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var rules: Dictionary=bindings.opening_staging.escape_camera
	check(Definitions.validate(rules,header.source_executable_bytes,header.architecture,bindings.opening_staging).is_empty(),"Imported camera proof rejected")
	for key in rules.provenance:
		var bad:=rules.duplicate(true);bad.provenance[key].offset+=2
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.opening_staging).is_empty(),"Disconnected camera proof accepted")
	var target:=Transform3D(Basis(Vector3.BACK,0.3),Vector3(100,200,300))
	var eye:=Vector3(500,900,-1500)
	var view:=View.fixed_eye(eye,target,true)
	view.merge({"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"eye":eye,"look":target.origin,"mode":"fixed_eye"})
	var state:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"phase":6,"eye":eye,
		"shake_strength":0.5,"shake_radius":20,"frame":{"camera_operations":[]}}
	var random:={"state":0}
	var saved:=state.duplicate(true)
	state.eye=eye+Vector3(500,0,0)
	var result:=camera.evaluate(0,state,target,view,random)
	check(not result.is_empty() and result.camera.view==view and result.random_state==random,"Zero-time ordinary update changed view or random state")
	check(result.camera.shot.eye==state.eye,"Zero-time cut lost the stored eye")
	state=saved.duplicate(true)
	state.frame.camera_operations=[{"eye":eye+Vector3(20,0,0),"shake_strength":0.25,"shake_radius":20,"immediate":true}]
	result=camera.evaluate(0,state,target,view,random)
	if result.is_empty():check(false,camera.error);return
	# These integer LCG expectations were computed independently of SeededRandom.
	check(result.immediate_view.look==target.origin+Vector3(-5,4.5,-1.25),"Immediate shake draw/order differs")
	check(result.random_state.state==11718085204285 and result.camera.view==result.immediate_view,"Pan did not consume exactly its immediate pass")
	result=camera.evaluate(100,state,target,view,random)
	if result.is_empty():check(false,camera.error);return
	check(result.camera.view.look==target.origin+Vector3(3,-7,8),"Ordinary shake accumulated prior jitter or used the wrong strength")
	check(result.random_state.state==25707281917278,"Immediate and ordinary camera passes did not share the stream")
	check(result.camera.view.eye==eye and result.immediate_view.eye==eye+Vector3(20,0,0),"Final stored eye replaced an earlier pan view")
	check(result.camera.view.pose.basis.y.dot(target.basis.y)>0.9,"Camera lost target up")
	check(random=={"state":0} and view.eye==eye,"Camera evaluation mutated input state")
	state=saved.duplicate(true);state.shake_strength=0.0;state.shake_radius=0
	result=camera.evaluate(150,state,target,view,random)
	check(not result.is_empty() and result.random_state==random and result.camera.view.look==target.origin,"Inactive shake consumed random values")
	state.eye=target.origin
	check(camera.evaluate(150,state,target,view,random).is_empty(),"Degenerate ordinary view was accepted")
	state=saved.duplicate(true);state.frame.camera_operations=[{"eye":eye,"shake_strength":0.5,"shake_radius":20,"immediate":true}]
	state.eye=target.origin+Vector3(3,-7,8)
	check(camera.evaluate(150,state,target,view,random).is_empty() and random=={"state":0},"Late camera failure consumed the caller's stream")
	state.eye=Vector3(INF,0,0)
	check(camera.evaluate(0,state,target,view,random).is_empty(),"Zero-time frame accepted an invalid stored eye")
	state=saved.duplicate(true);state.binding_id="foreign"
	check(camera.evaluate(100,state,target,view,random).is_empty(),"Foreign escape state was accepted")

func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)

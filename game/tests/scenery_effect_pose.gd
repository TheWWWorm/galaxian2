extends SceneTree
const Poses = preload("res://src/presentation/scenery_effect_pose.gd")
const Clock = preload("res://src/simulation/scenery_effect_clock.gd")
const Resources = preload("res://src/content/scenery_effect_resources.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Fixture = preload("res://tests/scenery_fixture.gd")
var failures := 0

func _initialize() -> void:
	check_math()
	check_ownership()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1])
	print("Scenery effect pose checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_math() -> void:
	var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenery_effect_pose_vectors.json"))
	check(cases is Array and cases.size()==6,"Missing independent orientation vectors")
	if not cases is Array:return
	var position := Vector3(-16.0,32.0,128.0)
	for row in cases:
		var camera := Transform3D(Basis(Vector3.RIGHT,vec(row.camera_up),vec(row.camera_backward)),Vector3(73,-19,4))
		var result := Poses.alpha_root(camera,position,row.scale)
		check(not result.has("error"),str(result))
		if result.has("error"):continue
		for axis in 3:
			for component in 3:
				check(bits(result.pose.basis[axis][component])==int(row.column_bits[axis][component]),"Source float32 orientation changed: "+row.name)
		check(result.pose.origin==position,"Alpha root translation was scaled or replaced")
		camera.origin=position
		camera.basis.x=Vector3(-9,7,12)
		check(Poses.alpha_root(camera,position,row.scale)==result,"Unused camera axis or eye position changed the alpha basis")
	var underflow := Transform3D(Basis(Vector3.RIGHT,Vector3(0,1e-30,0),Vector3.BACK),Vector3.ZERO)
	var pose: Transform3D = Poses.alpha_root(underflow,position,1.0).pose
	check(pose.basis==Basis(Vector3.UP,Vector3.LEFT,Vector3.BACK),"Squared-length underflow lost the exact +Y fallback")
	for invalid in [null,true,"1",0,-1,INF,NAN,1e100,1e-100]:
		check(Poses.alpha_root(Transform3D.IDENTITY,position,invalid).has("error"),"Invalid scale accepted")
	for invalid in [Transform3D(Basis(Vector3.RIGHT,Vector3(INF,0,0),Vector3.BACK),Vector3.ZERO),
		Transform3D(Basis.IDENTITY,Vector3(NAN,0,0)),
		Transform3D(Basis(Vector3.RIGHT,Vector3(0,1e30,0),Vector3.BACK),Vector3.ZERO),
		Transform3D(Basis(Vector3.RIGHT,Vector3(0,1e30,0),Vector3(0,0,1e30)),Vector3.ZERO)]:
		check(Poses.alpha_root(invalid,position,1.0).has("error"),"Nonfinite or overflowing orientation accepted")
	check(Poses.alpha_root(Transform3D.IDENTITY,Vector3(INF,0,0),1.0).has("error"),"Nonfinite root position accepted")
	var large_backward := Transform3D(Basis(Vector3.RIGHT,Vector3.UP,Vector3(0,0,1e10)),Vector3.ZERO)
	check(Poses.alpha_root(large_backward,position,1e30).has("error"),"Scaled basis overflow accepted")

func check_ownership() -> void:
	check(Poses.for_effect(null,Transform3D.IDENTITY).has("error") and Poses.for_effect(RefCounted.new(),Transform3D.IDENTITY).has("error"),"Unrelated clock owner accepted")
	check(Poses.for_effect(Clock.new(),Transform3D.IDENTITY).has("error"),"Unconfigured clock produced a pose")
	var bindings: RefCounted = Fixture.make()[0]
	bindings.frame_clock={"time_unit":"milliseconds","max_frame_milliseconds":100}
	bindings.scenery_effects={"variants":[],"speed_threshold":1,"speed_base":1,"speed_scale":3,"provenance":{}}
	for index in 4:
		bindings.scenery_effects.variants.append({"base_model_id":bindings.scenery_resources.model_ids[index],"effect_type":index+2,"model_ids":[200+index*2,201+index*2]})
	for index in 4:
		var variant: Dictionary = bindings.scenery_effects.variants[index]
		var effect := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"base_model_id":variant.base_model_id,
			"effect_type":variant.effect_type,"duration_ms":100,"models":[]}
		for model_index in 2:
			effect.models.append({"model_id":variant.model_ids[model_index],"resource":Resources.PATHS[index][model_index],"start_ms":1,"end_ms":100})
		check_clock(bindings,effect,0.5)

func check_clock(bindings: RefCounted, effect: Dictionary, scale: float) -> void:
	var clock := Clock.new()
	check(clock.configure(bindings,effect,scale),clock.error)
	if clock.snapshot().is_empty():return
	check(Poses.for_effect(clock,Transform3D.IDENTITY)=={"visible":false},"Untriggered effect became visible")
	var initial := Transform3D(Basis.from_euler(Vector3(0.3,-0.8,1.2),EULER_ORDER_XYZ).scaled(Vector3.ONE*scale),Vector3(18,-20,54))
	check(clock.trigger(initial),clock.error)
	var before := clock.snapshot()
	var result := Poses.for_effect(clock,Transform3D.IDENTITY)
	check(result.visible and result.alpha==Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*before.scale),initial.origin),"Alpha root retained asteroid rotation or applied scale twice")
	check(result.breakup==initial and clock.snapshot()==before,"Presentation changed the breakup pose or clock state")
	result.breakup.origin=Vector3.ZERO
	check(clock.snapshot()==before,"Returned presentation poses alias the clock")
	var camera := Transform3D(Basis(Vector3.UP,Vector3.LEFT,Vector3.BACK),Vector3(7,8,9))
	var rolled := Poses.for_effect(clock,camera)
	check(rolled.alpha.basis==camera.basis.scaled(Vector3.ONE*before.scale) and rolled.breakup==initial,"Active camera roll was lost or applied to breakup")
	check(Poses.for_effect(clock,Transform3D(Basis.IDENTITY,Vector3(INF,0,0))).has("error") and clock.snapshot()==before,"Invalid camera modified a live effect")
	check(clock.update(16),clock.error)
	check(Poses.for_effect(clock,camera)==rolled,"Clock sampling time moved the root pose")
	while clock.snapshot().active:check(clock.update(100),clock.error)
	check(Poses.for_effect(clock,camera)=={"visible":false},"Expired effect remained visible")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var resources := Resources.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not resources.configure(library,bindings):
		check(false,library.error+bindings.error+resources.error);return
	for variant in bindings.scenery_effects.variants:
		for scale in [0.3,1.0,2.0]:check_clock(bindings,resources.effect_for_model(int(variant.base_model_id)),scale)
	print(library.manifest.profile.edition,": active/inactive root poses verified for all four effects")

func vec(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])

func bits(value: float) -> int:
	return PackedFloat32Array([value]).to_byte_array().decode_u32(0)

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)

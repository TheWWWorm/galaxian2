extends SceneTree
const Motion = preload("res://src/simulation/scenery_motion.gd")
const Fixture = preload("res://tests/scenery_fixture.gd")
var failures := 0
func _initialize() -> void:
	var data := Fixture.make();var bindings: RefCounted = data[0]
	bindings.frame_clock={"time_unit":"milliseconds","max_frame_milliseconds":1000}
	var angles := Vector3(6.282,0.002,-100)
	var initial := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"objects":[{"index":0,"angles":angles,"basis":Basis.from_euler(angles,EULER_ORDER_XYZ),"spin":Vector3(0.1,-0.1,0.05)},
		{"index":1,"angles":Vector3.ZERO,"basis":Basis.IDENTITY,"spin":Vector3.ZERO}]}
	var motion := Motion.new()
	check(not motion.update(1),"Unconfigured motion accepted")
	check(motion.configure(bindings,initial),motion.error)
	for iteration in 500:
		for delta in [0,1,16,17,33,100,1000]:check(motion.update(delta),motion.error)
	var result := motion.snapshot();var final_angles: Vector3 = result.objects[0].angles
	var bytes := PackedFloat32Array([final_angles.x,final_angles.y,final_angles.z]).to_byte_array()
	for axis in 3:check(bytes.decode_u32(axis*4)==[1115767538,3261686595,3264063104][axis],"Independent per-frame float32 spin reference differs")
	check(final_angles.x>TAU and final_angles.y<0,"Source Euler accumulation must not wrap")
	check(result.objects[1]==initial.objects[1],"Zero-spin scenery changed")
	check(result.objects[0].basis.is_equal_approx(Basis.from_euler(final_angles,EULER_ORDER_XYZ)),"Spin did not rebuild XYZ orientation")
	check(motion.update(0) and motion.snapshot()==result,"Frozen presentation changed scenery")
	for bad in [-1,1001,0.5,true,null]:check(not motion.update(bad) and motion.snapshot()==result,"Invalid delta changed scenery")
	initial.objects[0].spin=Vector3.ONE;result.objects[0].angles=Vector3.INF
	check(motion.snapshot().objects[0].angles==final_angles,"Motion state aliases caller input/output")
	var valid := motion.snapshot()
	check(motion.update(100,[true,false]) and motion.snapshot()==valid,"Per-actor spin mask was ignored")
	for bad_mask in [[true],[false,false,false],[1,false]]:
		check(not motion.update(100,bad_mask) and motion.snapshot()==valid,"Malformed spin mask changed motion")
	for scenario in ["identity","angle","basis","spin","order"]:
		var malformed := valid.duplicate(true)
		if scenario=="identity":malformed.binding_id="f".repeat(64)
		elif scenario=="angle":malformed.objects[0].angles=Vector3.INF
		elif scenario=="basis":malformed.objects[0].basis=Basis.IDENTITY
		elif scenario=="spin":malformed.objects[0].spin=Vector3(2,0,0)
		else:malformed.objects[0].index=2
		check(not motion.configure(bindings,malformed) and motion.snapshot().is_empty(),"Failed reconfigure retained scenery")
	print("Scenery motion: %d failures" % failures)
	quit(1 if failures else 0)
func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)

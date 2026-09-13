extends SceneTree
const Flight = preload("res://src/simulation/npc_flight.gd")
const Definitions = preload("res://src/content/npc_flight_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
var failures := 0

func _initialize() -> void:
	var unconfigured := Flight.new()
	check(not unconfigured.configure(null,Transform3D.IDENTITY),"Unconfigured NPC flight accepted content")
	check(unconfigured.advance(1,Vector3.RIGHT,2,true).is_empty(),"Unconfigured flight advanced")
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("NPC flight checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, bindings_path: String) -> void:
	var library := Library.new()
	var bindings := Bindings.new()
	if not library.open(content) or not bindings.open(bindings_path,library.manifest):
		check(false,library.error+bindings.error)
		return
	var flight := Flight.new()
	var data: Dictionary = bindings.opening_actors.npc_initialization.get("flight",{})
	if data.is_empty():
		check(not flight.configure(bindings,Transform3D.IDENTITY) and flight.snapshot().is_empty(),"Legacy pack invented NPC motion")
		return
	check(Definitions.parameters(data),"Imported NPC flight parameters rejected")
	var architecture := "armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	var executable_bytes := 0
	for span in data.provenance.values(): executable_bytes=maxi(executable_bytes,int(span.offset)+int(span.bytes))
	check(Definitions.validate(data,executable_bytes,architecture).is_empty(),"Source NPC flight provenance rejected")
	for key in data.provenance:
		var bad := data.duplicate(true)
		bad.provenance[key].bytes+=1
		check(not Definitions.validate(bad,executable_bytes,architecture).is_empty(),"Invalid NPC extent accepted: "+key)
	var overlapping := data.duplicate(true)
	overlapping.provenance.virtual_update.offset=overlapping.provenance.actor_wrapper.offset
	check(not Definitions.validate(overlapping,executable_bytes,architecture).is_empty(),"Overlapping NPC provenance accepted")
	check(not Definitions.validate(data,executable_bytes-1,architecture).is_empty(),"Truncated NPC source extent accepted")
	for key in data:
		var bad := data.duplicate(true)
		bad.erase(key)
		check(not Definitions.parameters(bad),"Missing flight field accepted: "+key)
	for key in ["turn_scale","heading_snap_l1","bank_limit","bank_gain","bank_slew_numerator","bank_slew_divisor","bank_angle_scale"]:
		for value in [NAN,INF,-1.0,0.0,true]:
			var bad := data.duplicate(true)
			bad[key]=value
			check(not Definitions.parameters(bad),"Invalid flight parameter accepted: "+key)
	check(data.turn_numerator==48 and data.turn_scale==1.0/65536 and data.heading_snap_l1==0.0625 and data.bank_limit==750 and data.bank_samples==5,"Source NPC tuning changed")
	if not flight.configure(bindings,Transform3D.IDENTITY):
		check(false,flight.error)
		return
	var result := flight.advance(16,Vector3.RIGHT,2.9,true)
	if result.is_empty():
		check(false,flight.error)
		return
	# Independent one-step geometry: move toward +X from +Z by a 48/65536
	# correction per millisecond; yaw is small, not an immediate look-at.
	var correction := 16.0*48.0/65536.0/sqrt(2.0)
	var expected := Vector3(correction,0,1-correction).normalized()
	check(result.root_pose.basis.z.distance_to(expected)<0.000001,"NPC turn rate or direction changed")
	check(result.travel_units==46 and result.root_pose.origin.distance_to(expected*46)<0.00002,"NPC translation was not truncated before axis scaling")
	check(result.bank<0 and absf(result.bank+5.1282053)<0.000001,"Right turn bank sign or slew changed")
	check(result.pose.origin==result.root_pose.origin and result.pose.basis.z.distance_to(result.root_pose.basis.z)<0.000001,"Bank altered forward translation")
	check(not result.pose.basis.x.is_equal_approx(result.root_pose.basis.x),"Bank was omitted from the combat/visual pose")
	var saved := flight.snapshot()
	var fork: RefCounted = flight.fork_for_frame()
	check(not fork.advance(16,Vector3.LEFT,2,true).is_empty() and flight.snapshot()==saved,"NPC flight fork aliases live state")
	result=flight.advance(0,Vector3.RIGHT,2,true)
	check(not result.is_empty() and result.root_pose.origin==saved.root_pose.origin and result.bank==saved.bank,"Zero-time update translated or rolled the NPC")
	# Repeated sub-unit travel is discarded each source frame, not accumulated.
	flight.configure(bindings,Transform3D.IDENTITY)
	for i in 10:
		result=flight.advance(1,Vector3(0,0,1),0.9,false)
		check(not result.is_empty() and result.root_pose.origin==Vector3.ZERO,"NPC retained fractional travel across frames")
	check(flight.advance(1,Vector3(0,0,1),2.9,false).root_pose.origin==Vector3(0,0,2),"NPC per-frame quantization changed")
	# Steering permission resets history and returns bank toward level while
	# travel permission is independent of that decision.
	flight.configure(bindings,Transform3D.IDENTITY)
	flight.advance(16,Vector3.RIGHT,2,true)
	saved=flight.snapshot()
	result=flight.advance(100,Vector3.RIGHT,2,false,false)
	check(result.root_pose==saved.root_pose and result.bank==0 and result.target_bank==0 and result.history_cursor==0 and not result.history_wrapped,"Straight-flight reset or independent travel permission changed")
	flight.configure(bindings,Transform3D.IDENTITY)
	var near_heading := Vector3(0.03,0,1).normalized()
	result=flight.advance(0,near_heading,2,true)
	check(result.root_pose.basis.z.distance_to(near_heading)<0.000001,"Source near-heading snap was lost on a zero-duration update")
	flight.configure(bindings,Transform3D.IDENTITY)
	result=flight.advance(0,Vector3(0.2,0,1),2,true)
	check(result.root_pose.basis.z==Vector3(0,0,1),"Distant heading snapped without a turn step")
	flight.configure(bindings,Transform3D.IDENTITY)
	result=flight.advance(16,Vector3(0,0,1),2,true)
	check(result.root_pose.basis==Basis.IDENTITY and result.bank==0,"Aligned small-step heading drifted despite source snapping")
	check_history(bindings,data)
	flight.configure(bindings,Transform3D.IDENTITY)
	saved=flight.snapshot()
	for delta in [-1,0.5,1.0,true,2147483647]:
		check(flight.advance(delta,Vector3.RIGHT,2,true).is_empty() and flight.snapshot()==saved,"Invalid NPC duration changed state")
	for speed in [-1,INF,NAN,true,1.0e30]:
		check(flight.advance(16,Vector3.RIGHT,speed,true).is_empty() and flight.snapshot()==saved,"Invalid NPC speed changed state")
	for direction in [null,Vector3(INF,0,0),Vector3(1.0e30,0,0)]:
		check(flight.advance(16,direction,2,true).is_empty() and flight.snapshot()==saved,"Invalid/overflowing heading partly committed flight")
	check(flight.advance(1,Vector3.RIGHT,2,1).is_empty() and flight.snapshot()==saved,"Non-boolean steering permission accepted")
	# A large step snaps to the old up axis and makes the source cross products
	# degenerate. This unsupported pose must fail after staging without committing.
	check(flight.advance(1931,Vector3.UP,2,true).is_empty() and flight.snapshot()==saved,"Late singular pose failure partly committed motion")
	# A sustained, bounded flight run exercises basis stability and separation of
	# banked visual axes from the unbanked steering frame.
	for i in 600:
		var angle := float(i)*0.005
		result=flight.advance(16,Vector3(sin(angle),0.1*sin(angle*2),cos(angle)),2,true)
		if result.is_empty():
			check(false,"Sustained NPC steering failed: "+flight.error)
			break
		check(Flight.rigid_pose(result.root_pose) and Flight.rigid_pose(result.pose),"NPC basis drifted during sustained steering")
	check(not flight.configure(bindings,Transform3D(Basis.from_scale(Vector3(2,1,1)),Vector3.ZERO)) and flight.snapshot().is_empty(),"Scaled initial NPC pose accepted")
	check(flight.configure(bindings,Transform3D.IDENTITY),flight.error)
	bindings.opening_actors.npc_initialization.flight={}
	check(not flight.configure(bindings,Transform3D.IDENTITY) and flight.snapshot().is_empty(),"Missing tuning retained old NPC state")
	bindings.opening_actors.npc_initialization.flight=data
	print(library.manifest.profile.edition,": NPC steering, banking, quantization and rollback verified")

func check_history(bindings: RefCounted, data: Dictionary) -> void:
	var flight := Flight.new()
	flight.configure(bindings,Transform3D.IDENTITY)
	var means := [0.01,0.01,0.015,0.02,0.025,0.04]
	for i in means.size():
		flight.record_turn(Vitals.single((i+1)*0.01))
		var expected := Vitals.single(Vitals.single(means[i]*data.bank_limit)*data.bank_gain)
		check(absf(flight.snapshot().target_bank-expected)<0.0001,"NPC bank warmup included the new sample too early")
	check(flight.snapshot().history_cursor==1 and flight.snapshot().history_wrapped,"NPC bank history did not wrap after five samples")
	for i in 5: flight.record_turn(2)
	check(flight.snapshot().target_bank==data.bank_limit,"NPC bank limit was not applied")
	for i in 5: flight.record_turn(-2)
	check(flight.snapshot().target_bank==-data.bank_limit,"NPC opposite bank limit was not applied")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)

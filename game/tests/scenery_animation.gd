extends SceneTree
const Sampler = preload("res://src/presentation/scenery_animation.gd")
const Keys = preload("res://src/content/scenery_animation_keys.gd")
const AEM = preload("res://src/content/aem.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
var failures := 0

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1])
	print("Scenery animation checks: %d failures" % failures)
	quit(1 if failures else 0)

func vector_track(first: float, value: Vector3, last: float, end: Vector3) -> Dictionary:
	return {"dimensions":3,"keys":PackedFloat32Array([first,value.x,value.y,value.z,last,end.x,end.y,end.z])}

func shape(pivot: Vector3, translation: Vector3, rotation: Vector3, scale: Vector3, scalar := 100.0, first := 0.0) -> Dictionary:
	return {"pivot":pivot,"tracks":{
		"translation":[vector_track(first,translation,10.0,translation)],
		"rotation":[vector_track(first,rotation,10.0,rotation)],
		"scale":[vector_track(first,scale,10.0,scale)],
		"scalar":[{"dimensions":1,"keys":PackedFloat32Array([first,scalar,10,scalar])}]}}

func check_synthetic() -> void:
	var animation := Sampler.new()
	check(animation.sample(0,Transform3D.IDENTITY).is_empty(),"Unconfigured animation sampled")
	var raw := [shape(Vector3(2,3,4),Vector3(10,20,30),Vector3(0,0,PI/2),Vector3(2,3,4)),{"pivot":Vector3(8,9,10),"tracks":{}}]
	var before: Array=raw.duplicate(true)
	check(animation.configure(raw),animation.error)
	var parent := Transform3D(Basis.IDENTITY,Vector3(100,200,300))
	var result := animation.sample(10,parent)
	check(not result.is_empty(),animation.error)
	if result.is_empty():return
	var expected := Transform3D(Basis(Vector3(0,0,-2),Vector3(0,3,0),Vector3(4,0,0)),Vector3(124,212,331))
	check(result.surfaces[0].pose.is_equal_approx(expected),"Converted pivot, local scale or parent composition changed")
	check(result.surfaces[0].color_byte==255 and result.surfaces[0].animated,"Initial source color changed")
	check(result.surfaces[1]=={"animated":false,"pose":parent},"Unanimated surface pivot or tint was applied")
	check(raw==before,"Sampling changed raw source channels")
	check(animation.sample(0,parent)==result and animation.sample(10000000,parent)==result,"Start/end clamp changed")
	var state := animation.snapshot()
	result.surfaces[0].pose.origin=Vector3.ZERO
	check(animation.snapshot()==state,"Returned poses alias animation state")
	for bad in [null,true,"10",10.0,-1,NAN,INF]:
		check(animation.sample(bad,parent).is_empty() and animation.snapshot()==state,"Invalid time changed animation state")
	check(animation.sample(10,Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))).is_empty() and animation.snapshot()==state,"Nonfinite parent changed state")
	# A positive fractional source key truncates to zero. Rewinding to that first
	# record retains the already evaluated geometry and color, as the source does.
	var retained := shape(Vector3.ZERO,Vector3(7,8,9),Vector3.ZERO,Vector3.ONE,50.0,0.5)
	check(animation.configure([retained]),animation.error)
	var initial := animation.sample(0,Transform3D.IDENTITY)
	check(initial.surfaces[0].pose==Transform3D.IDENTITY and initial.surfaces[0].color_byte==255,"First record overwrote fresh geometry or packed color")
	var end := animation.sample(10,Transform3D.IDENTITY)
	check(end.surfaces[0].pose.origin==Vector3(7,8,9) and end.surfaces[0].color_byte==127,"Positive key or scalar sampling failed")
	check(animation.sample(0,Transform3D.IDENTITY)==end,"First-record rewind reset the retained geometry")
	for scalar in [-100.0,200.0]:
		check(animation.configure([shape(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ONE,scalar)]),animation.error)
		check(animation.sample(10,Transform3D.IDENTITY).surfaces[0].color_byte==(1 if scalar<0 else 254),"Source color byte was clamped instead of truncated and wrapped")
	var advancing := shape(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ONE)
	advancing.tracks.translation=[vector_track(0.0,Vector3.ZERO,10.0,Vector3.ONE*10)]
	advancing.tracks.rotation=[vector_track(1.0,Vector3.ZERO,10.0,Vector3.ZERO)]
	check(animation.configure([advancing,shape(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ONE*1e10)]),animation.error)
	state=animation.snapshot()
	check(animation.sample(10,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*1e30),Vector3.ZERO)).is_empty() and animation.snapshot()==state,"World transform overflow was not atomic")
	check(animation.sample(10,parent).surfaces[0].pose.origin==parent.origin+Vector3.ONE*10,"Valid sample did not advance after a later-surface failure")
	for invalid in [[shape(Vector3(INF,0,0),Vector3.ZERO,Vector3.ZERO,Vector3.ONE)],
		[shape(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ONE,1e20)],[],[{}]]:
		check(not animation.configure(invalid) and animation.snapshot().is_empty(),"Unsupported configuration retained a usable animation")
	check(animation.configure(before),animation.error)
	check(not animation.sample(10,parent).is_empty() and animation.error.is_empty(),"Failed request contaminated a new configuration")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	var identifiers := {}
	for variant in bindings.scenery_effects.variants:
		for model in variant.model_ids:identifiers[int(model)]=true
	check(identifiers.size()==7,"Expected seven distinct effect resources")
	var parent := Transform3D(Basis(Vector3(0,0,-2),Vector3(0,3,0),Vector3(4,0,0)),Vector3(137,-91,205))
	var report := {};var count := 0
	for identifier in identifiers:
		var reader := AEM.new()
		var model := reader.decode(library.read_resource(bindings.resolve(identifier,"mesh"),AEM.MAX_BYTES))
		if model.is_empty():check(false,reader.error);continue
		var animation := Sampler.new()
		if not animation.configure(model.surfaces):check(false,animation.error);continue
		var compiler := Keys.new();var tables := compiler.prepare(model.surfaces)
		var schedule := {0:true}
		for table in tables.surfaces:
			for index in table.times.size():
				var time_ms: int=table.times[index]
				for value in [maxi(time_ms-1,0),time_ms,time_ms+1]:schedule[value]=true
				if index>0:schedule[int((time_ms+table.times[index-1])/2)]=true
		var times := schedule.keys();times.sort();times.append(0)
		var frames := []
		for time_ms in times:
			var packet := animation.sample(time_ms,parent)
			check(not packet.is_empty(),animation.error)
			if packet.is_empty():continue
			check(packet.surfaces.size()==model.surfaces.size(),"Effect surface order changed")
			var frame := []
			for surface in packet.surfaces:
				check(surface.pose.is_finite(),"Nonfinite effect world pose")
				var values := [surface.get("color_byte",-1)]
				for column in 3:
					for row in 3:values.append(bits(surface.pose.basis[column][row]))
				for row in 3:values.append(bits(surface.pose.origin[row]))
				frame.append(values);count+=1
			frames.append(frame)
		report[str(identifier)]={"times":times,"frames":frames}
	var destination := OS.get_environment("GOF2_ANIMATION_REPORT_DIR")
	if not destination.is_empty():
		var file := FileAccess.open(destination.path_join(library.manifest.profile.edition+"-native-animation.json"),FileAccess.WRITE)
		check(file!=null,"Cannot write native animation report")
		if file!=null:file.store_string(JSON.stringify(report)+"\n")
	print(library.manifest.profile.edition,": ",count," surface world poses sampled")

func bits(value: float) -> int:
	return PackedFloat32Array([value]).to_byte_array().decode_u32(0)

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)

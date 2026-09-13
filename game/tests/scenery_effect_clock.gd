extends SceneTree
const Clock = preload("res://src/simulation/scenery_effect_clock.gd")
const Resources = preload("res://src/content/scenery_effect_resources.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Fixture = preload("res://tests/scenery_fixture.gd")
var failures := 0

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1])
	print("Scenery effect clock checks: %d failures" % failures)
	quit(1 if failures else 0)

func fixture(variant := 0) -> Array:
	var bindings: RefCounted = Fixture.make()[0]
	bindings.scenery_resources.model_ids=[100,101,102,103]
	bindings.frame_clock={"time_unit":"milliseconds","max_frame_milliseconds":100}
	bindings.scenery_effects={"variants":[],"speed_threshold":1.0,"speed_base":1.0,"speed_scale":3.0,"provenance":{}}
	for index in 4:
		bindings.scenery_effects.variants.append({"base_model_id":100+index,"effect_type":index+2,"model_ids":[200+index*2,201+index*2]})
	var declaration: Dictionary = bindings.scenery_effects.variants[variant]
	var models := []
	for index in 2:
		models.append({"model_id":declaration.model_ids[index],"resource":Resources.PATHS[variant][index],
			"start_ms":33 if variant==2 else 50,"end_ms":10000 if variant==2 and index==1 else 10050})
	var effect := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"base_model_id":declaration.base_model_id,"effect_type":declaration.effect_type,"models":models,"duration_ms":10050}
	return [bindings,effect]

func check_synthetic() -> void:
	var clock := Clock.new()
	check(not clock.configure(null,{},1.0) and clock.snapshot().is_empty(),"Missing effect source accepted")
	check(not clock.configure(RefCounted.new(),{},1.0) and clock.snapshot().is_empty(),"Unrelated source object accepted")
	check(not clock.trigger(Transform3D.IDENTITY) and not clock.update(0),"Unconfigured effect accepted an operation")
	var pair := fixture()
	for vector in [[0.3,0x40466666,3241,49],[0.5,0x40200000,4020,40],
		[0.9,0x3fa66667,7730,20],[1.0,0x3f800000,10050,16],[2.0,0x3f800000,10050,16]]:
		check(clock.configure(pair[0],pair[1],vector[0]),clock.error)
		var state := clock.snapshot()
		check(reference_bits(state.speed)==vector[1] and state.duration_ms==vector[2],"Source float32 scale/duration vector changed at scale %s" % vector[0])
		check(clock.trigger(Transform3D.IDENTITY) and clock.update(16),clock.error)
		check(clock.snapshot().models[0].time_ms==50+vector[3],"Source per-frame time truncation changed")
	for variant in 4:
		pair=fixture(variant)
		for scale in [0.3,0.5,0.9,0.99999995,1.0,1.00000005,2.0]:
			check_prefixes(pair[0],pair[1],scale)
	# Trigger captures only the initial pose, without consuming its actor frame.
	pair=fixture()
	check(clock.configure(pair[0],pair[1],0.3),clock.error)
	var before := clock.snapshot()
	check(not before.active and not before.triggered and not before.finished and before.pose==null,"Fresh effect is not inert")
	check(clock.update(100) and clock.snapshot()==before,"Inactive effect consumed presentation time")
	var pose := Transform3D(Basis.from_euler(Vector3(0.2,-0.7,1.1)).scaled(Vector3.ONE*0.3),Vector3(100,-50,70))
	var bad_pose := pose;bad_pose.origin.x=INF
	check(not clock.trigger(bad_pose) and clock.snapshot()==before,"Nonfinite trigger changed effect state")
	check(clock.trigger(pose),clock.error)
	before=clock.snapshot()
	check(before.pose==pose and before.elapsed_ms==0 and before.models[0].time_ms==50,"Trigger advanced time or lost the initial transform")
	check(not clock.trigger(pose) and clock.snapshot()==before,"Repeated trigger restarted an active effect")
	check(clock.update(0) and clock.snapshot()==before,"Zero presentation time advanced the effect")
	for invalid in [-1,0.5,true,null,"16",INF,NAN,101]:
		check(not clock.update(invalid) and clock.snapshot()==before,"Invalid effect frame changed state")
	# A snapshot, configured input, or speculative fork cannot own this state.
	var detached := clock.snapshot();detached.models[0].time_ms=999;detached.models.clear()
	pair[1].models[0].start_ms=800;pair[0].scenery_effects.speed_scale=999.0
	check(clock.snapshot()==before,"Effect state leaked through descriptor or snapshot")
	var fork: RefCounted = clock.fork_for_frame()
	check(fork.snapshot()==before and fork.update(16),fork.error)
	check(clock.snapshot()==before and fork.snapshot().models[0].time_ms==99,"Speculative clock update changed the original")
	check(fork.update(16),fork.error)
	check(clock.update(32),clock.error)
	check(fork.snapshot().models[0].time_ms==148 and clock.snapshot().models[0].time_ms==149,"Frame subdivision lost source quantization")
	# Exact model-end time retains its playback flag; only exceeding it stops it.
	pair=fixture(2);check(clock.configure(pair[0],pair[1],1.0) and clock.trigger(pose),clock.error)
	advance(clock,9967)
	check(clock.snapshot().models[1].time_ms==10000 and clock.snapshot().models[1].playing,"Model stopped at equality")
	check(clock.update(1),clock.error)
	check(not clock.snapshot().models[1].playing and clock.snapshot().models[0].playing,"Shorter breakup model did not clamp independently")
	advance(clock,82)
	check(clock.snapshot().active and clock.snapshot().elapsed_ms==10050,"Effect stopped at lifetime equality")
	check(clock.update(1),clock.error)
	var completed := clock.snapshot()
	check(completed.finished and completed.triggered and not completed.active and completed.elapsed_ms==0,"Expiry did not reset the effect clock")
	for model in completed.models:check(model.time_ms==model.start_ms and model.playing,"Expiry did not rewind and arm both model clocks")
	check(not clock.trigger(pose) and clock.snapshot()==completed,"Completed one-shot effect restarted")
	check(clock.update(100) and clock.snapshot()==completed,"Completed effect advanced without a new owner")
	# Per-frame lost fractions can leave a model unfinished at lifetime expiry.
	pair=fixture();check(clock.configure(pair[0],pair[1],0.3) and clock.trigger(pose),clock.error)
	for index in 202:check(clock.update(16),clock.error)
	check(clock.snapshot().elapsed_ms==3232 and clock.snapshot().models[0].time_ms==9948 and clock.snapshot().models[0].playing,"Quantized prefix unexpectedly reached its final key")
	check(clock.update(16) and clock.snapshot().finished,"Lifetime incorrectly waited for model completion")
	# A positive authored range can truncate to a zero lifetime after scaling.
	pair=fixture()
	for model in pair[1].models:model.start_ms=0;model.end_ms=1
	pair[1].duration_ms=1
	check(clock.configure(pair[0],pair[1],0.5) and clock.trigger(pose),clock.error)
	check(clock.snapshot().duration_ms==0 and clock.update(0) and clock.snapshot().active,"Zero scaled lifetime did not preserve its trigger frame")
	check(clock.update(1) and clock.snapshot().finished,"Zero scaled lifetime failed to expire after positive time")
	pair=fixture()
	for invalid in [0,-1,true,null,"1",NAN,INF,1e100,1e-100]:
		check(not clock.configure(pair[0],pair[1],invalid) and clock.snapshot().is_empty(),"Invalid scale retained a prior effect")
	for invalid in ["identity","model","order","path","start","end","duration","declarations","frame"]:
		pair=fixture()
		match invalid:
			"identity":pair[1].binding_id="c".repeat(64)
			"model":pair[1].base_model_id=999
			"order":pair[1].models.reverse()
			"path":pair[1].models[0].resource="resources/data/../unexpected.aem"
			"start":pair[1].models[0].start_ms=50.5
			"end":pair[1].models[0].end_ms=49
			"duration":pair[1].duration_ms=9999
			"declarations":pair[0].scenery_effects.speed_scale=4.0
			"frame":pair[0].frame_clock.max_frame_milliseconds=0
		check(not clock.configure(pair[0],pair[1],1.0) and clock.snapshot().is_empty(),"Invalid effect configuration retained state: "+invalid)
	clock.clear()
	check(clock.snapshot().is_empty() and clock.fork_for_frame().snapshot().is_empty(),"Clear or empty fork retained effect state")

func check_prefixes(bindings: RefCounted, effect: Dictionary, scale: float) -> void:
	var clock := Clock.new()
	if not clock.configure(bindings,effect,scale):check(false,clock.error);return
	check(clock.trigger(Transform3D.IDENTITY),clock.error)
	# Independent prefix sums derive time from all rounded frame contributions;
	# they do not call the component's helpers or model its mutable stop flags.
	var speed := reference_float(1.0+reference_float(reference_float(1.0-reference_float(scale))*3.0)) if reference_float(scale)<1.0 else 1.0
	var duration := int(reference_float(10050.0/speed))
	var elapsed := 0
	var accumulated := 0
	var frames := [0,1,7,16,32,80,100]
	for index in 400:
		var delta: int = frames[index%frames.size()]
		check(clock.update(delta),clock.error)
		elapsed+=delta
		accumulated+=int(reference_float(float(delta)*speed))
		var state := clock.snapshot()
		check(state.active==(elapsed<=duration) and state.finished==(elapsed>duration),"Effect lifetime disagrees with independent prefix")
		if elapsed>duration:break
		check(state.elapsed_ms==elapsed,"Unscaled lifetime accumulated model speed")
		for model_index in 2:
			var model: Dictionary = state.models[model_index]
			var expected: int = int(effect.models[model_index].start_ms)+accumulated
			check(model.time_ms==mini(expected,int(effect.models[model_index].end_ms)),"Model time disagrees with rounded prefix sum")
			check(model.playing==(expected<=int(effect.models[model_index].end_ms)),"Model stop flag changed at the wrong boundary")
	check(clock.snapshot().finished,"Bounded prefix did not reach effect expiry")

func check_profile(content: String, binding_path: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var resources := Resources.new()
	if not library.open(content) or not bindings.open(binding_path,library.manifest) or not resources.configure(library,bindings):
		check(false,library.error+bindings.error+resources.error);return
	for variant in 4:
		var declaration: Dictionary = bindings.scenery_effects.variants[variant]
		var effect := resources.effect_for_model(int(declaration.base_model_id))
		if effect.is_empty():check(false,resources.error);continue
		for index in 2:
			check(effect.models[index].start_ms==(33 if variant==2 else 50),"Actual model start lost positive-key truncation")
			check(effect.models[index].end_ms==(10000 if variant==2 and index==1 else 10050),"Actual model end changed")
		for scale in [0.3,0.5,0.9,1.0,2.0]:check_prefixes(bindings,effect,scale)
	print(library.manifest.profile.edition,": four effect variants and independent scaled clocks verified")

func advance(clock: RefCounted, milliseconds: int) -> void:
	var remaining := milliseconds
	while remaining>0:
		var delta := mini(remaining,100)
		check(clock.update(delta),clock.error)
		remaining-=delta

func reference_float(value: float) -> float:
	var bytes := PackedByteArray();bytes.resize(4);bytes.encode_float(0,value)
	return bytes.decode_float(0)

func reference_bits(value: float) -> int:
	var bytes := PackedByteArray();bytes.resize(4);bytes.encode_float(0,value)
	return bytes.decode_u32(0)

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)

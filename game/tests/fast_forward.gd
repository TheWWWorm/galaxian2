extends SceneTree
const Fast=preload("res://src/simulation/fast_forward.gd")
const Definitions=preload("res://src/content/fast_forward_definitions.gd")
const Clock=preload("res://src/simulation/frame_clock.gd")
const Rig=preload("res://src/simulation/camera_rig.gd")
const CameraFixture=preload("res://tests/camera_follow_fixture.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
var failures:=0
var checks:=0

func _initialize() -> void:
	verify_declarations()
	var bindings:=Bindings.new()
	bindings.base_content_id="a".repeat(64);bindings.binding_id="b".repeat(64)
	bindings.frame_clock={"max_frame_milliseconds":150,"time_unit":"milliseconds"}
	bindings.camera_follow=CameraFixture.definition()
	var fast:=Fast.new()
	check(not fast.configure(bindings) and fast.snapshot().is_empty(),"Old pack invented acceleration")
	check(Clock.simulation_limit(bindings)==150,"Old pack lost its ordinary time bound")
	bindings.fast_forward=Definitions.VALUES.duplicate(true)
	bindings.fast_forward.provenance={}
	check(fast.configure(bindings),fast.error)
	if not fast.error.is_empty():quit(1);return
	check(Clock.simulation_limit(bindings)==750,"Verified accelerated bound is missing")
	var clock:=Clock.new()
	check(clock.configure(bindings,bindings.base_content_id) and clock.rebase(0),clock.error)
	check(is_equal_approx(clock.sample(1000000,false),0.150),"Fast capability changed the raw clock clamp")
	for navigation in [false,true]:
		for battle in [false,true]:
			for near_target in [false,true]:
				check(fast.release() and fast.press(navigation,battle,near_target),fast.error)
				check(fast.held() and fast.active()==(navigation and not battle and not near_target),"Eligibility changed navigation/combat semantics")
	check(fast.release() and fast.press(false,false,false),fast.error)
	check(fast.press(true,false,false) and not fast.active(),"Unrouted held input silently armed later")
	check(fast.release() and fast.press(true,false,false),fast.error)
	for milliseconds in range(151):
		var step:=fast.frame(milliseconds,false,false,false)
		check(step.real_ms==milliseconds and step.simulation_ms==milliseconds*5 and step.camera_ms==milliseconds and step.camera_passes==5,"Fast frame lost single scaled simulation / five camera scheduling")
	for invalid in [-1,151,0.5,true,NAN,INF]:
		var before:=fast.snapshot()
		check(fast.frame(invalid,false,false,false).is_empty() and fast.snapshot()==before,"Bad raw interval changed acceleration")
	var retained:=fast.snapshot()
	var paused:=fast.frame(150,true,true,true,true)
	check(paused.real_ms==150 and paused.simulation_ms==0 and paused.camera_passes==0 and fast.snapshot()==retained,"Pause changed real time or ran active cancellation/simulation")
	for cause in range(3):
		check(fast.release() and fast.press(true,false,false),fast.error)
		var step:=fast.frame(150,cause==0,cause==1,cause==2)
		check(step.reset and step.simulation_ms==150 and step.camera_passes==1 and fast.held() and not fast.active(),"Cancellation happened after time scaling or cleared held input")
		check(fast.press(true,false,false) and not fast.active(),"Repeated down rearmed automatic cancellation")
		check(fast.frame(150,false,false,false).simulation_ms==150,"Removing the cancellation cause rearmed held input")
	check(fast.release() and fast.press(true,false,false),fast.error)
	check(fast.release(false) and fast.held() and not fast.active(),"Other control release cleared the physical time hold")
	check(fast.press(true,false,false) and not fast.active(),"Other control release allowed held input to rearm")
	check(fast.release() and fast.press(true,false,false) and fast.active(),"New down after release could not rearm")
	var branch: RefCounted=fast.fork_for_frame()
	check(branch.frame(16,false,true,false).reset and fast.active(),"Rejected prospective frame changed its parent")
	var exposed:=fast.snapshot();exposed.active=false
	check(fast.active(),"Published state mutated the owner")
	check(fast.release(),fast.error)
	for milliseconds in range(151):
		var step:=fast.frame(milliseconds,false,false,false)
		check(step.simulation_ms==milliseconds and step.camera_ms==milliseconds and step.camera_passes==1,"Ordinary frame time changed")
	verify_camera(bindings)
	verify_radar(bindings)
	check(fast.press(true,false,false),fast.error)
	bindings.fast_forward.timing.fast_multiplier=6
	check(fast.frame(150,false,false,false).simulation_ms==750,"External binding mutation changed an accepted owner's timing")
	check(not fast.configure(bindings) and fast.snapshot().is_empty(),"Unsupported multiplier retained active state")
	check(Clock.simulation_limit(bindings)==150,"Invalid declaration widened simulation bounds")
	print("Fast Forward: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_declarations() -> void:
	var origin:=1000000
	var source_bytes:=10000000
	var arrival:={"provenance":{"actor":{"offset":origin,"bytes":315}}}
	var layouts:=[[Definitions.SPANS,Definitions.RADAR_SPANS],[Definitions.MAC_ALTERNATE,Definitions.RADAR_MAC_ALTERNATE]]
	for index in layouts.size():
		var rules: Dictionary=Definitions.VALUES.duplicate(true)
		rules.provenance=proof_extents(layouts[index][0],origin)
		check(Definitions.validate(rules,source_bytes,"x86_64",arrival).is_empty(),"Previous Fast Forward declarations lost compatibility")
		rules.radar=Definitions.RADAR_VALUES.duplicate(true)
		rules.radar.provenance=proof_extents(layouts[index][1],origin)
		check(Definitions.validate(rules,source_bytes,"x86_64",arrival).is_empty(),"Coherent radar declarations were rejected")
		var mixed: Dictionary=rules.duplicate(true)
		mixed.radar.provenance=proof_extents(layouts[1-index][1],origin)
		check(not Definitions.validate(mixed,source_bytes,"x86_64",arrival).is_empty(),"Radar accepted proofs from a different executable layout")
		var truncated: Dictionary=rules.duplicate(true)
		truncated.radar.provenance.erase("base_constructor")
		check(not Definitions.validate(truncated,source_bytes,"x86_64",arrival).is_empty(),"Radar accepted an incomplete constructor proof")
		var shifted: Dictionary=rules.duplicate(true)
		shifted.radar.provenance.base_constructor.offset+=1
		check(not Definitions.validate(shifted,source_bytes,"x86_64",arrival).is_empty(),"Radar accepted a shifted proof extent")
		check(not Definitions.validate(rules,origin+315,"x86_64",arrival).is_empty(),"Radar accepted proofs beyond its source file")
		check(not Definitions.validate(rules,source_bytes,"arm64",arrival).is_empty(),"Radar accepted an unverified source architecture")
		var invented: Dictionary=rules.duplicate(true)
		invented.radar.distance_filter=true
		check(not Definitions.validate(invented,source_bytes,"x86_64",arrival).is_empty(),"Radar accepted an unverified distance rule")

func proof_extents(layout: Dictionary,origin: int) -> Dictionary:
	var result:={}
	for key in layout:result[key]={"offset":origin+int(layout[key][0]),"bytes":int(layout[key][1])}
	return result

func verify_camera(bindings: RefCounted) -> void:
	var rig:=Rig.new()
	check(rig.configure(bindings),rig.error)
	var shot:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"mode":"fixed_eye","target":"player","eye":Vector3(-120,40,-300),"inherit_target_up":true}
	var scene:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"player_pose":Transform3D(Basis.IDENTITY,Vector3(400,-50,700))}
	check(rig.update(16,shot,scene),rig.error)
	var view:=rig.snapshot()
	check(rig.response_snapshot().cached_handling==100 and rig.set_fast_forward(true),rig.error)
	check(rate_bits(rig)==[0x3b449ba6,0x3c449ba6],"Initial cached100 rates differ from source floats")
	check(rig.snapshot()==view and rig.response_snapshot().fast,"Changing rates replaced the camera pose")
	check(rig.refresh_player_response(true,50) and rig.response_snapshot().cached_handling==100 and rig.response_snapshot().dirty,"Fast mode refreshed the retained handling cache")
	check(rig.set_fast_forward(false) and rig.response_snapshot().dirty and rig.refresh_player_response(true,50),rig.error)
	check(rig.response_snapshot().cached_handling==50 and rate_bits(rig)==[0x3c2c0830,0x3bd4fdf4],"Captured refresh did not use current handling")
	check(rig.refresh_player_response(false,50),rig.error)
	check(rate_bits(rig)==[0x3c2c0830,0x3bd4fdf4] and not rig.response_snapshot().dirty,"A policy change bypassed the player refresh flag")
	rig.mark_response_dirty()
	check(rig.refresh_player_response(false,50),rig.error)
	check(rig.response_snapshot().cached_handling==50 and rate_bits(rig)==[0x3ba3d70a,0x3bc49ba6],"Uncaptured refresh lost the cache or normal rates")
	check(rig.set_fast_forward(true) and rate_bits(rig)==[0x3c2c0830,0x3bd4fdf4],"Fast transition ignored handling retained across policy changes")
	check(rig.refresh_player_response(true,100) and rig.response_snapshot().cached_handling==50,"Held Fast Forward consumed a handling change")
	var fork: RefCounted=rig.fork_for_frame()
	check(fork.set_fast_forward(false) and fork.refresh_player_response(true,100),fork.error)
	check(fork.response_snapshot().cached_handling==100 and rig.response_snapshot().cached_handling==50,"Camera fork changed parent cache")
	check(rig.set_fast_forward(false) and rig.response_snapshot().dirty,"Release did not dirty normal player response")
	check(rig.refresh_player_response(false,100) and rate_bits(rig)==[0x3ba3d70a,0x3bc49ba6] and rig.response_snapshot().cached_handling==50,"Next player update did not restore the selected policy")
	for bad in [NAN,INF,-1.0,0.0]:
		var before:=rig.response_snapshot()
		check(not rig.refresh_player_response(true,bad) and rig.response_snapshot()==before and rig.snapshot()==view,"Invalid handling changed view or cache")
	check(not rig.update(151,shot,scene),"Camera accepted a scaled world interval")
	check(rig.snapshot()==view,"Response changes moved the camera before its scheduled pass")

func rate_bits(rig: RefCounted) -> Array:
	var data: Dictionary=rig.response_snapshot()
	var bytes:=PackedFloat32Array([data.look_rate,data.eye_rate]).to_byte_array()
	return [bytes.decode_u32(0),bytes.decode_u32(4)]

func verify_radar(bindings: RefCounted) -> void:
	check(not Definitions.radar_available(bindings.fast_forward),"Old177 core invented the supplemental radar capability")
	var rules: Dictionary=bindings.fast_forward.duplicate(true)
	rules.radar=Definitions.RADAR_VALUES.duplicate(true);rules.radar.provenance={}
	bindings.fast_forward=rules
	var cat:=Catalogues.new();cat.content_id=bindings.base_content_id
	cat.tables={"items":[{"arrays":[[],[],PackedInt32Array([0,0,0,0,0,17])]},{"arrays":[[],[],PackedInt32Array([0,0,0,0,0,21])]}]}
	var fast:=Fast.new()
	check(fast.configure(bindings) and fast.configure_radar(cat,[0]),fast.error)
	var actor:={"actor_kind":8,"active":true,"hostile":true,"actor_mode":0,"hull":0,"position":Vector3(1e8,1e8,1e8),"cargo":true,"targeting_blocked":true}
	check(fast.publish_radar([actor],true) and fast.battle(),"Battle used hull, cargo, targeting or distance in place of the source predicate")
	check(fast.publish_radar([],false) and fast.battle(),"Hidden radar cleared a previously published battle")
	for mode in [3,4]:
		var dead:=actor.duplicate(true);dead.actor_mode=mode
		check(fast.publish_radar([dead],true) and not fast.battle(),"Retained dead cargo counted as combat")
	for field in ["active","hostile"]:
		var absent:=actor.duplicate(true);absent[field]=false
		check(fast.publish_radar([absent],true) and not fast.battle(),"Inactive or friendly actor counted as combat")
	var junk:=actor.duplicate(true);junk.population_group="debris"
	check(fast.publish_radar([junk],true) and not fast.battle(),"Junk counted as a hostile ordinary ship")
	check(fast.publish_radar([actor],true),fast.error)
	var before:=fast.snapshot()
	for field in ["active","hostile","actor_mode"]:
		var bad:=actor.duplicate(true);bad.erase(field)
		check(not fast.publish_radar([actor,bad],true) and fast.snapshot()==before,"Late invalid radar actor partly published combat")
	for kind in [9,10]:
		var unsupported:=actor.duplicate(true);unsupported.actor_kind=kind
		check(not fast.publish_radar([unsupported],true) and fast.snapshot()==before,"Special actor gained unverified radar state")
	check(fast.publish_radar([],true,143) and fast.snapshot()==before,"Special music mode replaced the retained radar sample")
	check(fast.publish_radar([actor,actor,actor],true) and fast.battle_count()==3 and fast.battle(),"Radar reduced the accepted enemy count to a boolean")
	check(fast.publish_radar([],false) and fast.battle_count()==3,"Hidden radar discarded the accepted enemy count")
	check(fast.radar_music_context()=={"radar_kind10":false},"Missing legacy actor markers silently implied unmarked battle music")
	var marked:=actor.duplicate(true);marked.radar_marked_actor=true
	check(fast.publish_radar([actor,marked],true) and fast.battle_count()==2 and fast.radar_music_context().get("radar_marked_actor")==true,"Counted source marker did not reach music selection")
	marked.hostile=false
	check(fast.publish_radar([marked],true) and fast.battle_count()==0 and fast.radar_music_context().get("radar_marked_actor")==false,"Uncounted marker selected special battle music")
	check(fast.publish_radar([actor],true),fast.error)
	var fork: RefCounted=fast.fork_for_frame()
	check(fork.publish_radar([],true) and not fork.battle() and fast.battle(),"Radar fork mutated the accepted battle flag")
	check(fast.configure_radar(cat,[1]) and fast.publish_radar([actor],true) and not fast.battle(),"Built-in scanner fallback invented an installed type17 scanner")
	check(fast.configure_radar(cat,[0]) and fast.press(true,false,false),fast.error)
	check(fast.publish_radar([actor],true) and fast.active(),"HUD publication cancelled acceleration before the next frame")
	check(fast.frame(150,fast.battle(),false,false).simulation_ms==150 and fast.held() and not fast.active(),"Next frame did not consume the published battle")
	bindings.fast_forward=rules.duplicate(true);bindings.fast_forward.erase("radar")

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)

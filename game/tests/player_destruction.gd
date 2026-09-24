extends SceneTree
## Mac component checks. Departure, lethal hull and close render cameras are
## disclosed fixtures; this does not claim a connected game-over playthrough.
const Fixture=preload("res://tests/full_hold_flight.gd")
const Death=preload("res://src/simulation/player_destruction.gd")
const Definitions=preload("res://src/content/player_destruction_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Geometry=preload("res://src/presentation/npc_death_effect_geometry.gd")
const Poses=preload("res://src/presentation/npc_destruction_pose.gd")
const Ship=preload("res://src/presentation/ship_geometry.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Numbers=preload("res://src/simulation/combat_vitals.gd")
const CAMERA=Transform3D(Basis.IDENTITY,Vector3(0,600,-1338))
const POSE=Transform3D(Basis.IDENTITY,Vector3(100,-50,70))
const INITIAL_RNG={"state":25214903917}
var checks:=0
var failures:=0
var lib:=Library.new()
var bindings:=Bindings.new()
var cat:=Catalogues.new()
var construction:=Construction.new()
var resources:=Resources.new()
var player: RefCounted
var reference: Dictionary
var capture_states:={}

func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	print("Player destruction: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	check(bindings.source_architecture=="x86_64","This verification is Mac only")
	if bindings.player_destruction.is_empty():
		check(not Death.new().configure(bindings,resources,construction),"Older pack fabricated player destruction")
		return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	var rules: Dictionary=bindings.player_destruction
	check(Definitions.validate(rules,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_flight,bindings.opening_actors).is_empty(),"Player destruction declaration refused")
	for key in Definitions.VALUES:
		var bad:=rules.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed destruction parameter accepted: "+key)
	for key in Definitions.SPANS:
		var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_flight,bindings.opening_actors).is_empty(),"Detached destruction extent accepted: "+key)
	verify_reader(args[1],header)
	var fixture:=Fixture.new()
	var packet: Dictionary=fixture.packet_fixture(bindings,cat,3);fixture.free()
	if not construction.prepare(bindings,cat,packet,4096,1789100000) or not resources.configure(lib,bindings):check(false,construction.error+resources.error);return
	reference=construction.snapshot();player=construction.player_owner()
	# Only this detached player's hull is exhausted. The station cache, cargo,
	# source loadout, earned progress and resource declarations remain unchanged.
	player._state.vitals.hull=0
	verify_invalid()
	verify_pose_handoff()
	verify_lifetime()
	check(construction.snapshot()==reference,"Destruction modified its prepared departure or earned progress")
	check(player.snapshot().vitals.hull==0 and player.snapshot().gamma==100,"Destruction healed or reset the external player")
	if failures==0:await verify_geometry(args)

func started(cursor:=5) -> RefCounted:
	var death:=Death.new()
	if not death.configure(bindings,resources,construction) or not death.start(player,POSE,Vector3.ZERO,CAMERA,cursor):check(false,death.error);return null
	return death

func advance_to(death: RefCounted, target_ms: int, rng: Dictionary, pose:=POSE) -> Dictionary:
	var state:=rng.duplicate(true)
	while death.snapshot().elapsed_ms<target_ms:
		var delta:=mini(100,target_ms-int(death.snapshot().elapsed_ms))
		var result: Dictionary=death.advance(delta,pose,state)
		if result.is_empty():check(false,death.error);return {}
		state=result.random_state
	return state

func verify_lifetime():
	var death: RefCounted=started()
	if death==null:return
	var initial: Dictionary=death.snapshot()
	check(initial.phase=="tumble" and initial.elapsed_ms==0 and initial.player_updates==0 and not initial.effect.active,"Lethal poll advanced the new effect")
	check(initial.fragments.is_empty() and initial.effect.models.size()==2 and initial.effect.duration_ms==4500,"Player borrowed NPC debris or lost authored effect timing")
	check(initial.body_visible and not initial.hud_visible and not initial.camera_follow_enabled and not initial.statistics_active,"Death entry visibility/activity differs from source")
	check(initial.events.sound_events.is_empty() and initial.events.stop_sound_ids==[27,35,2261,2260,2252,1095,1096,1097] and initial.events.stop_current_engine_sound,"Player entry used an NPC tumble sound or lost sound-stop commands")
	check(death.request_exit().is_empty() and death.snapshot()==initial,"Death entry accepted an early exit")
	var paused: Dictionary=death.advance(150,POSE,INITIAL_RNG,true)
	check(not paused.is_empty() and death.snapshot()==initial and paused.random_state==INITIAL_RNG,"Pause advanced death, RNG or sound events")
	var short: RefCounted=death.fork_for_frame();var long: RefCounted=death.fork_for_frame()
	check(not short.advance(0,POSE,INITIAL_RNG).is_empty() and not long.advance(150,POSE,INITIAL_RNG).is_empty(),"Zero/positive frame refused")
	var once:=Vector3.ONE*Numbers.single(0.03)
	check(short.snapshot().model_rotation==once and long.snapshot().model_rotation==once,"Death rotation depends on elapsed time")
	check(short.snapshot().elapsed_ms==0 and long.snapshot().elapsed_ms==150 and death.snapshot()==initial,"Fork or zero-time update changed its retained owner")
	check(short.snapshot().statistics_pose==POSE and short.snapshot().body_pose.basis.is_equal_approx(analytic_xyz(once)),"Death spin did not follow the statistics sample")
	var rng:=advance_to(death,2999,INITIAL_RNG)
	check(rng==INITIAL_RNG and death.snapshot().body_visible and not death.snapshot().effect.active,"Pre-breakup animation drew randomness or hid the ship")
	capture_states.tumble=death.fork_for_frame()
	var moved:=POSE;moved.origin+=Vector3(90,10,150)
	var result: Dictionary=death.advance(1,moved,rng)
	if result.is_empty():check(false,death.error);return
	var broken: Dictionary=death.snapshot()
	check(result.events.breakup and broken.elapsed_ms==3000 and not broken.body_visible and broken.effect.active,"Exact breakup boundary differs from source")
	check(result.random_state=={"state":205749139540596} and result.events.sound_events==[19],"Player breakup did not consume exactly one source sound draw")
	check(broken.effect.position==moved.origin and result.events.audio_events==[{"source_id":19,"position":moved.origin}],"Player effect used a stale physical position")
	check(broken.effect.elapsed_ms==0 and broken.effect.models[0].time_ms==33 and broken.effect.models[1].time_ms==33,"Breakup advanced positive-start model clocks")
	check(broken.particle_emitting and not broken.particle_drawing and result.events.particle_events==[{"emitting":false,"drawing":false,"impact_requested":true},{"emitting":true}],"Breakup and later poll collapsed independent particle flags")
	rng=result.random_state
	result=death.advance(1,moved,rng)
	check(not result.is_empty() and death.snapshot().elapsed_ms==3001 and death.snapshot().effect.elapsed_ms==0,"Old timer exactly3000 lost its source update gap")
	result=death.advance(1,moved,rng)
	check(not result.is_empty() and death.snapshot().effect.elapsed_ms==1 and death.snapshot().effect.models[0].time_ms==34,"Effect failed to advance after the exact3000 gap")
	advance_to(death,3801,rng,moved);capture_states.explosion=death.fork_for_frame()
	advance_to(death,7501,rng,moved)
	check(death.snapshot().effect.active and death.snapshot().effect.elapsed_ms==4500,"Shared effect expired at lifetime equality")
	result=death.advance(1,moved,rng)
	check(not result.is_empty() and result.events.expired and not death.snapshot().effect.active and death.snapshot().effect.models[0].time_ms==33,"Effect did not rewind strictly after4500")
	advance_to(death,8000,rng,moved)
	check(not death.snapshot().failed and death.snapshot().camera_pose==CAMERA,"Failure triggered at8000 or moved the frozen camera")
	result=death.advance(1,moved,rng)
	check(not result.is_empty() and result.events.failed and result.events.sound_events==[37] and death.snapshot().phase=="game_over_delay" and death.snapshot().failure_elapsed_ms==0,"Failure did not begin strictly after8000")
	for i in 30:result=death.advance(100,moved,rng)
	check(death.snapshot().failure_elapsed_ms==3000 and death.snapshot().fade_elapsed_ms==0 and not death.snapshot().game_over_visible,"Game-over fade began at delay equality")
	result=death.advance(1,moved,rng)
	check(death.snapshot().failure_elapsed_ms==3001 and death.snapshot().fade_elapsed_ms==1 and death.snapshot().game_over_visible and death.snapshot().game_over_alpha_byte==0,"Game-over fade lost the crossing frame")
	for i in 39:result=death.advance(100,moved,rng)
	result=death.advance(98,moved,rng)
	var fading: Dictionary=death.snapshot()
	check(fading.fade_elapsed_ms==3999 and fading.player_updates_enabled and not fading.continue_enabled and fading.game_over_alpha_byte==254,"Fade ended before4000")
	check(death.request_exit().is_empty() and death.snapshot()==fading,"Fade accepted an early continuation")
	result=death.advance(1,moved,rng)
	var ready: Dictionary=death.snapshot()
	check(ready.fade_elapsed_ms==4000 and ready.continue_enabled and ready.game_over_alpha_byte==255 and not ready.player_updates_enabled,"Completed fade did not release explicit continuation")
	var changed_statistics: Transform3D=ready.statistics_pose;changed_statistics.origin+=Vector3.RIGHT
	check(death.advance(0,moved,rng,false,changed_statistics).is_empty() and death.snapshot()==ready,"Completed fade accepted a changed statistics pose")
	var changed_physical:=moved;changed_physical.origin+=Vector3.UP
	check(death.advance(0,changed_physical,rng).is_empty() and death.snapshot()==ready,"Completed fade accepted player movement")
	result=death.advance(150,moved,rng)
	check(not result.is_empty() and death.snapshot().elapsed_ms==ready.elapsed_ms and death.snapshot().model_rotation==ready.model_rotation and death.snapshot().player_updates==ready.player_updates,"Player continued after fade completion")
	check(result.random_state==rng and result.events.sound_events.is_empty(),"Game-over wait replayed audio or randomness")
	var packet: Dictionary=death.request_exit()
	check(packet=={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"source_state":1,"campaign_cursor":5},"Game-over acknowledgement changed campaign state or invented a retry")
	var accepted: Dictionary=death.snapshot()
	check(death.request_exit().is_empty() and death.snapshot()==accepted and not death.advance(100,moved,rng).is_empty() and death.snapshot()==accepted,"Pending exit replayed acknowledgement or continued death")
	var overshoot: RefCounted=started(4)
	advance_to(overshoot,2999,INITIAL_RNG)
	result=overshoot.advance(150,POSE,INITIAL_RNG)
	check(not result.is_empty() and result.events.breakup and overshoot.snapshot().elapsed_ms==3149 and overshoot.snapshot().effect.elapsed_ms==0,"Breakup overshoot leaked into effect animation")

func verify_pose_handoff():
	var death:=Death.new();check(death.configure(bindings,resources,construction),death.error)
	var bank:=Basis(Vector3.BACK,1.1)
	var prior_statistics:=POSE*Transform3D(Basis(Vector3.RIGHT,-0.2),Vector3.ZERO)
	check(death.start(player,POSE,Vector3.ZERO,CAMERA,5,bank,prior_statistics),death.error)
	var initial: Dictionary=death.snapshot()
	check(initial.body_pose==POSE*Transform3D(bank,Vector3.ZERO) and initial.statistics_pose==prior_statistics,"Lethal handoff lost the separately sampled visual or statistics bank")
	check(initial.model_rotation==Vector3.ZERO and initial.elapsed_ms==0,"Visual banking became death Euler angles or advanced the death clock")
	capture_states.bank_entry=death.fork_for_frame()
	var moved:=Transform3D(Basis(Vector3.UP,0.15),POSE.origin+Vector3(10,-20,30))
	var next_statistics:=moved*Transform3D(Basis(Vector3.BACK,0.7),Vector3.ZERO)
	var guided: RefCounted=death.fork_for_frame()
	var result: Dictionary=guided.advance(0,moved,INITIAL_RNG,false,next_statistics)
	check(not result.is_empty(),guided.error)
	var once:=Vector3.ONE*Numbers.single(0.03)
	check(guided.snapshot().body_pose.basis.is_equal_approx(moved.basis*analytic_xyz(once)) and guided.snapshot().model_rotation==once,"First death spin accumulated the bank instead of the stored Euler state")
	check(guided.snapshot().statistics_pose==next_statistics and guided.snapshot().physical_pose==moved,"Death tail overwrote the guided statistics sample or physical pose")
	check(guided.snapshot().camera_pose==CAMERA and result.random_state==INITIAL_RNG,"Pose handoff moved the camera or consumed randomness")
	check(death.snapshot()==initial and guided.presentation_identity()==death.presentation_identity(),"Detached handoff mutated its owner or replaced its presentation identity")
	capture_states.bank_tumble=guided.fork_for_frame()
	var manual: RefCounted=death.fork_for_frame()
	result=manual.advance(16,moved,INITIAL_RNG)
	check(not result.is_empty() and manual.snapshot().statistics_pose==moved*Transform3D(bank,Vector3.ZERO),"First manual death motion sampled stored Euler instead of the preceding visual bank")
	var next_pose:=moved;next_pose.origin+=Vector3(0,0,12)
	result=guided.advance(16,next_pose,INITIAL_RNG)
	check(not result.is_empty() and guided.snapshot().statistics_pose.basis.is_equal_approx(next_pose.basis*analytic_xyz(once)) and guided.snapshot().statistics_pose.origin==next_pose.origin,"Manual motion after guided death lost the previous tumble matrix")
	# A mining movement owner can retain an older statistics position. Death
	# must preserve that explicit sample without guessing a new flight pose.
	var mining:=Death.new();check(mining.configure(bindings,resources,construction),mining.error)
	var retained:=Transform3D(Basis(Vector3.UP,-0.3),POSE.origin-Vector3(70,10,50))
	var euler:=Vector3(0.2,-0.1,0.4)
	check(mining.start(player,POSE,euler,CAMERA,4,bank,retained),mining.error)
	var before: Dictionary=mining.snapshot()
	check(not mining.advance(150,moved,INITIAL_RNG,true,next_statistics).is_empty() and mining.snapshot()==before,"Pause accepted new physical or statistics poses")
	result=mining.advance(0,moved,INITIAL_RNG,false,retained)
	var angles:=Vector3(Numbers.single(euler.x+once.x),Numbers.single(euler.y+once.y),Numbers.single(euler.z+once.z))
	check(not result.is_empty() and mining.snapshot().statistics_pose==retained and mining.snapshot().physical_pose==moved,"Death invented a statistics update for a retained mining sample")
	check(mining.snapshot().model_rotation==angles and mining.snapshot().body_pose.basis.is_equal_approx(moved.basis*analytic_xyz(angles)),"Retained Euler state was reset by the visual pose handoff")
	before=mining.snapshot()
	var scaled:=Transform3D(Basis.from_scale(Vector3(2,1,1)),Vector3.ZERO)
	var non_finite:=POSE;non_finite.origin.x=NAN
	for sample in [false,{},Basis.IDENTITY,scaled,non_finite]:
		check(mining.advance(0,moved,INITIAL_RNG,false,sample).is_empty() and mining.snapshot()==before,"Malformed statistics sample partially advanced destruction")
	var unused:=Death.new();check(unused.configure(bindings,resources,construction),unused.error)
	before=unused.snapshot()
	for pair in [[bank,null],[null,retained],[false,retained],[scaled.basis,retained],[bank,scaled],[bank,non_finite],[bank,{}]]:
		check(not unused.start(player,POSE,euler,CAMERA,4,pair[0],pair[1]) and unused.snapshot()==before,"Incomplete or malformed pose handoff started destruction")
	check(unused.start(player,POSE,euler,CAMERA,4) and unused.snapshot().body_pose.basis.is_equal_approx(analytic_xyz(euler)),"Existing Euler-only caller lost its initial visual pose")

func verify_invalid():
	var death: RefCounted=started()
	if death==null:return
	var previous: Dictionary=death.snapshot()
	for delta in [-1,751 if not bindings.fast_forward.is_empty() else 151,0.5,true,null,"16",INF,NAN]:
		check(death.advance(delta,POSE,INITIAL_RNG).is_empty() and death.snapshot()==previous,"Invalid frame changed death state")
	for rng in [null,{},0,{"state":-1},{"state":true},{"state":281474976710656}]:
		check(death.advance(0,POSE,rng).is_empty() and death.snapshot()==previous,"Invalid random stream changed death state")
	check(not death.start(player,POSE,Vector3.ZERO,CAMERA,5) and death.snapshot()==previous,"Repeated start reset death clocks")
	for bad in [null,RefCounted.new()]:
		check(not death.configure(bad,resources,construction) and death.snapshot()==previous,"Invalid bindings replaced accepted destruction")
		check(not death.configure(bindings,bad,construction) and death.snapshot()==previous,"Invalid resources replaced accepted destruction")
	var unused:=Death.new();check(unused.configure(bindings,resources,construction),unused.error)
	var initial: Dictionary=unused.snapshot()
	var alive: RefCounted=construction.player_owner()
	check(not unused.start(alive,POSE,Vector3.ZERO,CAMERA,4) and unused.snapshot()==initial,"Living player was destroyed")
	for cursor in [null,true,4.0,3,6,"5"]:check(not unused.start(player,POSE,Vector3.ZERO,CAMERA,cursor) and unused.snapshot()==initial,"Invalid story cursor started destruction")
	var bad_pose:=POSE;bad_pose.basis.x*=2
	check(not unused.start(player,bad_pose,Vector3.ZERO,CAMERA,4) and unused.snapshot()==initial,"Scaled physical root started destruction")
	var saved: Dictionary=resources._state.duplicate(true);resources._state.models[0].model_id=1
	check(not death.configure(bindings,resources,construction) and death.snapshot()==previous,"Changed model binding replaced accepted destruction")
	resources._state=saved
	var external: Dictionary=death.snapshot();external.effect.models.clear();external.fragments.append({})
	check(death.snapshot()==previous,"Snapshot exposed effect or fragment storage")
	death.clear();check(death.snapshot().is_empty() and death.fork_for_frame().snapshot().is_empty() and death.presentation_identity()==null,"Clear retained destruction state")

func verify_reader(pack: String, header: Dictionary):
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-player-destruction-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","type","value","extent","flight_absent","effect_absent","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("player_destruction")
			"type":changed.player_destruction=false
			"value":changed.player_destruction.fragment_count=3
			"extent":changed.player_destruction.provenance.death_start.offset+=1
			"flight_absent":changed.full_hold_flight={}
			"effect_absent":changed.opening_actors.npc_initialization.destruction={}
			"empty":
				changed.player_destruction={}
				if changed.has("game_over_presentation"):changed.game_over_presentation={}
				if changed.has("full_hold_particles"):changed.full_hold_particles={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,lib.manifest),reader.error)
		var accepted:=reader.open(directory,lib.manifest)
		check(accepted and reader.player_destruction.is_empty() if scenario=="empty" else not accepted and reader.binding_id.is_empty() and reader.player_destruction.is_empty(),"Malformed destruction reader retained stale state: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func verify_geometry(args: PackedStringArray):
	var visuals:=Visuals.new();check(visuals.open(args[2],lib.manifest),visuals.error)
	var canvas:=SubViewport.new();canvas.size=Vector2i(800,600);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.08,.12,.18);canvas.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-25,0);canvas.add_child(light)
	var camera:=Camera3D.new();camera.current=true;camera.near=.1;camera.far=100000;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;canvas.add_child(camera)
	var geometry:=Geometry.new();canvas.add_child(geometry)
	var body:=Ship.new();canvas.add_child(body)
	if not body.build(0,lib,visuals,bindings) or not body.apply_detail(0,1):check(false,body.error);canvas.free();return
	for stage in ["bank_entry","bank_tumble","tumble","explosion"]:
		var owner: RefCounted=capture_states[stage]
		if stage in ["bank_entry","tumble"]:
			if not geometry.build(lib,visuals,bindings,owner):check(false,geometry.error);canvas.free();return
			check(geometry.models.size()==2 and geometry.models[0].surfaces.size()==3 and geometry.models[1].surfaces.size()==10,"Player renderer regenerated NPC debris or lost source surfaces")
		var state: Dictionary=owner.snapshot()
		camera.size=12000 if stage=="explosion" else 1500
		camera.position=state.physical_pose.origin+Vector3(0,0,10000);camera.basis=Basis.IDENTITY
		body.transform=state.body_pose;body.visible=state.body_visible
		check(geometry.apply_effect(owner,camera.transform,PackedByteArray([255,255,255,255]),Vector4.ONE,1),geometry.error)
		check(geometry.body_visible==state.body_visible and geometry.visible==state.effect.active and owner.snapshot()==state,"Shared renderer changed player clocks or body cutoff")
		var poses:=Poses.for_death(owner,camera.transform)
		check(poses.roots.size()==(2 if stage=="explosion" else 0),"Player effect roots included absent fragments")
		if args.size()==4 and DisplayServer.get_name()!="headless":
			for i in 5:await process_frame
			await RenderingServer.frame_post_draw
			var shot:=canvas.get_texture().get_image();var colors:={}
			for y in range(0,600,5):
				for x in range(0,800,5):colors[shot.get_pixel(x,y).to_rgba32()]=true
			check(colors.size()>10,"Player component failed to render: "+stage)
			check(shot.save_png(args[3].path_join("player-"+stage+".png"))==OK,"Cannot save player component capture")
	var previous:=geometry.visible
	var unrelated: RefCounted=started()
	check(not geometry.apply_effect(unrelated,camera.transform,PackedByteArray([255,255,255,255]),Vector4.ONE,1) and geometry.visible==previous,"Renderer accepted an unrelated destruction owner")
	canvas.free()

static func analytic_xyz(a: Vector3) -> Basis:
	return Basis(Vector3(cos(a.y)*cos(a.z),cos(a.x)*sin(a.z)+sin(a.x)*sin(a.y)*cos(a.z),sin(a.x)*sin(a.z)-cos(a.x)*sin(a.y)*cos(a.z)),Vector3(-cos(a.y)*sin(a.z),cos(a.x)*cos(a.z)-sin(a.x)*sin(a.y)*sin(a.z),sin(a.x)*cos(a.z)+cos(a.x)*sin(a.y)*sin(a.z)),Vector3(sin(a.y),-sin(a.x)*cos(a.y),cos(a.x)*cos(a.y)))

func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",checks,": ",message)

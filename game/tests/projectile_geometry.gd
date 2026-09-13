extends SceneTree
const Capture=preload("res://tests/fixtures/model_capture.gd")
const Frame=preload("res://src/simulation/opening_world_frame.gd")
const Timeline=preload("res://src/simulation/opening_detail_timeline.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Deaths=preload("res://src/content/npc_destruction_resources.gd")
const Definitions=preload("res://src/content/projectile_visual_definitions.gd")
const State=preload("res://src/simulation/projectile_visual_state.gd")
const Geometry=preload("res://src/presentation/projectile_geometry.gd")
const Pose=preload("res://src/presentation/projectile_pose.gd")
const Playback=preload("res://src/simulation/model_playback.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
var failures:=0

func _initialize() -> void:call_deferred("run")
func run() -> void:
	check_playback();check_poses()
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):await verify_profile(args[i],args[i+1],args[i+2])
	print("Projectile geometry checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify_profile(content: String, pack: String, textures: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new();var visuals:=Visuals.new()
	if not library.open(content) or not library.select_language("gb") or not bindings.open(pack,library.manifest) or not catalogues.open(library) or not visuals.open(textures,library.manifest):check(false,library.error+bindings.error+catalogues.error+visuals.error);return
	var bodies:=Bodies.new();var effects:=Effects.new();var deaths:=Deaths.new();var scenery:=Scenery.new();var owner:=Frame.new();var timeline:=Timeline.new()
	var counts:=[];counts.resize(23);counts.fill(1)
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings) or not deaths.configure(library,bindings):check(false,bodies.error+effects.error+deaths.error);return
	if not scenery.configure(bindings,catalogues,1789100000,true,bodies,effects) or not scenery.complete_world_initialization(bindings,catalogues):check(false,scenery.error);return
	if not owner.configure(bindings,catalogues,scenery,0.5,deaths) or not timeline.configure(bindings,catalogues,library,counts,1.0,0.5):check(false,owner.error+timeline.error);return
	if not owner.configure_player_flight(bindings,catalogues,library,scenery,1.0):check(false,owner.error);return
	var before:=owner.snapshot()
	if bindings.opening_staging.get("projectile_visuals",{}).is_empty():
		check(not owner.configure_projectile_visuals(bindings,library) and owner.snapshot()==before,"Legacy content fabricated projectile models")
		return
	if not owner.configure_projectile_visuals(bindings,library):check(false,owner.error);return
	check(not owner.configure_projectile_visuals(bindings,library),"Projectile clocks can be reset after attachment")
	var rules: Dictionary=bindings.opening_staging.projectile_visuals
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	check(Definitions.validate(rules,header.source_executable_bytes,header.architecture,bindings.opening_staging).is_empty(),"Valid visual declaration rejected")
	for key in rules.provenance:
		var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.opening_staging).is_empty(),"Disconnected projectile span accepted: "+key)
	var invalid:=rules.duplicate(true);invalid.model_ids[0]=14600
	check(not Definitions.parameters(invalid),"Impact model accepted as travelling projectile")
	var animation: RefCounted=owner.projectile_visual_owner()
	var initial: Dictionary=animation.snapshot()
	for delta in [-1,151,0.5,NAN,true]:
		check(not animation.advance(delta) and animation.snapshot()==initial,"Invalid animation time changed the owner")
	check(initial.models.size()==5,"Opening lost a weapon animation owner")
	for i in initial.models.size():
		check(initial.models[i].time_ms==33 and initial.models[i].start_ms==33 and initial.models[i].end_ms==(200 if i<2 else 700),"Imported model animation range changed")
	var geometry:=Geometry.new();root.add_child(geometry)
	if not geometry.build(animation,library,visuals,bindings):check(false,geometry.error);geometry.free();return
	var empty:=geometry.prepare_world(animation,owner.snapshot(),Transform3D.IDENTITY)
	check(not empty.is_empty(),geometry.error)
	if empty.is_empty():geometry.free();return
	geometry.commit_world(empty)
	for gun in geometry.guns:
		for slot in gun.slots:check(not slot.visible,"Empty weapon slots became visible")
	check_render_transaction(geometry,owner)
	await capture_models(geometry,owner,library.manifest.profile.edition)
	var state:={"world_frame":owner,"timeline":timeline,"scenery":scenery}
	var released:=false
	for tick in 1000:
		var old: Dictionary=state.world_frame.snapshot()
		var result: Dictionary=state.world_frame.evaluate(state.timeline,state.scenery,100,true,1.0,Vector2.ZERO,true)
		check(not result.is_empty(),state.world_frame.error)
		if result.is_empty():break
		var frame: Dictionary=result.world_frame.snapshot()
		check(frame.projectile_visuals.elapsed_ms==frame.elapsed_ms,"Projectile animation left its world clock")
		for i in 5:
			var previous: Dictionary=old.projectile_visuals.models[i]
			var expected: int=int(previous.time_ms)+100
			if expected>previous.end_ms:expected=int(previous.start_ms)+expected%int(previous.end_ms)
			check(frame.projectile_visuals.models[i].time_ms==expected,"New shots restarted shared animation or empty weapons stopped it")
		var prepared:=geometry.prepare_world(result.world_frame.projectile_visual_owner(),frame,result.timeline.snapshot().camera.view.get("pose",Transform3D.IDENTITY))
		check(not prepared.is_empty(),geometry.error)
		if not prepared.is_empty():geometry.commit_world(prepared)
		state=result
		if result.timeline.snapshot().camera.shot.phase==4:
			released=true
			for i in 2:check(frame.primaries.guns[i].projectiles.slots.any(func(slot):return slot!=null),"Release did not fire player primaries")
			break
	check(released,"Projectile checks did not reach cinematic release")
	var saved:=snapshot(state)
	check(state.world_frame.evaluate(state.timeline,state.scenery,100,"invalid",1.0,Vector2.ZERO,true).is_empty(),"Late radio failure accepted")
	check(snapshot(state)==saved,"Failed world frame committed projectile time or slots")
	var changed: RefCounted=state.world_frame.fork_for_frame();check(changed.projectile_visual_owner().advance(1),changed.projectile_visual_owner().error)
	check(changed.evaluate(state.timeline,state.scenery,0,true).is_empty(),"Detached projectile clock was accepted")
	var zero: Dictionary=state.world_frame.evaluate(state.timeline,state.scenery,0,true)
	check(not zero.is_empty() and zero.world_frame.snapshot().projectile_visuals==state.world_frame.snapshot().projectile_visuals,"Zero-time frame changed model playback")
	geometry.clear();check(geometry.get_child_count()==0 and geometry.guns.is_empty(),"Geometry clear retained projectiles");geometry.free()
	print(library.manifest.profile.edition,": five weapon clocks, source model mappings, transactional geometry and live release verified")

func check_render_transaction(geometry: Node3D, owner: RefCounted) -> void:
	var clock: RefCounted=owner.projectile_visual_owner().fork_for_frame();check(clock.advance(100),clock.error)
	var fixture: Dictionary=owner.snapshot();fixture.elapsed_ms=100;fixture.projectile_visuals=clock.snapshot()
	var weapons:=State.weapons(fixture)
	weapons[0].projectiles.slots[0]=shot(Vector3(-80,0,0),Vector3.RIGHT,2000)
	weapons[2].projectiles.slots[0]=shot(Vector3(80,0,0),Vector3.FORWARD,2000)
	var prepared: Dictionary=geometry.prepare_world(clock,fixture,Transform3D.IDENTITY,PackedByteArray([255,255,255,255]),Vector4.ONE,0.8)
	check(not prepared.is_empty(),geometry.error)
	if prepared.is_empty():return
	geometry.commit_world(prepared)
	check(geometry.guns[0].slots[0].visible and geometry.guns[2].slots[0].visible,"Travelling player or NPC model remained hidden")
	for gun_index in [0,2]:
		var model: Node3D=geometry.guns[gun_index].slots[0]
		for i in model.materials.size():
			check(model.materials[i].get_shader_parameter("diffuse_texture")!=null,"Cull variant lost its source texture")
			check(model.materials[i].shader==(geometry._reflected_additive if model.instances[i].transform.basis.determinant()<0 else geometry.Additive),"Surface culling did not counter Godot's mirror adjustment")
			check(model.materials[i].get_shader_parameter("darken_value")==prepared.darken,"Cull variant lost its edition-specific darkening")
	var poses:=rendered(geometry)
	var samplers:=[]
	for sampler in geometry._samplers:samplers.append(sampler.snapshot())
	weapons[4].projectiles.slots[0]=shot(Vector3.ZERO,Vector3(NAN,0,1),2000)
	check(geometry.prepare_world(clock,fixture,Transform3D.IDENTITY).is_empty(),"Invalid final weapon slot accepted")
	check(rendered(geometry)==poses,"Failed group changed preceding projectile meshes")
	for i in samplers.size():check(geometry._samplers[i].snapshot()==samplers[i],"Failed group advanced a sampler")
	fixture=owner.snapshot()
	check(geometry.prepare_world(clock,fixture,Transform3D.IDENTITY).is_empty(),"Stale world accepted a newer projectile clock")

func capture_models(geometry: Node3D, owner: RefCounted, edition: String) -> void:
	if DisplayServer.get_name()=="headless":return
	var output:=OS.get_environment("GOF2_CAPTURE_DIR")
	if output.is_empty():return
	var clock: RefCounted=owner.projectile_visual_owner().fork_for_frame();check(clock.advance(100),clock.error)
	for weapon_index in [0,2]:
		var fixture: Dictionary=owner.snapshot();fixture.elapsed_ms=100;fixture.projectile_visuals=clock.snapshot()
		var weapons:=State.weapons(fixture)
		weapons[weapon_index].projectiles.slots[0]=shot(Vector3.ZERO,Vector3.RIGHT if weapon_index==0 else Vector3.FORWARD,2000)
		var prepared: Dictionary=geometry.prepare_world(clock,fixture,Transform3D.IDENTITY)
		check(not prepared.is_empty(),geometry.error)
		if prepared.is_empty():continue
		geometry.commit_world(prepared)
		var model: Node3D=geometry.guns[weapon_index].slots[0]
		var name:="projectile-%s-%s.png"%[edition,"player" if weapon_index==0 else "npc"]
		var result:=await Capture.capture(self,model,output.path_join(name))
		check(result.get("saved",false) and result.get("lit_pixels",0)>40,"Source model did not render independently: "+name+" "+str(result))
		print(name,": ",result)

func check_playback() -> void:
	var models:=[{"start_ms":33,"end_ms":200,"time_ms":33,"playing":true}]
	Playback.advance(models,167,true);check(models[0].time_ms==200 and models[0].playing,"Loop skipped its exact final key")
	Playback.advance(models,0,true);check(models[0].time_ms==200,"Zero time wrapped a final key")
	Playback.advance(models,1,true);check(models[0].time_ms==34 and models[0].playing,"Loop used duration instead of absolute end modulo")
	Playback.advance(models,367,true);check(models[0].time_ms==34,"Loop mishandled a multiple-end overshoot")
	Playback.advance(models,167);check(models[0].time_ms==200 and not models[0].playing,"Existing one-shot playback regressed")

func check_poses() -> void:
	var rules:=Definitions.VALUES
	check(not Pose.sample(null,0,Transform3D.IDENTITY,false,rules).visible,"Empty projectile rendered")
	check(not Pose.sample(shot(Vector3(50000,10,10),Vector3.RIGHT,2000),0,Transform3D.IDENTITY,false,rules).visible,"Hidden-position sentinel rendered")
	var moving:=Pose.sample(shot(Vector3(1,2,3),Vector3.RIGHT,2000),0,Transform3D.IDENTITY,false,rules)
	check(moving.pose==Transform3D(Basis(Vector3.FORWARD,Vector3.UP,Vector3.RIGHT),Vector3(1,2,3)),"Flight-oriented root changed")
	var camera:=Transform3D(Basis.from_euler(Vector3(0.2,0.5,-0.4)),Vector3(10,20,30))
	var facing:=Pose.sample(shot(Vector3.ZERO,Vector3.RIGHT,2000),1,camera,false,rules)
	check(facing.pose.basis==Basis(camera.basis.x,camera.basis.y,-camera.basis.z),"Billboard lost the source reflected camera basis")
	for remaining in [1000,999,500,0,-1,-100]:
		var result:=Pose.sample(shot(Vector3.ZERO,Vector3.BACK,remaining),0,Transform3D.IDENTITY,false,rules)
		var expected:=1.0 if remaining>=1000 else Vitals.single(float(remaining)/1000.0)
		check(result.visible and result.scale==expected and result.pose.basis.z.z==expected,"Final-second or signed-overshoot scale changed")
	var reduced:=Pose.sample(shot(Vector3.ZERO,Vector3.BACK,500),1,Transform3D.IDENTITY,true,rules)
	check(reduced.scale==Vitals.single(0.5*rules.reduced_billboard_scale),"Explicit reduced billboard scale changed")
	check(Pose.sample(shot(Vector3.ZERO,Vector3(INF,0,1),1000),0,Transform3D.IDENTITY,false,rules).has("error"),"Nonfinite projectile accepted")

func shot(position: Vector3, velocity: Vector3, remaining: int) -> Dictionary:return {"position":position,"velocity":velocity,"remaining_ms":remaining}
func snapshot(state: Dictionary) -> Dictionary:return {"world":state.world_frame.snapshot(),"timeline":state.timeline.snapshot(),"scenery":state.scenery.snapshot()}
func rendered(geometry: Node3D) -> Array:
	var result:=[]
	for gun in geometry.guns:
		for slot in gun.slots:
			var row:={"visible":slot.visible,"poses":[]}
			for mesh in slot.instances:row.poses.append(mesh.transform)
			result.append(row)
	return result
func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)

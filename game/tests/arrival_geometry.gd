extends SceneTree
## Rendering integration with explicit motion decisions. This does not claim a
## live rescue world, automatic Opening handoff or following station support.
const Geometry=preload("res://src/presentation/opening_geometry.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const SceneryGeometry=preload("res://src/presentation/scenery_geometry.gd")
const Motion=preload("res://src/simulation/arrival_actor_motion.gd")
const Staging=preload("res://src/simulation/arrival_choreography.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const SkyGeometry=preload("res://src/presentation/opening_sky.gd")
const Planets=preload("res://src/presentation/opening_planet_geometry.gd")
const Lighting=preload("res://src/presentation/opening_lighting.gd")
const Sun=preload("res://src/presentation/opening_sun_geometry.gd")
const SunFrame=preload("res://src/presentation/opening_sun_frame.gd")
const View=preload("res://src/simulation/camera_view.gd")
const CameraProjection=preload("res://src/presentation/flight_camera.gd")
var checks:=0
var failures:=0
var captures:=""

func _initialize():call_deferred("run")

func run():
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].begins_with("--captures="):captures=args[0].trim_prefix("--captures=");args.remove_at(0)
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visual triples")
	for i in range(0,args.size()-2,3):await verify_profile(args[i],args[i+1],args[i+2])
	print("Arrival geometry: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_profile(content: String, pack: String, texture_pack: String):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib) or not visuals.open(texture_pack,lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	var fresh:=Player.new();var player:=Player.new()
	check(fresh.configure(bindings,cat) and player.configure_arrival(bindings,cat,fresh.cache_snapshot()),fresh.error+player.error)
	var cache:=player.cache_snapshot();var construction:=Construction.new();var motion:=Motion.new();var staging:=Staging.new()
	var field_owner: RefCounted
	var poses:={}
	if not bindings.arrival_world_initialization.is_empty():
		field_owner=Scenery.new()
		var conditions:={"companions_empty":true,"location_match":false}
		check(field_owner.configure_arrival(bindings,cat,cache,conditions,1789100000),field_owner.error)
		check(field_owner.complete_world_initialization(bindings,cat),field_owner.error)
		poses=field_owner.arrival_motion_construction()
	else:
		check(construction.configure_arrival(bindings,cat,cache),construction.error)
		check(not construction.generate({"state":25214903917}).is_empty(),construction.error)
		poses=construction.arrival_motion_construction()
	check(motion.configure(bindings,cat,cache,poses),motion.error)
	check(staging.configure(bindings,lib),staging.error)
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,640);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var geometry:=Geometry.new();var sky:=SkyGeometry.new();var planets:=Planets.new();var lights:=Lighting.new();var sun:=Sun.new();var camera:=Camera3D.new();camera.current=true
	for node in [geometry,sky,planets,lights,sun,camera]:viewport.add_child(node)
	var scenery: Node3D
	if field_owner!=null:
		scenery=SceneryGeometry.new();viewport.add_child(scenery)
		check(scenery.build(field_owner.snapshot(),lib,visuals,bindings),scenery.error)
		check(scenery.objects.size()==field_owner.snapshot().objects.size(),"Rescue field lost source scenery geometry")
		check(scenery.apply_state(field_owner.snapshot()),scenery.error)
	check(geometry.build_arrival(lib,visuals,bindings,cat,cache),geometry.error)
	check(sky.build_arrival(lib,visuals,bindings,cat,cache),sky.error)
	check(planets.build_arrival(lib,visuals,bindings,cat,cache),planets.error)
	check(lights.build_arrival(bindings,cat,cache),lights.error)
	check(sun.build_arrival(lib,visuals,bindings,cat,cache),sun.error)
	if geometry.player==null or sun.selection.is_empty():viewport.free();return
	check(geometry.actors.size()==1 and geometry.actors[0].get_meta("source_ship_id")==30 and geometry.player.get_meta("source_ship_id")==10,"Rescue rendered the wrong hull set")
	check(geometry.actors[0].visible and geometry.actors[0].transform==poses.body_pose,"Disabled engine hid or displaced the rescue hull")
	for body in [geometry.player,geometry.actors[0]]:
		var selected:=bindings.resolve_ship_layers(body.get_meta("source_ship_id"));var count:=0
		for node in body.get_children():
			if node.has_meta("source_light_slot"):count+=1;check(node.transform==Transform3D.IDENTITY,"Rescue light layer gained an offset")
		check(count==selected.lights.size(),"Rescue lost original light layers")
	check(geometry.apply_arrival(staging.snapshot(),motion.snapshot()),geometry.error)
	var original_lights:=Lighting.new();check(original_lights.build(bindings,cat,bindings.base_content_id,0,3,false),original_lights.error)
	check(lights.state==original_lights.state and lights.lights.size()==2,"Retained rescue location changed ordinary lighting");original_lights.free()
	var original_sun:=SunFrame.new();check(original_sun.configure(bindings,cat,bindings.base_content_id),original_sun.error)
	check(original_sun.selection==sun.selection,"Rescue changed the sun's station resources")
	var projection:=CameraProjection.new();check(projection.configure(bindings.flight_projection,1,false).is_empty(),"Rescue projection unavailable")
	var view:=View.fixed_eye(staging.snapshot().eye,Transform3D.IDENTITY,false)
	apply_view(projection,camera,sky,planets,sun,view,viewport.size)
	if DisplayServer.get_name()!="headless":save(await capture(viewport),lib.manifest.profile.edition+"-rescue-initial")
	var radio:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":1,"started":[false,false,false],"finished":[false,false,false]}
	for i in 200:
		var previous:=motion.snapshot()
		check(staging.advance(100,radio,previous.statistics_pose.origin,previous.body_pose,true),staging.error)
		var cues:=staging.snapshot()
		var dispatch:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":1,"generation":cues.generation,
			"mode_at_dispatch":5,"actor_hostile":false,"route_has_targets":true,"target_present":true,"target_excluded":false,
			"target_relative_position":-cues.frame.actor_pose_override.origin,"model_local_pose":previous.model_local_pose}
		check(motion.advance(cues,dispatch) and geometry.apply_arrival(cues,motion.snapshot()),motion.error+geometry.error)
		if field_owner!=null:check(field_owner.update(100,Vector3.ZERO) and scenery.apply_state(field_owner.snapshot()),field_owner.error+scenery.error)
	check(geometry.actors[0].visible and not motion.snapshot().engine_draw_enabled,"Approach enabled the stopped engine or hid the hull")
	var cues:=staging.snapshot();var actor:=motion.snapshot();var saved_player:=geometry.player.transform;var saved_actor: Transform3D=geometry.actors[0].transform
	for field in ["base_content_id","generation","engine_draw_enabled","model_draw_enabled","statistics_pose"]:
		var bad:=actor.duplicate(true)
		match field:
			"base_content_id":bad[field]="foreign"
			"generation":bad[field]-=1
			"engine_draw_enabled":bad[field]=true
			"model_draw_enabled":bad.erase(field)
			"statistics_pose":bad[field]=Transform3D.IDENTITY
		check(not geometry.apply_arrival(cues,bad) and geometry.player.transform==saved_player and geometry.actors[0].transform==saved_actor and geometry.actors[0].visible,"Rejected rescue presentation partly changed nodes")
	view=View.fixed_eye(cues.eye,Transform3D.IDENTITY,false);apply_view(projection,camera,sky,planets,sun,view,viewport.size)
	if DisplayServer.get_name()!="headless":
		save(await capture(viewport),lib.manifest.profile.edition+"-rescue-approach")
		# A separate close view makes hull/light visibility observable regardless
		# of where the scripted camera currently places the incoming actor.
		view=View.fixed_eye(saved_actor.origin+Vector3(600,300,-1000),saved_actor,false)
		apply_view(projection,camera,sky,planets,sun,view,viewport.size)
		var visible:=await capture(viewport);save(visible,lib.manifest.profile.edition+"-rescue-hull-inspection")
		var hidden:=actor.duplicate(true);hidden.model_draw_enabled=false
		check(geometry.apply_arrival(cues,hidden),geometry.error)
		check((await capture(viewport)).get_data()!=visible.get_data(),"Enabled hull contributed no rendered pixels")
		check(geometry.apply_arrival(cues,actor),geometry.error)
		check((await capture(viewport)).get_data()==visible.get_data(),"Replaying the model state changed the image")
	check(geometry.build_arrival(lib,visuals,bindings,cat,cache,"high",true),geometry.error)
	check(geometry.player.apply_detail(0,2) and geometry.actors[0].apply_detail(0,2),"Rescue LOD selection failed")
	var detail:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"selections":{"player":geometry.player.selection,0:geometry.actors[0].selection}}
	check(geometry.apply_arrival(cues,actor,detail),geometry.error)
	check(geometry.actors[0].visible and not geometry.actors[0].selection.is_empty(),"Rescue detail selection hid its model")
	var foreign:=cache.duplicate(true);foreign.binding_id="foreign"
	check(not geometry.build_arrival(lib,visuals,bindings,cat,foreign) and geometry.player==null and geometry.actors.is_empty(),"Invalid cache retained prior rescue ships")
	check(not lights.build_arrival(bindings,cat,foreign) and lights.state.is_empty() and lights.lights.is_empty(),"Invalid cache retained rescue lighting")
	check(not sun.build_arrival(lib,visuals,bindings,cat,foreign) and sun.selection.is_empty() and sun.primary==null,"Invalid cache retained rescue sun")
	check(geometry.build(lib,visuals,bindings,cat) and geometry.actors.size()==3,geometry.error)
	check(not geometry.apply_arrival(cues,actor),"Rescue state entered rebuilt Opening geometry")
	viewport.free()

func apply_view(projection: RefCounted,camera: Camera3D,sky: Node3D,planets: Node3D,sun: Node3D,view: Dictionary,size_value: Vector2i):
	check(projection.apply(camera,view).is_empty() and sky.apply_view(view) and planets.apply_view(view),"Rescue camera rejected")
	var frame: Dictionary=sun.prepare_frame(view,size_value,0)
	check(not frame.has("error"),sun.error)
	if not frame.has("error"):sun.commit_frame(frame)

func capture(viewport: SubViewport) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func save(image: Image,name_value: String):
	if captures.is_empty():return
	DirAccess.make_dir_recursive_absolute(captures)
	check(image.save_png(captures.path_join(name_value+".png"))==OK,"Could not save rescue capture")

func check(condition: bool,message: String):
	checks+=1
	if not condition:failures+=1;push_error(message)

extends SceneTree
const Definitions=preload("res://src/content/arrival_environment_definitions.gd")
const Location=preload("res://src/simulation/arrival_location.gd")
const Layout=preload("res://src/simulation/opening_planet_layout.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const SkyGeometry=preload("res://src/presentation/opening_sky.gd")
const Planets=preload("res://src/presentation/opening_planet_geometry.gd")
const CameraView=preload("res://src/simulation/camera_view.gd")
const CameraProjection=preload("res://src/presentation/flight_camera.gd")
var checks:=0
var failures:=0
var captures:=""

func _initialize():call_deferred("run")

func run():
	verify_rounding()
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].begins_with("--captures="):captures=args[0].trim_prefix("--captures=");args.remove_at(0)
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visual triples")
	for i in range(0,args.size()-2,3):await verify_profile(args[i],args[i+1],args[i+2])
	print("Arrival environment: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_rounding():
	# Independent integer-size vectors include odd values where doubling the
	# already-truncated opening scale would lose one fixed-point unit.
	for row in [[1,[-1,0,1,2,3],36185],[2,[0,1,2,3,4],28204],[7,[5,6,7,8,9],23495]]:
		var owner:=Layout.new();var opening:=owner.arrange(row[0],0,row[1]);var rescue:=owner.arrange(row[0],0,row[1],false)
		check(rescue.entries[rescue.selected_index].scale==float(row[2])/65536.0,"Rescue size lost the constructor integer")
		check(opening.random_state==rescue.random_state,"Changing size consumed another random draw")
		for index in rescue.entries.size():
			var a: Dictionary=opening.entries[index].duplicate(true);var b: Dictionary=rescue.entries[index].duplicate(true)
			if index==rescue.selected_index:a.erase("scale");b.erase("scale")
			check(a==b,"Rescue size changed another planet, position or random continuation")

func verify_profile(content: String, pack: String, texture_pack: String):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib) or not visuals.open(texture_pack,lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	var fresh:=Player.new();var player:=Player.new();var location:=Location.new();var layout:=Layout.new()
	check(fresh.configure(bindings,cat),fresh.error)
	if bindings.arrival_environment.is_empty():
		check(location.resolve(bindings,cat,{}).is_empty() and layout.for_arrival(bindings,cat,{}).is_empty(),"Legacy profile supplied unsupported rescue scenery")
		return
	check(player.configure_arrival(bindings,cat,fresh.cache_snapshot()),player.error)
	var cache:=player.cache_snapshot();var context:=location.resolve(bindings,cat,cache)
	check(not context.is_empty(),location.error)
	if context.is_empty():return
	check(context.station_id==78 and context.system_id==15 and context.campaign_cursor==1 and context.sky_index==9,"Wrong retained rescue location")
	check(context.sky_parameters.sky_mesh_id==17809 and context.sky_parameters.sky_texture_id==10074 and context.current_planet_texture_id==10042,"Rescue retained an opening texture override")
	check(location.resolve(bindings,cat,fresh.cache_snapshot()).is_empty(),"Opening cache entered rescue scenery")
	for key in ["base_content_id","binding_id","station_id","system_id","ship_id","equipment_ids","campaign_cursor"]:
		var bad:=cache.duplicate(true)
		if key in ["base_content_id","binding_id"]:bad[key]="foreign"
		elif key=="equipment_ids":bad.equipment_ids.reverse()
		else:bad[key]+=1
		check(location.resolve(bindings,cat,bad).is_empty(),"Foreign rescue cache selected scenery: "+key)
	var resolved:=layout.for_arrival(bindings,cat,cache);check(not resolved.is_empty(),layout.error)
	if resolved.is_empty():return
	var opening:=layout.for_opening(bindings,cat,bindings.base_content_id)
	var current: int=resolved.selected_index
	check(resolved.entries[current].scale==0.5568695068359375 and opening.entries[current].scale==0.2784271240234375,"Retained opening scale replaced fresh rescue construction")
	check(resolved.entries[current].texture_id==10042 and resolved.random_state.state==73874710156757,"Rescue planet texture or random sequence differs")
	for index in resolved.entries.size():
		var a: Dictionary=opening.entries[index].duplicate(true);var b: Dictionary=resolved.entries[index].duplicate(true)
		if index==current:
			for key in ["texture_id","texture_path","scale"]:a.erase(key);b.erase(key)
		check(a==b,"Rescue changed noncurrent planet placement or resources")
	var low:=layout.for_arrival(bindings,cat,cache,"low")
	for index in resolved.entries.size():
		var a: Dictionary=resolved.entries[index].duplicate(true);var b: Dictionary=low.entries[index].duplicate(true)
		a.erase("texture_path");b.erase("texture_path");check(a==b,"Quality selection changed rescue content")
	var saved_sky: int=cat.tables.systems[15].sky_index
	for sky in [-1,15,17]:
		cat.tables.systems[15].sky_index=sky;check(location.resolve(bindings,cat,cache).is_empty(),"Unsupported background selected")
	cat.tables.systems[15].sky_index=saved_sky
	cat.tables.stations[78].planet_type=18;check(location.resolve(bindings,cat,cache).is_empty(),"Unsupported special planet selected")
	cat.tables.stations[78].planet_type=0
	check(location.resolve(bindings,cat,cache)==context and player.cache_snapshot()==cache,"Failed selection changed retained state")
	await verify_geometry(lib,bindings,cat,visuals,cache)
	verify_definitions(pack,lib,bindings)
	print(lib.manifest.profile.edition+": ordinary rescue sky, full constructor planet size and retained location verified")

func verify_geometry(lib: RefCounted, bindings: RefCounted, cat: RefCounted, visuals: RefCounted, cache: Dictionary):
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,640);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();camera.current=true;viewport.add_child(camera)
	var sky:=SkyGeometry.new();var planets:=Planets.new();viewport.add_child(sky);viewport.add_child(planets)
	check(sky.build_arrival(lib,visuals,bindings,cat,cache),sky.error)
	check(planets.build_arrival(lib,visuals,bindings,cat,cache),planets.error)
	if sky.selection.is_empty() or planets.selection.is_empty():viewport.free();return
	check(sky.selection.campaign_cursor==1 and sky.layers.size()==2 and sky.selection.star_variant==0,"Rescue sky retained escape layers")
	check(sky.layers[0].get_meta("source_resource_id")==17850 and sky.layers[0].get_meta("source_texture_id")==10086,"Wrong rescue star variant")
	check(sky.layers[1].get_meta("source_resource_id")==17809 and sky.layers[1].get_meta("source_texture_id")==10074,"Wrong rescue nebula")
	check(planets.models.size()==5 and planets.selection.campaign_cursor==1,"Wrong rescue planet membership")
	var projection:=CameraProjection.new();check(projection.configure(bindings.flight_projection,1,false).is_empty(),"Rescue camera projection unavailable")
	var eye: Array=bindings.arrival_staging.camera_position
	var view:=CameraView.fixed_eye(Vector3(eye[0],eye[1],eye[2]),Transform3D.IDENTITY,false)
	check(projection.apply(camera,view).is_empty(),"Source rescue view rejected")
	check(sky.apply_view(view) and planets.apply_view(view),sky.error+planets.error)
	var current: int=planets.selection.selected_index-1
	check(planets.selection.planets[current].scale==PackedFloat32Array([0.5568695068359375+PackedFloat32Array([0.00375])[0]])[0],"Rescue drawing lost its full-size constructor baseline")
	if DisplayServer.get_name()!="headless":
		var image:=await capture(viewport);check(variation(image)>100,"Source rescue camera rendered a flat environment");save(image,lib.manifest.profile.edition+"-rescue-camera")
		view={"pose":Transform3D.IDENTITY};check(projection.apply(camera,view).is_empty() and sky.apply_view(view) and planets.apply_view(view),"Planet inspection view rejected")
		var full:=await capture(viewport);check(variation(full)>100,"Rescue environment did not render");save(full,lib.manifest.profile.edition+"-current-planet")
		planets.hide();var background:=await capture(viewport);check(background.get_data()!=full.get_data(),"Rescue planet did not contribute to the image");planets.show()
		camera.position=Vector3(5000,6000,0);view={"pose":camera.transform};check(sky.apply_view(view) and planets.apply_view(view),"Translated rescue view rejected")
		check((await capture(viewport)).get_data()==full.get_data(),"Horizontal camera translation changed infinite rescue background")
		check(planets.build(lib,visuals,bindings,cat,"high",true),planets.error)
		var escape:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"phase":10}
		check(planets.apply_view(view,escape),planets.error)
		check((await capture(viewport)).get_data()!=full.get_data(),"Fresh rescue planet retained the smaller outgoing scale")
		check(planets.build_arrival(lib,visuals,bindings,cat,cache) and planets.apply_view(view),planets.error)
		check((await capture(viewport)).get_data()==full.get_data(),"Rebuilding rescue changed the image")
	var prior:=planets.selection.duplicate(true);var sky_pose:=sky.transform
	var bad_view:={"pose":Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))}
	check(not planets.apply_view(bad_view) and planets.selection==prior and not sky.apply_view(bad_view) and sky.transform==sky_pose,"Invalid view changed rescue geometry")
	var bad:=cache.duplicate(true);bad.binding_id="foreign"
	check(not planets.build_arrival(lib,visuals,bindings,cat,bad) and planets.models.is_empty() and planets.selection.is_empty(),"Failed planet replacement retained a scene")
	check(not sky.build_arrival(lib,visuals,bindings,cat,bad) and sky.layers.is_empty() and sky.selection.is_empty(),"Failed sky replacement retained a scene")
	var identity: String=visuals.base_content_id;visuals.base_content_id="foreign"
	check(not planets.build_arrival(lib,visuals,bindings,cat,cache) and not sky.build_arrival(lib,visuals,bindings,cat,cache),"Foreign texture pack accepted")
	visuals.base_content_id=identity
	viewport.free()

func verify_definitions(pack: String, lib: RefCounted, bindings: RefCounted):
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var data: Dictionary=bindings.arrival_environment
	check(Definitions.validate(data,header.source_executable_bytes,header.architecture,bindings.opening_sky,bindings.opening_actors,bindings.arrival_staging).is_empty(),"Valid environment declarations rejected")
	for key in data.provenance:
		var bad:=data.duplicate(true);bad.provenance[key].offset+=2
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.opening_sky,bindings.opening_actors,bindings.arrival_staging).is_empty(),"Detached environment provenance accepted")
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-arrival-environment-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var scenarios:=["missing","wrong_type","changed","no_cache","empty"]
	if not bindings.first_flight.is_empty():scenarios.append("empty_with_first_flight")
	if not bindings.mining_briefing.is_empty():scenarios.append("empty_with_mining_briefing")
	if not bindings.mining_drill.is_empty():scenarios.append("empty_with_mining_drill")
	if not bindings.mining_targeting.is_empty():scenarios.append("empty_with_mining_targeting")
	if not bindings.mining_approach.is_empty():scenarios.append("empty_with_mining_approach")
	if not bindings.mining_session.is_empty():scenarios.append("empty_with_mining_session")
	if not bindings.flight_notices.is_empty():scenarios.append("empty_with_flight_notices")
	if not bindings.mining_objective.is_empty():scenarios.append("empty_with_mining_objective")
	if not bindings.station_exterior.is_empty():scenarios.append("empty_with_station_exterior")
	if not bindings.station_autopilot.is_empty():scenarios.append("empty_with_station_autopilot")
	if not bindings.station_flight.is_empty():scenarios.append("empty_with_station_flight")
	if not bindings.station_return.is_empty():scenarios.append("empty_with_station_return")
	if not bindings.full_hold_departure.is_empty():scenarios.append("empty_with_full_hold_departure")
	if not bindings.full_hold_flight.is_empty():scenarios.append("empty_with_full_hold_flight")
	for scenario in scenarios:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("arrival_environment")
			"wrong_type":changed.arrival_environment=false
			"changed":changed.arrival_environment.sky_texture_base+=1
			"no_cache":changed.opening_actors.player_initialization.flight_cache={}
			"empty", "empty_with_first_flight", "empty_with_mining_briefing", "empty_with_mining_drill", "empty_with_mining_targeting", "empty_with_mining_approach", "empty_with_mining_session", "empty_with_flight_notices", "empty_with_mining_objective", "empty_with_station_exterior", "empty_with_station_autopilot", "empty_with_station_flight", "empty_with_station_return", "empty_with_full_hold_departure", "empty_with_full_hold_flight":
				changed.arrival_environment={}
				# An explicitly unsupported environment also removes capabilities
				# that require it. Keep one dependent declaration for the refusal case.
				for key in ["arrival_actor_motion","arrival_actor_construction","arrival_world_initialization","opening_handoff","arrival_session","station_entry","station_presentation","station_departure"]:
					if changed.has(key):changed[key]={}
				if scenario in ["empty_with_mining_briefing","empty_with_mining_drill"]:changed.first_flight={}
				if scenario=="empty_with_mining_drill":changed.mining_briefing={}
				if scenario=="empty_with_mining_targeting":
					for key in ["first_flight","mining_briefing","mining_drill"]:changed[key]={}
				if scenario=="empty_with_mining_approach":
					for key in ["first_flight","mining_briefing","mining_drill","mining_targeting"]:changed[key]={}
				if scenario=="empty_with_mining_session":
					for key in ["first_flight","mining_briefing","mining_drill","mining_targeting","mining_approach"]:changed[key]={}
				if scenario=="empty_with_flight_notices":
					for key in ["first_flight","mining_briefing","mining_drill","mining_targeting","mining_approach","mining_session"]:changed[key]={}
				if scenario=="empty_with_mining_objective":
					for key in ["first_flight","mining_briefing","mining_drill","mining_targeting","mining_approach","mining_session","flight_notices"]:changed[key]={}
				if scenario=="empty_with_full_hold_flight":
					for key in ["first_flight","mining_briefing","mining_drill","mining_targeting","mining_approach","mining_session","flight_notices","mining_objective","station_exterior","station_autopilot","station_flight","station_return","full_hold_departure"]:changed[key]={}
				if scenario=="empty_with_full_hold_departure":
					for key in ["first_flight","mining_briefing","mining_drill","mining_targeting","mining_approach","mining_session","flight_notices","mining_objective","station_exterior","station_autopilot","station_flight","station_return"]:changed[key]={}
				if scenario=="empty_with_station_return":
					for key in ["first_flight","mining_briefing","mining_drill","mining_targeting","mining_approach","mining_session","flight_notices","mining_objective","station_exterior","station_autopilot","station_flight"]:changed[key]={}
				if scenario=="empty_with_station_flight":
					for key in ["first_flight","mining_briefing","mining_drill","mining_targeting","mining_approach","mining_session","flight_notices","mining_objective","station_exterior","station_autopilot"]:changed[key]={}
				if scenario=="empty_with_station_autopilot":
					for key in ["first_flight","mining_briefing","mining_drill","mining_targeting","mining_approach","mining_session","flight_notices","mining_objective","station_exterior"]:changed[key]={}
				if scenario=="empty_with_station_exterior":
					for key in ["first_flight","mining_briefing","mining_drill","mining_targeting","mining_approach","mining_session","flight_notices","mining_objective"]:changed[key]={}
				if scenario=="empty":
					for key in ["first_flight","mining_briefing","mining_drill","mining_targeting","mining_approach","mining_session","flight_notices","mining_objective","station_exterior","station_autopilot","station_flight","station_return","full_hold_departure","full_hold_flight","full_hold_pirate","full_hold_control","full_hold_story","full_hold_appearance","full_hold_destruction","full_hold_return"]:
						if changed.has(key):changed[key]={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,lib.manifest),reader.error)
		var accepted:=reader.open(directory,lib.manifest)
		# Newer packs retain a destruction owner requiring the removed flight.
		if scenario=="empty" and changed.get("player_destruction",{}).is_empty():check(accepted and reader.arrival_environment.is_empty() and not reader.arrival_staging.is_empty(),"Explicit unsupported environment rejected: "+reader.error)
		else:check(not accepted and reader.arrival_environment.is_empty() and reader.arrival_staging.is_empty(),"Failed pack retained environment: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func capture(viewport: SubViewport) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func save(image: Image, name: String):
	if not captures.is_empty():check(image.save_png(captures.path_join(name+".png"))==OK,"Failed to save rescue environment capture")
func variation(image: Image) -> int:
	var colors:={}
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):colors[image.get_pixel(x,y).to_rgba32()]=true
	return colors.size()
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)

extends SceneTree
const Resources=preload("res://src/content/station_exterior_resources.gd")
const Volumes=preload("res://src/content/station_collision_volumes.gd")
const Definitions=preload("res://src/content/station_exterior_definitions.gd")
const Geometry=preload("res://src/presentation/station_exterior_geometry.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional capture directory")
	verify_volumes()
	if args.size() in [3,4]:await verify(args)
	print("Station exterior: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func record(id: int, values: Array) -> PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize((values.size()+2)*4)
	bytes.encode_s32(0,id);bytes.encode_s32(4,values.size()-1)
	for i in values.size():bytes.encode_s32((i+2)*4,values[i])
	return bytes

func verify_volumes():
	var reader:=Volumes.new();var one:=record(78,[1,1,20,30,40,-2,-3,-4])
	var decoded:=reader.decode(record(2,[0])+one,78,136)
	check(decoded.get("source_offset")==12 and decoded.get("source_bytes")==40,"Collision reader lost record extents")
	if decoded.is_empty():return
	var box: Dictionary=decoded.boxes[0]
	check(box.center==Vector3(-20,40,30) and box.half_extents==Vector3(2,4,3),"Station box coordinate or half-extent conversion differs")
	check(Volumes.contains_point(box.center,box.center,box.half_extents),"Box center was excluded")
	for axis in 3:
		for sign_value in [-1,1]:
			var point: Vector3=box.center;point[axis]+=sign_value*box.half_extents[axis]
			check(not Volumes.contains_point(point,box.center,box.half_extents),"Station box boundary was included")
			point[axis]-=sign_value*0.01
			check(Volumes.contains_point(point,box.center,box.half_extents),"Interior station point was excluded")
			point[axis]+=sign_value*0.02
			check(not Volumes.contains_point(point,box.center,box.half_extents),"Exterior station point was included")
	check(not Volumes.contains_point(Vector3(NAN,0,0),Vector3.ZERO,Vector3.ONE),"Nonfinite collision point accepted")
	for bytes in [PackedByteArray(),one.slice(0,11),one.slice(0,one.size()-1),one+PackedByteArray([0]),one+one,record(78,[0]),record(78,[1,0,20,30,40,-2,-3,-4]),record(78,[1,1,20,30,40,0,-3,-4])]:
		check(reader.decode(bytes,78,136).is_empty() and not reader.error.is_empty(),"Malformed station collision input accepted")
	var oversized:=one.duplicate();oversized.encode_s32(4,2147483647)
	check(reader.decode(oversized,78,136).is_empty(),"Unbounded collision extent accepted")
	check(reader.decode(one,77,136).is_empty() and reader.decode(record(2,[0])+one,78,1).is_empty(),"Missing or excessive collision records accepted")
	var a:=Vector4(0,0,0,4);var b:=Vector4(8,0,0,2)
	check(Resources.merge_spheres(a,b)==Vector4(3,0,0,7),"Disjoint station layers produced incorrect union bounds")
	check(Resources.merge_spheres(a,Vector4(1,0,0,1))==a and Resources.merge_spheres(Vector4(1,0,0,1),a)==a,"Contained station layer enlarged its parent")
	check(Resources.merge_spheres(a,Vector4(0,0,0,6))==Vector4(0,0,0,6),"Concentric station bounds divided by zero")

func verify(args: Array):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var bodies:=Bodies.new();var visuals:=Visuals.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not bodies.configure(lib,bindings) or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+cat.error+bodies.error+visuals.error);return
	if bindings.station_exterior.is_empty():check(not Resources.new().configure(lib,bindings,cat,Construction.new()),"Legacy pack invented a station exterior");return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(bindings.station_exterior,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Station exterior declarations were refused")
	for key in Definitions.VALUES:
		var bad: Dictionary=bindings.station_exterior.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed station parameter accepted: "+key)
	for key in Definitions.SPANS:
		var bad: Dictionary=bindings.station_exterior.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Detached station provenance accepted: "+key)
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var packet:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3));var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,packet,[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Could not prepare rescue fixture");return
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new();check(station.configure(bindings,cat,lib,arrival.prepare_station()),station.error)
	for i in 19:station.acknowledge()
	var construction:=Construction.new()
	if not construction.prepare(bindings,cat,station.prepare_departure(bindings,cat),4096,1789100000,true,bodies):check(false,construction.error);return
	var resources:=Resources.new()
	check(resources.snapshot().is_empty() and resources.point_volume(Vector3.ZERO)==-1,"Unprepared station returned a volume")
	if not resources.configure(lib,bindings,cat,construction):check(false,resources.error);return
	var state:=resources.snapshot()
	check(state.station_id==78 and state.system_id==15 and state.name=="Var Hastra" and state.faction==3,"Wrong source station or faction")
	check(state.pose.origin==Vector3.ZERO and (state.pose.basis*state.mesh_axes*Vector3(20,40,-30)).is_equal_approx(Vector3(-20,40,30)),"Station model and volume coordinate systems disagree")
	check(state.layers.size()==3 and state.layers[0].resource_id==21078 and state.layers[1].resource_id==21878 and state.layers[2].resource_id==22078,"Station layers differ from the source constructor")
	check(state.collision.source_offset==23144 and state.collision.source_bytes==208 and state.collision.boxes.size()==7,"Var Hastra collision record differs")
	check(state.sphere.w>state.layers[0].sphere.w and state.bounds_half_extent==int(Resources.f32(state.sphere.w+5000)),"Station broad phase omitted child model bounds")
	check(not state.light_animation_supported and not state.docking_transition_supported,"Station geometry overstates animation or docking support")
	for box in state.collision.boxes:check(resources.point_volume(box.center)>=0,"Authored collision volume center was missed")
	check(resources.point_volume(Vector3.ZERO)==3 and resources.point_volume(Vector3(14,123,23))==3,"Collision volume ordering differs")
	for point in [Vector3(100000,0,0),Vector3(0,0,100000),Vector3(INF,0,0),Vector3(state.bounds_half_extent,0,0)]:check(resources.point_volume(point)==-1,"Broad phase accepted an outside station point")
	var detached:=resources.snapshot();detached.collision.boxes.clear();detached.layers.clear()
	check(resources.snapshot()==state,"Station snapshot exposed mutable source records")
	var clone:=resources.fork_for_frame();clone.clear();check(resources.snapshot()==state,"Clearing station clone erased its source")
	var faction: int=cat.tables.systems[15].fields[2];cat.tables.systems[15].fields[2]=0
	check(not resources.configure(lib,bindings,cat,construction) and resources.snapshot()==state,"Wrong faction replaced the prepared station")
	cat.tables.systems[15].fields[2]=faction
	var foreign:=Construction.new();foreign._state=construction._state.duplicate(true);foreign._state.binding_id="foreign"
	# The construction snapshot also needs its prepared simulation owners.
	foreign._scenery=construction.scenery_owner();foreign._player=construction.player_owner();foreign._camera=construction.camera_owner()
	check(not resources.configure(lib,bindings,cat,foreign) and resources.snapshot()==state,"Foreign departure replaced the prepared station")
	var flight:=Frame.new()
	if not flight.configure(bindings,cat,lib,construction,"E",0.5,Vector2i(960,720)):check(false,flight.error);return
	var initial:=flight.snapshot();var legacy:=Frame.new();var declaration: Dictionary=bindings.station_exterior;var live: Dictionary=bindings.station_flight;var arrival_rules: Dictionary=bindings.station_return
	bindings.station_exterior={};bindings.station_flight={};bindings.station_return={}
	check(legacy.configure(bindings,cat,lib,construction,"E",0.5,Vector2i(960,720)),legacy.error)
	bindings.station_exterior=declaration;bindings.station_flight=live;bindings.station_return=arrival_rules
	var without:=initial.duplicate(true);without.erase("station_exterior");without.erase("station_volume_index");without.erase("station_autopilot");without.erase("station_arrival");without.erase("boundary")
	check(without==legacy.snapshot(),"Station construction changed flight, cargo or random state")
	check(flight.evaluate(100,Vector2.ONE,0.0,true).snapshot()==initial,"Paused station world advanced")
	for i in 71:
		flight=flight.evaluate(100);legacy=legacy.evaluate(100)
		if flight==null or legacy==null:check(false,"Station flight failed to advance");return
	var moving: Dictionary=flight.snapshot();without=moving.duplicate(true);without.erase("station_exterior");without.erase("station_volume_index");without.erase("station_autopilot");without.erase("station_arrival");without.erase("boundary")
	check(without==legacy.snapshot() and moving.station_exterior==state,"Station update changed ordinary simulation")
	var inside: RefCounted=flight.fork_for_frame();inside._pose.origin=Vector3.ZERO
	var overlap: Dictionary=inside.snapshot()
	check(overlap.station_volume_index==3 and overlap.mission==moving.mission and overlap.campaign_cursor==2 and overlap.cargo==moving.cargo and not overlap.mining_completed,"Station overlap awarded arrival, cargo or campaign progress")
	if args.size()==4 and failures==0:await render(args[3],lib,bindings,visuals,cat,resources,flight)
	resources.clear();check(resources.snapshot().is_empty() and flight.snapshot()==moving,"External station clear changed its flight")

func render(directory: String,lib: RefCounted,bindings: RefCounted,visuals: RefCounted,cat: RefCounted,resources: RefCounted,flight: RefCounted):
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var scene:=Scene.new();canvas.add_child(scene)
	if not scene.build(lib,bindings,visuals,cat,flight):check(false,scene.error);canvas.free();return
	check(scene.station!=null and scene.station.layers.size()==3,"Live flight omitted its station layers")
	check(scene.station.station.get_meta("source_station_id")==78,"Scene rendered the wrong station")
	var main_mesh: MeshInstance3D=scene.station.layers[0].instances[0]
	var world_bounds: AABB=main_mesh.global_transform*main_mesh.mesh.get_aabb()
	check(world_bounds.end.z<scene.camera.position.z,"Station hull obstructs the released departure camera after an extra axis conversion")
	for i in 3:
		var model: Node3D=scene.station.layers[i]
		check(model.get_meta("source_resource_id")==[21078,21878,22078][i],"Scene model selection differs")
		check(model.global_basis.is_equal_approx(resources.snapshot().pose.basis) and Resources.MESH_AXES==Basis.IDENTITY,"Station vertex coordinates were converted twice")
	var original: Transform3D=scene.geometry.player.transform
	var foreign: RefCounted=flight.fork_for_frame();foreign._station._state.station_id=1
	check(not scene.present(foreign) and scene.geometry.player.transform==original and scene.station.station.get_meta("source_station_id")==78,"Rejected station changed the visible scene")
	check(scene.present(flight),scene.error)
	await capture(canvas,directory,"station-flight")
	# Inspection cameras are deliberately separate from source gameplay cameras.
	scene.geometry.hide();scene.scenery.hide()
	for pose in [{"name":"station-overview","eye":Vector3(45000,32000,65000),"target":Vector3(-6000,1000,0)},{"name":"station-reverse","eye":Vector3(-60000,-12000,-40000),"target":Vector3(-6000,1000,0)}]:
		scene.camera.position=pose.eye;scene.camera.look_at(pose.target)
		var view:={"pose":scene.camera.global_transform}
		check(scene.sky.apply_view(view) and scene.planets.apply_view(view),"Inspection background failed")
		var shown: Image=await capture(canvas,directory,pose.name)
		scene.station.hide();var hidden: Image=await capture(canvas,"","")
		check(shown.get_data()!=hidden.get_data(),"Station did not contribute visible pixels")
		scene.station.show()
	canvas.free()

func capture(canvas: SubViewport, directory: String, label: String) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=canvas.get_texture().get_image()
	if not directory.is_empty():check(image.save_png(directory.path_join(label+".png"))==OK,"Could not save station capture")
	return image
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)

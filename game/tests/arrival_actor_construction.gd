extends SceneTree
## Shared factory stream and authored rescue handoff. Target decisions remain
## explicit in the motion integration; this test is not a complete world claim.
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Motion=preload("res://src/simulation/arrival_actor_motion.gd")
const Staging=preload("res://src/simulation/arrival_choreography.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/arrival_actor_construction_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
var checks:=0
var failures:=0

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visual triples")
	for i in range(0,args.size()-2,3):verify_profile(args[i],args[i+1])
	print("Arrival actor construction: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_profile(content: String, pack: String):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var owner:=Construction.new()
	if bindings.arrival_actor_construction.is_empty() or not preload("res://src/content/arrival_staging_definitions.gd").parameters(bindings.arrival_staging):
		check(not owner.configure_arrival(bindings,cat,{}),"Legacy profile invented rescue construction")
		check(owner.snapshot().is_empty() and owner.arrival_motion_construction().is_empty(),"Legacy construction retained actor poses")
		return
	var fresh:=Player.new();var player:=Player.new()
	check(fresh.configure(bindings,cat),fresh.error)
	check(player.configure_arrival(bindings,cat,fresh.cache_snapshot()),player.error)
	var cache:=player.cache_snapshot();var original: Array=cat.tables.items.duplicate(true)
	for fixture in FIXTURES:
		cat.tables.items=original.duplicate(true)
		if fixture.restricted:
			for item in cat.tables.items:item.arrays[0]=[1]
		check(owner.configure_arrival(bindings,cat,cache),owner.error)
		var empty:=owner.snapshot()
		check(owner.arrival_motion_construction().is_empty(),"Ungenerated rescue poses escaped")
		for bad in [{},{"state":-1},{"state":281474976710656},{"state":true}]:
			check(owner.generate(bad).is_empty() and owner.snapshot()==empty,"Invalid RNG partly constructed the rescue")
		var result:=owner.generate({"state":fixture.input_state})
		check(not result.is_empty(),owner.error)
		if result.is_empty():continue
		check(result.random_state.state==fixture.state,"Rescue consumed the wrong number or order of random draws")
		check(result.campaign_cursor==1 and result.actors.size()==1,"Rescue created the opening population")
		var actual: Dictionary=result.actors[0];var expected: Dictionary=fixture.actors[0]
		check(actual.actor_id==0 and actual.actor_kind==3 and actual.hull_catalogue_id==30 and actual.subtype==0,"Rescue actor identity changed")
		check(actual.factory_position==vector(expected.position),"Discarded spawn position lost its draws")
		check(actual.cargo==expected.discarded and actual.discarded_cargo.is_empty(),"Rescue lost generated cargo")
		check(actual.discarded_route.candidate_indices==expected.indices,"Rescue generated the wrong discarded route")
		for i in expected.waypoints.size():check(actual.discarded_route.waypoints[i]==vector(expected.waypoints[i]),"Discarded route coordinate changed")
		check(actual.route.waypoints==[Vector3(0,0,-5000),Vector3.ZERO] and actual.route.index==0 and not actual.route.loop,"Rescue did not replace the route with its authored non-looping points")
		check(actual.fragments.size()==expected.count,"Rescue fragment count differs")
		check_fragment(actual.fragments[0],expected.first_fragment)
		check_fragment(actual.fragments[-1],expected.last_fragment)
		check(actual.body_pose==Transform3D(Basis.IDENTITY,Vector3(300,50,-6000)) and actual.statistics_pose==actual.body_pose and actual.model_local_pose==Transform3D.IDENTITY,"Authored placement or initial transform changed")
		check(actual.model_draw_enabled and not actual.engine_draw_enabled and actual.engine_resource_id==18030 and owner.route(0)==null,"Generated patrol route or model draw escaped authored replacement")
		var motion:=Motion.new()
		check(motion.configure(bindings,cat,cache,owner.arrival_motion_construction()),motion.error)
		check(motion.snapshot().statistics_pose==actual.statistics_pose,"Constructed statistics were not handed to motion")
		var saved:=owner.snapshot()
		check(owner.generate({"state":fixture.input_state}).is_empty() and owner.snapshot()==saved,"Rescue regenerated after construction")
		result.actors[0].cargo.clear();result.actors[0].discarded_route.waypoints.clear();result.actors[0].route.waypoints.clear();result.random_state.state=0
		var poses:=owner.arrival_motion_construction();poses.body_pose=Transform3D.IDENTITY
		check(owner.snapshot()==saved,"Exported rescue records alias retained state")
	cat.tables.items=original.duplicate(true)
	verify_motion(owner,bindings,cat,lib,cache)
	for field in ["base_content_id","binding_id","campaign_cursor","ship_id","station_id"]:
		var bad:=cache.duplicate(true);bad[field]="foreign" if field.ends_with("content_id") or field=="binding_id" else -1
		check(not owner.configure_arrival(bindings,cat,bad) and owner.snapshot().is_empty(),"Foreign rescue cache accepted: "+field)
	check(not owner.configure_arrival(bindings,cat,fresh.cache_snapshot()),"Opening cache admitted as a rescue cache")
	cat.tables.items[54].arrays[2][5]=18
	check(not owner.configure_arrival(bindings,cat,cache) and owner.snapshot().is_empty(),"Special cargo override entered unsupported rescue scope")
	cat.tables.items=original
	verify_pack(pack,lib,bindings)
	print(lib.manifest.profile.edition+": retained cargo, discarded RNG work, authored route/poses and motion handoff verified")

func verify_motion(owner: RefCounted, bindings: RefCounted, cat: RefCounted, lib: RefCounted, cache: Dictionary):
	check(owner.configure_arrival(bindings,cat,cache),owner.error)
	check(not owner.generate({"state":25214903917}).is_empty(),owner.error)
	var motion:=Motion.new();var staging:=Staging.new()
	check(motion.configure(bindings,cat,cache,owner.arrival_motion_construction()),motion.error)
	check(staging.configure(bindings,lib),staging.error)
	var identity: Dictionary={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":1}
	var radio:=identity.duplicate();radio.started=[false,false,false];radio.finished=[false,false,false]
	for i in 52:
		var previous:=motion.snapshot()
		check(staging.advance(100,radio,previous.statistics_pose.origin,previous.body_pose,true),staging.error)
		var cues:=staging.snapshot();var dispatch:=identity.duplicate()
		dispatch.merge({"generation":cues.generation,"mode_at_dispatch":5,"actor_hostile":false,"route_has_targets":true,"target_present":true,"target_excluded":false,
			"target_relative_position":-cues.frame.actor_pose_override.origin,"model_local_pose":previous.model_local_pose})
		check(motion.advance(cues,dispatch),motion.error)
		if i in [0,49,50,51]:
			var expected: Dictionary={0:-5980.0,49:-5000.0,50:-4980.0,51:-4960.080078125}
			check(motion.snapshot().body_pose.origin==Vector3(300,50,expected[i]),"Constructed actor diverged at the approach speed boundary")
	check(owner.snapshot().actors[0].body_pose.origin==Vector3(300,50,-6000),"Motion mutated the construction snapshot")

func verify_pack(pack: String, lib: RefCounted, bindings: RefCounted):
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var directory:=OS.get_user_data_dir().path_join("arrival-construction-test-"+str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","type","changed","proof","routes","construction","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("arrival_actor_construction")
			"type":changed.arrival_actor_construction=false
			"changed":changed.arrival_actor_construction.authored_route_loop=true
			"proof":changed.arrival_actor_construction.provenance.placement.offset+=1
			"routes":changed.opening_actors.npc_initialization.routes={}
			"construction":changed.opening_actors.npc_initialization.construction={}
			"empty":
				changed.arrival_actor_construction={}
				# Later flight and station capabilities require this rescue world.
				# An explicitly unsupported fixture must remove those dependents too.
				for key in ["arrival_world_initialization","opening_handoff","arrival_session","station_entry","station_presentation","station_departure","first_flight","mining_briefing","mining_drill","mining_targeting","mining_approach","mining_session","flight_notices","mining_objective","station_exterior","station_autopilot","station_flight","station_return","full_hold_departure","full_hold_flight","full_hold_pirate","full_hold_control","full_hold_story","full_hold_appearance","full_hold_destruction","full_hold_return"]:
					if changed.has(key):changed[key]={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		check(bindings.open(pack,lib.manifest),bindings.error)
		var accepted: bool=bindings.open(directory,lib.manifest)
		if scenario=="empty":check(accepted and bindings.arrival_actor_construction.is_empty(),"Explicit unsupported construction capability rejected")
		else:check(not accepted and bindings.arrival_actor_construction.is_empty() and bindings.arrival_environment.is_empty(),"Rejected pack retained rescue construction: "+scenario)
	check(bindings.open(pack,lib.manifest),bindings.error)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func vector(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])
func check_fragment(actual: Dictionary, expected: Array):
	var rotation:=Vector3.ZERO
	for axis in 3:rotation[axis]=Vitals.single(Vitals.single(float(expected[axis])/180.0)*3.1415927410125732)
	check(actual.resource_id==14292 and actual.rotation_radians==rotation and actual.scale==Vitals.single(float(expected[3])/100.0),"Fragment conversion or resource changed")
func check(value: bool, message: String):
	checks+=1
	if not value:failures+=1;push_error(message)

const FIXTURES = [{"input_state":25214903917,"state":203325453775594,"actors":[{"position":[1360,5948,8029],"indices":[3,0,1,2],"waypoints":[[-17527,-5738,61095],[-13553,-6485,26053],[9491,-239,38719],[12854,-8923,62677]],"discarded":[{"item_id":124,"quantity":3}],"count":6,"first_fragment":[195,200,295,55],"last_fragment":[187,107,268,55]}],"restricted":false},{"input_state":25214903916,"state":76365784130308,"actors":[{"position":[8985,-15412,-18153],"indices":[3,1,0],"waypoints":[[-14683,-8737,75562],[9434,-3394,34978],[-9687,-5746,34904]],"discarded":[{"item_id":109,"quantity":8},{"item_id":118,"quantity":3}],"count":7,"first_fragment":[0,151,286,83],"last_fragment":[165,29,299,95]}],"restricted":false},{"input_state":25214903934,"state":193914656079601,"actors":[{"position":[-8275,1644,-15944],"indices":[2,3],"waypoints":[[8022,-520,60504],[-29389,-3928,56514]],"discarded":[{"item_id":150,"quantity":5}],"count":9,"first_fragment":[289,68,284,93],"last_fragment":[203,191,301,66]}],"restricted":false},{"input_state":24499952013,"state":141313508644643,"actors":[{"position":[16714,-8199,-3085],"indices":[3,2],"waypoints":[[-24259,-5950,64978],[19309,-2979,76084]],"discarded":[],"count":4,"first_fragment":[178,102,294,94],"last_fragment":[314,214,233,60]}],"restricted":false},{"input_state":280936762154123,"state":219154870465129,"actors":[{"position":[704,5566,3393],"indices":[0,1,2,3],"waypoints":[[-8751,-4631,44913],[15734,-6284,34796],[19883,-4737,77313],[-6418,-131,78579]],"discarded":[{"item_id":125,"quantity":8}],"count":5,"first_fragment":[166,125,241,61],"last_fragment":[313,235,124,70]}],"restricted":false},{"input_state":153548941033574,"state":266336588563691,"actors":[{"position":[14720,13852,-11917],"indices":[3,2],"waypoints":[[-22286,-6119,67295],[28952,-5937,64869]],"discarded":[{"item_id":112,"quantity":1},{"item_id":118,"quantity":8}],"count":8,"first_fragment":[113,108,66,93],"last_fragment":[271,285,40,62]}],"restricted":false},{"input_state":25214903934,"state":179309105939508,"actors":[{"position":[-8275,1644,-15944],"indices":[2,3],"waypoints":[[8022,-520,60504],[-29389,-3928,56514]],"discarded":[{"item_id":161,"quantity":2}],"count":5,"first_fragment":[123,183,214,75],"last_fragment":[24,243,187,62]}],"restricted":true}]

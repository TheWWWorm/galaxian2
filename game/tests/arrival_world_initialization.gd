extends SceneTree
## Mac rescue initialization at the full field -> NPC -> weapon boundary.
## Retained campaign conditions are explicit; no live session/completion claim.
const World=preload("res://src/simulation/opening_world_initialization.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Population=preload("res://src/simulation/scenery_population.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Motion=preload("res://src/simulation/arrival_actor_motion.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/arrival_world_initialization_definitions.gd")
const CONDITIONS={"companions_empty":true,"location_match":false}
const CENTER=Vector3(12298,36830,77237)
var checks:=0
var failures:=0

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected one Mac content/bindings/visuals triple")
	if args.size()==3:verify_profile(args[0],args[1])
	print("Mac rescue world initialization: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_profile(content: String, pack: String):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	check(lib.manifest.profile.edition=="mac-full-hd","Current rescue initialization validation is Mac only")
	var fresh:=Player.new();var player:=Player.new();var world:=World.new();var population:=Population.new()
	check(fresh.configure(bindings,cat) and player.configure_arrival(bindings,cat,fresh.cache_snapshot()),fresh.error+player.error)
	var cache:=player.cache_snapshot()
	check(population.configure(bindings),population.error)
	if bindings.arrival_world_initialization.is_empty():
		check(not world.configure_arrival(bindings,cat,cache,CONDITIONS),"Legacy pack invented rescue world initialization")
		check(population.for_arrival(78,CONDITIONS).is_empty(),"Legacy pack invented the rescue center")
		return
	check(Definitions.parameters(bindings.arrival_world_initialization),"Mac rescue declarations rejected")
	var selected:=population.for_arrival(78,CONDITIONS)
	check(selected.center==CENTER and selected.count==130,"Rescue center or Mac scenery count differs")
	check(selected.count_random_state.state==203883236650738 and selected.random_state.state==249765198238295,"Station count/center draws are out of order")
	for state in FIXTURES:
		check(world.configure_arrival(bindings,cat,cache,CONDITIONS),world.error)
		check(world.generate({"state":-1}).is_empty() and world.snapshot().is_empty(),"Invalid RNG partially constructed rescue actors")
		var result:=world.generate({"state":state.input_state})
		check(not result.is_empty(),world.error)
		if result.is_empty():return
		verify_world(result,state)
		var saved:=world.snapshot();var motion:=Motion.new()
		check(motion.configure(bindings,cat,cache,world.arrival_motion_construction()),motion.error)
		check(motion.snapshot().body_pose.origin==Vector3(300,50,-6000),"World construction lost authored actor placement")
		check(world.route(0)==null,"Discarded patrol became the rescue's active route")
		result.npc_construction.actors[0].cargo.clear();result.weapon_effects[0].primary.flipped.clear();result.entry_conditions.clear()
		check(world.snapshot()==saved,"World records alias retained state")
		check(world.generate({"state":0}).is_empty() and world.snapshot()==saved,"Rescue initialization ran twice")
	var scene:=Scenery.new();var opening:=Scenery.new()
	check(scene.configure_arrival(bindings,cat,cache,CONDITIONS,1789100000),scene.error)
	var field:=scene.snapshot()
	check(field.center==CENTER and field.objects.size()==130 and field.random_state.state==153548941033574,"Rescue field did not use the separate Unix seed")
	check(opening.configure(bindings,cat,1789100000),opening.error)
	var original:=opening.snapshot()
	check(original.random_state==field.random_state,"Center draws leaked into the field RNG")
	for i in field.objects.size():
		check(field.objects[i].position==original.objects[i].position+CENTER,"Rescue field was not centered on its source location")
		var row: Dictionary=field.objects[i].duplicate(true);row.position=original.objects[i].position
		check(row==original.objects[i],"Rescue field altered shared ore/scale/spin construction")
	var independent:=scene.fork_for_frame()
	check(independent.complete_world_initialization(bindings,cat),independent.error)
	check(scene.snapshot()==field,"Staged initialization mutated the previous scenery owner")
	var id: String=bindings.binding_id;bindings.binding_id="0".repeat(64)
	check(not scene.complete_world_initialization(bindings,cat) and scene.snapshot()==field,"Foreign binding changed the field RNG")
	bindings.binding_id=id
	var items: Array=cat.tables.items.duplicate(true);cat.tables.items[54].arrays[2][5]=33
	check(not scene.complete_world_initialization(bindings,cat) and scene.snapshot()==field,"Optional population was skipped without its equipment prerequisite")
	cat.tables.items=items
	check(scene.complete_world_initialization(bindings,cat),scene.error)
	var initialized:=scene.snapshot()
	verify_world(initialized.world_initialization,FIXTURES[1])
	check(initialized.random_state.state==205194410392979 and initialized.world_initialization.input_random_state==field.random_state,"Rescue did not retain the final world RNG")
	check(initialized.objects==field.objects and initialized.detail==field.detail,"NPC construction changed scenery")
	check(independent.snapshot()==initialized,"Staged deterministic initialization disagrees")
	check(not scene.complete_world_initialization(bindings,cat) and scene.snapshot()==initialized,"Repeated initialization changed an existing world")
	check(not scene.arrival_motion_construction().is_empty(),scene.error)
	var staged:=scene.fork_for_frame()
	check(staged.update(100,Vector3.ZERO),staged.error)
	check(staged.snapshot().random_state==initialized.random_state and scene.snapshot()==initialized,"Scenery spin consumed RNG or mutated the previous frame")
	check(not staged.complete_world_initialization(bindings,cat),"Running scenery allowed initialization")
	check(scene.configure_arrival(bindings,cat,cache,CONDITIONS,1789100000),scene.error)
	check(not scene.update(-1,Vector3.ZERO) and scene.complete_world_initialization(bindings,cat),"A rejected frame closed the initialization boundary")
	check(scene.configure_arrival(bindings,cat,cache,CONDITIONS,1789100000),scene.error)
	check(scene.update(0,Vector3.ZERO) and not scene.complete_world_initialization(bindings,cat),"A successful zero-time frame left initialization open")
	for key in CONDITIONS:
		for value in [null,1,not CONDITIONS[key]]:
			var invalid:=CONDITIONS.duplicate();invalid[key]=value
			check(not world.configure_arrival(bindings,cat,cache,invalid) and world.snapshot().is_empty(),"Unsupported rescue entry condition accepted: "+key)
			check(population.for_arrival(78,invalid).is_empty(),"Unsupported rescue center context accepted")
	for key in ["base_content_id","binding_id","campaign_cursor","ship_id","station_id"]:
		var bad:=cache.duplicate(true);bad[key]="foreign" if key.ends_with("content_id") or key=="binding_id" else -1
		check(not world.configure_arrival(bindings,cat,bad,CONDITIONS),"Foreign cache accepted: "+key)
	check(not scene.configure_arrival(bindings,cat,cache,CONDITIONS,-1) and scene.snapshot().is_empty(),"Invalid Unix time built scenery")
	verify_pack(pack,lib,bindings)
	scene.clear();world.clear();population.clear()
	check(scene.snapshot().is_empty() and world.snapshot().is_empty() and population.for_arrival(78,CONDITIONS).is_empty(),"Clear retained rescue initialization")

func verify_world(result: Dictionary, expected: Dictionary):
	check(result.campaign_cursor==1 and result.entry_conditions==CONDITIONS,"World lost its bounded entry context")
	check(result.npc_construction.actors.size()==1 and result.weapon_effects.size()==1,"Rescue gained extra actors")
	check(result.npc_construction.random_state.state==expected.npc_state and result.random_state.state==expected.final_state,"Rescue NPC/effect RNG boundary differs")
	var actor: Dictionary=result.npc_construction.actors[0]
	check(actor.cargo==expected.cargo and actor.discarded_cargo.is_empty(),"Rescue discarded or granted the wrong constructed cargo")
	check(actor.route.waypoints==[Vector3(0,0,-5000),Vector3.ZERO] and not actor.route.loop,"Rescue lost its authored non-looping route")
	var effect: Dictionary=result.weapon_effects[0]
	check(effect.discarded_default.item_id==0 and effect.discarded_default.resource_id==14600,"Default effect allocation was omitted")
	check(effect.primary.item_id==25 and effect.primary.resource_id==14606,"Opening weapon assignment leaked into rescue")
	check(effect.discarded_default.flipped==expected.flipped[0] and effect.primary.flipped==expected.flipped[1],"Rescue did not retain both four-slot effect draws")

func verify_pack(pack: String, lib: RefCounted, bindings: RefCounted):
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_user_data_dir().path_join("rescue-world-invalid")
	DirAccess.make_dir_recursive_absolute(directory)
	for mutation in ["missing","item","center","extent","numeric_condition"]:
		var bad:=body.duplicate(true)
		match mutation:
			"missing":bad.erase("arrival_world_initialization")
			"item":bad.arrival_world_initialization.weapon_item_sequence[1]=19
			"center":bad.arrival_world_initialization.center_offsets=[0,0,0]
			"extent":bad.arrival_world_initialization.provenance.center.offset+=2
			"numeric_condition":bad.arrival_world_initialization.requires_empty_companions=1
		var serialized:=JSON.stringify(bad,"",true,true);var changed:=header.duplicate(true)
		changed.records_sha256=serialized.sha256_text();changed.records_bytes=serialized.to_utf8_buffer().size()
		changed.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[changed.base_content_id,changed.source_executable_sha256,changed.architecture,changed.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(changed));file.close()
		var candidate:=Bindings.new()
		check(candidate.open(pack,lib.manifest),candidate.error)
		check(not candidate.open(directory,lib.manifest) and candidate.arrival_world_initialization.is_empty(),"Altered rescue profile accepted: "+mutation)
		check(candidate.error.to_lower().contains("rescue world initialization"),"Altered pack failed before the rescue capability validator: "+candidate.error)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)

const FIXTURES=[{"input_state":25214903917,"npc_state":203325453775594,"final_state":1262582287474,"cargo":[{"item_id":124,"quantity":3}],"flipped":[[false,false,true,true],[true,true,true,true]]},{"input_state":153548941033574,"npc_state":266336588563691,"final_state":205194410392979,"cargo":[{"item_id":112,"quantity":1},{"item_id":118,"quantity":8}],"flipped":[[true,false,false,false],[false,true,true,false]]}]

extends SceneTree
const Actor=preload("res://src/simulation/opening_combat_actor.gd")
const Definitions=preload("res://src/content/npc_hull_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	var stride:=2 if args.size()==2 else 3
	check(args.size()>0 and args.size()%stride==0,"Pass a content/bindings pair or content/bindings/visuals triples")
	for i in range(0,args.size()-stride+1,stride):verify(args[i],args[i+1])
	print("NPC hull checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify(content: String, pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new();var actor:=Actor.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var npc: Dictionary=bindings.opening_actors.npc_initialization
	if npc.get("hull",{}).is_empty():
		check(actor.configure(bindings,catalogues,0,10),actor.error)
		check(not actor.snapshot().has("max_hull") and not actor.snapshot().has("hull_percent"),"Legacy bindings invented NPC capacity")
		return
	if Definitions.legacy_parameters(npc.hull):
		check(not actor.configure(bindings,catalogues,0,10) and actor.snapshot().is_empty(),"Outdated rank assumption entered native combat")
		return
	var definition: Dictionary=npc.hull
	var architecture: String="armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	verify_stale_pack(pack,library,architecture)
	check(Definitions.validate(definition,10000000,architecture,npc).is_empty(),"Source NPC hull declaration rejected")
	for key in definition.provenance:
		var bad:=definition.duplicate(true);bad.provenance[key].offset+=2
		check(not Definitions.validate(bad,10000000,architecture,npc).is_empty(),"Disconnected NPC hull provenance accepted")
	for key in ["rank","campaign_cursor","factory_subtype","base_hull","difficulty_offset","percentage_scale"]:
		var bad:=definition.duplicate(true);bad[key]+=1
		check(not Definitions.parameters(bad),"Unsupported NPC hull parameter accepted: "+key)
	# These explicit vectors include the source difficulty rounding before the
	# opening override, and a higher factory maximum retained by that override.
	for row in [[0.0,10,150,100],[0.5,20,150,100],[1.0,30,150,100],[2.5,60,150,100],
		[7.0,150,150,100],[7.05,151,151,99],[7.1,152,152,98],[8.0,170,170,88],[10.0,210,210,71]]:
		for id in 3:
			check(actor.configure(bindings,catalogues,id,row[0]),actor.error)
			var state:=actor.snapshot()
			check(state.factory_hull==row[1] and state.max_hull==row[2] and state.vitals.hull==150 and state.hull_percent==row[3],"Factory/override hull mismatch: "+str(row))
	check(actor.configure(bindings,catalogues,0,1.0),actor.error)
	var initial:=actor.snapshot()
	check(not actor.normal_hit(63).accepted and actor.snapshot()==initial,"Inactive target lost maximum or health")
	check(actor.set_permissions(true,true,true),actor.error)
	check(actor.normal_hit(63).accepted and actor.snapshot().vitals.hull==87 and actor.snapshot().hull_percent==58,"Hull percentage lost source float rounding at 87/150")
	check(actor.snapshot().max_hull==150,"Damage lowered maximum hull")
	var saved:=actor.snapshot();var fork: RefCounted=actor.fork_for_frame()
	check(fork.snapshot()==saved,"Actor fork lost hull capacity")
	check(fork.normal_hit(87).destroyed_now and fork.snapshot().hull_percent==0 and fork.snapshot().max_hull==150,"Death lost maximum or retained a positive percentage")
	check(actor.snapshot()==saved,"Detached damage changed the original actor")
	check(actor.set_permissions(true,false,true),actor.error)
	saved=actor.snapshot()
	check(not actor.normal_hit(80).accepted and actor.snapshot()==saved,"Denied damage changed hull percentage")
	check(actor.normal_hit(-1).is_empty() and actor.snapshot()==saved,"Invalid damage changed retained health")
	check(actor.set_pose(Transform3D(Basis.IDENTITY,Vector3(1,2,3))),actor.error)
	check(actor.snapshot().vitals.hull==87 and actor.snapshot().max_hull==150 and actor.snapshot().hull_percent==58,"Scene positioning reset NPC capacity")
	npc.world_initialization.campaign_cursor=1
	check(not actor.configure(bindings,catalogues,0,1.0) and actor.snapshot().is_empty(),"Later campaign reused fresh hull formula")
	npc.world_initialization.campaign_cursor=0
	bindings.opening_actors.actors[0].hull_catalogue_id=23
	check(not actor.configure(bindings,catalogues,0,1.0) and actor.snapshot().is_empty(),"Changed hull reused a fresh actor binding")
	bindings.opening_actors.actors[0].hull_catalogue_id=2
	var world: Dictionary=npc.world_initialization
	for bad_world in [null,[],true,1]:
		npc.world_initialization=bad_world
		check(not Definitions.validate(definition,10000000,architecture,npc).is_empty(),"Malformed hull context passed validation")
		check(not actor.configure(bindings,catalogues,0,1.0) and actor.snapshot().is_empty(),"Malformed hull context retained an actor")
	npc.world_initialization=world
	check(actor.configure(bindings,catalogues,0,10.0) and actor.snapshot().max_hull==210,actor.error)
	actor.clear()
	check(actor.snapshot().is_empty(),"Cleared actor retained health")
	print(library.manifest.profile.edition,": factory capacity, difficulty, source percentages, denied hits and detached death verified")

func verify_stale_pack(pack: String, library: RefCounted, architecture: String) -> void:
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var directory:=OS.get_user_data_dir().path_join("npc-hull-entry-test-"+str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["outdated_rank","missing_entry_proof"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		var hull: Dictionary=changed.opening_actors.npc_initialization.hull
		for key in hull.provenance.keys():
			if not Definitions.LEGACY_SPANS[architecture].has(key):hull.provenance.erase(key)
		if scenario=="outdated_rank":hull.rank=1;hull.base_hull=34
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,library.manifest),reader.error)
		check(not reader.open(directory,library.manifest) and reader.opening_actors.is_empty(),"Current pack retained stale or unverified rank: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)

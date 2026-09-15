extends SceneTree
## Original station inputs and deterministic geometry vectors. This does not
## manufacture flight permission or a visited station.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Gate=preload("res://src/simulation/gate_environment.gd")
const Definitions=preload("res://src/content/gate_environment_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() in [2,3]:verify(args)
	else:check(false,"Expected content and binding paths")
	print("Gate environment: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var owner:=Gate.new()
	if not Definitions.available(bindings):
		check(not owner.configure(bindings,cat,95) and owner.snapshot().is_empty(),"Older pack inferred gate geometry")
		return
	if not owner.configure(bindings,cat,95):check(false,owner.error);return
	var state:=owner.snapshot();var gate:=owner.object_state(1);var incoming:=owner.object_state(2)
	check(state.station_id==95 and state.system_id==19 and state.gate_type==0 and state.gate_station_id==95,"Gome C catalogue gate selection changed")
	check(state.objects.size()==2 and gate.interactive and not incoming.interactive,"Gome C gate/arrival object roles changed")
	check(gate.angle_units==5120 and incoming.angle_units==11904,"The second gate lost the accumulated station angle")
	check(gate.sign_draw==1 and gate.increment_draw==70 and incoming.sign_draw==1 and incoming.increment_draw==174,"Gate generator draw order changed")
	check(gate.pose.origin.distance_to(Vector3(49666.359375,0,92919.21875))<0.02,"Gome C outgoing gate position changed")
	check(incoming.pose.origin.distance_to(Vector3(141568.375,0,64843.078125))<0.02,"Gome C incoming gate position changed")
	check(owner.arrival_position()==incoming.pose.origin,"Incoming flight selected the outgoing gate")
	check(state.random_state=={"state":251835078962695},"Gate generation changed the random continuation")
	check(gate.mesh_id==15000 and gate.child_mesh_ids==[15002,15001] and gate.jump_mesh_id==15003,"Terran gate lost original model layering")
	check(gate.lod_mesh_ids==[15016.0,15020.0] and gate.lod_distances==[40000.0,70000.0],"Gate LOD resources or distances changed")
	check(gate.collision_radius==7500.0 and incoming.collision_radius==0.0,"Arrival gate gained an interactive collision sphere")
	check(gate.pose.basis.is_equal_approx(Basis(Vector3.UP,PI)),"Gate model lost its original half-turn")
	var retained:=owner.snapshot();state.objects.clear();gate.models.clear()
	check(owner.snapshot()==retained,"Caller changed accepted gate layout")
	check(owner.fork().snapshot()==retained,"Detached gate layout changed")
	for id in [-1,135]:check(not owner.configure(bindings,cat,id) and owner.snapshot()==retained,"Invalid station replaced gate layout")
	if not owner.configure(bindings,cat,98):check(false,owner.error);return
	state=owner.snapshot();incoming=owner.object_state(2)
	check(state.objects.size()==1 and owner.object_state(1).is_empty(),"Alioth gained an outgoing inter-system gate")
	check(incoming.angle_units==4592 and state.random_state=={"state":194079232826379},"Skipped gate consumed random draws")
	check(incoming.pose.origin.distance_to(Vector3(57011.0390625,0,121019.6640625))<0.02,"Alioth arrival gate position changed")
	# Exercise every supplied ordinary catalogue faction without granting its
	# campaign or special-world availability. Original models must all resolve.
	var types:={};var locations:=0
	for station in cat.tables.stations:
		var system: Dictionary=cat.tables.systems[station.system_id]
		var type:=int(system.fields[2])
		if type<0 or type>3:continue
		if not owner.configure(bindings,cat,int(station.id)):check(false,owner.error);continue
		locations+=1;types[type]=true
		var rows: Array=owner.snapshot().objects
		check(rows.size()==(2 if station.id==system.fields[6] else 1),"Catalogue gate predicate changed at%d"%station.id)
		for row in rows:
			for path in row.models.values():check(library.manifest.files.has(path),"Original gate mesh absent: "+path)
			if type==1:check(row.child_lod_mesh_ids==[15024.0,15025.0],"Vossk child meshes were interpreted as an animation speed")
	check(types.size()==4 and locations>100,"Catalogue coverage omitted an ordinary gate faction")
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in Definitions.SPANS:
		var changed: Dictionary=bindings.mido_travel.duplicate(true);changed.provenance.erase(key)
		check(not Travel.validate(changed,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Missing gate proof was accepted: "+key)

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)

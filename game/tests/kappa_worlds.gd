extends SceneTree
## Source catalogue and scenery composition only. This grants no travel,
## campaign progress or location availability, and does not bypass world guards.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Planet=preload("res://src/simulation/opening_planet_layout.gd")
const Gate=preload("res://src/simulation/gate_environment.gd")
const MeshReader=preload("res://src/content/aem.gd")
const Exterior=preload("res://src/content/station_exterior_resources.gd")
const Volumes=preload("res://src/content/station_collision_volumes.gd")
const WORLDS={6:{"stations":[10],"types":[9],"security":3,"sky":0,"gate":10},7:{"stations":[35,36,37,38,39],"types":[6,16,11,9,18],"security":1,"sky":7,"gate":35}}
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Kappa onward scenery components: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var vectors: Variant=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("GOF2_KAPPA_WORLD_VECTORS")))
	if not vectors is Array or vectors.size()!=6:check(false,"Supply the six independently calculated source planet vectors");return
	var planet_rules: Dictionary=bindings.opening_sky.planet_resources
	var report:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"catalogues":cat.provenance,"locations":[]}
	for system_id in WORLDS:
		var expected: Dictionary=WORLDS[system_id];var system: Dictionary=cat.tables.systems[system_id]
		check(Array(system.station_ids)==expected.stations and system.sky_index==expected.sky and system.fields[0]==expected.security and system.fields[2]==0 and system.fields[6]==expected.gate,"The onward system differs from the verified catalogue")
		for n in expected.stations.size():
			var station_id: int=expected.stations[n];var station: Dictionary=cat.tables.stations[station_id]
			check(station.system_id==system_id and station.planet_type==expected.types[n],"The onward station has a different source system or planet type")
			var candidates: Array=vectors.filter(func(row):return row.station==station_id)
			if candidates.size()!=1:check(false,"Missing independent planet vector");return
			var vector: Dictionary=candidates[0]
			check(vector.type==station.planet_type,"Independent vector used a different catalogue planet type")
			var planet:=Planet.new();var arranged:=planet.arrange(station_id,int(station.planet_type),expected.stations,false,bindings.mido_travel.local_arrival_environment)
			if arranged.is_empty():check(false,planet.error);return
			check(arranged.entries.map(func(row):return row.angular_slot)==vector.slots.map(func(value):return int(value)),"Onward planet angular draw order changed")
			check(arranged.entries[arranged.selected_index].scale==float(vector.size_units)/65536.0 and arranged.random_state.state==int(vector.random_state),"Onward planet size or random stream changed")
			check(arranged.entries.size()==expected.stations.size()+1,"Onward system omitted a planet or its sun")
			var textures:=[int(planet_rules.sun_textures[system.sky_index]),int(planet_rules.near_textures[station.planet_type])]
			for other in expected.stations:textures.append(int(planet_rules.far_textures[cat.tables.stations[other].planet_type]))
			for id in textures:
				var path: String=bindings.resolve_texture(id,"high")
				check(not path.is_empty() and library.manifest.files.has(path),"Onward world lacks its original planet or sun texture")
			var meshes:=[]
			for base in bindings.mido_travel.exterior_model_bases:
				var id:=int(base)+station_id;var path: String=bindings.resolve(id,"mesh")
				var reader:=MeshReader.new();var model:=reader.decode(library.read_resource(path,reader.MAX_BYTES))
				if model.is_empty():check(false,reader.error+library.error);return
				check(model.version==4 and not model.surfaces.is_empty(),"Onward station exterior uses an unsupported model")
				for surface in model.surfaces:check(Exterior.initial_transform_supported(surface,meshes.size()==2),"Onward station exterior needs unsupported transform animation")
				meshes.append(id)
			var collision:=Volumes.new()
			var shapes:=collision.decode(library.read_resource(bindings.station_exterior.collision_resource,collision.MAX_BYTES),station_id,int(bindings.station_exterior.collision_record_limit),float(bindings.mido_travel.collision_sphere_scale))
			check(not shapes.is_empty() and not shapes.get("shapes",shapes.get("boxes",[])).is_empty(),"Onward station lacks original docking volumes")
			var hangar:=bindings.resolve_hangar(station_id,cat)
			check(not hangar.is_empty() and hangar.row==0,"Onward station lost its original Terran hangar")
			var gate:=Gate.new()
			if not gate.configure(bindings,cat,station_id):check(false,gate.error);return
			var layout:=gate.snapshot()
			check(layout.system_id==system_id and layout.gate_type==0 and layout.gate_station_id==expected.gate,"Onward gate uses a different system type")
			check(layout.objects.any(func(row):return row.index==1 and row.interactive)==(station_id==expected.gate),"Interactive gate appeared at the wrong station")
			check(gate.arrival_position() is Vector3,"Onward station lacks its incoming gate position")
			for object in layout.objects:
				for path in object.models.values():check(library.manifest.files.has(path),"An original onward gate model is absent")
			report.locations.append({"station_id":station_id,"system_id":system_id,"planet_type":station.planet_type,"sky_index":system.sky_index,"exterior_ids":meshes,"hangar_row":hangar.row,"gate_type":layout.gate_type,"gate_position":str(gate.arrival_position()),"planet_vector":vector})
	var output:=OS.get_environment("GOF2_KAPPA_WORLD_REPORT")
	if not output.is_empty():
		check(output.is_absolute_path() and not output.begins_with(ProjectSettings.globalize_path("res://")),"Keep scenery research outside the engine")
		if failures:return
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file==null:check(false,"Cannot write private world composition report");return
		file.store_string(JSON.stringify(report,"  ")+"\n")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

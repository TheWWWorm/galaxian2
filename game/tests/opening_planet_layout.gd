extends SceneTree
const Layout = preload("res://src/simulation/opening_planet_layout.gd")
const Definitions = preload("res://src/content/planet_resource_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const AEM = preload("res://src/content/aem.gd")
const Visuals = preload("res://src/content/visual_library.gd")
var failures:=0

func _initialize() -> void:
	var layout:=Layout.new()
	var vectors: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/opening_planet_layout_vectors.json"))
	for row in vectors:
		var ids:=[]
		for id in row.station_ids:ids.append(int(id))
		var got:=layout.arrange(int(row.station_id),0,ids)
		check(not got.is_empty(),layout.error)
		if got.is_empty():continue
		check(got.selected_index==int(row.selected_index) and got.random_state.state==int(row.random_state),"Planet selection or random continuation changed")
		check(got.entries.size()==row.entries.size(),"Wrong planet count")
		for i in got.entries.size():
			var actual: Dictionary=got.entries[i];var expected: Dictionary=row.entries[i]
			check(actual.station_id==int(expected.station_id) and actual.angular_slot==int(expected.angular_slot),"Wrong ordered planet slot")
			check(actual.scale==expected.scale and actual.random_state.state==int(expected.random_state),"Wrong planet scale or draw order")
			for axis in 3:
				check(actual.angles[axis]==PackedFloat32Array([expected.angles[axis]])[0] and actual.visual_angles[axis]==PackedFloat32Array([expected.visual_angles[axis]])[0],"Wrong placement versus visual angle")
				check(absf(actual.origin[axis]-expected.origin[axis])<0.005,"Wrong planet position or displacement")
			check(absf(actual.basis.determinant()-1.0)<0.000002,"Planet visual rotation lost orthonormal basis")
		check(got.sun.random_state==got.entries[0].random_state,"Planet owner redrew the sun stream")
		check(layout.arrange(int(row.station_id),0,ids)==got,"Planet layout is nondeterministic")
	var valid:=layout.arrange(3,0,[1,2,3,4,5])
	for ids in [null,[],[1,2], [3,3],[3,2], [3.0],[-2147483649,3],[3,2147483648],range(1,25)]:
		check(layout.arrange(3,0,ids).is_empty() and not layout.error.is_empty(),"Invalid or exhausted membership accepted")
	for value in [null,3.0,"3",2147483648]:check(layout.arrange(value,0,[1,2,3]).is_empty(),"Invalid station accepted")
	for value in [null,0.0,1,18,-1]:check(layout.arrange(3,value,[1,2,3]).is_empty(),"Unsupported planet type accepted")
	check(layout.arrange(3,0,[1,2,3,4,5])==valid and layout.error.is_empty(),"Failed construction changed later layout")
	var args:=OS.get_cmdline_user_args()
	for start in range(0,args.size(),3):
		var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new();var visuals:=Visuals.new()
		check(library.open(args[start]),library.error)
		check(catalogues.open(library),catalogues.error)
		check(bindings.open(args[start+1],library.manifest),bindings.error)
		check(visuals.open(args[start+2],library.manifest),visuals.error)
		if bindings.opening_sky.get("planet_resources",{}).is_empty():
			check(layout.for_opening(bindings,catalogues,library.manifest.content_id).is_empty(),"Legacy pack supplied unsupported planet resources")
			print("Opening planets unavailable in legacy ",library.manifest.profile.edition);continue
		var got:=layout.for_opening(bindings,catalogues,library.manifest.content_id)
		check(not got.is_empty(),layout.error)
		if got.is_empty():continue
		check(got.entries.size()==catalogues.tables.systems[got.system_id].station_ids.size()+1,"Source planet membership was lost")
		check(got.entries[got.selected_index].station_id==got.station_id and got.entries[got.selected_index].current,"Wrong current station planet")
		var original: Dictionary=bindings.opening_sky.planet_resources
		check(got.entries[got.selected_index].texture_id==int(original.opening_texture_id),"Opening override lost to ordinary texture table")
		for entry in got.entries:
			var image: Image=visuals.load_image(entry.texture_path)
			check(image!=null,visuals.error)
			if entry.kind=="planet" and not entry.current:
				check(entry.texture_id==int(original.far_textures[catalogues.tables.stations[entry.station_id].planet_type]),"Distant planet selected near texture")
		var low:=layout.for_opening(bindings,catalogues,library.manifest.content_id,"low")
		check(not low.is_empty(),layout.error)
		if not low.is_empty():
			for i in got.entries.size():
				var a: Dictionary=got.entries[i].duplicate();var b: Dictionary=low.entries[i].duplicate()
				a.erase("texture_path");b.erase("texture_path")
				check(a==b,"Texture quality changed planet placement or content")
		var reader:=AEM.new();var decoded:=reader.decode(library.read_resource(got.mesh_path,AEM.MAX_BYTES))
		check(not decoded.is_empty(),reader.error)
		check(int(decoded.get("keyframes",-1))==0,"Unexpected animated planet model")
		var mesh_bounds:=AABB()
		var first_vertex:=true
		for surface in decoded.get("surfaces",[]):
			for position in surface.positions:
				if first_vertex:mesh_bounds=AABB(position,Vector3.ZERO);first_vertex=false
				else:mesh_bounds=mesh_bounds.expand(position)
		print("Opening planet mesh: ",library.manifest.profile.edition," vertices=",decoded.get("vertices")," bounds=",mesh_bounds)
		var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[start+1]+"/bindings.json"))
		check(Definitions.validate(original,int(header.source_executable_bytes),header.architecture).is_empty(),"Valid resource provenance rejected")
		for bad in ["id","count","overlap","extent"]:
			var copy:=original.duplicate(true)
			match bad:
				"id":copy.mesh_id=65534
				"count":copy.far_textures.pop_back()
				"overlap":copy.provenance.far_textures.offset=copy.provenance.near_textures.offset
				"extent":copy.provenance.mesh.bytes=1
			check(not Definitions.validate(copy,int(header.source_executable_bytes),header.architecture).is_empty(),"Malformed planet declarations accepted: "+bad)
		var station: Dictionary=catalogues.tables.stations[got.station_id]
		station.planet_type=99
		check(layout.for_opening(bindings,catalogues,library.manifest.content_id).is_empty(),"Unsupported catalogue planet type accepted")
		station.planet_type=0
		bindings.opening_sky.planet_resources={}
		check(layout.for_opening(bindings,catalogues,library.manifest.content_id).is_empty(),"Missing capability accepted")
		bindings.opening_sky.planet_resources=original
		check(layout.for_opening(bindings,catalogues,"foreign").is_empty(),"Foreign base accepted")
		check(layout.for_opening(bindings,catalogues,library.manifest.content_id)==got,"Failure contaminated source planet layout")
		print("Opening planet layout: ",library.manifest.profile.edition," ",JSON.stringify(got))
	print("Opening planet layout: ",vectors.size()," mathematical vectors; ",failures," failures")
	quit(0 if failures==0 else 1)

func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)

extends SceneTree
const Sun = preload("res://src/simulation/sun_placement.gd")
const SceneryOrientation = preload("res://src/simulation/scenery_orientation.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/sun_placement_vectors.json"))
	var sun := Sun.new()
	for row in rows:
		var value := sun.for_station(int(row.station),int(row.planet_type))
		check(not value.is_empty(),sun.error)
		if value.is_empty(): continue
		check(value.angular_slot==int(row.angular_slot),"Wrong station sun slot")
		check(value.random_state.state==int(row.random_state),"Wrong random draw count or station seed")
		for axis in 3:
			check(value.angles[axis]==PackedFloat32Array([row.angles[axis]])[0],"Wrong float32 sun angle")
			check(absf(value.direction_to_sun[axis]-row.direction_to_sun[axis])<0.000001,"Wrong sun direction or rotation order")
			check(absf(value.origin[axis]-row.origin[axis])<0.004,"Wrong signed sun placement or distance")
		check(absf(value.origin.length()-20000.0)<0.004,"Sun placement changed its source distance")
		check(value.basis.determinant()>0 and value.basis.is_equal_approx(value.basis.orthonormalized()),"Sun pose changed scale or handedness")
		var repeat := sun.for_station(int(row.station),int(row.planet_type))
		check(value==repeat,"Sun placement was nondeterministic")
	var opening := sun.for_station(78,0)
	check(opening.angles!=SceneryOrientation.new().for_station(78).angles,"Sun reused the background rotation seed")
	for invalid in [null,"78",78.0,2147483648,-2147483649]:
		check(sun.for_station(invalid,0).is_empty() and not sun.error.is_empty(),"Invalid sun station accepted")
	for invalid in [null,"0",0.0,-1,2147483648]:
		check(sun.for_station(78,invalid).is_empty() and not sun.error.is_empty(),"Invalid planet type accepted")
	check(sun.for_station(78,0)==opening and sun.error.is_empty(),"Invalid call contaminated the next placement")
	for directory in OS.get_cmdline_user_args():
		var library := Library.new();var catalogues := Catalogues.new()
		check(library.open(directory),library.error)
		check(catalogues.open(library),catalogues.error)
		if catalogues.tables.is_empty(): continue
		for station in catalogues.tables.stations:
			check(station.planet_type==station.fields[3],"Planet type lost its catalogue binding")
			check(not sun.for_station(station.id,station.planet_type).is_empty(),sun.error)
		check(catalogues.tables.stations[78].planet_type==0,"Opening planet type differs from source fixture")
		print("Sun placement catalogue: ",library.manifest.profile.edition," ",catalogues.tables.stations.size()," station records")
	print("Sun placement: %d independent vectors, %d failures" % [rows.size(),failures])
	quit(0 if failures==0 else 1)

func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)

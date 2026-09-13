extends SceneTree
const Orientation = preload("res://src/simulation/scenery_orientation.gd")
var failures := 0

func _initialize() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenery_orientation_vectors.json"))
	var orientation := Orientation.new()
	for row in rows:
		var station: Variant = null if row.station==null else int(row.station)
		var result := orientation.for_station(station)
		check(not result.is_empty(),orientation.error)
		if result.is_empty(): continue
		for axis in 3:
			check(result.angles[axis]==PackedFloat32Array([row.angles[axis]])[0],"Scenery angle mismatch station=%s axis=%d actual=%.15f expected=%.15f" % [station,axis,result.angles[axis],row.angles[axis]])
			for column in 3:
				check(absf(result.basis[column][axis]-row.basis_rows[axis][column])<0.000001,"Scenery XYZ composition differs from independent matrix equation")
		check(result.basis.determinant()>0 and result.basis.is_equal_approx(result.basis.orthonormalized()),"Scenery introduced reflection or scale")
		check(orientation.for_station(station,true).basis==Basis.IDENTITY,"Suppressed rotation retained station orientation")
	for invalid in ["78",78.0,2147483648,-2147483649]:
		check(orientation.for_station(invalid).is_empty(),"Invalid scenery station accepted")
	check(orientation.for_station(null).angles!=orientation.for_station(-1).angles,"Absent station was conflated with record ID -1")
	print("Scenery orientation: %d independent station/basis vectors verified" % rows.size())
	quit(0 if failures==0 else 1)

func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)

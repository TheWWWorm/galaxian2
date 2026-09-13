extends RefCounted
## Independently designed deterministic scenery orientation. Both supplied editions
## use the same 48-bit generator and three 16-bit angles with float32 rounding.
const Generator = preload("res://src/simulation/seeded_random.gd")
const SOURCE_TAU := 6.2831854820251465
var error := ""

func for_station(station_id: Variant, suppressed := false) -> Dictionary:
	error=""
	if station_id!=null and (not station_id is int or station_id<-2147483648 or station_id>2147483647):
		error="Scenery requires a signed 32-bit station ID or an explicitly absent station"
		return {}
	var angles := Vector3.ZERO
	if not suppressed:
		var generator := Generator.new()
		# An absent station differs from an actual station record whose ID is -1.
		var seed_value := -1 if station_id==null else ((int(station_id)*2+2147483648)&0xffffffff)-2147483648
		generator.seed_from(seed_value)
		for axis in 3:
			angles[axis]=PackedFloat32Array([float(generator.next_int(65536))/65536.0*SOURCE_TAU])[0]
	return {"angles":angles,"basis":Basis.from_euler(angles,EULER_ORDER_XYZ)}

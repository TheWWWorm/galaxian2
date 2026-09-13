extends RefCounted
## Native placement of the first sun in station scenery. Other planets, sun
## appearance and renderer lighting are separate from this deterministic pose.
const Generator = preload("res://src/simulation/seeded_random.gd")
const SOURCE_TAU := 6.2831854820251465
const DISTANCE := 20000.0
var error := ""

func for_station(station_id: Variant, planet_type: Variant) -> Dictionary:
	error=""
	if not station_id is int or station_id<-2147483648 or station_id>2147483647:
		return reject("Sun placement requires a signed 32-bit station ID")
	if not planet_type is int or planet_type<0 or planet_type>2147483647:
		return reject("Sun placement requires a nonnegative station planet type")
	var generator := Generator.new()
	var seed_value := ((int(station_id)*300+2147483648)&0xffffffff)-2147483648
	generator.seed_from(seed_value)
	# Every station consumes the first draw, including fixed angular slots. This
	# keeps the following elevation draw independent of the planet-type branch.
	var slot := generator.next_int(14)+5
	if planet_type in [9,13,14,18,20]: slot=6
	elif planet_type==21: slot=4
	elif planet_type==22: slot=16
	var angles := Vector3(angle(generator.next_int(4096)-2048),angle(slot*2730),0)
	var rotation := Basis.from_euler(angles,EULER_ORDER_XYZ)
	# The source moves along negative model Z, then normalizes that same vector
	# for its light direction. This is a direction TO the sun, not light travel.
	var direction := -rotation.z.normalized()
	return {"angular_slot":slot,"angles":angles,"basis":rotation,
		"direction_to_sun":direction,"origin":direction*DISTANCE,
		"random_state":generator.snapshot()}

func angle(units: int) -> float:
	return PackedFloat32Array([float(units)/65536.0*SOURCE_TAU])[0]

func reject(message: String) -> Dictionary:
	error=message
	return {}

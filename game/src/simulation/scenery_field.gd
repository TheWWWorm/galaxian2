extends RefCounted
## Native initial scenery construction. The world owner supplies the recovered
## center and a separately seeded construction stream; station count RNG is not
## reused here. Source resource/ore identities come from the active binding pack.
const Population = preload("res://src/simulation/scenery_population.gd")
const Ores = preload("res://src/simulation/scenery_ores.gd")
const Generator = preload("res://src/simulation/seeded_random.gd")
const Orientation = preload("res://src/simulation/scenery_orientation.gd")
const MAX_CANDIDATES := 100000
const LARGE_COUNT_BASE := 2
const LARGE_COUNT_BOUND := 8
const LARGE_WIDTH := 60000
const SMALL_WIDTH := 100000
const DISTANCE_THRESHOLD := 8000
var error := ""
var _identity := {}
var _models: Array = []
var _count := 0
var _override_item_id := -1
var _system_id := -1
var _station_id := -1
var _location_match := false
var _ores: RefCounted

func clear() -> void:
	error="";_identity={};_models=[];_count=0;_override_item_id=-1;_system_id=-1;_station_id=-1;_location_match=false;_ores=null

func configure(bindings: RefCounted, catalogues: RefCounted, station_id: Variant, location_match: Variant, special_ore_flag: Variant, campaign_cursor: Variant) -> bool:
	clear()
	var ores := Ores.new();var population := Population.new()
	if not ores.configure(bindings,catalogues,station_id,location_match,special_ore_flag,campaign_cursor):return reject(ores.error)
	if not population.configure(bindings):return reject(population.error)
	var count_state: Dictionary = population.for_station(station_id)
	if count_state.is_empty():return reject(population.error)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_models=bindings.scenery_resources.model_ids.duplicate()
	_override_item_id=int(bindings.scenery_resources.override_item_id)
	_count=count_state.count;_system_id=int(catalogues.tables.stations[station_id].system_id)
	_station_id=station_id;_location_match=location_match;_ores=ores
	return true

func generate(center: Variant, random_state: Variant) -> Dictionary:
	error=""
	if _identity.is_empty():return fail("Configure scenery construction first")
	if not center is Vector3 or not center.is_finite():return fail("Scenery requires an explicit finite source center")
	if maxf(absf(center.x),maxf(absf(center.y),absf(center.z)))>100000000.0:return fail("Scenery center exceeds supported source precision")
	var random := Generator.new()
	if not random.restore(random_state):return fail(random.error)
	var large_count := LARGE_COUNT_BASE+random.next_int(LARGE_COUNT_BOUND)
	var rows := []
	var cursor := 0
	for index in _count:
		var ore: Dictionary = _ores.choose(random.snapshot(),cursor)
		if ore.is_empty():return fail(_ores.error)
		random.restore(ore.random_state);cursor=ore.cursor
		var large := index<large_count
		var width := LARGE_WIDTH if large else SMALL_WIDTH
		var candidate := Vector3.ZERO
		var accepted := false
		var attempts := 0
		for attempt in MAX_CANDIDATES:
			attempts=attempt+1
			for axis in 3:candidate[axis]=f32(f32(center[axis]-float(width >> 1))+float(random.next_int(width)))
			accepted=index==0 or not large
			if not accepted:
				# Source accepts a candidate far enough from ANY predecessor,
				# not a candidate separated from every existing object.
				for previous in rows:
					if source_distance(candidate,previous.position)>DISTANCE_THRESHOLD:
						accepted=true;break
			if accepted:break
		if not accepted:return fail("Scenery placement exceeded the work limit; no field committed")
		var scale_value := f32(float(random.next_int(100 if large else 70)+(120 if large else 30))*f32(0.01))
		var size_value := 4 if scale_value<0.4 else 5 if scale_value<0.7 else 6 if scale_value<0.92 else 7
		if scale_value>=0.92 and random.next_int(2)!=0:size_value=random.next_int(3)+4
		# The source consumes these three axis values before initial Euler angles,
		# even though their later use is outside this construction component.
		var construction_axis := Vector3.ZERO
		for axis in 3:construction_axis[axis]=f32(float(random.next_int(8192)-4096)*0.000244140625)
		var angles := Vector3.ZERO
		for axis in 3:angles[axis]=f32(f32(float(random.next_int(100))*f32(0.01))*Orientation.SOURCE_TAU)
		var spin_direction := Vector3.ZERO
		for axis in 3:spin_direction[axis]=float(random.next_int(3)-1)
		var spin_factor := f32(1.0-minf(maxf(f32(0.9),scale_value),1.0))
		var spin := Vector3(f32(spin_direction.x*spin_factor),f32(spin_direction.y*spin_factor),f32(spin_direction.z*spin_factor))
		var model_variant := 2 if _system_id==22 else 0
		if _location_match:model_variant=1
		if ore.item_id==_override_item_id:model_variant=3
		rows.append({"index":index,"item_id":ore.item_id,"model_variant":model_variant,"model_id":int(_models[model_variant]),
			"position":candidate,"scale":scale_value,"angles":angles,"basis":Basis.from_euler(angles,EULER_ORDER_XYZ),
			"large":large,"source_size_value":size_value,"construction_axis":construction_axis,"spin":spin,
			"position_attempts":attempts,"ore_draws":ore.draws})
	var result := _identity.duplicate()
	result.station_id=_station_id;result.system_id=_system_id;result.center=center
	result.large_count=large_count;result.objects=rows;result.ore_cursor=cursor;result.random_state=random.snapshot()
	return result

static func source_distance(a: Vector3,b: Vector3) -> int:
	var delta := a-b
	var squared := f32(f32(f32(delta.x*delta.x)+f32(delta.y*delta.y))+f32(delta.z*delta.z))
	return int(f32(sqrt(squared)))

static func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

func reject(message: String) -> bool:
	error=message;return false

func fail(message: String) -> Dictionary:
	error=message;return {}

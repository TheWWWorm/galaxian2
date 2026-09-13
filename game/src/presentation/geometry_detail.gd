extends RefCounted
## Shared native geometry selection. Zero maximum disables the source distance
## cull; the final distance still selects a mesh level, never visibility.
const Numbers = preload("res://src/content/opening_definitions.gd")
var error := ""
var _distances := []
var _count := 0
var _maximum := 0
var _boundaries := []
var _factors := []

func configure(distances: Array, count: int, maximum_distance: int, detail_boundaries: Array, squared_distance_factors: Array) -> bool:
	clear()
	if distances.is_empty() or distances.size()>32 or count<0 or count>distances.size():return reject("Invalid geometry detail level count")
	var previous := 0
	for distance in distances:
		if not Numbers.integer(distance,previous+1,1000000):return reject("Invalid geometry detail distances")
		previous=int(distance)
	if maximum_distance!=0 and (maximum_distance<=previous or maximum_distance>1000000):return reject("Invalid geometry maximum distance")
	if detail_boundaries.size()>32 or squared_distance_factors.size()!=detail_boundaries.size()+1:return reject("Invalid geometry detail bands")
	for values in [detail_boundaries,squared_distance_factors]:
		var preceding := 0.0
		for value in values:
			if not (value is float or value is int) or not is_finite(value) or value<=preceding or value>1.0:return reject("Invalid geometry detail factor or boundary")
			preceding=float(value)
	_distances=distances.duplicate();_count=count;_maximum=maximum_distance
	_boundaries=detail_boundaries.duplicate();_factors=squared_distance_factors.duplicate()
	return true

func select(distance_squared: Variant, detail: Variant) -> Dictionary:
	error=""
	if not is_configured():reject("Configure geometry detail before selecting");return {}
	if not (distance_squared is float or distance_squared is int) or not is_finite(distance_squared) or distance_squared<0 or distance_squared>9007199254740991:
		reject("Geometry detail requires a finite nonnegative squared distance");return {}
	if not (detail is float or detail is int) or not is_finite(detail) or not is_finite(single(detail)):
		reject("Geometry detail requires an explicit finite source detail input");return {}
	# Source float32 distance is truncated to uint64, then rounded back to
	# float32 for threshold comparison, including equality at detail boundaries.
	var distance_integer := int(single(distance_squared))
	if _maximum!=0 and distance_integer>=_maximum*_maximum:return {"visible":false,"level":-1}
	var band := 0
	for boundary in _boundaries:
		if single(detail)>boundary:band+=1
	var factor := float(_factors[band])
	for i in range(_count-1,-1,-1):
		var threshold := int(_distances[i])
		if single(distance_integer)>single(single(threshold*threshold)*factor):return {"visible":true,"level":i+1}
	return {"visible":true,"level":0}

func is_configured() -> bool:
	return not _distances.is_empty()

func has_alternates() -> bool:
	return is_configured() and _count>0

func clear() -> void:
	error="";_distances=[];_count=0;_maximum=0;_boundaries=[];_factors=[]

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._distances=_distances.duplicate();copy._count=_count;copy._maximum=_maximum
	copy._boundaries=_boundaries.duplicate();copy._factors=_factors.duplicate()
	return copy

static func single(value: float) -> float:
	return PackedFloat32Array([value])[0]

func reject(message: String) -> bool:
	error=message;return false

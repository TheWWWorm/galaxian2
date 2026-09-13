extends RefCounted
## Stateful sampling and world transforms for supported scenery effect surfaces.
## Drawing, material selection and bounds/culling remain the renderer's owners.
const Keys = preload("res://src/content/scenery_animation_keys.gd")
const Resources = preload("res://src/content/scenery_effect_resources.gd")
const Rotation = preload("res://src/presentation/scenery_animation_rotation.gd")
var error := ""
var _tables: Array = []
var _pivots: Array[Vector3] = []
var _state: Array = []
var _range := {}

func configure(surfaces: Variant) -> bool:
	error="";_tables=[];_pivots=[];_state=[];_range={}
	var timing := Resources.playback_range(surfaces)
	if timing.is_empty():error="Unsupported scenery animation channels or timing";return false
	for surface in surfaces:
		if not surface.get("pivot") is Vector3 or not surface.pivot.is_finite():
			error="Scenery animation requires finite source pivots";return false
	var compiler := Keys.new()
	var prepared := compiler.prepare(surfaces)
	if prepared.is_empty():error=compiler.error;return false
	_tables=prepared.surfaces;_range=timing
	for surface in surfaces:
		_pivots.append(convert_axis(surface.pivot))
		_state.append({"basis":Basis.IDENTITY,"translation":Vector3.ZERO,"color_byte":255})
	# Source loading evaluates the configured start before instances are cloned.
	if sample(timing.start_ms,Transform3D.IDENTITY).is_empty():
		_tables=[];_pivots=[];_state=[];_range={};return false
	return true

func sample(time_ms: Variant, parent: Transform3D) -> Dictionary:
	error=""
	if _tables.is_empty():return reject("Scenery animation is not configured")
	if not time_ms is int or time_ms<0:return reject("Scenery animation time must be a nonnegative integer in milliseconds")
	if not parent.is_finite():return reject("Scenery animation parent must be finite")
	var next := _state.duplicate(true)
	var output := []
	for surface in _tables.size():
		var table: Dictionary=_tables[surface]
		if table.times.is_empty():
			output.append({"animated":false,"pose":parent});continue
		var times: PackedInt32Array=table.times
		var start: int=_range.start_ms if _range.start_ms<=times[-1] else 0
		var at := mini(maxi(time_ms,start),times[-1])
		var index := lower_bound(times,at)
		# The first-record branch changes only source UV state. It leaves the
		# geometry matrix and packed color intact, including after a rewind.
		if index>0 and not update_row(next[surface],table.values,index,Keys.ratio(at-times[index-1],times[index]-times[index-1])):
			return {}
		var row: Dictionary=next[surface]
		var world := multiply(parent,Transform3D(Basis.IDENTITY,row.translation))
		world=multiply(world,Transform3D(Basis.IDENTITY,_pivots[surface]))
		world=multiply(world,Transform3D(row.basis,Vector3.ZERO))
		world=multiply(world,Transform3D(Basis.IDENTITY,-_pivots[surface]))
		if not world.is_finite():return reject("Scenery animation world transform exceeds source precision")
		output.append({"animated":true,"pose":world,"color_byte":row.color_byte})
	_state=next
	return {"surfaces":output}

func update_row(row: Dictionary, values: PackedFloat32Array, index: int, weight: float) -> bool:
	var a := (index-1)*Keys.WIDTH
	var b := index*Keys.WIDTH
	var rotation := Rotation.sample(vector_at(values,a+3),vector_at(values,b+3),weight)
	if rotation.has("error"):error=rotation.error;return false
	var basis: Basis=rotation.basis
	basis=Basis(convert_axis(basis.x),convert_axis(basis.z),-convert_axis(basis.y))
	var translation := Vector3.ZERO
	for axis in 3:
		var scale := Keys.blend(values[a+6+axis],values[b+6+axis],weight)
		# Scale the converted local columns. Basis.scaled() scales world axes.
		for component in 3:basis[axis][component]=Keys.single(basis[axis][component]*scale)
		translation[axis]=Keys.blend(values[a+axis],values[b+axis],weight)
	var scalar := Keys.blend(values[a+9],values[b+9],weight)
	var color := Keys.single(scalar*255.0)
	if not basis.is_finite() or not translation.is_finite() or not is_finite(color) or color<-2147483648.0 or color>=2147483648.0:
		error="Scenery animation values exceed source precision";return false
	row.basis=basis;row.translation=translation
	# All four source color channels use this byte. Material/parent modulation
	# is separate; do not clamp the authored scalar to an opacity range here.
	row.color_byte=int(color)&255
	return true

func snapshot() -> Dictionary:
	return {} if _tables.is_empty() else {"range":_range.duplicate(),"surfaces":_state.duplicate(true)}

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	# Compiled tables and pivots are private and immutable after configuration.
	copy._tables=_tables;copy._pivots=_pivots
	copy._state=_state.duplicate(true);copy._range=_range.duplicate()
	return copy

static func lower_bound(times: PackedInt32Array, value: int) -> int:
	var low := 0;var high := times.size()
	while low<high:
		var middle := int((low+high)/2)
		if times[middle]<value:low=middle+1
		else:high=middle
	return low

static func convert_axis(value: Vector3) -> Vector3:
	return Vector3(value.x,value.z,-value.y)

static func vector_at(values: PackedFloat32Array, start: int) -> Vector3:
	return Vector3(values[start],values[start+1],values[start+2])

static func multiply(left: Transform3D, right: Transform3D) -> Transform3D:
	# Explicit float32 products and sums preserve the source affine contract,
	# including the four successive pivot/parent products used when drawing.
	var result := Transform3D()
	for row in 3:
		for column in 4:
			var value := 0.0
			for term in 3:
				var component: float=right.basis[column][term] if column<3 else right.origin[term]
				var product := Keys.single(left.basis[term][row]*component)
				value=product if term==0 else Keys.single(value+product)
			if column<3:result.basis[column][row]=value
			else:result.origin[row]=Keys.single(value+left.origin[row])
	return result

func reject(message: String) -> Dictionary:
	error=message;return {}

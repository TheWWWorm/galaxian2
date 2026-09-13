extends RefCounted
## Rotation math for the verified scenery effect key tables, in source axes.
## Quaternion components here use the source convention. Always use to_basis()
## to turn them into a Godot Basis; a Godot Quaternion constructor differs.
const Keys = preload("res://src/content/scenery_animation_keys.gd")

static func sample(left: Vector3, right: Vector3, weight: Variant) -> Dictionary:
	if not valid_weight(weight):return {"error":"Scenery rotation weight must be finite and within [0, 1]"}
	var a := from_angles(left)
	var b := from_angles(right)
	if a.is_empty() or b.is_empty():return {"error":"Scenery rotation angles must be finite"}
	var mixed := blend(a,b,float(weight))
	if mixed.is_empty():return {"error":"Scenery rotation blend is singular or exceeds source precision"}
	var result := to_basis(mixed)
	if not result.has("error"):result.components=mixed
	return result

static func from_angles(angles: Vector3) -> PackedFloat32Array:
	if not angles.is_finite():return PackedFloat32Array()
	var sine := PackedFloat32Array()
	var cosine := PackedFloat32Array()
	for axis in 3:
		var half := Keys.single(angles[axis]*0.5)
		# Native trig with float32 inputs/outputs. Original platform libm's
		# final-bit behavior is not a cross-platform fidelity guarantee.
		sine.append(sin(half));cosine.append(cos(half))
	var sx: float=sine[0];var sy: float=sine[1];var sz: float=sine[2]
	var cx: float=cosine[0];var cy: float=cosine[1];var cz: float=cosine[2]
	# Conjugate of the usual Z * Y * X Euler quaternion. Round each product
	# separately, preserving the source's handedness and arithmetic precision.
	return PackedFloat32Array([
		product(sz,sy,cx)-product(cz,cy,sx),
		product(-cz,sy,cx)-product(sz,cy,sx),
		product(cz,sy,sx)-product(sz,cy,cx),
		product(sz,sy,sx)+product(cz,cy,cx)])

static func blend(left: PackedFloat32Array, right: PackedFloat32Array, weight: Variant) -> PackedFloat32Array:
	if not valid_components(left) or not valid_components(right) or not valid_weight(weight):return PackedFloat32Array()
	var mixed := PackedFloat32Array()
	var t := Keys.single(float(weight))
	for field in 4:mixed.append(Keys.blend(left[field],right[field],t))
	var squared := PackedFloat32Array()
	for value in mixed:squared.append(value*value)
	var length := Keys.single(sqrt(Keys.single(Keys.single(Keys.single(squared[0]+squared[1])+squared[2])+squared[3])))
	if not is_finite(length) or length==0.0:return PackedFloat32Array()
	# No shortest-hemisphere sign flip and no artificial fallback at zero.
	for field in 4:mixed[field]=mixed[field]/length
	return mixed if valid_components(mixed) else PackedFloat32Array()

static func to_basis(components: PackedFloat32Array) -> Dictionary:
	if not valid_components(components):return {"error":"Scenery rotation requires four finite quaternion components"}
	var squares := PackedFloat32Array()
	for value in components:squares.append(value*value)
	# Products are float32; sums, reciprocal and matrix expressions are double.
	var x2: float=squares[0];var y2: float=squares[1];var z2: float=squares[2];var w2: float=squares[3]
	var norm := ((x2+y2)+z2)+w2
	if not is_finite(norm) or norm==0.0:return {"error":"Scenery rotation matrix is singular or exceeds source precision"}
	var inverse := 1.0/norm
	var x: float=components[0];var y: float=components[1];var z: float=components[2];var w: float=components[3]
	var xy := Keys.single(x*y);var zw := Keys.single(z*w)
	var xz := Keys.single(x*z);var yw := Keys.single(y*w)
	var yz := Keys.single(y*z);var xw := Keys.single(x*w)
	# Source matrix rows become Godot Basis columns. Translation is separate.
	var result := Basis(
		Vector3((((x2-y2)-z2)+w2)*inverse,((xy-zw)*2.0)*inverse,((xz+yw)*2.0)*inverse),
		Vector3(((xy+zw)*2.0)*inverse,(((-x2+y2)-z2)+w2)*inverse,((yz-xw)*2.0)*inverse),
		Vector3(((xz-yw)*2.0)*inverse,((yz+xw)*2.0)*inverse,(((-x2-y2)+z2)+w2)*inverse))
	if not result.is_finite():return {"error":"Scenery rotation matrix exceeds source precision"}
	return {"basis":result}

static func product(a: float, b: float, c: float) -> float:
	return Keys.single(Keys.single(a*b)*c)

static func valid_components(value: PackedFloat32Array) -> bool:
	if value.size()!=4:return false
	for component in value:
		if not is_finite(component):return false
	return true

static func valid_weight(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value>=0.0 and value<=1.0

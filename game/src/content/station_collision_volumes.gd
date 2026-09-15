extends RefCounted
## Bounded reader for authored station and wreck collision records. Other records are
## skipped by their stored extent. Sphere support requires a verified scale.
const MAX_BYTES := 1024 * 1024
const Vectors=preload("res://src/simulation/source_vectors.gd")
var error := ""

func decode(bytes: PackedByteArray, station_id: int, record_limit: int, sphere_scale:=0.0, box_scale:=1.0) -> Dictionary:
	error=""
	if bytes.is_empty() or bytes.size()>MAX_BYTES or station_id<0 or record_limit<1 or record_limit>4096:return reject("Invalid station collision input")
	if not is_finite(sphere_scale) or sphere_scale<0 or sphere_scale>1:return reject("Invalid station sphere scale")
	if not is_finite(box_scale) or box_scale<=0 or box_scale>2:return reject("Invalid collision box scale")
	var offset:=0;var seen:={};var selected:={}
	while offset<bytes.size():
		if seen.size()>=record_limit or bytes.size()-offset<12:return reject("Truncated or excessive station collision records")
		var id:=bytes.decode_s32(offset);var count:=bytes.decode_s32(offset+4)
		if id<0 or seen.has(id) or count<0 or count>(bytes.size()-offset-12)/4:return reject("Invalid station collision record extent or duplicate ID")
		seen[id]=true
		var end:=offset+12+count*4
		if id==station_id:
			var shape_count:=bytes.decode_s32(offset+8)
			if shape_count<1 or shape_count>count/5:return reject("Unsupported station collision shape layout")
			var boxes:=[];var shapes:=[];var spheres:=[];var start:=offset+12
			for i in shape_count:
				if end-start<4:return reject("Truncated station collision shape")
				var kind:=bytes.decode_s32(start)
				if kind not in [0,1] or (kind==0 and sphere_scale==0):return reject("Unsupported station collision shape kind")
				var size:=28 if kind==1 else 20
				if end-start<size:return reject("Truncated station collision shape")
				# The station constructor maps source coordinates and takes absolute
				# half extents. Box volumes are already in world axes.
				var center:=Vector3(-float(bytes.decode_s32(start+4)),bytes.decode_s32(start+12),bytes.decode_s32(start+8))
				if kind==1:
					var half:=Vector3(absf(bytes.decode_s32(start+16)),absf(bytes.decode_s32(start+24)),absf(bytes.decode_s32(start+20)))
					for axis in 3:half[axis]=f32(half[axis]*box_scale)
					if half.x<=0 or half.y<=0 or half.z<=0:return reject("Empty station collision volume")
					boxes.append({"center":center,"half_extents":half})
					shapes.append({"kind":1,"center":center,"half_extents":half})
				else:
					var radius:=absf(f32(f32(bytes.decode_s32(start+16))*sphere_scale))
					if radius<=0:return reject("Empty station collision sphere")
					spheres.append({"center":center,"radius":radius})
					shapes.append({"kind":0,"center":center,"radius":radius})
				start+=size
			if start!=end:return reject("Station collision shape count does not match its extent")
			selected={"station_id":station_id,"source_offset":offset,"source_bytes":end-offset,"boxes":boxes}
			if not spheres.is_empty():selected.shapes=shapes;selected.spheres=spheres
		offset=end
	if selected.is_empty():return reject("No collision record for the current station")
	return selected

static func contains_point(point: Vector3, center: Vector3, half_extents: Vector3) -> bool:
	if not point.is_finite():return false
	for axis in 3:
		if point[axis]<=f32(center[axis]-half_extents[axis]) or point[axis]>=f32(center[axis]+half_extents[axis]):return false
	return true

static func contains_sphere(point: Vector3, center: Vector3, radius: float) -> bool:
	if not point.is_finite() or not center.is_finite() or not is_finite(radius) or radius<=0:return false
	var relative:=Vectors.added(point,-center)
	return Vectors.dot(relative,relative)<f32(radius*radius)

static func f32(value: float) -> float:return PackedFloat32Array([value])[0]

func reject(message: String) -> Dictionary:error=message;return {}

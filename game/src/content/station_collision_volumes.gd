extends RefCounted
## Bounded reader for authored station collision records. Other records are
## skipped by their stored extent; the selected station currently supports boxes.
const MAX_BYTES := 1024 * 1024
var error := ""

func decode(bytes: PackedByteArray, station_id: int, record_limit: int) -> Dictionary:
	error=""
	if bytes.is_empty() or bytes.size()>MAX_BYTES or station_id<0 or record_limit<1 or record_limit>4096:return reject("Invalid station collision input")
	var offset:=0;var seen:={};var selected:={}
	while offset<bytes.size():
		if seen.size()>=record_limit or bytes.size()-offset<12:return reject("Truncated or excessive station collision records")
		var id:=bytes.decode_s32(offset);var count:=bytes.decode_s32(offset+4)
		if id<0 or seen.has(id) or count<0 or count>(bytes.size()-offset-12)/4:return reject("Invalid station collision record extent or duplicate ID")
		seen[id]=true
		var end:=offset+12+count*4
		if id==station_id:
			var shape_count:=bytes.decode_s32(offset+8)
			if shape_count<1 or shape_count>count/7 or shape_count*7!=count:return reject("Unsupported station collision shape layout")
			var boxes:=[]
			for i in shape_count:
				var start:=offset+12+i*28
				if bytes.decode_s32(start)!=1:return reject("Unsupported station collision shape kind")
				# The station constructor maps source coordinates and takes absolute
				# half extents. Box volumes are already in world axes.
				var center:=Vector3(-float(bytes.decode_s32(start+4)),bytes.decode_s32(start+12),bytes.decode_s32(start+8))
				var half:=Vector3(absf(bytes.decode_s32(start+16)),absf(bytes.decode_s32(start+24)),absf(bytes.decode_s32(start+20)))
				if half.x<=0 or half.y<=0 or half.z<=0:return reject("Empty station collision volume")
				boxes.append({"center":center,"half_extents":half})
			selected={"station_id":station_id,"source_offset":offset,"source_bytes":end-offset,"boxes":boxes}
		offset=end
	if selected.is_empty():return reject("No collision record for the current station")
	return selected

static func contains_point(point: Vector3, center: Vector3, half_extents: Vector3) -> bool:
	if not point.is_finite():return false
	for axis in 3:
		if point[axis]<=center[axis]-half_extents[axis] or point[axis]>=center[axis]+half_extents[axis]:return false
	return true

func reject(message: String) -> Dictionary:error=message;return {}

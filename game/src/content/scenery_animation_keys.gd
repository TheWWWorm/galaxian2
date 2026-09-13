extends RefCounted
## Compile effect channels into integer-time records before frame sampling.
## This keeps the raw AEM intact and does not interpret pivots or draw materials.
const Resources = preload("res://src/content/scenery_effect_resources.gd")
const WIDTH := 10 # translation XYZ, rotation XYZ, scale XYZ, scalar fraction
const MAX_WORK := 8000000
var error := ""
var _work := 0

func prepare(surfaces: Variant) -> Dictionary:
	error="";_work=0
	if Resources.playback_range(surfaces).is_empty():
		return reject("Unsupported scenery animation channel layout or timing")
	var compiled := []
	for surface in surfaces:
		var rows := []
		for name in ["translation","rotation","scale","scalar"]:
			var group: Array = surface.tracks.get(name,[])
			var first: int = {"translation":0,"rotation":3,"scale":6,"scalar":9}[name]
			for axis in group.size():
				var track: Dictionary = group[axis]
				var width: int = track.dimensions
				var raw: PackedFloat32Array = track.keys
				for offset in range(0,raw.size(),width+1):
					var fields := []
					var values := PackedFloat32Array()
					for component in width:
						var field := first+(component if width==3 else axis)
						var value: float = raw[offset+component+1]
						if name=="translation" and group.size()==3:
							field=[0,2,1][axis]
							if axis==1:
								# Both source paths negate this axis, including its
								# zero sign (ARM subtracts from negative zero).
								value=-value
						elif name=="scalar":value=single(value/100.0)
						fields.append(field);values.append(value)
					if not insert(rows,int(raw[offset]),fields,values):return {}
		var times := PackedInt32Array()
		var values := PackedFloat32Array()
		for row in rows:
			times.append(row.time_ms);values.append_array(row.components)
		compiled.append({"times":times,"values":values})
	return {"surfaces":compiled}

func insert(rows: Array, time_ms: int, fields: Array, values: PackedFloat32Array) -> bool:
	_work+=(rows.size()+1)*WIDTH
	if _work>MAX_WORK:
		error="Scenery animation key preparation exceeded its work budget";return false
	var low := 0
	var high := rows.size()
	while low<high:
		var middle := int((low+high)/2)
		if rows[middle].time_ms<time_ms:low=middle+1
		else:high=middle
	var index := low
	if index==rows.size() or rows[index].time_ms!=time_ms:
		var row := {"time_ms":time_ms,"mask":0,"components":PackedFloat32Array([0,0,0,0,0,0,1,1,1,1])}
		if index>0:
			if index==rows.size():
				row.components=rows[index-1].components.duplicate()
				row.mask=rows[index-1].mask
			else:
				var weight := ratio(time_ms-rows[index-1].time_ms,rows[index].time_ms-rows[index-1].time_ms)
				for field in WIDTH:
					row.components[field]=blend(rows[index-1].components[field],rows[index].components[field],weight)
		rows.insert(index,row)
	var target: Dictionary = rows[index]
	for offset in fields.size():
		target.mask|=1<<int(fields[offset])
		target.components[fields[offset]]=values[offset]
	# Earlier gaps use the immediately preceding record, including its newly
	# filled value. The first record keeps its initial/default channel value.
	for before in range(1,index):
		var row: Dictionary = rows[before]
		var previous: Dictionary = rows[before-1]
		var weight := single(1.0-ratio(time_ms-row.time_ms,time_ms-previous.time_ms))
		for field in WIDTH:
			if target.mask&(1<<field) and not row.mask&(1<<field):
				row.components[field]=blend(previous.components[field],target.components[field],weight)
		row.mask|=target.mask
	# Later unspecified channels carry the current value without becoming
	# authored/filled endpoints; a later source key can still replace them.
	for after in range(index+1,rows.size()):
		var row: Dictionary = rows[after]
		for field in WIDTH:
			if target.mask&(1<<field) and not row.mask&(1<<field):
				row.components[field]=target.components[field]
	for row in rows:
		for value in row.components:
			if not is_finite(value):
				error="Scenery animation key arithmetic exceeds source precision";return false
	return true

static func ratio(numerator: int, denominator: int) -> float:
	return single(single(float(numerator))/single(float(denominator)))

static func blend(left: float, right: float, weight: float) -> float:
	return single(left+single(weight*single(right-left)))

static func single(value: float) -> float:
	return PackedFloat32Array([value])[0]

func reject(message: String) -> Dictionary:
	error=message;return {}

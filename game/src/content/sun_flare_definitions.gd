extends RefCounted
const Numbers=preload("res://src/content/opening_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	if data.get("scope")!="ordinary_sun_flares":return false
	var ids: Variant=data.get("image_ids")
	if not ids is Array or ids.size()!=3:return false
	for index in 3:
		if not Numbers.integer(ids[index],0,65533) or int(ids[index])!=int(ids[0])+index:return false
	var images: Variant=data.get("images")
	if not images is Array or images.size()!=3:return false
	for index in 3:
		var row: Variant=images[index]
		if not row is Dictionary or row.get("id")!=ids[index] or not Numbers.integer(row.get("texture_id"),0,65533) or not Numbers.integer(row.get("region"),0,65534):return false
	var types: Variant=data.get("system_types")
	if not types is Array or types.size()!=34:return false
	for value in types:
		if not Numbers.integer(value,0,5):return false
	var colors: Variant=data.get("colors")
	if not colors is Array or colors.size()!=6:return false
	for row in colors:
		if not row is Array or row.size()!=3:return false
		for value in row:
			if not Numbers.integer(value,0,255):return false
	return true

static func validate(data: Variant,executable_bytes: int,architecture: String) -> String:
	if not data is Dictionary:return "Missing sun flare declarations"
	if data.is_empty():return ""
	if not parameters(data):return "Invalid sun flare parameters"
	var sizes:={"resources":73,"system_type":36,"palette":129,"system":13,"system_id":9,"system_types":136,"palette_selectors":20} if architecture=="x86_64" else {"resources":56,"system_type":30,"palette":46,"fallback":12,"system":6,"system_id":4,"system_types":136,"red":20,"green":20,"blue":20} if architecture=="armv7" else {}
	if sizes.is_empty():return "Unsupported sun flare architecture"
	for index in 3:sizes["image_"+str(index)]=64
	var provenance: Variant=data.get("provenance")
	if not provenance is Dictionary or provenance.size()!=sizes.size():return "Invalid sun flare provenance"
	var spans:=[]
	for key in sizes:
		var row: Variant=provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes):return "Invalid sun flare extent: "+key
		var begin:=int(row.offset);var end:=begin+int(row.bytes)
		for span in spans:
			if begin<span.y and end>span.x:return "Overlapping sun flare declarations"
		spans.append(Vector2i(begin,end))
	if architecture=="armv7" and int(provenance.fallback.offset)!=int(provenance.palette.offset)+0x48:return "Unlinked sun flare palette"
	return ""

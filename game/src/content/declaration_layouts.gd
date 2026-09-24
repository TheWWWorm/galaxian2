extends RefCounted
## Validate one coherent set of imported proof extents against its source anchor.
const Fonts = preload("res://src/content/font_definitions.gd")

static func matches(provenance: Variant, origin: int, executable_bytes: int, layouts: Array) -> bool:
	if not provenance is Dictionary or provenance.is_empty():return false
	var accepted:=0
	for layout in layouts:
		if provenance.size()!=layout.size():continue
		var valid:=true
		for key in layout:
			var rule: Array=layout[key]
			var span: Variant=provenance.get(key)
			if not Fonts.extent(span,"offset","bytes",[rule[1]],executable_bytes) or int(span.offset)!=origin+int(rule[0]):
				valid=false;break
		if valid:accepted+=1
	return accepted==1

extends RefCounted
## Fresh kind-8 actors only; mission/companion disposition changes need new scope.
const Fonts = preload("res://src/content/font_definitions.gd")
const SIZES = {
	"x86_64":{"virtual_update":8,"stats_flags":29,"base_flags":8,"fresh_override":8,"kind":76,"overrides":119,"special_getter":14,"neutral_getter":14},
	"armv7":{"virtual_update":4,"stats_flags":88,"base_flags":62,"fresh_override":74,"kind":90,"overrides":124,"special_getter":6,"neutral_getter":6}}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=5 or not data.get("provenance") is Dictionary: return false
	if not (data.get("actor_kind") is int or data.get("actor_kind") is float) or data.actor_kind!=8: return false
	for key in ["initial_hostile","updated_hostile","updates_while_inactive"]:
		if not data.get(key) is bool: return false
	return not data.initial_hostile and data.updated_hostile and data.updates_while_inactive

static func validate(data: Variant, executable_bytes: int, architecture: String, initial: Dictionary) -> String:
	if not data is Dictionary: return "Missing NPC hostility declaration"
	if data.is_empty(): return ""
	if not parameters(data): return "Unsupported fresh NPC hostility parameters"
	var sizes: Dictionary=SIZES.get(architecture,{})
	if sizes.is_empty() or data.provenance.size()!=sizes.size(): return "Invalid NPC hostility provenance"
	var spans := []
	for key in sizes:
		var row: Variant=data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid NPC hostility source extent"
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for prior in spans:
			if span.x<prior.y and span.y>prior.x: return "Overlapping NPC hostility extents"
		spans.append(span)
	for key in ["guidance","flight"]:
		if data.provenance.virtual_update!=initial.get(key,{}).get("provenance",{}).get("virtual_update"): return "NPC hostility belongs to another update owner"
	var stats: Variant=initial.get("provenance",{}).get("stats_entry",{}).get("offset")
	var fresh: Variant=initial.get("primary_weapon",{}).get("provenance",{}).get("fresh_level",{}).get("offset")
	var point: Variant=initial.get("provenance",{}).get("point_geometry",{}).get("offset")
	if stats==null or fresh==null or point==null: return "NPC hostility requires fresh constructor anchors"
	if int(data.provenance.stats_flags.offset)!=int(stats)+(814 if architecture=="x86_64" else 524): return "NPC hostility statistics anchor disagrees"
	if int(data.provenance.fresh_override.offset)!=int(fresh)+(66 if architecture=="x86_64" else 0): return "NPC hostility fresh-game anchor disagrees"
	if int(data.provenance.base_flags.offset)!=int(point)-(134 if architecture=="x86_64" else 132): return "NPC hostility base-actor anchor disagrees"
	if int(data.provenance.overrides.offset)!=int(data.provenance.kind.offset)+(368 if architecture=="x86_64" else 390): return "NPC hostility update blocks are disconnected"
	return ""

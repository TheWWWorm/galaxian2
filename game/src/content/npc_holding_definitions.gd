extends RefCounted
## Fresh, suppressed opening holding state. Other dormant states are unsupported.
const Fonts = preload("res://src/content/font_definitions.gd")
const EXPECTED = {"actor_mode":5,"spatial_half_extent":50000,"initial_targeting_blocked":true,
	"selection_elapsed_ms":0,"boost_elapsed_ms":0}
const SIZES = {
	"x86_64":{"virtual_update":8,"timers":24,"range":38,"clock_step":14,"activation":82,"world_order":71,"deactivation":30,"player_suppression":14},
	"armv7":{"virtual_update":4,"timers":200,"range":36,"clock_step":32,"activation":50,"world_order":58,"deactivation":28,"player_suppression":18}}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=EXPECTED.size()+1 or not data.get("provenance") is Dictionary: return false
	for key in EXPECTED:
		var value: Variant = data.get(key)
		if EXPECTED[key] is bool:
			if not value is bool or value!=EXPECTED[key]: return false
		elif (not value is int and not value is float) or not is_finite(float(value)) or value!=EXPECTED[key]: return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening NPC holding declaration"
	if data.is_empty(): return ""
	if not parameters(data): return "Unsupported opening NPC holding parameters"
	var sizes: Dictionary = SIZES.get(architecture,{})
	if sizes.is_empty() or data.provenance.size()!=sizes.size(): return "Invalid opening NPC holding provenance"
	var spans := []
	for key in sizes:
		var row: Variant = data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid opening NPC holding extent: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping opening NPC holding extents"
		spans.append(span)
	return ""

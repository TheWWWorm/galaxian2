extends RefCounted
## Fresh opening NPC weapons; no later encounter, companion or mission variants.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=14: return false
	if data.get("actor_kind")!=8 or data.get("category")!=0 or data.get("kind")!=1 or data.get("launch_mode")!="ordinary": return false
	var ids: Variant = data.get("actor_ids")
	if not ids is Array or ids.size()!=3: return false
	for i in 3:
		if not Numbers.integer(ids[i],i,i): return false
	for key in ["item_id", "model_resource_id"]:
		if not Numbers.integer(data.get(key),0,65535): return false
	for key in ["damage", "interval_ms", "lifetime_ms"]:
		if not Numbers.integer(data.get(key),1,100000): return false
	if not Numbers.integer(data.get("projectile_capacity"),1,4096): return false
	var speed: Variant = data.get("speed_units_per_millisecond")
	if (not speed is float and not speed is int) or not is_finite(float(speed)) or speed<=0 or speed>100000: return false
	return data.get("local_muzzle")==[0.0,0.0,0.0] and data.get("provenance") is Dictionary

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening NPC weapon declaration"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid opening NPC weapon parameters"
	var sizes := {"main":180,"kind":31,"base_damage":43,"speed":10,"level_zero":77,"actor_kind":4,"player_constructor":70,"npc_owner":13,"cursor":12,"post_campaign":16,"fresh_level":11,"level_getter":12,"level_scale":4,"speed_value":4} if architecture=="x86_64" else {"main":154,"kind":22,"base_damage":24,"speed":4,"level_zero":82,"actor_kind":1,"player_constructor":72,"npc_owner":6,"cursor":6,"post_campaign":14,"fresh_level":42,"level_getter":6,"level_scale":4} if architecture=="armv7" else {}
	if sizes.is_empty() or data.provenance.size()!=sizes.size(): return "Invalid opening NPC weapon provenance"
	var spans := []
	for key in sizes:
		var row: Variant = data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid opening NPC weapon extent: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping opening NPC weapon extents"
		spans.append(span)
	return ""

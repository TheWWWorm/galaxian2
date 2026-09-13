extends RefCounted
const Audio=preload("res://src/content/weapon_audio_definitions.gd")
const CollisionBounds = preload("res://src/content/weapon_collision_bounds.gd")
const Hits = preload("res://src/content/ordinary_hit_definitions.gd")
const PlayerHits = preload("res://src/content/player_hit_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const Integer = preload("res://src/content/opening_definitions.gd")
const FIELDS := ["damage_property", "interval_property", "lifetime_property", "speed_property",
	"interval_percent_property", "damage_percent_property", "low_damage_threshold",
	"item_type_value_index", "item_category_value_index", "primary_category", "modifier_type"]

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func parameters(data: Dictionary) -> bool:
	if data.has("audio") and (not data.audio is Dictionary or (not data.audio.is_empty() and not Audio.parameters(data.audio))):return false
	if data.has("player_hit_policy") and (not data.player_hit_policy is Dictionary or (not data.player_hit_policy.is_empty() and not PlayerHits.parameters(data.player_hit_policy))): return false
	if data.has("collision_bounds") and not CollisionBounds.parameters(data.collision_bounds): return false
	if data.has("ordinary_hit_policy") and not Hits.parameters(data.ordinary_hit_policy): return false
	if data.has("launch_modes") and not launch_values(data.launch_modes): return false
	if data.has("projectile_capacity") and not capacity_values(data.projectile_capacity): return false
	for field in FIELDS:
		if not Integer.integer(data.get(field),0,65535): return false
	var properties := []
	for field in ["damage_property", "interval_property", "lifetime_property", "speed_property"]:
		if int(data[field]) in properties: return false
		properties.append(int(data[field]))
	if data.item_type_value_index!=5 or data.item_category_value_index!=3 or data.primary_category!=0 or data.modifier_type>29: return false
	for field in ["percent_divisor", "default_multiplier", "missing_multiplier", "low_damage_interval_scale"]:
		if not number(data.get(field)): return false
	return data.percent_divisor>0 and data.percent_divisor<=10000 and data.default_multiplier==1 \
		and data.missing_multiplier<0 and data.missing_multiplier>=-2147483648 \
		and data.low_damage_interval_scale>0 and data.low_damage_interval_scale<=1

static func validate(data: Variant, executable_bytes: int, architecture: String, vehicle: Dictionary, opening: Dictionary) -> String:
	if not data is Dictionary: return "Missing weapon parameter declarations"
	if data.is_empty(): return ""
	if data.size()!=17+int(data.has("launch_modes"))+int(data.has("projectile_capacity"))+int(data.has("ordinary_hit_policy"))+int(data.has("collision_bounds"))+int(data.has("player_hit_policy"))+int(data.has("audio")) or not parameters(data): return "Invalid weapon parameters"
	if data.has("player_hit_policy"):
		var player_error := PlayerHits.validate(data.player_hit_policy,executable_bytes,architecture,data)
		if not player_error.is_empty(): return player_error
	var mac := architecture=="x86_64"
	var sizes := {"head":77,"tail":120,"scale":147,"modifier":150,"defaults":16,"category_getter":9,"id_getter":8,"ship_getter":13,"damage_getter":11,"interval_getter":11,"property_getter":42,"type_getter":9,"equipment_table":120} if mac else {"head":60,"tail":100,"scale":98,"modifier":94,"defaults":10,"scale_tail":70,"constants":26,"scale_load":14,"category_getter":4,"id_getter":4,"ship_getter":6,"damage_getter":4,"interval_getter":4,"property_getter":48,"type_getter":4,"equipment_table":30} if architecture=="armv7" else {}
	var provenance: Variant = data.get("provenance")
	var sources: Variant = data.get("value_sources")
	var source_keys := ["percent_divisor", "missing_multiplier", "low_damage_interval_scale"]
	if mac: source_keys.append_array(["damage_divisor", "default_multiplier", "damage_default", "damage_missing"])
	if sizes.is_empty() or not provenance is Dictionary or provenance.size()!=sizes.size() or not sources is Dictionary or sources.size()!=source_keys.size(): return "Invalid weapon parameter provenance"
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid weapon context: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping weapon contexts"
		spans.append(span)
	for key in ["property_getter", "type_getter", "equipment_table"]:
		if provenance[key]!=vehicle.get("provenance",{}).get(key): return "Weapon parameters are not linked to this item catalogue: "+key
	if provenance.category_getter!=opening.get("provenance",{}).get("category_getter"): return "Weapon category does not match the opening loadout"
	if int(provenance.scale.offset)!=int(provenance.head.offset)+int(provenance.head.bytes): return "Disconnected weapon scaling context"
	if mac:
		if int(provenance.tail.offset)!=int(provenance.scale.offset)+147: return "Disconnected weapon factory context"
	else:
		if int(provenance.scale_tail.offset)!=int(provenance.scale.offset)+110 or int(provenance.tail.offset)!=int(provenance.scale_tail.offset)+70 or int(provenance.scale_load.offset)+76!=int(provenance.head.offset): return "Disconnected weapon factory context"
	var value_spans := []
	for key in source_keys:
		var row: Variant = sources.get(key)
		if not Fonts.extent(row,"offset","bytes",[4],executable_bytes): return "Invalid weapon constant: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+4)
		for context in spans:
			if span.x<context.y and span.y>context.x: return "Weapon constant overlaps a context"
		for previous in value_spans:
			if span!=previous and span.x<previous.y and span.y>previous.x: return "Partially overlapping weapon constants"
		value_spans.append(span)
	if data.has("launch_modes"):
		var launch_error := launch_modes(data.launch_modes,executable_bytes,architecture,data.provenance)
		if not launch_error.is_empty(): return launch_error
	if data.has("ordinary_hit_policy"):
		var hit_error := Hits.validate(data.ordinary_hit_policy,executable_bytes,architecture,data)
		if not hit_error.is_empty(): return hit_error
	if data.has("projectile_capacity"):
		var capacity_error := capacity(data.projectile_capacity,executable_bytes,architecture,data)
		if not capacity_error.is_empty(): return capacity_error
	if data.has("collision_bounds"):
		var bounds_error := CollisionBounds.validate(data.collision_bounds,executable_bytes,architecture,data)
		if not bounds_error.is_empty(): return bounds_error
	return ""

static func capacity_values(data: Variant) -> bool:
	return data is Dictionary and (data.is_empty() or (data.size()==2 and Integer.integer(data.get("slots"),1,4096) and data.get("provenance") is Dictionary))

static func capacity(data: Variant, executable_bytes: int, architecture: String, weapon: Dictionary) -> String:
	if not capacity_values(data): return "Invalid projectile capacity"
	if data.is_empty(): return ""
	var mac := architecture=="x86_64"
	var sizes := {"factory_entry":4,"range":40,"constructor_call":70,"type_selector":22,"kind_zero":4,"factory_call":120,"item_classification":65} if mac else {"factory_entry":4,"range":22,"constructor_call":72,"single":14,"type_selector":4,"kind_zero":2,"factory_call":100,"item_classification":56} if architecture=="armv7" else {}
	var p: Dictionary = data.provenance
	if sizes.is_empty() or p.size()!=sizes.size(): return "Invalid projectile capacity provenance"
	var spans := []
	for key in sizes:
		var row: Variant = p.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid projectile capacity context"
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping projectile capacity contexts"
		spans.append(span)
	if p.factory_call!=weapon.provenance.tail or p.item_classification!=weapon.get("launch_modes",{}).get("provenance",{}).get("classification"): return "Projectile capacity uses another weapon factory"
	if int(p.type_selector.offset)!=int(p.factory_entry.offset)+(57 if mac else 112): return "Disconnected projectile type selector"
	if mac:
		if int(p.constructor_call.offset)!=int(p.range.offset)+253: return "Disconnected projectile capacity call"
	elif int(p.constructor_call.offset)!=int(p.single.offset)+188 or int(p.kind_zero.offset)!=int(p.type_selector.offset)+4: return "Disconnected projectile capacity call"
	if int(p.range.offset)<=int(p.factory_entry.offset) or int(p.range.offset)>=int(p.factory_entry.offset)+1024 or int(p.constructor_call.offset)<=int(p.factory_entry.offset) or int(p.constructor_call.offset)>=int(p.factory_entry.offset)+2048: return "Projectile capacity lies outside its factory context"
	return ""

static func launch_modes(data: Variant, executable_bytes: int, architecture: String, weapon_provenance: Dictionary) -> String:
	if not launch_values(data): return "Invalid weapon launch modes"
	if data.is_empty(): return ""
	var sizes := {"classification":65,"selector":14,"selected_path":9,"property_getter":42} if architecture=="x86_64" else {"classification":56,"selector":14,"selected_path":4,"property_getter":48} if architecture=="armv7" else {}
	var provenance: Variant = data.get("provenance")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size()!=sizes.size(): return "Invalid weapon launch provenance"
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid weapon launch context"
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping weapon launch contexts"
		spans.append(span)
	if provenance.property_getter!=weapon_provenance.get("property_getter"): return "Weapon launch modes use another item catalogue"
	return ""

static func launch_values(data: Variant) -> bool:
	if not data is Dictionary: return false
	if data.is_empty(): return true
	if data.size()!=2 or not data.get("alternate_item_ids") is Array or data.alternate_item_ids.size()<2 or data.alternate_item_ids.size()>65: return false
	var ids := []
	for id in data.alternate_item_ids:
		if not Integer.integer(id,0,65535) or int(id) in ids: return false
		ids.append(int(id))
	return data.get("provenance") is Dictionary

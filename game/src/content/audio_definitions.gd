extends RefCounted
## Validate authored event metadata before any bank is opened or sound is played.
const Library=preload("res://src/content/library.gd")

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=low and value<=high

static func number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(value) and value>=low and value<=high

static func validate(data: Variant, files: Dictionary) -> String:
	if not data is Dictionary:return "Missing audio declarations"
	if data.is_empty():
		for file in files.values():
			if file.get("kind")=="audio_events":return "This base requires its audio event declarations"
		return ""
	if data.get("schema")!=1 and data.get("schema")!=2:return "Unsupported audio declaration schema"
	if data.get("format")!="fmod-designer-0x45":return "Unsupported audio declaration format"
	if not valid_category(data.get("categories")):return "Invalid audio category tree"
	var resource: Variant=data.get("source_resource")
	if not resource is String or not files.get(resource) is Dictionary:return "Missing audio event provenance"
	if files[resource].get("kind")!="audio_events" or data.get("source_sha256")!=files[resource].get("sha256") or not Library.valid_hash(data.source_sha256):return "Audio event checksum does not match the base"
	for key in ["banks","languages","events","sound_definitions","sound_settings"]:
		if not data.get(key) is Array or data[key].is_empty() or data[key].size()>20000:return "Invalid audio declaration table: "+key
	if data.banks.size()>256 or data.languages.size()>32 or not integer(data.get("default_language"),0,data.languages.size()-1):return "Invalid audio language table"
	for bank in data.banks:
		if not bank is Dictionary or not bank.get("variants") is Array or bank.variants.size()!=data.languages.size():return "Invalid audio bank variants"
		for variant in bank.variants:
			if not variant is Dictionary or not variant.get("resource") is String or not variant.get("hash_prefix") is String or variant.hash_prefix.length()!=16:return "Invalid audio bank provenance"
			var name: String=variant.resource
			if not name.begins_with("resources/") or not name.ends_with(".fsb") or name.contains("..") or name.contains(":") or name.contains("\\"):return "Unsafe audio bank resource"
			if not files.get(name) is Dictionary or files[name].get("kind")!="audio_bank":return "An event refers to a missing audio bank"
	for setting in data.sound_settings:
		if not setting is Dictionary:return "Invalid audio sound settings"
		var required: Array=["playlist_flags","volume_random_method","volume_min","volume_max","volume_random","pitch","pitch_random_method","pitch_min","pitch_max","pitch_random","pitch_recalc","position_random_min","position_random_max","trigger_delay_min","trigger_delay_max","spawn_count"]
		required.append_array(["spawn_min","spawn_max","spawn_mode","spawn_random"] if data.schema==1 else ["spawn_min_ms","spawn_max_ms","maximum_polyphony","volume"])
		for key in required:
			if not setting.has(key):return "Missing audio sound setting: "+key
		for key in setting:
			if not number(setting[key],-1000000,1000000):return "Invalid audio sound setting value"
	for definition in data.sound_definitions:
		if not definition is Dictionary or not integer(definition.get("settings"),0,data.sound_settings.size()-1) or not definition.get("entries") is Array or definition.entries.size()>256:return "Invalid audio sound definition"
		for entry in definition.entries:
			if not entry is Dictionary or not integer(entry.get("type"),0,3) or not integer(entry.get("weight"),0,1000000):return "Invalid audio sound entry"
			if entry.type==0 and (not integer(entry.get("bank"),0,data.banks.size()-1) or not integer(entry.get("index"),0,19999) or not integer(entry.get("length_ms"),0,3600000)):return "Invalid audio sample reference"
	for i in data.events.size():
		var event: Variant=data.events[i]
		if not event is Dictionary or event.get("id")!=i or not event.get("name") is String or not event.get("path") is String or not event.get("properties") is Dictionary:return "Invalid audio event identity"
		if not integer(event.get("source_offset"),0,files[resource].bytes-1) or not integer(event.get("source_bytes"),1,files[resource].bytes-event.source_offset):return "Invalid audio event extent"
		if not event.get("categories") is Array or event.categories.size()>16:return "Invalid audio event categories"
		for category in event.categories:
			if not category is String:return "Invalid audio event category"
		var p: Dictionary=event.properties
		for key in ["volume","pitch","pitch_random","volume_random","min_distance","max_distance","doppler","reverb_dry_db","reverb_wet_db","pan_level"]:
			if not number(p.get(key),-1000000,1000000):return "Invalid audio event parameter: "+key
		for key in ["mode","flags","max_playbacks","max_playbacks_behavior","fade_in_ms","fade_out_ms"]:
			if not integer(p.get(key),0,0xffffffff):return "Invalid audio event flags or timing"
		var sounds: Array=[]
		if event.has("sound"):
			if not event.sound is Dictionary:return "Invalid simple audio event"
			sounds.append(event.sound)
		else:
			if not event.get("layers") is Array or not event.get("parameters") is Array or event.layers.size()>64 or event.parameters.size()>64:return "Invalid layered audio event"
			for layer in event.layers:
				if not layer is Dictionary or not layer.get("sounds") is Array or not layer.get("envelopes") is Array or layer.sounds.size()>256:return "Invalid audio event layer"
				sounds.append_array(layer.sounds)
		for sound in sounds:
			if not sound is Dictionary or not integer(sound.get("sound_def"),0,data.sound_definitions.size()-1):return "Invalid audio event sound reference"
			for key in ["flags","flags2","auto_pitch","fade_in_type","fade_out_type"]:
				if not integer(sound.get(key),0,0xffffffff):return "Invalid audio sound flags"
			for key in ["volume","x","width","fine_tune","fade_in","fade_out"]:
				if not number(sound.get(key),-1000000,1000000):return "Invalid audio sound parameter"
			if not integer(sound.get("loop_count"),-1,1000000):return "Invalid audio sound loop count"
	return ""

static func valid_category(value: Variant, depth: int=0) -> bool:
	if depth>16 or not value is Dictionary or not value.get("name") is String or not value.get("children") is Array or value.children.size()>64:return false
	if not number(value.get("volume"),0,1000000) or not number(value.get("pitch"),-1000000,1000000) or not integer(value.get("max_playbacks"),0,0xffffffff) or not integer(value.get("flags"),0,0xffffffff):return false
	for child in value.children:
		if not valid_category(child,depth+1):return false
	return true

static func normalized(data: Dictionary) -> Dictionary:
	if data.schema==2:return data
	# v72 retained these words with provisional names/types. Reinterpret their
	# exact float32 bits; converting a subnormal float to int would erase its ms.
	var result:=data.duplicate(true)
	var word:=PackedByteArray();word.resize(4)
	for setting in result.sound_settings:
		for side in ["min","max"]:
			word.encode_float(0,setting["spawn_"+side])
			setting["spawn_"+side+"_ms"]=word.decode_u32(0)
			setting.erase("spawn_"+side)
		setting.maximum_polyphony=int(setting.spawn_mode);setting.erase("spawn_mode")
		setting.volume=setting.spawn_random;setting.erase("spawn_random")
	result.schema=2
	return result

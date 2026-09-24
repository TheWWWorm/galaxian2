extends RefCounted
## Native read-only access to normalized content. No original executable is loaded.
const SCHEMA := 1
const MAX_MANIFEST := 16 * 1024 * 1024
const MAX_LANGUAGE := 4 * 1024 * 1024
const MAX_CACHED_AUDIO_PCM := 64 * 1024 * 1024
# Catalogue and localization extents identify independently verified layouts.
# A bundle's version label and CPU architecture do not identify its ship set.
const LAYOUTS := {"ios-hd": {64: 3402}, "mac-full-hd": {61: 3371, 64: 3385}}
var error := ""
var root := ""
var manifest: Dictionary = {}
var strings: Array = []
var active_language := ""
var _audio_pcm := {}
var _audio_pcm_bytes := 0


func open(directory: String) -> bool:
	error = ""
	_audio_pcm.clear()
	_audio_pcm_bytes = 0
	manifest = {}
	strings = []
	active_language = ""
	root = ""
	if not directory.is_absolute_path():
		return fail("Choose an absolute path to an imported content directory.")
	var file := FileAccess.open(directory.path_join("manifest.json"), FileAccess.READ)
	if file == null or file.get_length() > MAX_MANIFEST:
		return fail("The imported content manifest is missing or too large.")
	var value: Variant = JSON.parse_string(file.get_as_text())
	if not value is Dictionary:
		return fail("The content manifest is not a JSON object.")
	if value.get("schema") != SCHEMA:
		return fail("Unsupported import schema. Import the source again with this engine.")
	for key in ["profile", "languages", "files", "counts", "support", "ship_table"]:
		if not value.get(key) is Dictionary:
			return fail("Incomplete content manifest: " + key)
	if value.profile.get("edition") not in ["ios-hd", "mac-full-hd"]:
		return fail("Unsupported content profile.")
	if value.profile.get("layout") != "gof2-bundle-v1":
		return fail("Unsupported content layout.")
	if catalogue_layout(value).is_empty():
		return fail("The ship and language tables do not match a supported content layout.")
	for kind in ["mesh", "texture", "catalogue", "audio_bank"]:
		var count: Variant = value.counts.get(kind, 0)
		if not count is float and not count is int:
			return fail("Invalid content count.")
		if count < 0 or count > 20000 or count != floor(count):
			return fail("Invalid content count.")
	if not valid_hash(value.get("content_id")):
		return fail("Invalid base content identity.")
	if value.languages.is_empty() or value.languages.size() > 12:
		return fail("Missing or unsupported language set.")
	for code in value.languages:
		if code not in ["de", "es", "fr", "gb", "it", "ja", "ko", "pl", "ptl", "ru", "zs", "zt"]:
			return fail("Unsupported language identifier.")
		var entry: Variant = value.languages[code]
		var expected := "definitions/languages/%s.json" % code
		if not entry is Dictionary or entry.get("path") != expected:
			return fail("Invalid language definition path.")
		var record: Variant = value.files.get(expected)
		if not record is Dictionary or not valid_hash(record.get("sha256")):
			return fail("Missing language provenance.")
		if not record.get("bytes") is float and not record.get("bytes") is int:
			return fail("Invalid language size.")
		if record.bytes < 1 or record.bytes > MAX_LANGUAGE:
			return fail("Oversized language definition.")
	root = directory
	manifest = value
	return true


func select_language(code: String) -> bool:
	error = ""
	strings = []
	active_language = ""
	if not manifest.get("languages", {}).has(code):
		return fail("This language is absent from the selected content profile.")
	var entry: Dictionary = manifest.languages[code]
	var path: String = root.path_join(entry.path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fail("The selected language definition is missing.")
	var record: Dictionary = manifest.files[entry.path]
	if file.get_length() != int(record.bytes):
		return fail("The selected language definition has changed. Reimport the source.")
	var bytes := file.get_buffer(int(record.bytes))
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if hash.finish().hex_encode() != record.sha256:
		return fail("Language checksum mismatch. Reimport the source.")
	var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not value is Dictionary or value.get("schema") != SCHEMA or value.get("language") != code:
		return fail("Invalid normalized language definition.")
	if value.get("source_resource") != entry.get("source_resource"):
		return fail("Language source provenance mismatch.")
	if not value.get("strings") is Array:
		return fail("Missing localized strings.")
	var count := int(catalogue_layout(manifest).get("strings", 0))
	if value.strings.size() != count or entry.get("records") != count:
		return fail("Language record count does not match the content profile.")
	for text in value.strings:
		if not text is String:
			return fail("Invalid localized string.")
	strings = value.strings
	active_language = code
	return true


static func catalogue_layout(value: Dictionary) -> Dictionary:
	var profile: Variant = value.get("profile")
	var ships: Variant = value.get("ship_table")
	var languages: Variant = value.get("languages")
	if not profile is Dictionary or not ships is Dictionary or not languages is Dictionary or languages.is_empty():
		return {}
	var edition: Variant = profile.get("edition")
	var count: Variant = ships.get("records")
	if not LAYOUTS.has(edition) or not (count is int or count is float) or not is_finite(count) or count < 1 or count > 256 or count != floor(count):
		return {}
	if not LAYOUTS[edition].has(int(count)) or ships.get("record_bytes") != 36:
		return {}
	var strings: int = LAYOUTS[edition][int(count)]
	for language in languages.values():
		if not language is Dictionary or language.get("records") != strings:
			return {}
	var files: Variant = value.get("files")
	if not files is Dictionary:
		return {}
	var table: Variant = files.get("resources/data/bin/ships.bin")
	if not table is Dictionary or table.get("bytes") != int(count) * 36:
		return {}
	return {"variant": "%s-%d" % [edition, int(count)], "ships": int(count), "strings": strings}


func save_directory() -> String:
	# Reserved namespace only: campaign saves are not implemented yet.
	if manifest.is_empty():
		return ""
	return "user://saves/%s/%s" % [manifest.profile.edition, manifest.content_id]


func read_resource(name: String, limit: int) -> PackedByteArray:
	error = ""
	if not name.begins_with("resources/") or name.contains("\\") or name.contains(":"):
		fail("Invalid resource path")
		return PackedByteArray()
	for part in name.split("/"):
		if part in ["", ".", ".."]:
			fail("Unsafe resource path")
			return PackedByteArray()
	var row: Variant = manifest.get("files", {}).get(name)
	if not row is Dictionary or not valid_hash(row.get("sha256")):
		fail("Missing resource provenance")
		return PackedByteArray()
	if not row.get("bytes") is float and not row.get("bytes") is int:
		fail("Invalid resource size")
		return PackedByteArray()
	if row.bytes < 1 or row.bytes > limit:
		fail("Resource exceeds its reader budget")
		return PackedByteArray()
	var file := FileAccess.open(root.path_join(name), FileAccess.READ)
	if file == null or file.get_length() != int(row.bytes):
		fail("Resource is missing or changed")
		return PackedByteArray()
	var bytes := file.get_buffer(int(row.bytes))
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if hash.finish().hex_encode() != row.sha256:
		fail("Resource checksum mismatch")
		return PackedByteArray()
	return bytes


## AudioResources re-reads and verifies each bank before asking for its PCM.
## This cache stores only decoded samples, never a substitute for that check.
func cached_audio_pcm(name: String, index: int, expected_bytes: int) -> PackedByteArray:
	var key := _audio_pcm_key(name, index)
	if key.is_empty() or expected_bytes < 1:
		return PackedByteArray()
	var cached: PackedByteArray = _audio_pcm.get(key, PackedByteArray())
	return cached.duplicate() if cached.size() == expected_bytes else PackedByteArray()


func remember_audio_pcm(name: String, index: int, pcm: PackedByteArray) -> void:
	var key := _audio_pcm_key(name, index)
	if key.is_empty() or pcm.is_empty() or _audio_pcm.has(key) or _audio_pcm_bytes + pcm.size() > MAX_CACHED_AUDIO_PCM:
		return
	_audio_pcm[key] = pcm.duplicate()
	_audio_pcm_bytes += pcm.size()


func cached_audio_pcm_bytes() -> int:
	return _audio_pcm_bytes


func _audio_pcm_key(name: String, index: int) -> String:
	if index < 0:
		return ""
	var row: Variant = manifest.get("files", {}).get(name)
	if not row is Dictionary or row.get("kind") != "audio_bank" or not valid_hash(row.get("sha256")):
		return ""
	return name + ":" + row.sha256 + ":" + str(index)


func fail(message: String) -> bool:
	error = message
	return false


static func valid_hash(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

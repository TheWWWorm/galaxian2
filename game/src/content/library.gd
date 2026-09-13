extends RefCounted
## Native read-only access to normalized content. No original executable is loaded.
const SCHEMA := 1
const MAX_MANIFEST := 16 * 1024 * 1024
const MAX_LANGUAGE := 4 * 1024 * 1024
var error := ""
var root := ""
var manifest: Dictionary = {}
var strings: Array = []
var active_language := ""


func open(directory: String) -> bool:
	error = ""
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
	var count := 3402 if manifest.profile.edition == "ios-hd" else 3371
	if value.strings.size() != count or entry.get("records") != count:
		return fail("Language record count does not match the content profile.")
	for text in value.strings:
		if not text is String:
			return fail("Invalid localized string.")
	strings = value.strings
	active_language = code
	return true


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

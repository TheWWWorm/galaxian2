extends RefCounted
## Local engine preferences, kept separate from content-bound career saves.
const MAX_BYTES=32768
const LANGUAGES=["de","es","fr","gb","it","ja","ko","pl","ptl","ru","zs","zt"]
var error:=""
var values:=defaults()

static func defaults() -> Dictionary:
	return {"schema":1,"content":"","bindings":"","visuals":"","import_record":"","language":"gb",
		"music":1.0,"fx":1.0,"voice":1.0,"invert_pitch":false,"touch_controls":OS.has_feature("mobile")}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=defaults().size() or value.get("schema")!=1 or value.get("language") not in LANGUAGES:return false
	for key in ["content","bindings","visuals","import_record"]:
		if not value.get(key) is String or value[key].length()>4096 or (not value[key].is_empty() and not value[key].is_absolute_path()):return false
	for key in ["music","fx","voice"]:
		if not (value.get(key) is float or value.get(key) is int) or not is_finite(value[key]) or value[key]<0 or value[key]>1:return false
	for key in ["invert_pitch","touch_controls"]:
		if not value.get(key) is bool:return false
	return true

func read_file(path: String) -> bool:
	error=""
	if not FileAccess.file_exists(path):return true
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>MAX_BYTES:return reject("Could not read the saved game preferences")
	var candidate: Variant=JSON.parse_string(file.get_as_text());file.close()
	if candidate is Dictionary and not candidate.has("import_record"):candidate.import_record=""
	if not valid(candidate):return reject("Saved preferences are invalid; choose the game files again")
	values=candidate;return true

func save_file(path: String,candidate: Dictionary) -> bool:
	error=""
	if not valid(candidate):return reject("The game preferences are invalid")
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir())!=OK:return reject("Could not create the preferences folder")
	var staged:=path+".tmp";var text:=JSON.stringify(candidate,"\t")+"\n"
	var file:=FileAccess.open(staged,FileAccess.WRITE)
	if file==null:return reject("Could not write the game preferences")
	file.store_string(text);file.flush();var result:=file.get_error();file.close()
	var check_file:=FileAccess.open(staged,FileAccess.READ)
	var verified:=check_file!=null and check_file.get_as_text()==text
	if check_file!=null:check_file.close()
	if result!=OK or not verified or DirAccess.rename_absolute(staged,path)!=OK:
		DirAccess.remove_absolute(staged);return reject("Could not finish saving preferences")
	values=candidate.duplicate(true);return true

func reject(message: String) -> bool:error=message;return false

extends RefCounted
## Local engine preferences, kept separate from content-bound career saves.
const MAX_BYTES=32768
const LANGUAGES=["de","es","fr","gb","it","ja","ko","pl","ptl","ru","zs","zt"]
const RESOLUTIONS=["native","1120x720","1280x720","1280x800","1366x768","1600x900","1920x1080","1920x1200","2560x1080","2560x1440","2560x1600","3440x1440","3840x1600","3840x2160","5120x2160","5120x2880","7680x4320"]
const ASPECTS=["auto","native","4:3","16:9","16:10","21:9","32:9"]
const FRAME_RATES=[-1,0,30,60,90,120,144,165,240,360]
const UI_SCALES=[0,75,100,125,150,175,200,225,250,275,300]
const DISPLAY_KEYS=["window_mode","resolution","aspect_ratio","frame_rate","ui_scale"]
var error:=""
var values:=defaults()

static func defaults() -> Dictionary:
	return {"schema":3,"content":"","bindings":"","visuals":"","import_record":"","language":"gb",
		"music":1.0,"fx":1.0,"voice":1.0,"invert_pitch":false,"touch_controls":OS.has_feature("mobile"),
		"window_mode":"windowed","resolution":"1120x720","aspect_ratio":"auto","frame_rate":-1,"ui_scale":0,
		"mouse_steering":not OS.has_feature("mobile"),"mouse_sensitivity":1.0}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=defaults().size() or value.get("schema")!=3 or value.get("language") not in LANGUAGES:return false
	for key in ["content","bindings","visuals","import_record"]:
		if not value.get(key) is String or value[key].length()>4096 or (not value[key].is_empty() and not value[key].is_absolute_path()):return false
	for key in ["music","fx","voice"]:
		if not (value.get(key) is float or value.get(key) is int) or not is_finite(value[key]) or value[key]<0 or value[key]>1:return false
	for key in ["invert_pitch","touch_controls","mouse_steering"]:
		if not value.get(key) is bool:return false
	if value.get("window_mode") not in ["windowed","fullscreen"] or value.get("resolution") not in RESOLUTIONS or value.get("aspect_ratio") not in ASPECTS:return false
	if not (value.get("frame_rate") is int or value.get("frame_rate") is float) or not is_finite(value.frame_rate) or value.frame_rate!=floor(value.frame_rate) or int(value.frame_rate) not in FRAME_RATES:return false
	if not (value.get("ui_scale") is int or value.get("ui_scale") is float) or not is_finite(value.ui_scale) or value.ui_scale!=floor(value.ui_scale) or int(value.ui_scale) not in UI_SCALES:return false
	if not (value.get("mouse_sensitivity") is int or value.get("mouse_sensitivity") is float) or not is_finite(value.mouse_sensitivity) or value.mouse_sensitivity<0.1 or value.mouse_sensitivity>3.0:return false
	return true

func read_file(path: String) -> bool:
	error=""
	if not FileAccess.file_exists(path):return true
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>MAX_BYTES:return reject("Could not read the saved game preferences")
	var candidate: Variant=JSON.parse_string(file.get_as_text());file.close()
	if candidate is Dictionary and candidate.get("schema")==1:
		# Preserve the existing import, language, audio and controls on upgrade.
		if not candidate.has("import_record"):candidate.import_record=""
		for key in DISPLAY_KEYS+["mouse_steering","mouse_sensitivity"]:
			if not candidate.has(key):candidate[key]=defaults()[key]
		candidate.schema=2
	if candidate is Dictionary and candidate.get("schema")==2:
		candidate.ui_scale=0;candidate.schema=3
	if not valid(candidate):return reject("Saved preferences are invalid; choose the game files again")
	candidate.schema=int(candidate.schema);candidate.frame_rate=int(candidate.frame_rate);candidate.ui_scale=int(candidate.ui_scale)
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

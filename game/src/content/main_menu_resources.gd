extends RefCounted
## Semantic bindings for the Mac menu, using already imported aliases and text.
## Menu type0 declares these actions; type2 is the separate in-game menu.
const Atlas=preload("res://src/content/atlas_region.gd")
const LOGO_IMAGE_ID=7002
const LOGO_TEXTURE_ID=10002
const LOGO_RESOURCE="resources/data/textures/gof2_logos.aei"
const ACTIONS=[
	{"action":"new_game","source_action":0,"text_id":28},
	{"action":"supernova","source_action":83,"text_id":282},
	{"action":"resume","source_action":11,"text_id":41},
	{"action":"load","source_action":1,"text_id":29},
	{"action":"options","source_action":3,"text_id":31},
	{"action":"language","source_action":25,"text_id":0},
	{"action":"info","source_action":4,"text_id":43},
]
const EXIT_TEXT_ID=33
const TITLE_PROMPT_TEXT_ID=188
var error:=""
var logo: AtlasTexture
var title_prompt: String
var actions: Array=[]
var identity:={}

func configure(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> bool:
	error=""
	if library==null or bindings==null or visuals==null or library.manifest.get("profile",{}).get("edition")!="mac-full-hd" or bindings.base_content_id!=library.manifest.get("content_id") or visuals.base_content_id!=bindings.base_content_id:return reject("The main menu requires matching Mac Full HD content")
	var alias: Dictionary=bindings.resolve_image_region(LOGO_IMAGE_ID,LOGO_TEXTURE_ID)
	if alias.is_empty() or int(alias.get("region",-1))!=2:return reject("The imported Full HD logo alias is unavailable")
	var registered:=false
	for row in bindings.records.get(LOGO_TEXTURE_ID,[]):
		if row.kind=="texture" and row.resource==LOGO_RESOURCE and row.registration_type==2:registered=true
	if not registered:return reject("The original Mac Full HD logo atlas is unavailable")
	var atlas:=Atlas.new();var prepared:=atlas.load(library,visuals,LOGO_RESOURCE,int(alias.region))
	if prepared==null:return reject(atlas.error)
	var rows:=[]
	for item in ACTIONS:
		if item.text_id>=library.strings.size() or library.strings[item.text_id].is_empty():return reject("The imported menu text is incomplete")
		var row: Dictionary=item.duplicate();row.text=library.strings[item.text_id];rows.append(row)
	if EXIT_TEXT_ID>=library.strings.size() or TITLE_PROMPT_TEXT_ID>=library.strings.size() or library.strings[TITLE_PROMPT_TEXT_ID].is_empty():return reject("The menu title text is unavailable")
	logo=prepared;actions=rows;title_prompt=library.strings[TITLE_PROMPT_TEXT_ID]
	identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	return true

func reject(message: String) -> bool:error=message;return false

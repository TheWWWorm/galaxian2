extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Original Mac game-over image and prompt. Destruction owns progression/clocks.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Death=preload("res://src/content/player_destruction_definitions.gd")
const VALUES := {"scope":"mac_starter_game_over_presentation","image_id":1313,"texture_id":10062,"region":211,"resource":"resources/data/textures/gof2_interface.aei","continue_text_id":188,"blink_radians_per_millisecond":0.003000000026077032,"prompt_gap":10,"center_image":true,"center_prompt":true,"prompt_rgb":[255,255,255],"prompt_after_full_fade":true,"blink_uses_absolute_milliseconds":true}
const SPANS := {"image_alias":[-524764,64],"alias_collection":[-388935,32],"alias_collection_helper":[1132154,64],"failure_display":[390050,435],"image_positioning":[1140682,1120],"image_height":[1140586,96],"sine_wrapper":[1248314,48],"blink_constant":[1584146,4],"alpha_constant":[1573874,4]}

const MAC_ALTERNATE := {"image_alias":[-527198,64],"alias_collection":[-390823,32],"alias_collection_helper":[1131346,64],"failure_display":[390566,435],"image_positioning":[1139394,1040],"image_height":[1139298,96],"sine_wrapper":[1241138,48],"blink_constant":[1559210,4],"alpha_constant":[1548938,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, death: Dictionary) -> String:
	if not data is Dictionary:return "Missing game-over presentation declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported game-over presentation declarations"
	if not Death.parameters(death):return "Game-over presentation lacks its destruction context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Game-over presentation lacks its source anchor"
	var layouts: Array=[SPANS,MAC_ALTERNATE]
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,layouts) else "Invalid game over presentation extents"

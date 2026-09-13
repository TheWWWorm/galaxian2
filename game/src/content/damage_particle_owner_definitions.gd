extends RefCounted
## Source-bound ownership, distinct from the reusable particle presets.
const Numbers=preload("res://src/content/opening_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.get("scope")!="fresh_opening_damage_emitters":return false
	var fraction: Variant=data.get("npc_hull_fraction")
	if not (fraction is float or fraction is int) or not is_finite(fraction) or fraction<=0 or fraction>=1:return false
	return Numbers.integer(data.get("npc_suppressed_mode"),9,9) and Numbers.integer(data.get("active_mode"),1,1) and Numbers.integer(data.get("player_max_campaign_cursor"),1,1) and data.get("npc_uses_detail_gate") is bool and data.get("initially_damaged") is bool and not data.initially_damaged

static func validate(data: Variant,executable_bytes: int,architecture: String) -> String:
	if not data is Dictionary:return "Missing damage particle owner declarations"
	if data.is_empty():return ""
	if not parameters(data):return "Unsupported damage particle owner parameters"
	if architecture not in ["x86_64","armv7"] or data.npc_uses_detail_gate!=(architecture=="x86_64"):return "Damage particle owner profile differs from its executable"
	var sizes:=MAC_SIZES if architecture=="x86_64" else ARM_SIZES
	var proof: Variant=data.get("provenance")
	if not proof is Dictionary or proof.size()!=sizes.size():return "Invalid damage particle owner provenance"
	var spans:=[]
	for key in sizes:
		var row: Variant=proof.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes):return "Invalid damage particle owner extent: "+key
		var begin:=int(row.offset);var end:=begin+int(row.bytes)
		for span in spans:
			if begin<span.y and end>span.x:return "Overlapping damage particle owner declarations"
		spans.append(Vector2i(begin,end))
	return ""

const MAC_SIZES={"npc_registration":128,"npc_initial_flag":18,"npc_threshold":351,"hull_fraction":4,"npc_release":77,"npc_holding":75,"npc_breakup":173,"player_registration":157,"player_enable":80,"restore_cue":5,"relocation_reset":28,"world_smoke_update":20,"world_fire_update":20,"npc_root_getter":13,"npc_root_capture":45,"player_root_getter":17}
const ARM_SIZES={"npc_registration":84,"npc_initial_flag":70,"npc_threshold":272,"hull_fraction":4,"npc_release":78,"npc_holding":70,"npc_breakup":122,"player_registration":108,"player_enable":48,"restore_cue":4,"relocation_reset":34,"world_smoke_update":12,"world_fire_update":14,"npc_root_getter":4,"npc_root_capture":30,"player_root_getter":8}

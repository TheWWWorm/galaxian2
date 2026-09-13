extends RefCounted
## Source first-mining drill dispatch; missions remain separate.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Approach=preload("res://src/content/mining_approach_definitions.gd")
const Drill=preload("res://src/content/mining_drill_definitions.gd")
const VALUES := {"scope":"first_mining_session","campaign_cursor":2,"max_frame_ms":150,"failure_notification":8,"failure_text_id":528,"stop_audio_events":[1,3],"automatic_finish_resumes_motion":true,"commands_after_update":true,"creation_frame_advances_drill":false,"cancelled_target_grants_ore":false}
const SPANS := {"ongoing_drill":[588551,179],"finish_release":[602148,84],"stop_dispatch":[344857,48],"stop_finish":[345173,9],"active_drill":[558724,17],"player_frame_dispatch":[366274,86],"frame_delta":[363155,72],"hud_drill_input":[378881,448],"failure_text":[-115464,20],"notification_dispatch":[-116996,29],"failure_jump_entry":[-111902,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, approach: Dictionary, drill: Dictionary) -> String:
	if not data is Dictionary:return "Missing mining session declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Approach.parameters(approach) or not Drill.parameters(drill):return "Unsupported mining session declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Mining session lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid mining session provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid mining session extent: "+key
	return ""

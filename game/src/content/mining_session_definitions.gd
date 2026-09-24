extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Source first-mining drill dispatch; missions remain separate.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Approach=preload("res://src/content/mining_approach_definitions.gd")
const Drill=preload("res://src/content/mining_drill_definitions.gd")
const VALUES := {"scope":"first_mining_session","campaign_cursor":2,"max_frame_ms":150,"failure_notification":8,"failure_text_id":528,"stop_audio_events":[1,3],"automatic_finish_resumes_motion":true,"commands_after_update":true,"creation_frame_advances_drill":false,"cancelled_target_grants_ore":false}
const SPANS := {"ongoing_drill":[588551,179],"finish_release":[602148,84],"stop_dispatch":[344857,48],"stop_finish":[345173,9],"active_drill":[558724,17],"player_frame_dispatch":[366274,86],"frame_delta":[363155,72],"hud_drill_input":[378881,448],"failure_text":[-115464,20],"notification_dispatch":[-116996,29],"failure_jump_entry":[-111902,4]}

const MAC_ALTERNATE := {"ongoing_drill":[589098,179],"finish_release":[602696,84],"stop_dispatch":[344571,48],"stop_finish":[344887,9],"active_drill":[559260,17],"player_frame_dispatch":[365997,86],"frame_delta":[362878,72],"hud_drill_input":[379393,448],"failure_text":[-115884,20],"notification_dispatch":[-117416,29],"failure_jump_entry":[-112322,4],"failure_instruction_gate":[372439,170],"failed_getter":[602800,14],"instruction_ack_gate":[348093,42],"instruction_ack_dispatch":[350198,34],"instruction_acknowledgement":[350334,36],"instruction_title":[-713296,54],"instruction_pause":[340770,99],"instruction_resume":[340870,88],"instruction_button":[-708672,152],"instruction_update":[377763,31],"instruction_reset_owner":[588850,222]}
const CURRENT_SPANS := {"ongoing_drill":[588551,179],"finish_release":[602148,84],"stop_dispatch":[344857,48],"stop_finish":[345173,9],"active_drill":[558724,17],"player_frame_dispatch":[366274,86],"frame_delta":[363155,72],"hud_drill_input":[378881,448],"failure_text":[-115464,20],"notification_dispatch":[-116996,29],"failure_jump_entry":[-111902,4],"failed_getter":[602252,14],"failure_instruction_gate":[371951,146],"instruction_ack_dispatch":[350484,34],"instruction_ack_gate":[348379,42],"instruction_acknowledgement":[350620,36],"instruction_button":[-702776,152],"instruction_pause":[341056,99],"instruction_reset_owner":[588314,211],"instruction_resume":[341156,88],"instruction_title":[-707400,54],"instruction_update":[377251,31]}
const CURRENT_VALUES := {"scope":"first_mining_session","campaign_cursor":2,"max_frame_ms":150,"failure_notification":8,"failure_text_id":528,"stop_audio_events":[1,3],"automatic_finish_resumes_motion":true,"commands_after_update":true,"creation_frame_advances_drill":false,"cancelled_target_grants_ore":false,"failure_instruction":{"campaign_cursor":-1,"text_id":606,"title_text_id":379,"repeat_each_drill":false,"opens_before_mission_poll":true,"acknowledgement_advances_story":false}}
const MAC_VALUES := {"scope":"first_mining_session","campaign_cursor":2,"max_frame_ms":150,"failure_notification":8,"failure_text_id":528,"stop_audio_events":[1,3],"automatic_finish_resumes_motion":true,"commands_after_update":true,"creation_frame_advances_drill":false,"cancelled_target_grants_ore":false,"failure_instruction":{"campaign_cursor":2,"text_id":606,"title_text_id":379,"repeat_each_drill":true,"opens_before_mission_poll":true,"acknowledgement_advances_story":false}}

static func parameters(data: Variant) -> bool:
	return _parameters(data,VALUES) or _parameters(data,CURRENT_VALUES) or _parameters(data,MAC_VALUES)

static func retain_hint_history(progress: Dictionary, target: Dictionary, rules: Dictionary) -> bool:
	if not progress.has("mining_failure_hint_seen"):return true
	if not rules.has("failure_instruction") or not progress.mining_failure_hint_seen is bool:return false
	target.mining_failure_hint_seen=progress.mining_failure_hint_seen
	return true

static func _parameters(data: Variant,expected: Dictionary) -> bool:
	if not data is Dictionary or data.size()!=expected.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in expected:
		if not Equal.equal_value(data.get(key),expected[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, approach: Dictionary, drill: Dictionary) -> String:
	if not data is Dictionary:return "Missing mining session declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Approach.parameters(approach) or not Drill.parameters(drill):return "Unsupported mining session declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Mining session lacks its source anchor"
	var layouts: Array=[]
	if _parameters(data,VALUES):layouts.append(SPANS)
	if _parameters(data,CURRENT_VALUES):layouts.append(CURRENT_SPANS)
	if _parameters(data,MAC_VALUES):layouts.append(MAC_ALTERNATE)
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,layouts) else "Invalid mining session extents"

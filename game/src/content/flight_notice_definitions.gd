extends RefCounted
## Timed notices for the first mining flight; no dialogue or mission completion.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Flight=preload("res://src/content/first_flight_definitions.gd")
const VALUES := {"scope":"first_mining_flight_notices","campaign_cursor":2,"max_frame_ms":150,"pending_capacity":19,"retire_at_ms":4001,"falling_at_ms":2001,"fade_half_ms":2000.0,"alpha_max":255,"duplicate_key":"localized_text","new_notice_resets_clock":false,"drilling_holds_clock":true,"messages":{"6":{"text_ids":[560,39],"separator":" ","rgb":[255,255,255]},"8":{"text_ids":[528],"separator":"","rgb":[255,255,255]},"9":{"text_ids":[529],"separator":"","rgb":[255,255,255]},"11":{"text_ids":[535,539],"separator":": ","rgb":[255,255,255]},"20":{"text_ids":[530],"separator":"","rgb":[255,255,255]},"27":{"text_ids":[311],"separator":"","rgb":[255,42,0]}},"background_image_id":1219,"background_texture_id":10062,"background_region":118}
const SPANS := {"queue_allocation":[-127697,69],"queue_resize":[-173421,86],"queue_initial":[-127366,67],"queue_update":[-118108,203],"duplicate_check":[-117112,87],"insert_dispatch":[-112369,196],"ordinary_insert":[-112050,83],"ordinary_style":[235630,32],"colored_style":[235931,13],"alpha":[-118642,75],"colors_and_text":[-118445,197],"alpha_constants":[1573870,8],"drill_gate":[-107442,58],"dispatcher":[-116996,29],"cancel_text":[-116162,126],"failure_text":[-115464,20],"tractor_text":[-115444,20],"target_text":[-115424,126],"drill_text":[-113644,20],"full_hold_text":[-113544,20],"text_separators":[1682229,5],"action_notices":[344326,191],"background_lookup":[-131356,20],"background_alias":[-528604,64],"background_draw":[-118567,70],"dispatch_6":[-111910,4],"dispatch_8":[-111902,4],"dispatch_9":[-111898,4],"dispatch_11":[-111890,4],"dispatch_20":[-111854,4],"dispatch_27":[-111826,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, flight: Dictionary) -> String:
	if not data is Dictionary:return "Missing flight notice declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Flight.parameters(flight):return "Unsupported flight notice declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Flight notice lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid flight notice provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid flight notice extent: "+key
	return ""

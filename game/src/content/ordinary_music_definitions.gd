extends RefCounted
## Verified Mac ordinary flight music selection. Special scripted cues are separate.
const Layouts=preload("res://src/content/declaration_layouts.gd")
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const FastForward=preload("res://src/content/fast_forward_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")

const VALUES := {"scope":"ordinary_flight_music","sample_phase":"radar_hud_after_world","requires_visible_radar":true,"intro_hold_id":143,"battle_maximums":[2,4],"battle_event_ids":[140,141,142],"faction_event_ids":[134,139,138,137],"portal_battle_id":136,"portal_peace_id":145,"deep_science_peace_id":152,"kind10_battle_id":151,"marked_battle_event_ids":[149,150],"marked_battle_maximum":4,"marked_actor_base_flag":false,"marked_root_bit_initial":false,"marked_actor_effective":"actor_flag_and_root_bit","marked_world_roll":{"faction":0,"group_count_positive":true,"bound":100,"below":30,"extra_group_sizes":[7,8]},"battle_retained_ids":[136,140,141,142,149,150,151],"peace_retained_ids":[127,128,129,130,134,137,138,139,145,146,147,148,152],"switch_action":"stop_then_start","stop_fade_ms":800,"normal_world_context_only":true}
const LEGACY := {"selector":[10,1001],"faction_getter":[57760,10],"faction_table":[912162,16],
	"selected_retained":[181154,27],"station_source":[174480,29],"system_special":[195740,79],"station_special":[195976,83],
	"location_equal":[176384,23],"station_getter":[174448,11],"system_getter":[57710,11],"cursor_getter":[181252,13],
	"actor_marker_clear":[-758044,4],"marked_faction_origin":[-707598,97],"marked_roll_gate":[-702453,71],"marked_group_size":[-702103,31],"marked_actor_branch":[-701268,940],
	"stats_marker_zero":[-141911,7],"stats_marker_setter":[-141280,28],"stats_marker_getter":[-141210,14]}
const APPSTORE := {"selector":[10,1001],"faction_getter":[57844,10],"faction_table":[886710,16],
	"selected_retained":[181238,27],"station_source":[174564,29],"system_special":[195824,79],"station_special":[196060,83],
	"location_equal":[176468,23],"station_getter":[174532,11],"system_getter":[57794,11],"cursor_getter":[181336,13],
	"actor_marker_clear":[-758592,4],"marked_faction_origin":[-708146,97],"marked_roll_gate":[-703001,71],"marked_group_size":[-702651,31],"marked_actor_branch":[-701816,940],
	"stats_marker_zero":[-141923,7],"stats_marker_setter":[-141292,28],"stats_marker_getter":[-141222,14]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, fast_forward: Dictionary, audio: Dictionary) -> String:
	if not data is Dictionary:return "Invalid ordinary music declaration"
	if data.is_empty():return ""
	if not parameters(data) or arch!="x86_64" or not FastForward.radar_available(fast_forward):return "Ordinary music needs verified Mac radar and event declarations"
	var origin: Variant=fast_forward.radar.provenance.get("radar_music_publication_gate")
	if not Fonts.extent(origin,"offset","bytes",[22],source_bytes):return "Ordinary music lost its radar source anchor"
	if not Layouts.matches(data.provenance,int(origin.offset),source_bytes,[LEGACY,APPSTORE]):return "Invalid or mixed ordinary music source provenance"
	var events: Variant=audio.get("events")
	if not events is Array or events.size()!=2293:return "Ordinary music needs the selected source event project"
	var selected: Array=VALUES.battle_event_ids+VALUES.faction_event_ids+VALUES.marked_battle_event_ids+[VALUES.intro_hold_id,VALUES.portal_battle_id,VALUES.portal_peace_id,VALUES.deep_science_peace_id,VALUES.kind10_battle_id]
	for id in selected:
		var event: Variant=events[int(id)]
		if not event is Dictionary or event.get("id")!=id or event.get("categories")!=["music"] or event.get("simple_flags")!=1 or not event.get("properties") is Dictionary or not event.get("sound") is Dictionary:return "Ordinary music event identity changed"
		if event.properties.get("fade_out_ms")!=VALUES.stop_fade_ms or event.properties.get("max_playbacks")!=1 or event.sound.get("flags")!=0:return "Ordinary music event is not its source loop"
	return ""

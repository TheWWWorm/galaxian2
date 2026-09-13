extends RefCounted
## Source-present starter offers and installed-equipment tutorial predicate.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Return=preload("res://src/content/full_hold_return_definitions.gd")
const VALUES := {"scope":"var_hastra_equipment_tutorial","station_id":78,"system_id":15,"campaign_cursor":6,"mission_kind":158,"stock_maximum_cursor":6,"stock":[{"item_id":0,"quantity":1,"unit_price":0},{"item_id":22,"quantity":1,"unit_price":0},{"item_id":55,"quantity":1,"unit_price":0}],"protected_item_ids":[90,81],"item_category_value_index":3,"item_subtype_value_index":5,"item_text_offset":1255,"multiple_subtype_mask":6137572235519,"weapon_category":0,"armor_subtype":10,"refresh_cargo_on_transaction":true,"reward_credits":0,"bonus_credits":0,"cursor_after_acknowledgement":7,"next_mission_kind":4,"next_mission_parameter":0,"next_text_id":179,"final_text_id":180,"events":[{"speaker_id":2,"text_id":1725,"voice_event_id":438}],"mount_audio_id":98,"unmount_audio_id":96}
const SPANS := {"tutorial_stock":[-244274,214],"stock_clone":[-81912,30],"zero_price_preserved":[877999,16],"stock_install":[857285,73],"item_fields":[-84866,152],"category":[-84670,20],"subtype":[-84650,10],"protected":[-81574,10],"multiple_subtypes":[-84704,26],"item_transfer":[-84322,104],"quantity_commit":[-166554,146],"mount":[-137582,780],"unmount":[-138150,568],"first_free_slot":[731910,100],"cargo_refresh":[730926,112],"protected_action":[-135013,64],"equipment_check":[874532,119],"equipment_result":[874886,38],"station_check":[446081,78],"completion_dialogue":[447318,69],"mode1_counts":[1555258,28],"mode1_event":[1546642,8],"voice_table":[1560154,12032],"cursor7_dispatch":[871430,4],"cursor7_factory":[860756,38],"factory_install":[860545,16],"station_acknowledgement":[429803,1908],"item_text":[-134704,34]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, station_return: Dictionary) -> String:
	if not data is Dictionary:return "Missing station equipment declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported station equipment declarations"
	if not Return.parameters(station_return):return "Station equipment lacks its mining delivery"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Station equipment lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid station equipment provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid station equipment extent: "+key
	return ""

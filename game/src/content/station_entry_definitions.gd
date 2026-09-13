extends RefCounted
## Source-backed declarations for the first Mac station visit only.
const Values=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"first_station_entry","source_state":5,"campaign_cursor":1,"station_id":78,"system_id":15,"ship_id":0,"item_category_value_index":3,"source_ship_configuration":8,"display_ship_configuration":3,"equipment":[{"item_id":90,"slot":0,"quantity":1},{"item_id":81,"slot":1,"quantity":1}],"source_marked_item_ids":[90,81],"dialogue":{"mode":1,"events":[{"speaker_id":0,"text_id":1678},{"speaker_id":2,"text_id":1679},{"speaker_id":0,"text_id":1680},{"speaker_id":2,"text_id":1681},{"speaker_id":0,"text_id":1682},{"speaker_id":2,"text_id":1683},{"speaker_id":0,"text_id":1684},{"speaker_id":2,"text_id":1685},{"speaker_id":2,"text_id":1686},{"speaker_id":0,"text_id":1687},{"speaker_id":2,"text_id":1688},{"speaker_id":2,"text_id":1689},{"speaker_id":0,"text_id":1690},{"speaker_id":2,"text_id":1691},{"speaker_id":0,"text_id":1692},{"speaker_id":2,"text_id":1693},{"speaker_id":2,"text_id":1694},{"speaker_id":0,"text_id":1695},{"speaker_id":16,"text_id":1696}],"instruction_text_id":1696,"instruction_key_substitution":true,"acknowledgement_required":true,"previous_available":true},"mission":{"kind":11,"reward":0,"bonus":0,"station_id":78,"cursor_after_acknowledgement":2,"next_kind":154,"next_parameter":10}}
const SPANS := {"state_request":[143511,87],"loadout":[415025,251],"replace_ship":[872102,92],"ship_configuration":[729164,20],"item_mark":[-84714,10],"item_clone":[-81788,32],"item_slot":[732010,151],"item_category":[-84670,10],"story_increment":[859802,58],"story_dispatch":[860092,29],"story_slots":[871406,8],"entry_mission":[860364,70],"mining_mission":[860434,73],"mission_constructor":[399266,317],"mission_parameter":[400562,12],"trigger_call":[446081,55],"trigger_gates":[873523,172],"trigger_station":[875132,33],"trigger_dispatch":[874924,16],"trigger_slot":[875406,4],"mission_kind":[400586,10],"mission_station":[400888,10],"story_flag":[400856,16],"shown_flag":[400498,22],"dialogue_call":[447318,69],"dialogue_constructor":[-694662,109],"dialogue_reset":[-693644,164],"dialogue_offsets":[-694496,97],"speaker_read":[-692286,186],"text_read":[-691916,87],"instruction_substitution":[-691739,53],"dialogue_count":[-686416,82],"dialogue_next":[-686464,48],"dialogue_previous":[-686208,30],"manual_next":[-685001,56],"manual_completion":[427938,56],"story_completion_gate":[428261,39],"story_completion_dispatch":[428382,498],"story_completion":[428880,54],"story_advance":[429803,57],"after_advance_dispatch":[429850,1652],"reward_and_retirement":[431502,209],"reward_getter":[400774,10],"bonus_getter":[400814,10],"dialogue_sizes":[1555258,8],"dialogue_records":[1546362,152]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Values.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, session: Dictionary) -> String:
	if not data is Dictionary:return "Missing first-station declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported first-station declarations"
	if session.is_empty() or arrival.get("campaign_cursor")!=1:return "First station requires the rescue session"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "First station lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid first-station provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid first-station extent: "+key
	return ""

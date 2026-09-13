extends RefCounted
## Cached player values and source restoration after the fresh opening.
const Declarations=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"fresh_opening_to_rescue","arrival_cursor":1,"cache_minimum":0,"gamma_full":100,"gamma_sentinel":9999999,"skip_cache_refresh_cursor":95,"quest_kind":11,"quest_target_station":78,"gamma_special_quest":183,"hazard_station_min":109,"hazard_station_max":113,"hull_cache_raises_max":true,"armor_clamped":true,"shield_clamped":true,"refresh_cache_after_enter":true}
const SPANS := {"x86_64":{"new_game_cache":[401,68],"opening_hull_cache":[-880104,54],"restore":[-547863,128],"cache_refresh":[-547726,126],"gamma_reset":[-547600,72],"hull_setter":[-346146,30],"shield_setter":[-346116,44],"armor_setter":[-346072,32],"gamma_setter":[-346040,52],"constant_a47e6":[673766,4],"ship_hull":[-153672,60],"ship_shield":[-153612,10],"ship_armor":[-153682,10],"rescue_quest":[-22796,70],"gamma_context":[-4522,80],"constant_acf46":[708422,4],"gamma_return":[-4275,11],"quest_type":[-482574,9]},"armv7":{"new_game_cache":[302,40],"opening_hull_cache":[-825564,52],"restore":[-479324,104],"cache_refresh":[-479206,80],"gamma_reset":[-479126,70],"hull_setter":[-330452,20],"shield_setter":[-330432,44],"armor_setter":[-330388,20],"gamma_setter":[-330368,64],"ship_hull":[-166740,52],"ship_shield":[-166688,4],"ship_armor":[-166744,4],"rescue_quest":[-22686,66],"gamma_context":[-3788,52],"gamma_zero":[-3716,6],"gamma_return":[-3674,6],"quest_type":[-413784,4],"gamma_limit":[-330304,4]}}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Declarations.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, bytes: int, arch: String, opening: Dictionary, actors: Dictionary, arrival: Dictionary) -> String:
	if not data is Dictionary:return "Missing flight player cache capability"
	if data.is_empty():return ""
	if not parameters(data) or not SPANS.has(arch):return "Unsupported flight player cache declarations"
	if actors.get("player_initialization",{}).get("repair",{}).is_empty() or arrival.get("campaign_cursor")!=1:return "Flight cache lacks its source player/rescue context"
	if opening.get("station_id",-1)>=data.hazard_station_min and opening.get("station_id",-1)<=data.hazard_station_max:return "Rescue gamma environment is unsupported"
	var origin: Variant=opening.get("provenance",{}).get("declaration")
	if not Fonts.extent(origin,"offset","bytes",[376 if arch=="x86_64" else 284],bytes):return "Flight cache lacks its loadout anchor"
	if data.provenance.size()!=SPANS[arch].size():return "Invalid flight cache provenance"
	for key in SPANS[arch]:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[arch][key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Disconnected flight cache declaration"
	return ""

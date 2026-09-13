extends RefCounted
## Live first-flight guidance, preceding input state and station notices.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Flight=preload("res://src/content/first_flight_definitions.gd")
const VALUES := {"scope":"first_mining_station_flight","station_id":78,"system_id":15,"input_mode":"elapsed","mining_shares_guidance_history":true,"manual_commands_during_guidance":false,"manual_sample_before_neutral":true,"guidance_retains_preceding_command_flags":true,"target_notice":{"source_id":10,"prefix_text_id":535,"separator":": ","suffix_separator":" ","suffix_text_id":135,"rgb":[255,255,255]},"restricted_notice":{"source_id":21,"text_id":514,"rgb":[255,255,255]},"docking_transition_supported":false}
const SPANS := {"mining_guidance_history":[587316,29],"mining_visual_gate":[579171,40],"manual_response_sample":[565055,32],"manual_command_clear":[565902,48],"visual_neutral_return":[579664,534],"yaw_negative_gate":[595613,45],"yaw_positive_gate":[596309,45],"pitch_negative_gate":[597426,45],"pitch_positive_gate":[598385,45],"neutral_divisors":[1587874,8],"station_menu":[358266,73],"notice_dispatch":[-116996,29],"target_message":[-114776,324],"restricted_message":[-113624,20],"current_station":[858084,14],"station_name":[851326,26],"station_id":[851352,10],"separators":[1682229,5],"notice_10_entry":[-111894,4],"notice_21_entry":[-111850,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, flight: Dictionary) -> String:
	if not data is Dictionary:return "Missing station flight declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Flight.parameters(flight):return "Unsupported station flight declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Station flight lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid station flight provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid station flight extent: "+key
	return ""

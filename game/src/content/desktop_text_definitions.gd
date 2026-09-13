extends RefCounted
## Imported desktop text aliases; raw localization and voice IDs stay separate.
const Values=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"mac_desktop_text","pairs":[[16,17],[188,189],[573,574],[579,580],[582,583],[615,616],[618,619],[624,625],[627,628],[631,632],[1658,1659],[1696,1697],[1703,1704],[1708,1709],[1728,1729],[1853,1854],[592,593],[595,596],[598,599]],"lookup":"first_match_once"}
const SPANS := {"declaration":[-228336,316],"setter":[1120042,153],"lookup":[1120202,253]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Values.equal_value(data.get(key),VALUES[key]):return false
	return true

static func select_id(data: Dictionary, source_id: int) -> int:
	if not parameters(data):return source_id
	for pair in data.pairs:
		if int(pair[0])==source_id:return int(pair[1])
	return source_id

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary) -> String:
	if not data is Dictionary:return "Missing desktop text declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported desktop text declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Desktop text lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid desktop text provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid desktop text extent: "+key
	return ""

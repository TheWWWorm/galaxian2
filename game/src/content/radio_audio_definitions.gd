extends RefCounted
## Source-bound opening voice selection, display timing and language fallback.
const Numbers=preload("res://src/content/opening_definitions.gd")
const Layouts=preload("res://src/content/declaration_layouts.gd")

const VALUES := {"trigger":"radio_display","repeat":"once_per_event","spatial":false,"stop_on_radio_finish":false,"default_language":"english","override_language":"deutsch","override_language_id":1,"override_text_language":"de","category":"voice","category_max_playbacks":2,"category_overflow":"stop_oldest_immediately"}
const SPANS := {"x86_64":{"duration":[-352,32],"selection":[-212,44],"text_getter":[1153,10],"lookup":[-898405,59],"lookup_return":[-896090,14],"display_delay":[0,26],"display":[22,39],"finish":[443,90],"language":[-1347499,52],"language_init":[-1349369,16],"language_getter":[436837,13],"lookup_table":[876965,12032],"language_table":[1714117,16],"default_name":[1007365,8],"override_name":[1007373,8]},"armv7":{"duration":[-420,32],"selection":[-308,46],"text_getter":[978,4],"lookup":[-814366,40],"lookup_found":[-814216,8],"lookup_return":[-813426,10],"display_delay":[0,44],"display":[44,58],"finish":[514,132],"language":[-1624698,52],"language_init":[-1625040,12],"language_getter":[1444774,16],"lookup_table":[1834414,12032],"language_table":[2135054,8],"default_name":[1578070,8],"override_name":[1578078,8]}}

const MAC_ALTERNATE := {"duration":[-352,32],"selection":[-212,44],"text_getter":[1153,10],"lookup":[-899909,59],"lookup_return":[-897594,14],"display_delay":[0,26],"display":[22,39],"finish":[443,90],"language":[-1353935,52],"language_init":[-1355805,16],"language_getter":[435753,13],"lookup_table":[851481,12032],"language_table":[1691001,16],"default_name":[981897,8],"override_name":[981905,8]}

static func parameters(data: Variant, count: int = 23) -> bool:
	if count not in [2, 3, 5, 6, 23]: return false
	if not data is Dictionary or data.size()!=VALUES.size()+3 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		var value: Variant=data.get(key)
		var expected: Variant=VALUES[key]
		if expected is int:
			if not Numbers.integer(value,expected,expected):return false
		elif typeof(value)!=typeof(expected) or value!=expected:return false
	for key in ["event_ids","text_ids"]:
		var rows: Variant=data.get(key)
		if not rows is Array or rows.size()!=count:return false
		for id in rows:
			if not Numbers.integer(id,-1 if key=="event_ids" else 0,19999 if key=="event_ids" else 65535):return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String, dialogue: Dictionary, fonts: Dictionary, audio: Dictionary) -> String:
	if not data is Dictionary:return "Invalid opening radio voice capability"
	if data.is_empty():return ""
	var count: int=dialogue.get("events",[]).size()
	if (dialogue.get("campaign_cursor")!=0 or count!=23) and (dialogue.get("campaign_cursor")!=1 or count!=3):return "Unsupported radio voice owner"
	if not parameters(data,count) or not SPANS.has(architecture):return "Unsupported radio voice declarations"
	var origin: Variant=dialogue.get("provenance",{}).get("display_delay",{}).get("offset")
	if not Numbers.integer(origin,0,executable_bytes):return "Radio voice lacks its display timing anchor"
	var spans: Dictionary=SPANS[architecture]
	if data.provenance.size()!=spans.size():return "Invalid radio voice provenance"
	var layouts: Array=[spans]
	if architecture=="x86_64":layouts.append(MAC_ALTERNATE)
	if not Layouts.matches(data.provenance,int(origin),executable_bytes,layouts):return "Disconnected radio voice declaration"
	for key in ["duration","display_delay"]:
		if data.provenance[key]!=dialogue.get("provenance",{}).get(key):return "Radio voice timing differs from its text owner"
	var languages: Variant=fonts.get("languages",{}).get("rows",[])
	if not languages is Array or languages.size()!=16 or not languages[1] is Dictionary or languages[1].get("file")!="de.lang" or languages[1].get("language_id")!=1:return "Radio voice language differs from its text language mapping"
	if audio.is_empty():return "Radio voice lacks its dialogue or event catalogue"
	if not data.default_language in audio.languages or not data.override_language in audio.languages:return "Radio voice language is absent from the source event project"
	for i in count:
		if data.text_ids[i]!=dialogue.events[i].text_id or data.event_ids[i]>=audio.events.size():return "Radio voice belongs to another text or event catalogue"
	return ""

static func language(data: Dictionary, text_language: String) -> String:
	return data.override_language if text_language==data.override_text_language else data.default_language

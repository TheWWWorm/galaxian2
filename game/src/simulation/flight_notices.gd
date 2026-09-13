extends RefCounted
## Source timed text queue for the first mining flight. It never pauses flight,
## accepts acknowledgement, advances missions or consumes randomness.
const Definitions=preload("res://src/content/flight_notice_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Desktop=preload("res://src/content/desktop_text_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const StationFlight=preload("res://src/content/station_flight_definitions.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const TrainingStory=preload("res://src/content/combat_training_story_definitions.gd")
var error:=""
var _rules:={}
var _identity:={}
var _messages:={}
var _pending:=[]
var _elapsed:=0
var _falling:=false
var _suppressed:=false

func configure(bindings: RefCounted, library: RefCounted, construction: RefCounted, catalogues: RefCounted=null) -> bool:
	error=""
	if bindings==null or library==null or construction==null or construction.get_script()!=Construction or not Definitions.parameters(bindings.flight_notices):return reject("Flight notices require supported departure declarations")
	var entry: Dictionary=construction.snapshot()
	if entry.is_empty() or entry.get("base_content_id")!=bindings.base_content_id or entry.get("binding_id")!=bindings.binding_id or library.manifest.get("content_id")!=bindings.base_content_id or library.active_language.is_empty() or OrdinaryFlight.select(bindings,entry.get("campaign_cursor")).is_empty():return reject("Flight notices belong to another departure or language")
	var messages:={}
	var definitions: Dictionary=bindings.flight_notices.messages.duplicate(true)
	if entry.campaign_cursor==7:
		var navigation:=TrainingStory.navigation(bindings)
		if not navigation.is_empty():
			var notice: Dictionary=navigation.progress_notice
			definitions[str(int(notice.source_id))]=notice
	for key in definitions:
		var rule: Dictionary=definitions[key];var pieces:=PackedStringArray();var display_ids:=[]
		for source_id in rule.text_ids:
			var id:=Desktop.select_id(bindings.desktop_text,int(source_id))
			if id<0 or id>=library.strings.size() or library.strings[id].is_empty():return reject("A flight notice is missing in this language")
			pieces.append(library.strings[id]);display_ids.append(id)
		var rgb:=[];var text_ids:=[]
		for component in rule.rgb:rgb.append(int(component))
		for source_id in rule.text_ids:text_ids.append(int(source_id))
		messages[int(key)]={"source_id":int(key),"text_ids":text_ids,"display_text_ids":display_ids,"text":str(rule.separator).join(pieces),"rgb":rgb}
	if not bindings.station_flight.is_empty():
		var data: Dictionary=bindings.station_flight
		if not StationFlight.parameters(data) or entry.location.station_id!=int(data.station_id) or entry.location.system_id!=int(data.system_id):return reject("Station notices belong to another flight location")
		var tables: RefCounted=catalogues
		if tables==null:
			tables=Catalogues.new()
			if not tables.open(library):return reject(tables.error)
		if tables.content_id!=bindings.base_content_id or tables.tables.stations.size()<=int(data.station_id):return reject("Station notices require their own source catalogue")
		var name: Variant=tables.tables.stations[int(data.station_id)].get("name")
		if not name is String or name.is_empty():return reject("Station notice has no source name")
		var source_ids:=[int(data.target_notice.prefix_text_id),int(data.target_notice.suffix_text_id),int(data.restricted_notice.text_id)]
		var display_ids:=[]
		for source_id in source_ids:
			var id:=Desktop.select_id(bindings.desktop_text,source_id)
			if id<0 or id>=library.strings.size() or library.strings[id].is_empty():return reject("A station notice is missing in this language")
			display_ids.append(id)
		var text: String=library.strings[display_ids[0]]+str(data.target_notice.separator)+name+str(data.target_notice.suffix_separator)+library.strings[display_ids[1]]
		messages[int(data.target_notice.source_id)]={"source_id":int(data.target_notice.source_id),"text_ids":source_ids.slice(0,2),"display_text_ids":display_ids.slice(0,2),"text":text,"rgb":data.target_notice.rgb.duplicate(),"station_id":int(data.station_id)}
		messages[int(data.restricted_notice.source_id)]={"source_id":int(data.restricted_notice.source_id),"text_ids":[source_ids[2]],"display_text_ids":[display_ids[2]],"text":library.strings[display_ids[2]],"rgb":data.restricted_notice.rgb.duplicate()}
	_rules=bindings.flight_notices.duplicate(true);_messages=messages
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	_pending=[];_elapsed=0;_falling=false;_suppressed=false
	return true

func enqueue(source_id: Variant) -> bool:
	error=""
	if _rules.is_empty() or not Numbers.integer(source_id,0,65534) or not _messages.has(int(source_id)):return reject("Unsupported first-flight notice")
	var message: Dictionary=_messages[int(source_id)]
	# The source compares pending localized text, excluding the previous retired
	# entry. A duplicate neither replaces its slot nor restarts the current fade.
	for pending in _pending:
		if pending.text==message.text:return true
	if _pending.size()<int(_rules.pending_capacity):_pending.append(message.duplicate(true))
	return true

func advance(milliseconds: Variant, suppressed:=false, paused:=false) -> bool:
	error=""
	if _rules.is_empty() or not Numbers.integer(milliseconds,0,int(_rules.max_frame_ms)):return reject("Invalid timed-notice frame")
	if paused:return true
	_suppressed=suppressed
	if suppressed or _pending.is_empty():return true
	_elapsed+=int(milliseconds)
	if _elapsed>=int(_rules.retire_at_ms):
		_pending.pop_front();_elapsed=0;_falling=false
	elif _elapsed>=int(_rules.falling_at_ms):_falling=true
	return true

func snapshot() -> Dictionary:
	if _rules.is_empty():return {}
	var value:=int(f32(f32(float(_elapsed)/float(_rules.fade_half_ms))*float(_rules.alpha_max)))
	if value>int(_rules.alpha_max):value=2*int(_rules.alpha_max)-value
	var result:=_identity.duplicate()
	result.merge({"pending":_pending.duplicate(true),"current":{} if _pending.is_empty() else _pending[0].duplicate(true),
		"elapsed_ms":_elapsed,"falling":_falling,"suppressed":_suppressed,"visible":not _pending.is_empty() and not _suppressed,"alpha":value&255})
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules;copy._identity=_identity;copy._messages=_messages
	copy._pending=_pending.duplicate(true);copy._elapsed=_elapsed;copy._falling=_falling;copy._suppressed=_suppressed
	return copy
func clear() -> void:error="";_rules={};_identity={};_messages={};_pending=[];_elapsed=0;_falling=false;_suppressed=false
static func f32(value: float) -> float:
	var bytes:=PackedByteArray();bytes.resize(4);bytes.encode_float(0,value);return bytes.decode_float(0)
func reject(message: String) -> bool:error=message;return false

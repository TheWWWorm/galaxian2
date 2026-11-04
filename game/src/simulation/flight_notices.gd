extends RefCounted
const Frames=preload("res://src/simulation/frame_clock.gd")
var _max_ms:=0
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
var _item_names:={}
var _pending:=[]
var _elapsed:=0
var _falling:=false
var _suppressed:=false

func configure(bindings: RefCounted, library: RefCounted, construction: RefCounted, catalogues: RefCounted=null) -> bool:
	error=""
	if bindings==null or library==null or construction==null or construction.get_script()!=Construction or not Definitions.parameters(bindings.flight_notices):return reject("Flight notices require supported departure declarations")
	var entry: Dictionary=construction.snapshot()
	if entry.is_empty() or entry.get("base_content_id")!=bindings.base_content_id or entry.get("binding_id")!=bindings.binding_id or library.manifest.get("content_id")!=bindings.base_content_id or library.active_language.is_empty() or OrdinaryFlight.for_departure(bindings,entry).is_empty():return reject("Flight notices belong to another departure or language")
	return _configure_messages(bindings,library,int(entry.campaign_cursor),entry.location,catalogues)

## Only shared flight/equipment notices are admitted here. Station warnings
## still require a native station owner; no guessed location is substituted.
func configure_selected40(bindings: RefCounted,library: RefCounted,world: RefCounted) -> bool:
	error=""
	if not _rules.is_empty() or not is_instance_of(world,load("res://src/simulation/opening_world_initialization.gd")) or bindings==null or library==null:return reject("Selected40 notices require a fresh native world and language")
	if world.npc_construction_owner()==null or not load("res://src/content/selected40_population_definitions.gd").context_valid(bindings,world.snapshot().get("selected40_context",{})):return reject("Selected40 notices lack their selected source generation")
	if not Definitions.parameters(bindings.flight_notices) or library.manifest.get("content_id")!=bindings.base_content_id or library.active_language.is_empty():return reject("Selected40 notices belong to another content or language")
	return _configure_messages(bindings,library,40,{},null)

func configure_mission(bindings: RefCounted,library: RefCounted,context: RefCounted) -> bool:
	error=""
	if not _rules.is_empty() or not is_instance_of(context,load("res://src/simulation/mission_context.gd")) or bindings==null or library==null:return reject("Mission notices require an admitted context and language")
	if not Definitions.parameters(bindings.flight_notices) or library.manifest.get("content_id")!=bindings.base_content_id or library.active_language.is_empty():return reject("Mission notices belong to another content or language")
	return _configure_messages(bindings,library,int(context.recipe().cursor),{},null)

func _configure_messages(bindings: RefCounted,library: RefCounted,cursor: int,location: Dictionary,catalogues: RefCounted) -> bool:
	var messages:={}
	var definitions: Dictionary=bindings.flight_notices.messages.duplicate(true)
	definitions["21"]={"text_ids":[514],"separator":"","rgb":[255,255,255]}
	definitions["22"]={"text_ids":[531],"separator":"","rgb":[255,255,255]}
	definitions["44"]={"text_ids":[3190],"separator":"","rgb":[255,255,255]}
	# Story dock "Transfer complete" (Hud message 3189); optional like 44.
	definitions["45"]={"text_ids":[3189],"separator":"","rgb":[255,255,255]}
	# A blown race signature: "Signature invalid" (Hud event 31, text 313).
	definitions["46"]={"text_ids":[313],"separator":"","rgb":[255,255,255]}
	# Refused story courses (Supernova passenger berths); optional like 44.
	var campaign:=load("res://src/content/valkyrie_campaign_definitions.gd")
	for need in campaign.ENTRY_REQUIREMENTS.values():
		for text in [int(need.text_id),int(need.get("free_cargo_text_id",need.text_id))]:
			definitions[str(campaign.ENTRY_NOTICE_BASE+text)]={"text_ids":[text],"separator":"","rgb":[255,255,255]}
	# Volatile cargo refuses the Khador Drive (text 601).
	var volatile_text:=int(load("res://src/content/valkyrie_world_definitions.gd").VOLATILE_GOODS.drive_text_id)
	definitions[str(campaign.ENTRY_NOTICE_BASE+volatile_text)]={"text_ids":[volatile_text],"separator":"","rgb":[255,255,255]}
	if cursor==7:
		var navigation:=TrainingStory.navigation(bindings)
		if not navigation.is_empty():
			var notice: Dictionary=navigation.progress_notice
			definitions[str(int(notice.source_id))]=notice
	for key in definitions:
		var rule: Dictionary=definitions[key];var pieces:=PackedStringArray();var display_ids:=[]
		for source_id in rule.text_ids:
			var id:=Desktop.select_id(bindings.desktop_text,int(source_id))
			if (id<0 or id>=library.strings.size() or library.strings[id].is_empty()) and (key in ["44","45"] or int(key)>=40000):pieces=PackedStringArray();break
			if id<0 or id>=library.strings.size() or library.strings[id].is_empty():return reject("A flight notice is missing in this language")
			pieces.append(library.strings[id]);display_ids.append(id)
		if pieces.is_empty():continue
		var rgb:=[];var text_ids:=[]
		for component in rule.rgb:rgb.append(int(component))
		for source_id in rule.text_ids:text_ids.append(int(source_id))
		messages[int(key)]={"source_id":int(key),"text_ids":text_ids,"display_text_ids":display_ids,"text":str(rule.separator).join(pieces),"rgb":rgb}
	for key in {"cloak_ready":305,"energy_spent":1385}:
		var text_id: int={"cloak_ready":305,"energy_spent":1385}[key]
		var display_id:=Desktop.select_id(bindings.desktop_text,text_id)
		if display_id<0 or display_id>=library.strings.size() or library.strings[display_id].is_empty():return reject("A cloak notice is missing in this language")
		messages[key]={"kind":key,"text_ids":[text_id],"display_text_ids":[display_id],"text":library.strings[display_id],"rgb":[255,255,255]}
	# Shield Injector: "-30t <text 1465>" (Hud event 0x2f). Optional text.
	var injected_id:=Desktop.select_id(bindings.desktop_text,1465)
	if injected_id>=0 and injected_id<library.strings.size() and not library.strings[injected_id].is_empty():
		messages["plasma_injected"]={"kind":"plasma_injected","text_ids":[1465],"display_text_ids":[injected_id],"text":library.strings[injected_id],"rgb":[255,255,255]}
	# Auto turret switched on/off: "<turret> <activated/deactivated>" (Hud event 0x20/0x21).
	for key in {"auto_turret_on":38,"auto_turret_off":39}:
		var ids:=[Desktop.select_id(bindings.desktop_text,207),Desktop.select_id(bindings.desktop_text,{"auto_turret_on":38,"auto_turret_off":39}[key])]
		if ids.any(func(id):return id<0 or id>=library.strings.size() or library.strings[id].is_empty()):return reject("An auto-turret notice is missing in this language")
		messages[key]={"kind":key,"text_ids":[207,38 if key=="auto_turret_on" else 39],"display_text_ids":ids,"text":library.strings[ids[0]]+" "+library.strings[ids[1]],"rgb":[255,255,255]}
	if location.get("station_id",-1)>=0 and not bindings.station_flight.is_empty():
		var data: Dictionary=bindings.station_flight
		if not StationFlight.parameters(data):return reject("Station notices require their verified declarations")
		data=data.duplicate(true);data.station_id=int(location.station_id);data.system_id=int(location.system_id)
		if location.station_id!=int(data.station_id) or location.system_id!=int(data.system_id):return reject("Station notices belong to another flight location")
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
	var item_names:={}
	if bindings.station_equipment.has("item_text_offset"):
		var tables: RefCounted=catalogues
		if tables==null:
			tables=Catalogues.new()
			if not tables.open(library):return reject(tables.error)
		for item in tables.tables.items:
			var text_id:=int(bindings.station_equipment.item_text_offset)+int(item.id)
			if text_id<0 or text_id>=library.strings.size() or library.strings[text_id].is_empty():return reject("A cargo scan item has no localized name")
			item_names[int(item.id)]={"text_id":text_id,"name":library.strings[text_id]}
	_rules=bindings.flight_notices.duplicate(true);_messages=messages;_item_names=item_names
	_max_ms=Frames.simulation_limit(bindings,int(_rules.max_frame_ms))
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	_pending=[];_elapsed=0;_falling=false;_suppressed=false
	return true

func enqueue(source_id: Variant) -> bool:
	error=""
	if _rules.is_empty() or not Numbers.integer(source_id,0,65534) or not _messages.has(int(source_id)):return reject("Unsupported first-flight notice")
	return _enqueue(_messages[int(source_id)])

func has_message(source_id: int) -> bool:return _messages.has(source_id)
func enqueue_cloak_ready() -> bool:return _enqueue(_messages.cloak_ready)
func enqueue_auto_turret(enabled: bool) -> bool:return _enqueue(_messages.auto_turret_on if enabled else _messages.auto_turret_off)
func enqueue_energy_spent(units: int) -> bool:
	if units<=0:return reject("Fuel notice requires spent energy")
	var message: Dictionary=_messages.energy_spent.duplicate(true)
	message.text="-%dt " % units+message.text
	return _enqueue(message)

func enqueue_plasma_injected(units: int) -> bool:
	if units<=0 or not _messages.has("plasma_injected"):return true
	var message: Dictionary=_messages.plasma_injected.duplicate(true)
	message.text="-%dt " % units+message.text
	return _enqueue(message)

func _enqueue(message: Dictionary) -> bool:
	# The source compares pending localized text, excluding the previous retired
	# entry. A duplicate neither replaces its slot nor restarts the current fade.
	for pending in _pending:
		if pending.text==message.text:return true
	if _pending.size()<int(_rules.pending_capacity):_pending.append(message.duplicate(true))
	return true

func advance(milliseconds: Variant, suppressed:=false, paused:=false) -> bool:
	error=""
	if _rules.is_empty() or not Numbers.integer(milliseconds,0,_max_ms):return reject("Invalid timed-notice frame")
	if paused:return true
	_suppressed=suppressed
	if suppressed or _pending.is_empty():return true
	_elapsed+=int(milliseconds)
	if _elapsed>=int(_rules.retire_at_ms):
		_pending.pop_front();_elapsed=0;_falling=false
	elif _elapsed>=int(_rules.falling_at_ms):_falling=true
	return true

## The scanner requests inspection; the encounter's cargo lifecycle owns the
## contents. A readout cannot transfer goods or change the selected actor.
func enqueue_scanner(events: Array,encounter: RefCounted) -> bool:
	for event in events:
		if event.kind=="notification":
			if not enqueue(event.source_id):return false
		elif event.kind=="cargo_scan":
			var owner: RefCounted=encounter.npc_destruction_owner(int(event.actor_id))
			var entries: Array=[] if owner==null else owner.snapshot().get("cargo",{}).get("entries",[])
			if not enqueue_scanned_cargo(entries):return false
	return true

## Caught cargo uses the same "Nt <item>" text in green (Hud::catchCargo type 2).
const CAUGHT_RGB:=[0,237,0]

func enqueue_scanned_cargo(entries: Array,rgb:=[255,255,255]) -> bool:
	error=""
	if _rules.is_empty():return reject("Configure flight notices before inspecting cargo")
	if entries.is_empty():return enqueue(22)
	# Living cargo is validated by its lifecycle. A spent first stack produces
	# no readout, and inspection never searches or alters later stacks.
	var row: Dictionary=entries[0]
	if not Numbers.integer(row.get("quantity"),0,2147483647) or not _item_names.has(row.get("item_id")):return reject("Cargo inspection lost its retained item or quantity")
	if row.quantity==0:return true
	var item: Dictionary=_item_names[row.item_id]
	var message:={"source_id":-1,"item_id":row.item_id,"quantity":row.quantity,
		"text_ids":[item.text_id],"display_text_ids":[item.text_id],
		"text":"%dt %s"%[row.quantity,item.name],"rgb":rgb.duplicate()}
	if _pending.size()<int(_rules.pending_capacity):_pending.append(message)
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
	copy._rules=_rules;copy._identity=_identity;copy._messages=_messages;copy._item_names=_item_names
	copy._pending=_pending.duplicate(true);copy._elapsed=_elapsed;copy._falling=_falling;copy._suppressed=_suppressed
	copy._max_ms=_max_ms;return copy
func clear() -> void:_max_ms=0;error="";_rules={};_identity={};_messages={};_item_names={};_pending=[];_elapsed=0;_falling=false;_suppressed=false
static func f32(value: float) -> float:
	var bytes:=PackedByteArray();bytes.resize(4);bytes.encode_float(0,value);return bytes.decode_float(0)
func reject(message: String) -> bool:error=message;return false

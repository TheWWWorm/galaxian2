extends RefCounted
## Shared preparation for the recovered opening's baseline radio layout.
## This is an explicit verified fixture, not automatic source device detection.
const Metrics = preload("res://src/content/image_font.gd")
const Layout = preload("res://src/presentation/source_text_layout.gd")
const Definitions = preload("res://src/content/dialogue_definitions.gd")
const Portraits = preload("res://src/presentation/portrait_compositor.gd")
const Travel = preload("res://src/content/mido_travel_definitions.gd")
const ContractWorld = preload("res://src/content/contract_world_definitions.gd")
const LocalRadio = preload("res://src/simulation/local_traffic_radio.gd")
var error := ""
var line_counts := []
var speakers := {}
var portrait_diagnostics := {}
var _local_identity := {}
var _local_rules := {}
var _library: RefCounted
var _bindings: RefCounted
var _visuals: RefCounted
var _portraits := {}

func prepare(library: RefCounted, bindings: RefCounted, visuals: RefCounted = null, campaign_cursor: int = 0) -> bool:
	error="";line_counts=[];speakers={};portrait_diagnostics={}
	_clear_local()
	if library==null or bindings==null:return fail("Open imported content and resource bindings first")
	var dialogue: Dictionary=Definitions.select(bindings,campaign_cursor)
	if not Definitions.valid_parameters(dialogue,campaign_cursor):return fail("Scene radio declarations are unavailable")
	var layout:=prepare_layout(library,bindings)
	if layout==null:return false
	var counts := [];var resolved := {};var diagnostics := {}
	var composer := Portraits.new()
	for event in dialogue.events:
		var text_id := int(event.text_id)
		if text_id<0 or text_id>=library.strings.size():return fail("Opening text is outside the selected language")
		var lines: Array = layout.wrap(library.strings[text_id])
		if not layout.error.is_empty():return fail(layout.error)
		counts.append(lines.size())
		var id := int(event.speaker_id)
		if resolved.has(id) or bindings.speaker_bindings.is_empty():continue
		var speaker_name: String = bindings.resolve_speaker_name(id,library)
		if not bindings.error.is_empty():return fail(bindings.error)
		resolved[id]={"name":speaker_name}
		if visuals!=null and not visuals.base_content_id.is_empty() and not bindings.portrait_layers.is_empty():
			var portrait := composer.compose(library,bindings,visuals,id,"baseline")
			if portrait.is_empty():diagnostics[id]=composer.error
			else:resolved[id].portrait=ImageTexture.create_from_image(portrait.image)
	line_counts=counts;speakers=resolved;portrait_diagnostics=diagnostics
	return true

func prepare_local_traffic(library: RefCounted, bindings: RefCounted, visuals: RefCounted,cursor: int=10) -> bool:
	error="";line_counts=[];speakers={};portrait_diagnostics={};_clear_local()
	if library==null or bindings==null or visuals==null or (Travel.journey(bindings.mido_travel,cursor).is_empty() and not ContractWorld.supports(bindings,cursor) and not (load("res://src/content/free_campaign_definitions.gd").supported(bindings.mido_travel,cursor) and load("res://src/content/free_flight_definitions.gd").available(bindings))):return fail("Local radio requires its imported content and declarations")
	if library.manifest.get("content_id")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id:return fail("Local radio resources belong to another content identity")
	var id:=int(bindings.mido_travel.traffic_combat.radio.speaker_id)
	var label: String=bindings.resolve_speaker_name(id,library)
	if not bindings.error.is_empty():return fail(bindings.error)
	speakers={id:{"name":label}}
	_local_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":cursor,"language":library.active_language}
	_local_rules=bindings.mido_travel.traffic_combat.radio.duplicate(true)
	_library=library;_bindings=bindings;_visuals=visuals
	return true

func local_speaker(snapshot: Dictionary) -> Dictionary:
	error=""
	if _local_identity.is_empty():fail("Prepare local radio resources before resolving a transmission");return {}
	for key in _local_identity:
		if snapshot.get(key)!=_local_identity[key]:error="Local radio belongs to another content or language";return {}
	var message: Variant=snapshot.get("message");var portrait: Variant=snapshot.get("portrait")
	if not message is Dictionary or not portrait is Dictionary or not LocalRadio.valid_payload(_local_rules,message) or not LocalRadio.valid_portrait(_local_rules,portrait):error="Local radio lost its source message or selected portrait";return {}
	if snapshot.get("speaker_id")!=message.speaker_id or snapshot.get("text_id")!=message.text_id or snapshot.get("text")!=_library.strings[message.text_id]:error="Local radio text differs from its selected message";return {}
	var key:=str([portrait.family,portrait.parts])
	if not _portraits.has(key):
		var composer:=Portraits.new()
		var result:=composer.compose_definition(_library,_bindings,_visuals,message.speaker_id,"baseline",portrait)
		if result.is_empty():error=composer.error;return {}
		_portraits[key]=ImageTexture.create_from_image(result.image)
	return {"name":speakers[message.speaker_id].name,"portrait":_portraits[key]}

func _clear_local() -> void:
	_local_identity={};_local_rules={};_library=null;_bindings=null;_visuals=null;_portraits={}

func prepare_layout(library: RefCounted, bindings: RefCounted) -> RefCounted:
	error=""
	var metrics:=Metrics.new();var layout:=Layout.new()
	if not metrics.open_selected(library,bindings,0):fail(metrics.error);return null
	var margin:=15 if library.active_language in ["ja","zs","zt"] else 5
	if not layout.configure_from_bindings(metrics,350,margin,bindings):fail(layout.error);return null
	return layout

func fail(message: String) -> bool:
	error=message;line_counts=[];speakers={};portrait_diagnostics={}
	_clear_local()
	return false

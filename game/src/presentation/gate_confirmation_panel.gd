extends Control
## Original travel questions and interface artwork, with desktop/touch input.
signal choice_requested(result: int)
const OriginalUI=preload("res://src/presentation/original_ui.gd")
const GateArrival=preload("res://src/content/gate_arrival_definitions.gd")
var error:=""
var _art: RefCounted
var _panel: PanelContainer
var _text: Label
var _yes: Button
var _no: Button
var _mobile:=false
var _active:=false
var _accept_result:=-1
var _map_result:=-1
var _state:={}

func _init() -> void:
	visible=false;mouse_filter=Control.MOUSE_FILTER_STOP
	_panel=PanelContainer.new();add_child(_panel)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",14);_panel.add_child(column)
	_text=Label.new();_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;column.add_child(_text)
	var buttons:=HBoxContainer.new();buttons.alignment=BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation",12);column.add_child(buttons)
	_no=Button.new();_yes=Button.new()
	for button in [_no,_yes]:button.focus_mode=Control.FOCUS_NONE;buttons.add_child(button)
	_no.pressed.connect(func():choose(_map_result));_yes.pressed.connect(func():choose(_accept_result))
	resized.connect(_relayout)
	_panel.minimum_size_changed.connect(_relayout)

func present(library: RefCounted,bindings: RefCounted,visuals: RefCounted,catalogues: RefCounted,flight: Dictionary) -> bool:
	error=""
	if not GateArrival.available(bindings) or library.manifest.get("content_id")!=bindings.base_content_id or catalogues.content_id!=bindings.base_content_id:return reject("Gate question requires matching imported content")
	for key in ["base_content_id","binding_id"]:
		if flight.get(key)!=bindings.get(key):return reject("Gate question belongs to another flight")
	var gate: Dictionary=flight.get("gate_transit",{})
	if gate.get("phase")!="confirmation":return reject("The gate is not waiting for confirmation")
	var destination: int=gate.get("course",{}).get("destination_station_id",-1)
	if not flight.get("gate_destinations",[]).has(destination):return reject("The gate destination is unavailable")
	var rules: Dictionary=bindings.mido_travel.gate_transit.confirmation
	var ids: Array=rules.text_ids
	for id in ids+[133,134]:
		if int(id)<0 or int(id)>=library.strings.size() or library.strings[int(id)].is_empty():return reject("Gate confirmation text is missing")
	if not _prepare_art(library,bindings,visuals):return false
	_accept_result=int(rules.accept_result);_map_result=int(rules.map_result)
	_text.text=library.strings[int(ids[0])]+str(rules.separators[0])+str(catalogues.tables.stations[destination].name)+str(rules.separators[1])+library.strings[int(ids[1])]
	_yes.text=library.strings[133];_no.text=library.strings[134]
	_state={"destination_station_id":destination,"text":_text.text,"text_ids":ids.duplicate()}
	visible=true;_relayout()
	return true

func present_departure(library: RefCounted,bindings: RefCounted,visuals: RefCounted,packet: Dictionary) -> bool:
	error=""
	if library.manifest.get("content_id")!=bindings.base_content_id or packet.get("base_content_id")!=bindings.base_content_id or packet.get("binding_id")!=bindings.binding_id:return reject("Departure question requires matching imported content")
	var text_id: int=int(packet.get("confirmation_text_id",-1))
	for id in [text_id,133,134]:
		if id<0 or id>=library.strings.size() or library.strings[id].is_empty():return reject("Departure confirmation text is missing")
	if not _prepare_art(library,bindings,visuals):return false
	_accept_result=1;_map_result=0
	_text.text=library.strings[text_id];_yes.text=library.strings[133];_no.text=library.strings[134]
	_state={"text":_text.text,"text_ids":[text_id]}
	visible=true;_relayout()
	return true

func _prepare_art(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> bool:
	var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language}
	if _art==null or _art.identity!=identity:
		var art:=OriginalUI.new()
		if not art.configure(library,bindings,visuals):return reject(art.error)
		_art=art;var original_theme:=Theme.new();original_theme.default_font=art.font;theme=original_theme
	return true

func choose(result: int) -> void:
	if not _active or not visible or result not in [_accept_result,_map_result]:return
	choice_requested.emit(result)

func handle_event(event: InputEvent) -> bool:
	if not visible:return false
	if not _active:return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int=event.physical_keycode if event.physical_keycode else event.keycode
		if key in [KEY_ENTER,KEY_KP_ENTER]:choose(_accept_result)
		elif key in [KEY_ESCAPE,KEY_M,KEY_BACKSPACE]:choose(_map_result)
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index==JOY_BUTTON_A:choose(_accept_result)
		elif event.button_index==JOY_BUTTON_B:choose(_map_result)
	return true

func set_active(value: bool) -> void:
	_active=value and visible
	_yes.disabled=not _active;_no.disabled=not _active

func set_mobile_layout(value: bool) -> void:
	_mobile=value;_relayout()

func _relayout() -> void:
	if not visible or _art==null:return
	_panel.add_theme_stylebox_override("panel",_art.styles[_mobile].panel)
	_text.add_theme_font_size_override("font_size",20 if _mobile else 15)
	_text.custom_minimum_size.x=minf(540 if _mobile else 400,maxf(1,size.x-72))
	for button in [_yes,_no]:
		_art.apply_button(button,_mobile);button.custom_minimum_size.x=112
	_panel.size=_panel.get_combined_minimum_size()
	_panel.position=(size-_panel.size)/2

func snapshot() -> Dictionary:return _state.duplicate(true)
func clear() -> void:
	visible=false;_active=false;_state={};error=""
	_text.text="";_yes.disabled=true;_no.disabled=true
func reject(message: String) -> bool:error=message;return false

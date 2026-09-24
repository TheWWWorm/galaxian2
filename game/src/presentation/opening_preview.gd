extends VBoxContainer
const FlightStages=preload("res://src/content/flight_stages.gd")
signal menu_requested
signal game_over_requested
## Application host for the recovered opening and its supported ordinary fight.
## Unimplemented transitions stop without completing a mission or creating a save.
const Session = preload("res://src/presentation/opening_session.gd")
const ArrivalSession = preload("res://src/presentation/arrival_session.gd")
const StationSession = preload("res://src/presentation/station_session.gd")
const FirstFlightSession = preload("res://src/presentation/first_flight_session.gd")
const StationPanel = preload("res://src/presentation/station_dialogue_panel.gd")
const EquipmentPanel = preload("res://src/presentation/station_equipment_panel.gd")
const StationShell = preload("res://src/presentation/station_shell_panel.gd")
const FlightVitals = preload("res://src/presentation/flight_vitals_overlay.gd")
const LoungePanel = preload("res://src/presentation/lounge_panel.gd")
const EquipmentDefinitions = preload("res://src/content/station_equipment_definitions.gd")
const Shopping = preload("res://src/content/ordinary_shopping_definitions.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const RadioPanel = preload("res://src/presentation/radio_panel.gd")
const OriginalUI = preload("res://src/presentation/original_ui.gd")
const Touch = preload("res://src/presentation/flight_touch_controls.gd")
const Controls = preload("res://src/input/flight_controls.gd")
const SecondaryPanel = preload("res://src/presentation/secondary_weapon_panel.gd")
const TargetFrame = preload("res://src/presentation/flight_target_frame.gd")
const NpcMarkers = preload("res://src/presentation/flight_npc_markers.gd")
const AimReticle = preload("res://src/presentation/flight_aim_reticle.gd")
const FlightActionMenu = preload("res://src/presentation/flight_action_menu.gd")
const TravelDefinitions = preload("res://src/content/mido_travel_definitions.gd")
const LocalMapPanel = preload("res://src/presentation/local_map_panel.gd")
const GateConfirmationPanel = preload("res://src/presentation/gate_confirmation_panel.gd")
const LocationCache = preload("res://src/simulation/lounge_cache.gd")
const StationGeneration = preload("res://src/content/station_generation_definitions.gd")
const StationArchive=preload("res://src/simulation/station_archive.gd")
const StationSaveFile=preload("res://src/simulation/station_save_file.gd")
# Current base-campaign run profile. Expansion activation is explicit; bundled
# files are not treated as evidence of ownership. Menu settings remain pending.
const BASE_STOCK_SETTINGS={"difficulty":0.5,"valkyrie_owned":false,"supernova_owned":false,
	"energy_availability_percent":0,"missile_availability_percent":0}
const STATION_DEPARTURE_PHASES=["ready_to_launch","combat_departure_required","local_departure_required","contracts_required","convoy_departure_required","alioth_departure_required","free_play_required"]
const PRIMARY_FLIGHT_CURSORS=([7,10,11,12,13,14,16,17]+FlightStages.FREE+FlightStages.POST_SAHI)

var _support_context: RefCounted
var _support_identity:=""
var _departure_support:={}

var library: RefCounted
var bindings: RefCounted
var visuals: RefCounted
var session: Node3D
var radio_panel: Control
var station_panel: Control
var equipment_panel: Control
var station_shell: Control
var flight_vitals: Control
var _chrome_context: Array=[]
var _touch_detected:=false
var lounge_panel: Control
var _lounge_button: Button
var _hangar_button: Button
var status: Label
var viewport: SubViewport
var _pause_button: Button
var _touch_toggle: CheckButton
var _user_paused := false
var _focused := true
var _controls := Controls.new()
var touch_overlay: Control
var target_frame: Control
var aim_reticle: Control
var npc_markers: Control
var _transition_failed := false
var _launch_button: Button
var _launch_dialog: Control
var _flight_hint: Label
var _skip_button: Button
var _launch_packet:={}
var _flight_actions: Control
var secondary_panel: Control
var _mine_button: Button
var _station_button: Button
var _map_button: Button
var _jump_button: Button
var _time_button: Button
var map_panel: Control
var flight_menu: Control
var _station_map_open:=false
var _station_course_id:=-1
var _station_map_button: Button
var gate_panel: Control
var _retry_button: Button
var _last_game_over:={}
var _locations: RefCounted
var _location_error:=""
var _save_directory:=""
var _save_file:=StationSaveFile.new()
var _save_button: Button
var _load_button: Button
var _save_notice: Label
var _mobile_layout:=false
var _player_mode:=false
var _mouse_steering:=false
var _mouse_captured:=false
var _preview_controls: Array[Control]=[]
var _menu_button: Button
const BOUNDARIES = Session.BOUNDARIES + ArrivalSession.BOUNDARIES + FirstFlightSession.BOUNDARIES + StationSession.BOUNDARIES

func _ready() -> void:
	_touch_detected=DisplayServer.is_touchscreen_available() and not ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse",false)
	var row := HFlowContainer.new();add_child(row)
	var play := Button.new();play.text="Run opening scene";play.pressed.connect(start);row.add_child(play)
	var stop := Button.new();stop.text="Stop";stop.pressed.connect(reset);row.add_child(stop)
	_preview_controls.assign([play,stop])
	_menu_button=Button.new();_menu_button.text="Menu";_menu_button.pressed.connect(func():menu_requested.emit());row.add_child(_menu_button);_menu_button.hide()
	_pause_button=Button.new();_pause_button.text="Pause";_pause_button.toggle_mode=true
	_pause_button.toggled.connect(set_user_paused);row.add_child(_pause_button)
	var touch := CheckButton.new();_touch_toggle=touch;touch.text="Touch controls";touch.button_pressed=_controls.touch_controls
	touch.toggled.connect(set_touch_controls)
	row.add_child(touch);_pause_button.visible=_controls.touch_controls
	_preview_controls.append(touch)
	_launch_button=Button.new();_launch_button.text="Depart";_launch_button.pressed.connect(request_departure);row.add_child(_launch_button)
	_hangar_button=Button.new();_hangar_button.text="Hangar";_hangar_button.pressed.connect(func():equipment_action("open"));row.add_child(_hangar_button)
	_station_map_button=Button.new();_station_map_button.text="Map";_station_map_button.pressed.connect(func():open_map());row.add_child(_station_map_button)
	_lounge_button=Button.new();_lounge_button.text="Space Lounge";_lounge_button.pressed.connect(func():contract_action("open",-1));row.add_child(_lounge_button)
	_retry_button=Button.new();_retry_button.text="Retry";_retry_button.pressed.connect(retry_transition);row.add_child(_retry_button)
	_save_button=Button.new();_save_button.text="Save";_save_button.tooltip_text="Save station (F5)";_save_button.pressed.connect(func():save_station());row.add_child(_save_button)
	_load_button=Button.new();_load_button.text="Load";_load_button.tooltip_text="Load saved station (F9)";_load_button.pressed.connect(func():load_station());row.add_child(_load_button)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(status)
	_save_notice=Label.new();_save_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_save_notice.hide();add_child(_save_notice)
	var host := Control.new();host.size_flags_vertical=Control.SIZE_EXPAND_FILL;add_child(host)
	_pause_button.reparent(host)
	_pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_pause_button.offset_left=-60;_pause_button.offset_right=-8;_pause_button.offset_top=8;_pause_button.offset_bottom=60
	var container := preload("res://src/presentation/native_scene_view.gd").new();host.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport=container.viewport
	flight_vitals=FlightVitals.new();host.add_child(flight_vitals);flight_vitals.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target_frame=TargetFrame.new();host.add_child(target_frame);target_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target_frame.set_mobile_layout(OS.has_feature("mobile"))
	aim_reticle=AimReticle.new();host.add_child(aim_reticle);aim_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	aim_reticle.set_mobile_layout(OS.has_feature("mobile"))
	npc_markers=NpcMarkers.new();host.add_child(npc_markers);npc_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	npc_markers.set_mobile_layout(OS.has_feature("mobile"))
	radio_panel=RadioPanel.new();host.add_child(radio_panel);radio_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	radio_panel.set_mobile_layout(OS.has_feature("mobile"))
	station_shell=StationShell.new();host.add_child(station_shell);station_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	station_shell.action_requested.connect(_station_shell_action)
	station_panel=StationPanel.new();host.add_child(station_panel)
	station_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);station_panel.set_mobile_layout(OS.has_feature("mobile"))
	connect_station_panel(station_panel)
	equipment_panel=EquipmentPanel.new();host.add_child(equipment_panel)
	equipment_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	equipment_panel.action_requested.connect(equipment_action)
	equipment_panel.slot_action_requested.connect(equipment_action)
	touch_overlay=Touch.new();host.add_child(touch_overlay);touch_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_overlay.steering.connect(func(command,held):_controls.set_touch_command(command,held))
	touch_overlay.firing.connect(func(held):_controls.set_touch_action("fire",held))
	_flight_actions=Control.new();_flight_actions.mouse_filter=Control.MOUSE_FILTER_IGNORE;host.add_child(_flight_actions)
	_flight_actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_mine_button=Button.new();_mine_button.text="Mine";_mine_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_mine_button)
	_station_button=Button.new();_station_button.text="Station";_station_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_station_button)
	_map_button=Button.new();_map_button.text="Map";_map_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_map_button)
	_jump_button=Button.new();_jump_button.text="Jump";_jump_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_jump_button)
	_time_button=Button.new();_time_button.text="Time";_time_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_time_button)
	for pair in [[_mine_button,"dock"],[_station_button,"autopilot"],[_map_button,"map"],[_jump_button,"jump"],[_time_button,"time"]]:
		pair[0].button_down.connect(_touch_flight_action.bind(pair[1],true))
		pair[0].button_up.connect(_touch_flight_action.bind(pair[1],false))
	_flight_actions.resized.connect(_layout_flight_overlays)
	secondary_panel=SecondaryPanel.new();host.add_child(secondary_panel);secondary_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	secondary_panel.action_requested.connect(flight_action)
	secondary_panel.selection_requested.connect(func(id):confirm_secondary_selection(id))
	secondary_panel.selection_cancelled.connect(func():close_secondary_menu())
	secondary_panel.layout_changed.connect(_layout_flight_overlays)
	secondary_panel.visibility_changed.connect(_layout_flight_overlays)
	flight_menu=FlightActionMenu.new();host.add_child(flight_menu);flight_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flight_menu.cancelled.connect(close_flight_menu);flight_menu.chosen.connect(choose_flight_menu)
	map_panel=LocalMapPanel.new();host.add_child(map_panel);map_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gate_panel=GateConfirmationPanel.new();host.add_child(gate_panel);gate_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gate_panel.choice_requested.connect(func(result):choose_gate_confirmation(result))
	lounge_panel=LoungePanel.new();host.add_child(lounge_panel);lounge_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lounge_panel.set_mobile_layout(OS.has_feature("mobile"));lounge_panel.action_requested.connect(contract_action)
	map_panel.close_requested.connect(func():close_map())
	map_panel.destination_requested.connect(func(id):confirm_map_planet(id))
	map_panel.system_requested.connect(func(id):switch_map_system(id))
	_flight_hint=Label.new();host.add_child(_flight_hint)
	_flight_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_flight_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_flight_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_flight_hint.grow_vertical=Control.GROW_DIRECTION_BEGIN;_flight_hint.offset_top=-48;_flight_hint.offset_bottom=-8
	_flight_hint.add_theme_font_size_override("font_size",14)
	_flight_hint.add_theme_color_override("font_color",Color(0.8,0.86,0.91))
	_flight_hint.add_theme_color_override("font_outline_color",Color(0,0,0,0.9))
	_flight_hint.add_theme_constant_override("outline_size",4)
	_skip_button=Button.new();host.add_child(_skip_button)
	_skip_button.text="Skip cinematic";_skip_button.visible=false
	_skip_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_button.offset_left=-224;_skip_button.offset_right=-16;_skip_button.offset_top=-76;_skip_button.offset_bottom=-24
	_skip_button.pressed.connect(skip_cinematic)
	_launch_dialog=GateConfirmationPanel.new();host.add_child(_launch_dialog)
	_launch_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_launch_dialog.choice_requested.connect(choose_departure)
	host.move_child(_pause_button,-1)
	set_mobile_layout(OS.has_feature("mobile"))
	set_touch_controls(_controls.touch_controls)
	Input.joy_connection_changed.connect(_controller_connection)
	visibility_changed.connect(_visibility_changed)
	reset()

func set_context(content: RefCounted, definitions: RefCounted, prepared_visuals: RefCounted) -> void:
	reset();library=content;bindings=definitions;visuals=prepared_visuals;_chrome_context=[]
	if library!=null and library.strings.size()>406:_launch_button.text=library.strings[406]
	if library!=null and bindings!=null and visuals!=null and touch_overlay.configure(library,bindings,visuals):
		_style_touch_buttons()
	refresh_render_mode()

func _style_touch_buttons() -> void:
	var art: Dictionary=touch_overlay.sprites
	for row in [[_mine_button,1257,1258,"Mine / Stop"],[_station_button,1212,1213,"Station autopilot"],
		[_map_button,1210,1211,"Map"],[_jump_button,1200,1201,"Jump"],[_time_button,1345,1344,"Fast Forward"],
		[_pause_button,1208,1209,"Pause / Resume"]]:
		var button: Button=row[0]
		button.text="";button.tooltip_text=row[3]
		for state in ["normal","hover","disabled"]:button.add_theme_stylebox_override(state,_touch_icon_style(art[row[1]]))
		for state in ["pressed","hover_pressed"]:button.add_theme_stylebox_override(state,_touch_icon_style(art[row[2]]))
		button.add_theme_stylebox_override("focus",OriginalUI.focus_style(true))

func _touch_icon_style(texture: Texture2D) -> StyleBoxTexture:
	var style:=StyleBoxTexture.new();style.texture=texture
	return style

func enable_saves(directory: String="user://saves") -> void:
	# The application enables persistence explicitly. Component previews and
	# ordinary test hosts never write to a player's save directory by default.
	_save_directory=directory
	refresh_render_mode()

func station_save_path() -> String:return StationSaveFile.path_for(_save_directory,bindings)

func _can_save_station(state: Dictionary={}) -> bool:
	if _save_directory.is_empty() or not StationArchive.available(bindings) or not session is StationSession:return false
	if state.is_empty():state=session.snapshot()
	return StationArchive.can_capture(state)

func save_station(announce: bool=true) -> bool:
	if not _focused or not is_visible_in_tree() or not _can_save_station():return _save_message("Finish the station conversation and close its panels before saving",false)
	var cat:=Catalogues.new()
	if not cat.open(library):return _save_message(cat.error,false)
	if not _save_file.save(station_save_path(),session.station_owner(),bindings,cat,library,session.location_owner()):return _save_message(_save_file.error,false)
	if announce:_save_message("Station saved",true)
	refresh_render_mode()
	return true

func _autosave_station() -> bool:
	return save_station(false) if _can_save_station() else true

func _save_message(message: String,success: bool) -> bool:
	if _save_notice!=null:
		_save_notice.text=message;_save_notice.modulate=Color(0.7,0.9,0.8) if success else Color(1.0,0.65,0.5);_save_notice.show()
	if not success and _player_mode:print("Station save: "+message)
	return success

func load_station(now_microseconds: int=-1) -> bool:
	if _save_directory.is_empty() or not _focused or not is_visible_in_tree():return false
	if not StationArchive.available(bindings) or library==null or visuals==null:return _save_message("Select the game's content, bindings and prepared textures before loading",false)
	var cat:=Catalogues.new()
	if not cat.open(library):return _save_message(cat.error,false)
	var document:=_save_file.load_document(station_save_path(),bindings,cat,library)
	if document.is_empty():return _save_message(_save_file.error,false)
	# Station and subsequent flight scenes prepare their own presentation.
	# Leave the current opening HUD intact until the replacement is ready.
	var now:=Time.get_ticks_usec() if now_microseconds<0 else now_microseconds
	var candidate:=StationSession.new();viewport.add_child(candidate)
	var panel:=StationPanel.new();station_panel.get_parent().add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.set_mobile_layout(_mobile_layout)
	var prepared:=candidate.configure_saved(library,bindings,visuals,document,now)
	if prepared:
		# A restored station can already satisfy a declared fitting predicate.
		# Prepare its dialogue before replacing the current application state.
		var restored: Dictionary=candidate.snapshot()
		if restored.get("campaign_conversation",false):prepared=panel.configure_campaign_visit(library,bindings,visuals,int(restored.campaign_cursor),restored.mission,true)
		else:prepared=panel.configure_station_return(library,bindings,visuals,5) if restored.campaign_cursor==6 else panel.configure_empty(library,bindings)
	if not prepared or not panel.present(candidate.snapshot()):
		var message: String=candidate.error+panel.error;panel.free();candidate.free()
		if session!=null:session.camera.make_current()
		return _save_message(message,false)
	if not candidate.activate():
		var message: String=candidate.error;panel.free();candidate.free()
		if session!=null:session.camera.make_current()
		return _save_message(message,false)
	# Every fallible restore and scene preparation completed before this commit.
	reset()
	var previous_panel:=station_panel
	session=candidate;station_panel=panel;connect_station_panel(panel);previous_panel.free()
	_locations=session.location_owner();session.camera.make_current()
	session.rebase_time(now);refresh_render_mode();present_session()
	_save_message("Recovered the previous saved station" if _save_file.recovered_backup else "Saved station loaded",true)
	return true

func reset() -> void:
	if lounge_panel!=null:lounge_panel.clear()
	cancel_departure()
	if map_panel!=null:map_panel.clear()
	if gate_panel!=null:gate_panel.clear()
	if session!=null:session.free();session=null
	_transition_failed=false
	_last_game_over={}
	if _save_notice!=null:_save_notice.hide()
	_locations=null;_location_error=""
	clear_input();_user_paused=false;_station_map_open=false;_station_course_id=-1
	if flight_menu!=null:flight_menu.close()
	if _pause_button!=null:_pause_button.set_pressed_no_signal(false)
	if _pause_button!=null:_pause_button.disabled=false
	if radio_panel!=null:radio_panel.clear()
	if station_panel!=null:station_panel.clear()
	if equipment_panel!=null:equipment_panel.clear()
	if station_shell!=null:station_shell.clear()
	if flight_vitals!=null:flight_vitals.clear()
	if target_frame!=null:target_frame.clear()
	if aim_reticle!=null:aim_reticle.clear()
	if npc_markers!=null:npc_markers.clear()
	if secondary_panel!=null:secondary_panel.clear()
	if viewport!=null:viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	if status!=null:status.text="Reconstructed opening · Mouse / arrows or left stick steer · Space / right trigger fires · Esc / Start pauses"
	refresh_render_mode()

func start() -> void:
	reset()
	if viewport==null:return
	session=Session.new();viewport.add_child(session)
	# Native desktop presentation uses the source large-display scenery setting.
	# Mobile follows physical display dimensions, not the embedded preview size.
	var screen := DisplayServer.screen_get_size()
	var mac_profile: bool = library!=null and library.manifest.get("profile",{}).get("edition")=="mac-full-hd"
	var large_display := mac_profile or not OS.has_feature("mobile") or (maxi(screen.x,screen.y)>=1024 and mini(screen.x,screen.y)>=768)
	if not session.configure(library,bindings,visuals,Time.get_ticks_usec(),0.5,null,large_display,Session.supports_player_controls(bindings),Session.supports_escape(bindings)):
		show_error(session.error);return
	var overlay_error: String=_prepare_player_overlays() if session.interactive else ""
	if not overlay_error.is_empty():show_error(overlay_error);return
	if not radio_panel.configure(bindings.base_content_id,bindings.binding_id,library.active_language,session.radio_resources.speakers):
		show_error(radio_panel.error);return
	if not radio_panel.configure_art(library,bindings,visuals):
		show_error(radio_panel.error);return
	# Loading resources consumes no simulation time.
	session.rebase_time(Time.get_ticks_usec())
	session.set_pause("hidden",not is_visible_in_tree(),Time.get_ticks_usec())
	session.set_pause("focus",not _focused,Time.get_ticks_usec())
	refresh_render_mode()
	status.text="Opening cinematic · Esc / controller Start pauses"
	if not session.radio_resources.portrait_diagnostics.is_empty():status.text+=" · Some portraits unavailable"
	var focused:=get_viewport().gui_get_focus_owner()
	if focused!=null:focused.release_focus()

func _prepare_player_overlays() -> String:
	if not target_frame.prepare(library,bindings,visuals):return target_frame.error
	if not bindings.opening_staging.get("player_aim",{}).is_empty() and not aim_reticle.prepare(library,bindings,visuals):return aim_reticle.error
	if not bindings.opening_staging.get("npc_scanner",{}).is_empty() and not npc_markers.prepare(library,bindings,visuals):return npc_markers.error
	return ""

func set_user_paused(value: bool) -> void:
	_user_paused=value;clear_input()
	release_action_focus()
	_pause_button.set_pressed_no_signal(value)
	if session!=null and session.status in ["running","gate_confirmation_required","gate_map_required"]:session.set_pause("user",value,Time.get_ticks_usec())
	refresh_render_mode()
	if value and _player_mode:menu_requested.emit()

func _visibility_changed() -> void:
	clear_input()
	if not is_visible_in_tree():cancel_departure()
	if session!=null and (session.status=="running" or session.status in BOUNDARIES):session.set_pause("hidden",not is_visible_in_tree(),Time.get_ticks_usec())
	refresh_render_mode()

func _notification(what: int) -> void:
	if what not in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_FOCUS_OUT]:return
	_focused=what==NOTIFICATION_APPLICATION_FOCUS_IN
	clear_input()
	if session!=null and (session.status=="running" or session.status in BOUNDARIES):session.set_pause("focus",not _focused,Time.get_ticks_usec())
	refresh_render_mode()

func _departure_available(cursor: int) -> bool:
	# UI availability is invariant for an opened content pack and campaign cursor.
	# Actual departure still validates its packet and all native owners.
	var identity: String="" if bindings==null else bindings.binding_id
	if _support_context!=bindings or _support_identity!=identity:
		_support_context=bindings;_support_identity=identity;_departure_support={}
	if not _departure_support.has(cursor):_departure_support[cursor]=FirstFlightSession.supported(bindings,cursor)
	return _departure_support[cursor]

func _shopping_available() -> bool:
	var identity: String="" if bindings==null else bindings.binding_id
	if _support_context!=bindings or _support_identity!=identity:
		_support_context=bindings;_support_identity=identity;_departure_support={}
	if not _departure_support.has("shopping"):_departure_support.shopping=Shopping.available(bindings)
	return _departure_support.shopping

func refresh_render_mode(state: Dictionary={}) -> void:
	if state.is_empty() and session!=null:state=session.snapshot()
	_sync_mouse_capture()
	var touch_actions:=touch_actions_enabled()
	if _pause_button!=null:_pause_button.visible=touch_actions and session!=null and (session.flight_hud_visible(state) or session.can_control())
	if _station_map_button!=null:
		_station_map_button.visible=_station_map_available(state) and not _station_map_open
		_station_map_button.disabled=session==null or session.is_paused() or not _focused
	if flight_menu!=null:flight_menu.set_active(session!=null and session._pauses.has("flight_menu") and session._pauses.size()==1 and _focused and is_visible_in_tree())
	if _menu_button!=null:_menu_button.visible=_player_mode and session is StationSession
	if _save_button!=null:
		_save_button.visible=not _save_directory.is_empty() and session is StationSession
		_save_button.disabled=not _can_save_station(state) or not _focused or not _launch_packet.is_empty()
	if _load_button!=null:
		var path:=station_save_path()
		_load_button.visible=not path.is_empty() and (session==null or session is StationSession or not _last_game_over.is_empty())
		_load_button.disabled=path.is_empty() or not _focused or not (FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"))
		_load_button.text="Retry saved game" if not _last_game_over.is_empty() else "Load"
	if _retry_button!=null:_retry_button.visible=_transition_failed and session!=null
	if _launch_button!=null:
		_launch_button.visible=session is StationSession and state.phase in STATION_DEPARTURE_PHASES and not state.get("lounge_open",false) and not state.get("hangar_open",false) and state.get("contracts",{}).get("pending_result",{}).is_empty() and _departure_available(int(state.campaign_cursor))
		_launch_button.disabled=session==null or session.is_paused() or not _focused or not _launch_packet.is_empty()
	if secondary_panel!=null:
		secondary_panel.set_interaction(session is FirstFlightSession and session.can_control() and _focused and is_visible_in_tree() and not _transition_failed,touch_actions)
		secondary_panel.set_hud_visible(session is FirstFlightSession and session.flight_hud_visible(state) and not session.map_open())
		secondary_panel.set_selection_active(session is FirstFlightSession and session.secondary_menu_active() and _focused and is_visible_in_tree() and not _transition_failed)
	if _flight_actions!=null:
		_flight_actions.visible=touch_actions and session is FirstFlightSession and session.flight_hud_visible(state) and not session.map_open()
		_mine_button.disabled=session==null or not session.can_control() or not _focused
		_station_button.disabled=_mine_button.disabled
		var local: bool=session is FirstFlightSession and not state.get("local_travel",{}).is_empty()
		_map_button.visible=local;_map_button.disabled=_mine_button.disabled
		_jump_button.visible=local and int(state.local_travel.acquired_station_id)>=0
		_jump_button.disabled=_mine_button.disabled
		var fast: Dictionary=state.get("fast_forward",{})
		_time_button.visible=not fast.is_empty()
		# Retain button-up delivery after an automatic cancellation while held.
		_time_button.disabled=_mine_button.disabled or (not fast.get("enabled",false) and not fast.get("held",false))
		var mine_label:="Stop" if session is FirstFlightSession and not state.mining_session.drill.is_empty() else "Mine"
		if touch_overlay.sprites.is_empty():_mine_button.text=mine_label
		else:_mine_button.tooltip_text=mine_label
		_layout_flight_overlays()
	if station_panel!=null:station_panel.set_active(session!=null and session is StationSession and not session.is_paused() and is_visible_in_tree() and _focused)
	if equipment_panel!=null:equipment_panel.set_active(session!=null and session is StationSession and not session.is_paused() and is_visible_in_tree() and _focused)
	if map_panel!=null:map_panel.set_active((_station_map_open and session is StationSession and session._pauses.has("map") and session._pauses.size()==1 or session is FirstFlightSession and (session.map_active() or (session.status=="gate_map_required" and session.gate_modal_active()))) and is_visible_in_tree() and _focused)
	if gate_panel!=null:gate_panel.set_active(session is FirstFlightSession and session.status=="gate_confirmation_required" and session.gate_modal_active() and is_visible_in_tree() and _focused)
	if _launch_dialog!=null:_launch_dialog.set_active(not _launch_packet.is_empty() and session is StationSession and not session.is_paused() and is_visible_in_tree() and _focused)
	if lounge_panel!=null:lounge_panel.set_active(session!=null and not session.is_paused() and is_visible_in_tree() and _focused)
	if _lounge_button!=null:
		_lounge_button.visible=_station_lounge_available(state) and not state.dialogue.visible and not state.get("lounge_open",false) and not state.get("hangar_open",false) and state.contracts.pending_result.is_empty()
		_lounge_button.disabled=not _focused or not is_visible_in_tree() or (session!=null and session.is_paused())
	if _hangar_button!=null:
		_hangar_button.visible=session is StationSession and bindings!=null and EquipmentDefinitions.parameters(bindings.station_equipment) and (state.phase=="station_equipment_required" or (state.phase=="free_play_required" and _shopping_available())) and not state.get("hangar_open",false) and not state.get("lounge_open",false) and state.get("contracts",{}).get("pending_result",{}).is_empty()
		_hangar_button.disabled=not _focused or not is_visible_in_tree() or not _launch_packet.is_empty() or (session!=null and session.is_paused())
	if touch_overlay!=null:
		var drilling: bool=session is FirstFlightSession and not state.mining_session.drill.is_empty()
		touch_overlay.set_fire_label(("Stop" if drilling else "Fire" if state.location.campaign_cursor in PRIMARY_FLIGHT_CURSORS else "Mine") if session is FirstFlightSession else "Fire")
		touch_overlay.visible=touch_actions and session!=null and session.flight_hud_visible(state)
		touch_overlay.set_active(touch_overlay.visible and session.can_control() and is_visible_in_tree() and _focused)
	if flight_vitals!=null:
		var gauges_visible: bool=session!=null and session.flight_hud_visible(state)
		if session is FirstFlightSession:gauges_visible=gauges_visible and not session.map_open() and not session.secondary_menu_open()
		flight_vitals.set_active(gauges_visible)
		flight_vitals.set_touch_inset(touch_actions and flight_vitals.visible)
	if _flight_hint!=null:
		var cinematic: bool=session is Session and session.can_skip_cinematic()
		_flight_hint.visible=_player_mode and not touch_actions and ((session is FirstFlightSession and session.can_control()) or cinematic) and _focused and is_visible_in_tree()
		if _flight_hint.visible and cinematic:
			_flight_hint.text="Skipping cinematic…" if session.cinematic_skipping() else "Enter / A  Skip cinematic"
		elif _flight_hint.visible:
			_flight_hint.text="Q  Autopilot destinations / Cancel" if state.get("station_autopilot",{}).get("active",false) else "Q  Autopilot destinations    ·    F  Dock / Mine    ·    E  Actions"
			var fast: Dictionary=state.get("fast_forward",{})
			if not fast.is_empty():
				_flight_hint.text+="    ·    Hold Tab  Fast Forward" if fast.get("enabled",false) else "    ·    Hold Tab  Fast Forward (unavailable)"
	if _skip_button!=null:
		_skip_button.visible=touch_actions and session is Session and session.can_skip_cinematic() and _focused and is_visible_in_tree()
		_skip_button.disabled=session is Session and session.cinematic_skipping()
	_layout_flight_overlays()
	_refresh_station_shell(state)
	if _player_mode and session is StationSession and (_station_map_open or state.get("dialogue",{}).get("visible",false) or state.get("hangar_open",false) or state.get("lounge_open",false) or not state.get("contracts",{}).get("pending_result",{}).is_empty()):
		for button in [_menu_button,_launch_button,_hangar_button,_lounge_button,_station_map_button,_save_button,_load_button]:button.hide()
	if status!=null and _player_mode:status.visible=_transition_failed or (not _station_map_open and not flight_menu.visible and not (session is StationSession) and not (flight_vitals!=null and flight_vitals.visible and session.can_control()))
	if _station_map_open and _save_notice!=null:_save_notice.hide()
	if viewport==null:return
	if not is_visible_in_tree():viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	elif session!=null and session.status=="running" and not session.is_paused():viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	else:viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func _prepare_chrome() -> bool:
	var context:=[library,bindings,visuals,library.active_language]
	if _chrome_context==context:return true
	if not station_shell.configure(library,bindings,visuals) or not flight_vitals.configure(library,bindings,visuals):return transition_error(station_shell.error+flight_vitals.error)
	_flight_hint.theme=flight_vitals.theme
	_chrome_context=context
	return true

func _refresh_station_shell(state: Dictionary) -> void:
	if station_shell==null:return
	if _station_map_open or not _player_mode or _chrome_context.is_empty() or not session is StationSession or state.get("dialogue",{}).get("visible",false) or state.get("hangar_open",false) or state.get("lounge_open",false) or not state.get("contracts",{}).get("pending_result",{}).is_empty():
		station_shell.clear();return
	var buttons:={"map":_station_map_button,"hangar":_hangar_button,"lounge":_lounge_button,"depart":_launch_button,"save":_save_button,"load":_load_button,"menu":_menu_button}
	var displayed:=state.duplicate();displayed.ui_actions={}
	for action in buttons:
		var button: Button=buttons[action]
		displayed.ui_actions[action]={"visible":button.visible,"enabled":not button.disabled}
	if not station_shell.present(displayed):status.text=station_shell.error;return
	station_shell.set_active(not session.is_paused() and _focused and is_visible_in_tree() and _launch_packet.is_empty())
	for button in buttons.values():button.hide()

func _station_shell_action(action: String) -> void:
	if not session is StationSession:return
	match action:
		"map":open_map()
		"hangar":equipment_action("open")
		"lounge":contract_action("open",-1)
		"depart":request_departure()
		"save":save_station()
		"load":load_station()
		"menu":menu_requested.emit()

func _sync_mouse_capture() -> void:
	var active: bool=_player_mode and _mouse_steering and not _mobile_layout and not touch_actions_enabled() and _focused and is_visible_in_tree() and session!=null and (session.can_control() or (session is FirstFlightSession and session.can_stop_mining()))
	_controls.set_mouse_active(active)
	if active==_mouse_captured:return
	_mouse_captured=active
	if DisplayServer.get_name()!="headless":Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE

func _exit_tree() -> void:
	if _mouse_captured and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if not _touch_detected and event is InputEventScreenTouch and event.pressed and event.device!=InputEvent.DEVICE_ID_EMULATION:
		_touch_detected=true;refresh_render_mode()
	# Own captured mouse input before the flight SubViewport can consume it.
	if not _mouse_captured or not _focused or not is_visible_in_tree():return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if _controls.accept(event):
			handle_action_events(_controls.take_events())
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _focused:return
	if not _launch_packet.is_empty():
		_controls.discard_modal_event(event)
		_launch_dialog.handle_event(event)
		get_viewport().set_input_as_handled();return
	# A failed transition or an unsupported boundary must still offer the menu.
	# Normal map Escape remains owned by the map below.
	if _player_mode and session!=null and (_transition_failed or session.status not in ["running","gate_confirmation_required","gate_map_required"]):
		var menu_key: bool=event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_ESCAPE
		var menu_pad: bool=event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_START
		if menu_key or menu_pad:menu_requested.emit();get_viewport().set_input_as_handled();return
	if not _save_directory.is_empty() and event is InputEventKey and event.pressed and not event.echo:
		var key: int=event.physical_keycode if event.physical_keycode else event.keycode
		if key in [KEY_F5,KEY_F9]:
			if key==KEY_F5:save_station()
			else:load_station()
			get_viewport().set_input_as_handled();return
	if session==null:return
	if _transition_failed:
		var retry_key: bool=event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode) in [KEY_ENTER,KEY_KP_ENTER]
		var retry_button: bool=event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_A
		if retry_key or retry_button:retry_transition();get_viewport().set_input_as_handled()
		return
	if session.status not in ["running","gate_confirmation_required","gate_map_required"]:return
	if flight_menu.visible:
		flight_menu.handle_event(event);get_viewport().set_input_as_handled();return
	if _station_map_open:
		map_panel.handle_event(event);get_viewport().set_input_as_handled();return
	if session is FirstFlightSession and session.secondary_menu_open():
		_controls.discard_modal_event(event)
		var resume_key: bool=_user_paused and event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_ESCAPE
		if resume_key:set_user_paused(false)
		elif event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_START:set_user_paused(not _user_paused)
		else:secondary_panel.handle_selection_event(event)
		get_viewport().set_input_as_handled();return
	if session is FirstFlightSession and (session.map_open() or session.status in ["gate_confirmation_required","gate_map_required"]):
		# The map consumes releases too, so a held flight action cannot cross the
		# modal boundary. Controller Start remains a separate user pause.
		var resume_key: bool=_user_paused and event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_ESCAPE
		if resume_key:set_user_paused(false)
		elif event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_START:set_user_paused(not _user_paused)
		elif session.status=="gate_confirmation_required":gate_panel.handle_event(event);clear_input();present_session()
		elif map_panel.handle_event(event):clear_input();present_session()
		get_viewport().set_input_as_handled();return
	var pause_key: bool = event is InputEventKey and (event.physical_keycode if event.physical_keycode else event.keycode) in [KEY_ESCAPE,KEY_P]
	var pause_button: bool = event is InputEventJoypadButton and event.button_index==JOY_BUTTON_START
	var supported:=pause_key or pause_button
	if session is Session and session.can_skip_cinematic():
		var skip_key: bool=event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode) in [KEY_ENTER,KEY_KP_ENTER]
		var skip_pad: bool=event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_A
		if skip_key or skip_pad:skip_cinematic();get_viewport().set_input_as_handled();return
	if lounge_panel.visible and not supported:
		if lounge_panel.handle_event(event):clear_input();present_session()
		get_viewport().set_input_as_handled();return
	if _station_lounge_available() and not session.is_paused() and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_L:
		contract_action("open",-1);get_viewport().set_input_as_handled();return
	if session is FirstFlightSession and not supported and session.handle_game_over_event(event):
		clear_input();present_session();get_viewport().set_input_as_handled();return
	if session is StationSession and session.snapshot().get("hangar_open",false) and not supported:return
	if session is StationSession and not session.is_paused() and event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_H and _hangar_button.visible:
		equipment_action("open");get_viewport().set_input_as_handled();return
	if (session is StationSession or (session is FirstFlightSession and session.snapshot().dialogue.visible)) and not session.is_paused() and not supported:
		var action:=""
		if event is InputEventKey and event.pressed and not event.echo:
			var key: int=event.physical_keycode if event.physical_keycode else event.keycode
			if key in [KEY_ENTER,KEY_KP_ENTER,KEY_RIGHT]:action="next"
			elif key==KEY_LEFT:action="previous"
		elif event is InputEventJoypadButton and event.pressed:
			if event.button_index==JOY_BUTTON_A:action="next"
			elif event.button_index==JOY_BUTTON_B:action="previous"
		if not action.is_empty():
			if session is FirstFlightSession:session.navigate(action);clear_input();present_session()
			elif session.snapshot().phase in STATION_DEPARTURE_PHASES and action=="next":request_departure()
			elif session.snapshot().phase=="station_equipment_required" and action=="next":equipment_action("open")
			else:station_navigation(action)
			get_viewport().set_input_as_handled();return
	if session.can_control():
		if session is FirstFlightSession:
			if event is InputEventKey:
				var key: int=event.physical_keycode if event.physical_keycode else event.keycode
				supported=supported or key in Controls.DIRECTIONS or (Controls.KEY_ACTIONS.has(key) and Controls.KEY_ACTIONS[key] in ["fire","dock","autopilot","map","jump","throttle_up","throttle_down","brake","mouse_mode","action_menu"]) or (session.secondary_available() and Controls.KEY_ACTIONS.get(key) in ["missiles","secondary_menu"]) or (session.fast_forward_available() and Controls.KEY_ACTIONS.get(key)=="time")
			elif event is InputEventJoypadButton:supported=supported or (Controls.BUTTON_ACTIONS.has(event.button_index) and Controls.BUTTON_ACTIONS[event.button_index] in ["fire","dock","autopilot","map","jump","throttle_up","throttle_down","brake","mouse_mode","action_menu"]) or (session.secondary_available() and Controls.BUTTON_ACTIONS.get(event.button_index) in ["missiles","secondary_menu"]) or (session.fast_forward_available() and Controls.BUTTON_ACTIONS.get(event.button_index)=="time")
			elif event is InputEventJoypadMotion:supported=event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y,JOY_AXIS_TRIGGER_RIGHT] or (session.secondary_available() and event.axis==JOY_AXIS_TRIGGER_LEFT)
		elif event is InputEventKey:
			var key: int=event.physical_keycode if event.physical_keycode else event.keycode
			supported=supported or key in Controls.DIRECTIONS or Controls.KEY_ACTIONS.get(key) in ["fire","brake","mouse_mode"]
		elif event is InputEventJoypadMotion:supported=event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y,JOY_AXIS_TRIGGER_RIGHT]
	elif session is FirstFlightSession and session.can_stop_mining():
		if event is InputEventKey:
			var key: int=event.physical_keycode if event.physical_keycode else event.keycode
			supported=supported or (Controls.KEY_ACTIONS.has(key) and Controls.KEY_ACTIONS[key] in ["fire","dock"])
		elif event is InputEventJoypadButton:supported=supported or (Controls.BUTTON_ACTIONS.has(event.button_index) and Controls.BUTTON_ACTIONS[event.button_index] in ["fire","dock"])
		elif event is InputEventJoypadMotion:supported=supported or event.axis==JOY_AXIS_TRIGGER_RIGHT
	if supported and _controls.accept(event):
		handle_action_events(_controls.take_events())
		get_viewport().set_input_as_handled()

func clear_input() -> void:
	_controls.clear()
	if session is FirstFlightSession:session.clear_flight_input()
	if touch_overlay!=null:touch_overlay.clear()

func set_touch_controls(enabled: bool) -> void:
	_controls.set_touch_controls(enabled)
	if _touch_toggle!=null:_touch_toggle.set_pressed_no_signal(enabled)
	release_action_focus()
	if _pause_button!=null:_pause_button.visible=touch_actions_enabled() and session is FirstFlightSession
	if touch_overlay!=null:
		if not enabled:touch_overlay.clear()
		touch_overlay.visible=touch_actions_enabled()
	refresh_render_mode()

func touch_actions_enabled() -> bool:return _touch_detected and _controls.touch_controls

func set_player_mode(enabled: bool) -> void:
	_player_mode=enabled
	for control in _preview_controls:control.visible=not enabled
	refresh_render_mode()

func apply_preferences(preferences: Dictionary) -> void:
	clear_input()
	_controls.configure_preferences(_controls.deadzone,preferences.invert_pitch,preferences.touch_controls)
	_mouse_steering=preferences.get("mouse_steering",false)
	_controls.mouse_sensitivity=preferences.get("mouse_sensitivity",1.0)
	set_touch_controls(preferences.touch_controls)

func set_mobile_layout(value: bool) -> void:
	_mobile_layout=value
	_sync_mouse_capture()
	for panel in [station_panel,equipment_panel,station_shell,flight_vitals,lounge_panel,radio_panel,target_frame,aim_reticle,npc_markers,map_panel,gate_panel,secondary_panel,_launch_dialog,flight_menu]:
		if panel!=null:panel.set_mobile_layout(value)
	if touch_overlay!=null:touch_overlay.mobile=value;touch_overlay.queue_redraw()
	for button in [_mine_button,_station_button,_map_button,_jump_button,_time_button]:
		if button!=null:button.custom_minimum_size=Vector2(56,56) if value else Vector2(42,42)
	for button in [_save_button,_load_button]:
		if button!=null:button.custom_minimum_size.y=48 if value else 0
	if session is FirstFlightSession:session.scene.set_mobile_layout(value)
	_layout_flight_overlays()

func _layout_flight_overlays() -> void:
	if _flight_actions==null or not session is FirstFlightSession or session.scene==null or session.scene.radio==null:return
	var scale_value:=1.0 if _mobile_layout else 0.75
	_flight_actions.offset_left=-244.0*scale_value;_flight_actions.offset_right=-12.0
	_flight_actions.offset_top=-192.0*scale_value;_flight_actions.offset_bottom=-12.0
	for row in [[_mine_button,Vector2(75,42)],[_station_button,Vector2(93,130)],
		[_map_button,Vector2(185,42)],[_jump_button,Vector2(25,125)],[_time_button,Vector2(132,72)]]:
		var button: Button=row[0];var extent:=Vector2.ONE*52.0*scale_value
		button.size=extent;button.position=Vector2(row[1])*scale_value-extent*0.5
	if secondary_panel!=null:secondary_panel.set_top_inset(flight_vitals.top_inset() if flight_vitals!=null else 0.0)
	session.scene.radio.set_top_inset(secondary_panel.top_inset() if secondary_panel!=null else 0.0)

func release_action_focus() -> void:
	if not is_inside_tree():return
	var focused:=get_viewport().gui_get_focus_owner()
	if focused!=null and focused in [_pause_button,_touch_toggle]:focused.release_focus()

func _controller_connection(device: int, connected: bool) -> void:
	if not connected:
		var was_active: bool=_controls.device==device
		_controls.disconnect_controller(device)
		# The pressed edge may already have left Controls for the session queue.
		# Disconnecting the active pad must not fire it on the next world frame.
		if was_active and session is FirstFlightSession:session.clear_flight_input()

func skip_cinematic() -> void:
	if not session is Session or not _focused or not is_visible_in_tree():return
	if not session.request_cinematic_skip():show_error(session.error);return
	clear_input();present_session()

func _process(_delta: float) -> void:
	_controls.advance_mouse(_delta)
	if session==null or session.status not in ["running","arrival_transition_required","station_transition_required","station_reload_required","local_arrival_transition_required","gate_confirmation_required","gate_map_required","gate_arrival_transition_required","game_over_transition_required","convoy_arrival_transition_required","sahi_arrival_transition_required","void_return_transition_required"] or _transition_failed:return
	if _station_course_id>=0 and session is FirstFlightSession and session.can_control():
		if session.select_planet(_station_course_id):_station_course_id=-1
		else:transition_error(session.error);return
	if session.status=="running":
		handle_action_events(_controls.take_events())
		var input: Dictionary=_controls.snapshot() if session.can_control() else {"command":Vector2.ZERO,"held":{"fire":false}}
		if session is FirstFlightSession and session.can_stop_mining():input.command=Controls.pointer_command(input.command)
		var accepted: bool
		if session is FirstFlightSession:accepted=session.step(Time.get_ticks_usec(),input.command,input.held.fire,_mouse_captured,input.get("strafe",0.0),input.held.get("brake",false))
		elif session is Session:accepted=session.step(Time.get_ticks_usec(),input.command,input.held.fire,input.get("strafe",0.0),input.held.get("brake",false))
		else:accepted=session.step(Time.get_ticks_usec(),input.command,input.held.fire)
		if not accepted:
			if session is FirstFlightSession:transition_error(session.error)
			else:show_error(session.error)
			return
	if session.status=="arrival_transition_required" and not _transition_failed and ArrivalSession.supported(bindings):
		if not enter_arrival(Time.get_ticks_usec()):return
	if session.status=="local_arrival_transition_required" and not _transition_failed:
		if not enter_local_arrival(Time.get_ticks_usec()):return
	if session.status=="gate_arrival_transition_required" and not _transition_failed:
		if not enter_gate_arrival(Time.get_ticks_usec()):return
	if session.status in ["sahi_arrival_transition_required","void_return_transition_required"] and not _transition_failed:
		if not enter_portal_arrival(Time.get_ticks_usec()):return
	if session.status in ["station_transition_required","station_reload_required","convoy_arrival_transition_required"] and not _transition_failed and StationSession.supported(bindings):
		if not enter_station(Time.get_ticks_usec()):return
	if session.status=="game_over_transition_required" and not session.is_paused() and _focused and is_visible_in_tree():
		enter_game_over();return
	present_session()

func connect_station_panel(panel: Control) -> void:
	panel.next_requested.connect(func():station_navigation("next"))
	panel.previous_requested.connect(func():station_navigation("previous"))

func station_navigation(action: String) -> void:
	if session==null or not session is StationSession or not _focused or not is_visible_in_tree() or session.is_paused():return
	if not session.navigate(action,station_panel):
		status.text=session.error;return
	present_session()
	if action=="next":_autosave_station()

func equipment_action(action: String, item_id: int=-1, slot_index: int=-1) -> bool:
	if not session is StationSession or not _focused or not is_visible_in_tree() or session.is_paused() or not _launch_packet.is_empty():return false
	if action=="open" and not equipment_panel.configure(library,bindings,visuals):status.text=equipment_panel.error;return false
	if not session.equipment_action(action,item_id,library,bindings,station_panel,equipment_panel,null,slot_index):
		equipment_panel.show_error(session.error);status.text=session.error;return false
	if action=="close" and session.campaign_story_ready():
		if not _begin_campaign_story():return false
	clear_input();present_session()
	if action=="close":_autosave_station()
	return true

func handle_actions(actions: Array) -> void:
	for action in actions:
		if action=="pause":set_user_paused(not _user_paused)
		elif action=="mouse_mode":
			_mouse_steering=not _mouse_steering;clear_input();_sync_mouse_capture()
		elif session is FirstFlightSession:flight_action(action)

func _touch_flight_action(action: String,down: bool) -> void:
	if _controls.set_touch_action(action,down):handle_action_events(_controls.take_events())

func handle_action_events(events: Array) -> void:
	for event in events:
		if event.pressed:
			handle_actions([event.action])
			# A pause/modal transition owns the remaining input batch.
			if session==null or not session.can_control():break
		elif session is FirstFlightSession:
			if not session.release_action(event.action):status.text=session.error;return
			present_session()

func flight_action(action: String) -> void:
	if action in ["autopilot","action_menu"]:open_flight_menu(action=="autopilot");return
	if action=="map":open_map();return
	if action=="secondary_menu":open_secondary_menu();return
	if not session is FirstFlightSession or not _focused or not is_visible_in_tree():return
	if not session.action(action):status.text=session.error;return
	present_session()

func open_secondary_menu(now_microseconds: int=-1) -> bool:
	if not session is FirstFlightSession or not _focused or not is_visible_in_tree() or _transition_failed or not session.can_open_secondary_menu():return false
	var problem:=_present_secondaries()
	if not problem.is_empty():status.text=problem;return false
	refresh_render_mode()
	if not secondary_panel.open_selection():status.text=secondary_panel.error;return false
	var now:=Time.get_ticks_usec() if now_microseconds<0 else now_microseconds
	if not session.open_secondary_menu(now):secondary_panel.close_selection();status.text=session.error;return false
	clear_input();present_session();return true

func close_secondary_menu(now_microseconds: int=-1) -> bool:
	if not session is FirstFlightSession or not _focused or not is_visible_in_tree():return false
	var now:=Time.get_ticks_usec() if now_microseconds<0 else now_microseconds
	if not session.close_secondary_menu(now):return false
	secondary_panel.close_selection();clear_input();present_session();return true

func confirm_secondary_selection(item_id: int,now_microseconds: int=-1) -> bool:
	if not session is FirstFlightSession or not _focused or not is_visible_in_tree() or _transition_failed:return false
	var choice: Dictionary=secondary_panel.selection_snapshot()
	if not choice.open or not choice.active or choice.highlighted_item_id!=item_id:return false
	var now:=Time.get_ticks_usec() if now_microseconds<0 else now_microseconds
	if not session.confirm_secondary(item_id,now):status.text=session.error;return false
	secondary_panel.close_selection();clear_input();present_session();return true

func _station_map_available(state: Dictionary={}) -> bool:
	if not session is StationSession or bindings==null:return false
	if state.is_empty():state=session.snapshot()
	if state.get("dialogue",{}).get("visible",false) or state.get("hangar_open",false) or state.get("lounge_open",false) or not state.get("contracts",{}).get("pending_result",{}).is_empty():return false
	return int(state.campaign_cursor)>=10 and not TravelDefinitions.navigation_stations(bindings.mido_travel,int(state.campaign_cursor),int(state.loadout.station_id)).is_empty()

func _station_map_observation() -> Dictionary:
	var state: Dictionary=session.snapshot().duplicate()
	var cat:=Catalogues.new()
	if not cat.open(library):return {}
	var id: int=int(state.loadout.station_id)
	state.location={"station_id":id,"system_id":int(cat.tables.stations[id].system_id)}
	state.station_map=true
	return state

func open_map(now_microseconds: int=-1) -> bool:
	if not _focused or not is_visible_in_tree():return false
	var docked: bool=_station_map_available()
	if not docked and (not session is FirstFlightSession or not session.can_open_map()):return false
	var catalogues:=Catalogues.new()
	if not catalogues.open(library):status.text=catalogues.error;return false
	var observation: Dictionary=_station_map_observation() if docked else session.snapshot()
	if not map_panel.configure(library,bindings,visuals,catalogues,observation):status.text=map_panel.error;return false
	var now:=Time.get_ticks_usec() if now_microseconds<0 else now_microseconds
	if docked:
		if not session.set_pause("map",true,now):map_panel.clear();status.text=session.error;return false
		_station_map_open=true
	elif not session.open_map(now):map_panel.clear();status.text=session.error;return false
	clear_input();present_session();return true

func close_map(now_microseconds: int=-1) -> bool:
	if not _focused or not is_visible_in_tree():return false
	var now:=Time.get_ticks_usec() if now_microseconds<0 else now_microseconds
	if _station_map_open:
		if not session is StationSession or not session.set_pause("map",false,now):return false
		_station_map_open=false
	else:
		if not session is FirstFlightSession:return false
		var closed: bool=session.close_gate_map(false,-1,now) if session.status=="gate_map_required" else session.close_map(now)
		if not closed:return false
	map_panel.clear();clear_input();present_session();return true

func open_flight_menu(autopilot: bool=true) -> bool:
	if not session is FirstFlightSession or not session.can_control() or not _focused:return false
	var state: Dictionary=session.snapshot();var rows:=[]
	if autopilot:
		if state.get("station_autopilot",{}).get("active",false):rows.append({"action":"cancel_autopilot","label":library.strings[134]})
		if not state.get("scenery",{}).get("objects",[]).is_empty():rows.append({"action":"field_autopilot","label":library.strings[538]})
		if int(state.location.station_id)>=0:rows.append({"action":"station_autopilot","label":state.station_exterior.name+" "+library.strings[135]})
	else:
		rows.append({"action":"autopilot","label":"Autopilot"})
		if session.can_open_map():rows.append({"action":"map","label":library.strings[176]})
		if session.secondary_available():rows.append({"action":"secondary_menu","label":"Secondary weapons"})
	if rows.is_empty() or not flight_menu.configure(library,bindings,visuals):return false
	if not flight_menu.present(rows,KEY_Q if autopilot else KEY_E):return false
	if not session.set_pause("flight_menu",true,Time.get_ticks_usec()):flight_menu.close();status.text=session.error;return false
	clear_input();refresh_render_mode();return true

func close_flight_menu() -> void:
	if session==null or not flight_menu.visible:return
	if not session.set_pause("flight_menu",false,Time.get_ticks_usec()):return
	flight_menu.close();clear_input();present_session()

func choose_flight_menu(action: String) -> void:
	if not flight_menu.visible or not flight_menu.snapshot().active:return
	close_flight_menu();flight_action(action)

func confirm_map_planet(station_id: int, now_microseconds: int=-1) -> bool:
	if _station_map_open:
		var choice: Dictionary=map_panel.snapshot()
		if choice.get("selected_station_id")!=station_id or not choice.get("confirmation_visible",false):return false
		_station_course_id=station_id
		return close_map(now_microseconds)
	if not session is FirstFlightSession or not _focused or not is_visible_in_tree() or map_panel.snapshot().get("selected_station_id")!=station_id or not map_panel.snapshot().get("confirmation_visible",false):return false
	if not session.map_active() and not (session.status=="gate_map_required" and session.gate_modal_active()):return false
	var now:=Time.get_ticks_usec() if now_microseconds<0 else now_microseconds
	var accepted: bool
	if session.status=="gate_map_required":accepted=session.close_gate_map(true,station_id,now)
	elif map_panel.snapshot().route_mode=="gate":accepted=session.confirm_map_gate(station_id,now)
	else:accepted=session.confirm_map_planet(station_id,now)
	if not accepted:map_panel.set_error(session.error);return false
	map_panel.clear();clear_input();present_session()
	return true

func switch_map_system(system_id: int) -> bool:
	if not session is FirstFlightSession or not _focused or not is_visible_in_tree() or not session.map_active():return false
	if map_panel.snapshot().get("confirmation_visible",false):return false
	var catalogues:=Catalogues.new()
	if not catalogues.open(library):map_panel.set_error(catalogues.error);return false
	if not map_panel.configure(library,bindings,visuals,catalogues,session.snapshot(),system_id):map_panel.set_error(map_panel.error);return false
	clear_input();present_session();return true

func choose_gate_confirmation(result: int,now_microseconds: int=-1) -> bool:
	if not session is FirstFlightSession or not _focused or not is_visible_in_tree() or not session.gate_modal_active():return false
	var now:=Time.get_ticks_usec() if now_microseconds<0 else now_microseconds
	if not session.choose_gate_confirmation(result,now):status.text=session.error;return false
	gate_panel.clear();clear_input();present_session();return true

func request_departure() -> bool:
	if not session is StationSession or not _focused or not is_visible_in_tree() or session.is_paused() or not _launch_packet.is_empty():return false
	var state: Dictionary=session.snapshot()
	if state.get("lounge_open",false) or not _departure_available(int(state.campaign_cursor)):return false
	var cat:=Catalogues.new()
	if not cat.open(library):status.text=cat.error;return false
	var packet: Dictionary=session.prepare_departure(bindings,cat)
	if packet.is_empty():status.text=session.error;return false
	if not _launch_dialog.present_departure(library,bindings,visuals,packet):status.text=_launch_dialog.error;return false
	_launch_packet=packet;clear_input()
	refresh_render_mode(state)
	return true

func choose_departure(result: int) -> void:
	if result==1:enter_first_flight(Time.get_ticks_usec())
	elif result==0:cancel_departure();refresh_render_mode()

func prepare_lounge() -> bool:
	if lounge_panel.configured_for(bindings,library.active_language):return true
	var cat:=Catalogues.new()
	if not cat.open(library):return transition_error(cat.error)
	if not lounge_panel.configure(library,bindings,visuals,cat):return transition_error(lounge_panel.error)
	return true

func _station_lounge_available(state: Dictionary={}) -> bool:
	if not session is StationSession or not session.has_contracts():return false
	if state.is_empty():state=session.snapshot()
	return state.phase in ["contracts_required","convoy_departure_required"] or (state.phase=="free_play_required" and preload("res://src/content/ordinary_contracts_definitions.gd").available(bindings))

func contract_action(action: String,id: int) -> bool:
	if session==null or not _focused or not is_visible_in_tree() or session.is_paused():return false
	if not prepare_lounge():return false
	var accepted: bool=false
	if session is StationSession:accepted=session.contract_action(action,id,lounge_panel)
	elif session is FirstFlightSession and action=="result_close":accepted=session.acknowledge_contract_result(id)
	if not accepted:lounge_panel.show_error(session.error);return false
	if session is StationSession and session.contract_story_ready():
		if not _begin_contract_story():return false
	if session is StationSession and session.campaign_story_ready():
		if not _begin_campaign_story():return false
	clear_input();present_session()
	if action in ["close","result_close"]:_autosave_station()
	return true

func _begin_contract_story() -> bool:
	return _begin_station_story(false)

func _begin_campaign_story() -> bool:
	return _begin_station_story(true)

func _begin_station_story(campaign: bool) -> bool:
	var panel:=StationPanel.new();station_panel.get_parent().add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.set_mobile_layout(OS.has_feature("mobile"))
	var state: Dictionary=session.snapshot()
	var prepared: bool=panel.configure_campaign_visit(library,bindings,visuals,int(state.campaign_cursor),state.mission,true) if campaign else panel.configure_station_return(library,bindings,visuals,13)
	if not prepared or not (session.begin_campaign_story(panel) if campaign else session.begin_contract_story(panel)):
		var problem: String=panel.error+session.error;panel.free();return transition_error(problem)
	var previous:=station_panel;station_panel=panel;connect_station_panel(panel);previous.free()
	return true

func cancel_departure() -> void:
	_launch_packet={}
	if _launch_dialog!=null:_launch_dialog.clear()
	if _launch_button!=null:_launch_button.disabled=false

func enter_first_flight(now_microseconds: int, environment_seconds: Variant=null, unix_seconds: Variant=null) -> bool:
	if _launch_packet.is_empty() or not session is StationSession or session.is_paused() or not _focused or not is_visible_in_tree():return false
	var cat:=Catalogues.new()
	if not cat.open(library) or session.prepare_departure(bindings,cat)!=_launch_packet:return transition_error("The prepared departure no longer matches this station")
	if not _autosave_station():cancel_departure();refresh_render_mode();return false
	var candidate:=FirstFlightSession.new();viewport.add_child(candidate)
	var prepared: bool
	if _launch_packet.campaign_cursor==16 or FirstFlightSession.FreeFlight.Campaign.supported(bindings.mido_travel,_launch_packet.campaign_cursor):
		var seconds:=int(Time.get_unix_time_from_system())
		var configure_flight: Callable=candidate.configure_alioth if _launch_packet.campaign_cursor==16 else candidate.configure_free
		prepared=configure_flight.call(library,bindings,visuals,session.station_owner(),now_microseconds,seconds if environment_seconds==null else int(environment_seconds),seconds if unix_seconds==null else int(unix_seconds),OS.has_feature("mobile"))
	else:prepared=candidate.configure(library,bindings,visuals,_launch_packet,true,now_microseconds,environment_seconds,unix_seconds,OS.has_feature("mobile"),session.equipment_owner(),session.contract_owner(),session.station_owner())
	if not prepared:
		var message:=candidate.error;candidate.free();session.camera.make_current();cancel_departure()
		return transition_error(message)
	return _accept_first_flight(candidate,now_microseconds)

func enter_local_arrival(now_microseconds: int, environment_seconds: Variant=null, unix_seconds: Variant=null) -> bool:
	return _enter_flight_arrival(now_microseconds,environment_seconds,unix_seconds,false)

func enter_gate_arrival(now_microseconds: int, environment_seconds: Variant=null, unix_seconds: Variant=null) -> bool:
	return _enter_flight_arrival(now_microseconds,environment_seconds,unix_seconds,true)

func enter_portal_arrival(now_microseconds: int,environment_seconds: Variant=null,unix_seconds: Variant=null) -> bool:
	if not session is FirstFlightSession or session.status not in ["sahi_arrival_transition_required","void_return_transition_required"]:return transition_error("The flight has not reached its portal transition")
	var candidate:=FirstFlightSession.new();viewport.add_child(candidate)
	var prepare: Callable=candidate.configure_sahi_arrival if session.status=="sahi_arrival_transition_required" else candidate.configure_void_return
	if not prepare.call(library,bindings,visuals,session.flight_owner(),now_microseconds,environment_seconds,unix_seconds,OS.has_feature("mobile")):
		var message:=candidate.error;candidate.free();session.camera.make_current()
		return transition_error(message)
	return _accept_first_flight(candidate,now_microseconds)

func _enter_flight_arrival(now_microseconds: int,environment_seconds: Variant,unix_seconds: Variant,gate: bool) -> bool:
	var boundary:="gate_arrival_transition_required" if gate else "local_arrival_transition_required"
	if not session is FirstFlightSession or session.status!=boundary:return transition_error("The flight has not reached its destination transition")
	var locations: RefCounted
	var contract_trip: bool=session.flight_owner().contract_owner()!=null
	if gate and not contract_trip:return transition_error("Gate arrival lost its retained career")
	var settings:=BASE_STOCK_SETTINGS.duplicate(true) if contract_trip else {}
	if contract_trip and FirstFlightSession.FreeFlight.Campaign.supported(bindings.mido_travel,session.snapshot().campaign_cursor):settings.ship_price_percent=0
	if StationGeneration.available(bindings) and not contract_trip:
		var departing: RefCounted=session.flight_owner()
		var trip: Dictionary=departing.prepare_local_arrival()
		var previous: Dictionary=departing.snapshot()
		if trip.is_empty():return transition_error(departing.error)
		locations=_prepare_locations(int(trip.station_id),previous.progress,previous.random_state,unix_seconds)
		if locations==null:return transition_error(_location_error)
	var candidate:=FirstFlightSession.new();viewport.add_child(candidate)
	var prepare: Callable=candidate.configure_gate_arrival if gate else candidate.configure_local_arrival
	if not prepare.call(library,bindings,visuals,session.flight_owner(),now_microseconds,environment_seconds,unix_seconds,OS.has_feature("mobile"),settings):
		var message:=candidate.error;candidate.free();session.camera.make_current()
		return transition_error(message)
	if contract_trip:
		var career: RefCounted=candidate.flight_owner().contract_owner()
		if career==null:career=candidate.flight_owner().convoy_career_owner()
		locations=career.location_owner()
	if not _accept_first_flight(candidate,now_microseconds):return false
	if locations!=null:_locations=locations
	return true

func _accept_first_flight(candidate: Node3D, now_microseconds: int) -> bool:
	candidate.transition_rejected.connect(transition_error)
	for reason in ["user","hidden","focus"]:
		candidate.set_pause(reason,_user_paused if reason=="user" else not is_visible_in_tree() if reason=="hidden" else not _focused,now_microseconds)
	if not candidate.activate():
		var message: String=candidate.error;candidate.free();session.camera.make_current();cancel_departure()
		return transition_error(message)
	var previous:=session;session=candidate;previous.free();cancel_departure()
	_save_notice.hide()
	station_panel.clear();radio_panel.clear();target_frame.clear();aim_reticle.clear();npc_markers.clear()
	lounge_panel.clear()
	map_panel.clear()
	gate_panel.clear()
	_transition_failed=false;_pause_button.disabled=false;clear_input();session.rebase_time(Time.get_ticks_usec())
	present_session();return true

func enter_game_over() -> bool:
	if not session is FirstFlightSession or session.status!="game_over_transition_required":return transition_error("The flight has not requested game-over exit")
	if _user_paused or not _focused or not is_visible_in_tree():return false
	var packet: Dictionary=session.prepare_game_over();var state: Dictionary=session.snapshot()
	var expected:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"source_state":1,"campaign_cursor":state.campaign_cursor}
	var rescue_failed:=false
	var failure: Dictionary=state.get("mining_objective",{}).get("campaign_failure",{})
	if not failure.is_empty():
		var visit: Dictionary=state.mining_objective.get("campaign_visit",{})
		rescue_failed=state.campaign_cursor==21 and failure==state.get("contracts",{}).get("flight",{}).get("story_failure") and failure.get("outcome")=="failed" and failure.get("source_state")==1 and failure.get("reward_credits")==0 and visit.get("phase")=="acknowledged" and visit.get("acknowledged")==true
		if rescue_failed:expected.campaign_failure=failure.duplicate(true)
	var player_failed: bool=state.get("player_destruction",{}).get("phase")=="game_over" and state.player_destruction.get("exit_requested",false)
	if packet!=expected or state.campaign_cursor not in ([2,3,4,5,7,8,10,11,12,13,14,16,17]+FlightStages.FREE+FlightStages.POST_SAHI) or state.get("boundary")!="game_over_transition_required" or not (player_failed or rescue_failed):return transition_error("Game-over exit lost its accepted source state")
	# Source state1 is the main menu, with no implicit retry or inventory change.
	var result:={"transition":packet.duplicate(true),"flight":state.duplicate(true)}
	reset();_last_game_over=result
	status.text="Game over · Retry saved game or run the opening to start again" if not station_save_path().is_empty() else "Game over · Run opening scene to start a new game"
	refresh_render_mode()
	if _player_mode:game_over_requested.emit()
	return true

func game_over_result() -> Dictionary:return _last_game_over.duplicate(true)

func enter_station(now_microseconds: int, camera_seed: int=0, unix_seconds: Variant=null) -> bool:
	var reloading: bool=session is StationSession and session.status=="station_reload_required"
	if not reloading and (session==null or not (session is ArrivalSession or session is FirstFlightSession) or session.status not in ["station_transition_required","convoy_arrival_transition_required"]):return transition_error("The flight has not reached station entry")
	var returning:=session is FirstFlightSession
	var captured: bool=returning and session.status=="convoy_arrival_transition_required"
	var alioth_return: bool=returning and session.snapshot().get("campaign_cursor")==17
	var ordinary_return: bool=returning and FirstFlightSession.FreeFlight.Campaign.supported(bindings.mido_travel,session.snapshot().get("campaign_cursor"))
	var captured_settings:=BASE_STOCK_SETTINGS.duplicate(true) if captured or alioth_return else {}
	if captured:captured_settings.ship_price_percent=0
	var seconds: Variant=int(Time.get_unix_time_from_system()) if unix_seconds==null else unix_seconds
	var packet: Dictionary={} if returning or reloading else session.prepare_station()
	if not returning and not reloading and packet.is_empty():return transition_error(session.error)
	var candidate:=StationSession.new();viewport.add_child(candidate)
	var prepared: bool
	if reloading:prepared=candidate.configure_reload(library,bindings,visuals,session.station_owner(),now_microseconds,camera_seed)
	elif returning:prepared=candidate.configure_return(library,bindings,visuals,session.flight_owner(),now_microseconds,camera_seed,captured_settings,seconds)
	else:prepared=candidate.configure(library,bindings,visuals,packet,now_microseconds,camera_seed)
	if not prepared:
		var message:=candidate.error;candidate.free();session.camera.make_current()
		return transition_error(message)
	var locations: RefCounted
	if captured or alioth_return or ordinary_return:locations=candidate.location_owner()
	elif StationGeneration.available(bindings):
		var state: Dictionary=candidate.snapshot()
		var random: Dictionary
		if reloading:random={} if _locations==null else _locations.snapshot().random
		elif returning:random=session.snapshot().random_state
		else:random=session.snapshot().scenery.random_state
		locations=_prepare_locations(int(state.loadout.station_id),state.progress,random,null)
		if locations==null or not candidate.retain_locations(locations):
			var message: String=_location_error if locations==null else candidate.error
			candidate.free();session.camera.make_current();return transition_error(message)
	var panel:=StationPanel.new();station_panel.get_parent().add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.set_mobile_layout(OS.has_feature("mobile"))
	var prepared_station: Dictionary=candidate.snapshot()
	var panel_ready: bool
	if prepared_station.get("campaign_conversation",false):panel_ready=panel.configure_campaign_visit(library,bindings,visuals,int(prepared_station.campaign_cursor),prepared_station.mission,true)
	elif prepared_station.get("contract_station",false) and not prepared_station.get("contract_conversation",false):panel_ready=panel.configure_empty(library,bindings)
	else:panel_ready=panel.configure_station_return(library,bindings,visuals,int(prepared_station.campaign_cursor)) if returning or prepared_station.get("local_conversation",false) else panel.configure(library,bindings,visuals)
	if not panel_ready or not panel.present(candidate.snapshot()):
		var message:=panel.error;panel.free();candidate.free();session.camera.make_current()
		return transition_error(message)
	candidate.set_pause("user",_user_paused,now_microseconds)
	candidate.set_pause("hidden",not is_visible_in_tree(),now_microseconds)
	candidate.set_pause("focus",not _focused,now_microseconds)
	if not candidate.activate():
		var message:=candidate.error;panel.free();candidate.free();session.camera.make_current()
		return transition_error(message)
	var previous:=session;var previous_panel:=station_panel
	session=candidate;station_panel=panel;connect_station_panel(panel)
	if locations!=null:_locations=locations
	previous.free();previous_panel.free();radio_panel.clear()
	target_frame.set_active(false);aim_reticle.clear();npc_markers.clear()
	session.rebase_time(Time.get_ticks_usec());_transition_failed=false;_pause_button.disabled=false;clear_input()
	refresh_render_mode()
	_autosave_station()
	return true

func _prepare_locations(station_id: int,progress: Dictionary,random_state: Dictionary,unix_seconds: Variant) -> RefCounted:
	_location_error=""
	var cat:=Catalogues.new()
	if not cat.open(library):_location_error=cat.error;return null
	var locations: RefCounted=current_locations()
	if locations==null:
		if station_id!=78 or progress.get("campaign_cursor")!=1:
			_location_error="The opening lost its earlier station history";return null
		locations=LocationCache.new()
		if not locations.configure(bindings):_location_error=locations.error;return null
	var context:={"station_id":station_id,"campaign_cursor":progress.get("campaign_cursor"),
		"rank":progress.get("rank"),"reputation":progress.get("reputation")}
	var seconds: Variant=int(Time.get_unix_time_from_system()) if unix_seconds==null else unix_seconds
	if not locations.select_location(bindings,cat,library,context,BASE_STOCK_SETTINGS,random_state,seconds):
		_location_error=locations.error;return null
	return locations

func current_locations() -> RefCounted:
	if session is StationSession:return session.location_owner() if session.location_owner()!=null else (null if _locations==null else _locations.fork())
	if session is FirstFlightSession:
		var contracts: RefCounted=session.flight_owner().contract_owner()
		if contracts==null:contracts=session.flight_owner().convoy_career_owner()
		if contracts!=null:return contracts.location_owner()
	return null if _locations==null else _locations.fork()

func locations_snapshot() -> Dictionary:
	var locations: RefCounted=current_locations()
	return {} if locations==null else locations.snapshot()

func enter_arrival(now_microseconds: int, unix_seconds: Variant=null) -> bool:
	if session==null or not session is Session or session.status!="arrival_transition_required":return transition_error("The opening has not reached rescue entry")
	var cat:=Catalogues.new()
	if not cat.open(library):return transition_error(cat.error)
	var packet: Dictionary=session.prepare_arrival(bindings,cat)
	if packet.is_empty():return transition_error(session.error)
	var candidate:=ArrivalSession.new();viewport.add_child(candidate)
	if not candidate.configure(library,bindings,visuals,packet,now_microseconds,unix_seconds):
		var message:=candidate.error;candidate.free();session.camera.make_current()
		return transition_error(message)
	var panel:=RadioPanel.new();radio_panel.get_parent().add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.set_mobile_layout(OS.has_feature("mobile"))
	if not panel.configure(bindings.base_content_id,bindings.binding_id,library.active_language,candidate.radio_resources.speakers,1) or not panel.configure_art(library,bindings,visuals) or not panel.present(candidate.snapshot().radio):
		var message:=panel.error;panel.free();candidate.free();session.camera.make_current()
		return transition_error(message)
	# Both worlds are prepared before replacing any committed state. Loading
	# consumes no simulation time, and each scene retains independent radio flags.
	candidate.set_pause("user",_user_paused,now_microseconds)
	candidate.set_pause("hidden",not is_visible_in_tree(),now_microseconds)
	candidate.set_pause("focus",not _focused,now_microseconds)
	if not candidate.audio.take_listener_from(session.audio):
		var message: String=candidate.audio.error;panel.free();candidate.free();session.camera.make_current()
		return transition_error(message)
	var previous:=session;var previous_panel:=radio_panel
	session=candidate;radio_panel=panel
	previous.free();previous_panel.free()
	session.camera.make_current();session.rebase_time(Time.get_ticks_usec())
	_transition_failed=false;_pause_button.disabled=false;clear_input()
	refresh_render_mode()
	return true

func transition_error(message: String) -> bool:
	_transition_failed=true;clear_input()
	if session is FirstFlightSession:session.set_pause("transition",true,Time.get_ticks_usec())
	status.text="Scene transition could not be prepared: "+message+" · Enter / controller A retries"
	if _player_mode:print(status.text)
	refresh_render_mode()
	return false

func retry_transition() -> bool:
	if not _transition_failed or session==null or not _focused or not is_visible_in_tree():return false
	var now:=Time.get_ticks_usec()
	if session.status=="arrival_transition_required":return enter_arrival(now)
	if session.status=="local_arrival_transition_required":return enter_local_arrival(now)
	if session.status=="gate_arrival_transition_required":return enter_gate_arrival(now)
	if session.status in ["sahi_arrival_transition_required","void_return_transition_required"]:return enter_portal_arrival(now)
	if session.status in ["gate_confirmation_required","gate_map_required"]:
		session.set_pause("transition",false,now);_transition_failed=false;present_session();return not _transition_failed
	if session.status in ["station_transition_required","station_reload_required","convoy_arrival_transition_required"]:return enter_station(now)
	if session.status=="game_over_transition_required":return enter_game_over()
	if session is StationSession:return request_departure()
	if session is FirstFlightSession and session.status=="running":
		if not session.present_current():return transition_error(session.scene.error)
		session.set_pause("transition",false,now);session.rebase_time(now);_transition_failed=false;present_session();return true
	return false

func _present_secondaries() -> String:
	if not session is FirstFlightSession or not session.secondary_menu_open():secondary_panel.close_selection()
	if not session is FirstFlightSession or not session.secondary_available():secondary_panel.clear_sample();return ""
	if not secondary_panel.matches_context(library,bindings,visuals) and not secondary_panel.configure(library,bindings,visuals):return secondary_panel.error
	var sample: Dictionary=session.secondary_feedback()
	if sample.is_empty():return "The equipped secondary feedback is unavailable"
	return "" if secondary_panel.present(sample) else secondary_panel.error

func present_session() -> void:
	if session==null:return
	var secondary_error:=_present_secondaries()
	if not secondary_error.is_empty():transition_error(secondary_error);return
	var state: Dictionary=session.presentation_snapshot() if session.has_method("presentation_snapshot") else session.snapshot()
	if not bindings.mido_travel.get("map",{}).get("ui",{}).is_empty() and (session is FirstFlightSession or (session is Session and session.interactive) or session is StationSession):
		if not _prepare_chrome():return
		if session is FirstFlightSession and not flight_vitals.present(state):transition_error(flight_vitals.error);return
		# Opening flight has accepted ship pools but no cargo owner. Keep its
		# scripted hull reserve as a gauge, without displaying the internal count.
		if session is Session and not flight_vitals.present(state.world_frame,false):transition_error(flight_vitals.error);return
	if session is FirstFlightSession and session.status=="gate_confirmation_required":
		if not gate_panel.visible:
			var catalogues:=Catalogues.new()
			if not catalogues.open(library):transition_error(catalogues.error);return
			if not gate_panel.present(library,bindings,visuals,catalogues,state):transition_error(gate_panel.error);return
	else:gate_panel.clear()
	if session is FirstFlightSession and session.status=="gate_map_required" and not map_panel.visible:
		var catalogues:=Catalogues.new()
		if not catalogues.open(library):transition_error(catalogues.error);return
		if not map_panel.configure(library,bindings,visuals,catalogues,state):transition_error(map_panel.error);return
	if state.get("lounge_open",false) or not state.get("contracts",{}).get("pending_result",{}).is_empty():
		if not prepare_lounge() or not lounge_panel.present(state):transition_error(lounge_panel.error);return
	else:lounge_panel.clear()
	if session is StationSession:
		if not station_panel.present(state):status.text=station_panel.error;return
		if not equipment_panel.present(state):status.text=equipment_panel.error;return
		if session.is_paused():status.text="Paused · Esc / controller Start resumes your pause"
		elif not state.conversation_started:status.text=session.station_name
		elif state.dialogue.visible:status.text=session.station_name+" · Enter / controller A continues · Left / controller B goes back · Esc / Start pauses"
		elif state.get("lounge_open",false):status.text=session.station_name+" · Space Lounge · Arrows / D-pad select · Enter / A confirms · Backspace / B returns"
		elif state.get("hangar_open",false):status.text=session.station_name+" · Hangar · Tab / controller focus navigates · Esc / Start pauses"
		elif state.phase in STATION_DEPARTURE_PHASES and _departure_available(int(state.campaign_cursor)):status.text=session.station_name+" · Depart when ready · Enter / controller A"+(" · Space Lounge: L" if state.campaign_cursor in [13,14] else " · Hangar: H" if FirstFlightSession.FreeFlight.Campaign.supported(bindings.mido_travel,state.campaign_cursor) and _shopping_available() else "")
		elif state.phase=="station_equipment_required":status.text=session.station_name+(" · Enter the hangar · Enter / controller A" if EquipmentDefinitions.parameters(bindings.station_equipment) else " · This content pack has no equipment tutorial declarations.")
		elif state.phase=="combat_departure_required":status.text=session.station_name+" · Equipment ready. The combat-training flight is still being reconstructed."
		elif state.phase=="station_reload_required":status.text=session.station_name+" · Entering station"
		elif state.phase=="station_followup_required":status.text=session.station_name+" · Training complete. The next mission is still being reconstructed."
		elif state.phase=="free_play_required":status.text=session.station_name+" · The next departure is unavailable in this content pack."
		else:status.text=session.station_name+" · The next flight is still being reconstructed."
		refresh_render_mode(state);return
	if session is FirstFlightSession:
		var station_name: String=state.get("station_exterior",{}).get("name","")
		if not session.can_control():clear_input()
		if session.map_open() or session.status=="gate_map_required":
			status.text="Map · Esc / M / controller B returns to flight" if session.map_active() or session.gate_modal_active() else "Map paused · Esc / controller Start resumes your pause"
			if map_panel.snapshot().get("system_choices",[]).size()>1:status.text+=" · System: Q / E / R1"
		elif session.secondary_menu_open():status.text="Weapons · Arrows / D-pad browse · Enter / A selects · Esc / G / B cancels" if session.secondary_menu_active() else "Weapons menu paused · Esc / controller Start resumes your pause"
		elif session.is_paused():status.text="Paused · Esc / controller Start resumes your pause"
		elif session.status=="gate_confirmation_required":status.text="Jumpgate · Enter / A accepts · Esc / B chooses another destination"
		elif state.dialogue.visible:status.text="Enter / controller A continues · Left / controller B goes back · Esc / Start pauses"
		elif session.status=="station_transition_required":status.text="Entering "+station_name
		elif state.get("player_destruction",{}).get("phase","ready")!="ready":status.text="Game over" if state.player_destruction.game_over_visible else "Your ship was destroyed · Esc / Start pauses"
		elif session.status in ["local_arrival_transition_required","gate_arrival_transition_required","sahi_arrival_transition_required","void_return_transition_required"]:status.text="Preparing destination"
		elif state.get("gate_transit",{}).get("phase")=="departing":status.text="Jumpgate transit · Esc / Start pauses"
		elif state.get("local_travel",{}).get("phase")=="launch":status.text="Travelling · Esc / Start pauses"
		elif not state.entry_released:status.text=("Arriving at " if state.get("arrival_from_station_id",-1)>=0 else "Departing ")+station_name+" · Esc / Start pauses"
		elif not state.mining_session.drill.is_empty():status.text="Keep the drill centered: Mouse / arrows / stick · Stop: F / Space / controller X"
		elif state.location.campaign_cursor in PRIMARY_FLIGHT_CURSORS:status.text="Steer: Mouse / arrows / stick · Fire: Space / right trigger · Mine / Dock: F / X · Autopilot: Q / Y · Speed: ] / /"
		else:status.text="Steer: Mouse / arrows / stick · Mine / Dock: F / X · Autopilot: Q / Y · Speed: ] / / · Cargo: %d / %d"%[state.cargo.used,state.cargo.capacity]
		if session.can_open_map():status.text+=" · Map: E → Map / L1"
		refresh_render_mode(state);return
	var hud_visible: bool=session.flight_hud_visible(state)
	if not radio_panel.present(state.radio):show_error(radio_panel.error);return
	target_frame.set_active(hud_visible)
	if not aim_reticle.present(state.world_frame.get("player_aim",{})):show_error(aim_reticle.error);return
	if not npc_markers.present(state.world_frame.get("npc_scanner",{})):show_error(npc_markers.error);return
	if not hud_visible:clear_input()
	if session.status in BOUNDARIES:
		clear_input()
		if session.status=="mission_transition_required":status.text="The first fight is over. The next mission scene is still being reconstructed."
		elif session.status=="player_death_required":status.text="Your ship was destroyed. Restart the opening to try again."
		elif session.status=="arrival_transition_required":status.text="The opening escape has ended. The arrival scene is still being reconstructed."
		elif session.status=="station_transition_required":status.text="The rescue has reached Var Hastra. Station entry is still being reconstructed."
		else:status.text="This binding pack supports the opening cinematic. Reimport bindings for the supported first fight."
		_pause_button.disabled=true
		refresh_render_mode(state)
	elif session.is_paused():status.text="Paused · Esc / controller Start resumes your pause"
	elif session.can_control():status.text="Steer: Mouse / arrows / left stick · Fire: Space / right trigger · Pause: Esc / Start"
	else:status.text=("Rescue cinematic" if session is ArrivalSession else "Opening cinematic")+" · Esc / controller Start pauses"
	refresh_render_mode(state)

func show_error(message: String) -> void:
	reset()
	status.text=message

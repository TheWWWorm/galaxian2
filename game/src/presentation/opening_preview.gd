extends VBoxContainer
## Application host for the recovered opening and its supported ordinary fight.
## Unimplemented transitions stop without completing a mission or creating a save.
const Session = preload("res://src/presentation/opening_session.gd")
const ArrivalSession = preload("res://src/presentation/arrival_session.gd")
const StationSession = preload("res://src/presentation/station_session.gd")
const FirstFlightSession = preload("res://src/presentation/first_flight_session.gd")
const StationPanel = preload("res://src/presentation/station_dialogue_panel.gd")
const EquipmentPanel = preload("res://src/presentation/station_equipment_panel.gd")
const EquipmentDefinitions = preload("res://src/content/station_equipment_definitions.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const RadioPanel = preload("res://src/presentation/radio_panel.gd")
const Touch = preload("res://src/presentation/flight_touch_controls.gd")
const Controls = preload("res://src/input/flight_controls.gd")
const TargetFrame = preload("res://src/presentation/flight_target_frame.gd")
const NpcMarkers = preload("res://src/presentation/flight_npc_markers.gd")
const AimReticle = preload("res://src/presentation/flight_aim_reticle.gd")
var library: RefCounted
var bindings: RefCounted
var visuals: RefCounted
var session: Node3D
var radio_panel: Control
var station_panel: Control
var equipment_panel: Control
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
var _launch_dialog: ConfirmationDialog
var _launch_packet:={}
var _flight_actions: HBoxContainer
var _mine_button: Button
var _station_button: Button
var _retry_button: Button
var _last_game_over:={}
const BOUNDARIES = Session.BOUNDARIES + ArrivalSession.BOUNDARIES + FirstFlightSession.BOUNDARIES

func _ready() -> void:
	var row := HFlowContainer.new();add_child(row)
	var play := Button.new();play.text="Run opening scene";play.pressed.connect(start);row.add_child(play)
	var stop := Button.new();stop.text="Stop";stop.pressed.connect(reset);row.add_child(stop)
	_pause_button=Button.new();_pause_button.text="Pause";_pause_button.toggle_mode=true
	_pause_button.toggled.connect(set_user_paused);row.add_child(_pause_button)
	var touch := CheckButton.new();_touch_toggle=touch;touch.text="Touch controls";touch.button_pressed=_controls.touch_controls
	touch.toggled.connect(set_touch_controls)
	row.add_child(touch);_pause_button.visible=_controls.touch_controls
	_launch_button=Button.new();_launch_button.text="Depart";_launch_button.pressed.connect(request_departure);row.add_child(_launch_button)
	_hangar_button=Button.new();_hangar_button.text="Hangar";_hangar_button.pressed.connect(func():equipment_action("open"));row.add_child(_hangar_button)
	_retry_button=Button.new();_retry_button.text="Retry";_retry_button.pressed.connect(retry_transition);row.add_child(_retry_button)
	_launch_dialog=ConfirmationDialog.new();_launch_dialog.title="";add_child(_launch_dialog)
	_launch_dialog.confirmed.connect(func():enter_first_flight(Time.get_ticks_usec()))
	_launch_dialog.canceled.connect(cancel_departure)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(status)
	var host := Control.new();host.size_flags_vertical=Control.SIZE_EXPAND_FILL;add_child(host)
	var container := SubViewportContainer.new();container.stretch=true;host.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport=SubViewport.new();viewport.own_world_3d=true;viewport.handle_input_locally=false
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;container.add_child(viewport)
	target_frame=TargetFrame.new();host.add_child(target_frame);target_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target_frame.set_mobile_layout(OS.has_feature("mobile"))
	aim_reticle=AimReticle.new();host.add_child(aim_reticle);aim_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	aim_reticle.set_mobile_layout(OS.has_feature("mobile"))
	npc_markers=NpcMarkers.new();host.add_child(npc_markers);npc_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	npc_markers.set_mobile_layout(OS.has_feature("mobile"))
	radio_panel=RadioPanel.new();host.add_child(radio_panel);radio_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	radio_panel.set_mobile_layout(OS.has_feature("mobile"))
	station_panel=StationPanel.new();host.add_child(station_panel)
	station_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);station_panel.set_mobile_layout(OS.has_feature("mobile"))
	connect_station_panel(station_panel)
	equipment_panel=EquipmentPanel.new();host.add_child(equipment_panel)
	equipment_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	equipment_panel.action_requested.connect(equipment_action)
	touch_overlay=Touch.new();host.add_child(touch_overlay);touch_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_overlay.steering.connect(func(command,held):_controls.set_touch_command(command,held))
	touch_overlay.firing.connect(func(held):_controls.set_touch_action("fire",held))
	_flight_actions=HBoxContainer.new();host.add_child(_flight_actions)
	_flight_actions.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);_flight_actions.grow_horizontal=Control.GROW_DIRECTION_BEGIN
	_flight_actions.offset_right=-12;_flight_actions.offset_left=-12;_flight_actions.offset_top=12
	_mine_button=Button.new();_mine_button.text="Mine";_mine_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_mine_button)
	_station_button=Button.new();_station_button.text="Station";_station_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_station_button)
	_mine_button.pressed.connect(func():flight_action("dock"));_station_button.pressed.connect(func():flight_action("autopilot"))
	set_mobile_layout(OS.has_feature("mobile"))
	set_touch_controls(_controls.touch_controls)
	Input.joy_connection_changed.connect(_controller_connection)
	visibility_changed.connect(_visibility_changed)
	reset()

func set_context(content: RefCounted, definitions: RefCounted, prepared_visuals: RefCounted) -> void:
	reset();library=content;bindings=definitions;visuals=prepared_visuals
	if library!=null and library.strings.size()>406:_launch_button.text=library.strings[406]

func reset() -> void:
	cancel_departure()
	if session!=null:session.free();session=null
	_transition_failed=false
	_last_game_over={}
	clear_input();_user_paused=false
	if _pause_button!=null:_pause_button.set_pressed_no_signal(false)
	if _pause_button!=null:_pause_button.disabled=false
	if radio_panel!=null:radio_panel.clear()
	if station_panel!=null:station_panel.clear()
	if equipment_panel!=null:equipment_panel.clear()
	if target_frame!=null:target_frame.clear()
	if aim_reticle!=null:aim_reticle.clear()
	if npc_markers!=null:npc_markers.clear()
	if viewport!=null:viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	if status!=null:status.text="Reconstructed opening · WASD / arrows or left stick steer · Space / right trigger fires · Esc / Start pauses"
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
	if session.interactive and not target_frame.prepare(library,bindings,visuals):
		show_error(target_frame.error);return
	if session.interactive and not bindings.opening_staging.get("player_aim",{}).is_empty() and not aim_reticle.prepare(library,bindings,visuals):
		show_error(aim_reticle.error);return
	if session.interactive and not bindings.opening_staging.get("npc_scanner",{}).is_empty() and not npc_markers.prepare(library,bindings,visuals):
		show_error(npc_markers.error);return
	if not radio_panel.configure(bindings.base_content_id,bindings.binding_id,library.active_language,session.radio_resources.speakers):
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

func set_user_paused(value: bool) -> void:
	_user_paused=value;clear_input()
	release_action_focus()
	_pause_button.set_pressed_no_signal(value)
	if session!=null and session.status=="running":session.set_pause("user",value,Time.get_ticks_usec())
	refresh_render_mode()

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

func refresh_render_mode() -> void:
	if _retry_button!=null:_retry_button.visible=_transition_failed and session!=null
	if _launch_button!=null:
		_launch_button.visible=session is StationSession and session.snapshot().phase=="ready_to_launch" and FirstFlightSession.supported(bindings,int(session.snapshot().campaign_cursor))
		_launch_button.disabled=session==null or session.is_paused() or not _focused or not _launch_packet.is_empty()
	if _flight_actions!=null:
		_flight_actions.visible=_controls.touch_controls and session is FirstFlightSession and session.flight_hud_visible()
		_mine_button.disabled=session==null or not session.can_control() or not _focused
		_station_button.disabled=_mine_button.disabled
		_mine_button.text="Stop" if session is FirstFlightSession and not session.snapshot().mining_session.drill.is_empty() else "Mine"
	if station_panel!=null:station_panel.set_active(session!=null and session is StationSession and not session.is_paused() and is_visible_in_tree() and _focused)
	if equipment_panel!=null:equipment_panel.set_active(session!=null and session is StationSession and not session.is_paused() and is_visible_in_tree() and _focused)
	if _hangar_button!=null:
		_hangar_button.visible=session is StationSession and bindings!=null and EquipmentDefinitions.parameters(bindings.station_equipment) and session.snapshot().phase=="station_equipment_required" and not session.snapshot().get("hangar_open",false)
		_hangar_button.disabled=not _focused or not is_visible_in_tree() or (session!=null and session.is_paused())
	if touch_overlay!=null:
		var drilling: bool=session is FirstFlightSession and not session.snapshot().mining_session.drill.is_empty()
		touch_overlay.set_fire_label(("Stop" if drilling else "Mine") if session is FirstFlightSession else "Fire")
		touch_overlay.visible=_controls.touch_controls and session!=null and session.flight_hud_visible()
		touch_overlay.set_active(touch_overlay.visible and session.can_control() and is_visible_in_tree() and _focused)
	if viewport==null:return
	if not is_visible_in_tree():viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	elif session!=null and session.status=="running" and not session.is_paused():viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	else:viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _focused or session==null:return
	if _transition_failed:
		var retry_key: bool=event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode) in [KEY_ENTER,KEY_KP_ENTER]
		var retry_button: bool=event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_A
		if retry_key or retry_button:retry_transition();get_viewport().set_input_as_handled()
		return
	if session.status!="running":return
	if not _launch_packet.is_empty():return
	var pause_key: bool = event is InputEventKey and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_ESCAPE
	var pause_button: bool = event is InputEventJoypadButton and event.button_index==JOY_BUTTON_START
	var supported:=pause_key or pause_button
	if session is FirstFlightSession and not supported and session.handle_game_over_event(event):
		clear_input();present_session();get_viewport().set_input_as_handled();return
	if session is StationSession and session.snapshot().get("hangar_open",false) and not supported:return
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
			elif session.snapshot().phase=="ready_to_launch" and action=="next":request_departure()
			elif session.snapshot().phase=="station_equipment_required" and action=="next":equipment_action("open")
			else:station_navigation(action)
			get_viewport().set_input_as_handled();return
	if session.can_control():
		if session is FirstFlightSession:
			if event is InputEventKey:
				var key: int=event.physical_keycode if event.physical_keycode else event.keycode
				supported=supported or key in Controls.DIRECTIONS or (Controls.KEY_ACTIONS.has(key) and Controls.KEY_ACTIONS[key] in ["fire","dock","autopilot","throttle_up","throttle_down"])
			elif event is InputEventJoypadButton:supported=supported or (Controls.BUTTON_ACTIONS.has(event.button_index) and Controls.BUTTON_ACTIONS[event.button_index] in ["dock","autopilot","throttle_up","throttle_down"])
			elif event is InputEventJoypadMotion:supported=event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y,JOY_AXIS_TRIGGER_RIGHT]
		elif event is InputEventKey:
			var key: int=event.physical_keycode if event.physical_keycode else event.keycode
			supported=supported or key in Controls.DIRECTIONS or key==KEY_SPACE
		elif event is InputEventJoypadMotion:supported=event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y,JOY_AXIS_TRIGGER_RIGHT]
	elif session is FirstFlightSession and session.can_stop_mining():
		if event is InputEventKey:
			var key: int=event.physical_keycode if event.physical_keycode else event.keycode
			supported=supported or (Controls.KEY_ACTIONS.has(key) and Controls.KEY_ACTIONS[key] in ["fire","dock"])
		elif event is InputEventJoypadButton:supported=supported or (Controls.BUTTON_ACTIONS.has(event.button_index) and Controls.BUTTON_ACTIONS[event.button_index] in ["fire","dock"])
		elif event is InputEventJoypadMotion:supported=supported or event.axis==JOY_AXIS_TRIGGER_RIGHT
	if supported and _controls.accept(event):
		handle_actions(_controls.take_pressed())
		get_viewport().set_input_as_handled()

func clear_input() -> void:
	_controls.clear()
	if touch_overlay!=null:touch_overlay.clear()

func set_touch_controls(enabled: bool) -> void:
	_controls.set_touch_controls(enabled)
	if _touch_toggle!=null:_touch_toggle.set_pressed_no_signal(enabled)
	release_action_focus()
	if _pause_button!=null:_pause_button.visible=enabled
	if touch_overlay!=null:
		if not enabled:touch_overlay.clear()
		touch_overlay.visible=enabled
	refresh_render_mode()

func set_mobile_layout(value: bool) -> void:
	for panel in [station_panel,equipment_panel,radio_panel,target_frame,aim_reticle,npc_markers]:
		if panel!=null:panel.set_mobile_layout(value)
	if touch_overlay!=null:touch_overlay.mobile=value;touch_overlay.queue_redraw()
	for button in [_mine_button,_station_button]:
		if button!=null:button.custom_minimum_size=Vector2(88,48) if value else Vector2(68,30)
	if session is FirstFlightSession:session.scene.set_mobile_layout(value)

func release_action_focus() -> void:
	if not is_inside_tree():return
	var focused:=get_viewport().gui_get_focus_owner()
	if focused!=null and focused in [_pause_button,_touch_toggle]:focused.release_focus()

func _controller_connection(device: int, connected: bool) -> void:
	if not connected:_controls.disconnect_controller(device)

func _process(_delta: float) -> void:
	if session==null or session.status not in ["running","arrival_transition_required","station_transition_required","game_over_transition_required"] or _transition_failed:return
	if session.status=="running":
		handle_actions(_controls.take_pressed())
		var input: Dictionary=_controls.snapshot() if session.can_control() else {"command":Vector2.ZERO,"held":{"fire":false}}
		if not session.step(Time.get_ticks_usec(),input.command,input.held.fire):
			if session is FirstFlightSession:transition_error(session.error)
			else:show_error(session.error)
			return
	if session.status=="arrival_transition_required" and not _transition_failed and ArrivalSession.supported(bindings):
		if not enter_arrival(Time.get_ticks_usec()):return
	if session.status=="station_transition_required" and not _transition_failed and StationSession.supported(bindings):
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

func equipment_action(action: String, item_id: int=-1) -> bool:
	if not session is StationSession or not _focused or not is_visible_in_tree() or session.is_paused():return false
	if action=="open" and not equipment_panel.configure(library,bindings):status.text=equipment_panel.error;return false
	if not session.equipment_action(action,item_id,library,bindings,station_panel,equipment_panel):
		equipment_panel.show_error(session.error);status.text=session.error;return false
	clear_input();present_session()
	return true

func handle_actions(actions: Array) -> void:
	for action in actions:
		if action=="pause":set_user_paused(not _user_paused)
		elif session is FirstFlightSession:flight_action(action)

func flight_action(action: String) -> void:
	if not session is FirstFlightSession or not _focused or not is_visible_in_tree():return
	if not session.action(action):status.text=session.error;return
	present_session()

func request_departure() -> bool:
	if not session is StationSession or not _focused or not is_visible_in_tree() or session.is_paused() or not FirstFlightSession.supported(bindings,int(session.snapshot().campaign_cursor)):return false
	var cat:=Catalogues.new()
	if not cat.open(library):status.text=cat.error;return false
	var packet: Dictionary=session.prepare_departure(bindings,cat)
	if packet.is_empty():status.text=session.error;return false
	var text_id:=int(packet.confirmation_text_id)
	if text_id>=library.strings.size():status.text="Departure confirmation is unavailable";return false
	_launch_packet=packet;clear_input()
	_launch_dialog.dialog_text=library.strings[text_id]
	_launch_dialog.get_ok_button().text=library.strings[133];_launch_dialog.get_cancel_button().text=library.strings[134]
	_launch_dialog.popup_centered(Vector2i(360,140));refresh_render_mode()
	return true

func cancel_departure() -> void:
	_launch_packet={}
	if _launch_dialog!=null:_launch_dialog.hide()
	if _launch_button!=null:_launch_button.disabled=false

func enter_first_flight(now_microseconds: int, environment_seconds: Variant=null, unix_seconds: Variant=null) -> bool:
	if _launch_packet.is_empty() or not session is StationSession or session.is_paused() or not _focused or not is_visible_in_tree():return false
	var cat:=Catalogues.new()
	if not cat.open(library) or session.prepare_departure(bindings,cat)!=_launch_packet:return transition_error("The prepared departure no longer matches this station")
	var candidate:=FirstFlightSession.new();viewport.add_child(candidate)
	if not candidate.configure(library,bindings,visuals,_launch_packet,true,now_microseconds,environment_seconds,unix_seconds,OS.has_feature("mobile")):
		var message:=candidate.error;candidate.free();session.camera.make_current();cancel_departure()
		return transition_error(message)
	candidate.transition_rejected.connect(transition_error)
	for reason in ["user","hidden","focus"]:
		candidate.set_pause(reason,_user_paused if reason=="user" else not is_visible_in_tree() if reason=="hidden" else not _focused,now_microseconds)
	if not candidate.activate():
		var message:=candidate.error;candidate.free();session.camera.make_current();cancel_departure()
		return transition_error(message)
	var previous:=session;session=candidate;previous.free();cancel_departure()
	station_panel.clear();radio_panel.clear();target_frame.clear();aim_reticle.clear();npc_markers.clear()
	_transition_failed=false;_pause_button.disabled=false;clear_input();session.rebase_time(Time.get_ticks_usec())
	present_session();return true

func enter_game_over() -> bool:
	if not session is FirstFlightSession or session.status!="game_over_transition_required":return transition_error("The flight has not requested game-over exit")
	if _user_paused or not _focused or not is_visible_in_tree():return false
	var packet: Dictionary=session.prepare_game_over();var state: Dictionary=session.snapshot()
	var expected:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"source_state":1,"campaign_cursor":state.campaign_cursor}
	if packet!=expected or state.campaign_cursor not in [4,5] or state.get("boundary")!="game_over_transition_required" or state.get("player_destruction",{}).get("phase")!="game_over" or not state.player_destruction.get("exit_requested",false):return transition_error("Game-over exit lost its accepted source state")
	# Source state1 is the main menu, with no implicit retry or inventory change.
	# The current remake launcher remains its frontend until the full menu is built.
	var result:={"transition":packet.duplicate(true),"flight":state.duplicate(true)}
	reset();_last_game_over=result
	status.text="Game over · Run opening scene to start a new game"
	return true

func game_over_result() -> Dictionary:return _last_game_over.duplicate(true)

func enter_station(now_microseconds: int, camera_seed: int=0) -> bool:
	if session==null or not (session is ArrivalSession or session is FirstFlightSession) or session.status!="station_transition_required":return transition_error("The flight has not reached station entry")
	var returning:=session is FirstFlightSession
	var packet: Dictionary={} if returning else session.prepare_station()
	if not returning and packet.is_empty():return transition_error(session.error)
	var candidate:=StationSession.new();viewport.add_child(candidate)
	var prepared: bool=candidate.configure_return(library,bindings,visuals,session.flight_owner(),now_microseconds,camera_seed) if returning else candidate.configure(library,bindings,visuals,packet,now_microseconds,camera_seed)
	if not prepared:
		var message:=candidate.error;candidate.free();session.camera.make_current()
		return transition_error(message)
	var panel:=StationPanel.new();station_panel.get_parent().add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.set_mobile_layout(OS.has_feature("mobile"))
	var panel_ready: bool=panel.configure_station_return(library,bindings,visuals,int(candidate.snapshot().campaign_cursor)) if returning else panel.configure(library,bindings,visuals)
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
	previous.free();previous_panel.free();radio_panel.clear()
	target_frame.set_active(false);aim_reticle.clear();npc_markers.clear()
	session.rebase_time(Time.get_ticks_usec());_transition_failed=false;_pause_button.disabled=false;clear_input()
	refresh_render_mode()
	return true

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
	if not panel.configure(bindings.base_content_id,bindings.binding_id,library.active_language,candidate.radio_resources.speakers,1) or not panel.present(candidate.snapshot().radio):
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
	refresh_render_mode()
	return false

func retry_transition() -> bool:
	if not _transition_failed or session==null or not _focused or not is_visible_in_tree():return false
	var now:=Time.get_ticks_usec()
	if session.status=="arrival_transition_required":return enter_arrival(now)
	if session.status=="station_transition_required":return enter_station(now)
	if session.status=="game_over_transition_required":return enter_game_over()
	if session is StationSession:return request_departure()
	if session is FirstFlightSession and session.status=="running":
		if not session.present_current():return transition_error(session.scene.error)
		session.set_pause("transition",false,now);session.rebase_time(now);_transition_failed=false;present_session();return true
	return false

func present_session() -> void:
	if session==null:return
	var state: Dictionary=session.snapshot()
	if session is StationSession:
		if not station_panel.present(state):status.text=station_panel.error;return
		if not equipment_panel.present(state):status.text=equipment_panel.error;return
		if session.is_paused():status.text="Paused · Esc / controller Start resumes your pause"
		elif not state.conversation_started:status.text=session.station_name
		elif state.dialogue.visible:status.text=session.station_name+" · Enter / controller A continues · Left / controller B goes back · Esc / Start pauses"
		elif state.phase=="ready_to_launch" and FirstFlightSession.supported(bindings,int(state.campaign_cursor)):status.text=session.station_name+" · Depart when ready · Enter / controller A"
		elif state.get("hangar_open",false):status.text=session.station_name+" · Hangar · Tab / controller focus navigates · Esc / Start pauses"
		elif state.phase=="station_equipment_required":status.text=session.station_name+(" · Enter the hangar · Enter / controller A" if EquipmentDefinitions.parameters(bindings.station_equipment) else " · This content pack has no equipment tutorial declarations.")
		elif state.phase=="combat_departure_required":status.text=session.station_name+" · Equipment ready. The combat-training flight is still being reconstructed."
		else:status.text=session.station_name+" · The next mining trip is still being reconstructed."
		refresh_render_mode();return
	if session is FirstFlightSession:
		if not session.can_control():clear_input()
		if session.is_paused():status.text="Paused · Esc / controller Start resumes your pause"
		elif state.dialogue.visible:status.text="Enter / controller A continues · Left / controller B goes back · Esc / Start pauses"
		elif session.status=="station_transition_required":status.text="Entering Var Hastra"
		elif state.get("player_destruction",{}).get("phase","ready")!="ready":status.text="Game over" if state.player_destruction.game_over_visible else "Your ship was destroyed · Esc / Start pauses"
		elif not state.entry_released:status.text="Departing Var Hastra · Esc / Start pauses"
		elif not state.mining_session.drill.is_empty():status.text="Keep the drill centered: WASD / arrows / stick · Stop: E / Space / controller X"
		else:status.text="Steer: WASD / arrows / stick · Mine: E / X · Station: P / Y · Speed: + / − · Cargo: %d / %d"%[state.cargo.used,state.cargo.capacity]
		refresh_render_mode();return
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
		refresh_render_mode()
	elif session.is_paused():status.text="Paused · Esc / controller Start resumes your pause"
	elif session.can_control():status.text="Steer: WASD / arrows / left stick · Fire: Space / right trigger · Pause: Esc / Start"
	else:status.text=("Rescue cinematic" if session is ArrivalSession else "Opening cinematic")+" · Esc / controller Start pauses"
	refresh_render_mode()

func show_error(message: String) -> void:
	reset()
	status.text=message

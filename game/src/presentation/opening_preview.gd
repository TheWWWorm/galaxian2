extends VBoxContainer
const FlightStages=preload("res://src/content/flight_stages.gd")
signal menu_requested
signal game_over_requested
## Supernova Challenge: the timed run is over with this score.
signal challenge_finished(score: int)
## Application host for the recovered opening and its supported ordinary fight.
## Unimplemented transitions stop without completing a mission or creating a save.
const Session = preload("res://src/presentation/opening_session.gd")
const ArrivalSession = preload("res://src/presentation/arrival_session.gd")
const StationSession = preload("res://src/presentation/station_session.gd")
const FirstFlightSession = preload("res://src/presentation/first_flight_session.gd")
const EliteMedals=preload("res://src/simulation/elite_medal_progress.gd")
const Selected40Session = preload("res://src/presentation/selected40_session.gd")
const MissionSession = preload("res://src/presentation/mission_session.gd")
const StationPanel = preload("res://src/presentation/station_dialogue_panel.gd")
const EquipmentPanel = preload("res://src/presentation/station_equipment_panel.gd")
const StationShell = preload("res://src/presentation/station_shell_panel.gd")
const FlightVitals = preload("res://src/presentation/flight_vitals_overlay.gd")
const LoungePanel = preload("res://src/presentation/lounge_panel.gd")
const EquipmentDefinitions = preload("res://src/content/station_equipment_definitions.gd")
const Shopping = preload("res://src/content/ordinary_shopping_definitions.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const MissionContext = preload("res://src/simulation/mission_context.gd")
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
const LocalMapPanel = preload("res://src/presentation/navigation_map_panel.gd")
const StatusPanel = preload("res://src/presentation/status_panel.gd")
const MissionsPanel = preload("res://src/presentation/missions_panel.gd")
const MISSIONS_FIRST_CURSOR:=9
const MedalNoticePanel = preload("res://src/presentation/medal_notice_panel.gd")
const GateConfirmationPanel = preload("res://src/presentation/gate_confirmation_panel.gd")
const FlightHints=preload("res://src/simulation/flight_hints.gd")
const StationHelp=preload("res://src/content/station_help_definitions.gd")
const UISounds=preload("res://src/presentation/ui_sounds.gd")
const LocationCache = preload("res://src/simulation/lounge_cache.gd")
const StationGeneration = preload("res://src/content/station_generation_definitions.gd")
const StationArchive=preload("res://src/simulation/station_archive.gd")
const StationSaveFile=preload("res://src/simulation/station_save_file.gd")
const Difficulty=preload("res://src/content/difficulty_definitions.gd")
# Current base-campaign run profile. Expansion activation is explicit; bundled
# files are not treated as evidence of ownership. Difficulty is the career's.
const BASE_STOCK_SETTINGS={"difficulty":0.5,"valkyrie_owned":false,"supernova_owned":false,
	"energy_availability_percent":0,"missile_availability_percent":0}
const STATION_DEPARTURE_PHASES=["ready_to_launch","combat_departure_required","local_departure_required","contracts_required","convoy_departure_required","alioth_departure_required","free_play_required"]

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
## Last docked career, for the in-flight pause window (Missions, Cargo hold).
var _docked_state:={}
var _hud_hidden:={}
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
var _actions_button: Button
var _jump_button: Button
var _time_button: Button
var _boost_button: Button
var _cloak_charge: Control
var _transfer_bar: Control
var _hacking: Control
var _cloak_dialog: Control
var _hint_dialog: Control
## Loma toll question, then the shortfall notice when the player can't pay.
var _toll_dialog: Control
var _toll_notice:=false
var _hints:=FlightHints.new()
var _cloak_generation:=0
var _cloak_failure_serial:=0
var map_panel: Control
var flight_menu: Control
var _station_map_open:=false
var status_panel: Control
var _status_open:=false
var missions_panel: Control
var _missions_open:=false
var medal_notice: Control
## Career stats observed by the application and banked at the next station.
var _career_play_ms:=0.0
var _elite_tracker:=preload("res://src/simulation/elite_medal_tracker.gd").new()
var _career_cloak_ms:=0.0
var _last_flight_hull_percent:=-1
var _station_course_id:=-1
var _station_drive_course:=false
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
var _scene_effects:=preload("res://src/presentation/scene_effect_settings.gd").new()
var _player_mode:=false
var _mouse_steering:=false
var _mouse_captured:=false
var _preview_controls: Array[Control]=[]
var _menu_button: Button
## Career difficulty chosen at New Game or read from the loaded save.
var _difficulty:=Difficulty.NORMAL
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
	equipment_panel.blueprint_action_requested.connect(equipment_action)
	touch_overlay=Touch.new();host.add_child(touch_overlay);touch_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_overlay.steering.connect(func(command,held):_controls.set_touch_command(command,held))
	touch_overlay.firing.connect(func(held):_controls.set_touch_action("fire",held))
	_flight_actions=Control.new();_flight_actions.mouse_filter=Control.MOUSE_FILTER_IGNORE;host.add_child(_flight_actions)
	_flight_actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_boost_button=Button.new();_boost_button.text="W";_boost_button.focus_mode=Control.FOCUS_NONE;host.add_child(_boost_button)
	_boost_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_boost_button.button_down.connect(func():_controls.set_touch_action("boost",true))
	_boost_button.button_up.connect(func():_controls.set_touch_action("boost",false))
	_mine_button=Button.new();_mine_button.text="Mine";_mine_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_mine_button)
	_station_button=Button.new();_station_button.text="Station";_station_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_station_button)
	_actions_button=Button.new();_actions_button.text="Actions";_actions_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_actions_button)
	_jump_button=Button.new();_jump_button.text="Jump";_jump_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_jump_button)
	_time_button=Button.new();_time_button.text="Time";_time_button.focus_mode=Control.FOCUS_NONE;_flight_actions.add_child(_time_button)
	for pair in [[_mine_button,"dock"],[_station_button,"autopilot"],[_actions_button,"action_menu"],[_jump_button,"jump"],[_time_button,"time"]]:
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
	status_panel=StatusPanel.new();host.add_child(status_panel);status_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status_panel.close_requested.connect(func():close_status())
	missions_panel=MissionsPanel.new();host.add_child(missions_panel);missions_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	missions_panel.close_requested.connect(func():close_missions())
	missions_panel.map_requested.connect(func():if close_missions():open_map())
	missions_panel.wanted_map_requested.connect(func(seen: int,to: int):if close_missions():open_map(-1,false,{"seen":seen,"to":to}))
	missions_panel.discard_requested.connect(func():discard_mission())
	medal_notice=MedalNoticePanel.new();host.add_child(medal_notice);medal_notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	medal_notice.acknowledged.connect(func():acknowledge_medal_notice())
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
	_cloak_charge=preload("res://src/presentation/cloak_charge_panel.gd").new();host.add_child(_cloak_charge)
	_cloak_charge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transfer_bar=preload("res://src/presentation/story_transfer_bar.gd").new();host.add_child(_transfer_bar)
	_transfer_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cloak_dialog=GateConfirmationPanel.new();host.add_child(_cloak_dialog)
	_cloak_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hacking=preload("res://src/presentation/hacking_panel.gd").new();host.add_child(_hacking)
	_hacking.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hacking.turn_requested.connect(hack_press)
	_cloak_dialog.choice_requested.connect(func(_choice):_close_cloak_notice())
	_help_button=TextureButton.new();_help_button.visible=false;_help_button.focus_mode=Control.FOCUS_NONE
	_help_button.ignore_texture_size=true;_help_button.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_help_button.pressed.connect(open_screen_help);host.add_child(_help_button)
	reward_banner=preload("res://src/presentation/reward_banner.gd").new();host.add_child(reward_banner)
	reward_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint_dialog=GateConfirmationPanel.new();host.add_child(_hint_dialog)
	_hint_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint_dialog.choice_requested.connect(func(_choice):_close_flight_hint())
	_toll_dialog=GateConfirmationPanel.new();host.add_child(_toll_dialog)
	_toll_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toll_dialog.choice_requested.connect(_answer_toll)
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
		if not _cloak_charge.configure(library,bindings,visuals):status.text=_cloak_charge.error
		if not _transfer_bar.configure(library,bindings,visuals):status.text=_transfer_bar.error
		if not _hacking.configure(library,bindings,visuals):status.text=_hacking.error
	refresh_render_mode()

func _style_touch_buttons() -> void:
	var art: Dictionary=touch_overlay.sprites
	for row in [[_mine_button,1257,1258,"Mine / Stop"],[_station_button,1212,1213,"Station autopilot"],
		[_actions_button,1210,1211,"Actions (E)"],[_jump_button,1200,1201,"Jump"],[_time_button,1345,1344,"Fast Forward"],
		[_pause_button,1208,1209,"Pause / Resume"],[_boost_button,1202,1203,"Boost (W / A)"]]:
		var button: Button=row[0]
		button.text="";button.tooltip_text=row[3]
		for state in ["normal","hover","disabled"]:button.add_theme_stylebox_override(state,_touch_icon_style(art[row[1]]))
		for state in ["pressed","hover_pressed"]:button.add_theme_stylebox_override(state,_touch_icon_style(art[row[2]]))
		button.add_theme_stylebox_override("focus",OriginalUI.focus_style(true))

## The story hacking puzzle while docked at a hack point.
func _sync_hacking() -> void:
	if _hacking==null:return
	var state: Dictionary=session.flight_reader().story_hack_state() if session is FirstFlightSession and session.flight_reader()!=null else {}
	_hacking.present(state if _hacking.available() else {},bool(state.get("highlighted",false)))

## A hacking button press (on-screen, keys or controller).
func hack_press(button: String) -> bool:
	if not session is FirstFlightSession or session.flight_owner()==null or not session.flight_owner().story_hack_press(button):return false
	present_session();return true

func _sync_cloak_ui(flight: Dictionary={}) -> void:
	_sync_hacking()
	if _cloak_charge==null:return
	var generation: int=0 if session==null else session.get_instance_id()
	if generation!=_cloak_generation:
		_cloak_generation=generation;_cloak_failure_serial=0;_cloak_dialog.clear()
	var state: Dictionary=session.cloak_state() if session is FirstFlightSession or session is MissionSession else {}
	var hud: bool=session.flight_hud_visible() if session is MissionSession else session.flight_hud_visible(flight) if session is FirstFlightSession else false
	var drive: Dictionary=flight.get("khador",{})
	_cloak_charge.present(drive if drive.get("phase")=="charging" else state,hud,_mobile_layout,"khador" if drive.get("phase")=="charging" else "cloak")
	var transfer: Dictionary=session.flight_reader().story_transfer_state() if session is FirstFlightSession and session.flight_reader()!=null else {}
	# The dock hold hides the rest of the HUD; the bar still shows over it.
	var held: bool=not transfer.is_empty() and session.flight_reader().story_dock_held() and session.status=="running" and not flight.get("dialogue",{}).get("visible",false)
	_transfer_bar.present(transfer,hud or held,_mobile_layout)
	if int(state.get("failure_serial",0))>_cloak_failure_serial:
		if not _cloak_dialog.present_message(library,bindings,visuals,572," %d."%int(state.energy_cost)):status.text=_cloak_dialog.error;return
		if not session.set_pause("cloak_notice",true,Time.get_ticks_usec()):status.text=session.error;return
		_cloak_failure_serial=int(state.failure_serial);clear_input()
	_cloak_dialog.set_mobile_layout(_mobile_layout)
	_cloak_dialog.set_active(_focused and is_visible_in_tree() and not _user_paused)

func _close_cloak_notice() -> void:
	if not _cloak_dialog.visible or session==null:return
	if not session.set_pause("cloak_notice",false,Time.get_ticks_usec()):status.text=session.error;return
	_cloak_dialog.clear();clear_input();present_session()

## One-time hint windows (flight_hints.gd): pause the flight until confirmed.
func _sync_flight_hints(flight: Dictionary) -> void:
	# Automated checks turn hint windows off unless they test them.
	if _hint_dialog==null or OS.get_environment("GOF2_FLIGHT_HINTS")=="0":return
	if not session is FirstFlightSession:
		if _hint_dialog.visible and not (_station_help_open and session is StationSession):_hint_dialog.clear();_station_help_open=false
		return
	_hint_dialog.set_mobile_layout(_mobile_layout)
	_hint_dialog.set_active(_focused and is_visible_in_tree() and not _user_paused)
	if _hint_dialog.visible or _cloak_dialog.visible or flight.is_empty() or session.status!="running" or session.is_paused() or not session.flight_hud_visible(flight):return
	var hint: Dictionary=_hints.next_hint(FlightHints.flight_facts(flight,_hacking!=null and _hacking.visible))
	if hint.is_empty():return
	var text:=FlightHints.text(library,bindings,int(hint.text_id),touch_actions_enabled())
	if text.is_empty() or not _hint_dialog.present_text(library,bindings,visuals,text,int(hint.text_id)):return
	if not session.set_pause("hint",true,Time.get_ticks_usec()):_hint_dialog.clear();status.text=session.error;return
	clear_input()

## First-visit station help (station_help_definitions.gd): once per game run
## per screen, in the same one-button window as the flight hints.
static var _station_help_shown:={}
var _station_help_open:=false
func _station_help(screen: String) -> void:
	if _hint_dialog==null or OS.get_environment("GOF2_FLIGHT_HINTS")=="0" or not session is StationSession or _station_help_shown.has(screen):return
	var id:=StationHelp.text_id(screen)
	var text:=FlightHints.text(library,bindings,id,touch_actions_enabled()) if id>=0 else ""
	if _show_station_help(id):_station_help_shown[screen]=true

func _show_station_help(id: int) -> bool:
	var text:=FlightHints.text(library,bindings,id,touch_actions_enabled()) if id>=0 else ""
	if text.is_empty() or not _hint_dialog.present_text(library,bindings,visuals,text,id):return false
	_hint_dialog.set_mobile_layout(_mobile_layout);_hint_dialog.set_active(_focused and is_visible_in_tree())
	_station_help_open=true;clear_input();return true

## The "?" button at the top right of station screens reopens their help.
var _help_button: TextureButton
var _help_screen:=""
var _help_context:=[]
const WANTED_HINT_CURSOR:=128
const WANTED_HINT_TEXT:=590
func _sync_screen_help(state: Dictionary) -> void:
	_help_screen=""
	if _player_mode and session is StationSession and not session.presentation_active() and not state.get("dialogue",{}).get("visible",false) and state.get("contracts",{}).get("pending_result",{}).is_empty() and not medal_notice.visible:
		if _station_map_open:_help_screen="map"
		elif _status_open:_help_screen="status"
		elif _missions_open:_help_screen="missions"
		elif state.get("hangar_open",false):_help_screen="hangar"
		elif state.get("lounge_open",false):_help_screen="lounge"
		elif station_shell.visible:_help_screen="station"
		# 590 "Wanted Boards": once when 128 has started (after its station talk).
		if _help_screen=="station" and int(state.get("campaign_cursor",-1))==WANTED_HINT_CURSOR and _hint_dialog!=null and not _station_help_open and not _station_help_shown.has("wanted") and OS.get_environment("GOF2_FLIGHT_HINTS")!="0":
			if _show_station_help(WANTED_HINT_TEXT):_station_help_shown["wanted"]=true
	if visuals==null:_help_screen=""
	if not _help_screen.is_empty() and _help_context!=[library,bindings,visuals]:
		var art:=OriginalUI.new()
		var loaded: Dictionary=art.load_regions(library,bindings,visuals,[StationHelp.BUTTON_IMAGE_ID],bindings.mido_travel.get("map",{}).get("ui",{}).get("atlas_resources",{}))
		_help_button.texture_normal=loaded.get(StationHelp.BUTTON_IMAGE_ID);_help_context=[library,bindings,visuals]
	_help_button.visible=not _help_screen.is_empty() and _help_button.texture_normal!=null
	if not _help_button.visible:return
	var size: Vector2=_help_button.texture_normal.get_size()+Vector2(8.0,8.0)
	_help_button.size=size;_help_button.position=Vector2(_help_button.get_parent().size.x-size.x,0.0)
	equipment_panel.set_help_inset(size.x)

## Reward banner: a bounty when the kill pays in flight, a freelance job's
## pay when its completed result is closed.
var reward_banner: Control
var _reward_context:=[]
var _bounty_seen:={}
func _sync_reward_banner(state: Dictionary) -> void:
	if library==null or bindings==null or visuals==null:return
	if _reward_context!=[library,bindings,visuals]:
		_reward_context=[library,bindings,visuals]
		if not reward_banner.configure(library,bindings,visuals):push_warning(reward_banner.error)
	reward_banner.set_mobile_layout(_mobile_layout)
	var transition: Dictionary=state.get("contracts",{}).get("flight",{}).get("story_transition",{})
	if transition.get("reward_banner","")!="bounty" or transition==_bounty_seen:return
	_bounty_seen=transition.duplicate(true)
	reward_banner.show_reward(int(transition.get("previous_mission",{}).get("reward",0)),true)

func open_screen_help() -> bool:
	if _help_screen.is_empty() or _hint_dialog.visible:return false
	UISounds.event(self,UISounds.HELP_WINDOW)
	return _show_station_help(StationHelp.button_text_id(equipment_panel.help_screen() if _help_screen=="hangar" else _help_screen))

func _close_flight_hint() -> void:
	if not _hint_dialog.visible:return
	_station_help_open=false
	if session is FirstFlightSession and not session.set_pause("hint",false,Time.get_ticks_usec()):status.text=session.error;return
	_hint_dialog.clear();clear_input();present_session()

## Loma toll: when the flight asks, pause on "toll" and show the question.
func _sync_toll(flight: Dictionary) -> void:
	if _toll_dialog==null:return
	if not session is FirstFlightSession:
		if _toll_dialog.visible:_toll_dialog.clear()
		return
	_toll_dialog.set_mobile_layout(_mobile_layout)
	_toll_dialog.set_active(_focused and is_visible_in_tree() and not _user_paused)
	var toll: Dictionary=flight.get("loma_toll",{})
	if _toll_dialog.visible or _hint_dialog.visible or _cloak_dialog.visible or not toll.get("question",false) or session.status!="running" or session.is_paused():return
	var Toll=preload("res://src/content/loma_toll_definitions.gd")
	var text: String=Toll.question_text(library.strings[Toll.QUESTION_TEXT],int(toll.percent),int(toll.amount))
	if not _toll_dialog.present_question(library,bindings,visuals,text,Toll.QUESTION_TEXT):status.text=_toll_dialog.error;return
	if not session.set_pause("toll",true,Time.get_ticks_usec()):_toll_dialog.clear();status.text=session.error;return
	_toll_notice=false;clear_input()

func _answer_toll(choice: int) -> void:
	if not _toll_dialog.visible or not session is FirstFlightSession:return
	if not _toll_notice:
		if not session.answer_toll(choice==1):status.text=session.error;return
		var missing:=int(session.toll_state().get("shortfall",0))
		if choice==1 and missing>0:
			var Toll=preload("res://src/content/loma_toll_definitions.gd")
			_toll_dialog.clear()
			if _toll_dialog.present_text(library,bindings,visuals,Toll.shortfall_text(library.strings[Toll.SHORTFALL_TEXT],missing),Toll.SHORTFALL_TEXT):
				_toll_notice=true;_toll_dialog.set_active(_focused and is_visible_in_tree());clear_input();return
	_toll_notice=false
	if not session.set_pause("toll",false,Time.get_ticks_usec()):status.text=session.error;return
	_toll_dialog.clear();clear_input();present_session()

func _sync_booster_indicator(flight: Dictionary={}) -> void:
	_sync_cloak_ui(flight)
	_sync_toll(flight)
	_sync_flight_hints(flight)
	if _boost_button==null:return
	var state: Dictionary=flight.get("booster",{}) if session is FirstFlightSession else session.booster_state() if session is MissionSession else {}
	_boost_button.visible=state.get("available",false)
	if not _boost_button.visible:return
	_boost_button.visible=session.flight_hud_visible() if session is MissionSession else session.flight_hud_visible(flight)
	if not _boost_button.visible:return
	_boost_button.disabled=not state.ready or not session.can_control() or not _focused
	# The desktop glyph is a status indicator; touch enables its button surface.
	_boost_button.mouse_filter=Control.MOUSE_FILTER_STOP if touch_actions_enabled() else Control.MOUSE_FILTER_IGNORE
	_boost_button.modulate=Color(1,1,1,float(state.icon_alpha))
	var extent:=52.0 if _mobile_layout else 34.0
	_boost_button.offset_right=-16.0;_boost_button.offset_left=-16.0-extent
	_boost_button.offset_bottom=-178.0 if _mobile_layout else -132.0
	_boost_button.offset_top=_boost_button.offset_bottom-extent

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

## Fold application-observed stats into the docked career (medals settle there).
func bank_career_stats(arrived:=false,target: Node=null) -> void:
	var docked: Node=session if target==null else target
	if not docked is StationSession or docked._world==null or not docked._world.has_contracts():return
	var state: Dictionary=docked.station_owner().snapshot()
	var observed:={"play_ms":int(_career_play_ms),"cloak_ms":int(_career_cloak_ms)}
	var primaries:=0
	for slot in state.get("loadout",{}).get("slots",[]):
		if slot is Dictionary and int(slot.get("category",-1))==0:primaries+=1
	observed.max_primaries=primaries
	var cargo: Variant=state.get("cargo")
	if cargo is Dictionary and cargo.get("capacity") is int and cargo.get("used") is int:observed.max_free_cargo=maxi(0,cargo.capacity-cargo.used)
	if arrived and _last_flight_hull_percent>=0:observed.min_arrival_hull_percent=_last_flight_hull_percent
	if docked._world.record_stats(observed):_career_play_ms-=int(_career_play_ms);_career_cloak_ms-=int(_career_cloak_ms)
	if not _hints.pending().is_empty():
		if docked._world.record_hints(_hints.pending()):_hints.banked()
		else:status.text=docked._world.error
	# Add-on medals: flight streaks latched since the last docking, plus the
	# docked ship's cargo capacity. Docking resets the streaks.
	var elite: Array=_elite_tracker.take_reached()
	if cargo is Dictionary and cargo.get("capacity") is int:elite.append_array(EliteMedals.dock_reached(cargo.capacity))
	_elite_tracker.reset()
	if not docked._world.record_elite_medals(elite):status.text=docked._world.error
	_last_flight_hull_percent=-1

func save_station(announce: bool=true) -> bool:
	if not _focused or not is_visible_in_tree() or not _can_save_station():return _save_message("Finish the station conversation and close its panels before saving",false)
	bank_career_stats()
	var cat:=Catalogues.new()
	if not cat.open(library):return _save_message(cat.error,false)
	if not _save_file.save(station_save_path(),session.station_owner(),bindings,cat,library,session.location_owner()):return _save_message(_save_file.error,false)
	if announce:_save_message("Station saved",true)
	refresh_render_mode()
	return true

func _autosave_station() -> bool:
	return save_station(false) if _can_save_station() else true

## Recipe acknowledgement and its durable checkpoint are one transaction.
func _save_station_candidate(candidate: RefCounted) -> bool:
	if _save_directory.is_empty():return true
	var cat:=Catalogues.new()
	if not cat.open(library):return _save_message(cat.error,false)
	if not _save_file.save(station_save_path(),candidate,bindings,cat,library,candidate.contract_owner().location_owner()):return _save_message(_save_file.error,false)
	if _save_notice!=null:_save_notice.hide()
	return true

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
	_difficulty=session.career_difficulty()
	_locations=session.location_owner();session.camera.make_current()
	session.rebase_time(now);refresh_render_mode();present_session()
	if _save_file.recovered_backup:_save_message("Recovered the previous saved station",true)
	elif not _player_mode:_save_message("Saved station loaded",true)
	return true

func reset() -> void:
	if lounge_panel!=null:lounge_panel.clear()
	if _cloak_dialog!=null:_cloak_dialog.clear()
	if _hint_dialog!=null:_hint_dialog.clear()
	_station_help_open=false
	if _toll_dialog!=null:_toll_dialog.clear()
	_toll_notice=false
	_hints.reset()
	# Unbanked play and cloak time, the last arrival hull and add-on streaks
	# belong to the career being left; the original restores them from the save.
	_career_play_ms=0.0;_career_cloak_ms=0.0;_last_flight_hull_percent=-1;_elite_tracker=preload("res://src/simulation/elite_medal_tracker.gd").new()
	_cloak_generation=0;_cloak_failure_serial=0
	cancel_departure()
	if map_panel!=null:map_panel.clear()
	if status_panel!=null:status_panel.clear()
	if missions_panel!=null:missions_panel.clear()
	_missions_open=false
	if medal_notice!=null:medal_notice.clear()
	_status_open=false
	if gate_panel!=null:gate_panel.clear()
	if session!=null:session.free();session=null
	_transition_failed=false
	_last_game_over={}
	if _save_notice!=null:_save_notice.hide()
	_locations=null;_location_error=""
	clear_input();_user_paused=false;_station_map_open=false;_station_course_id=-1;_docked_state={};set_action_freeze(false)
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

func start(difficulty: Variant=Difficulty.NORMAL) -> void:
	reset()
	if viewport==null:return
	if not Difficulty.valid(difficulty):show_error("The game difficulty is invalid");return
	_difficulty=float(difficulty)
	session=Session.new();viewport.add_child(session)
	# Native desktop presentation uses the source large-display scenery setting.
	# Mobile follows physical display dimensions, not the embedded preview size.
	var screen := DisplayServer.screen_get_size()
	var mac_profile: bool = library!=null and library.manifest.get("profile",{}).get("edition")=="mac-full-hd"
	var large_display := mac_profile or not OS.has_feature("mobile") or (maxi(screen.x,screen.y)>=1024 and mini(screen.x,screen.y)>=768)
	if not session.configure(library,bindings,visuals,Time.get_ticks_usec(),_difficulty,null,large_display,Session.supports_player_controls(bindings),Session.supports_escape(bindings)):
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
	hold_paused(value)
	if value and _player_mode:menu_requested.emit()

## Freeze or release the session for a menu without asking for the menu again.
func hold_paused(value: bool) -> void:
	_user_paused=value;clear_input()
	release_action_focus()
	_pause_button.set_pressed_no_signal(value)
	if session!=null and session.status in ["running","gate_confirmation_required","gate_map_required"]:session.set_pause("user",value,Time.get_ticks_usec())
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

func _capability_identity() -> String:
	if bindings==null:return ""
	return "%s:%s:%s"%[bindings.binding_id,bindings.dekato_source_receipt().get("source_binding_id",""),bindings.nehma_source_receipt().get("source_binding_id","")]

func _departure_available(cursor: int) -> bool:
	# UI availability is invariant for an opened content pack and campaign cursor.
	# Actual departure still validates its packet and all native owners.
	var identity:=_capability_identity()
	if _support_context!=bindings or _support_identity!=identity:
		_support_context=bindings;_support_identity=identity;_departure_support={}
	if not _departure_support.has(cursor):_departure_support[cursor]=FirstFlightSession.supported(bindings,cursor)
	return _departure_support[cursor]

func _shopping_available() -> bool:
	var identity:=_capability_identity()
	if _support_context!=bindings or _support_identity!=identity:
		_support_context=bindings;_support_identity=identity;_departure_support={}
	if not _departure_support.has("shopping"):_departure_support.shopping=Shopping.available(bindings)
	return _departure_support.shopping

func refresh_render_mode(state: Dictionary={}) -> void:
	if session is MissionSession:
		_sync_booster_indicator()
		_sync_mouse_capture()
		flight_menu.set_active(_focused and is_visible_in_tree() and not _user_paused)
		for node in [station_shell,station_panel,equipment_panel,flight_vitals,radio_panel,target_frame,aim_reticle,npc_markers,secondary_panel,lounge_panel,map_panel,gate_panel,touch_overlay,_flight_actions,_flight_hint,_launch_button,_hangar_button,_station_map_button,_lounge_button,_save_button,_load_button,_retry_button,_skip_button]:
			if node!=null:node.hide()
		var touch_actions:=touch_actions_enabled()
		var hud_visible: bool=session.flight_hud_visible()
		var input_active: bool=session.can_control() and _focused and is_visible_in_tree()
		_pause_button.visible=touch_actions and hud_visible;_pause_button.disabled=false
		touch_overlay.visible=touch_actions and hud_visible;touch_overlay.set_fire_label("Fire")
		touch_overlay.set_active(touch_overlay.visible and input_active)
		_flight_actions.visible=touch_actions and hud_visible
		for button in [_mine_button,_station_button,_jump_button,_time_button]:button.hide()
		_actions_button.visible=true;_actions_button.disabled=not input_active
		session.scene.secondary_panel.set_interaction(input_active,touch_actions)
		session.scene.secondary_panel.set_mobile_layout(_mobile_layout)
		session.scene.hud.set_mobile_layout(_mobile_layout,touch_actions)
		var skip_available: bool=_focused and is_visible_in_tree() and session.can_skip_cinematic()
		_flight_hint.visible=_player_mode and not touch_actions_enabled() and skip_available
		_flight_hint.text="Click / Enter / A  Skip cinematic"
		_skip_button.visible=touch_actions_enabled() and skip_available;_skip_button.disabled=false
		_layout_flight_overlays()
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if is_visible_in_tree() and not session.is_paused() and session.status=="running" else SubViewport.UPDATE_ONCE
		status.visible=not _player_mode or _transition_failed
		return
	if state.is_empty() and session!=null:state=session.snapshot()
	# Each query below is asked several times per refresh; ask once.
	var controllable: bool=session!=null and session.can_control()
	var hud_visible: bool=session!=null and session.flight_hud_visible(state)
	var skippable: bool=session!=null and session.has_method("can_skip_cinematic") and session.can_skip_cinematic()
	_sync_booster_indicator(state)
	_sync_mouse_capture()
	var touch_actions:=touch_actions_enabled()
	if _pause_button!=null:_pause_button.visible=touch_actions and session!=null and (hud_visible or controllable)
	if _station_map_button!=null:
		_station_map_button.visible=_station_map_available(state) and not _station_map_open
		_station_map_button.disabled=session==null or session.is_paused() or not _focused
	if flight_menu!=null:flight_menu.set_active(session!=null and session._pauses.has("flight_menu") and session._pauses.size()==1 and _focused and is_visible_in_tree())
	if _menu_button!=null:_menu_button.visible=_player_mode and session is StationSession
	if _save_button!=null:
		_save_button.visible=not _save_directory.is_empty() and session is StationSession
		_save_button.disabled=not _can_save_station(state) or not _focused or not _launch_packet.is_empty()
	if _load_button!=null:
		# Flight hides Load; skip the save path and disk checks every frame there.
		var offered: bool=session==null or session is StationSession or not _last_game_over.is_empty()
		var path:=station_save_path() if offered else ""
		_load_button.visible=not path.is_empty()
		_load_button.disabled=path.is_empty() or not _focused or not (FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"))
		_load_button.text="Retry saved game" if not _last_game_over.is_empty() else "Load"
	if _retry_button!=null:_retry_button.visible=_transition_failed and session!=null
	if _launch_button!=null:
		_launch_button.visible=session is StationSession and state.phase in STATION_DEPARTURE_PHASES and not state.get("lounge_open",false) and not state.get("hangar_open",false) and state.get("contracts",{}).get("pending_result",{}).is_empty() and _departure_available(int(state.campaign_cursor))
		_launch_button.disabled=session==null or session.is_paused() or not _focused or not _launch_packet.is_empty()
	if secondary_panel!=null:
		secondary_panel.set_interaction(session is FirstFlightSession and controllable and _focused and is_visible_in_tree() and not _transition_failed,touch_actions)
		secondary_panel.set_hud_visible(session is FirstFlightSession and hud_visible and not session.map_open() and not state.get("guided_missile",false))
		secondary_panel.set_selection_active(session is FirstFlightSession and session.secondary_menu_active() and _focused and is_visible_in_tree() and not _transition_failed)
	if _flight_actions!=null:
		_flight_actions.visible=touch_actions and ((session is FirstFlightSession and hud_visible and not session.map_open()) or (session is MissionSession and session.flight_hud_visible()))
		_mine_button.disabled=session==null or not controllable or not _focused
		_station_button.disabled=_mine_button.disabled
		var local: bool=session is FirstFlightSession and not state.get("local_travel",{}).is_empty()
		_actions_button.visible=true;_actions_button.disabled=_mine_button.disabled
		_mine_button.visible=session is FirstFlightSession;_station_button.visible=session is FirstFlightSession
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
		touch_overlay.set_fire_label(("Stop" if drilling else "Fire" if not state.get("encounter",{}).get("primaries",{}).is_empty() else "Mine") if session is FirstFlightSession else "Fire")
		touch_overlay.visible=touch_actions and session!=null and hud_visible
		touch_overlay.set_active(touch_overlay.visible and controllable and is_visible_in_tree() and _focused)
	if flight_vitals!=null:
		var gauges_visible: bool=session!=null and hud_visible
		if session is FirstFlightSession:gauges_visible=gauges_visible and not session.map_open() and not session.secondary_menu_open()
		flight_vitals.set_active(gauges_visible)
		flight_vitals.set_touch_inset(touch_actions and flight_vitals.visible)
	if _flight_hint!=null:
		var cinematic: bool=session!=null and skippable
		_flight_hint.visible=_player_mode and not touch_actions and cinematic and _focused and is_visible_in_tree()
		if _flight_hint.visible:
			_flight_hint.text="Skipping cinematic…" if session.cinematic_skipping() else "Click / Enter / A  Skip cinematic"
	if _skip_button!=null:
		_skip_button.visible=touch_actions and session!=null and skippable and _focused and is_visible_in_tree()
		_skip_button.disabled=session!=null and session.has_method("cinematic_skipping") and session.cinematic_skipping()
	_layout_flight_overlays()
	_refresh_station_shell(state)
	_sync_screen_help(state)
	_sync_reward_banner(state)
	if session is StationSession and session.presentation_active():
		for node in [station_shell,station_panel,equipment_panel,lounge_panel,map_panel,_menu_button,_launch_button,_hangar_button,_lounge_button,_station_map_button,_save_button,_load_button,_flight_hint,_skip_button]:
			if node!=null:node.hide()
		if _save_notice!=null and not _transition_failed:_save_notice.hide()
	if _player_mode and session is StationSession and (_station_map_open or _status_open or _missions_open or state.get("dialogue",{}).get("visible",false) or state.get("hangar_open",false) or state.get("lounge_open",false) or not state.get("contracts",{}).get("pending_result",{}).is_empty()):
		for button in [_menu_button,_launch_button,_hangar_button,_lounge_button,_station_map_button,_save_button,_load_button]:button.hide()
	if status!=null and _player_mode:status.visible=_transition_failed
	if _station_map_open and _save_notice!=null:_save_notice.hide()
	if viewport==null:return
	var scene_view: Control=viewport.get_parent()
	scene_view.visible=not state.get("presentation",{}).get("background_swapped",false)
	if not scene_view.is_visible_in_tree():viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
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
	if _station_map_open or _status_open or _missions_open or not _player_mode or _chrome_context.is_empty() or not session is StationSession or state.get("dialogue",{}).get("visible",false) or state.get("hangar_open",false) or state.get("lounge_open",false) or not state.get("contracts",{}).get("pending_result",{}).is_empty():
		station_shell.clear();return
	var buttons:={"map":_station_map_button,"hangar":_hangar_button,"lounge":_lounge_button,"depart":_launch_button,"save":_save_button,"load":_load_button,"menu":_menu_button}
	var displayed:=state.duplicate();displayed.ui_actions={}
	for action in buttons:
		var button: Button=buttons[action]
		displayed.ui_actions[action]={"visible":button.visible,"enabled":not button.disabled}
	displayed.ui_actions.status={"visible":session.has_contracts(),"enabled":session.has_contracts()}
	# The original station menu offers the Missions log once training is over.
	var log_ready: bool=session.has_contracts() and int(state.get("campaign_cursor",0))>MISSIONS_FIRST_CURSOR-1
	displayed.ui_actions.missions={"visible":log_ready,"enabled":log_ready}
	if not station_shell.present(displayed):status.text=station_shell.error;return
	_sync_medal_notice(state)
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
		"status":open_status()
		"missions":open_missions()

func _sync_mouse_capture() -> void:
	var active: bool=_player_mode and _mouse_steering and not _mobile_layout and not touch_actions_enabled() and _focused and is_visible_in_tree() and not _user_paused and session!=null and (session.can_control() or (session is FirstFlightSession and session.can_stop_mining()))
	if session is MissionSession and session.flight_observation().camera_mode==3:active=false
	_controls.set_mouse_active(active)
	if active==_mouse_captured:return
	_mouse_captured=active
	if DisplayServer.get_name()!="headless":Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE

func _exit_tree() -> void:
	if _mouse_captured and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if handle_hangar_back(event):return
	if session is StationSession and session.presentation_active() and _focused and is_visible_in_tree():
		var pressed: bool=(event is InputEventKey and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
		if pressed:
			if _transition_failed:retry_transition()
			elif session.skip_presentation():present_session()
		if not event is InputEventMouseMotion:get_viewport().set_input_as_handled()
		return
	if not _touch_detected and event is InputEventScreenTouch and event.pressed and event.device!=InputEvent.DEVICE_ID_EMULATION:
		_touch_detected=true;refresh_render_mode()
	# Cinematics release the mouse, so take the skip click before the scene
	# view forwards it into its GUI or the captured-flight check rejects it.
	if event is InputEventMouseButton and _handle_cinematic_skip_event(event):return
	# Own captured mouse input before the flight SubViewport can consume it.
	if not _mouse_captured or not _focused or not is_visible_in_tree():return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if _controls.accept(event):
			handle_action_events(_controls.take_events())
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _toll_dialog!=null and _toll_dialog.visible:
		_controls.discard_modal_event(event)
		if _focused and is_visible_in_tree():_toll_dialog.handle_event(event)
		get_viewport().set_input_as_handled();return
	if _hint_dialog!=null and _hint_dialog.visible:
		_controls.discard_modal_event(event)
		if _focused and is_visible_in_tree():_hint_dialog.handle_event(event)
		get_viewport().set_input_as_handled();return
	if _cloak_dialog.visible:
		_controls.discard_modal_event(event)
		if _focused and is_visible_in_tree():_cloak_dialog.handle_event(event)
		get_viewport().set_input_as_handled();return
	if session is MissionSession and flight_menu.visible:
		if _focused and is_visible_in_tree():flight_menu.handle_event(event)
		get_viewport().set_input_as_handled();return
	if session is MissionSession:
		_selected40_input(event)
		return
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
	if medal_notice.visible and session is StationSession:
		medal_notice.handle_event(event);get_viewport().set_input_as_handled();return
	if _status_open:
		status_panel.handle_event(event);get_viewport().set_input_as_handled();return
	if _missions_open:
		missions_panel.handle_event(event);get_viewport().set_input_as_handled();return
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
	if _handle_cinematic_skip_event(event):return
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
	if (session is StationSession or (session is FirstFlightSession and session.dialogue_visible())) and not session.is_paused() and not supported:
		var action:="";var accept:=false
		if event is InputEventKey and event.pressed and not event.echo:
			var key: int=event.physical_keycode if event.physical_keycode else event.keycode
			if key in [KEY_ENTER,KEY_KP_ENTER,KEY_RIGHT]:action="next";accept=key!=KEY_RIGHT
			elif key==KEY_LEFT:action="previous"
		elif event is InputEventJoypadButton and event.pressed:
			if event.button_index==JOY_BUTTON_A:action="next";accept=true
			elif event.button_index==JOY_BUTTON_B:action="previous"
		if session is StationSession and station_shell.visible:
			if station_shell.action_focused():
				# Enter / A press the focused station action instead of departing,
				# and B lets go of it so that A means "next" again.
				if accept:return
				if action=="previous" and event is InputEventJoypadButton:
					get_viewport().gui_release_focus();get_viewport().set_input_as_handled();return
			# Up or down gives a keyboard or controller its first focus.
			elif get_viewport().gui_get_focus_owner()==null and (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up")):
				if station_shell.focus_edge(event.is_action_pressed("ui_up")):get_viewport().set_input_as_handled();return
		if not action.is_empty():
			if session is FirstFlightSession:session.navigate(action);clear_input();present_session()
			elif session.snapshot().phase in STATION_DEPARTURE_PHASES and action=="next":request_departure()
			elif session.snapshot().phase=="station_equipment_required" and action=="next":equipment_action("open")
			else:station_navigation(action)
			get_viewport().set_input_as_handled();return
	# Hacking: left/right (arrows, A/D, shoulder buttons) turn the blocks.
	if session is FirstFlightSession and session.flight_reader()!=null and not session.flight_reader().story_hack_state().is_empty() and not session.is_paused():
		var turn:=""
		if event is InputEventKey and event.pressed and not event.echo:
			var key: int=event.physical_keycode if event.physical_keycode else event.keycode
			if key in [KEY_LEFT,KEY_A]:turn="left"
			elif key in [KEY_RIGHT,KEY_D]:turn="right"
		elif event is InputEventJoypadButton and event.pressed:
			if event.button_index in [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_DPAD_LEFT]:turn="left"
			elif event.button_index in [JOY_BUTTON_RIGHT_SHOULDER,JOY_BUTTON_DPAD_RIGHT]:turn="right"
		if not turn.is_empty():hack_press(turn);get_viewport().set_input_as_handled();return
	if session.can_control():
		if session is FirstFlightSession:
			if event is InputEventKey:
				var key: int=event.physical_keycode if event.physical_keycode else event.keycode
				supported=supported or (session.wingmen_available() and Controls.KEY_ACTIONS.get(key)=="wingmen")
				supported=supported or key in Controls.DIRECTIONS or (Controls.KEY_ACTIONS.has(key) and Controls.KEY_ACTIONS[key] in ["fire","boost","cloak","change_view","dock","autopilot","map","jump","throttle_up","throttle_down","brake","mouse_mode","action_menu","time_extender"]) or ((session.secondary_available() or session.turret_state().get("active",false)) and Controls.KEY_ACTIONS.get(key) in ["missiles","secondary_menu"]) or (session.fast_forward_available() and Controls.KEY_ACTIONS.get(key)=="time")
			elif event is InputEventJoypadButton:supported=supported or (Controls.BUTTON_ACTIONS.has(event.button_index) and Controls.BUTTON_ACTIONS[event.button_index] in ["fire","boost","cloak","change_view","dock","autopilot","map","jump","throttle_up","throttle_down","brake","mouse_mode","action_menu","time_extender"]) or ((session.secondary_available() or session.turret_state().get("active",false)) and Controls.BUTTON_ACTIONS.get(event.button_index) in ["missiles","secondary_menu"]) or (session.fast_forward_available() and Controls.BUTTON_ACTIONS.get(event.button_index)=="time")
			elif event is InputEventJoypadMotion:supported=event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y,JOY_AXIS_TRIGGER_RIGHT] or ((session.secondary_available() or session.turret_state().get("active",false)) and event.axis==JOY_AXIS_TRIGGER_LEFT)
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
	if session is FirstFlightSession or session is MissionSession:session.clear_flight_input()
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
	_scene_effects.apply(preferences)
	clear_input()
	_controls.configure_preferences(_controls.deadzone,preferences.invert_pitch,preferences.touch_controls)
	_mouse_steering=preferences.get("mouse_steering",false)
	_controls.mouse_sensitivity=preferences.get("mouse_sensitivity",1.0)
	set_touch_controls(preferences.touch_controls)
	set_mobile_layout(_mobile_layout)

func scene_effect_settings() -> RefCounted:return _scene_effects

func set_mobile_layout(value: bool) -> void:
	_mobile_layout=value
	_sync_mouse_capture()
	for panel in [station_panel,equipment_panel,station_shell,flight_vitals,lounge_panel,radio_panel,target_frame,aim_reticle,npc_markers,map_panel,gate_panel,secondary_panel,_launch_dialog,flight_menu]:
		if panel!=null:panel.set_mobile_layout(value)
	if touch_overlay!=null:touch_overlay.mobile=value;touch_overlay.queue_redraw()
	for button in [_mine_button,_station_button,_actions_button,_jump_button,_time_button]:
		if button!=null:button.custom_minimum_size=Vector2(56,56) if value else Vector2(42,42)
	for button in [_save_button,_load_button]:
		if button!=null:button.custom_minimum_size.y=48 if value else 0
	if session is FirstFlightSession:session.scene.set_mobile_layout(value)
	_layout_flight_overlays()

func _layout_flight_overlays() -> void:
	if _flight_actions==null:return
	var scale_value:=1.0 if _mobile_layout else 0.75
	_flight_actions.offset_left=-244.0*scale_value;_flight_actions.offset_right=-12.0
	_flight_actions.offset_top=-192.0*scale_value;_flight_actions.offset_bottom=-12.0
	for row in [[_mine_button,Vector2(75,42)],[_station_button,Vector2(93,130)],
		[_actions_button,Vector2(185,42)],[_jump_button,Vector2(25,125)],[_time_button,Vector2(132,72)]]:
		var button: Button=row[0];var extent:=Vector2.ONE*52.0*scale_value
		button.size=extent;button.position=Vector2(row[1])*scale_value-extent*0.5
	if not session is FirstFlightSession or session.scene==null or session.scene.radio==null:return
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
		if was_active and (session is FirstFlightSession or session is MissionSession):session.clear_flight_input()

func _handle_cinematic_skip_event(event: InputEvent) -> bool:
	if not _focused or not is_visible_in_tree() or session==null or not session.has_method("can_skip_cinematic") or not session.can_skip_cinematic():return false
	var skip_key: bool=event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode) in [KEY_ENTER,KEY_KP_ENTER]
	var skip_pad: bool=event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_A
	var skip_click: bool=event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT
	if not skip_key and not skip_pad and not skip_click:return false
	skip_cinematic();get_viewport().set_input_as_handled()
	return true

func skip_cinematic() -> void:
	if session==null or not session.has_method("request_cinematic_skip") or not _focused or not is_visible_in_tree():return
	if not session.request_cinematic_skip():show_error(session.error);return
	clear_input();present_session()

func _process(_delta: float) -> void:
	_controls.advance_mouse(_delta,Vector2(viewport.size),session is FirstFlightSession and session.can_stop_mining())
	if session is MissionSession:
		_selected40_tick(Time.get_ticks_usec())
		return
	if session==null or session.status not in ["running","arrival_transition_required","station_transition_required","station_reload_required","local_arrival_transition_required","gate_confirmation_required","gate_map_required","gate_arrival_transition_required","drive_arrival_transition_required","game_over_transition_required","convoy_arrival_transition_required","sahi_arrival_transition_required","void_return_transition_required","mission_station_return_required"] or _transition_failed:return
	if session.status=="running":
		if not session.is_paused() and _focused:
			_career_play_ms+=_delta*1000.0
			if (session is FirstFlightSession) and session.cloak_state().get("active",false):_career_cloak_ms+=_delta*1000.0
		handle_action_events(_controls.take_events())
		var input: Dictionary=_controls.snapshot() if session.can_control() else {"command":Vector2.ZERO,"held":{"fire":false}}
		if session is FirstFlightSession and session.can_stop_mining():input.command=Controls.pointer_command(input.command)
		var accepted: bool
		if session is FirstFlightSession:session.elite_tracker=_elite_tracker
		if session is FirstFlightSession:accepted=session.step(Time.get_ticks_usec(),input.command,input.held.fire,input.get("mouse_response",false),input.get("strafe",0.0),input.held.get("brake",false),_controls.invert_pitch)
		elif session is Session:accepted=session.step(Time.get_ticks_usec(),input.command,input.held.fire,input.get("strafe",0.0),input.held.get("brake",false),input.get("mouse_response",false))
		else:accepted=session.step(Time.get_ticks_usec(),input.command,input.held.fire)
		if not accepted:
			if session is FirstFlightSession:transition_error(session.error)
			else:show_error(session.error)
			return
	if session.status=="arrival_transition_required" and not _transition_failed and ArrivalSession.supported(bindings):
		if not enter_arrival(Time.get_ticks_usec()):return
	if session.status=="local_arrival_transition_required" and not _transition_failed:
		if not enter_local_arrival(Time.get_ticks_usec()):return
	if session.status=="drive_arrival_transition_required" and not _transition_failed:
		if not enter_drive_arrival(Time.get_ticks_usec()):return
	if session.status=="gate_arrival_transition_required" and not _transition_failed:
		if not enter_gate_arrival(Time.get_ticks_usec()):return
	if session.status in ["sahi_arrival_transition_required","void_return_transition_required"] and not _transition_failed:
		if not enter_portal_arrival(Time.get_ticks_usec()):return
	if session.status in ["station_transition_required","station_reload_required","convoy_arrival_transition_required","mission_station_return_required"] and not _transition_failed and StationSession.supported(bindings):
		if not enter_station(Time.get_ticks_usec()):return
	if session.status=="game_over_transition_required" and not session.is_paused() and _focused and is_visible_in_tree():
		enter_game_over();return
	present_session()

func connect_station_panel(panel: Control) -> void:
	panel.next_requested.connect(func():station_navigation("next"))
	panel.previous_requested.connect(func():station_navigation("previous"))

func station_navigation(action: String) -> void:
	if session==null or not session is StationSession or not _focused or not is_visible_in_tree() or session.is_paused():return
	var recipe_checkpoint: bool=session.has_station_recipe_context()
	if not session.navigate(action,station_panel,_save_station_candidate):
		status.text=session.error;return
	present_session()
	# An unmanned station's notice launches the ship as it closes.
	if not session is StationSession:return
	if action=="next" and not recipe_checkpoint:_autosave_station()
	# The original reloads the station after a story talk, so a talk now
	# ready at this same station (e.g. Kothar 74 -> 75 -> 76) opens at once.
	if action=="next" and not session.snapshot().dialogue.visible and session.campaign_story_ready():
		if _begin_campaign_story():present_session()

func handle_hangar_back(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo or (event.physical_keycode if event.physical_keycode else event.keycode)!=KEY_ESCAPE:return false
	if not session is StationSession or not _focused or not is_visible_in_tree() or session.is_paused() or not session.snapshot().get("hangar_open",false):return false
	if not equipment_panel.back():return false
	get_viewport().set_input_as_handled();return true

func equipment_action(action: String, item_id: int=-1, slot_index: int=-1,quantity: int=1) -> bool:
	if not session is StationSession or not _focused or not is_visible_in_tree() or session.is_paused() or not _launch_packet.is_empty():return false
	if action=="open" and not equipment_panel.configure(library,bindings,visuals):status.text=equipment_panel.error;return false
	if not session.equipment_action(action,item_id,library,bindings,station_panel,equipment_panel,null,slot_index,quantity):
		equipment_panel.show_error(session.error);status.text=session.error;return false
	if action=="close" and session.campaign_story_ready():
		if not _begin_campaign_story():return false
	clear_input();present_session()
	if action=="open":_station_help("hangar")
	if action=="close":_autosave_station()
	return true

func handle_actions(actions: Array) -> void:
	for action in actions:
		if action=="pause":set_user_paused(not _user_paused)
		elif action=="mouse_mode":
			_mouse_steering=not _mouse_steering;clear_input();_sync_mouse_capture()
		elif session is MissionSession:
			if action=="action_menu":open_flight_menu(false);continue
			if not session.action(action):status.text=session.error
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
	if action=="wingmen":open_wingmen_menu();return
	if action in ["autopilot","action_menu"]:open_flight_menu(action=="autopilot");return
	if action=="khador" or (action=="jump" and session is FirstFlightSession and session.drive_fitted()):open_map(-1,true);return
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
	# Explicit source attachment changes capability, never the save identity.
	var identity:=_capability_identity()
	if _support_context!=bindings or _support_identity!=identity:
		_support_context=bindings;_support_identity=identity;_departure_support={}
	var key:="map:%d:%d"%[int(state.campaign_cursor),int(state.loadout.station_id)]
	if not _departure_support.has(key):
		var cat:=Catalogues.new()
		if not cat.open(library):return false
		var observation:=state.duplicate()
		observation.location={"station_id":int(state.loadout.station_id),"system_id":int(state.loadout.system_id)}
		_departure_support[key]=not MissionContext.navigation_destinations(bindings,cat,observation).is_empty()
	return _departure_support[key]

func _station_map_observation() -> Dictionary:
	var state: Dictionary=session.snapshot().duplicate()
	var cat:=Catalogues.new()
	if not cat.open(library):return {}
	var id: int=int(state.loadout.station_id)
	state.location={"station_id":id,"system_id":int(cat.tables.stations[id].system_id)}
	state.station_map=true
	if load("res://src/content/khador_drive_definitions.gd").fitted(state.loadout):
		var navigation=load("res://src/simulation/system_navigation.gd").new()
		if navigation.configure(bindings,cat,state.contracts.lounges.system_availability):
			var drive=load("res://src/simulation/khador_drive.gd").new()
			var destinations: Array=MissionContext.navigation_destinations(bindings,cat,state)
			if drive.configure(bindings,cat,state.loadout,state.contracts.difficulty,navigation,destinations):
				var energy:=0
				for row in state.cargo.entries:
					if row.item_id==122:energy+=int(row.quantity)
				state.drive_mode=true;state.drive_quotes={}
				for destination in destinations:
					if destination!=id:state.drive_quotes[destination]=drive.quote(destination,energy)
	return state

## wanted: the Most Wanted board's "Show on map" ({seen,to} stations): the
## galaxy map with his destination marked (the original also draws the route
## from his last stop; not drawn here).
func open_map(now_microseconds: int=-1,drive_mode:=false,wanted:={}) -> bool:
	if not _focused or not is_visible_in_tree():return false
	var docked: bool=_station_map_available()
	if drive_mode and not docked and (not session is FirstFlightSession or not session.request_drive_map()):present_session();return false
	if drive_mode and not docked and session.story_drive_destination()!=null:
		var jumped: bool=session.activate_story_drive(Time.get_ticks_usec() if now_microseconds<0 else now_microseconds)
		if not jumped:status.text=session.error
		clear_input();present_session();return jumped
	if drive_mode and not docked and session.snapshot().location.station_id<0 and session.flight_reader().drive_quote(-1).get("affordable",false):
		var started: bool=session.activate_drive_return(Time.get_ticks_usec() if now_microseconds<0 else now_microseconds)
		clear_input();present_session();return started
	if not docked and (not session is FirstFlightSession or (not drive_mode and not session.can_open_map())):return false
	var catalogues:=Catalogues.new()
	if not catalogues.open(library):status.text=catalogues.error;return false
	var observation: Dictionary=_station_map_observation() if docked else (session.drive_map_observation() if drive_mode and session.drive_available() else session.snapshot())
	if docked and not wanted.is_empty():observation=observation.duplicate();observation.wanted_marker=int(wanted.to);observation.wanted_from=int(wanted.seen)
	if not map_panel.configure(library,bindings,visuals,catalogues,observation):status.text=map_panel.error;return false
	var now:=Time.get_ticks_usec() if now_microseconds<0 else now_microseconds
	if docked:
		if not session.set_pause("map",true,now):map_panel.clear();status.text=session.error;return false
		_station_map_open=true
	elif not session.open_map(now,drive_mode):map_panel.clear();status.text=session.error;return false
	clear_input();present_session()
	if docked:_station_help("map")
	return true

func open_status(now_microseconds: int=-1) -> bool:
	if not session is StationSession or not session.has_contracts() or not _focused or not is_visible_in_tree() or session.is_paused():return false
	bank_career_stats()
	if not status_panel.configure(library,bindings,visuals) or not status_panel.present(session.station_owner().snapshot()):status.text=status_panel.error;return false
	if not session.set_pause("status",true,Time.get_ticks_usec() if now_microseconds<0 else now_microseconds):status_panel.clear();status.text=session.error;return false
	status_panel.set_mobile_layout(_mobile_layout)
	_status_open=true;clear_input();present_session();_station_help("status");return true

## The idle station shows each newly reached medal tier once, in order.
func _sync_medal_notice(state: Dictionary) -> void:
	var notices: Array=state.get("contracts",{}).get("medal_notices",[])
	# A medal waits while a station conversation is on screen.
	if notices.is_empty() or not _focused or state.get("dialogue",{}).get("visible",false):
		if notices.is_empty() or medal_notice.visible:medal_notice.clear()
		return
	if medal_notice.shown()==notices[0]:return
	if not status_panel.configure(library,bindings,visuals):status.text=status_panel.error;return
	medal_notice.present(status_panel,notices[0],float(state.get("contracts",{}).get("difficulty",Difficulty.NORMAL))!=Difficulty.EXTREME)

func acknowledge_medal_notice() -> bool:
	if not session is StationSession or not medal_notice.visible:return false
	if not session._world.acknowledge_medal_notice():status.text=session._world.error;return false
	medal_notice.clear();clear_input();_autosave_station();present_session();return true

func close_status(now_microseconds: int=-1) -> bool:
	if not _status_open:return false
	if session is StationSession:session.set_pause("status",false,Time.get_ticks_usec() if now_microseconds<0 else now_microseconds)
	_status_open=false;status_panel.clear();clear_input();present_session();return true

func open_missions(now_microseconds: int=-1) -> bool:
	if not session is StationSession or not session.has_contracts() or not _focused or not is_visible_in_tree() or session.is_paused():return false
	if not status_panel.configure(library,bindings,visuals) or not missions_panel.configure(status_panel,library,bindings,visuals) or not missions_panel.present(session.station_owner().snapshot()):status.text=status_panel.error+missions_panel.error;return false
	if not session.set_pause("missions",true,Time.get_ticks_usec() if now_microseconds<0 else now_microseconds):missions_panel.clear();status.text=session.error;return false
	_missions_open=true;clear_input();present_session();_station_help("missions");return true

func close_missions(now_microseconds: int=-1) -> bool:
	if not _missions_open:return false
	if session is StationSession:session.set_pause("missions",false,Time.get_ticks_usec() if now_microseconds<0 else now_microseconds)
	_missions_open=false;missions_panel.clear();clear_input();present_session();return true

## Missions log "Discard": the job's cargo and passengers leave, then the career autosaves.
func discard_mission() -> bool:
	if not _missions_open or not session is StationSession:return false
	if not session._world.discard_mission():status.text=session._world.error;return false
	_autosave_station()
	missions_panel.present(session.station_owner().snapshot());present_session();return true

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
	if not (session is FirstFlightSession or session is MissionSession) or not session.can_control() or not _focused:return false
	var state: Dictionary=session.snapshot();var rows:=[]
	if autopilot and session is FirstFlightSession:
		if state.get("station_autopilot",{}).get("active",false):rows.append({"action":"cancel_autopilot","label":library.strings[134]})
		if not state.get("scenery",{}).get("objects",[]).is_empty():rows.append({"action":"field_autopilot","label":library.strings[538]})
		if int(state.location.station_id)>=0:rows.append({"action":"station_autopilot","label":state.station_exterior.name+" "+library.strings[135]})
	elif session is FirstFlightSession:
		rows.append({"action":"autopilot","label":"Autopilot"})
		if session.can_open_map():rows.append({"action":"map","label":library.strings[176]})
		if session.drive_available():rows.append({"action":"khador","label":library.strings[int(bindings.station_equipment.item_text_offset)+85]})
		if session.secondary_available():rows.append({"action":"secondary_menu","label":library.strings[255]})
		if session.wingmen_available():rows.append({"action":"wingmen","label":library.strings[295]})
	if session is MissionSession and not autopilot and not session.flight_reader().secondary_feedback().get("weapons",[]).is_empty():rows.append({"action":"secondary_menu","label":library.strings[255]})
	var turret: Dictionary=session.turret_state()
	if not autopilot and turret.get("ready",false):rows.append({"action":"turret","label":library.strings[207]})
	if not autopilot and turret.get("auto",false) and not session is MissionSession:rows.append({"action":"auto_turret","label":library.strings[207]+" "+library.strings[39 if turret.get("auto_enabled",true) else 38]})
	var cloak: Dictionary=session.cloak_state()
	if not autopilot and cloak.get("ready",false):rows.append({"action":"cloak","label":library.strings[int(bindings.station_equipment.item_text_offset)+int(cloak.item_id)]})
	var extender: Dictionary=session.time_extender_state()
	if not autopilot and extender.get("phase") in ["ready","active"]:rows.append({"action":"time_extender","label":library.strings[int(bindings.station_equipment.item_text_offset)+int(extender.item_id)]})
	if rows.is_empty() or not flight_menu.configure(library,bindings,visuals):return false
	if not flight_menu.present(rows,KEY_Q if autopilot else KEY_E):return false
	if not session.set_pause("flight_menu",true,Time.get_ticks_usec()):flight_menu.close();status.text=session.error;return false
	clear_input();refresh_render_mode();return true

func open_wingmen_menu() -> bool:
	if not session is FirstFlightSession or not session.can_control() or not session.wingmen_available() or not _focused or not is_visible_in_tree():return false
	var groups: Array=session.snapshot().wingman_actors.weapon_groups
	# A missing route retains the previous order; it never invents a waypoint.
	var rows:=[{"action":"wingman_fire_at_will","label":library.strings[296]},
		{"action":"wingman_attack_target","label":library.strings[297]},
		{"action":"wingman_secure_waypoint","label":library.strings[298]}]
	rows.append({"action":"wingman_weapon_switch","label":library.strings[300 if groups[0]==0 else 299]})
	if not flight_menu.configure(library,bindings,visuals) or not flight_menu.present(rows,KEY_V):return false
	if not session.set_pause("flight_menu",true,Time.get_ticks_usec()):flight_menu.close();status.text=session.error;return false
	clear_input();refresh_render_mode();return true

func close_flight_menu() -> void:
	if session==null or not flight_menu.visible:return
	if not session.set_pause("flight_menu",false,Time.get_ticks_usec()):return
	flight_menu.close();clear_input();present_session()

func choose_flight_menu(action: String) -> void:
	if not flight_menu.visible or not flight_menu.snapshot().active:return
	close_flight_menu()
	if session is MissionSession:
		if not session.action(action):status.text=session.error
	else:flight_action(action)

func confirm_map_planet(station_id: int, now_microseconds: int=-1) -> bool:
	if _station_map_open:
		var choice: Dictionary=map_panel.snapshot()
		if choice.get("selected_station_id")!=station_id or not choice.get("confirmation_visible",false):return false
		_station_course_id=station_id
		_station_drive_course=choice.get("drive_mode",false) and not choice.get("gate_alternative",false) and choice.system_id!=session.snapshot().loadout.system_id
		if not close_map(now_microseconds):return false
		var cat:=Catalogues.new()
		if not cat.open(library):return transition_error(cat.error)
		_launch_packet=session.prepare_departure(bindings,cat)
		return enter_first_flight(Time.get_ticks_usec() if now_microseconds<0 else now_microseconds)
	if not session is FirstFlightSession or not _focused or not is_visible_in_tree() or map_panel.snapshot().get("selected_station_id")!=station_id or not map_panel.snapshot().get("confirmation_visible",false):return false
	if not session.map_active() and not (session.status=="gate_map_required" and session.gate_modal_active()):return false
	var now:=Time.get_ticks_usec() if now_microseconds<0 else now_microseconds
	var accepted: bool
	if session.status=="gate_map_required":accepted=session.close_gate_map(true,station_id,now)
	elif map_panel.snapshot().get("drive_mode",false) and not map_panel.snapshot().get("gate_alternative",false) and (station_id<0 or map_panel.snapshot().system_id!=session.snapshot().location.system_id):accepted=session.confirm_drive_destination(station_id,now)
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

## An unmanned station sends the ship straight back out, without the
## departure question.
func _force_departure() -> bool:
	var cat:=Catalogues.new()
	if not cat.open(library):return transition_error(cat.error)
	bank_career_stats()
	_launch_packet=session.prepare_departure(bindings,cat)
	if _launch_packet.is_empty():return transition_error(session.error)
	return enter_first_flight(Time.get_ticks_usec())

func request_departure() -> bool:
	if not session is StationSession or not _focused or not is_visible_in_tree() or session.is_paused() or not _launch_packet.is_empty():return false
	var state: Dictionary=session.snapshot()
	if state.get("lounge_open",false) or not _departure_available(int(state.campaign_cursor)):return false
	var cat:=Catalogues.new()
	if not cat.open(library):status.text=cat.error;return false
	bank_career_stats()
	var owner: RefCounted=session.station_owner()
	if owner!=null:
		var career: Dictionary=owner.snapshot().get("contracts",{})
		_elite_tracker.owned=EliteMedals.earned(career);_elite_tracker.capital_kills=int(career.get("progress",{}).get("capital_ship_kills",0))
	if session._world!=null and session._world.has_contracts() and state.get("loadout",{}).get("slots",[]).all(func(slot):return slot==null):session._world.record_stats({"unarmed_departures":1})
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
	var paid: Dictionary=lounge_panel.pending_result() if action=="result_close" else {}
	if session is StationSession:
		var checkpoint: Callable=_save_station_candidate if action in ["buy_coordinates","buy_blueprint","buy_diplomat","hire_wingmen","buy_kaamo"] else Callable()
		accepted=session.contract_action(action,id,lounge_panel,checkpoint)
	elif session is FirstFlightSession and action=="result_close":accepted=session.acknowledge_contract_result(id)
	if not accepted:lounge_panel.show_error(session.error);return false
	if paid.get("completed",false) and paid.get("continuation",{}).is_empty():reward_banner.show_reward(int(paid.get("reward_credits",paid.get("credit_delta",0))))
	if session is StationSession and session.contract_story_ready():
		if not _begin_contract_story():return false
	if session is StationSession and session.campaign_story_ready():
		if not _begin_campaign_story():return false
	clear_input();present_session()
	if action=="open" and session is StationSession:_station_help("lounge")
	if action in ["close","result_close","buy_goods"]:_autosave_station()
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
	# The old panel may still be emitting the click that got us here.
	var previous:=station_panel;station_panel=panel;connect_station_panel(panel);previous.get_parent().remove_child(previous);previous.queue_free()
	if _save_notice!=null:_save_notice.hide()
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
	# The autosave banks the play time spent on the question into the career,
	# which a contract departure compares with its packet.
	_launch_packet=session.prepare_departure(bindings,cat)
	if _launch_packet.is_empty():return transition_error(session.error)
	var candidate:=FirstFlightSession.new();viewport.add_child(candidate)
	var prepared: bool
	if _launch_packet.campaign_cursor==16 or FirstFlightSession.FreeFlight.Campaign.supported(bindings,_launch_packet.campaign_cursor):
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

func enter_drive_arrival(now_microseconds: int,environment_seconds: Variant=null,unix_seconds: Variant=null) -> bool:
	return _enter_flight_arrival(now_microseconds,environment_seconds,unix_seconds,false,true)

func _enter_flight_arrival(now_microseconds: int,environment_seconds: Variant,unix_seconds: Variant,gate: bool,drive:=false) -> bool:
	var boundary:="drive_arrival_transition_required" if drive else "gate_arrival_transition_required" if gate else "local_arrival_transition_required"
	if not session is FirstFlightSession or session.status!=boundary:return transition_error("The flight has not reached its destination transition")
	var locations: RefCounted
	var contract_trip: bool=session.flight_owner().contract_owner()!=null
	if gate and not contract_trip:return transition_error("Gate arrival lost its retained career")
	var settings:=_stock_settings() if contract_trip else {}
	if contract_trip and FirstFlightSession.FreeFlight.Campaign.supported(bindings,session.snapshot().campaign_cursor):settings.ship_price_percent=0
	if not drive and session.snapshot().campaign_cursor==40:return _enter_navigation40_arrival(now_microseconds,environment_seconds,unix_seconds,gate,settings)
	if StationGeneration.available(bindings) and not contract_trip:
		var departing: RefCounted=session.flight_owner()
		var trip: Dictionary=departing.prepare_local_arrival()
		var previous: Dictionary=departing.snapshot()
		if trip.is_empty():return transition_error(departing.error)
		locations=_prepare_locations(int(trip.station_id),previous.progress,previous.random_state,unix_seconds)
		if locations==null:return transition_error(_location_error)
	var candidate:=FirstFlightSession.new();viewport.add_child(candidate)
	var prepare: Callable=candidate.configure_drive_arrival if drive else candidate.configure_gate_arrival if gate else candidate.configure_local_arrival
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

func _enter_navigation40_arrival(now_microseconds: int,environment_seconds: Variant,unix_seconds: Variant,gate: bool,settings: Dictionary) -> bool:
	var cat:=Catalogues.new();var bodies:=FirstFlightSession.Bodies.new();var effects:=FirstFlightSession.Effects.new()
	if not cat.open(library) or not bodies.configure(library,bindings) or not effects.configure(library,bindings):return transition_error(cat.error+bodies.error+effects.error)
	var environment_seed: Variant=int(Time.get_unix_time_from_system()) if environment_seconds==null else environment_seconds
	var field_seed: Variant=int(Time.get_unix_time_from_system()) if unix_seconds==null else unix_seconds
	var departing: RefCounted=session.flight_owner()
	var construction: RefCounted=departing.construct_gate_arrival(bindings,cat,environment_seed,field_seed,true,bodies,effects,settings,library) if gate else departing.construct_local_arrival(bindings,cat,environment_seed,field_seed,true,bodies,effects,settings,library)
	if construction==null:return transition_error(departing.error)
	if construction is Selected40Session.Construction:
		var locations: RefCounted=construction.world_owner().career_owner().location_owner()
		if not enter_selected40_prepared(construction,now_microseconds):return false
		_locations=locations
		return true
	var candidate:=FirstFlightSession.new();viewport.add_child(candidate)
	if not candidate.configure_prepared_arrival(library,bindings,visuals,cat,construction,now_microseconds,int(field_seed),OS.has_feature("mobile")):
		var message:=candidate.error;candidate.free();session.camera.make_current();return transition_error(message)
	var locations: RefCounted=candidate.flight_owner().contract_owner().location_owner()
	if not _accept_first_flight(candidate,now_microseconds):return false
	_locations=locations
	return true

func _accept_first_flight(candidate: Node3D, now_microseconds: int,normal_return: RefCounted=null) -> bool:
	candidate.transition_rejected.connect(transition_error)
	if _station_course_id>=0 and not candidate.queue_map_destination(_station_course_id,_station_drive_course):
		var problem: String=candidate.error;candidate.free();session.camera.make_current()
		return transition_error(problem)
	for reason in ["user","hidden","focus"]:
		candidate.set_pause(reason,_user_paused if reason=="user" else not is_visible_in_tree() if reason=="hidden" else not _focused,now_microseconds)
	# Preparation may involve complete resource/scene construction. Recheck the
	# living source immediately before activating/swapping the staged candidate.
	if normal_return!=null and (not is_instance_of(normal_return,load("res://src/simulation/mission_portal_return.gd")) or not session is MissionSession or not normal_return.matches_departure(session.flight_owner())):
		candidate.free();session.camera.make_current()
		return transition_error("The Void departure changed while its normal-space candidate was prepared")
	if not candidate.activate():
		var message: String=candidate.error;candidate.free();session.camera.make_current();cancel_departure()
		return transition_error(message)
	_remember_docked()
	var previous:=session;session=candidate;previous.free();cancel_departure()
	_station_course_id=-1;_station_drive_course=false
	_save_notice.hide()
	station_panel.clear();radio_panel.clear();target_frame.clear();aim_reticle.clear();npc_markers.clear()
	lounge_panel.clear()
	map_panel.clear()
	gate_panel.clear()
	_transition_failed=false;_pause_button.disabled=false;clear_input();session.rebase_time(Time.get_ticks_usec())
	present_session();return true

## An explicit prepared-flight caller, not a new station departure capability.
## Admission of a saved career/travel result remains with its existing owners.
func enter_selected40_prepared(construction: RefCounted,now_microseconds: int) -> bool:
	return enter_mission_prepared(construction,now_microseconds)

func enter_mission_prepared(construction: RefCounted,now_microseconds: int) -> bool:
	if viewport==null or library==null or bindings==null or visuals==null:return false
	var catalogues:=Catalogues.new()
	if not catalogues.open(library):status.text=catalogues.error;return false
	var previous_camera: Camera3D=viewport.get_camera_3d()
	var candidate:=MissionSession.new();viewport.add_child(candidate)
	if not candidate.configure(library,bindings,visuals,catalogues,construction,now_microseconds,viewport.size):
		status.text=candidate.error;candidate.free()
		if previous_camera!=null:previous_camera.make_current()
		return false
	for reason in ["user","hidden","focus"]:
		candidate.set_pause(reason,_user_paused if reason=="user" else not is_visible_in_tree() if reason=="hidden" else not _focused,now_microseconds)
	if not candidate.activate():
		status.text=candidate.error;candidate.free()
		if previous_camera!=null:previous_camera.make_current()
		return false
	_remember_docked()
	var previous:=session;session=candidate
	if previous!=null:previous.free()
	cancel_departure();station_panel.clear();radio_panel.clear();target_frame.clear();aim_reticle.clear();npc_markers.clear();lounge_panel.clear();map_panel.clear();gate_panel.clear()
	candidate.transition_rejected.connect(func(message):status.text=message)
	_transition_failed=false;_last_game_over={};clear_input();present_session()
	return true

func enter_mission_portal(now_microseconds: int,environment_seconds: Variant=null,field_seconds: Variant=null) -> bool:
	if not session is MissionSession or session.is_paused() or session.status!="selected40_portal_transition_required":return transition_error("The living portal transition is not ready")
	var catalogues:=Catalogues.new()
	if not catalogues.open(library):return transition_error(catalogues.error)
	var constructor: RefCounted=load("res://src/simulation/mission_entry.gd").new()
	var now:=int(Time.get_unix_time_from_system())
	if not constructor.prepare_portal(bindings,catalogues,library,session.flight_owner(),now if environment_seconds==null else int(environment_seconds),now if field_seconds==null else int(field_seconds),1.0,viewport.size):return transition_error(constructor.error)
	if not enter_mission_prepared(constructor,now_microseconds):return transition_error(status.text)
	return true

func enter_mission_normal_space(now_microseconds: int,environment_seconds: Variant=null,field_seconds: Variant=null) -> bool:
	if not session is MissionSession or session.is_paused() or session.status!="normal_space_return_required":return transition_error("The living Void escape has not finished")
	var catalogues:=Catalogues.new()
	if not catalogues.open(library):return transition_error(catalogues.error)
	var transfer: RefCounted=load("res://src/simulation/mission_portal_return.gd").new()
	if not transfer.prepare(bindings,catalogues,session.flight_owner()):return transition_error(transfer.error)
	var bodies:=FirstFlightSession.Bodies.new();var effects:=FirstFlightSession.Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):return transition_error(bodies.error+effects.error)
	var now:=int(Time.get_unix_time_from_system())
	var field_seed: int=now if field_seconds==null else int(field_seconds)
	var construction:=FirstFlightSession.Construction.new()
	if not construction.prepare_mission_return(bindings,catalogues,transfer,now if environment_seconds==null else int(environment_seconds),field_seed,true,bodies,effects):return transition_error(construction.error)
	var previous_camera: Camera3D=viewport.get_camera_3d()
	var candidate:=FirstFlightSession.new();viewport.add_child(candidate)
	if not candidate.configure_prepared_arrival(library,bindings,visuals,catalogues,construction,now_microseconds,field_seed,_controls.touch_controls):
		var message: String=candidate.error;candidate.free()
		if previous_camera!=null:previous_camera.make_current()
		return transition_error(message)
	return _accept_first_flight(candidate,now_microseconds,transfer)

func _selected40_input(event: InputEvent) -> void:
	# Dialogue may consume the trigger as acknowledgement. Retain its neutral
	# requirement before that dispatch, so a repeated value cannot become a
	# fresh flight shot when the modal/cinematic gives control back.
	if not _focused or not is_visible_in_tree() or not session.can_control():_controls.discard_modal_event(event)
	if session.handle_selection_event(event):
		clear_input();present_session();get_viewport().set_input_as_handled();return
	if session.handle_game_over_event(event):
		clear_input();present_session();get_viewport().set_input_as_handled();return
	if not _focused or not is_visible_in_tree():return
	if _handle_cinematic_skip_event(event):return
	if session.orbit_event(event):get_viewport().set_input_as_handled();return
	var pause_event:=false
	if event is InputEventKey:pause_event=Controls.KEY_ACTIONS.get(event.physical_keycode if event.physical_keycode else event.keycode)=="pause"
	elif event is InputEventJoypadButton:pause_event=Controls.BUTTON_ACTIONS.get(event.button_index)=="pause"
	if (pause_event or (session.can_control() and session.supports_event(event))) and _controls.accept(event):
		handle_action_events(_controls.take_events());present_session();get_viewport().set_input_as_handled()

func _selected40_tick(now_microseconds: int) -> void:
	if _transition_failed:return
	handle_action_events(_controls.take_events())
	var input: Dictionary=_controls.snapshot() if session.can_control() else {"command":Vector2.ZERO,"held":{"fire":false}}
	if not session.step(now_microseconds,input.command,input.held.fire,input.get("mouse_response",false),input.get("strafe",0.0),input.held.get("brake",false),_controls.invert_pitch):
		transition_error(session.error);return
	if session.status=="game_over_transition_required" and not session.is_paused() and _focused and is_visible_in_tree():enter_game_over();return
	if session.status=="selected40_portal_transition_required" and not session.is_paused() and _focused and is_visible_in_tree():enter_mission_portal(now_microseconds);return
	if session.status=="normal_space_return_required" and not session.is_paused() and _focused and is_visible_in_tree():enter_mission_normal_space(now_microseconds);return
	present_session()

func enter_game_over() -> bool:
	if session is MissionSession:
		if session.status!="game_over_transition_required" or session.is_paused() or not _focused or not is_visible_in_tree():return false
		var selected_packet: Dictionary=session.prepare_game_over();var selected_state: Dictionary=session.snapshot()
		var selected_owner: RefCounted=session.flight_owner();var native_failure: Dictionary={}
		if load("res://src/simulation/mission_context.gd").from_owner(selected_owner)!=null and selected_owner.has_method("prepare_campaign_failure_exit"):
			native_failure=selected_owner.prepare_campaign_failure_exit()
		if not native_failure.is_empty():
			if native_failure.base_content_id!=bindings.base_content_id or native_failure.binding_id!=bindings.binding_id or native_failure.campaign_cursor!=int(selected_state.campaign_cursor):return transition_error("Mission failure exit changed the Host's source identity")
			# Keep the native campaign boundary and raw transition in the flight;
			# the acknowledged owner alone supplies the menu's exit receipt.
			selected_packet=native_failure
		else:
			var selected_expected:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"source_state":1,"campaign_cursor":int(selected_state.campaign_cursor)}
			var story_failed:=false
			if selected_state.get("campaign_phase","")=="failure_acknowledged":
				var failure:=selected_expected.duplicate(true);failure.outcome="failed";failure.reward_credits=0
				story_failed=selected_state.get("campaign_failure",{})==failure
				if story_failed:selected_expected.campaign_failure=failure
			var player_failed: bool=selected_state.player_destruction.phase=="game_over" and selected_state.player_destruction.exit_requested
			if selected_packet!=selected_expected or selected_state.boundary!="game_over_transition_required" or not (player_failed or story_failed):return transition_error("Selected game-over exit lost its accepted native state")
		var selected_result:={"transition":selected_packet.duplicate(true),"flight":selected_state.duplicate(true)}
		reset();_last_game_over=selected_result;status.text="Game over · Return to your saved game from the menu"
		if _player_mode:game_over_requested.emit()
		return true
	if not session is FirstFlightSession or session.status!="game_over_transition_required":return transition_error("The flight has not requested game-over exit")
	if _user_paused or not _focused or not is_visible_in_tree():return false
	var packet: Dictionary=session.prepare_game_over();var state: Dictionary=session.snapshot()
	var expected:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"source_state":1,"campaign_cursor":state.campaign_cursor}
	var rescue_failed:=false;var contest_failed:=false;var mission_failed:=false
	var failure: Dictionary=state.get("mining_objective",{}).get("campaign_failure",{})
	if not failure.is_empty():
		var visit: Dictionary=state.mining_objective.get("campaign_visit",{})
		rescue_failed=state.campaign_cursor==21 and failure==state.get("contracts",{}).get("flight",{}).get("story_failure") and failure.get("outcome")=="failed" and failure.get("source_state")==1 and failure.get("reward_credits")==0 and visit.get("phase")=="acknowledged" and visit.get("acknowledged")==true
		# The native contest frame owns scoring and final acknowledgement; its
		# receipt is not a lounge-contract result or Kappa's rescue ledger.
		var contest_receipt:=expected.duplicate(true)
		contest_receipt.outcome="failed";contest_receipt.reward_credits=0
		contest_failed=state.campaign_cursor==36 and FirstFlightSession.Frame.OrdinaryFlight.Bakka.context_valid(bindings,state.get("player",{}).get("bakka_context",{})) and state.mining_objective.get("phase")=="failure_acknowledged" and failure==contest_receipt
		var admitted: RefCounted=load("res://src/simulation/mission_context.gd").from_owner(session.flight_owner())
		mission_failed=admitted!=null and state.mining_objective.get("phase")=="failure_acknowledged" and failure==contest_receipt
		if rescue_failed or contest_failed or mission_failed:expected.campaign_failure=failure.duplicate(true)
	var player_failed: bool=state.get("player_destruction",{}).get("phase")=="game_over" and state.player_destruction.get("exit_requested",false)
	if packet!=expected or state.get("boundary")!="game_over_transition_required" or not (player_failed or rescue_failed or contest_failed or mission_failed):return transition_error("Game-over exit lost its accepted source state")
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
	if not reloading and (session==null or not (session is ArrivalSession or session is FirstFlightSession) or session.status not in ["station_transition_required","convoy_arrival_transition_required","mission_station_return_required"]):return transition_error("The flight has not reached station entry")
	var mission_return: bool=session.status=="mission_station_return_required"
	if mission_return and (_user_paused or not _focused or not is_visible_in_tree()):return false
	var returning:=session is FirstFlightSession
	var captured: bool=returning and session.status=="convoy_arrival_transition_required"
	var alioth_return: bool=returning and session.snapshot().get("campaign_cursor")==17
	var ordinary_return: bool=returning and FirstFlightSession.FreeFlight.Campaign.supported(bindings,session.snapshot().get("campaign_cursor"))
	var dekato_return: bool=returning and load("res://src/content/dekato_convoy_definitions.gd").station_supported(bindings,session.snapshot().get("campaign_cursor"),session.snapshot().get("equipment",{}).get("loadout",{}).get("station_id"))
	var captured_settings:=_stock_settings() if captured or alioth_return or mission_return else {}
	if captured or mission_return:captured_settings.ship_price_percent=0
	var seconds: Variant=int(Time.get_unix_time_from_system()) if unix_seconds==null else unix_seconds
	var transfer: RefCounted
	var continuation_catalogues: RefCounted
	if mission_return:
		var cat:=Catalogues.new()
		if not cat.open(library):return transition_error(cat.error)
		continuation_catalogues=cat
		transfer=load("res://src/simulation/mission_station_return.gd").new()
		var retained: RefCounted=session.flight_owner().contract_owner()
		if retained==null:return transition_error("The pending station continuation lost its retained career")
		captured_settings.difficulty=retained.snapshot().difficulty
		if not transfer.prepare(bindings,cat,library,session.flight_owner(),captured_settings,seconds):return transition_error(transfer.error)
	var packet: Dictionary={} if returning or reloading else session.prepare_station()
	if not returning and not reloading and packet.is_empty():return transition_error(session.error)
	var candidate:=StationSession.new();viewport.add_child(candidate)
	var prepared: bool
	if reloading:prepared=candidate.configure_reload(library,bindings,visuals,session.station_owner(),now_microseconds,camera_seed)
	elif mission_return:prepared=candidate.configure_mission_return(library,bindings,visuals,transfer,now_microseconds,camera_seed)
	elif returning:prepared=candidate.configure_return(library,bindings,visuals,session.flight_owner(),now_microseconds,camera_seed,captured_settings,seconds)
	else:prepared=candidate.configure(library,bindings,visuals,packet,now_microseconds,camera_seed)
	if prepared:prepared=candidate.retain_difficulty(_difficulty)
	if not prepared:
		var message:=candidate.error;candidate.free();session.camera.make_current()
		return transition_error(message)
	var locations: RefCounted
	if captured or alioth_return or ordinary_return or dekato_return or mission_return:locations=candidate.location_owner()
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
	if transfer!=null and not transfer.matches_departure(session.flight_owner()):
		panel.free();candidate.free();session.camera.make_current()
		return transition_error("The pending mission changed before station commit")
	if not candidate.activate():
		var message:=candidate.error;panel.free();candidate.free();session.camera.make_current()
		return transition_error(message)
	# A continuation autosave is part of this transaction, so the flight's
	# career stats are banked into it first. A checked atomic file failure
	# keeps the pending world, camera and previous save retryable.
	if transfer!=null:bank_career_stats(returning,candidate)
	if transfer!=null and not _save_directory.is_empty() and not _save_file.save(station_save_path(),candidate.station_owner(),bindings,continuation_catalogues,library,candidate.location_owner()):
		var message: String=_save_file.error;panel.free();candidate.free();session.camera.make_current()
		return transition_error(message)
	var previous:=session;var previous_panel:=station_panel
	session=candidate;station_panel=panel;connect_station_panel(panel)
	if locations!=null:_locations=locations
	previous.free();previous_panel.free();radio_panel.clear()
	target_frame.set_active(false);aim_reticle.clear();npc_markers.clear()
	session.rebase_time(Time.get_ticks_usec());_transition_failed=false;_pause_button.disabled=false;clear_input()
	refresh_render_mode()
	if transfer==null:
		bank_career_stats(returning)
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
	if not locations.select_location(bindings,cat,library,context,_stock_settings(),random_state,seconds):
		_location_error=locations.error;return null
	return locations

func _stock_settings() -> Dictionary:
	var settings:=BASE_STOCK_SETTINGS.duplicate(true);settings.difficulty=_difficulty
	return settings

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
	if session is StationSession and session.presentation_complete():
		_transition_failed=false
		present_session()
		return not _transition_failed
	if session.status=="arrival_transition_required":return enter_arrival(now)
	if session.status=="local_arrival_transition_required":return enter_local_arrival(now)
	if session.status=="drive_arrival_transition_required":return enter_drive_arrival(now)
	if session.status=="gate_arrival_transition_required":return enter_gate_arrival(now)
	if session.status in ["sahi_arrival_transition_required","void_return_transition_required"]:return enter_portal_arrival(now)
	if session.status in ["gate_confirmation_required","gate_map_required"]:
		session.set_pause("transition",false,now);_transition_failed=false;present_session();return not _transition_failed
	if session.status in ["station_transition_required","station_reload_required","convoy_arrival_transition_required","mission_station_return_required"]:return enter_station(now)
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
	if session is StationSession and not _transition_failed:
		if session.presentation_complete() and not session.is_paused():
			if not session.complete_presentation(station_panel,_save_station_candidate):transition_error(session.error);return
		if session.has_station_recipe_context() and not session.presentation_active() and not session.is_paused() and session.campaign_story_ready():
			if not _begin_campaign_story():return
		if not session.poll_wingman_farewell(station_panel,_save_station_candidate):transition_error(session.error);return
		if not session.poll_kaamo(station_panel,_save_station_candidate):transition_error(session.error);return
		if session.take_forced_departure() and not _force_departure():return
	# Medal notices belong to the idle station; one left open at launch waits for the next dock.
	if not session is StationSession and medal_notice.visible:medal_notice.clear()
	if session is MissionSession:
		if not session.can_control():clear_input()
		if session.is_paused():status.text="Paused · Esc / controller Start resumes"
		elif session.status!="running":status.text="This flight has reached an unimplemented travel or result boundary. No progress has been awarded."
		else:
			var observation: Dictionary=session.flight_observation()
			if observation.destruction_phase!="ready":status.text="Game over" if observation.game_over_visible else "Your ship was destroyed"
			elif not observation.entry_released:status.text="Entering the selected encounter"
			else:status.text="Steer: Mouse / arrows / stick · Fire: Space / trigger · Select secondary: G · EMP: R / left trigger · View: T"
		refresh_render_mode();return
	var secondary_error:=_present_secondaries()
	if not secondary_error.is_empty():transition_error(secondary_error);return
	var state: Dictionary=session.presentation_snapshot() if session.has_method("presentation_snapshot") else session.snapshot()
	if not bindings.mido_travel.get("map",{}).get("ui",{}).is_empty() and (session is FirstFlightSession or (session is Session and session.interactive) or session is StationSession):
		if not _prepare_chrome():return
		if session is FirstFlightSession and not flight_vitals.present(state):transition_error(flight_vitals.error);return
		if session is FirstFlightSession:_present_challenge(state.get("kill_score",{}))
		if session is FirstFlightSession and state.get("player") is Dictionary and int(state.player.get("max_hull",0))>0:
			_last_flight_hull_percent=clampi(int(state.player.get("vitals",{}).get("hull",-1))*100/int(state.player.max_hull),-1,100)
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
		elif state.phase in STATION_DEPARTURE_PHASES and _departure_available(int(state.campaign_cursor)):status.text=session.station_name+" · Depart when ready · Enter / controller A"+(" · Space Lounge: L" if state.campaign_cursor in [13,14] else " · Hangar: H" if FirstFlightSession.FreeFlight.Campaign.supported(bindings,state.campaign_cursor) and _shopping_available() else "")
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
		elif not state.get("encounter",{}).get("primaries",{}).is_empty():status.text="Steer: Mouse / arrows / stick · Fire: Space / right trigger · Mine / Dock: F / X · Autopilot: Q / Y · Speed: ] / /"
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

# --- In-flight pause window support (read-only career view, Action Freeze).

func _remember_docked() -> void:
	if session is StationSession and session.has_method("station_owner"):
		var owner: RefCounted=session.station_owner()
		if owner!=null:_docked_state=owner.snapshot()

## Career observation for the pause window: the last docked career with the
## flight's current story cursor, story mission and cargo hold.
func pause_state() -> Dictionary:
	var state: Dictionary=_docked_state.duplicate(true)
	if session==null or session is StationSession:return state
	var flight: Dictionary=session.snapshot()
	for key in ["campaign_cursor","mission","contracts","cargo"]:
		if flight.get(key) is Dictionary or (key=="campaign_cursor" and flight.has(key)):state[key]=flight[key]
	state.skip_available=session.has_method("story_skip_available") and session.story_skip_available()
	# The alien world (the Void) has no station: Missions is hidden there.
	state.alien_orbit=flight.get("location") is Dictionary and int(flight.location.get("station_id",0))<0
	return state

## Action Freeze: hide every HUD layer and keep rendering only the 3D view
## while the paused world stays still.
func set_action_freeze(value: bool) -> void:
	if not value:
		if _hud_hidden.is_empty():return
		for node in _hud_hidden:
			if is_instance_valid(node) and node!=self:node.visible=true
		_hud_hidden={};refresh_render_mode();return
	if not _hud_hidden.is_empty() or viewport==null:return
	var view: Node=viewport.get_parent()
	var nodes:=[]
	for node in view.get_parent().get_children():
		if node!=view:nodes.append(node)
	for node in get_children():
		if node is CanvasItem and not node.is_ancestor_of(view):nodes.append(node)
	for node in view.get_children():
		if node is CanvasItem:nodes.append(node)
	nodes.append_array(viewport.find_children("*","CanvasLayer",true,false))
	for node in nodes:
		if (node is CanvasItem or node is CanvasLayer) and node.visible:_hud_hidden[node]=true;node.visible=false
	_hud_hidden[self]=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS

func freeze_camera() -> Camera3D:return null if viewport==null else viewport.get_camera_3d()

## The player's ship position in the flight scene.
func freeze_pivot() -> Vector3:
	var scene: Variant=null if session==null else session.get("scene")
	if not scene is Node3D:return Vector3.ZERO
	var ship: Variant=scene.get("player")
	var geometry: Variant=scene.get("geometry")
	if not ship is Node3D and geometry is Node3D:ship=geometry.get("player")
	if ship is Node3D:return ship.global_position
	var pose: Variant=session.snapshot().get("player_pose")
	if pose is Transform3D:return scene.global_transform*pose.origin
	return Vector3.ZERO

## The original pause window belongs to free flight; cinematics, maps and
## transitions keep the main menu.
func flight_pausable() -> bool:
	return _player_mode and (session is FirstFlightSession or session is MissionSession) and session.status=="running"

## Supernova Challenge (main menu 282): a fresh flight of its own, built from
## an in-memory career. This host never has saves enabled for it.
var _challenge_hud: Control
var _challenge_done:=false

func start_challenge() -> bool:
	if viewport==null or library==null or bindings==null or visuals==null or not _save_directory.is_empty():return false
	var cat:=Catalogues.new();var bodies:=FirstFlightSession.Bodies.new();var effects:=FirstFlightSession.Effects.new()
	if not cat.open(library) or not bodies.configure(library,bindings) or not effects.configure(library,bindings):status.text=cat.error+bodies.error+effects.error;return false
	var entry:=preload("res://src/simulation/supernova_challenge_entry.gd").new()
	var seconds:=int(Time.get_unix_time_from_system())
	var construction: RefCounted=entry.prepare(bindings,cat,seconds,seconds,bodies,effects)
	if construction==null:status.text=entry.error;return false
	reset()
	var now:=Time.get_ticks_usec()
	var candidate:=FirstFlightSession.new();viewport.add_child(candidate)
	if not candidate.configure_prepared_arrival(library,bindings,visuals,cat,construction,now,seconds,_controls.touch_controls):
		status.text=candidate.error;candidate.free();return false
	candidate.transition_rejected.connect(transition_error)
	for reason in ["user","hidden","focus"]:
		candidate.set_pause(reason,_user_paused if reason=="user" else not is_visible_in_tree() if reason=="hidden" else not _focused,now)
	if not candidate.activate():status.text=candidate.error;candidate.free();return false
	session=candidate;_challenge_done=false
	_transition_failed=false;clear_input();session.rebase_time(Time.get_ticks_usec());refresh_render_mode()
	present_session();return true

func _present_challenge(readout: Dictionary) -> void:
	if readout.is_empty() and _challenge_hud==null:return
	if _challenge_hud==null:
		_challenge_hud=preload("res://src/presentation/kill_score_overlay.gd").new();flight_vitals.get_parent().add_child(_challenge_hud)
		_challenge_hud.configure(flight_vitals.theme.default_font,int(readout.get("window_ms",7500)),_mobile_layout)
	_challenge_hud.present(readout)
	if readout.get("finished",false) and not _challenge_done:
		_challenge_done=true;hold_paused(true);challenge_finished.emit(int(readout.score))

extends "res://tests/station_presentation.gd"
## Detached presentation fixtures. Mouse events use window pixels and a frame
## between DOWN, the host's ordinary refresh, and UP; no career is advanced.
const Dialogue=preload("res://src/presentation/station_dialogue_panel.gd")
const FlightMenu=preload("res://src/presentation/flight_action_menu.gd")
const Gate=preload("res://src/presentation/gate_confirmation_panel.gd")
const MapPanel=preload("res://src/presentation/local_map_panel.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Secondary=preload("res://src/presentation/secondary_weapon_panel.gd")
const Frontend=preload("res://src/presentation/player_frontend.gd")
const Preferences=preload("res://src/content/player_preferences.gd")
var _shell_actions:=[]
var _equipment_actions:=[]
var _slot_actions:=[]
var _dialogue_actions:=[]
var _menu_actions:=[]
var _gate_actions:=[]
var _map_actions:=[]
var _secondary_actions:=[]

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected content, bindings and visuals");finish();return
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new();var catalogues:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not visuals.open(args[2],library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+visuals.error+catalogues.error);finish();return
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(960,540)
	await station_controls(library,bindings,visuals)
	await dialogue_controls(library,bindings,visuals)
	await flight_menu_controls(library,bindings,visuals)
	await gate_controls(library,bindings,visuals)
	await map_controls(library,bindings,visuals,catalogues)
	await secondary_controls(library,bindings,visuals)
	await options_controls(args)
	finish()

func station_controls(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> void:
	var shell:=Shell.new();root.add_child(shell);shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.action_requested.connect(func(action):_shell_actions.append(action))
	if not shell.configure(library,bindings,visuals):check(false,shell.error);shell.free();return
	var state:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":"gb",
		"loadout":{"station_id":78},"cargo":{"used":3,"capacity":25},"contracts":{"credits":1000},"ui_actions":{}}
	for action in shell.ACTION_ORDER:state.ui_actions[action]={"visible":true,"enabled":true}
	if not shell.present(state):check(false,shell.error);shell.free();return
	shell.set_active(true);await process_frame
	for action in shell.ACTION_ORDER:
		var button: Button=shell._actions[action]
		if shell._navigation_scroll.is_ancestor_of(button):shell._navigation_scroll.ensure_control_visible(button)
		await process_frame
		var before:=_shell_actions.size()
		await click_refresh(button,func():check(shell.present(state),shell.error))
		check(_shell_actions.size()==before+1 and _shell_actions.back()==action,"Station shell missed mouse "+action)
	shell.free();await process_frame

	var panel:=Equipment.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.action_requested.connect(func(action,id):_equipment_actions.append([action,id]))
	panel.slot_action_requested.connect(func(action,id,index):_slot_actions.append([action,id,index]))
	if not panel.configure(library,bindings,visuals):check(false,panel.error);panel.free();return
	var shop_state:=inventory({"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":"gb"})
	if not panel.present(shop_state):check(false,panel.error);panel.free();return
	panel.set_active(true);await process_frame
	for tab in ["cargo","ship","shop"]:
		await click_refresh(panel._tabs[tab],func():check(panel.present(shop_state),panel.error))
		check(panel._tab==tab,"Hangar tab missed mouse "+tab)
	panel._rows[68].node.grab_focus();await process_frame
	var before:=_equipment_actions.size()
	await click_refresh(panel._rows[68].actions.buy,func():check(panel.present(shop_state),panel.error))
	check(_equipment_actions.size()==before+1 and _equipment_actions.back()==["buy",68],"Hangar Buy missed mouse release")
	panel.select_tab("cargo");panel._rows[68].node.grab_focus();await process_frame
	before=_equipment_actions.size()
	await click_refresh(panel._rows[68].actions.sell,func():check(panel.present(shop_state),panel.error))
	check(_equipment_actions.size()==before+1 and _equipment_actions.back()==["sell",68],"Hangar Sell missed mouse release")
	before=_equipment_actions.size()
	await click_refresh(panel._rows[68].actions.mount,func():check(panel.present(shop_state),panel.error))
	check(_equipment_actions.size()==before+1 and _equipment_actions.back()==["mount",68],"Hangar Mount missed mouse release")
	panel.select_tab("ship");panel._installed_rows[0].node.grab_focus();await process_frame
	before=_slot_actions.size()
	await click_refresh(panel._installed_rows[0].button,func():check(panel.present(shop_state),panel.error))
	check(_slot_actions.size()==before+1 and _slot_actions.back()==["unmount",0,0],"Hangar Unmount missed mouse release")
	before=_equipment_actions.size()
	await click_refresh(panel._close,func():check(panel.present(shop_state),panel.error))
	check(_equipment_actions.size()==before+1 and _equipment_actions.back()==["close",-1],"Hangar Close missed mouse release")
	panel.free();await process_frame

func dialogue_controls(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> void:
	var panel:=Dialogue.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.next_requested.connect(func():_dialogue_actions.append("next"))
	panel.previous_requested.connect(func():_dialogue_actions.append("previous"))
	if not panel.configure(library,bindings,visuals):check(false,panel.error);panel.free();return
	var state:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":"gb",
		"dialogue":{"visible":true,"speaker_id":0,"speaker_name":"Keith","text":"The route is clear.","index":1,"count":3,"previous_available":true}}
	if not panel.present(state):check(false,panel.error);panel.free();return
	panel.set_active(true);await process_frame
	for action in ["previous","next"]:
		var button: Button=panel._previous if action=="previous" else panel._next
		var before:=_dialogue_actions.size()
		await click_refresh(button,func():check(panel.present(state),panel.error))
		check(_dialogue_actions.size()==before+1 and _dialogue_actions.back()==action,"Dialogue missed mouse "+action)
	panel.free();await process_frame

func flight_menu_controls(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> void:
	var panel:=FlightMenu.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.chosen.connect(func(action):_menu_actions.append(action))
	if not panel.configure(library,bindings,visuals):check(false,panel.error);panel.free();return
	var rows:=[{"action":"dock","label":"Dock"},{"action":"time","label":"Time"},{"action":"autopilot","label":"Autopilot"}]
	if not panel.present(rows):check(false,panel.error);panel.free();return
	await process_frame
	for index in panel._buttons.size():
		var before:=_menu_actions.size()
		await click_refresh(panel._buttons[index],func():panel.set_active(true);panel._layout())
		check(_menu_actions.size()==before+1 and _menu_actions.back()==rows[index].action,"Flight action menu missed mouse "+rows[index].action)
	panel.free();await process_frame

func gate_controls(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> void:
	var panel:=Gate.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.choice_requested.connect(func(result):_gate_actions.append(result))
	var packet:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"confirmation_text_id":133}
	if not panel.present_departure(library,bindings,visuals,packet):check(false,panel.error);panel.free();return
	panel.set_active(true);await process_frame
	for button in [panel._no,panel._yes]:
		var before:=_gate_actions.size()
		await click_refresh(button,func():panel.set_active(true);panel._relayout())
		check(_gate_actions.size()==before+1 and _gate_actions.back()==(0 if button==panel._no else 1),"Gate/departure confirmation missed mouse "+button.text)
	panel.free();await process_frame

func map_controls(library: RefCounted,bindings: RefCounted,visuals: RefCounted,catalogues: RefCounted) -> void:
	if bindings.mido_travel.is_empty():return
	var panel:=MapPanel.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.destination_requested.connect(func(id):_map_actions.append(["destination",id]))
	panel.close_requested.connect(func():_map_actions.append(["close"]))
	var flight:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":10,
		"location":{"station_id":78,"system_id":15},"mission":{"kind":11,"station_id":79},"local_travel":{"phase":"flight"}}
	if not panel.configure(library,bindings,visuals,catalogues,flight):check(false,panel.error);panel.free();return
	panel.set_active(true);await process_frame
	await click_refresh(panel._key,func():panel._present())
	check(panel._legend.visible,"Map key missed mouse release")
	await click_refresh(panel._key,func():panel._present())
	check(not panel._legend.visible,"Map key did not close by mouse")
	panel.select_station(79)
	await click_refresh(panel._target,func():panel._present())
	check(panel.snapshot().confirmation_visible,"Map destination button missed mouse release")
	await click_refresh(panel._no,func():panel._present())
	check(not panel.snapshot().confirmation_visible,"Map No missed mouse release")
	await click_refresh(panel._target,func():panel._present())
	var before:=_map_actions.size()
	await click_refresh(panel._yes,func():panel._present())
	check(_map_actions.size()==before+1 and _map_actions.back()==["destination",79],"Map Yes missed mouse release")
	# The detached listener does not perform the host's destination transition.
	await click_refresh(panel._no,func():panel._present())
	before=_map_actions.size()
	await click_refresh(panel._back,func():panel._present())
	check(_map_actions.size()==before+1 and _map_actions.back()==["close"],"Map Back missed mouse release")
	panel.free();await process_frame
	if bindings.mido_travel.has("gate_arrival"):
		var gate_map:=MapPanel.new();root.add_child(gate_map);gate_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		gate_map.system_requested.connect(func(id):_map_actions.append(["system",id]))
		var gate_flight:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":18,
			"location":{"station_id":95,"system_id":19},"mission":{"kind":156,"station_id":56,"reward":0,"bonus":0,"source_parameter":0},
			"local_travel":{"phase":"flight"},"gate_destinations":[70,71,72,73,74],"gate_transit":{"phase":"flight"}}
		if gate_map.configure(library,bindings,visuals,catalogues,gate_flight):
			gate_map.set_active(true);await process_frame
			var before_system:=_map_actions.size()
			await click_refresh(gate_map._systems.get_child(1),func():gate_map._present())
			check(_map_actions.size()==before_system+1 and _map_actions.back()==["system",14],"Map system selector missed mouse release")
		else:check(false,gate_map.error)
		gate_map.free();await process_frame

func options_controls(args: PackedStringArray) -> void:
	# A private preferences directory keeps this UI check away from the player's save.
	var directory:=OS.get_cache_dir().path_join("gof2-mouse-audit-%d"%OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(directory)
	var app:=Frontend.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.boot(PackedStringArray(),directory)
	var selection:=Preferences.defaults();selection.content=args[0];selection.bindings=args[1];selection.visuals=args[2]
	if not app.select_content(selection):check(false,app.error);app.free();return
	app.show_options();await process_frame
	var scroll: ScrollContainer=app._body.get_parent()
	for key in ["invert_pitch","touch_controls","mouse_steering"]:
		var button: CheckButton=app._settings_controls[key]
		scroll.ensure_control_visible(button);await process_frame
		var before: bool=button.button_pressed
		await click_refresh(button,func():app._layout())
		check(button.button_pressed!=before and app.preferences.values[key]==button.button_pressed,"Options toggle missed mouse "+key)
	for key in ["ui_scale","window_mode","resolution","aspect_ratio","frame_rate"]:
		var choice: OptionButton=app._settings_controls[key]
		scroll.ensure_control_visible(choice);await process_frame
		await click_refresh(choice,func():app._layout())
		check(choice.get_popup().visible,"Options "+key+" selector did not open by mouse")
		choice.get_popup().hide()
	for key in ["music","fx","voice","mouse_sensitivity"]:
		var slider: HSlider=app._settings_controls[key]
		scroll.ensure_control_visible(slider);await process_frame
		var before: float=float(app.preferences.values[key])
		var rect: Rect2=slider.get_global_rect()
		var point:=rect.position+Vector2(rect.size.x*0.27,rect.size.y*0.5)
		await pointer_event(point,true);app._layout();await process_frame;await pointer_event(point,false)
		check(not is_equal_approx(float(app.preferences.values[key]),before),"Options slider missed mouse "+key)
	var files: Button
	for control in app._body.get_children():
		if control is Button and control.text=="Game files…":files=control;break
	check(files!=null,"Options game-file button is absent")
	if files!=null:
		scroll.ensure_control_visible(files);await process_frame
		await click_refresh(files,func():app._layout())
		check(app.phase=="setup","Options Game files missed mouse release")
	app.show_options();await process_frame
	await click_refresh(app._back,func():app._layout())
	check(app.phase=="menu","Options Back missed mouse release")
	app.free();await process_frame
	DirAccess.remove_absolute(directory.path_join("player.json"))
	DirAccess.remove_absolute(directory)

func secondary_controls(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> void:
	var panel:=Secondary.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.action_requested.connect(func(action):_secondary_actions.append(action))
	panel.selection_requested.connect(func(id):_secondary_actions.append(["select",id]))
	panel.selection_cancelled.connect(func():_secondary_actions.append("cancel"))
	if not panel.configure(library,bindings,visuals):check(false,panel.error);panel.free();return
	var sample:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"selected_item_id":41,
		"weapons":[{"item_id":41,"quantity":2,"live":false,"slot_index":0,"wait_ms":0}],
		"actions":[{"item_id":41,"action":"launched"}]}
	if not panel.present(sample):check(false,panel.error);panel.free();return
	panel.set_interaction(true,true);panel.set_hud_visible(true);await process_frame
	for data in [[panel._select,"secondary_menu"],[panel._fire,"missiles"]]:
		var before:=_secondary_actions.size()
		await click_refresh(data[0],func():check(panel.present(sample),panel.error))
		check(_secondary_actions.size()==before+1 and _secondary_actions.back()==data[1],"Secondary HUD missed mouse "+data[1])
	if panel.open_selection():
		await process_frame
		var before:=_secondary_actions.size()
		await click_refresh(panel._menu_confirm,func():check(panel.present(sample),panel.error))
		check(_secondary_actions.size()==before+1 and _secondary_actions.back()==["select",41],"Secondary Select missed mouse release")
		before=_secondary_actions.size()
		await click_refresh(panel._menu_cancel,func():check(panel.present(sample),panel.error))
		check(_secondary_actions.size()==before+1 and _secondary_actions.back()=="cancel","Secondary Cancel missed mouse release")
	else:check(false,panel.error)
	panel.free();await process_frame

func click_refresh(button: Button,refresh: Callable) -> void:
	check(button.visible and not button.disabled and button.is_visible_in_tree(),"Mouse target is not enabled: "+button.text)
	var point: Vector2=button.get_global_rect().get_center()
	await pointer_event(point,true)
	refresh.call();await process_frame
	await pointer_event(point,false)

func pointer_event(point: Vector2,down: bool) -> void:
	var window_point:=root.get_final_transform()*point
	if down:
		var motion:=InputEventMouseMotion.new();motion.position=window_point;motion.global_position=window_point
		Input.parse_input_event(motion);Input.flush_buffered_events();await process_frame
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
	event.position=window_point;event.global_position=window_point;event.pressed=down
	Input.parse_input_event(event);Input.flush_buffered_events();await process_frame

func finish() -> void:
	print("Mouse controls audit: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

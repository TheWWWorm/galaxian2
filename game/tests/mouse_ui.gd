extends SceneTree
## Real pointer delivery to the title, menu actions and lounge acknowledgements.
const Menu=preload("res://src/presentation/main_menu_panel.gd")
const GameHost=preload("res://src/presentation/opening_preview.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
var checks:=0
var failures:=0
var menu_actions: Array[String]=[]
var lounge_actions: Array[Dictionary]=[]

class MovingContact extends Node3D:
	var anchor:=Vector2(450,250)
	func select_contact(_id: int) -> void:pass
	func screen_contacts() -> Array:
		return [{"id":17,"rect":Rect2(anchor-Vector2(40,60),Vector2(80,120)),"anchor":anchor,"depth":1.0}]

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected content, bindings and visuals");finish();return
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new();var catalogues:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not visuals.open(args[2],library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+visuals.error+catalogues.error);finish();return
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(960,540)
	var host:=Control.new();root.add_child(host);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The player frontend is itself a full-screen Control with STOP mouse policy.
	var menu:=Menu.new();host.add_child(menu);menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.action_requested.connect(func(action):menu_actions.append(action))
	if not menu.configure(library,bindings,visuals):check(false,menu.error);finish();return
	menu.present(true,true);await process_frame
	for frame in 26:menu.advance_title(150.0)
	check(menu.snapshot().title_active and menu._title_prompt.visible,"The pointer test never reached the title prompt")
	await click(menu._title_prompt.get_global_rect().get_center())
	check(not menu.snapshot().title_active and menu._scroll.visible,"Mouse click did not dismiss Tap to continue")
	for action in ["new_game","resume","load","options","language","info"]:
		var button: Button=menu._buttons[action]
		await click(button.get_global_rect().get_center())
		check(menu_actions.size()>0 and menu_actions.back()==action,"Mouse click missed menu "+action)
	var before:=menu_actions.size()
	await click(menu._buttons.supernova.get_global_rect().get_center())
	check(menu_actions.size()==before,"Disabled Supernova menu action dispatched")
	await click(menu._exit.get_global_rect().get_center())
	check(menu_actions.size()==before+1 and menu_actions.back()=="exit","Mouse click missed Exit")
	menu.hide()

	var game_host:=GameHost.new();host.add_child(game_host);game_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_host.set_process(false);game_host._focused=true
	var lounge: Control=game_host.lounge_panel
	lounge.action_requested.connect(func(action,id):lounge_actions.append({"action":action,"id":id}))
	if not lounge.configure(library,bindings,visuals,catalogues):check(false,lounge.error);finish();return
	var career:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"station_id":79,"offers":{},"mission":{},"pending_result":{},"credits":100,
		"accepted_contact":{},"completed_side_missions":0,"population":{"contacts":[]}}
	var state:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"lounge_open":true,"contracts":career,"cargo":{},"contract_previews":{}}
	# Only the panel is under test; no station career is modified by these input cases.
	career.pending_result={"kind":0,"serial":7,"completed":true,"reward_credits":50}
	if not lounge.present(state):check(false,lounge.error);finish();return
	lounge.set_active(true)
	await process_frame
	check(lounge._yes.visible and lounge._yes.text==library.strings[180],"Contract result Close is not presented")
	await click_lounge(lounge,state,lounge._yes.get_global_rect().get_center())
	check(lounge_actions.size()==1 and lounge_actions[0]=={"action":"result_close","id":7},"Mouse click missed contract-result Close")
	career.pending_result={}
	career.offers={17:{"offer":{"mission":{"title_text_id":775,"briefing_text_id":775,"station_id":79,"quantity":1,"cargo_text_id":0,"reward":25,"bonus":0}},"consumed":false}}
	state.contract_previews={17:{"can_accept":true,"replacement_required":false}}
	if not lounge.present(state):check(false,lounge.error);finish();return
	lounge._selected=17;lounge._refresh();lounge._layout()
	var contact:=MovingContact.new();host.add_child(contact);lounge.set_scene(contact);await process_frame
	check(lounge._yes.visible and lounge._yes.text==lounge.label_text(847),"Contract Okay is not presented")
	var okay_point: Vector2=lounge._yes.get_global_rect().get_center()
	await pointer_event(okay_point,true)
	# The source camera travels for three seconds after lounge entry. The
	# acknowledgement panel must survive a presentation update during a press.
	contact.anchor=Vector2(850,420);lounge._process(0.016)
	check(lounge.present(state),lounge.error);await process_frame
	await pointer_event(okay_point,false)
	check(lounge.snapshot().confirming and lounge_actions.size()==1,"Mouse Okay moved away during the lounge camera transition")
	await click_lounge(lounge,state,lounge._no.get_global_rect().get_center())
	check(not lounge.snapshot().confirming and lounge_actions.size()==1,"Mouse No thanks missed cancellation")
	await click_lounge(lounge,state,lounge._yes.get_global_rect().get_center())
	await click_lounge(lounge,state,lounge._yes.get_global_rect().get_center())
	check(lounge_actions.size()==2 and lounge_actions[1]=={"action":"accept","id":17},"Mouse confirmation missed contract acceptance")
	# In the application the accepted state is presented immediately by the host.
	lounge._confirming=false;lounge._refresh()
	await click_lounge(lounge,state,lounge._back.get_global_rect().get_center())
	check(lounge_actions.size()==3 and lounge_actions[2]=={"action":"close","id":-1},"Mouse click missed lounge Back")
	host.free();finish()

func click(point: Vector2) -> void:
	await pointer_event(point,true)
	await pointer_event(point,false)

func click_lounge(lounge: Control,state: Dictionary,point: Vector2) -> void:
	await pointer_event(point,true)
	check(lounge.present(state),lounge.error)
	await process_frame
	await pointer_event(point,false)

func pointer_event(point: Vector2,down: bool) -> void:
	# Input.parse_input_event expects window pixels, including content scaling.
	var window_point:=root.get_final_transform()*point
	if down:
		var motion:=InputEventMouseMotion.new();motion.position=window_point;motion.global_position=window_point
		Input.parse_input_event(motion);Input.flush_buffered_events();await process_frame
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
	event.position=window_point;event.global_position=window_point;event.pressed=down
	Input.parse_input_event(event);Input.flush_buffered_events();await process_frame

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish() -> void:
	print("Mouse UI: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

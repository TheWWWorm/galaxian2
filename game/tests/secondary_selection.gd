extends "res://tests/secondary_feedback.gd"
## Selection UI and session/input routing around actual detached secondary owners.
## The protocol doubles omit scenery and presentation, not weapon validation.
## This does NOT construct an earned Kappa departure or a supported campaign save.
const MenuClock=preload("res://src/simulation/frame_clock.gd")
const TouchInput=preload("res://tests/fixtures/touch_input.gd")
var confirmations:=[]
var cancellations:=0

class MenuWorld extends RefCounted:
	var error:=""
	var encounter: RefCounted
	func _init(owner: RefCounted=null) -> void:encounter=owner
	func secondary_available() -> bool:return encounter!=null and encounter.has_secondaries()
	func fast_forward_available() -> bool:return false
	func secondary_feedback() -> Dictionary:return encounter.secondary_feedback()
	func dialogue_visible() -> bool:return false
	func snapshot() -> Dictionary:
		return {"encounter":encounter.snapshot(),"dialogue":{"visible":false},"entry_released":true,"location":{"campaign_cursor":21}}
	func select_secondary(item_id: int) -> RefCounted:
		var result: RefCounted=encounter.select_secondary(item_id)
		if result==null:error=encounter.error;return null
		return MenuWorld.new(result)

class PauseSink extends Node:
	var paused:=false
	func set_paused(value: bool) -> void:paused=value

class MenuSession extends "res://src/presentation/first_flight_session.gd":
	var reject_presentation:=false
	func can_control() -> bool:return _active and status=="running" and not is_paused()
	func can_stop_mining() -> bool:return false
	func can_open_map() -> bool:return false
	func handle_game_over_event(_event: InputEvent) -> bool:return false
	func flight_hud_visible(_state: Dictionary={}) -> bool:return _active and status=="running"
	func _sync_input() -> void:
		if not can_control():clear_flight_input()
	func _commit(world: RefCounted,_advance_sun: bool,_absolute_milliseconds: int=-1) -> bool:
		if reject_presentation:return reject("Injected presentation rejection")
		_world=world;_generation+=1;_sync_input();return true

class MenuApplication extends "res://src/presentation/opening_preview.gd":
	# Keep the real application input, signals, open/confirm/cancel and clearing.
	# Scene presentation is deliberately outside this detached routing fixture.
	func refresh_render_mode(_state: Dictionary={}) -> void:
		if secondary_panel==null:return
		var flight: bool=session is FirstFlightSession
		secondary_panel.set_interaction(flight and session.can_control() and _focused and is_visible_in_tree(),touch_actions_enabled())
		secondary_panel.set_hud_visible(flight and session.flight_hud_visible())
		secondary_panel.set_selection_active(flight and session.secondary_menu_active() and _focused and is_visible_in_tree())
	func present_session() -> void:
		if session==null:return
		var problem:=_present_secondaries()
		if not problem.is_empty():_transition_failed=true;status.text=problem;return
		if not session.can_control():clear_input()
		refresh_render_mode()

func _initialize() -> void:call_deferred("run_selection")

func run_selection() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [3,4]:check(false,"Expected content, bindings, visuals and optional captures")
	else:await verify_selection(args)
	await process_frame
	print("Secondary menu, pause and input routing: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_selection(args: PackedStringArray) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):check(false,lib.error+bindings.error+cat.error);return
	var panel:=WeaponPanel.new();root.add_child(panel)
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(960,540)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not OwnershipRules.available(bindings):
		check(not panel.configure(lib,bindings) and not panel.open_selection(),"Legacy content enabled the secondary menu")
		panel.free();return
	var built:=construction(bindings,cat,0.5)
	if built==null:panel.free();return
	var ship:=-1;var count:=0
	for row in cat.tables.ships:
		if row.stats.primary_slots>0 and int(row.stats.secondary_slots)>count:ship=int(row.id);count=mini(3,int(row.stats.secondary_slots))
	if ship<0 or count<2:check(false,"No original hull supports the menu's multi-launcher test");panel.free();return
	var entries:=[]
	for index in count:entries.append({"item_id":41+index,"slot":index,"quantity":2})
	# Multi-launcher UI uses the supported detached equipment owner. The live
	# encounter's target contract currently supports the starter hull only;
	# do not bypass that constructor to make a larger test menu.
	var menu_owner:=Ownership.new()
	if not menu_owner.configure(bindings,cat,equipped(bindings,cat,entries,ship)):check(false,menu_owner.error);panel.free();return
	var menu_sample: Dictionary=menu_owner.selection_feedback(-1)
	var menu_before: Dictionary=menu_owner.snapshot()
	var initial:=equipped(bindings,cat,[{"item_id":41,"slot":0,"quantity":2}])
	var views:=detached_views(bindings,cat,lib,initial,built.snapshot().random_state)
	if views.is_empty():panel.free();return
	var encounter:=detached_encounter(bindings,cat,lib,built,views)
	if encounter==null:check(false,"Cannot construct the detached encounter");panel.free();return
	if not encounter.configure_secondaries(bindings,cat,views.player,views.equipment):check(false,encounter.error);panel.free();return
	var stable: Dictionary=encounter.snapshot();var inventory:=view_snapshot(views)
	if not panel.configure(lib,bindings) or not panel.present(menu_sample):check(false,panel.error);panel.free();return
	panel.action_requested.connect(func(action):_signals.append(action))
	panel.selection_requested.connect(func(id):confirmations.append(id))
	panel.selection_cancelled.connect(func():cancellations+=1)
	panel.set_interaction(true,false);await process_frame
	await verify_menu_widget(panel,menu_sample)
	await verify_menu_layout(lib,bindings,panel,menu_sample,args[3] if args.size()==4 else "")
	check(menu_owner.snapshot()==menu_before,"Browsing changed the detached multi-launcher owner")
	panel.free()
	verify_menu_session(bindings,encounter)
	await verify_menu_application(lib,bindings,encounter)
	verify_last_round_menu(lib,bindings,cat,built)
	check(encounter.snapshot()==stable and view_snapshot(views)==inventory,"Menu tests modified retained ammunition, targets or player inventory")

func verify_menu_widget(panel: Control,sample: Dictionary) -> void:
	check(panel.open_selection(),panel.error)
	var expected: Array=sample.weapons.filter(func(row):return row.quantity>0).map(func(row):return {"item_id":row.item_id,"quantity":row.quantity})
	expected.append({"item_id":-1,"quantity":0})
	check(panel.selection_snapshot().choices==expected and panel.selection_snapshot().highlighted_item_id==-1,"Menu lost equipped order, ammunition or explicit None")
	var down:=menu_key(KEY_DOWN,true)
	panel.handle_selection_event(down);panel.handle_selection_event(down)
	check(panel.selection_snapshot().highlighted_item_id==expected[0].item_id,"A held menu key skipped multiple choices")
	panel.handle_selection_event(menu_key(KEY_DOWN,false))
	check(panel.snapshot().state==sample and confirmations.is_empty() and _signals.is_empty(),"Browsing changed selection or fired a weapon")
	panel.handle_selection_event(menu_key(KEY_R,true));panel.handle_selection_event(menu_key(KEY_R,false))
	panel._fire.pressed.emit();panel._select.pressed.emit()
	check(_signals.is_empty(),"A firing action escaped the menu")
	var enter:=menu_key(KEY_ENTER,true)
	panel.handle_selection_event(enter);panel.handle_selection_event(enter)
	enter.echo=true;panel.handle_selection_event(enter)
	panel.handle_selection_event(menu_key(KEY_ENTER,false))
	check(confirmations==[expected[0].item_id] and panel.snapshot().state==sample and panel.selection_snapshot().open,"Confirmation repeated or optimistically changed accepted state")
	confirmations.clear()
	var before: Dictionary=panel.snapshot();var bad:=sample.duplicate(true);bad.weapons[0].quantity=-1
	check(not panel.present(bad) and panel.snapshot()==before,"Rejected menu data changed the current choices")
	panel.set_selection_active(false)
	panel._menu_confirm.pressed.emit();panel._menu_cancel.pressed.emit()
	panel.handle_selection_event(menu_key(KEY_ENTER,true))
	panel.set_selection_active(true);panel.handle_selection_event(menu_key(KEY_ENTER,true))
	check(confirmations.is_empty() and cancellations==0,"A paused menu or held confirmation escaped its input boundary")
	panel.handle_selection_event(menu_key(KEY_ENTER,false))
	panel.set_hud_visible(false);panel._menu_confirm.pressed.emit();panel._menu_cancel.pressed.emit()
	check(confirmations.is_empty() and cancellations==0,"Hidden menu buttons emitted a choice")
	panel.set_hud_visible(true)
	panel.handle_selection_event(menu_key(KEY_ESCAPE,true));panel.handle_selection_event(menu_key(KEY_ESCAPE,true))
	check(cancellations==1 and panel.snapshot().state==sample,"Cancel repeated or changed the accepted launcher")
	panel.close_selection();cancellations=0
	check(panel.open_selection(),panel.error)
	await process_frame
	await click_button(panel._menu_rows.get_child(0))
	check(panel.selection_snapshot().highlighted_item_id==expected[0].item_id and confirmations.is_empty(),"Pointer browsing did not remain a preview")
	await click_button(panel._menu_confirm)
	check(confirmations==[expected[0].item_id] and _signals.is_empty(),"Pointer confirmation emitted more than one choice or fired")
	confirmations.clear();panel.close_selection()

func verify_menu_layout(lib: RefCounted,bindings: RefCounted,panel: Control,sample: Dictionary,captures: String) -> void:
	for language in ["gb","de","pl","ru"]:
		if not lib.select_language(language):check(false,lib.error);continue
		check(panel.configure(lib,bindings) and panel.present(sample),panel.error)
		for mobile in [false,true]:
			panel.close_selection();panel.set_mobile_layout(mobile);panel.set_interaction(true,mobile)
			root.size=Vector2i(1280,720) if mobile else Vector2i(960,540)
			check(panel.open_selection(),panel.error)
			for tick in 3:await process_frame
			var rect: Rect2=panel._menu.get_global_rect()
			check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(rect),"Secondary menu exceeds the landscape viewport")
			var previous:=Rect2()
			for index in panel._menu_rows.get_child_count():
				var row: Button=panel._menu_rows.get_child(index)
				var choice: Dictionary=panel.selection_snapshot().choices[index]
				check(rect.encloses(row.get_global_rect()) and row.size.y>=(56 if mobile else 42) and not previous.intersects(row.get_global_rect()),"Menu rows overlap or have undersized targets")
				previous=row.get_global_rect()
				var text_width: float=row.get_theme_font("font").get_string_size(row.text,HORIZONTAL_ALIGNMENT_LEFT,-1,row.get_theme_font_size("font_size")).x
				check(text_width<row.size.x-16,"Original secondary name is clipped")
				if choice.item_id!=-1:check(row.text.begins_with(lib.strings[choice.item_id+int(bindings.station_equipment.item_text_offset)]),"Menu did not use the active original item name")
			check(rect.encloses(panel._menu_confirm.get_global_rect()) and rect.encloses(panel._menu_cancel.get_global_rect()),"Menu actions are outside their panel")
			if DisplayServer.get_name()!="headless" and language=="gb" and not captures.is_empty():
				await RenderingServer.frame_post_draw
				var image:=root.get_texture().get_image();DirAccess.make_dir_recursive_absolute(captures)
				check(image!=null and image.save_png(captures.path_join("secondary-menu-"+("touch" if mobile else "desktop")+".png"))==OK,"Cannot save menu capture")
	panel.close_selection();lib.select_language("gb")

func make_menu_session(bindings: RefCounted,encounter: RefCounted) -> Node3D:
	var session:=MenuSession.new();session._world=MenuWorld.new(encounter)
	session._clock=MenuClock.new()
	if not session._clock.configure(bindings,bindings.base_content_id) or not session._clock.rebase(0):check(false,session._clock.error);session.free();return null
	session.briefing_audio=PauseSink.new();session.add_child(session.briefing_audio)
	session.objective_audio=PauseSink.new();session.add_child(session.objective_audio)
	session.status="running";session._active=true
	return session

func verify_menu_session(bindings: RefCounted,encounter: RefCounted) -> void:
	var session:=make_menu_session(bindings,encounter)
	if session==null:return
	var before: Dictionary=session.snapshot();var original: Dictionary=encounter.snapshot()
	session._secondary_requested=true
	check(session.open_secondary_menu(1000000) and session.secondary_menu_active() and not session.can_control() and not session._secondary_requested,"Menu failed to own a pause or clear a queued shot")
	check(session.briefing_audio.paused and session.objective_audio.paused and session.snapshot()==before,"Menu pause changed accepted gameplay or left audio unpaused")
	check(session.step(7000000) and session.snapshot()==before,"A paused menu advanced its weapon world")
	var clock_before: int=session._clock._last_ms
	check(not session.confirm_secondary(999,8000000) and session.snapshot()==before and session._clock._last_ms==clock_before and session.secondary_menu_active(),"Invalid selection partially committed or unpaused")
	check(not session.confirm_secondary(41,-1) and session.snapshot()==before and session.secondary_menu_active(),"Invalid menu timestamp committed a selection")
	session.reject_presentation=true
	check(not session.confirm_secondary(41,8000000) and session.snapshot()==before and session._clock._last_ms==clock_before and session.secondary_menu_active(),"Rejected presentation committed selection or clock")
	session.reject_presentation=false
	for reason in ["user","focus","hidden"]:
		check(session.set_pause(reason,true,8000000) and not session.secondary_menu_active(),"Nested pause left menu input enabled")
		check(not session.confirm_secondary(41,9000000) and not session.close_secondary_menu(9000000) and not session.action("missiles") and session.snapshot()==before,"A nested pause allowed selection, close or fire")
		check(session.set_pause(reason,false,9000000) and session.secondary_menu_active(),"Resuming a nested pause lost the weapons menu")
	check(session.confirm_secondary(41,10000000) and session.can_control() and not session.secondary_menu_open() and not session._secondary_requested,"Selection failed to return control cleanly")
	var expected:=original.duplicate(true);expected.selected_secondary=41
	check(session.snapshot().encounter==expected and session.snapshot().session_generation==1,"Confirm changed something other than the validated launcher choice")
	check(is_equal_approx(session._clock.sample(10016000,false),0.016),"The menu accumulated catch-up simulation time")
	var selected: Dictionary=session.snapshot()
	check(session.action("missiles") and session.open_secondary_menu(11000000) and not session._secondary_requested,"Reopening the menu did not discard queued activation")
	check(session.close_secondary_menu(13000000) and session.snapshot()==selected and not session._secondary_requested,"Cancellation changed selection, equipment or session generation")
	check(not session.confirm_secondary(-1,14000000) and session.snapshot()==selected,"A stale confirmation worked after the menu closed")
	session.free()

func verify_menu_application(lib: RefCounted,bindings: RefCounted,encounter: RefCounted) -> void:
	root.size=Vector2i(960,540)
	var app:=MenuApplication.new();root.add_child(app);app.set_process(false)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);app.set_context(lib,bindings,null)
	var session:=make_menu_session(bindings,encounter)
	if session==null:app.free();return
	app.viewport.add_child(session);app.session=session;app.present_session();await process_frame
	var before: Dictionary=session.snapshot()
	app._unhandled_input(menu_key(KEY_G,true));app._unhandled_input(menu_key(KEY_G,false))
	check(session.secondary_menu_active() and app.secondary_panel.selection_snapshot().open and session.snapshot()==before,"Application G did not open the menu without changing gameplay")
	app._unhandled_input(menu_key(KEY_DOWN,true));app._unhandled_input(menu_key(KEY_DOWN,false))
	var chosen: int=app.secondary_panel.selection_snapshot().highlighted_item_id
	check(chosen!=-1 and session.snapshot()==before and not session._secondary_requested,"Application browsing fired or committed early")
	check(not app.confirm_secondary_selection(999) and session.snapshot()==before,"Application accepted an unhighlighted selection")
	app._unhandled_input(menu_key(KEY_ENTER,true));app._unhandled_input(menu_key(KEY_ENTER,false))
	check(not session.secondary_menu_open() and session.snapshot().encounter.selected_secondary==chosen and not session._secondary_requested,"Application confirmation failed or queued fire")
	var selected: Dictionary=session.snapshot()
	app._unhandled_input(menu_pad(JOY_BUTTON_DPAD_RIGHT,true));app._unhandled_input(menu_pad(JOY_BUTTON_DPAD_RIGHT,false))
	check(session.secondary_menu_active(),"Controller could not open the menu")
	app._unhandled_input(menu_pad(JOY_BUTTON_B,true));app._unhandled_input(menu_pad(JOY_BUTTON_B,false))
	check(not session.secondary_menu_open() and session.snapshot()==selected and not session._secondary_requested,"Controller cancellation became a secondary activation")
	TouchInput.set_preference(app,true);app.present_session();await process_frame
	check(app._touch_detected and app.touch_actions_enabled(),"The menu touch fixture did not register a real device before enabling actions")
	await click_button(app.secondary_panel._select)
	check(session.secondary_menu_active(),"Touch Select did not route to the same menu")
	var motion:=InputEventJoypadMotion.new();motion.device=7;motion.axis=JOY_AXIS_TRIGGER_LEFT;motion.axis_value=0.9
	app._unhandled_input(motion)
	check(not session._secondary_requested,"A trigger inside the menu queued a shot")
	await click_button(app.secondary_panel._menu_cancel)
	app._unhandled_input(motion)
	check(not session.secondary_menu_open() and not session._secondary_requested,"A held modal trigger became a shot on return")
	motion.axis_value=0.0;app._unhandled_input(motion);motion.axis_value=0.9;app._unhandled_input(motion)
	check(session._secondary_requested,"A neutral-rearmed trigger no longer fires")
	check(app.open_secondary_menu() and not session._secondary_requested,"Application menu did not clear an already-queued trigger")
	app.hide();await process_frame
	check(session.secondary_menu_open() and not session.secondary_menu_active() and not app.confirm_secondary_selection(-1),"Hidden application allowed menu confirmation")
	app.show();await process_frame
	check(session.secondary_menu_active() and app.close_secondary_menu() and session.snapshot()==selected,"Visibility resume lost the menu or changed the selected world")
	app.reset()
	check(not app.secondary_panel.visible and not app.secondary_panel.selection_snapshot().open,"Application reset retained a stale menu")
	app.free();await process_frame

func verify_last_round_menu(lib: RefCounted,bindings: RefCounted,cat: RefCounted,built: RefCounted) -> void:
	var owner:=Ownership.new();var group:=active_group(bindings,cat,built,0)
	if group==null or not owner.configure(bindings,cat,equipped(bindings,cat,[{"item_id":41,"slot":0,"quantity":1}])):check(false,"Cannot prepare last-round owner");return
	var motion: Dictionary=owner.evaluate_advance(1,group,[0,1,2,3])
	if motion.is_empty():check(false,owner.error);return
	owner=motion.owner
	var launch: Dictionary=owner.evaluate_trigger(Transform3D.IDENTITY,41,motion.combat,[0,1,2,3])
	if launch.is_empty():check(false,owner.error);return
	owner=launch.owner
	var panel:=WeaponPanel.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var live: Dictionary=owner.selection_feedback(41);var before: Dictionary=owner.snapshot()
	check(panel.configure(lib,bindings) and panel.present(live),panel.error)
	panel.set_interaction(true,false)
	check(panel.open_selection() and panel.selection_snapshot().choices==[{"item_id":-1,"quantity":0}] and panel.selection_snapshot().highlighted_item_id==-1,"An exhausted launcher was offered as selectable ammunition")
	panel.close_selection()
	check(owner.snapshot()==before and panel.snapshot().state==live and live.weapons[0].live and live.actions==[{"item_id":41,"action":"detonated"}],"Browsing removed a live last round or its detonation action")
	panel.free()

func menu_key(code: int,down: bool) -> InputEventKey:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=down;return event

func menu_pad(code: int,down: bool) -> InputEventJoypadButton:
	var event:=InputEventJoypadButton.new();event.device=7;event.button_index=code;event.pressed=down;return event

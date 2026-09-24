extends SceneTree
## Detached station view/input checks. These display vectors do not earn a career.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Equipment=preload("res://src/presentation/station_equipment_panel.gd")
const Shell=preload("res://src/presentation/station_shell_panel.gd")
var checks:=0
var failures:=0
var capture_directory:=""

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [3,4]:check(false,"Expected content, bindings, visuals and optional captures");quit(1);return
	if args.size()==4:capture_directory=args[3];DirAccess.make_dir_recursive_absolute(capture_directory)
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):
		check(false,library.error+bindings.error+visuals.error);quit(1);return
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1920,1080)
	var shell:=Shell.new();root.add_child(shell);shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel:=Equipment.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var actions:=[];var slots:=[];var navigation:=[]
	panel.action_requested.connect(func(action,id):actions.append([action,id]))
	panel.slot_action_requested.connect(func(action,id,index):slots.append([action,id,index]))
	shell.action_requested.connect(func(action):navigation.append(action))
	for language in ["gb","de","ru"]:
		check(library.select_language(language),library.error)
		check(panel.configure(library,bindings,visuals),panel.error)
		check(shell.configure(library,bindings,visuals),shell.error)
		if failures:break
		var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":language}
		var state:=inventory(identity)
		check(panel.present(state),panel.error)
		check(panel._rows.has(93),"An owned item absent from shop offers disappeared from cargo")
		check(panel._rows[93].detail.text.is_empty(),"An unquoted item displayed an invented zero price")
		check(panel._row_art[1160].get_meta("source_image_id")==1160 and panel._row_styles[true] is StyleBoxTexture,"Selected row lost the original amber art")
		check(panel._rows[68].actions.buy.get_theme_stylebox("normal") is StyleBoxTexture,"Late shop row lost original button art")
		check(panel._installed_rows[0].button.get_theme_stylebox("normal") is StyleBoxTexture,"Late fitted slot lost original button art")
		check(panel._rows[68].quantity.text=="2","Quantity must not depend on an unavailable multiplication glyph")
		panel._rows[68].node.grab_focus()
		check(panel._selected_id==68 and panel._rows[68].action_box.visible and not panel._rows[0].action_box.visible,"Keyboard focus did not reveal just the selected item actions")
		panel._rows[68].actions.buy.pressed.emit()
		check(actions.back()==["buy",68],"Selected Buy changed its existing session action")
		panel.select_tab("ship");panel._installed_rows[0].node.grab_focus()
		check(panel._rows[68].node.visible and not panel._rows[68].actions.mount.disabled and not panel._rows[68].actions.sell.visible,"Ship fitting omitted compatible loose cargo or exposed Sell")
		check(panel._ship_band.visible and panel._ship_row.visible and panel._ship_name.text==panel._ship_names[0],"Fitting omitted the current ship heading")
		check(panel._selected_slot==0 and panel._installed_rows[0].button.visible and not panel._installed_rows[2].button.visible,"Fitted slot focus did not select its row action")
		await settle();key(KEY_TAB);await settle()
		check(root.gui_get_focus_owner()==panel._installed_rows[0].button,"Tab did not reach the selected slot action")
		var down:=InputEventJoypadButton.new();down.button_index=JOY_BUTTON_DPAD_DOWN;down.pressed=true;root.push_input(down)
		var up:=down.duplicate();up.pressed=false;root.push_input(up);await settle()
		check(root.gui_get_focus_owner()!=panel._installed_rows[0].button and panel._selected_slot!=0,"Controller navigation did not leave the selected slot action")
		panel._installed_rows[0].button.pressed.emit()
		check(slots.back()==["unmount",0,0],"Fitted action lost its exact slot index")
		panel._installed_rows[3].node.grab_focus()
		var slot_count:=slots.size();panel._installed_rows[3].button.pressed.emit()
		check(panel._installed_rows[3].button.disabled and slots.size()==slot_count,"Protected equipment emitted a disabled action")
		panel.select_tab("cargo");panel._rows[68].node.grab_focus()
		panel.set_active(false);var action_count:=actions.size();panel._rows[68].actions.mount.pressed.emit()
		check(actions.size()==action_count and panel._close.disabled,"Paused Hangar emitted a transaction")
		panel.set_active(true);panel._rows[68].actions.mount.pressed.emit()
		check(actions.back()==["mount",68],"Compatible Mount lost its existing session signal")
		var unsupported:=state.duplicate(true);unsupported.equipment.fitting_support[68]="This equipment is not supported."
		check(panel.present(unsupported),panel.error);panel._rows[68].node.grab_focus()
		check(panel._rows[68].actions.mount.disabled and panel._rows[68].detail.text.contains(unsupported.equipment.fitting_support[68]),"Selected unavailable equipment has no visible explanation")
		check(panel.present(state),panel.error)
		var station:=identity.duplicate();station.loadout={"station_id":78};station.cargo={"used":3,"capacity":25};station.contracts={"credits":1234567}
		station.ui_actions={}
		for action in shell.ACTION_ORDER:station.ui_actions[action]={"visible":true,"enabled":true}
		check(shell.present(station),shell.error)
		shell.set_active(false);var navigation_count:=navigation.size();shell._actions.depart.pressed.emit()
		check(navigation.size()==navigation_count,"Inactive station shell emitted departure")
		shell.set_active(true);shell._actions.depart.pressed.emit()
		check(navigation.back()=="depart","Footer departure lost the accepted action name")
		for form in [{"name":"desktop","size":Vector2i(1920,1080),"mobile":false},{"name":"compact","size":Vector2i(1280,720),"mobile":false},{"name":"touch","size":Vector2i(800,450),"mobile":true},{"name":"short-touch","size":Vector2i(640,360),"mobile":true}]:
			root.size=form.size;panel.set_mobile_layout(form.mobile);shell.set_mobile_layout(form.mobile)
			panel.select_tab("cargo");panel._rows[68].node.grab_focus()
			await settle()
			var viewport:=Rect2(Vector2.ZERO,Vector2(form.size))
			check(viewport.encloses(panel._panel.get_global_rect()) and viewport.encloses(panel._close.get_global_rect()),"Hangar exceeds "+form.name+" in "+language)
			check(viewport.encloses(panel._rows[68].actions.mount.get_global_rect()) and viewport.encloses(panel._rows[68].actions.sell.get_global_rect()),"Selected actions exceed "+form.name+" in "+language)
			check(panel._rows[68].icon.texture.get_meta("source_region")==68,"Layout switched source item art")
			if language=="gb" and form.name!="compact":
				await capture("cargo-"+form.name)
				panel.select_tab("shop");panel._rows[68].node.grab_focus();await settle();await capture("shop-"+form.name)
				panel.select_tab("ship");panel._installed_rows[0].node.grab_focus();await settle();await capture("ship-"+form.name)
				if form.name=="desktop":
					var unavailable:=state.duplicate(true);unavailable.equipment.stock[1].quantity=0
					check(panel.present(unavailable),panel.error);panel.select_tab("shop");panel._rows[68].node.grab_focus();await settle()
					check(panel._rows[68].actions.buy.disabled,"Sold-out stock enabled Purchase")
					await capture("shop-disabled-desktop")
					check(panel.present(state),panel.error);panel.select_tab("ship");panel._installed_rows[3].node.grab_focus();await settle()
					await capture("ship-protected-desktop")
			panel.hide();await settle()
			check(viewport.encloses(shell._actions.depart.get_global_rect()) and viewport.encloses(shell._actions.menu.get_global_rect()),"Station footer exceeds "+form.name+" in "+language)
			check(not shell._actions.depart.get_global_rect().intersects(shell._credits.get_global_rect()),"Departure overlaps the wallet")
			var before_click:=navigation.size();click(shell._actions.depart.get_global_rect().get_center());await settle()
			check(navigation.size()==before_click+1 and navigation.back()=="depart","Footer departure is not pointer-accessible at "+form.name)
			check(shell._navigation_scroll.position.y>=shell._faction.position.y+shell._faction.size.y,"Station navigation overlaps identity")
			shell._actions.load.grab_focus();await settle()
			if form.name=="short-touch":
				check(shell._navigation_scroll.scroll_vertical>0,"Short landscape cannot scroll to the last station action")
				check(shell._navigation_scroll.get_global_rect().encloses(shell._actions.load.get_global_rect()),"Focused station action remains clipped")
			if language=="gb" and form.name!="compact":await capture("station-"+form.name)
			panel.show()
		# Exercise real pointer propagation through the row thumbnail, not signal-only selection.
		root.size=Vector2i(1280,720);panel.set_mobile_layout(false);panel.select_tab("shop");await settle()
		var point: Vector2=panel._rows[0].icon.get_global_rect().get_center()
		click(point);await settle()
		check(panel._selected_id==0 and panel._rows[0].action_box.visible,"Clicking a thumbnail did not select its row")
		panel.clear();shell.clear()
	panel.free();shell.free();await process_frame
	print("Station presentation: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func inventory(identity: Dictionary) -> Dictionary:
	var result:=identity.duplicate();result.hangar_open=true;result.contracts={"credits":20000}
	result.equipment={"ordinary_shopping_open":true,"requirements":{"weapon_installed":true,"armor_installed":true},
		"cargo":{"used":3,"capacity":25,"entries":[{"item_id":68,"quantity":1},{"item_id":93,"quantity":2}]},
		"stock":[{"item_id":0,"quantity":1,"unit_price":0},{"item_id":68,"quantity":2,"unit_price":8400}],
		"market_rows":[{"item_id":0,"stock":1,"owned":0,"unit_price":0,"mission":false},{"item_id":68,"stock":2,"owned":1,"unit_price":8400,"mission":false}],
		"loadout":{"ship_id":0,"slots":[{"item_id":0,"category":0,"slot":0,"quantity":1},null,{"item_id":55,"category":3,"slot":0,"quantity":1},{"item_id":81,"category":3,"slot":1,"quantity":1},null]},
		"fitting_support":{68:""},"fitting_conflicts":{},"fitting_stats":{"hull":95,"armor":40,"shield":0,"handling_bonus_percent":0,"passenger_capacity":0},"protected_item_ids":[81,90]}
	return result

func click(point: Vector2) -> void:
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=point
	root.push_input(press)
	var release:=press.duplicate();release.pressed=false;root.push_input(release)

func key(code: int) -> void:
	var press:=InputEventKey.new();press.keycode=code;press.physical_keycode=code;press.pressed=true;root.push_input(press)
	var release:=press.duplicate();release.pressed=false;root.push_input(release)

func settle() -> void:
	await process_frame;await process_frame

func capture(name: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_directory.path_join(name+".png"))==OK,"Could not save "+name)

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

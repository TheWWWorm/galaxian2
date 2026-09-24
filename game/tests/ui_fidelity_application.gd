extends "res://tests/free_application.gd"
## Live station and flight UI acceptance from the earned, paid Carme save.

func _initialize() -> void:
	if OS.get_environment("GOF2_SOURCE_SAVE").is_empty():
		call_deferred("missing_carme_save")
	else:
		call_deferred("run_free_checkpoint")

func missing_carme_save() -> void:
	check(false,"Set GOF2_SOURCE_SAVE to the earned fitted Carme save")
	quit(1)

func verify_free_application() -> void:
	var directory:=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if directory.is_empty() or not FreePlayCheckpoint.private_path(directory.path_join("save.bin")):
		check(false,"Set a private application save directory");return
	var original: Dictionary=app.session.station_owner().snapshot()
	check(original.campaign_cursor==24 and original.loadout.station_id==37 and original.contracts.credits==6161 and original.contracts.passengers==3,"Resume the actual paid/fitted Carme career at cursor24")
	check(original.loadout.equipment_ids.has(2) and original.loadout.equipment_ids.has(68) and original.loadout.equipment_ids.has(91),"The retained ship lost its paid primary, tractor or cabin")
	if failures:return
	var tractor_slot:=-1
	for index in original.loadout.slots.size():
		if original.loadout.slots[index]!=null and int(original.loadout.slots[index].item_id)==68:tractor_slot=index;break
	check(tractor_slot>=0,"The earned tractor is not mounted in an actual ship slot")
	if failures:return
	app.enable_saves(directory)
	app.set_player_mode(true)
	app.show();app.present_session();await process_frame;resume_application_focus();app.present_session()
	check(app.station_shell.visible and app.station_shell._actions.hangar.visible and not app.station_shell._actions.hangar.disabled,"The live Carme station did not expose the shell Hangar action")
	check(app.station_shell._station.text==catalogue.tables.stations[37].name and app.station_shell._credits.text.contains("6161") and app.station_shell._cargo.text.contains(str(original.cargo.used)),"The live station shell lost its source station, wallet or cargo")
	check(not app._hangar_button.visible and not app._launch_button.visible,"The station shell left duplicate legacy actions visible")
	check(app.session.station_sky!=null and app.session.station_sky.selection.station_id==37 and app.session.station_sky.layers.size()==2,"The earned station did not draw its source exterior through the hangar window")
	await capture_free_application("ui-carme-station-desktop")
	if failures:return
	app.station_shell._actions.hangar.pressed.emit()
	var opened: Dictionary=app.session.station_owner().snapshot()
	check(opened.hangar_open and app.equipment_panel.visible and not app.station_shell.visible,"The shell Hangar action did not dispatch through the application")
	check(app.equipment_panel._credits==6161 and app.equipment_panel._wallet.text.contains("6161") and app.equipment_panel._installed_rows.has(tractor_slot),"The live Hangar omitted the wallet or fitted slot")
	check(not app.status.visible and not app._menu_button.visible and not app._save_button.visible and not app._load_button.visible,"Hangar retained the outer native toolbar above its source header")
	if failures:return
	app.equipment_panel.select_tab("ship")
	await capture_free_application("ui-carme-hangar-desktop")
	app.equipment_panel._installed_rows[tractor_slot].button.pressed.emit()
	var unmounted: Dictionary=app.session.station_owner().snapshot()
	check(unmounted.loadout.slots[tractor_slot]==null and unmounted.cargo.entries.any(func(row):return int(row.item_id)==68 and int(row.quantity)==1),"The actual Unmount button did not return the owned tractor to cargo")
	check(unmounted.loadout.equipment_ids.has(91) and unmounted.contracts.credits==6161 and unmounted.contracts.passengers==3 and unmounted.mission==original.mission,"Unmounting changed the paid wallet, cabin, passengers or story")
	if failures:return
	app.equipment_panel.select_tab("cargo")
	check(app.equipment_panel._rows.has(68) and not app.equipment_panel._rows[68].actions.mount.disabled,"The owned tractor cannot remount in its vacated slot")
	if failures:return
	app.equipment_panel._rows[68].actions.mount.pressed.emit()
	var remounted: Dictionary=app.session.station_owner().snapshot()
	check(remounted.loadout.slots[tractor_slot]!=null and int(remounted.loadout.slots[tractor_slot].item_id)==68 and remounted.loadout.equipment_ids==original.loadout.equipment_ids,"The actual Mount button did not restore the paid loadout")
	check(remounted.cargo==original.cargo and remounted.contracts.credits==6161 and remounted.contracts.passengers==3 and remounted.contracts.mission==original.contracts.mission,"Remounting changed retained cargo, wallet or passenger job")
	if failures:return
	app.equipment_panel._close.pressed.emit()
	check(not app.session.snapshot().hangar_open and app.station_shell.visible,"Closing Hangar did not return to the station shell")
	if failures:return
	app.station_shell._actions.save.pressed.emit()
	check(FileAccess.file_exists(app.station_save_path()),"The station shell Save action did not write the fitted career")
	if failures:return
	check(app.load_station(now_us),app._save_notice.text)
	if failures:return
	var loaded: Dictionary=app.session.station_owner().snapshot()
	check(loaded.campaign_cursor==24 and loaded.loadout.station_id==37 and loaded.loadout.equipment_ids==original.loadout.equipment_ids and loaded.cargo==original.cargo,"The saved Carme loadout or cargo was not restored")
	check(loaded.contracts.credits==6161 and loaded.contracts.passengers==3 and loaded.contracts.mission==original.contracts.mission and loaded.mission==original.mission,"Loading changed the paid wallet, passengers or pending story")
	check(app.station_shell.visible and not app.equipment_panel.visible,"The loaded station did not restore its shell")
	if failures:return
	app.station_shell._actions.depart.pressed.emit()
	check(not app._launch_packet.is_empty() and app._launch_dialog.visible,"The station shell Depart action omitted the real confirmation")
	if failures:return
	if not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	check(not app.station_shell.visible and not app.flight_vitals.visible,"Flight chrome appeared before Carme launch released its HUD")
	if not await release_carme_flight():return
	var flight: Dictionary=app.session.snapshot()
	check(flight.location.station_id==37 and flight.campaign_cursor==24 and flight.player.equipment_ids==loaded.loadout.equipment_ids and flight.cargo==loaded.cargo,"Carme departure lost the fitted tractor or retained career")
	check(app.flight_vitals.visible and app.flight_vitals._cargo_text.text=="%d / %dt"%[flight.cargo.used,flight.cargo.capacity],"The live flight HUD omitted accepted cargo totals")
	var hull_max: int=int(flight.player.get("max_hull",catalogue.tables.ships[int(flight.player.ship_id)].stats.armor))
	check(absf(app.flight_vitals._hull_ratio-float(flight.player.vitals.hull)/float(hull_max))<0.001 and app.flight_vitals._shield_visible==(int(flight.player.capacities.shield)>0),"Flight gauges disagree with accepted Carme hull or shield capacity")
	check(not app._flight_actions.visible and not app.touch_overlay.visible and not app._pause_button.visible,"Desktop flight showed touch-only actions without detected touch")
	await capture_free_application("ui-carme-flight-desktop")
	if failures:return
	await verify_touch_gates()

func release_carme_flight() -> bool:
	app.session.rebase_time(now_us)
	for tick in 71:
		if app.session.can_control() and app.session.flight_audio!=null:break
		if not application_step():return false
	check(app.session.can_control() and app.session.flight_audio!=null,"The actual Carme departure did not release flight controls")
	return failures==0

func verify_touch_gates() -> void:
	root.size=Vector2i(960,540)
	app._touch_detected=false;app.set_mobile_layout(true);app.set_touch_controls(true)
	await process_frame;resume_application_focus();app.present_session()
	check(not app.touch_actions_enabled() and not app._flight_actions.visible and not app.touch_overlay.visible and not app._pause_button.visible,"Mobile layout and preference alone exposed touch actions")
	check(app.flight_vitals.visible,"Mobile layout removed accepted flight vitals")
	var simulated:=InputEventScreenTouch.new();simulated.pressed=true;simulated.device=InputEvent.DEVICE_ID_EMULATION;simulated.index=0
	app._input(simulated)
	check(not app._touch_detected and not app.touch_actions_enabled() and not app._flight_actions.visible,"Emulated mouse touch enabled flight buttons")
	var actual:=InputEventScreenTouch.new();actual.pressed=true;actual.device=0;actual.index=0
	app._input(actual);app.present_session()
	check(app._touch_detected and app.touch_actions_enabled() and app._flight_actions.visible and app.touch_overlay.visible and app._pause_button.visible,"Real touch did not enable the preferred flight buttons")
	check(app.touch_overlay.sprites.has(1205) and app.touch_overlay.sprites[1205].get_meta("source_image_id")==1205 and app._mine_button.get_theme_stylebox("normal") is StyleBoxTexture and not app._load_button.visible,"Touch flight kept placeholder controls or the desktop Load toolbar")
	check(app._pause_button.get_theme_stylebox("normal") is StyleBoxTexture and not app._pause_button.get_global_rect().intersects(app.flight_vitals._cargo_frame.get_global_rect()),"The source Pause action is hidden behind the cargo counter")
	var fire_center: Vector2=app.touch_overlay.get_global_transform_with_canvas()*app.touch_overlay.fire_center()
	var fire_extent: Vector2=Vector2.ONE*app.touch_overlay.fire_radius()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(app._flight_actions.get_global_rect()) and not app._map_button.get_global_rect().intersects(Rect2(fire_center-fire_extent,fire_extent*2.0)),"Touch action layout exceeds landscape bounds or covers primary fire")
	check(app.flight_vitals.visible and app.flight_vitals._cargo_text.text.contains(str(app.session.snapshot().cargo.used)),"Touch flight hid its source vitals or cargo")
	await capture_free_application("ui-carme-flight-touch-landscape")
	if failures:return
	tap_action(app._map_button)
	await process_frame
	check(app.session.map_active(),"The source Map touch button did not open the live map")
	if failures:return
	check(not app.flight_vitals.visible and not app._flight_actions.visible and not app.touch_overlay.active,"Map modal left flight gauges or touch actions active")
	check(app.close_map(now_us),app.status.text)
	if failures:return
	check(app.flight_vitals.visible and app._flight_actions.visible and app.touch_overlay.active,"Closing the map did not restore live flight chrome")
	app.set_user_paused(true)
	check(not app.touch_overlay.active and app._mine_button.disabled and app._map_button.disabled,"Pause left touch flight input active")
	app.set_user_paused(false);app.session.rebase_time(now_us);app.present_session()
	check(app.touch_overlay.active and not app._mine_button.disabled,"Resuming did not restore touch input")
	app.set_touch_controls(false)
	check(not app.touch_actions_enabled() and not app._flight_actions.visible and not app.touch_overlay.visible and not app._pause_button.visible,"Disabling the preference left touch buttons visible")
	root.size=Vector2i(1280,720);app.set_mobile_layout(false)
	await process_frame;resume_application_focus();app.present_session()
	check(app.flight_vitals.visible and app.session.snapshot().campaign_cursor==24 and app.session.snapshot().contracts.credits==6161,"UI checks changed the earned campaign or lost flight vitals")

func tap_action(button: Button) -> void:
	var point:=button.get_global_rect().get_center()
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=point
	root.push_input(press)
	var release:=press.duplicate();release.pressed=false;root.push_input(release)

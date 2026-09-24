extends SceneTree
## Presentation-only checks using imported Mac content; no career is advanced.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Equipment=preload("res://src/presentation/station_equipment_panel.gd")
const Shell=preload("res://src/presentation/station_shell_panel.gd")
const Vitals=preload("res://src/presentation/flight_vitals_overlay.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [3,4]:check(false,"Expected content, bindings, visuals and optional captures");quit(1);return
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest) or not cat.open(library):
		check(false,library.error+bindings.error+visuals.error+cat.error);quit(1);return
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1280,720)
	var shell:=Shell.new();root.add_child(shell);shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hud:=Vitals.new();root.add_child(hud);hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var equipment:=Equipment.new();root.add_child(equipment);equipment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for language in ["gb","de","ru"]:
		if not library.select_language(language):check(false,library.error);continue
		check(shell.configure(library,bindings,visuals),shell.error)
		check(hud.configure(library,bindings,visuals),hud.error)
		check(equipment.configure(library,bindings,visuals),equipment.error)
		if not shell.error.is_empty() or not hud.error.is_empty() or not equipment.error.is_empty():continue
		var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":language}
		var station:=identity.duplicate()
		station.loadout={"station_id":78};station.cargo={"used":3,"capacity":25};station.contracts={"credits":6161}
		station.ui_actions={"hangar":{"visible":true,"enabled":true},"lounge":{"visible":true,"enabled":false},"depart":{"visible":true,"enabled":true},"save":{"visible":true,"enabled":true},"load":{"visible":false,"enabled":false},"menu":{"visible":true,"enabled":true}}
		check(shell.present(station),shell.error)
		check(shell._station.text==cat.tables.stations[78].name and shell._system.text==cat.tables.systems[15].name,"Station shell lost catalogue identity")
		check(shell._tech.text.contains(str(cat.tables.stations[78].fields[2])) and shell._faction_icon.texture!=null,"Station shell lost source tech/faction art")
		check(shell._actions.hangar.text==library.strings[166] and shell._actions.lounge.disabled and not shell._actions.load.visible,"Station actions lost localized visibility/availability")
		var emitted:=[];shell.action_requested.connect(func(action):emitted.append(action),CONNECT_ONE_SHOT)
		shell._actions.hangar.pressed.emit()
		check(emitted==["hangar"],"Station shell action did not hand off without touching a session")
		var flight:=identity.duplicate()
		flight.player={"ship_id":0,"vitals":{"hull":47,"armor":20,"shield":25.0},"capacities":{"armor":40,"shield":50}}
		flight.cargo={"used":1,"capacity":25}
		flight.control_throttle=1.0
		check(hud.present(flight),hud.error)
		check(absf(hud._hull_ratio-47.0/95.0)<0.001 and absf(hud._shield_ratio-0.5)<0.001 and hud._shield_visible,"Flight gauges lost accepted hull/shield fractions")
		check(hud._cargo_text.text=="1 / 25t" and hud._cargo_frame.texture.get_meta("source_image_id")==1218,"Cargo HUD lost source counter art or totals")
		check(hud._throttle_text.text=="100" and hud._throttle_frame.texture.get_meta("source_image_id")==1352 and hud._throttle_frame.texture.get_meta("source_region")==250,"Throttle HUD lost its accepted percentage or source art")
		var bare:=flight.duplicate(true);bare.player.capacities.shield=0;bare.player.vitals.shield=0.0;bare.control_throttle=0.35
		check(hud.present(bare) and not hud._shield_visible and hud._throttle_text.text=="35","Unfitted shield or reduced throttle showed a stale gauge")
		var invalid:=flight.duplicate(true);invalid.control_throttle=1.5
		check(not hud.present(invalid) and hud._throttle_text.text=="35","Invalid throttle replaced the last accepted indicator")
		check(hud.present(flight),hud.error)
		var inventory:=identity.duplicate()
		inventory.hangar_open=true;inventory.contracts={"credits":6161}
		inventory.equipment={"ordinary_shopping_open":true,"requirements":{"weapon_installed":true,"armor_installed":true},
			"cargo":{"used":1,"capacity":25,"entries":[{"item_id":68,"quantity":1}]},
			"stock":[{"item_id":68,"quantity":0,"unit_price":8400}],
			"market_rows":[{"item_id":68,"stock":0,"owned":1,"unit_price":8400,"mission":false}],
			"loadout":{"ship_id":0,"slots":[null,null,{"item_id":55,"category":3,"slot":0,"quantity":1},{"item_id":81,"category":3,"slot":1,"quantity":1},{"item_id":90,"category":3,"slot":2,"quantity":1}]},
			"fitting_support":{68:""},"fitting_conflicts":{},"fitting_stats":{"hull":95,"armor":40,"shield":50,"handling_bonus_percent":0,"passenger_capacity":0},"protected_item_ids":[81,90]}
		check(equipment.present(inventory),equipment.error)
		check(equipment._rows[68].icon.texture!=null and equipment._rows[68].icon.texture.get_meta("source_region")==68,"Tractor thumbnail lost the source item atlas index")
		equipment.select_tab("cargo")
		check(equipment._rows[68].actions.mount.disabled,"Full compatible equipment slots allowed a misleading Mount action")
		equipment.set_active(false)
		check(equipment._rows[68].actions.mount.disabled and equipment._close.disabled,"Inactive hangar accepted actions")
		equipment.set_active(true)
		inventory.equipment.loadout.slots[3]=null
		check(equipment.present(inventory) and not equipment._rows[68].actions.mount.disabled,"Free compatible slot stayed disabled")
		equipment.select_tab("ship")
		check(equipment._installed_rows[3].name.text==library.strings[173],"Empty ship slot lost the localized source marker")
		shell.set_active(false)
		check(shell._actions.hangar.disabled,"Inactive station shell accepted actions")
		shell.set_active(true)
		hud.set_active(false)
		check(not hud.visible,"Inactive flight overlay remained visible")
		hud.set_active(true)
		for mobile in [false,true]:
			root.size=Vector2i(800,450) if mobile else Vector2i(1280,720)
			shell.set_mobile_layout(mobile);hud.set_mobile_layout(mobile);equipment.set_mobile_layout(mobile)
			await process_frame;await process_frame
			var viewport:=Rect2(Vector2.ZERO,Vector2(root.size))
			check(viewport.encloses(equipment._panel.get_global_rect()) and viewport.encloses(equipment._close.get_global_rect()),"Hangar escaped the landscape viewport")
			check(viewport.encloses(shell._actions.hangar.get_global_rect()) and viewport.encloses(hud._cargo_frame.get_global_rect()),"Station/HUD corner action escaped landscape")
			check(viewport.encloses(hud._throttle_frame.get_global_rect()) and absf(hud._throttle_frame.get_global_rect().get_center().x-float(root.size.x)*0.5)<1.0,"Throttle indicator escaped the centered landscape flight layout")
			if args.size()==4 and language=="gb" and DisplayServer.get_name()!="headless":
				if not DirAccess.dir_exists_absolute(args[3]):DirAccess.make_dir_recursive_absolute(args[3])
				var form:="touch" if mobile else "desktop"
				equipment.select_tab("shop");equipment._select_row(68)
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(args[3].path_join("hangar-shop-"+form+".png"))==OK,"Could not capture selected shop row")
				equipment.select_tab("cargo");await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(args[3].path_join("hangar-cargo-"+form+".png"))==OK,"Could not capture cargo row")
				equipment.select_tab("ship");await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(args[3].path_join("hangar-ship-"+form+".png"))==OK,"Could not capture ship slots")
				equipment.hide();hud.hide();await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(args[3].path_join("station-"+form+".png"))==OK,"Could not capture station shell")
				shell.hide();hud.show();await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(args[3].path_join("flight-"+form+".png"))==OK,"Could not capture flight gauges")
				shell.show();equipment.show()
		equipment.clear();shell.clear();hud.clear()
	equipment.free();shell.free();hud.free()
	await process_frame
	print("UI fidelity components: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

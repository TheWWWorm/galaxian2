extends SceneTree
## Presentation-only checks using imported Mac content; no career is advanced.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Equipment=preload("res://src/presentation/station_equipment_panel.gd")
const Shell=preload("res://src/presentation/station_shell_panel.gd")
const Vitals=preload("res://src/presentation/flight_vitals_overlay.gd")
const HitArcs=preload("res://src/presentation/hit_arc_overlay.gd")
const OrbitBanner=preload("res://src/presentation/orbit_banner.gd")
const HudRules=preload("res://src/content/flight_hud_definitions.gd")
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
		check(hud._cargo_text.text=="1 / 25t" and hud._cargo_frame.texture.get_meta("source_image_id")==1312,"Cargo HUD lost source counter art or totals")
		check(hud._throttle_text.text=="100" and hud._throttle_frame.texture.get_meta("source_image_id")==1352 and hud._throttle_frame.texture.get_meta("source_region")==250,"Throttle HUD lost its accepted percentage or source art")
		var bare:=flight.duplicate(true);bare.player.capacities.shield=0;bare.player.vitals.shield=0.0;bare.control_throttle=0.35
		check(hud.throttle_alpha(Time.get_ticks_msec())==0.0,"Throttle indicator stayed visible without a throttle change")
		check(hud.present(bare) and not hud._shield_visible and hud._throttle_text.text=="35","Unfitted shield or reduced throttle showed a stale gauge")
		var changed: int=hud._throttle_changed_ms
		check(hud.throttle_alpha(changed)==1.0 and absf(hud.throttle_alpha(changed+Vitals.THROTTLE_HOLD_MS+Vitals.THROTTLE_FADE_MS/2)-0.5)<0.01 and hud.throttle_alpha(changed+Vitals.THROTTLE_HOLD_MS+Vitals.THROTTLE_FADE_MS)==0.0,"Throttle indicator did not show then fade after a change")
		check(hud.present(bare) and hud._throttle_changed_ms==changed,"An unchanged throttle restarted its indicator")
		var invalid:=flight.duplicate(true);invalid.control_throttle=1.5
		check(not hud.present(invalid) and hud._throttle_text.text=="35","Invalid throttle replaced the last accepted indicator")
		check(hud.present(flight),hud.error)
		verify_mission_readout(hud,flight)
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
			verify_gauge_frames(hud,flight)
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
	await verify_hit_feedback(library,bindings,visuals,cat,hud,shell,equipment,args)
	equipment.free();shell.free();hud.free()
	await process_frame
	print("UI fidelity components: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

func verify_gauge_frames(hud: Control,flight: Dictionary) -> void:
	for row in [[hud._hull_badge,hud._hull_frame,hud._hull_back],
		[hud._shield_badge,hud._shield_frame,hud._shield_back],
		[hud._armor_badge,hud._armor_frame,hud._armor_back]]:
		var badge: Rect2=row[0].get_global_rect()
		var frame: Rect2=row[1].get_global_rect()
		var back: Rect2=row[2].get_global_rect()
		check(row[1].texture!=null and absf(badge.end.x-frame.position.x)<0.01 and absf(badge.position.y-frame.position.y)<0.01 and absf(badge.size.y-frame.size.y)<0.01,"Gauge badge connectors did not join a full-height frame")
		check(frame.grow(1.0).encloses(back) and back.size.x>badge.size.x*4.0,"Long gauge artwork was missing or outside its frame")
	var state:=flight.duplicate(true)
	for fraction in [0.0,0.5,1.0]:
		state.player.max_hull=100;state.player.vitals={"hull":roundi(100*fraction),"armor":roundi(40*fraction),"shield":50.0*fraction}
		check(hud.present(state),hud.error)
		for row in [[hud._hull_frame,hud._hull_clip,hud._hull_fill],[hud._shield_frame,hud._shield_clip,hud._shield_fill],[hud._armor_frame,hud._armor_clip,hud._armor_fill]]:
			check(row[0].visible and absf(row[1].size.x-row[2].size.x*fraction)<0.01 and row[2].size.x>0.0,"Pool changes resized the gauge artwork or removed its frame")
	check(hud.present(flight),hud.error)

func verify_mission_readout(hud: Control,flight: Dictionary) -> void:
	var sample:=flight.duplicate(true)
	for row in [[61234,"01:01"],[1000,"00:01"],[1,"00:00"],[3600123,"01:00:00"]]:
		sample.mission_readout={"kind":"countdown","remaining_ms":row[0]}
		check(hud.present(sample) and hud._cargo_text.text==row[1],"The mission countdown rounded up or lost its clock format")
	var accepted:=sample.duplicate(true)
	check(hud.present(sample) and sample==accepted and hud._cargo_text.text=="01:00:00","Presenting an unchanged timer advanced its clock or changed the sample")
	sample.mission_readout={"kind":"contest","player":2,"other":1}
	check(hud.present(sample) and hud._cargo_text.text=="2 : 1","The contest did not replace cargo with its player/rival score")
	sample.mission_readout.other=3
	check(hud.present(sample) and hud._cargo_text.text=="2 : 3","The rival score did not update independently")
	hud.set_active(false)
	check(not hud.visible,"A cinematic gate retained the mission readout")
	hud.set_active(true)
	var invalid:=sample.duplicate(true);invalid.mission_readout.player=-1
	check(not hud.present(invalid) and hud._cargo_text.text=="2 : 3","An invalid contest score replaced the accepted display")
	sample.mission_readout={"kind":"score","score":4106}
	check(hud.present(sample) and hud._cargo_text.text=="0004106" and hud.counter_rect().has_area(),"The kill score did not take the counter plate")
	check(hud.counter_rect().position.x>hud.size.x*0.5,"The counter plate left the top-right corner")
	check(hud.present(flight) and hud._cargo_text.text=="1 / 25t","Retiring the readout did not restore cargo")

## Hit arcs, the shield hit badge and the arrival orbit information.
func verify_hit_feedback(library: RefCounted,bindings: RefCounted,visuals: RefCounted,cat: RefCounted,hud: Control,shell: Control,equipment: Control,args: Array) -> void:
	check(library.select_language("gb") and hud.configure(library,bindings,visuals),library.error+hud.error)
	var tangents:=Vector2(0.7,0.4)
	check(HudRules.hit_sides(Vector3(0,0,-100),tangents)==["top"] and HudRules.hit_sides(Vector3(0,0,100),tangents)==["bottom"],"A shooter ahead/behind did not light the top/bottom arc")
	check(HudRules.hit_sides(Vector3(-500,0,-100),tangents)==["left","top"] and HudRules.hit_sides(Vector3(500,0,-100),tangents)==["right","top"],"A shooter ahead off screen did not add its side arc")
	check(HudRules.hit_sides(Vector3(-500,0,100),tangents)==["right","bottom"] and HudRules.hit_sides(Vector3(-5000,0,1),tangents)==["right"],"A shooter behind lost the source's mirrored side or abeam rule")
	var arcs:=HitArcs.new();root.add_child(arcs);arcs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var banner:=OrbitBanner.new();root.add_child(banner);banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check(arcs.prepare(library,bindings,visuals),arcs.error)
	check(banner.prepare(library,bindings,visuals,cat),banner.error)
	var flight:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":"gb","campaign_cursor":18,
		"player":{"ship_id":0,"vitals":{"hull":47,"armor":20,"shield":25.0},"capacities":{"armor":40,"shield":50}},"cargo":{"used":1,"capacity":25},
		"player_pose":Transform3D.IDENTITY,"camera_view":{"pose":Transform3D(Basis.IDENTITY,Vector3(0,0,30))},"world_phase_elapsed_ms":1000,
		"location":{"station_id":78,"system_id":15},
		"actors":[{"hostile":true,"active":true,"pose":Transform3D(Basis.IDENTITY,Vector3(0,0,-500))},{"hostile":false,"active":true,"pose":Transform3D(Basis.IDENTITY,Vector3(0,0,40))}]}
	check(arcs.present(flight,tangents) and not arcs.visible,"Hit arcs lit without a hit")
	var hit:=flight.duplicate(true);hit.player.vitals.shield=15.0;hit.world_phase_elapsed_ms=1016
	check(arcs.present(hit,tangents) and arcs.visible and arcs._lit.keys()==["top"] and arcs._blue,"A hit from the hostile ahead did not light the blue top arc")
	check(arcs.arc_alpha("top",1016)==1.0 and absf(arcs.arc_alpha("top",1166)-0.5)<0.01 and arcs.arc_alpha("top",1016+HudRules.HIT_ARC_MS)==0.0,"The hit arc did not fade out over 300 ms")
	check(hud.present(flight) and hud.present(hit) and hud._shield_badge.texture.get_meta("source_image_id")==HudRules.SHIELD_HIT_IMAGE,"The shield badge did not turn to its hit art")
	check(hud.shield_hit_shown(hud._shield_hit_ms+Vitals.SHIELD_HIT_MS-1) and not hud.shield_hit_shown(hud._shield_hit_ms+Vitals.SHIELD_HIT_MS),"The shield hit badge did not last 500 ms")
	var bare:=hit.duplicate(true);bare.player.vitals.shield=0.0;bare.world_phase_elapsed_ms=1100
	check(arcs.present(bare,tangents) and not arcs._blue and hud.present(bare) and not hud.shield_hit_shown(Time.get_ticks_msec()),"An empty shield kept blue arcs or the shield hit badge")
	check(banner.present(flight) and banner.visible and banner._station.text==cat.tables.stations[78].name and banner._system.text.begins_with(cat.tables.systems[15].name) and banner._system.visible and banner._security.visible,"Orbit information lost station, system or security")
	check(banner._logo.texture==null or int(banner._logo.texture.get_meta("source_image_id")) in [1187,1188,1189,1190],"Orbit information lost the original race logo")
	var late:=flight.duplicate(true);late.world_phase_elapsed_ms=HudRules.ORBIT_MS
	check(banner.present(late) and not banner.visible,"Orbit information outlived the 7 s arrival sequence")
	var early:=flight.duplicate(true);early.campaign_cursor=10
	check(banner.present(early) and banner.visible and not banner._system.visible,"Before cursor 16 the orbit information showed more than the station")
	early.campaign_cursor=7
	check(banner.present(early) and not banner.visible,"The tutorial showed orbit information")
	if args.size()==4 and DisplayServer.get_name()!="headless":
		check(banner.present(flight) and hud.present(flight),banner.error+hud.error)
		shell.hide();equipment.hide();hud.show()
		hud.set_mobile_layout(false);arcs.set_mobile_layout(false);banner.set_mobile_layout(false);root.size=Vector2i(1280,720)
		var frame:=ColorRect.new();frame.color=Color(0.05,0.07,0.12);frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(frame);root.move_child(frame,0)
		hud._shield_hit_ms=Time.get_ticks_msec();hud._shield_points=25.0;hud._apply_shield_badge(Time.get_ticks_msec())
		arcs._blue=true;arcs.register_hit(["top","left"],5000);arcs.register_hit(["bottom","right"],5000);arcs.visible=true;arcs.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(args[3].path_join("flight-hit-arcs-blue-orbit.png"))==OK,"Could not capture hit arcs")
		early.campaign_cursor=10;arcs._blue=false;arcs.queue_redraw();banner.present(early)
		await process_frame;await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(args[3].path_join("flight-hit-arcs-red.png"))==OK,"Could not capture red hit arcs")
		frame.free();shell.show();equipment.show()
	arcs.free();banner.free()

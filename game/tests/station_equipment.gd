extends "res://tests/second_flight_session.gd"
## Exercise the actual application after two earned mining returns. Trading,
## installed-slot ownership, failed preparation and acknowledged progression
## are checked through the same station session used by players.
const EquipmentScenario=preload("res://tests/fixtures/equipment_scenario.gd")
const EquipmentRules=preload("res://src/content/station_equipment_definitions.gd")

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	if is_instance_valid(host):host.free()
	print("Station equipment: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func after_second_return(args: PackedStringArray):
	var before: Dictionary=host.session.snapshot()
	var scenario_before:=before.duplicate(true)
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	if header.reader=="resource-registration-v116":check(EquipmentRules.parameters(bindings.station_equipment),"Current Mac pack omitted the equipment tutorial")
	if not EquipmentRules.parameters(bindings.station_equipment):
		check(not host._hangar_button.visible and not host.equipment_action("open") and host.session.snapshot()==before,"Older pack exposed or changed unsupported equipment")
		return
	check(host._hangar_button.visible and not host.equipment_panel.visible,"Equipment hangar did not unlock at its source cursor")
	var corrupt: Dictionary=bindings.station_equipment.duplicate(true);corrupt.stock[0].quantity=2
	check(not EquipmentRules.parameters(corrupt),"Altered source stock was accepted")
	corrupt=bindings.station_equipment.duplicate(true);corrupt.provenance.equipment_check.offset+=1
	check(not EquipmentRules.validate(corrupt,2147483647,"x86_64",bindings.arrival_staging,bindings.full_hold_return).is_empty(),"Unverified equipment predicate was accepted")
	key(KEY_ENTER)
	check(host.equipment_panel.visible and host.session.snapshot().hangar_open and host.session.snapshot().cargo.used==25,"Opening the hangar changed cargo cache or lost its panel")
	if not host.equipment_panel.visible:return
	if args.size()==4:await capture(args[3],"equipment-shop-desktop")
	var stock: Array=host.session.snapshot().equipment.stock
	check(stock==[{"item_id":0,"quantity":1,"unit_price":0},{"item_id":22,"quantity":1,"unit_price":0},{"item_id":55,"quantity":1,"unit_price":0}],"Tutorial offers differ from source stock")
	var detached: Dictionary=host.session.snapshot();detached.equipment.stock[0].quantity=99;detached.equipment.loadout.slots.clear()
	check(host.session.snapshot().equipment.stock==stock and not host.session.snapshot().loadout.slots.is_empty(),"Public inventory snapshot mutated its live owner")
	before=host.session.snapshot()
	for action in ["buy","sell","mount","unmount"]:
		check(not host.equipment_action(action,999) and host.session.snapshot()==before,"Invalid item changed inventory: "+action)
		for id in [90,81]:check(not host.equipment_action(action,id) and host.session.snapshot()==before,"Protected source item moved: "+action)
	check(not host.equipment_action("mount",0) and host.session.snapshot()==before,"Unowned weapon was mounted")
	check(host.equipment_action("close") and host.session.snapshot().campaign_cursor==6 and not host.session.snapshot().dialogue.visible,"Empty hangar completed the tutorial")
	check(host.equipment_action("open") and host.session.snapshot().equipment.stock==stock,"Reopening restocked the hangar")
	for reason in ["user","focus","hidden"]:
		host.session.set_pause(reason,true,now_us);before=host.session.snapshot()
		check(not host.equipment_action("buy",0) and host.session.snapshot()==before,"Paused inventory accepted a transaction: "+reason)
		host.session.set_pause(reason,false,now_us)
	check(host.equipment_action("buy",0),host.session.error)
	var state: Dictionary=host.session.snapshot()
	check(state.cargo.used==1 and state.cargo.free_space==24 and not state.cargo_cache_stale and state.cargo.entries==[{"item_id":0,"quantity":1}],"Purchase failed to replace the stale ore cache with owned equipment")
	before=state
	check(not host.equipment_action("buy",0) and host.session.snapshot()==before,"Exhausted stock duplicated a weapon")
	check(host.equipment_action("sell",0) and host.session.snapshot().cargo.used==0 and host.session.snapshot().equipment.stock==stock,"Selling a free offer changed price, lost stock or retained cargo")
	check(host.equipment_action("buy",0) and host.equipment_action("mount",0),host.session.error)
	state=host.session.snapshot()
	check(state.equipment.requirements.weapon_installed and not state.equipment.requirements.armor_installed and state.cargo.used==0,"Mounted weapon was still cargo or satisfied armor")
	check(host.equipment_action("close") and host.session.snapshot().campaign_cursor==6,"Weapon alone completed the tutorial")
	check(host.equipment_action("open") and host.session.snapshot().equipment.stock[0].quantity==0,"Reopening duplicated the acquired weapon")
	check(host.equipment_action("unmount",0) and not host.session.snapshot().equipment.requirements.weapon_installed and host.session.snapshot().cargo.used==1,"Demount failed to move equipment back to cargo")
	check(host.session.audio.snapshot().equipment_effects==[98,96],"Accepted mount/demount did not use their original UI sounds")
	check(host.equipment_action("buy",22) and host.equipment_action("mount",22),host.session.error)
	state=host.session.snapshot()
	check(state.loadout.equipment_ids.has(22) and not state.loadout.equipment_ids.has(0) and state.equipment.requirements.weapon_installed,"Alternate starter gun was not accepted")
	check(host.equipment_action("buy",55) and host.equipment_action("close"),host.session.error)
	check(host.session.snapshot().campaign_cursor==6 and not host.session.snapshot().dialogue.visible,"Owning unmounted armor completed the tutorial")
	check(host.equipment_action("open") and host.equipment_action("mount",55),host.session.error)
	state=host.session.snapshot()
	check(state.equipment.requirements.satisfied and state.cargo.used==1 and state.cargo.entries==[{"item_id":0,"quantity":1}],"Equipment predicate counted cargo or consumed the spare gun")
	host.equipment_panel.select_tab("ship")
	if args.size()==4:
		var file:=FileAccess.open(args[3].path_join("equipment-installed-state.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(state));file.close()
		await capture(args[3],"equipment-installed-desktop")
		host.equipment_panel.select_tab("cargo");await capture(args[3],"equipment-cargo-desktop")
		await capture_equipment_phone(args[3])
	var old_audio: Dictionary=bindings.audio;bindings.audio={};before=host.session.snapshot()
	check(not host.equipment_action("close") and host.session.snapshot()==before and host.equipment_panel.visible,"Failed completion speech discarded the hangar or advanced story")
	bindings.audio=old_audio
	check(host.equipment_action("close"),host.session.error)
	state=host.session.snapshot()
	check(not host.equipment_panel.visible and state.dialogue.visible and state.dialogue.text_id==1725 and state.campaign_cursor==6 and state.mission.kind==158,"Equipment completion skipped its acknowledged source line")
	check(host.session.audio.snapshot().history.back().source_id==438,"Equipment completion used the wrong voice")
	check(state.progress==before.progress and state.reward_credits==0 and state.equipment.credit_delta==0,"Equipment granted credits or premature campaign progress")
	if args.size()==4:await capture(args[3],"equipment-confirmed-dialogue")
	var cargo: Dictionary=state.cargo;var loadout: Dictionary=state.loadout;var arrival: Dictionary=state.arrival_player
	for i in 3:check(step(),host.session.error)
	check(host.session.snapshot().campaign_cursor==6,"Timed speech acknowledged itself")
	key(KEY_ENTER);state=host.session.snapshot()
	check(state.campaign_cursor==7 and state.phase=="combat_departure_required" and state.mission.kind==4 and state.equipment_acknowledged,"Acknowledged equipment failed to select combat training")
	check(state.progress.rank_score==before.progress.rank_score+int(bindings.opening_handoff.cursor_weight) and state.progress.campaign_cursor==7,"Equipment completion duplicated or omitted its rank contribution")
	check(state.cargo==cargo and state.loadout==loadout and state.arrival_player==arrival and state.reward_credits==0,"Completion discarded owned gear, healed the player or granted credits")
	check(host.session.audio._player==null,"Completion speech kept playing after acknowledgement")
	var training_ready: bool=not bindings.combat_training_story.get("station_return",{}).is_empty()
	check(host.request_departure()==training_ready,"Departure availability differs from the supported training return")
	if training_ready:
		check(host._launch_packet.get("equipment")==state.equipment and host.session.snapshot()==state,"Departure confirmation changed the equipped station")
		host.cancel_departure()
	before=state
	check(not host.equipment_action("buy",0) and not host.equipment_action("open") and not host.session.navigate("next",host.station_panel) and host.session.snapshot()==before,"Completed tutorial repeated actions or advanced twice")
	if args.size()==4:await capture(args[3],"equipment-completed-action-rejection")
	var scenario_path:=OS.get_environment("GOF2_SCENARIO_OUTPUT")
	if not scenario_path.is_empty() and failures==0:
		var problem:=EquipmentScenario.capture(scenario_path,bindings,scenario_before,state,host.session._world.equipment_owner())
		check(problem.is_empty(),problem)

func death_branch(_args: PackedStringArray, _packet: Dictionary):pass

func capture(directory: String, name: String):
	# The desktop can change focus while this fixture yields for rendering.
	# Focus the actual test window, retaining the application's normal gates.
	root.grab_focus()
	for i in 3:await process_frame
	check(host._focused,"GPU test window did not receive focus before "+name)
	await super.capture(directory,name)
	if host.equipment_panel.visible:check(Rect2(Vector2.ZERO,host.equipment_panel.size).encloses(host.equipment_panel._panel.get_rect()),"Equipment panel escaped the desktop viewport")
	host.session.rebase_time(now_us)

func capture_equipment_phone(directory: String):
	var canvas:=SubViewport.new();canvas.size=Vector2i(420,800);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	host.reparent(canvas);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.set_mobile_layout(true)
	var original: Dictionary=host.session.snapshot()
	for code in lib.manifest.languages:
		check(lib.select_language(code),lib.error)
		var localized:=original.duplicate(true);localized.language=code
		check(host.equipment_panel.configure(lib,bindings) and host.equipment_panel.present(localized),host.equipment_panel.error)
		host.equipment_panel.select_tab("ship")
		for i in 5:await process_frame
		await RenderingServer.frame_post_draw
		check(Rect2(Vector2.ZERO,host.equipment_panel.size).encloses(host.equipment_panel._panel.get_rect()),"Equipment panel escaped the phone viewport: "+str(code))
		if code in ["gb","de","ru"]:
			check(canvas.get_texture().get_image().save_png(directory.path_join("equipment-installed-phone-"+code+".png"))==OK,"Could not capture equipment phone: "+code)
	check(lib.select_language("gb") and host.equipment_panel.configure(lib,bindings),"Could not restore equipment language")
	host.reparent(root);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.set_mobile_layout(false)
	canvas.free();host.equipment_panel.present(original);host.equipment_panel.select_tab("ship")
	root.grab_focus()
	for i in 3:await process_frame
	host.session.rebase_time(now_us)

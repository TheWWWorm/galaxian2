extends "res://tests/secondary_flight.gd"
## Read-only feedback and native control widgets, using actual detached launcher
## operations. No campaign departure, fitting unlock or earned save is created.
const WeaponPanel=preload("res://src/presentation/secondary_weapon_panel.gd")
var _signals:=[]

func _initialize() -> void:call_deferred("run_feedback")

func run_feedback() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [3,4]:check(false,"Expected content, bindings, visuals and optional captures")
	else:await verify_feedback(args)
	await process_frame
	print("Secondary feedback and controls: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_feedback(args: PackedStringArray) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):check(false,lib.error+bindings.error+cat.error);return
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var panel:=WeaponPanel.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.action_requested.connect(func(action):_signals.append(action))
	if not OwnershipRules.available(bindings):
		check(not panel.configure(lib,bindings) and not panel.visible,"Legacy bindings enabled secondary feedback")
		panel.free();return
	if not panel.configure(lib,bindings):check(false,panel.error);panel.free();return
	var built:=construction(bindings,cat,0.5)
	if built==null:panel.free();return
	check(Ownership.new().selection_feedback(-1).is_empty(),"An unconfigured launcher produced feedback")
	var capture_sample:={}
	for id in [41,42,43]:
		var group:=active_group(bindings,cat,built,0);var owner:=Ownership.new()
		if group==null or not owner.configure(bindings,cat,equipped(bindings,cat,[{"item_id":id,"slot":0,"quantity":2}])):check(false,owner.error);break
		var none:=owner.selection_feedback(-1);var before:=owner.snapshot()
		check(none.selected_item_id==-1 and none.actions.is_empty() and owner.snapshot()==before,"Feedback selected or fired an unselected weapon")
		check(panel.present(none) and panel.snapshot().name=="None selected","The initial explicit None choice was hidden")
		var selected:=owner.selection_feedback(id)
		check(selected.weapons[0].wait_ms==1 and selected.actions.is_empty(),"Readiness ignored strict interval equality")
		check(panel.present(selected) and panel.snapshot().name==lib.strings[id+int(bindings.station_equipment.item_text_offset)] and panel.snapshot().status.begins_with("Reloading"),"Selected secondary lost its original name or cooldown")
		var pose:=Transform3D(Basis.IDENTITY,group.snapshot().actors[0].position-Vector3(0,0,400))
		var equal:=compare_trigger(owner,group,pose,id)
		if equal.is_empty():break
		var motion:=owner.evaluate_advance(1,group,[0,1,2,3])
		if motion.is_empty():check(false,owner.error);break
		owner=motion.owner
		var ready:=owner.selection_feedback(id)
		check(ready.actions==[{"item_id":id,"action":"launched"}] and panel.present(ready) and panel.snapshot().status=="Ready to launch","Ready launcher had no usable control feedback")
		var fired:=compare_trigger(owner,group,pose,id)
		if fired.is_empty():break
		owner=fired.owner;group=fired.combat
		var flying:=owner.selection_feedback(id)
		check(flying.weapons[0].quantity==1 and flying.weapons[0].live and panel.present(flying) and panel.snapshot().status=="Ready to detonate","Live bomb did not replace launch feedback")
		var pulse:=compare_trigger(owner,group,pose,id)
		if pulse.is_empty():break
		owner=pulse.owner;group=pulse.combat
		var cooling:=owner.selection_feedback(id)
		check(cooling.actions.is_empty() and not cooling.weapons[0].live and cooling.weapons[0].quantity==1 and panel.present(cooling) and not panel.snapshot().activate_enabled,"Detonated bomb remained live or changed ammunition")
		var interval: int=owner.snapshot().guns[0].bomb.weapon.interval_ms
		motion=owner.evaluate_advance(interval,group,[0,1,2,3])
		if motion.is_empty():check(false,owner.error);break
		owner=motion.owner;group=motion.combat
		check(owner.selection_feedback(id).weapons[0].wait_ms==1 and owner.selection_feedback(id).actions.is_empty(),"Cooldown equality was advertised as ready")
		motion=owner.evaluate_advance(1,group,[0,1,2,3])
		if motion.is_empty():check(false,owner.error);break
		owner=motion.owner
		fired=compare_trigger(owner,group,pose,id)
		if fired.is_empty():break
		owner=fired.owner;group=fired.combat
		var last:=owner.selection_feedback(-1)
		check(last.weapons[0].quantity==0 and last.weapons[0].live and last.actions==[{"item_id":id,"action":"detonated"}],"None selection hid the last live round")
		check(panel.present(last) and panel.snapshot().status=="Ready to detonate" and panel.snapshot().ammunition.contains("In flight: 1"),"Last-round detonation became undiscoverable")
		if id==41:capture_sample=owner.selection_feedback(id)
		pulse=compare_trigger(owner,group,pose,-1)
		if pulse.is_empty():break
		owner=pulse.owner
		var exhausted:=owner.selection_feedback(id)
		check(panel.present(exhausted) and panel.snapshot().status=="No ammunition remaining" and exhausted.actions.is_empty(),"Exhausted launcher advertised a new round")
		var retained:=owner.snapshot();var detached:=owner.selection_feedback(id);detached.weapons[0].quantity=999
		check(owner.snapshot()==retained and owner.selection_feedback(999).is_empty(),"Feedback mutated retained inventory or accepted an unowned selection")
		verify_rejections(panel,exhausted)
	verify_order_feedback(bindings,cat,built,panel)
	if not capture_sample.is_empty():await verify_widget(lib,bindings,panel,capture_sample,args[3] if args.size()==4 else "")
	panel.clear();check(not panel.visible and panel.snapshot().state.is_empty(),"Secondary control teardown kept the previous flight")
	panel.free()

func compare_trigger(owner: RefCounted,group: RefCounted,pose: Transform3D,selected: int) -> Dictionary:
	var before: Dictionary=owner.snapshot();var actors: Dictionary=group.snapshot()
	var feedback: Dictionary=owner.selection_feedback(selected)
	var operation: Dictionary=owner.evaluate_trigger(pose,selected,group,[0,1,2,3])
	if operation.is_empty():check(false,owner.error);return {}
	var actions: Array=operation.events.map(func(event):return {"item_id":int(event.item_id),"action":event.action})
	check(feedback.actions==actions,"Control prediction disagreed with the actual firing pass")
	check(owner.snapshot()==before and group.snapshot()==actors,"Control prediction or prospective input changed retained owners")
	return operation

func verify_rejections(panel: Control,sample: Dictionary) -> void:
	var before: Dictionary=panel.snapshot()
	for corruption in ["identity","selection","quantity","boolean","timer","repeat","action","missing"]:
		var bad:=sample.duplicate(true)
		match corruption:
			"identity":bad.binding_id="foreign"
			"selection":bad.selected_item_id=999
			"quantity":bad.weapons[0].quantity=-1
			"boolean":bad.weapons[0].live=1
			"timer":bad.weapons[0].wait_ms=2147483648
			"repeat":bad.weapons.append(bad.weapons[0].duplicate(true))
			"action":bad.actions=[{"item_id":41,"action":"launched"}]
			"missing":bad.erase("selected_item_id")
		check(not panel.present(bad) and panel.snapshot()==before,"Rejected feedback changed the visible controls: "+corruption)

func verify_order_feedback(bindings: RefCounted,cat: RefCounted,built: RefCounted,panel: Control) -> void:
	var ship:=-1
	for row in cat.tables.ships:
		if row.stats.primary_slots>0 and row.stats.secondary_slots>=2:ship=int(row.id);break
	if ship<0:check(false,"No original hull supports the multi-launcher check");return
	var owner:=Ownership.new();var group:=active_group(bindings,cat,built,0)
	if group==null or not owner.configure(bindings,cat,equipped(bindings,cat,[{"item_id":41,"slot":0,"quantity":2},{"item_id":42,"slot":1,"quantity":2}],ship)):check(false,owner.error);return
	var pose:=Transform3D.IDENTITY
	var step:=owner.evaluate_advance(1,group,[0,1,2,3])
	if step.is_empty():check(false,owner.error);return
	owner=step.owner
	var armed: RefCounted=owner.fork()
	var first:=compare_trigger(owner,group,pose,41)
	if first.is_empty():return
	owner=first.owner;group=first.combat
	var priority:=owner.selection_feedback(42)
	check(priority.weapons[1].live and priority.actions==[{"item_id":42,"action":"launched"}] and panel.present(priority) and panel.snapshot().status=="Ready to launch","An earlier selected launcher falsely promised to detonate a later live bomb")
	var second:=compare_trigger(owner,group,pose,42)
	if second.is_empty():return
	owner=second.owner;group=second.combat
	var all_live:=owner.selection_feedback(-1)
	check(all_live.actions==[{"item_id":42,"action":"detonated"},{"item_id":41,"action":"detonated"}] and panel.present(all_live) and panel.snapshot().status=="Ready to detonate","Unselected feedback lost multiple live bombs or their order")
	compare_trigger(owner,group,pose,-1)
	var upper:=compare_trigger(armed,group,pose,42)
	if upper.is_empty():return
	var mixed: Dictionary=upper.owner.selection_feedback(41)
	check(mixed.actions==[{"item_id":42,"action":"detonated"},{"item_id":41,"action":"launched"}] and panel.present(mixed) and panel.snapshot().status=="Detonate, then launch","Mixed input hid an earlier detonation or later launch")
	compare_trigger(upper.owner,upper.combat,pose,41)

func verify_widget(lib: RefCounted,bindings: RefCounted,panel: Control,sample: Dictionary,captures: String) -> void:
	check(panel.present(sample),panel.error)
	panel.set_hud_visible(true);panel.set_interaction(true,false)
	await process_frame
	check(panel.visible and not panel._actions.is_visible_in_tree() and panel.snapshot().hint.contains("R / B / LT: Detonate"),"Desktop feedback exposed touch actions or lost the second-press hint")
	panel._fire.pressed.emit()
	check(_signals.is_empty(),"A hidden desktop action emitted secondary input")
	check(panel.snapshot().hint.contains("Q / D-pad right: Weapons menu") and panel.snapshot().hint.contains("R / B / LT: Detonate"),"Feedback hid a usable input family after switching devices")
	panel.set_interaction(true,true)
	await process_frame
	await click_button(panel._fire)
	check(_signals==["missiles"],"One pointer click did not emit exactly one secondary request")
	_signals.clear()
	await click_button(panel._select)
	check(_signals==["secondary_menu"],"Pointer selection did not request the menu independently of firing")
	_signals.clear()
	for mode in ["paused","focus","hidden","map"]:
		panel.set_interaction(false,true)
		if mode in ["hidden","map"]:panel.set_hud_visible(false)
		panel._fire.pressed.emit();panel._select.pressed.emit()
		check(_signals.is_empty() and not panel.snapshot().activate_enabled and not panel.snapshot().select_enabled,"Inactive controls leaked input: "+mode)
		panel.set_hud_visible(true)
	panel.set_interaction(true,true)
	panel.clear_sample();panel._fire.pressed.emit()
	check(not panel.visible and _signals.is_empty(),"The previous flight's controls survived an empty sample")
	check(panel.present(sample),panel.error)
	for language in ["gb","de","pl","ru"]:
		if not lib.select_language(language):check(false,lib.error);continue
		check(not panel.matches_context(lib,bindings) or language=="gb","Changed language reused the old item-name cache")
		check(panel.configure(lib,bindings) and panel.present(sample),panel.error)
		for mobile in [false,true]:
			panel.set_mobile_layout(mobile);panel.set_interaction(true,mobile)
			root.size=Vector2i(960,540) if not mobile else Vector2i(1280,720)
			for tick in 3:await process_frame
			check_layout(panel,root.size)
			if DisplayServer.get_name()!="headless" and language=="gb" and not captures.is_empty():
				await RenderingServer.frame_post_draw
				var image:=root.get_texture().get_image()
				DirAccess.make_dir_recursive_absolute(captures)
				check(image!=null and image.save_png(captures.path_join("secondary-controls-"+("touch" if mobile else "desktop")+".png"))==OK,"Could not save secondary control capture")
	if not lib.select_language("gb"):check(false,lib.error)

func check_layout(panel: Control,viewport: Vector2i) -> void:
	var rect: Rect2=panel.snapshot().panel_rect
	check(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(rect) and rect.size.x>=280 and rect.size.y<viewport.y/2.0,"Secondary controls overflowed the landscape viewport")
	for label in [panel._name,panel._ammunition,panel._status,panel._hint]:
		if not label.is_visible_in_tree():continue
		check(panel._panel.get_global_rect().encloses(label.get_global_rect()) and label.get_visible_line_count()==label.get_line_count(),"Secondary text was clipped or outside its panel")
	if panel._actions.is_visible_in_tree():
		check(panel._fire.size.y>=48 and panel._select.size.y>=48 and not panel._fire.get_global_rect().intersects(panel._select.get_global_rect()),"Touch targets were too small or overlapping")

func click_button(button: Button) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
	event.position=button.get_global_rect().get_center();event.global_position=event.position;event.pressed=true
	root.push_input(event);await process_frame
	event=event.duplicate();event.pressed=false
	root.push_input(event);await process_frame

extends SceneTree
## Isolated map presentation/selection fixtures; earned flight and pause ownership
## are exercised separately by the local station departure integration.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Navigation=preload("res://src/simulation/local_map.gd")
const MapPanel=preload("res://src/presentation/local_map_panel.gd")
const GatePanel=preload("res://src/presentation/gate_confirmation_panel.gd")
var checks:=0
var failures:=0
var confirmed:=[]
var closed:=0

func _initialize() -> void:
	create_timer(30).timeout.connect(func():push_error("Local map checks timed out");quit(1))
	call_deferred("verify")
func check(value: bool, message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

func verify():
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [3,4]:check(false,"Expected content, bindings, visuals and optional capture directory");finish();return
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not library.select_language("gb") or not bindings.open(args[1],library.manifest) or not catalogues.open(library) or not visuals.open(args[2],library.manifest):
		check(false,library.error+bindings.error+catalogues.error+visuals.error);finish();return
	var flight:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":10,
		"location":{"station_id":78,"system_id":15},"mission":{"kind":11,"station_id":79},"local_travel":{"phase":"flight"}}
	var navigation:=Navigation.new()
	if bindings.mido_travel.is_empty():check(not navigation.configure(library,bindings,catalogues,flight),"Earlier content invented a local map");finish();return
	if not navigation.configure(library,bindings,catalogues,flight):check(false,navigation.error);finish();return
	var initial:=navigation.snapshot()
	check(initial.system_name=="Mido" and initial.rows.size()==5,"Local map omitted catalogue locations")
	check(initial.rows.map(func(row):return row.station_id)==[75,76,77,78,79],"Map changed catalogue station order")
	check(initial.rows.map(func(row):return row.radius)==[8715,15832,22820,26235,31495],"Map orbit radii differ from the independent source vector")
	check(initial.rows.map(func(row):return row.angle_units)==[10922,0,32766,21844,43688],"Map reused an angular sector or another seed")
	check(initial.layout_random=={"state":212762317302449},"Map random call order changed")
	check(initial.rows.map(func(row):return row.model_id)==[18184,18190,18198,18180,18191],"Map replaced original planet models")
	check(initial.rows.filter(func(row):return row.supported).size()==1 and initial.rows[4].supported and initial.rows[4].mission_target,"Map silently enabled unimplemented destination worlds")
	check(initial.rows[3].current and not initial.rows[3].supported,"Current station became a travel destination")
	check(not navigation.request_confirmation() and navigation.snapshot()==initial,"Map confirmed a course without a selection")
	check(navigation.select_station(78) and navigation.request_confirmation() and navigation.snapshot().diagnostic==library.strings[408] and navigation.destination()==-1,"Current-location response was omitted")
	check(navigation.select_station(75) and navigation.request_confirmation() and navigation.destination()==-1 and not navigation.snapshot().diagnostic.is_empty(),"Unsupported local destination was completed")
	check(navigation.select_station(79) and navigation.request_confirmation() and navigation.destination()==79,"Supported planet did not require confirmation")
	var pending:=navigation.snapshot()
	check(not navigation.select_station(76) and navigation.snapshot()==pending,"Pending confirmation accepted a different selection")
	check(navigation.cancel_confirmation() and navigation.destination()==-1 and navigation.snapshot().selected_station_id==79,"Cancel discarded the selected row or retained a pending trip")
	var held:=navigation.snapshot()
	for changes in [{"binding_id":"wrong"},{"campaign_cursor":9},{"location":{"station_id":79,"system_id":15}},{"local_travel":{"phase":"launch"}}]:
		var changed:=flight.duplicate(true);changed.merge(changes,true)
		check(not navigation.configure(library,bindings,catalogues,changed) and navigation.snapshot()==held,"Rejected map replaced its accepted catalogue state")
	if bindings.mido_travel.has("gate_arrival"):
		var gate_view:=gate_view_fixture(bindings)
		check(navigation.configure(library,bindings,catalogues,gate_view,14) and navigation.snapshot().route_mode=="gate" and navigation.snapshot().rows.all(func(row):return row.supported),"Gate map lost its supported foreign-system choices")
		var accepted:=navigation.snapshot()
		check(not navigation.configure(library,bindings,catalogues,gate_view,11) and navigation.snapshot()==accepted,"Gate map displayed an unsupported world")
		gate_view.contracts={"mission":{"kind":0,"station_id":71}}
		var story: Dictionary=gate_view.mission.duplicate(true)
		check(navigation.configure(library,bindings,catalogues,gate_view,14),navigation.error)
		check(navigation.snapshot().rows.filter(func(row):return row.mission_target).map(func(row):return row.station_id)==[71],"Map omitted the retained side-contract destination")
		check(gate_view.mission==story,"Map replaced pending story with a contract destination")
	if DisplayServer.get_name()=="headless":finish();return
	root.size=Vector2i(1120,720)
	var panel:=MapPanel.new();root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.destination_requested.connect(func(id):confirmed.append(id));panel.close_requested.connect(func():closed+=1)
	if not panel.configure(library,bindings,visuals,catalogues,flight):check(false,panel.error);panel.free();finish();return
	panel.set_active(true)
	for i in 8:await process_frame
	check(panel._world.get_child_count()==2 and panel._world.get_child(1).get_child_count()==5 and panel._system.get_child_count()==10,"Original map planet/orbit/background staging is incomplete")
	check(panel._panel.get_rect().end.x<=panel.size.x and panel._panel.get_rect().end.y<=panel.size.y,"Desktop map exceeds its available area")
	check(is_equal_approx(panel._camera.position.z,500),"Desktop map lost its source camera distance")
	check_projection(panel)
	var pointer:=InputEventMouseButton.new();pointer.pressed=true;pointer.button_index=MOUSE_BUTTON_LEFT
	pointer.position=panel._canvas.rows[4].pixels;pointer.global_position=pointer.position
	root.push_input(pointer,true);pointer.pressed=false;root.push_input(pointer,true)
	check(panel.snapshot().selected_station_id==79 and confirmed.is_empty(),"Original planet frame did not select its rendered destination")
	if args.size()==4:await capture(args[3],"local-map-desktop")
	panel._key.pressed.emit()
	check(panel._legend.visible and panel._legend_rows.get_child_count()==5 and panel.snapshot().selected_station_id==79,"Map key changed the destination or omitted original legend entries")
	if args.size()==4:await capture(args[3],"local-map-key-desktop")
	panel._key.pressed.emit()
	panel.request_confirmation()
	check(panel.snapshot().confirmation_visible and confirmed.is_empty(),"Selecting a planet skipped confirmation")
	panel.set_error("Destination resources could not be staged")
	var before:=panel.snapshot();panel.set_active(false);panel.confirm_destination();panel.back()
	check(panel.snapshot()==before and confirmed.is_empty() and closed==0,"Inactive map accepted input")
	check(panel._status.text=="Destination resources could not be staged","Pause hid a rejected destination's diagnostic")
	panel.set_active(true);panel.back()
	var controller:=InputEventJoypadButton.new();controller.pressed=true;controller.button_index=JOY_BUTTON_A
	check(panel.handle_event(controller) and confirmed.is_empty() and panel.snapshot().confirmation_visible,"Controller skipped its first confirmation")
	check(panel.handle_event(controller) and confirmed==[79],"Controller did not confirm the original destination")
	panel.back()
	var phone:=SubViewport.new();phone.size=Vector2i(800,450);phone.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(phone)
	panel.reparent(phone);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.set_mobile_layout(true)
	for i in 8:await process_frame
	check_projection(panel)
	check(panel._panel.get_rect().end.x<=panel.size.x and panel._panel.get_rect().end.y<=panel.size.y,"Phone map exceeds its available area")
	for button in [panel._back,panel._target,panel._key,panel._yes,panel._no]:check(button.size.y>=44,"Phone map lost its touch target")
	check(panel._font!=null and not str(panel._font.get_meta("source_resource","")).is_empty(),"Map did not use imported bitmap glyphs")
	check(panel._sprites[1162].get_meta("source_region")==61 and panel._sprites[1277].get_meta("source_region")==176,"Map target frames lost their original atlas mappings")
	check(panel._sprites[1112].get_meta("source_image_id")==1112 and panel._sprites[1151].get_meta("source_image_id")==1151,"Map substituted its original button/footer art")
	check(panel._legend.get_theme_stylebox("panel").get_meta("source_image_ids")==[1150,1156,1155],"Map key substituted the source type-seven panel pieces")
	if args.size()==4:await capture(args[3],"local-map-phone",phone)
	# The development host also reserves a toolbar above this landscape map.
	phone.size=Vector2i(800,390)
	for i in 3:await process_frame
	check_projection(panel)
	panel.select_station(76)
	var tap:=InputEventScreenTouch.new();tap.index=1;tap.pressed=true;tap.position=panel._canvas.rows[4].pixels
	phone.push_input(tap,true);tap.pressed=false;phone.push_input(tap,true)
	check(panel.snapshot().selected_station_id==79 and not panel.snapshot().confirmation_visible,"Landscape touch did not select the planet independently of its label")
	if args.size()==4:await capture(args[3],"local-map-mobile-short",phone)
	panel._key.pressed.emit()
	check(panel._legend.get_rect().position.x>=0 and panel._legend.get_rect().end.y<=panel._footer.position.y,"Original map key exceeds the phone display")
	if args.size()==4:await capture(args[3],"local-map-key-phone",phone)
	panel._key.pressed.emit()
	panel.select_station(75);panel.request_confirmation()
	check(panel.snapshot().diagnostic.contains("Deuter IV") and not panel.snapshot().confirmation_visible,"Unsupported planet omitted its explicit support limit")
	if args.size()==4:await capture(args[3],"local-map-unavailable",phone)
	panel.back();check(closed==1,"Map cancellation did not return to its owner")
	panel.clear();check(not panel.visible and panel.snapshot().is_empty(),"Map retained resources after closing")
	panel.free();phone.free()
	if bindings.mido_travel.has("gate_arrival"):await verify_gate_panels(library,bindings,visuals,catalogues,args[3] if args.size()==4 else "")
	finish()

func gate_view_fixture(bindings: RefCounted) -> Dictionary:
	# A read-only interface fixture: it has no career, inventory or world owner
	# and cannot produce gameplay progress. gate_arrival tests the earned route.
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":18,
		"location":{"station_id":95,"system_id":19},"mission":{"kind":156,"station_id":56,"reward":0,"bonus":0,"source_parameter":0},
		"local_travel":{"phase":"flight"},"gate_destinations":[70,71,72,73,74],"gate_transit":{"phase":"flight"}}

func verify_gate_panels(library: RefCounted,bindings: RefCounted,visuals: RefCounted,catalogues: RefCounted,directory: String) -> void:
	root.size=Vector2i(1280,720)
	var flight:=gate_view_fixture(bindings);var panel:=MapPanel.new()
	root.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not panel.configure(library,bindings,visuals,catalogues,flight):check(false,panel.error);panel.free();return
	panel.set_active(true)
	panel.system_requested.connect(func(id):check(panel.configure(library,bindings,visuals,catalogues,flight,id),panel.error);panel.set_active(true))
	for tick in 3:await process_frame
	panel._systems.get_child(1).pressed.emit()
	check(panel.snapshot().system_id==14 and panel._systems.get_child_count()==2,"System-button dispatch retained old buttons or lost its destination")
	panel._systems.get_child(0).pressed.emit()
	check(panel.snapshot().system_id==19 and panel._systems.get_child_count()==2,"Repeated system-button dispatch failed")
	panel._systems.get_child(1).pressed.emit()
	for tick in 3:await process_frame
	check_projection(panel)
	if not directory.is_empty():await capture(directory,"gate-map-desktop")
	root.size=Vector2i(960,540);panel.set_mobile_layout(true)
	for tick in 3:await process_frame
	check_projection(panel)
	for button in panel._systems.get_children():check(button.size.y>=44 and Rect2(Vector2.ZERO,panel.size).encloses(Rect2(button.position+panel._systems.position,button.size)),"System selector exceeds the landscape touch map")
	if not directory.is_empty():await capture(directory,"gate-map-mobile")
	panel.free()
	var question:=GatePanel.new();root.add_child(question);question.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flight.gate_transit={"phase":"confirmation","course":{"destination_station_id":70}}
	for mobile in [false,true]:
		root.size=Vector2i(960,540) if mobile else Vector2i(1280,720);question.set_mobile_layout(mobile)
		if not question.present(library,bindings,visuals,catalogues,flight):check(false,question.error);break
		question.set_active(true)
		for tick in 4:await process_frame
		check(Rect2(Vector2.ZERO,question.size).encloses(question._panel.get_rect()) and question._panel.size.y<question.size.y/2,"Gate question did not settle to its compact landscape bounds")
		check(question.snapshot().text==library.strings[563]+": Dis\n"+library.strings[410],"Gate question lost source text")
		if not directory.is_empty():await capture(directory,"gate-question-mobile" if mobile else "gate-question-desktop")
	question.free()

func check_projection(panel: Control) -> void:
	var labels: Array=panel._canvas.label_rectangles()
	for index in labels.size():
		check(labels[index].end.y<=panel._footer.position.y,"Planet name falls under the navigation footer")
		for other in index:check(not labels[index].intersects(labels[other]),"Planet names overlap")
	for row in panel._canvas.rows:
		var model: Node3D=null
		for node in panel._system.get_children():
			if node.get_meta("source_station_id",-1)==row.station_id:model=node;break
		check(model!=null and panel._camera.unproject_position(model.global_position).distance_to(row.pixels)<0.5,"Planet frame and original model use different projections")
		var radius:=34 if panel._mobile else 22
		check(Rect2(Vector2(radius,radius),panel.size-Vector2.ONE*radius*2).has_point(row.pixels),"Planet selection frame is clipped")

func capture(directory: String, name: String, canvas: Viewport=root):
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	check(canvas.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Could not capture local map")

func finish() -> void:
	print("Local map: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

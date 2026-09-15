extends SceneTree
## GPU room-template check. Explicit visitors and faction fixtures do not claim
## campaign travel outside Mido. Backgrounds come from actual station records.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Lounge=preload("res://src/presentation/lounge_scene.gd")
var failures:=0
var checks:=0
var canvas: SubViewport
func _initialize() -> void:
	create_timer(60).timeout.connect(func():push_error("Lounge scene check timed out");quit(1))
	call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func frame() -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return canvas.get_texture().get_image()
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [3,4] or DisplayServer.get_name()=="headless":push_error("Expected GPU and explicit content/bindings/visuals");quit(1);return
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest) or not cat.open(library):push_error(library.error+bindings.error+visuals.error+cat.error);quit(1);return
	canvas=SubViewport.new();canvas.size=Vector2i(1280,720);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var visitors:=[]
	for id in 3:visitors.append({"contact_id":id,"faction":3,"male":true,"portrait":{"family":2}})
	var state:={"loadout":{"station_id":79},"campaign_cursor":13,"contracts":{"population":{"contacts":visitors}}}
	var faction: int=cat.tables.systems[15].fields[2]
	for room in [3,0,1,2]:
		# Exercise every original room without pretending the player travelled.
		cat.tables.systems[15].fields[2]=room
		var scene:=Lounge.new();canvas.add_child(scene)
		if not scene.build(library,bindings,visuals,cat,state,79):check(false,scene.error);scene.free();break
		var environment:=WorldEnvironment.new();environment.environment=scene.environment;scene.add_child(environment)
		scene.camera.make_current();check(scene.advance(3000),scene.error)
		var snapshot:=scene.snapshot()
		check(snapshot.room==room and snapshot.station_id==79 and snapshot.system_id==15,"Room or actual background location changed")
		check(snapshot.visitors.size()==visitors.size() and scene.screen_contacts().size()==visitors.size(),"Original visitors are absent or unselectable")
		var slots:={}
		for row in snapshot.visitors:slots[row.slot]=true
		check(slots.size()==visitors.size(),"Original visitor slots overlap")
		check(snapshot.sky.station_id==79 and snapshot.planets.station_id==79,"Window layers use another station")
		scene.select_contact(1)
		check(scene._visitors.filter(func(row):return row.highlight.visible).size()==1,"Selection glow is missing or duplicated")
		scene.select_contact(-1)
		var shown:=await frame()
		if args.size()==4:check(shown.save_png(args[3].path_join("room-"+str(room)+".png"))==OK,"Could not capture the original lounge template")
		scene.sky.hide();scene.planets.hide()
		var hidden:=await frame();var changed:=0
		for y in range(0,shown.get_height(),8):
			for x in range(0,shown.get_width(),8):
				if shown.get_pixel(x,y)!=hidden.get_pixel(x,y):changed+=1
		if room in [0,1,2]:check(changed>100,"Transparent lounge windows have no visible location background")
		print("Lounge room %d: %d changed background samples"%[room,changed]);scene.free()
	cat.tables.systems[15].fields[2]=faction
	var previous:={}
	for station_id in [79,75]:
		state.loadout.station_id=station_id
		var scene:=Lounge.new();canvas.add_child(scene)
		if not scene.build(library,bindings,visuals,cat,state,79):check(false,scene.error);scene.free();break
		var snapshot:=scene.snapshot()
		check(snapshot.sky.station_id==station_id and snapshot.planets.station_id==station_id,"Window view ignored a real station change")
		if not previous.is_empty():check(snapshot.sky.angles!=previous.sky.angles and snapshot.planets.planets!=previous.planets.planets,"Stations reused one static space backdrop")
		previous=snapshot;scene.free()
	canvas.free();print("Lounge scene: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

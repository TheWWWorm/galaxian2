extends SceneTree
const MiningPanel=preload("res://src/presentation/mining_panel.gd")
const Drill=preload("res://src/simulation/mining_drill.gd")
const Field=preload("res://src/simulation/scenery_field.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	print("Mining panel: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: Array):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	var canvas:=SubViewport.new();canvas.size=Vector2i(1280,720);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var backdrop:=ColorRect.new();backdrop.color=Color(0.015,0.03,0.05);canvas.add_child(backdrop);backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel:=MiningPanel.new();canvas.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not panel.configure(lib,bindings,visuals):check(false,panel.error);canvas.free();return
	check(panel.source().image_aliases.size()==17 and panel._spinner_frames.size()==10,"Original mining atlas mappings or animation cells are incomplete")
	for frame in panel._spinner_frames:check(frame.region.size==Vector2(33,33),"Drill animation used the entire strip as a frame")
	var random:=Random.new();random.seed_from(12345)
	var population:=Field.new();check(population.configure(bindings,cat,78,false,false,2),population.error)
	var field:=population.generate(Vector3(12298,36830,77237),random.snapshot())
	var chosen:=-1
	for row in field.objects:
		if row.source_size_value==7:chosen=row.index;break
	if chosen<0:check(false,"Reference field has no core asteroid");canvas.free();return
	var drill:=Drill.new();check(drill.configure(bindings,cat,[90,81],field,chosen,Vector2(640,360)),drill.error)
	var samples:={"rings":drill.fork()}
	for i in 120:steer(drill,Vector2(640,360),100,random.snapshot())
	samples["inner-rings"]=drill.fork()
	for i in 40:steer(drill,Vector2(825,360),50,random.snapshot())
	samples["drift"]=drill.fork()
	for language in lib.manifest.languages:
		check(lib.select_language(language) and panel.configure(lib,bindings,visuals),lib.error+panel.error)
		for mobile in [false,true]:
			canvas.size=Vector2i(420,800) if mobile else Vector2i(1280,720);panel.set_mobile_layout(mobile)
			for key in samples:
				var before: Dictionary=samples[key].snapshot()
				check(panel.present(samples[key],0,true),panel.error)
				for frame in 3:await process_frame
				check(panel.visible and Rect2(Vector2.ZERO,canvas.size).encloses(panel._quantity.get_rect()),"Mining quantity is clipped: "+language+" "+key)
				check(panel._instruction.get_line_count()*panel._instruction.get_line_height()<=panel._instruction.size.y,"Mining instruction is clipped: "+language)
				check(samples[key].snapshot()==before,"Rendering or resizing advanced the drill")
				if key=="drift":check(panel._reserve.visible and panel._quantity.get_theme_color("font_color").g<0.3,"Remaining time or insufficient-space feedback is absent")
				if args.size()==4 and language in ["gb","ja"]:
					await RenderingServer.frame_post_draw
					var image:=canvas.get_texture().get_image()
					check(image.get_size()==canvas.size,"Capture uses the wrong layout size")
					image.save_png(args[3].path_join("mining-%s-%s-%s.png"%[language,key,"phone" if mobile else "desktop"]))
	var before: Dictionary=drill.snapshot()
	check(panel.present(drill,100,false) and not panel._instruction.visible,"Later flight retained the tutorial hint")
	var identity: String=visuals.base_content_id;visuals.base_content_id="foreign"
	check(not panel.configure(lib,bindings,visuals) and panel.present(drill,100,false),"Failed resource configuration replaced the valid mining display")
	visuals.base_content_id=identity
	check(not panel.present(drill,-1,true) and drill.snapshot()==before,"Invalid cargo display changed drilling")
	check(drill.stop() and panel.present(drill,100,false) and not panel.visible,"Finished drill remains visible")
	canvas.free()

func steer(drill: RefCounted, target: Vector2, dt: int, seed: Dictionary):
	var state: Dictionary=drill.snapshot();var desired: Vector2=(target-state.point)*20.0/float(dt)-state.drift;var command:=Vector2.ZERO
	for axis in 2:command[axis]=signf(desired[axis])*sqrt(minf(1.0,absf(desired[axis])/3.0))
	if not drill.set_command(command) or not drill.advance(dt,seed if state.random_state.is_empty() else state.random_state):check(false,drill.error)

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)

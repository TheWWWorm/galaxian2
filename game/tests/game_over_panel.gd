extends SceneTree
## Mac-only component verification. Lethal input and plain capture scenery are
## disclosed fixtures; this does not claim the second application trip works.
const Fixture=preload("res://tests/full_hold_flight.gd")
const GameOver=preload("res://src/presentation/game_over_panel.gd")
const Definitions=preload("res://src/content/game_over_definitions.gd")
const Death=preload("res://src/simulation/player_destruction.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var checks:=0
var failures:=0
var requests:=0
var lib:=Library.new()
var bindings:=Bindings.new()
var cat:=Catalogues.new()
var visuals:=Visuals.new()
var construction:=Construction.new()
var resources:=Resources.new()
var death:=Death.new()
var rng:={"state":25214903917}
var pose:=Transform3D.IDENTITY
var canvas: SubViewport
var panel: Control
var captures:=""

func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	if args.size()==3 and DisplayServer.get_name()!="headless" and not OS.get_environment("GOF2_CAPTURE_DIR").is_empty():args.append(OS.get_environment("GOF2_CAPTURE_DIR"))
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	if canvas!=null:canvas.free()
	print("Game-over panel: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not cat.open(lib) or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	check(bindings.source_architecture=="x86_64","This verification is Mac only")
	panel=GameOver.new();canvas=SubViewport.new();canvas.size=Vector2i(960,720)
	canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var background:=ColorRect.new();background.color=Color(.015,.026,.042);background.size=Vector2(1280,1280);canvas.add_child(background)
	canvas.add_child(panel);panel.size=canvas.size
	panel.continue_requested.connect(func():requests+=1)
	if bindings.game_over_presentation.is_empty():
		check(not panel.configure(lib,bindings,visuals,death) and panel.snapshot().is_empty(),"Older pack fabricated game-over presentation")
		return
	if args.size()==4 and DisplayServer.get_name()!="headless":captures=args[3]
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(bindings.game_over_presentation,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.player_destruction).is_empty(),"Game-over declaration refused")
	for key in Definitions.VALUES:
		var bad: Dictionary=bindings.game_over_presentation.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed game-over parameter accepted: "+key)
	for key in Definitions.SPANS:
		var bad: Dictionary=bindings.game_over_presentation.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.player_destruction).is_empty(),"Detached game-over extent accepted: "+key)
	verify_reader(args[1],header)
	var fixture:=Fixture.new();var packet: Dictionary=fixture.packet_fixture(bindings,cat,3);fixture.free()
	if not construction.prepare(bindings,cat,packet,4096,1789100000) or not resources.configure(lib,bindings) or not death.configure(bindings,resources,construction):check(false,construction.error+resources.error+death.error);return
	pose=construction.snapshot().player_pose
	var player: RefCounted=construction.player_owner();player._state.vitals.hull=0
	if not death.start(player,pose,Vector3.ZERO,construction.snapshot().camera_view.pose,4) or not panel.configure(lib,bindings,visuals,death):check(false,death.error+panel.error);return
	var entry: Dictionary=construction.snapshot()
	check(panel.present(death,0) and not panel.visible and not panel.handle_event(enter()),"Tumble exposed game-over UI or input")
	advance_time(8000);check(not death.snapshot().failed and panel.present(death,8000) and not panel.visible,"Game-over UI appeared at death equality")
	advance_time(1);advance_time(3000)
	check(panel.present(death,11001) and not panel.visible,"Game-over UI appeared at delay equality")
	advance_time(1)
	check(panel.present(death,11002) and panel.visible and panel.snapshot().alpha_byte==0 and not panel.snapshot().prompt_visible and not panel.handle_event(enter()),"First fade frame accepted continuation")
	advance_time(1999)
	check(panel.present(death,13001) and panel.snapshot().alpha_byte==127 and not panel.snapshot().prompt_visible,"Half fade or prompt visibility differs from source")
	await capture("desktop-half-fade")
	advance_time(1999)
	check(panel.present(death,15000) and panel.snapshot().alpha_byte==254 and not panel.handle_event(enter()),"Continuation opened before full fade")
	var held_trigger:=InputEventJoypadMotion.new();held_trigger.axis=JOY_AXIS_TRIGGER_RIGHT;held_trigger.axis_value=1.0
	check(not panel.handle_event(held_trigger),"Fire trigger acknowledged during fade")
	advance_time(1)
	check(panel.present(death,0) and panel.snapshot().alpha_byte==255 and panel.snapshot().prompt_visible and panel.snapshot().prompt_alpha_byte==0,"Full fade or absolute blink origin differs")
	check(not panel.handle_event(held_trigger),"Held trigger crossed into game-over acknowledgement")
	held_trigger.axis_value=0.0;check(not panel.handle_event(held_trigger),"Trigger release acknowledged game-over")
	var before: Dictionary=death.snapshot()
	var previous_requests:=requests
	check(panel.handle_event(enter()) and requests==previous_requests+1 and death.snapshot()==before,"Continuation intent mutated death/progress or was lost")
	verify_inputs()
	await verify_dispatch()
	var expected:={0:0,1:0,174:127,524:254,1047:0,1571:254,100000:254,1000000:55,16777216:48,16777217:48,2147483647:119}
	for milliseconds in expected:
		check(panel.present(death,milliseconds) and panel.snapshot().prompt_alpha_byte==expected[milliseconds],"Float32 source sine differs at %d"%milliseconds)
	check(death.snapshot()==before,"Drawing advanced destruction or shared RNG")
	check(panel.present(death.fork_for_frame(),524),"A detached frame with the same presentation identity was refused")
	await capture("desktop-complete")
	verify_atomic()
	for language in lib.manifest.languages:
		check(lib.select_language(language),lib.error)
		check(panel.configure(lib,bindings,visuals,death),panel.error)
		panel.set_mobile_layout(false);panel.size=Vector2(960,720)
		check(panel.present(death,524) and panel.snapshot().text_id==189 and panel.snapshot().text==lib.strings[189],"Desktop continuation alias lost: "+language)
		check(panel.snapshot().image_rect.size==Vector2(147,68),"Desktop game-over composition is not compact")
		panel.set_mobile_layout(true);panel.size=Vector2(800,450)
		check(panel.present(death,524) and panel.snapshot().text_id==188 and panel.snapshot().text==lib.strings[188],"Mobile continuation text lost: "+language)
		await process_frame
		var state: Dictionary=panel.snapshot()
		var viewport:=Rect2(Vector2.ZERO,panel.size)
		check(state.image_rect.size==Vector2(294,136) and viewport.encloses(state.image_rect) and viewport.encloses(state.prompt_rect),"Phone art/prompt exceeds its landscape viewport: "+language)
	check(lib.select_language("ja") and panel.configure(lib,bindings,visuals,death),"Japanese capture resources unavailable")
	canvas.size=Vector2i(800,450);panel.size=canvas.size
	check(panel.present(death,524),panel.error);await capture("phone-japanese")
	check(not death.request_exit().is_empty() and panel.present(death,524) and not panel.handle_event(enter()),"Committed exit still accepts duplicate continuation")
	check(construction.snapshot()==entry,"Game-over presentation changed departure, cargo or progress")
	panel.clear();check(panel.snapshot().is_empty() and not panel.visible and not panel.handle_event(enter()),"Clear left game-over presentation/input active")

func advance_time(milliseconds: int):
	var remaining:=milliseconds
	while remaining>0:
		var amount:=mini(100,remaining);var result: Dictionary=death.advance(amount,pose,rng)
		if result.is_empty():check(false,death.error);return
		rng=result.random_state;remaining-=amount

func verify_inputs():
	var invalid:=enter();invalid.echo=true;check(not panel.handle_event(invalid),"Echo continued game-over")
	invalid=enter();invalid.pressed=false;check(not panel.handle_event(invalid),"Key release continued game-over")
	invalid=enter();invalid.keycode=KEY_A;check(not panel.handle_event(invalid),"Flight shortcut continued game-over")
	panel.set_active(false);check(not panel.handle_event(enter()) and not panel.snapshot().input_enabled,"Inactive panel continued game-over")
	panel.set_active(true)
	var joystick:=InputEventJoypadButton.new();joystick.button_index=JOY_BUTTON_A;joystick.pressed=true
	var touch:=InputEventScreenTouch.new();touch.pressed=true
	var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true
	for event in [enter(),joystick,touch,mouse]:
		var old:=requests;check(panel.handle_event(event) and requests==old+1,"Native continuation action was lost or repeated")
	joystick.pressed=false;touch.pressed=false;mouse.pressed=false
	for event in [joystick,touch,mouse]:check(not panel.handle_event(event),"Pointer/controller release continued game-over")
	var trigger:=InputEventJoypadMotion.new();trigger.axis=JOY_AXIS_TRIGGER_RIGHT;trigger.axis_value=1.0
	check(panel.handle_event(trigger),"The flight fire trigger did not acknowledge its original prompt")
	check(not panel.handle_event(trigger),"Held fire trigger repeatedly acknowledged game-over")
	trigger.axis_value=0.0;check(not panel.handle_event(trigger),"Fire trigger release acknowledged game-over")
	trigger.axis_value=NAN;check(not panel.handle_event(trigger),"Invalid fire trigger acknowledged game-over")
	var hidden_parent:=Control.new();canvas.add_child(hidden_parent);panel.reparent(hidden_parent);hidden_parent.hide()
	check(not panel.handle_event(enter()) and not panel.snapshot().input_enabled,"Hidden ancestor left game-over input active")
	panel.reparent(canvas);hidden_parent.free()

func verify_dispatch():
	await process_frame
	var pointer:=InputEventMouseButton.new();pointer.button_index=MOUSE_BUTTON_LEFT;pointer.pressed=true;pointer.position=Vector2(300,300)
	for event in [enter(),pointer]:
		var before:=requests;canvas.push_input(event,true)
		check(requests==before+1,"Viewport continuation was lost or dispatched twice")
	pointer.pressed=false;var before:=requests;canvas.push_input(pointer,true)
	check(requests==before,"Viewport pointer release repeated continuation")

func verify_atomic():
	var before: Dictionary=panel.snapshot()
	for invalid in [-1,0.0,null,true,"1"]:check(not panel.present(death,invalid) and panel.snapshot()==before,"Invalid clock replaced game-over screen")
	var foreign:=Death.new();check(foreign.configure(bindings,resources,construction),foreign.error)
	check(not panel.present(foreign,524) and panel.snapshot()==before,"Unrelated flight replaced game-over screen")
	var rules: Dictionary=bindings.game_over_presentation.duplicate(true);bindings.game_over_presentation.region=210
	check(not panel.configure(lib,bindings,visuals,death) and panel.snapshot()==before,"Changed atlas mapping replaced game-over screen")
	bindings.game_over_presentation=rules
	var directory: String=visuals.root;visuals.root=directory.path_join("missing-game-over-fixture")
	check(not panel.configure(lib,bindings,visuals,death) and panel.snapshot()==before,"Missing atlas discarded the accepted screen")
	visuals.root=directory
	var copy: Dictionary=panel.snapshot();copy.text="changed"
	check(panel.snapshot()==before,"Snapshot exposed mutable display state")

func verify_reader(pack: String, header: Dictionary):
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-game-over-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","type","value","extent","death_absent","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("game_over_presentation")
			"type":changed.game_over_presentation=false
			"value":changed.game_over_presentation.region=210
			"extent":changed.game_over_presentation.provenance.image_alias.offset+=1
			"death_absent":changed.player_destruction={}
			"empty":changed.game_over_presentation={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,lib.manifest),reader.error)
		var accepted:=reader.open(directory,lib.manifest)
		check(accepted and reader.game_over_presentation.is_empty() if scenario=="empty" else not accepted and reader.binding_id.is_empty() and reader.game_over_presentation.is_empty(),"Malformed game-over pack retained stale state: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func enter() -> InputEventKey:
	var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=true;return event

func capture(name: String):
	if captures.is_empty():return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var pixels: Image=canvas.get_texture().get_image()
	check(pixels!=null and pixels.save_png(captures.path_join(name+".png"))==OK,"Could not capture "+name)

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)

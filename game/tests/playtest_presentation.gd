extends SceneTree
## Focused player-reported GUI and portrait regressions; no campaign state changes.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
const Vitals=preload("res://src/presentation/flight_vitals_overlay.gd")
const SceneView=preload("res://src/presentation/native_scene_view.gd")
const Menu=preload("res://src/presentation/main_menu_panel.gd")
class FakeArt extends RefCounted:
	func apply_button(_button: Button,_mobile: bool) -> void:pass
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3 and DisplayServer.get_name()!="headless" and not OS.get_environment("GOF2_CAPTURE_DIR").is_empty():args.append(OS.get_environment("GOF2_CAPTURE_DIR"))
	if args.size() not in [3,4]:check(false,"Expected content, bindings, visuals and optional capture directory");quit(1);return
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):
		check(false,library.error+bindings.error+visuals.error);quit(1);return
	if not library.select_language("gb"):check(false,library.error);quit(1);return
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(800,450)
	var hud:=Vitals.new();root.add_child(hud);hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check(hud.configure(library,bindings,visuals),hud.error)
	var state:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"player":{"ship_id":0,"vitals":{"hull":47,"armor":20,"shield":25.0},
		"capacities":{"armor":40,"shield":50}},"cargo":{"used":1,"capacity":25}}
	check(hud.present(state),hud.error)
	check(hud.get("_armor_ratio") is float and absf(float(hud.get("_armor_ratio"))-0.5)<0.001,
		"Accepted armor pool has no separate visible gauge")
	if args.size()==4 and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(args[3])
		for mobile in [false,true]:
			root.size=Vector2i(800,450) if mobile else Vector2i(1280,720)
			hud.set_mobile_layout(mobile)
			await process_frame;await RenderingServer.frame_post_draw
			var name:="vitals-touch.png" if mobile else "vitals-desktop.png"
			check(root.get_texture().get_image().save_png(args[3].path_join(name))==OK,"Could not capture "+name)
	hud.free()
	var radio:=RadioResources.new()
	for cursor in [0,1,7,14,16,21,24,25,28,29]:
		if not radio.prepare(library,bindings,visuals,cursor):
			print("Radio cursor %d unavailable: %s"%[cursor,radio.error]);continue
		print("Radio cursor %d speakers %s diagnostics %s"%[cursor,str(radio.speakers.keys()),str(radio.portrait_diagnostics)])
		if radio.speakers.has(0):check(radio.speakers[0].get("portrait") is Texture2D,"Keith portrait absent in radio cursor %d"%cursor)
	var view:=SceneView.new();root.add_child(view);view.position=Vector2(0,0);view.size=Vector2(400,300)
	await process_frame;await process_frame
	var canvas:=Control.new();view.viewport.add_child(canvas);canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var button:=Button.new();button.text="Next";button.position=Vector2(100,100);button.size=Vector2(100,45);canvas.add_child(button)
	var clicks:=[];button.pressed.connect(func():clicks.append(true))
	await process_frame
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=Vector2(140,120)
	root.push_input(event,true);event=event.duplicate();event.pressed=false;root.push_input(event,true)
	await process_frame
	check(clicks.size()==1,"Mouse click did not reach a flight SubViewport dialogue button")
	root.content_scale_factor=2.0
	view.refresh_size();await process_frame
	event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=Vector2(140,120)
	root.push_input(event,true);event=event.duplicate();event.pressed=false;root.push_input(event,true)
	await process_frame
	check(clicks.size()==2,"Mouse click missed flight dialogue at desktop UI scale 2")
	view.free()
	var menu:=Menu.new();root.add_child(menu);menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu._ui=FakeArt.new()
	var logo_image:=Image.create(8,4,false,Image.FORMAT_RGBA8);logo_image.fill(Color.WHITE)
	menu._logo.texture=ImageTexture.create_from_image(logo_image)
	menu._background=SubViewport.new();menu.add_child(menu._background)
	await process_frame;await process_frame;menu._layout()
	check(menu._background.size.x>=root.size.x and menu._background.size.y>=root.size.y,
		"Menu 3D scene renders below the physical display resolution")
	menu.free();root.content_scale_factor=1.0
	if args.size()==4 and DisplayServer.get_name()!="headless":
		root.size=Vector2i(1920,1080);root.content_scale_factor=2.0
		var live_menu:=Menu.new();root.add_child(live_menu);live_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if check_result(live_menu.configure(library,bindings,visuals),live_menu.error):
			live_menu._layout()
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			check(live_menu._background.size==Vector2i(1920,1080),"Real menu background is not rendered at 1920x1080 physical pixels")
			check(live_menu._background.get_texture().get_image().save_png(args[3].path_join("menu-1920.png"))==OK,"Could not capture real menu resolution")
		live_menu.free();root.content_scale_factor=1.0
	print("Playtest presentation: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func check_result(value: bool,message: String) -> bool:
	check(value,message)
	return value

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

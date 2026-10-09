extends SceneTree
## In-flight pause window: the original entries and texts, the career's
## Missions log (read-only) and Cargo hold, the Back to Main Menu confirmation,
## and the Action Freeze orbit camera limits.
const Pause=preload("res://src/presentation/flight_pause_panel.gd")
const Status=preload("res://src/presentation/status_panel.gd")
var library=preload("res://src/content/library.gd").new()
var bindings=preload("res://src/content/resource_bindings.gd").new()
var visuals=preload("res://src/content/visual_library.gd").new()
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<3 or not library.open(args[0]) or not bindings.open(args[1],library.manifest,library) or not visuals.open(args[2],library.manifest) or not library.select_language("gb"):
		check(false,"content: "+library.error+bindings.error+visuals.error)
	else:await verify()
	print("Flight pause menu: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify() -> void:
	var root:=Control.new();root.size=Vector2(1280,720);get_root().add_child(root)
	var status:=Status.new();root.add_child(status)
	check(status.configure(library,bindings,visuals),"status: "+status.error)
	var pause:=Pause.new();root.add_child(pause);pause.size=root.size
	check(pause.configure(library,bindings,visuals,status,false),"pause: "+pause.error)
	if failures:return
	var s: Array=library.strings
	check(s[40]=="Pause" and s[41]=="Resume" and s[31]=="Options" and s[128]=="Missions" and s[165]=="Cargo hold" and s[511]=="Back to Main Menu" and s[58]=="Action Freeze" and s[169]=="Back" and s[513]=="OK","Mac string ids moved")
	var name116: String=s[int(bindings.station_equipment.item_text_offset)+116]
	var career:={"campaign_cursor":20,"mission":{"station_id":3},"station_id":3,"loadout":{"ship_id":0},
		"contracts":{"campaign_cursor":20,"mission":{},"progress":{}},
		"cargo":{"capacity":40,"used":7,"entries":[{"item_id":116,"quantity":5},{"item_id":117,"quantity":2}]}}
	pause.present(career);await process_frame
	var menu: Dictionary=pause.snapshot()
	check(menu.title=="Pause","title "+menu.title)
	check(menu.buttons==[s[41],s[31],s[128],s[165],s[511],s[58]],"entries "+str(menu.buttons))
	# Missions: the same story log the station shows, without Map / Discard.
	check(pause.press(s[128]) and pause.view=="missions","Missions did not open")
	var log: Dictionary=pause.snapshot().missions
	check(log.story==pause._missions.story_text(career) and not log.story.is_empty(),"story text "+str(log.story))
	check(log.job==s[173],"no-job text "+str(log.job))
	check(not log.story_map and not log.discard,"Missions log must be read-only in flight")
	check(pause.back() and pause.view=="menu","Back from Missions")
	# Cargo hold: names, quantities and used/capacity.
	check(pause.press(s[165]) and pause.view=="cargo","Cargo hold did not open")
	var rows: Array=pause.cargo_rows()
	check(rows.size()==2 and rows[0].name==name116 and not name116.is_empty() and rows[0].quantity==5 and rows[1].quantity==2,"cargo rows "+str(rows))
	var texts:=[]
	for node in pause._list.find_children("*","Label",true,false):texts.append(node.text)
	check(texts.has(name116) and texts.has("5") and texts.has("7/40"),"cargo labels "+str(texts))
	check(pause.snapshot().title==s[165],"cargo title")
	check(pause.back() and pause.view=="menu","Back from Cargo hold")
	# Back to Main Menu asks first; OK hands the action to the frontend.
	var asked:=[];pause.action_requested.connect(func(action):asked.append(action))
	check(pause.press(s[511]) and pause.view=="confirm","confirmation missing")
	var labels:=pause._list.find_children("*","Label",true,false).map(func(node):return node.text)
	check(labels.has(s[512]) and pause.button_texts()==[s[513],s[169]],"confirmation texts "+str(labels)+str(pause.button_texts()))
	check(asked.is_empty(),"leaving must wait for OK")
	pause.press(s[513])
	check(asked==["main_menu"],"OK did not leave: "+str(asked))
	pause.show_menu()
	pause.press(s[41]);check(asked.back()=="resume","Resume")
	# Before the training ends only the opening entries remain.
	pause.present({"campaign_cursor":1,"contracts":{},"cargo":{}})
	check(pause.snapshot().buttons==[s[41],s[31],s[511],s[58]],"opening entries "+str(pause.snapshot().buttons))
	# A story scene with a long opening conversation also offers Skip (384).
	pause.present({"campaign_cursor":154,"contracts":{},"cargo":{},"skip_available":true})
	check(pause.snapshot().buttons.back()==s[384],"no Skip entry "+str(pause.snapshot().buttons))
	pause.press(s[384]);check(asked.back()=="skip","Skip did not ask to skip")
	# The Supernova Challenge hides Missions and Cargo hold; the alien world hides Missions.
	pause.present({"campaign_cursor":152,"contracts":{},"cargo":{},"mission":{"supernova_challenge":true}})
	check(not pause.snapshot().buttons.has(s[128]) and not pause.snapshot().buttons.has(s[165]),"the challenge shows Missions or Cargo "+str(pause.snapshot().buttons))
	pause.present({"campaign_cursor":154,"contracts":{},"cargo":{},"alien_orbit":true})
	check(not pause.snapshot().buttons.has(s[128]) and pause.snapshot().buttons.has(s[165]),"the alien world gating is wrong "+str(pause.snapshot().buttons))
	# Status: arrows, D-pad and stick reach the medal grid, which scrolls with
	# the focus (#19). The station hands Status every unhandled event.
	var levels:=[];levels.resize(36);levels.fill(0);levels[0]=1
	status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check(status.present({"contracts":{"base_medals":{"version":1,"levels":levels}},"loadout":{"ship_id":0}}),"status present: "+status.error)
	for frame in 2:await process_frame
	var scroll: ScrollContainer=status._medal_grid.get_parent()
	var arrow:=InputEventKey.new();arrow.keycode=KEY_DOWN;arrow.physical_keycode=KEY_DOWN;arrow.pressed=true
	check(status.handle_event(arrow) and status._medal_buttons[0].has_focus(),"Down did not reach the Status medals")
	status._medal_buttons[0].release_focus()
	var pad:=InputEventJoypadButton.new();pad.button_index=JOY_BUTTON_DPAD_DOWN;pad.pressed=true
	check(status.handle_event(pad) and status._medal_buttons[0].has_focus(),"The D-pad did not reach the Status medals")
	for step in 14:
		for pressed in [true,false]:
			var move:=pad.duplicate();move.pressed=pressed;get_root().push_input(move,true);await process_frame
	check(scroll.scroll_vertical>0 and status._medal_buttons.find(get_root().gui_get_focus_owner())>=36,"The Status medals did not scroll with the D-pad: %d"%scroll.scroll_vertical)
	status.clear()
	# Action Freeze: orbit around the ship within 1500..20000, Back restores.
	var world:=Node3D.new();get_root().add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.global_position=Vector3(0,200,800)
	var start:=camera.global_transform
	pause.present(career)
	check(pause.begin_freeze(camera,Vector3(0,0,-100)) and pause.view=="freeze","freeze did not start")
	check(is_equal_approx(pause.distance,1500.0),"near camera clamps to 1500: "+str(pause.distance))
	pause.orbit(0.5,0.2,100.0)
	check(is_equal_approx(pause.distance,20000.0) and is_equal_approx(camera.global_position.distance_to(Vector3(0,0,-100)),20000.0),"zoom clamps to 20000")
	check(pause.back() and pause.view=="menu" and camera.global_transform.is_equal_approx(start),"Back restores the flight camera")
	root.queue_free();world.queue_free()

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+message)

extends SceneTree
const Host=preload("res://src/presentation/opening_preview.gd")
const Rescue=preload("res://src/presentation/arrival_session.gd")
const Station=preload("res://src/presentation/station_session.gd")
const Camera=preload("res://src/simulation/station_camera.gd")
const DialoguePanel=preload("res://src/presentation/station_dialogue_panel.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const StationState=preload("res://src/simulation/station_entry.gd")
const DesktopText=preload("res://src/content/desktop_text_definitions.gd")
const PresentationDefinitions=preload("res://src/content/station_presentation_definitions.gd")
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content/bindings/visuals and optional screenshot directory")
	if args.size() in [3,4]:await verify(args)
	print("First station session: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: Array):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not visuals.open(args[2],lib.manifest):
		check(false,lib.error+bindings.error+cat.error+visuals.error);return
	if bindings.station_presentation.is_empty():
		check(not Station.supported(bindings),"Legacy pack fabricated station presentation");return
	var source_bytes:=int(JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json"))).source_executable_bytes)
	if not bindings.desktop_text.is_empty():
		for pair in bindings.desktop_text.pairs:
			check(bindings.desktop_text_id(int(pair[0]))==int(pair[1]),"Source desktop alias was discarded")
		check(bindings.desktop_text_id(1697)==1697 and bindings.desktop_text_id(1678)==1678,"Desktop text remapped an unlisted string")
		for key in DesktopText.SPANS:
			var bad: Dictionary=bindings.desktop_text.duplicate(true);bad.provenance[key].offset+=1
			check(not DesktopText.validate(bad,source_bytes,"x86_64",bindings.arrival_staging).is_empty(),"Desktop text accepted a disconnected source extent")
		var bad: Dictionary=bindings.desktop_text.duplicate(true);bad.pairs[11][1]=1698
		check(not DesktopText.parameters(bad),"Desktop text accepted a guessed platform variant")
	for key in PresentationDefinitions.SPANS:
		var bad: Dictionary=bindings.station_presentation.duplicate(true);bad.provenance[key].offset+=1
		check(not PresentationDefinitions.validate(bad,source_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry).is_empty(),"Station accepted a disconnected source declaration: "+key)
	var altered: Dictionary=bindings.station_presentation.duplicate(true);altered.portraits["0"].parts[0]=1
	check(not PresentationDefinitions.parameters(altered),"Station accepted an invented Keith appearance")
	var camera:=Camera.new();check(camera.configure(bindings.station_presentation,42),camera.error)
	var initial:=camera.snapshot();var clone: RefCounted=camera.fork()
	check(initial.pose.basis.determinant()>0.9999,"Station camera orientation reflected the hangar")
	check(initial.pose.basis.z.dot(Vector3(1800,800,-1778).normalized())>0.9,"Camera faces away from the source hangar")
	check(not camera.advance(-1) and not camera.advance(151) and camera.snapshot()==initial,"Invalid camera frame mutated state")
	for i in 900:
		check(camera.advance(100) and clone.advance(100) and clone.snapshot()==camera.snapshot(),"Camera fork diverged")
		var offset: Vector3=camera.snapshot().pose.origin-Vector3(1800,800,-1778)
		check(absf(offset.x)<=150 and absf(offset.y)<=150 and absf(offset.z)<=150,"Station camera left authored drift bounds")
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var packet:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3))
	var host:=Host.new();root.add_child(host);host.set_context(lib,bindings,visuals)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.set_process(false)
	root.size=Vector2i(1280,720)
	var rescue:=Rescue.new();host.viewport.add_child(rescue);host.session=rescue
	if not rescue.configure(lib,bindings,visuals,packet,0,1789100000):check(false,rescue.error);host.free();return
	for i in 500:
		if rescue.status!="running":break
		if not rescue.step((i+1)*100000):check(false,rescue.error);host.free();return
	check(rescue.status=="station_transition_required","Rescue did not reach the station")
	var before: Dictionary=rescue.snapshot()
	var station_packet: Dictionary=rescue.prepare_station()
	var textures: Dictionary=visuals.textures;visuals.textures={}
	check(not host.enter_station(60000000,42),"Broken station resources replaced the rescue")
	check(host.session==rescue and rescue.snapshot()==before and is_instance_valid(rescue.camera),"Failed station entry destroyed committed rescue")
	visuals.textures=textures
	if not host.enter_station(60000000,42):check(false,host.status.text);host.free();return
	check(host.session is Station and not is_instance_valid(rescue),"Station did not replace its accepted rescue")
	var session: Node3D=host.session
	check(not session.snapshot().conversation_started and session.audio.snapshot().history.is_empty(),"Station conversation started during scene loading")
	check(not session.navigate("next",host.station_panel),"Station acknowledged before the source entry delay")
	check(session.prepare_departure(bindings,cat).is_empty(),"Station prepared departure before conversation began")
	session.rebase_time(60000000)
	for i in 9:session.step(60000000+(i+1)*100000)
	check(not session.snapshot().conversation_started,"Station conversation ignored its entry delay")
	session.step(61000000)
	host.present_session()
	check(host.station_panel.visible and not host.radio_panel.visible and not host.touch_overlay.visible,"Station retained the flight HUD or lacked conversation")
	check(session.snapshot().progress.player_kills==3 and session.snapshot().campaign_cursor==1,"Station entry lost earned kill credit or advanced story")
	check(session.audio.snapshot().history.size()==1 and session.audio.snapshot().history[0].source_id==267,"First station recording did not start")
	session.rebase_time(60000000);session.set_pause("user",true,60000000)
	var paused: Dictionary=session.snapshot()
	check(session.step(66000000) and session.snapshot()==paused,"Pause advanced the station camera")
	check(not session.navigate("next",host.station_panel) and session.snapshot()==paused,"Paused station acknowledged dialogue")
	session.set_pause("user",false,66000000);session.step(66100000)
	check(session.snapshot().camera.elapsed_ms==1100,"Station pause accumulated catch-up time")
	var other:=DialoguePanel.new();root.add_child(other)
	var prior: Dictionary=session.snapshot()
	check(not session.navigate("next",other) and session.snapshot()==prior,"Rejected panel advanced story")
	other.free()
	check(session.navigate("next",host.station_panel) and session.navigate("previous",host.station_panel),session.error)
	check(session.snapshot().dialogue.index==0 and session.audio.snapshot().history.size()==3,"Back navigation failed to replay the selected voice")
	if args.size()==4:
		host.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		for i in 4:await process_frame
		root.get_texture().get_image().save_png(args[3].path_join("station-keith.png"))
	for i in 19:
		check(session.snapshot().dialogue.index==i and session.snapshot().campaign_cursor==1,"Conversation advanced without final acknowledgement")
		if i==1 and args.size()==4:
			for f in 3:await process_frame
			root.get_texture().get_image().save_png(args[3].path_join("station-gunant.png"))
		if i==18:
			check(session.audio.snapshot().line==18,"Instruction retained the previous spoken line")
			if args.size()==4:
				for f in 3:await process_frame
				root.get_texture().get_image().save_png(args[3].path_join("station-instruction.png"))
		check(session.navigate("next",host.station_panel),session.error)
	var finished: Dictionary=session.snapshot()
	check(finished.campaign_cursor==2 and finished.mission.kind==154 and finished.reward_credits==0 and not finished.mining_completed,"Station completion fabricated mining success or rewards")
	check(finished.progress.player_kills==3 and not host.station_panel.visible,"Completion lost progress or left a modal open")
	check(not session.navigate("next",host.station_panel) and session.snapshot()==finished,"Repeated final input advanced twice")
	if not bindings.station_departure.is_empty():
		var departure_packet: Dictionary=session.prepare_departure(bindings,cat)
		check(not departure_packet.is_empty() and departure_packet.player.vitals.hull==95 and departure_packet.progress==finished.progress,"Live station did not prepare its replacement ship and earned progress")
		check(session.snapshot()==finished and session.audio.snapshot().line==-1,"Preparation changed the station scene or restarted speech")
		for reason in ["user","focus","hidden"]:
			session.set_pause(reason,true,70000000)
			check(session.prepare_departure(bindings,cat).is_empty(),"Paused station prepared departure: "+reason)
			session.set_pause(reason,false,70000000)
		check(session.prepare_departure(bindings,cat)==departure_packet and session.snapshot()==finished,"Resumed preparation lost its unchanged station")
	host.present_session()
	if bindings.station_return.is_empty():check("mining" in host.status.text,"Unsupported launch was not disclosed")
	else:check(host._launch_button.visible and not host._launch_button.disabled,"Supported departure was unavailable after acknowledgement")
	for language in lib.manifest.languages:
		check(lib.select_language(language),lib.error)
		var state:=StationState.new();var panel:=DialoguePanel.new();root.add_child(panel)
		check(state.configure(bindings,cat,lib,station_packet) and panel.configure(lib,bindings,visuals),state.error+panel.error)
		for i in 19:
			check(panel.present(state.snapshot()) and panel._body.text==lib.strings[bindings.desktop_text_id(1678+i)],"Station panel used another language: "+language)
			panel.set_mobile_layout(true)
			check(panel._body.text==lib.strings[1678+i],"Phone station text used desktop wording")
			panel.set_mobile_layout(false)
			check(state.acknowledge(),state.error)
		panel.free()
	host.free()

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)

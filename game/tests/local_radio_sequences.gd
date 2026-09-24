extends SceneTree
## Local faction messages can run during ordinary travel at a story cursor.
## Source-selected transmission vectors exercise no inventory or earned trip.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Radio=preload("res://src/simulation/local_traffic_radio.gd")
const Metrics=preload("res://src/content/image_font.gd")
const Layout=preload("res://src/presentation/source_text_layout.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Local radio sequences: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb"):check(false,library.error+bindings.error);return
	var metrics:=Metrics.new();var layout:=Layout.new()
	if not metrics.open_selected(library,bindings,0) or not layout.configure_from_bindings(metrics,350,5,bindings):check(false,metrics.error+layout.error);return
	var rules: Dictionary=bindings.mido_travel.traffic_combat.radio
	for cursor in [10,14,21,24]:
		if cursor>14 and not Radio.FreeFlight.Campaign.supported(bindings.mido_travel,cursor):continue
		var radio:=Radio.new()
		if not radio.configure(bindings,library,layout,cursor):check(false,radio.error);return
		var reaction:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":cursor,
			"radio_serial":1,"pending_radio":{"serial":1,"kind":"warning","speaker_id":int(rules.speaker_id),"text_id":int(rules.warning_text_ids[0]),"voice_event_id":int(rules.warning_voice_ids[0])}}
		# Prepared voice-adapter context only; the earned application verifies
		# actual playback. Rejected scheduler frames must never reach this owner.
		var audio:=Audio.new()
		audio._local_radio_rules=rules.duplicate(true);audio._voice_displayed=[false,false]
		audio._radio_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":cursor,"language":"gb"}
		var random:={"state":42}
		var lines: int=layout.wrap(library.strings[int(rules.warning_text_ids[0])]).size()
		var finish:=100+2000+1500+2000*lines
		for sample in [[100,"started"],[2100,""],[2101,"display"],[finish,""],[finish+1,"finished"],[finish+1,""]]:
			var held: Dictionary=radio.snapshot()
			var update:=radio.evaluate(sample[0],reaction,random)
			if update.is_empty():check(false,radio.error);audio.free();return
			check(radio.snapshot()==held,"Prospective local radio changed its accepted owner")
			radio=update.radio;random=update.random_state
			var state: Dictionary=radio.snapshot()
			check(update.events.map(func(event):return event.kind)==([] if sample[1]=="" else [sample[1]]),"Local radio transition differs at cursor %d/time %d"%[cursor,sample[0]])
			var prepared:=audio.prepare_local_radio({"radio":state,"radio_changes":update.events})
			if prepared.is_empty():check(false,audio.error);audio.free();return
			check(prepared.operations.size()==(1 if sample[1]=="display" else 0),"Local radio repeated or lost its voice display")
			audio._voice_displayed=prepared.displayed
		check(radio.snapshot().message.is_empty() and radio.snapshot().active_event==-1,"Finished local radio retained its active transmission")
		var invalid: Dictionary=radio.snapshot();invalid.visible=true
		check(audio.prepare_local_radio({"radio":invalid,"radio_changes":[]}).is_empty(),"Inactive visible radio bypassed voice validation")
		audio.free()
		if cursor==10:continue
		var story:=Radio.Sequence.new()
		if not story.configure_from_layout(bindings,library,layout,cursor):check(false,story.error);return
		check(story.step(100,{},0).is_empty() and not story.error.is_empty(),"Authored encounter radio accepted a context-free step")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

extends "res://tests/lounge_application.gd"
## One retained career, generated contacts and four actual application contracts.
## Initial hidden population history and combat hits are disclosed fixtures.
## No earned count, credits, inventory or accepted job is injected between jobs.
var jobs:=[]

func _initialize() -> void:call_deferred("run_progression")

func run_progression() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit content, bindings and visuals")
	if args.size()==3:verify(args)
	if failures==0 and origin!=null:
		visual=Visuals.new()
		check(visual.open(args[2],source.manifest),visual.error)
	if failures==0:
		root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
		app=Host.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		app.set_context(source,definitions,visual);app.set_process(false);app._focused=true
		await process_frame
		var fixture:=generated_fixture(0)
		if not fixture.is_empty():
			var session:=StationSession.new();app.viewport.add_child(session)
			session._world=fixture.owner
			if not session._build_scene(source,definitions,visual,catalogue,now_us,42):check(false,session.error)
			elif not app.station_panel.configure_empty(source,definitions) or not session.activate():check(false,app.station_panel.error+session.error)
			else:
				app.session=session;app.present_session()
				await complete_retained_jobs(args)
	if is_instance_valid(app):app.free()
	print("Lounge progression: %d checks; jobs %s; %d failures"%[checks,str(jobs),failures])
	quit(1 if failures else 0)

func complete_retained_jobs(args: PackedStringArray) -> void:
	var original_story: Dictionary=app.session.snapshot().mission.duplicate(true)
	var credits:=0
	for number in 4:
		if not app.contract_action("open",-1):check(false,app.session.error);return
		var contact:=-1
		var offers: Dictionary=app.session.snapshot().contracts.offers
		for preferred_kind in [0,7,4,12]:
			for id in offers:
				var preview: Dictionary=app.session.station_owner().contract_preview(id)
				if preview.get("can_accept",false) and offers[id].offer.mission.kind==preferred_kind:contact=id;break
			if contact>=0:break
		if contact<0:
			check(false,"No affordable contact in retained lounge: "+str(app.session.snapshot().contracts.population));return
		app.lounge_panel.select_contact(contact);app.lounge_panel.confirm();app.lounge_panel.confirm()
		if app._transition_failed:check(false,app.status.text);return
		var accepted: Dictionary=app.session.snapshot()
		var mission: Dictionary=accepted.contracts.mission
		if mission.is_empty():check(false,"The retained contact was not accepted");return
		var kind:=int(mission.kind)
		check(accepted.contracts.credits==credits and accepted.completed_side_missions==number and accepted.mission==original_story,"The next job reset the retained career or story")
		jobs.append({"kind":kind,"from":accepted.loadout.station_id,"to":mission.station_id,"contact":contact})
		print("Lounge progression job %d: %s"%[number+1,str(jobs.back())])
		app.lounge_panel.back()
		if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
		if not await release_application_flight():return
		if mission.station_id!=app.session.snapshot().location.station_id:
			if not await travel_application(mission.station_id):return
		if kind==0:
			if not await dock_application() or not application_step():return
		else:
			if not damage_contract_targets(kind):return
			for tick in 100:
				if not app.session.snapshot().contracts.pending_result.is_empty():break
				if not application_step():return
		await verify_application_result(kind,args,credits,number)
		if failures:return
		credits=app.session.snapshot().contracts.credits
		if app.session is FlightSession:
			if not await dock_application():return
		check(app.session.snapshot().completed_side_missions==number+1 and app.session.snapshot().contracts.credits==credits,"Docking lost the accumulated count or balance")
		check(app.session.snapshot().mission==original_story,"The station replaced the pending story")
		if failures:return
	check(jobs.size()==4 and app.session.snapshot().completed_side_missions==int(original_story.completed_contract_target),"The single career did not earn all four required successes")
	await after_four_successes()

func after_four_successes() -> void:
	# This is a detached continuation of the actual earned application state.
	# The application keeps its current boundary until the convoy flight works.
	var actual: RefCounted=app.session.station_owner()
	var before: Dictionary=actual.snapshot()
	if not definitions.mido_travel.has("contract_completion"):
		check(not actual.begin_contract_conversation(definitions,catalogue,source) and actual.snapshot()==before,"Older bindings enabled the unsupported story conversation")
		return
	check(not origin.begin_contract_conversation(definitions,catalogue,source),"The lounge introduction skipped its required contracts")
	var short: RefCounted=actual.fork()
	# Explicit offset-threshold fixture: four total successes do not satisfy a
	# requirement established after one prior success (target five).
	short._state.mission.completed_contract_target+=1
	var unchanged: Dictionary=short.snapshot()
	check(not short.begin_contract_conversation(definitions,catalogue,source) and short.snapshot()==unchanged,"The story used lifetime total four instead of its retained threshold")
	var continued: RefCounted=actual.fork()
	if not continued.begin_contract_conversation(definitions,catalogue,source):check(false,continued.error);return
	var opened: Dictionary=continued.snapshot()
	check(opened.dialogue.text_id==1792 and opened.dialogue.count==2 and opened.campaign_cursor==13,"The earned threshold opened the wrong original dialogue")
	check(opened.contracts==before.contracts and opened.mission==before.mission,"Opening the story paid or changed the retained job")
	check(not continued.begin_contract_conversation(definitions,catalogue,source) and continued.snapshot()==opened,"The open conversation restarted or advanced twice")
	check(continued.prepare_contract_departure(definitions,catalogue).is_empty(),"The unacknowledged story allowed departure")
	check(continued.acknowledge(),continued.error)
	check(continued.snapshot().dialogue.text_id==1793 and continued.snapshot().progress==before.progress,"The first line advanced the story early")
	check(continued.previous() and continued.snapshot().dialogue.text_id==1792,"Previous did not retain the original conversation")
	check(continued.acknowledge() and continued.acknowledge(),continued.error)
	var finished: Dictionary=continued.snapshot()
	check(finished.campaign_cursor==14 and finished.progress.campaign_cursor==14 and finished.contracts.campaign_cursor==14,"Final acknowledgement split the story and contract career")
	check(finished.mission=={"kind":4,"station_id":79,"reward":0,"bonus":0,"source_parameter":0},"The handoff invented a mission or reward")
	check(finished.completed_side_missions==4 and finished.contracts.completed_side_missions==4 and finished.contracts.credits==before.contracts.credits,"The story acknowledgement counted another contract or paid twice")
	check(finished.progress.rank_score==before.progress.rank_score+int(definitions.opening_handoff.cursor_weight),"The story lost its source rank contribution")
	check(finished.cargo==before.cargo and finished.equipment==before.equipment and finished.contracts.lounges==before.contracts.lounges,"The conversation changed inventory or regenerated contacts and stock")
	check(finished.contracts.progress==finished.progress and not finished.dialogue.visible and finished.phase=="convoy_departure_required","The continuation did not retain its next flight boundary")
	check(not continued.acknowledge() and continued.snapshot()==finished,"Repeated final acknowledgement advanced or paid again")
	check(actual.snapshot()==before,"Detached continuation mutated the actual application before convoy support")

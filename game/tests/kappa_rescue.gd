extends SceneTree
## Detached observations exercise radio and rescue boundaries. They create no
## inventory, earned career state, save fixture or playable mission completion.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Rules=preload("res://src/content/kappa_rescue_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const Rescue=preload("res://src/simulation/kappa_rescue.gd")
const Resources=preload("res://src/presentation/opening_radio_resources.gd")
const Audio=preload("res://src/content/audio_resources.gd")
var library: RefCounted
var bindings: RefCounted
var counts:=[]
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Kappa rescue components: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	library=Library.new();bindings=Bindings.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb"):
		check(false,library.error+bindings.error);return
	var owner:=Rescue.new()
	if not Rules.available(bindings):
		check(not owner.configure(bindings) and owner.snapshot().is_empty(),"Older content inferred the rescue")
		check(Rules.radio(bindings).is_empty(),"Older content inferred rescue radio")
		return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in Rules.SPANS:
		var changed: Dictionary=bindings.mido_travel.duplicate(true)
		changed.provenance[key].offset+=1
		check(not Travel.validate(changed,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Moved rescue proof accepted: "+key)
	for key in Rules.VALUES:
		var changed: Dictionary=bindings.mido_travel.duplicate(true)
		changed.kappa_rescue[key]=null
		check(not Travel.parameters(changed),"Changed rescue value accepted: "+key)
	var resources:=Resources.new()
	check(resources.prepare(library,bindings,null,21),resources.error)
	counts=resources.line_counts.duplicate()
	if counts.size()!=5:check(false,"Missing rescue source layout");return
	check(resources.speakers.has(10) and resources.speakers.has(0) and resources.speakers.has(14),"Missing rescue speakers")
	verify_sequence()
	verify_predicates()
	for language in ["gb","de"]:
		check(library.select_language(language),library.error)
		var audio:=Audio.new();check(audio.configure(library,bindings,21),audio.error)
		for id in range(504,509):
			var clip:=audio.prepare(id)
			check(not clip.is_empty() and not clip.has("unsupported") and clip.get("voice",false),"Rescue voice unavailable: %s/%d %s"%[language,id,audio.error])

func fresh_radio() -> RefCounted:
	var radio:=Radio.new()
	check(radio.configure(bindings,library,counts,21),radio.error)
	return radio

func targets() -> Dictionary:
	var rows:=[]
	for id in 4:rows.append({"scenery":false,"active":false,"friendly":false,"systems_disabled":false,"current_hull":100})
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":21,"route_index":0,"player_targets":rows}

func actors() -> Dictionary:
	var rows:=[]
	for source in Rules.VALUES.population.actors:
		var row: Dictionary=source.duplicate(true)
		row.hostile=bool(source.initial_hostile);row.actor_mode=5
		rows.append(row)
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":21,"actors":rows}

func finish(radio: RefCounted,event: int,at: int,context: Dictionary) -> int:
	check(radio.step_kappa_rescue(at+2000,context).is_empty() and not radio.snapshot().visible,"Radio appeared at the delay equality")
	check(radio.step_kappa_rescue(at+2001,context)==[{"kind":"display","event":event,"text_id":1856+event}],"Radio displayed the wrong original line")
	var end:=at+3500+2000*int(counts[event])
	check(radio.step_kappa_rescue(end,context).is_empty() and not radio.snapshot().finished[event],"Radio finished at duration equality")
	check(radio.step_kappa_rescue(end+1,context)==[{"kind":"finished","event":event}],"Radio did not finish once")
	return end+1

func verify_sequence() -> void:
	var radio:=fresh_radio();var context:=targets();var cast:=actors();var owner:=Rescue.new()
	check(owner.configure(bindings),owner.error)
	check(owner.advance(radio,cast) and not owner.snapshot().failure_ready and owner.snapshot().force_hostile_actor_ids.is_empty(),"Dormant actors failed or activated the rescue")
	var before:=owner.snapshot();var branch: RefCounted=owner.fork()
	cast.actors[2].hostile=true
	check(branch.advance(radio,cast) and branch.snapshot().force_hostile_actor_ids==[1,2,3] and branch.snapshot().phase==0 and owner.snapshot()==before,"Escort provocation altered the wrong group or parent")
	cast.actors[2].hostile=false
	check(radio.step_kappa_rescue(0,context).is_empty(),"Dormant ships started the scout conversation")
	context.player_targets[1].active=true
	check(radio.step_kappa_rescue(0,context)==[{"kind":"started","event":0}],"Active unfriendly scout did not start radio")
	context.route_index=1
	var now:=finish(radio,0,0,context)
	check(radio.snapshot().waypoint_observations.get(2)==0,"Playing radio prematurely observed the waypoint")
	check(radio.step_kappa_rescue(now,context)==[{"kind":"started","event":1}],"Keith lost the scout reply dependency")
	now=finish(radio,1,now,context)
	check(radio.step_kappa_rescue(now,context)==[{"kind":"started","event":2}],"Deferred first waypoint observation was lost")
	check(owner.advance(radio,cast) and owner.snapshot().phase==1 and owner.snapshot().force_hostile_actor_ids==[1,2,3],"Attack radio did not activate the three escorts")
	check(owner.advance(radio,cast) and owner.snapshot().force_hostile_actor_ids.is_empty(),"Attack activation repeated")
	now=finish(radio,2,now,context)
	check(radio.step_kappa_rescue(now,context).is_empty(),"Inactive kidnapper started its transmission")
	context.player_targets[0].active=true
	check(radio.step_kappa_rescue(now,context)==[{"kind":"started","event":3}],"Active kidnapper lost its transmission")
	now=finish(radio,3,now,context)
	check(radio.step_kappa_rescue(now,context).is_empty(),"Healthy systems completed the rescue")
	context.player_targets[0].systems_disabled=true
	check(radio.step_kappa_rescue(now,context)==[{"kind":"started","event":4}],"Disabled kidnapper did not report systems failure")
	check(owner.advance(radio,cast) and not owner.snapshot().completion_ready,"Starting the final line completed the rescue")
	now=finish(radio,4,now,context)
	check(owner.advance(radio,cast) and owner.snapshot().completion_ready and not owner.snapshot().failure_ready and owner.snapshot().campaign_cursor==21,"Finished radio failed to offer the result or changed career state")
	cast.actors[0].actor_mode=3
	check(owner.advance(radio,cast) and not owner.snapshot().failure_ready,"Breakup bypassed the source retirement condition")
	cast.actors[0].actor_mode=4
	check(owner.advance(radio,cast) and owner.snapshot().failure_ready,"Retired kidnapper failed to report mission failure")
	before=owner.snapshot();cast.actors[0].hull_catalogue_id=5
	check(not owner.advance(radio,cast) and owner.snapshot()==before,"Changed cast partly committed rescue state")
	cast=actors();before=owner.snapshot()
	check(not owner.advance(fresh_radio(),cast) and owner.snapshot()==before,"Regressed radio replaced rescue state")

func verify_predicates() -> void:
	var radio:=fresh_radio();var context:=targets();var before: Dictionary=radio.snapshot()
	check(radio.step(0,{},0).is_empty() and not radio.error.is_empty() and radio.snapshot()==before,"Generic radio inputs bypassed target observations")
	var bad:=context.duplicate(true);bad.player_targets[3].erase("systems_disabled")
	check(radio.step_kappa_rescue(0,bad).is_empty() and not radio.error.is_empty() and radio.snapshot()==before,"Malformed last target partly updated radio")
	bad=context.duplicate(true);bad.binding_id="foreign"
	check(radio.step_kappa_rescue(0,bad).is_empty() and radio.snapshot()==before,"Foreign target list changed radio")
	context.route_index=1
	var speculative: RefCounted=radio.fork_for_frame()
	check(speculative.step_kappa_rescue(0,context)==[{"kind":"started","event":2}] and radio.snapshot()==before,"Inactive living ships did not count as survivors or speculative radio leaked")
	context.player_targets[0].current_hull=0;context.player_targets[1].current_hull=-1
	context.player_targets[2].scenery=true
	check(radio.step_kappa_rescue(0,context).is_empty(),"Scenery or dead hulls counted as living ships")
	context.player_targets[0].current_hull=100
	check(radio.step_kappa_rescue(1,context).is_empty(),"A consumed route transition replayed after survivor count increased")
	context.route_index=2
	check(radio.step_kappa_rescue(2,context).is_empty(),"The second waypoint replayed the first-waypoint condition")
	radio=fresh_radio();context=targets();context.route_index=-1
	check(radio.step_kappa_rescue(0,context).is_empty() and radio.snapshot().waypoint_observations.is_empty(),"An absent route changed observation history")
	context.route_index=0;context.player_targets[0].scenery=true;context.player_targets[0].active=true
	check(radio.step_kappa_rescue(1,context).is_empty(),"Scenery started an NPC radio condition")
	context.player_targets[0].scenery=false;context.player_targets[0].friendly=true
	check(radio.step_kappa_rescue(2,context)==[{"kind":"started","event":3}],"Indexed activity was incorrectly gated by hostility")
	radio=fresh_radio();context=targets();context.player_targets[0].systems_disabled=true
	check(radio.step_kappa_rescue(0,context)==[{"kind":"started","event":4}],"Systems-disabled predicate added an unsupported activity gate")
	before=radio.snapshot()
	check(radio.step_kappa_rescue(-1,context).is_empty() and radio.snapshot()==before,"Backward time changed radio")

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)

extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Mounts=preload("res://src/content/weapon_mounts.gd")
const Opening=preload("res://src/simulation/opening_loadout.gd")
const Primary=preload("res://src/simulation/primary_weapons.gd")
const NPC=preload("res://src/simulation/opening_npc_weapons.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
const Selection=preload("res://src/simulation/weapon_audio.gd")
const Definitions=preload("res://src/content/weapon_audio_definitions.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
var checks:=0
var failures:=0

func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	for i in range(0,args.size(),3):
		verify(args[i],args[i+1])
		await process_frame
	print("Weapon audio: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(content: String,pack: String):
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):check(false,library.error+bindings.error+catalogues.error);return
	var mounts:=Mounts.new();var loadout:=Opening.new();var primary:=Primary.new()
	if not mounts.open(library,catalogues) or not loadout.configure(bindings,catalogues,catalogues.content_id) or not primary.configure(bindings,catalogues,mounts,loadout.snapshot()):check(false,mounts.error+loadout.error+primary.error);return
	var data: Dictionary=bindings.weapon_parameters.get("audio",{})
	if data.is_empty():
		primary.advance(1)
		check(not primary.fire(Transform3D.IDENTITY,true).weapons[0].has("audio_events"),"Legacy pack invented weapon audio")
		return
	verify_selection(data,catalogues.tables.items)
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for key in data.provenance:
		var broken:=data.duplicate(true);broken.provenance[key].offset+=2
		check(not Definitions.validate(broken,header.source_executable_bytes,header.architecture,bindings.weapon_parameters,bindings.opening_actors,bindings.opening_staging).is_empty(),"Disconnected sound provenance accepted: "+key)
	var pose:=Transform3D(Basis(Vector3.UP,0.3),Vector3(100,20,300))
	var equal_interval:=primary.fire(pose,true)
	check(equal_interval.weapons[0].audio_events.is_empty() and equal_interval.weapons[1].audio_events.is_empty(),"Interval equality played a gun")
	primary.advance(1)
	var saved:=primary.snapshot()
	check(primary.fire(pose,false).weapons[0].audio_events.is_empty() and primary.snapshot()==saved,"Denied fire played sound or changed its owner")
	var volley:=primary.fire(pose,true)
	check(volley.weapons[0].slot==1 and volley.weapons[0].audio_events.size()==1 and volley.weapons[1].audio_events.is_empty(),"Duplicate opening guns did not use only the first firing entry")
	var cue: Dictionary=volley.weapons[0].audio_events[0]
	check(cue.source_id==54 and cue.pitch_raw==0.0 and cue.position==pose.origin and cue.position!=volley.weapons[0].result.projectile.position,"Player audio used a muzzle or incorrect event/pitch")
	saved=primary.snapshot()
	check(primary.fire(Transform3D(Basis.IDENTITY,Vector3(INF,0,0)),true).is_empty() and primary.snapshot()==saved,"Failed volley mutated weapon audio state")
	var fork:=primary.fork_state();fork._guns[0].audio.enabled=false
	check(primary.snapshot().guns[0].audio.enabled,"Forked audio selection aliases its owner")
	var empty_seed:=loadout.snapshot();empty_seed.slots[1].quantity=0
	var empty:=Primary.new();check(empty.configure(bindings,catalogues,mounts,empty_seed),empty.error);empty.advance(1)
	var empty_shot:=empty.fire(pose,true)
	check(empty_shot.weapons[0].result.reason=="quantity" and empty_shot.weapons[0].audio_events.is_empty() and empty_shot.weapons[1].result.fired and empty_shot.weapons[1].audio_events.is_empty(),"Empty selected gun transferred sound to a duplicate")
	# A full projectile pool is a valid denied launch; audio follows the result.
	var full:=primary.fork_state()
	for gun in full._guns:
		for j in gun.projectiles._slots.size():gun.projectiles._slots[j]={"remaining_ms":1000}
		gun.projectiles._elapsed_ms=100000
	var capacity: Dictionary=full.fire(pose,true)
	check(capacity.weapons[0].result.reason=="capacity" and capacity.weapons[0].audio_events.is_empty(),"Capacity rejection played a gun")
	var npc:=NPC.new();check(npc.configure(bindings,catalogues),npc.error)
	var actors:=active_group(bindings,catalogues)
	npc.advance(1)
	var npc_shots:=npc.fire(actors,[2,0,1])
	check(npc_shots.actors.size()==3,"NPC firing lost an owner")
	for id in 3:
		var shot: Dictionary=npc_shots.actors[id]
		check(shot.actor_id==id and shot.audio_events.size()==1 and shot.audio_events[0].source_id==61 and shot.audio_events[0].position==Vector3(100+id*100,0,0),"NPC sound did not retain its source launch position")
	check(npc.fire(actors,[0]).actors[0].audio_events.is_empty(),"NPC interval rejection played sound")
	verify_playback(library,bindings,primary.snapshot(),volley,npc_shots)

func verify_selection(data: Dictionary, source_items: Array):
	var items:=source_items.duplicate(true)
	for id in 3:
		items[id].arrays[2][15]=10+id*10;items[id].arrays[2][17]=10+id*10
	var entries:=Selection.player_entries(data,items,[weapon(0),weapon(0),weapon(2)])
	check(entries.size()==3 and entries[0].enabled and entries[1].enabled and not entries[2].enabled,"Price-sorted copy indices were incorrectly remapped to original item IDs")
	entries=Selection.player_entries(data,items,[weapon(2),weapon(2),weapon(0)])
	check(entries[0].enabled and not entries[1].enabled and entries[2].enabled,"Duplicate elimination lost a later distinct weapon")
	entries=Selection.player_entries(data,items,[weapon(0),weapon(1),weapon(2)])
	check(entries[0].enabled and entries[1].enabled and not entries[2].enabled,"Player sound entry limit changed")
	items[0].arrays[2][15]=30;items[0].arrays[2][17]=30
	entries=Selection.player_entries(data,items,[weapon(0),weapon(2),weapon(0)])
	check(entries[0].enabled and entries[1].enabled and not entries[2].enabled,"Equal-price order changed")
	entries=Selection.player_entries(data,items,[weapon(0,0.75)])
	check(entries[0].pitch_raw==0.25,"Equipped interval reduction did not reach raw pitch")
	entries=Selection.player_entries(data,items,[weapon(0,1.25)])
	check(entries[0].pitch_raw==0.0,"Negative pitch update changed the fresh zero default")
	var missing:=data.duplicate(true);missing.player_event_ids[0]=-1
	entries=Selection.player_entries(missing,items,[weapon(0)])
	check(Selection.cue(entries[0],Vector3.ZERO).is_empty(),"Absent source event was replaced")
	check(Selection.npc_entry(data,9).source_id==62 and Selection.npc_entry(data,10).source_id==2276 and Selection.npc_entry(data,11).source_id==61,"NPC sound-kind table or fallback changed")
	items[0].arrays[2][15]=-2147483648;items[0].arrays[2][17]=2147483647
	check(Selection.player_entries(data,items,[weapon(0)]).is_empty(),"Source price overflow was accepted")
	var broken:=data.duplicate(true);broken.player_event_ids[0]=true
	check(not Definitions.parameters(broken),"Boolean event identifier was accepted")
	broken=data.duplicate(true);broken.player_event_ids.pop_back()
	check(not Definitions.parameters(broken),"Truncated source event table was accepted")

func verify_playback(library: RefCounted,bindings: RefCounted,primaries: Dictionary,volley: Dictionary,npc_shots: Dictionary):
	var audio:=Audio.new();root.add_child(audio);check(audio.configure(library,bindings,123),audio.error);audio.set_paused(true)
	var world:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"elapsed_ms":0,"primaries":primaries,"primary_fire":volley,
		"actor_events":[{"actor_id":0,"firing":{"actors":[npc_shots.actors[0]]}},{"actor_id":1,"destruction":{"started":true,"breakup":false,"sound_events":[20],"audio_events":[{"source_id":20,"position":Vector3(100,0,0)}]}}]}
	var before:=audio.snapshot();var prepared:=audio.prepare_frame(0,frame(0),world)
	check(not prepared.is_empty() and audio.snapshot()==before,"Weapon preparation played or consumed random choices")
	if prepared.is_empty():check(false,audio.error);audio.free();return
	check(prepared.operations.map(func(op):return op.source_id)==[54,61,20],"Player/NPC firing and death audio order changed")
	var corrupt:=world.duplicate(true);corrupt.actor_events[0].firing.actors[0].audio_events[0].position=Vector3(NAN,0,0)
	check(audio.prepare_frame(0,frame(0),corrupt).is_empty() and audio.snapshot()==before,"Late malformed cue partially played the volley")
	corrupt=world.duplicate(true);corrupt.primary_fire.weapons[0].result.fired=false
	check(audio.prepare_frame(0,frame(0),corrupt).is_empty(),"Audio was accepted for a rejected launch")
	corrupt=world.duplicate(true);corrupt.primary_fire.weapons[1].audio_events=[volley.weapons[0].audio_events[0]]
	check(audio.prepare_frame(0,frame(0),corrupt).is_empty(),"Disabled duplicate emitted a sound")
	corrupt=world.duplicate(true);corrupt.primary_fire.weapons[0].result=false
	check(audio.prepare_frame(0,frame(0),corrupt).is_empty(),"Malformed launch result was accepted")
	corrupt=world.duplicate(true);corrupt.actor_events[0].destruction=3
	check(audio.prepare_frame(0,frame(0),corrupt).is_empty(),"Malformed NPC destruction was accepted alongside firing")
	audio.commit_frame(prepared)
	var first:=audio.snapshot()
	check(first.active.has(54) and first.active.has(61) and first.unsupported.is_empty(),"Connected weapon events were not playable")
	check(first.active[54].pitch>=pow(2.0,-0.050001) and first.active[54].pitch<=pow(2.0,0.050001) and first.active[61].pitch>=pow(2.0,-0.020001) and first.active[61].pitch<=pow(2.0,0.020001),"Source weapon pitch variation changed")
	var node: Node=audio._players[54].node
	world.elapsed_ms=1;world.primary_fire.weapons[0].audio_events[0].position=Vector3(150,20,300)
	audio.commit_frame(audio.prepare_frame(1,frame(1),world))
	check(audio._players[54].node==node and audio.snapshot().random_state==first.random_state and audio.snapshot().active[54].position==Vector3(150,20,300),"Active cached gun restarted or redrew its random sample")
	world.elapsed_ms=2;world.primaries.guns[0].audio.pitch_raw=0.25;world.primary_fire.weapons[0].audio_events[0].pitch_raw=0.25
	audio.commit_frame(audio.prepare_frame(2,frame(2),world))
	check(audio._players[54].node==node and is_equal_approx(node.pitch_scale,2.0*first.active[54].pitch),"Raw equipment pitch did not update the cached voice")
	var committed:=audio.snapshot();audio.commit_frame(prepared)
	check(audio.snapshot()==committed,"Replayed frame duplicated a sound")
	audio.set_paused(false);node.stop();world.elapsed_ms=3
	audio.commit_frame(audio.prepare_frame(3,frame(3),world))
	check(node.is_queued_for_deletion() and audio.snapshot().random_state!=committed.random_state,"Completed gun sound did not restart")
	audio.clear();check(audio.get_child_count()==0,"Weapon audio survived owner cleanup");audio.free()

func active_group(bindings: RefCounted,catalogues: RefCounted) -> RefCounted:
	var combat:=Combat.new();check(combat.configure(bindings,catalogues,0.5),combat.error)
	var scene:=combat.snapshot()
	for id in 3:
		scene.actors[id].pose=Transform3D(Basis.IDENTITY,Vector3(100+id*100,0,0));scene.actors[id].position=scene.actors[id].pose.origin
	var finished:=[];finished.resize(bindings.opening_dialogue.events.size());finished.fill(false);finished[7]=true
	check(combat.update(scene,3,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"finished":finished}),combat.error)
	return combat
func weapon(id: int,factor: float=1.0) -> Dictionary:return {"item_id":id,"interval_multiplier":factor}
func frame(ms: int) -> Dictionary:return {"elapsed_ms":ms,"camera":{"view":{"pose":Transform3D.IDENTITY}}}
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)

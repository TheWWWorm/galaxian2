extends SceneTree
const Music=preload("res://src/simulation/ordinary_music.gd")
const Definitions=preload("res://src/content/ordinary_music_definitions.gd")
var checks:=0
var failures:=0

func _initialize():call_deferred("run")

func run():
	var rules: Dictionary=Definitions.VALUES.duplicate(true)
	rules.provenance={"selector":{"offset":100,"bytes":1001},"faction_getter":{"offset":200,"bytes":10},"faction_table":{"offset":300,"bytes":16}}
	var owner:=Music.new()
	check(owner.configure(rules),"Source music rules were refused")
	var imported:=Music.new()
	check(imported.configure(JSON.parse_string(JSON.stringify(rules))),"JSON music rules were refused")
	assert_selection(imported,141,3,3,true,141,"Imported battle cue remains active")
	assert_selection(imported,137,0,3,true,137,"Imported exploration cue remains active")
	check(Definitions.validate({},0,"armv7",{},{}).is_empty(),"Unsupported profile must omit the optional declaration")
	check(not Definitions.validate([],0,"x86_64",{},{}).is_empty(),"Nondictionary optional music was accepted")
	assert_selection(owner,-1,0,0,true,134,"Initial ordinary Terran flight")
	assert_selection(owner,134,0,0,true,134,"Same exploration cue stays active")
	assert_selection(owner,134,0,1,true,134,"Faction change alone does not interrupt a retained exploration cue")
	assert_selection(owner,134,1,1,true,140,"One hostile enters battle")
	assert_selection(owner,140,3,1,true,140,"Active battle music survives an intensity change")
	assert_selection(owner,140,0,1,true,139,"Battle exit selects current faction exploration")
	assert_selection(owner,139,4,1,true,141,"Three to four hostiles select mid battle")
	assert_selection(owner,141,5,1,true,141,"Active mid battle music does not retune at five hostiles")
	assert_selection(owner,139,5,1,true,142,"Five hostiles select full battle at entry")
	assert_selection(owner,142,0,3,true,137,"Battle exit selects Midorian exploration")
	assert_selection(owner,-1,0,2,true,138,"Nivelian exploration table index")
	assert_selection(owner,143,5,0,true,143,"Intro music freezes radar music selection")
	assert_selection(owner,145,0,0,true,145,"Authored Void peace music is retained")
	assert_selection(owner,151,2,0,true,151,"Authored wanted battle music is retained")
	assert_selection(owner,141,0,0,false,141,"Hidden or absent HUD sample leaves music untouched")
	check(owner.prepare(141,0,0,true,false).is_empty() and not owner.error.is_empty(),"Special scene was incorrectly treated as ordinary")
	check(owner.prepare(-2,0,0,true,true).is_empty(),"Invalid retained music was accepted")
	check(owner.prepare(140,-1,0,true,true).is_empty(),"Negative radar count was accepted")
	check(owner.prepare(140,0,4,true,true).is_empty(),"Unknown faction index was accepted")
	var flight:={"world_type":3,"campaign_cursor":0,"selected_station_id":78,"retained_void_station_id":-1,"void_source_station_id":-1,"system_id":15,"radar_kind10":false,"radar_marked_actor":false}
	check(Music.ordinary_context(flight,0),"Opening ordinary location must remain eligible once intro143 releases")
	for cursor in [2,4,7,8,10,11,12,13,14]:
		flight.campaign_cursor=cursor
		check(Music.ordinary_context(flight,0),"Mido station78 flight lost ordinary music at cursor "+str(cursor))
	flight.campaign_cursor=18;flight.selected_station_id=98;flight.system_id=19
	check(Music.ordinary_context(flight,0),"First free flight at Alioth98 must use faction music")
	for cursor in [21,22]:
		flight.campaign_cursor=cursor;flight.selected_station_id=55;flight.system_id=11
		check(Music.ordinary_context(flight,0),"Kappa55 flight lost ordinary faction music")
	flight.campaign_cursor=23;flight.selected_station_id=10;flight.system_id=6
	check(not Music.ordinary_context(flight,0) and Music.ordinary_context(flight,2),"Kappa return to Thynome10 has special peace music")
	flight.campaign_cursor=24;flight.selected_station_id=48;flight.system_id=9
	check(Music.ordinary_context(flight,0),"Sahi48 ordinary faction cue was excluded")
	flight.campaign_cursor=27;flight.selected_station_id=10;flight.system_id=6
	check(not Music.ordinary_context(flight,0) and Music.ordinary_context(flight,2),"Thynome10 has special peace152 but ordinary battle")
	flight.campaign_cursor=31;flight.selected_station_id=98;flight.system_id=19;flight.void_source_station_id=91
	check(Music.ordinary_context(flight,0),"Alioth31 must use its ordinary faction cue")
	flight.campaign_cursor=32;flight.selected_station_id=10;flight.system_id=6
	check(not Music.ordinary_context(flight,0) and Music.ordinary_context(flight,2),"Thynome32 peace remains station-special")
	flight.campaign_cursor=28;flight.selected_station_id=91;flight.system_id=18
	check(not Music.ordinary_context(flight,0) and not Music.ordinary_context(flight,2),"Dima source station must take its portal music")
	flight.campaign_cursor=33;flight.selected_station_id=98;flight.system_id=19;flight.void_source_station_id=98
	check(not Music.ordinary_context(flight,0),"Rerolled Void source must not get faction music")
	flight.void_source_station_id=91;flight.selected_station_id=-1;flight.retained_void_station_id=-1;flight.system_id=-1
	check(not Music.ordinary_context(flight,0),"Retained Void location must not reach normal music")
	flight.selected_station_id=108;flight.system_id=19
	check(not Music.ordinary_context(flight,0) and not Music.ordinary_context(flight,2),"Unavailable station108 remains guarded")
	flight.selected_station_id=101
	check(not Music.ordinary_context(flight,0) and not Music.ordinary_context(flight,2),"Unavailable station101 remains guarded")
	flight.selected_station_id=100
	check(not Music.ordinary_context(flight,0) and Music.ordinary_context(flight,2),"Station100 peace is special152")
	flight.selected_station_id=98;flight.system_id=27
	check(not Music.ordinary_context(flight,0) and not Music.ordinary_context(flight,2),"Unavailable system27 remains guarded")
	flight.system_id=19;flight.campaign_cursor=16
	check(not Music.ordinary_context(flight,2),"Cursor16 battle selects special136")
	flight.campaign_cursor=18;flight.radar_kind10=true
	check(not Music.ordinary_context(flight,2) and Music.ordinary_context(flight,0),"Counted kind10 changes only the battle branch")
	flight.radar_kind10=false;flight.radar_marked_actor=true
	check(not Music.ordinary_context(flight,2),"Marked radar actor changes battle music")
	flight.radar_marked_actor=false
	var incomplete: Dictionary=flight.duplicate();incomplete.erase("void_source_station_id")
	check(not Music.ordinary_context(incomplete,0),"Unobserved portal source was assumed ordinary")
	var scene:={"world_type":3,"campaign_cursor":32,"selected_station_id":10,"retained_void_station_id":-1,"void_source_station_id":91,"system_id":6,"radar_kind10":false,"radar_marked_actor":false}
	assert_context_selection(owner,-1,0,2,scene,152,"Thynome10 begins source Deep Science peace cue")
	assert_context_selection(owner,140,0,2,scene,152,"Thynome battle exit returns to event152")
	assert_context_selection(owner,152,2,2,scene,140,"Thynome combat enters ordinary low battle")
	assert_context_selection(owner,134,0,2,scene,134,"Retained faction peace cue survives station change")
	scene.selected_station_id=100
	assert_context_selection(owner,-1,0,2,scene,152,"Station100 shares source peace event152")
	scene.selected_station_id=91;scene.system_id=18
	assert_context_selection(owner,-1,0,0,scene,145,"Dima source station begins Void peace cue")
	assert_context_selection(owner,145,3,0,scene,136,"Dima source station enters Void battle cue")
	assert_context_selection(owner,141,3,0,scene,141,"Retained battle cue survives entry into portal station")
	scene.selected_station_id=-1;scene.retained_void_station_id=-1;scene.system_id=-1
	assert_context_selection(owner,-1,0,-1,scene,145,"Selected retained Void begins peace cue without a catalogue faction")
	assert_context_selection(owner,-1,5,-1,scene,136,"Selected retained Void begins battle cue without a catalogue faction")
	scene.selected_station_id=98;scene.system_id=19;scene.campaign_cursor=16
	assert_context_selection(owner,-1,5,0,scene,136,"Cursor16 battle precedes count and actor variants")
	scene.campaign_cursor=18;scene.radar_kind10=true
	assert_context_selection(owner,-1,1,0,scene,151,"Counted kind10 picks event151 at low count")
	assert_context_selection(owner,-1,5,0,scene,151,"Counted kind10 picks event151 at high count")
	scene.radar_kind10=false;scene.radar_marked_actor=true
	assert_context_selection(owner,-1,1,0,scene,149,"Marked actor chooses event149 at low count")
	assert_context_selection(owner,-1,4,0,scene,149,"Marked actor chooses event149 through count4")
	assert_context_selection(owner,-1,5,0,scene,150,"Marked actor chooses event150 above count4")
	scene.radar_kind10=true
	assert_context_selection(owner,-1,5,0,scene,151,"Kind10 takes precedence over marked actor")
	scene.radar_kind10=false;scene.radar_marked_actor=false;scene.campaign_cursor=1
	assert_context_selection(owner,-1,0,0,scene,143,"Cursor1 reselects source intro cue when released")
	scene.campaign_cursor=18
	var no_flags: Dictionary=scene.duplicate();no_flags.erase("radar_kind10");no_flags.erase("radar_marked_actor")
	check(owner.prepare_for_context(-1,1,0,true,no_flags).is_empty(),"Positive radar count guessed missing special flags")
	assert_context_selection(owner,-1,0,0,no_flags,134,"Zero radar count does not require positive-count flags")
	check(owner.prepare_for_context(-1,0,-1,true,no_flags).is_empty(),"Ordinary peace inferred a missing system faction")
	assert_context_selection(owner,-1,1,-1,scene,140,"Battle music does not need an unused faction index")
	scene.campaign_cursor=18;scene.selected_station_id=101
	check(owner.prepare_for_context(-1,0,0,true,scene).is_empty() and not owner.error.is_empty(),"Unavailable Valkyrie peace scene was guessed")
	scene.selected_station_id=98;scene.system_id=27
	check(owner.prepare_for_context(-1,0,0,true,scene).is_empty(),"Unavailable Supernova system was guessed")
	check(owner.prepare_for_context(143,0,0,true,{}).get("selected_id")==143,"Retained intro143 must bypass context")
	check(owner.prepare_for_context(141,0,0,false,{}).get("selected_id")==141,"No radar sample must retain music without context")
	print("Ordinary music: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func assert_selection(owner: RefCounted,current: int,count: int,faction: int,sampled: bool,wanted: int,label: String) -> void:
	var frame: Dictionary=owner.prepare(current,count,faction,sampled,true)
	check(not frame.is_empty() and frame.get("selected_id")==wanted and frame.get("operations",[]).size()==(0 if current==wanted else 1),label+": "+str(frame))
	if not frame.is_empty() and frame.get("operations",[]).size()==1:
		check(frame.operations[0]=={"action":"replace_music","source_id":wanted},label+" did not use the shared playback command")

func assert_context_selection(owner: RefCounted,current: int,count: int,faction: int,context: Dictionary,wanted: int,label: String) -> void:
	var frame: Dictionary=owner.prepare_for_context(current,count,faction,true,context)
	check(not frame.is_empty() and frame.get("selected_id")==wanted and frame.get("operations",[]).size()==(0 if current==wanted else 1),label+": "+str(frame))
	if not frame.is_empty() and frame.get("operations",[]).size()==1:
		check(frame.operations[0]=={"action":"replace_music","source_id":wanted},label+" did not use the shared playback command")

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

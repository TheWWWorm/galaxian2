extends SceneTree
const Drill=preload("res://src/simulation/mining_drill.gd")
const Extraction=preload("res://src/simulation/mining_extraction.gd")
const Definitions=preload("res://src/content/mining_drill_definitions.gd")
const Field=preload("res://src/simulation/scenery_field.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
var checks:=0
var failures:=0
var bindings: RefCounted
var cat: RefCounted
var field:={}
var random:={}
var by_size:={}
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()>=2,"Expected Mac content and bindings")
	if args.size()>=2:verify(args)
	print("Mining drill: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: Array):
	var lib:=Library.new();bindings=Bindings.new();cat=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var drill:=Drill.new()
	check(drill.snapshot().is_empty() and not drill.advance(0,{}) and not drill.stop(),"Unprepared drill accepted an action")
	if bindings.mining_drill.is_empty():
		check(not drill.configure(bindings,cat,[90,81],{},0,Vector2.ZERO),"Legacy pack invented mining support");return
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(bindings.mining_drill,metadata.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.first_flight).is_empty(),"Valid mining declarations rejected")
	check(not Definitions.validate(bindings.mining_drill,metadata.source_executable_bytes,"x86_64",bindings.arrival_staging,{}).is_empty(),"Mining accepted a missing field capability")
	for key in Definitions.SPANS:
		var bad: Dictionary=bindings.mining_drill.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,metadata.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.first_flight).is_empty(),"Detached mining source span accepted: "+key)
	var generator:=Random.new();generator.seed_from(12345);random=generator.snapshot()
	var population:=Field.new();check(population.configure(bindings,cat,78,false,false,2),population.error)
	field=population.generate(Vector3(12298,36830,77237),random)
	if field.is_empty():check(false,population.error);return
	for object in field.objects:by_size[int(object.source_size_value)]=int(object.index)
	check(by_size.size()==4,"Reference field does not cover four asteroid classes")
	if by_size.size()!=4:return
	for id in [86,87,88,89,90]:
		check(drill.configure(bindings,cat,[id,81],field,by_size[7],Vector2(640,360)),drill.error)
		var source: Dictionary=cat.tables.items[id].properties
		check(is_equal_approx(drill.snapshot().stability,float(source[32])/100.0*1.5+0.3) and is_equal_approx(drill.snapshot().rate,float(source[33])/100.0),"Drill ignored equipment properties")
	drill=new_drill(7);var fresh:=drill.snapshot()
	for items in [[],[81],[81,90,86],[90,90],[0],[90,233]]:
		check(not drill.configure(bindings,cat,items,field,by_size[7],Vector2(640,360)) and drill.snapshot()==fresh,"Invalid equipment replaced the active drill")
	var foreign:=field.duplicate(true);foreign.binding_id="foreign"
	check(not drill.configure(bindings,cat,[90,81],foreign,by_size[7],Vector2.ZERO) and drill.snapshot()==fresh,"Foreign field replaced drilling")
	for vital in [{"hull":0},{"hull":-1},false]:
		var exhausted:=field.duplicate(true);exhausted.objects[by_size[7]].vitals=vital
		check(not drill.configure(bindings,cat,[90,81],exhausted,by_size[7],Vector2.ZERO) and drill.snapshot()==fresh,"Invalid or exhausted asteroid replaced drilling")
	for value in [-1,151,1.5,"10"]:check(not drill.advance(value,random) and drill.snapshot()==fresh,"Invalid time mutated drill state")
	check(not drill.advance(100,{"state":-1}) and drill.snapshot()==fresh,"Invalid random stream advanced drilling")
	check(not drill.set_command(Vector2(NAN,0)) and not drill.set_command(Vector2(0,1.1)) and drill.snapshot()==fresh,"Invalid input mutated drilling")
	check(drill.advance(150,random,true) and drill.snapshot()==fresh,"Pause advanced drilling or the shared random stream")
	check(drill.set_command(Vector2(0.5,-0.5)),drill.error)
	check(drill.snapshot().input==Vector2(0.75,-0.75),"Analog drilling input lost its signed square curve")
	check(drill.set_command(Vector2.ZERO),drill.error)
	var time:=0
	while time<2500:
		var dt:=mini(100,2500-time);drill.advance(dt,random);time+=dt
	check(drill.snapshot().drift==Vector2.ZERO and drill.snapshot().drift_changes==0 and drill.snapshot().random_state==random,"Drift changed at or before 2500 ms")
	drill.advance(1,random)
	var changed:=drill.snapshot()
	check(changed.drift_elapsed_ms==751 and changed.drift_changes==1 and changed.random_state=={"state":234494368871619},"Drift did not consume the shared interval and four direction draws")
	check(changed.drift==Vector2(-0.3888888955116272,-0.6111111640930176) and changed.point==Vector2(639.9805297851562,359.9694519042969),"Drift direction, stability or single-precision motion changed")
	var copy: RefCounted=drill.fork();copy.set_command(Vector2.ONE);copy.advance(100,changed.random_state)
	check(drill.snapshot()==changed and copy.snapshot()!=changed,"Forked drill mutated its parent")
	var exported: Dictionary=copy.snapshot();exported.random_state.state=0
	check(copy.snapshot().random_state.state!=0,"Snapshot exposes mutable random state")
	# A 2.5-unit command moves exactly 0.125 pixels/ms: 999 ms is inside,
	# 1000 ms reaches the first ring boundary. Its equality must be outside.
	drill=new_drill(7);drill.set_command(Vector2(sqrt(2.5/3.0),0))
	for i in 9:drill.advance(100,random)
	drill.advance(99,random)
	check(drill.snapshot().inside and drill.snapshot().point.x==764.875,"Reference boundary setup moved unexpectedly")
	drill.advance(1,random)
	check(not drill.snapshot().inside and drill.snapshot().outside_elapsed_ms==1 and drill.snapshot().point.x==765.0,"Ring boundary equality counted as inside")
	drill.set_command(Vector2(-sqrt(2.5/3.0),0));drill.advance(1,random)
	check(drill.snapshot().inside and drill.snapshot().outside_elapsed_ms==1,"Reentering the ring refunded outside time")
	# Leave, return, then leave again through public input. Both excursions
	# count toward the same failure limit, while extraction pauses outside.
	drill=new_drill(7)
	for i in 40:steer(drill,Vector2(840,360),50)
	var outside:=drill.snapshot()
	check(not outside.inside and outside.outside_elapsed_ms>0,"Controlled excursion never left the ring")
	for i in 8:steer(drill,Vector2(840,360),50)
	check(drill.snapshot().ore_progress==outside.ore_progress,"Ore accumulated outside the ring")
	for i in 35:steer(drill,Vector2(640,360),50)
	var reentered:=drill.snapshot()
	check(reentered.inside and reentered.outside_elapsed_ms>outside.outside_elapsed_ms and reentered.phase=="drilling","Return flight discarded cumulative outside time")
	for i in 5:steer(drill,Vector2(640,360),50)
	check(drill.snapshot().outside_elapsed_ms==reentered.outside_elapsed_ms and drill.snapshot().ore_progress>reentered.ore_progress,"Inside drilling did not resume without refunding outside time")
	for i in 100:
		var state:=drill.snapshot()
		if state.outside_elapsed_ms>=2500:break
		steer(drill,Vector2(840,360),mini(50,2500-int(state.outside_elapsed_ms)))
	check(drill.snapshot().outside_elapsed_ms==2500 and drill.snapshot().phase=="drilling","Failure threshold was not strictly greater than 2500")
	steer(drill,Vector2(840,360),1)
	var failed:=drill.snapshot()
	check(failed.phase=="failed" and failed.ore_tons==0 and failed.ore_progress==0 and not failed.core,"Failure retained unearned ore or a core")
	check(drill.advance(100,failed.random_state) and drill.snapshot()==failed and not drill.stop(),"Terminal drill advanced or repeated its stop")
	var extraction:=Extraction.new()
	check(extraction.plan(bindings,cat,drill,100,false).entries.is_empty(),"Failed drill granted cargo")
	for count in [4,5,6,7]:
		drill=new_drill(count)
		for layer in count:
			for i in 60:steer(drill,Vector2(640,360),100)
			check(drill.snapshot().layer_index==layer and drill.snapshot().layer_elapsed_ms==6000,"Ring advanced at 6000 ms")
			steer(drill,Vector2(640,360),1)
			check(drill.snapshot().layer_index==layer+1 and drill.snapshot().layer_elapsed_ms==0,"Ring did not advance at 6001 ms or retained overshoot")
		var result:=drill.snapshot();var expected: Array=[23.746824264526367,34.72010040283203,47.7078742980957,62.71037292480469]
		check(result.phase=="extracted" and result.all_layers and result.core==(count==7) and result.ore_progress==expected[count-4],"Layer extraction disagrees with independently calculated ore totals")
		var full:=extraction.plan(bindings,cat,drill,100,false)
		check(full.ore_tons==int(expected[count-4]) and full.cargo_added==int(expected[count-4])+(1 if count==7 else 0),"Extracted cargo amount changed")
		check(extraction.plan(bindings,cat,drill,100,true).entries==full.entries,"Hard difficulty halved a fully extracted asteroid")
		check(extraction.plan(bindings,cat,drill,0,false).entries.is_empty(),"Full hold accepted ore")
		var one:=extraction.plan(bindings,cat,drill,1,false)
		check(one.cargo_added==1 and one.free_space_after==0 and one.ore_tons==(0 if count==7 else 1),"Core did not receive the last cargo space first")
		if count==7:check(one.entries==[{"item_id":result.item_id+11,"quantity":1}] and full.entries.front()==one.entries.front(),"Ordinary core mapping or extraction order changed")
		check(not extraction.plan(bindings,cat,drill,-1,false) and not extraction.plan(bindings,cat,drill,1.5,false),"Invalid cargo capacity was accepted")
	var special:=field.duplicate(true);special.objects[by_size[7]].item_id=217
	drill=Drill.new();check(drill.configure(bindings,cat,[90,81],special,by_size[7],Vector2(640,360)),drill.error)
	for i in 427:steer(drill,Vector2(640,360),100)
	check(extraction.plan(bindings,cat,drill,1,false).entries==[{"item_id":218,"quantity":1}],"Special ore did not use its explicitly declared core")
	# Manual termination returns integer partial ore. The difficulty deduction
	# is applied before the free-space clamp and only to partial extraction.
	drill=new_drill(7)
	for i in 70:steer(drill,Vector2(640,360),100)
	check(extraction.plan(bindings,cat,drill,100,false).is_empty(),"Running drill produced an extraction plan")
	check(drill.stop(),drill.error)
	var stopped:=drill.snapshot();check(stopped.ore_tons==3 and not stopped.core,"Manual stop changed partial ore")
	check(extraction.plan(bindings,cat,drill,100,false).ore_tons==3 and extraction.plan(bindings,cat,drill,100,true).ore_tons==1,"Hard partial extraction did not truncate half the integer ore")
	check(extraction.plan(bindings,cat,drill,2,true).ore_tons==1,"Cargo was clamped before partial-difficulty deduction")
	check(not drill.stop() and drill.snapshot()==stopped,"Repeated manual stop changed the result")
	copy.clear();check(copy.snapshot().is_empty() and drill.snapshot()==stopped,"Clearing another drill changed this result")

func new_drill(count: int) -> RefCounted:
	var drill:=Drill.new();check(drill.configure(bindings,cat,[90,81],field,by_size[count],Vector2(640,360)),drill.error)
	return drill

func steer(drill: RefCounted, point: Vector2, dt: int):
	var state: Dictionary=drill.snapshot()
	var desired: Vector2=(point-state.point)*20.0/float(dt)-state.drift
	var command:=Vector2.ZERO
	for axis in 2:command[axis]=signf(desired[axis])*sqrt(minf(1.0,absf(desired[axis])/3.0))
	if not drill.set_command(command):check(false,drill.error);return
	if not drill.advance(dt,random if state.random_state.is_empty() else state.random_state):check(false,drill.error)

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)

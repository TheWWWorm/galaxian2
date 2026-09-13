extends SceneTree
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Weapons = preload("res://src/simulation/weapon_loadout.gd")
var failures := 0

func _initialize() -> void:
	check_timing_and_pool()
	check_expiration_and_rounding()
	check_failures()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("Ordinary projectile checks: %d failures" % failures)
	quit(1 if failures else 0)

func weapon() -> Dictionary:
	return {"base_content_id":"a".repeat(64),"binding_id":"b".repeat(64),"item_id":2,
		"category":0,"kind":0,"damage":6,"interval_ms":380,"lifetime_ms":2000,
		"speed_units_per_millisecond":20.0,"launch_mode":"ordinary"}

func check_timing_and_pool() -> void:
	var simulation := Projectiles.new()
	var definition := weapon()
	definition.projectile_capacity=2
	check(simulation.configure(definition) and simulation.snapshot().slots.size()==2,"Bound capacity was not selected")
	check(not simulation.configure(definition,1) and simulation.snapshot().is_empty(),"Explicit capacity overrode source capacity")
	check(not simulation.configure(definition,2.0),"Fractional-type explicit capacity accepted")
	check(simulation.configure(definition,2),simulation.error)
	definition.damage=999
	check(simulation.snapshot().weapon.damage==6,"Configuration aliases caller data")
	check(simulation.snapshot().elapsed_ms==380 and not simulation.snapshot().time_ready,"New weapon did not start at its exact interval")
	check(simulation.fire(Vector3.ZERO,Vector3.FORWARD,true).get("reason")=="interval","Initial equality fired")
	check(not simulation.advance(1).is_empty(),simulation.error)
	var before := simulation.snapshot()
	check(simulation.fire(Vector3.ZERO,Vector3.FORWARD,false).get("reason")=="permission","Permission gate ignored")
	check(simulation.snapshot()==before,"Denied shot changed state")
	var first: Dictionary = simulation.fire(Vector3(10,20,30),Vector3(3,4,0),true)
	check(first.get("fired",false),simulation.error)
	if not first.get("fired",false): return
	var id: int = first.projectile.id
	check(first.projectile.slot==0 and first.projectile.velocity==Vector3(12,16,0),"First slot or normalized launch speed changed")
	first.projectile.position=Vector3.ONE
	check(simulation.snapshot().slots[0].position==Vector3(10,20,30),"Shot result aliases simulation")
	check(simulation.fire(Vector3.ZERO,Vector3.FORWARD,true).get("reason")=="interval","Repeated request fired without time")
	check(not simulation.advance(380).is_empty(),simulation.error)
	check(simulation.fire(Vector3.ZERO,Vector3.FORWARD,true).get("reason")=="interval","Exact interval fired")
	check(not simulation.advance(1).is_empty(),simulation.error)
	var second: Dictionary = simulation.fire(Vector3.ZERO,Vector3.FORWARD,true)
	check(second.get("fired",false) and second.get("projectile",{}).get("slot")==1,"Second projectile did not use next free slot")
	check(not simulation.advance(381).is_empty(),simulation.error)
	before=simulation.snapshot()
	check(simulation.fire(Vector3.ZERO,Vector3.FORWARD,true).get("reason")=="capacity","Full pool accepted a shot")
	check(simulation.snapshot()==before,"Full pool reset clock or changed a projectile")
	check(simulation.retire(id),simulation.error)
	check(not simulation.retire(id),"Repeated retirement accepted")
	var third: Dictionary = simulation.fire(Vector3.ZERO,Vector3.RIGHT,true)
	check(third.get("fired",false) and third.projectile.slot==0 and third.projectile.id!=id,"Free slot was not reused with a fresh handle")
	check(simulation.snapshot().elapsed_ms==0,"Successful shot did not reset interval")
	var old_id: int = third.projectile.id
	check(simulation.configure(weapon(),1),simulation.error)
	simulation.advance(1)
	var replacement: Dictionary = simulation.fire(Vector3.ZERO,Vector3.RIGHT,true)
	check(replacement.projectile.id!=old_id and not simulation.retire(old_id),"Content replacement reused a stale handle")

func check_expiration_and_rounding() -> void:
	var simulation := Projectiles.new()
	check(simulation.configure(weapon(),1),simulation.error)
	simulation.advance(1)
	var launch: Dictionary = simulation.fire(Vector3.ZERO,Vector3.RIGHT,true)
	var first: Dictionary = simulation.advance(1999)
	check(first.moved[0].position==Vector3(39980,0,0) and first.moved[0].remaining_ms==1,"Incorrect pre-expiration travel")
	var last: Dictionary = simulation.advance(5)
	check(last.moved[0].previous_position==Vector3(39980,0,0) and last.moved[0].position==Vector3(40080,0,0),"Final movement was clamped to remaining lifetime")
	check(last.expired==[launch.projectile.id] and last.moved[0].remaining_ms==-4,"Final step did not expire once")
	var before := simulation.snapshot()
	var cleanup: Dictionary = simulation.advance(0)
	check(simulation.snapshot().elapsed_ms==before.elapsed_ms,"Zero-time cleanup advanced the firing clock")
	check(simulation.snapshot().available_slots==1,"Expired slot is not reusable")
	check(cleanup.cleared==[launch.projectile.id] and cleanup.moved.is_empty() and cleanup.expired.is_empty(),"Expired projectile advanced or expired twice")
	check(simulation.snapshot().slots==[null],"Expired slot retained after cleanup")
	check(simulation.fire(Vector3.ZERO,Vector3.RIGHT,true).get("fired",false),simulation.error)
	var exact: Dictionary = simulation.advance(2000)
	check(exact.moved[0].remaining_ms==0 and exact.moved[0].position==Vector3(40000,0,0),"Exact lifetime expiration changed")
	var reused: Dictionary = simulation.fire(Vector3.ZERO,Vector3.RIGHT,true)
	check(reused.get("fired",false) and reused.projectile.slot==0 and reused.projectile.id!=exact.moved[0].id,"Expired slot not immediately reusable")
	var definition := weapon()
	definition.speed_units_per_millisecond=1.0
	check(simulation.configure(definition,1),simulation.error)
	simulation.advance(1)
	simulation.fire(Vector3(16777216,0,0),Vector3.RIGHT,true)
	check(simulation.advance(1).moved[0].position.x==16777216.0,"Binary32 position rounding lost")
	check(simulation.advance(3).moved[0].position.x==16777220.0,"Binary32 tie rounding changed")
	check(simulation.configure(definition,1),simulation.error)
	simulation.advance(1)
	check(simulation.fire(Vector3.ZERO,Vector3.ZERO,true).projectile.velocity==Vector3.UP,"Zero launch vector did not use source positive-Y fallback")

func check_failures() -> void:
	var simulation := Projectiles.new()
	check(simulation.advance(1).is_empty() and simulation.fire(Vector3.ZERO,Vector3.RIGHT,true).is_empty(),"Unconfigured simulation accepted work")
	for capacity in [0,-1,true,1.0,4097]:
		check(not simulation.configure(weapon(),capacity) and simulation.snapshot().is_empty(),"Invalid capacity accepted")
	for field in ["item_id","kind","category","damage","interval_ms","lifetime_ms","speed_units_per_millisecond","binding_id","base_content_id"]:
		var bad := weapon()
		bad[field]=true
		check(not simulation.configure(bad,1) and simulation.snapshot().is_empty(),"Invalid weapon value accepted: "+field)
	for values in [["kind",2],["category",1],["interval_ms",0],["lifetime_ms",0],["speed_units_per_millisecond",INF],["launch_mode","alternate"],["launch_mode","unsupported"],["launch_mode",null]]:
		var bad := weapon()
		bad[values[0]]=values[1]
		check(not simulation.configure(bad,1),"Unsupported weapon kind/value accepted")
	check(simulation.configure(weapon(),1),simulation.error)
	simulation.advance(1)
	var before := simulation.snapshot()
	for time in [-1,1.5,true,null,"1",2147483647]:
		check(simulation.advance(time).is_empty() and simulation.snapshot()==before,"Invalid time changed state")
	for invalid in [null,Vector3(INF,0,0),Vector3(0,NAN,0),[0,0,0]]:
		check(simulation.fire(invalid,Vector3.RIGHT,true).is_empty() and simulation.snapshot()==before,"Invalid muzzle changed state")
		check(simulation.fire(Vector3.ZERO,invalid,true).is_empty() and simulation.snapshot()==before,"Invalid aim changed state")
	check(simulation.fire(Vector3.ZERO,Vector3.RIGHT,1).is_empty() and simulation.snapshot()==before,"Implicit permission accepted")
	# Two-projectile update must roll back the earlier valid motion if the second overflows.
	var huge := weapon()
	huge.speed_units_per_millisecond=1.0e38
	huge.interval_ms=1
	check(simulation.configure(huge,2),simulation.error)
	simulation.advance(1)
	before=simulation.snapshot()
	check(simulation.fire(Vector3.ZERO,Vector3(1.0e30,0,0),true).is_empty() and simulation.snapshot()==before,"Overflowing launch normalization changed state")
	check(simulation.fire(Vector3(2.0e38,0,0),Vector3.LEFT,true).get("fired",false),simulation.error)
	check(not simulation.advance(2).is_empty(),simulation.error)
	check(simulation.fire(Vector3(2.0e38,0,0),Vector3.RIGHT,true).get("fired",false),simulation.error)
	before=simulation.snapshot()
	check(simulation.advance(2).is_empty() and simulation.snapshot()==before,"Overflow partially advanced a projectile pool")
	check(not simulation.configure({},1) and simulation.snapshot().is_empty(),"Failed reconfiguration retained live projectiles")
	simulation.clear()
	check(simulation.snapshot().is_empty() and not simulation.retire(1),"Clear retained a projectile")

func check_profile(content: String, path: String) -> void:
	var library := Library.new()
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	var resolver := Weapons.new()
	if not library.open(content) or not bindings.open(path,library.manifest) or not catalogues.open(library) or not resolver.configure(bindings,catalogues,library.manifest.content_id):
		check(false,library.error+bindings.error+catalogues.error+resolver.error)
		return
	var definition: Dictionary = resolver.resolve(2,[])
	var simulation := Projectiles.new()
	if definition.has("projectile_capacity"):
		check(definition.projectile_capacity==20,"Original ordinary capacity changed")
		check(not simulation.configure(definition,2),"Source pool size silently overridden")
		check(simulation.configure(definition) and simulation.snapshot().slots.size()==20,simulation.error)
	else:
		check(not simulation.configure(definition),"Legacy pack inferred a capacity")
		check(simulation.configure(definition,2),simulation.error)
	simulation.advance(1)
	check(simulation.fire(Vector3.ZERO,Vector3.FORWARD,true).get("fired",false),simulation.error)
	check(simulation.advance(25).moved[0].position==Vector3(0,0,-500),"Original weapon speed/time mapping changed")
	check(simulation.snapshot().weapon.base_content_id==library.manifest.content_id and simulation.snapshot().weapon.binding_id==bindings.binding_id,"Projectile lost content identity")
	print(library.manifest.profile.edition,": original primary parameters drive native projectile flight")
	for id in [9,10,11,228]:
		var alternate: Dictionary = resolver.resolve(id,[])
		check(alternate.get("launch_mode")=="alternate" and not simulation.configure(alternate,1),"Alternate type-zero item accepted as an ordinary projectile")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)

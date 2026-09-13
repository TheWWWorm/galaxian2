extends SceneTree
const Generator = preload("res://src/simulation/seeded_random.gd")
var failures := 0

func _initialize() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/seeded_random_vectors.json"))
	var generator := Generator.new()
	check(generator.next_int(2)==-1 and generator.next_bits(1)==-1,"Unseeded generator accepted draws")
	var rejections := 0
	for row in rows:
		check(generator.seed_from(int(row.seed)),generator.error)
		for index in row.values.size():
			check(generator.next_int(int(row.bound))==int(row.values[index]),"Random value differs from independent integer oracle")
			check(generator.snapshot().state==int(row.states[index]),"Random state differs from independent integer oracle")
			if row.draws[index]>1: rejections+=1
	check(rejections>0,"Vectors never exercise modulo rejection")
	var state := generator.snapshot()
	for value in [-1,0,2147483648,2.0,"2",null]:
		check(generator.next_int(value)==-1 and generator.snapshot()==state,"Invalid bound advanced the generator")
	for value in [-1,0,33,1.0,"1",null]:
		check(generator.next_bits(value)==-1 and generator.snapshot()==state,"Invalid bit count advanced the generator")
	check(not generator.seed_from(1.0) and generator.snapshot()==state,"Invalid seed discarded the current state")
	for value in [null,{}, {"state":-1},{"state":281474976710656},{"state":1.0}]:
		check(not generator.restore(value) and generator.snapshot()==state,"Invalid restore discarded the current state")
	check(generator.seed_from(0),generator.error)
	check(generator.next_bits(32)==3139482720,"32-bit draws truncated the unsigned high bit")
	check(generator.next_bits(1)==1,"Single-bit draw mismatch")
	var copy := generator.fork()
	var saved := generator.snapshot()
	var value := generator.next_int(65536)
	check(copy.snapshot()==saved and copy.next_int(65536)==value,"Fork changed state or sequence")
	check(generator.restore(saved) and generator.next_int(65536)==value,"Restore did not reproduce the next draw")
	check(generator.restore({"state":281474976710655}) and generator.next_bits(32)==4294582547,"Maximum-state recurrence overflowed")
	generator.clear()
	check(generator.snapshot().is_empty() and generator.next_int(2)==-1,"Clear retained usable random state")
	print("Seeded random: %d independent vectors and %d rejection draws verified" % [rows.size(),rejections])
	quit(0 if failures==0 else 1)

func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)

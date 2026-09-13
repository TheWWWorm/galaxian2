extends SceneTree
const Rotation = preload("res://src/presentation/scenery_animation_rotation.gd")
const Keys = preload("res://src/content/scenery_animation_keys.gd")
const AEM = preload("res://src/content/aem.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
var failures := 0

func _initialize() -> void:
	check_math()
	check_invalid()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1])
	print("Scenery animation rotation checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_math() -> void:
	var cases: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenery_animation_rotation_vectors.json"))
	check(cases is Dictionary and cases.get("angles",[]).size()==8,"Missing independent rotation vectors")
	if not cases is Dictionary:return
	for row in cases.angles:
		var angles := Vector3(row.angles[0],row.angles[1],row.angles[2])
		var result := Rotation.sample(angles,angles,0.5)
		check(not result.has("error"),str(result))
		if result.has("error"):continue
		for axis in 3:
			for component in 3:
				check(abs(result.basis[axis][component]-row.columns[axis][component])<0.000002,"Analytical Euler composition changed: "+row.name)
	for row in cases.matrices:
		var result := Rotation.to_basis(PackedFloat32Array(row.components))
		check(not result.has("error"),str(result))
		if result.has("error"):continue
		for axis in 3:
			for component in 3:
				check(bits(result.basis[axis][component])==int(row.column_bits[axis][component]),"Quaternion matrix arithmetic changed")
	for row in cases.blends:
		var a := PackedFloat32Array(row.left);var b := PackedFloat32Array(row.right)
		var before_a := a.duplicate();var before_b := b.duplicate()
		var result := Rotation.blend(a,b,row.weight)
		check(a==before_a and b==before_b,"Rotation blending changed its endpoints")
		if row.component_bits==null:check(result.is_empty(),"Singular quaternion blend produced a rotation")
		else:
			check(result.size()==4,"Missing blended quaternion")
			for field in result.size():check(bits(result[field])==int(row.component_bits[field]),"Unflipped normalized rotation blend changed")
	check(bits(Rotation.from_angles(Vector3.ZERO)[1])==0x80000000,"Euler conversion lost the source Y zero sign")
	var left := Vector3(0.2,-0.8,0.4);var right := Vector3(2.1,1.3,-2.2)
	var blended: Basis=Rotation.sample(left,right,0.25).basis
	var euler: Basis=Rotation.sample(left.lerp(right,0.25),left.lerp(right,0.25),0.0).basis
	check(not blended.is_equal_approx(euler),"Rotation sampling became direct Euler interpolation")

func check_invalid() -> void:
	for invalid in [null,true,"0.5",-0.1,1.1,NAN,INF]:
		check(Rotation.sample(Vector3.ZERO,Vector3.ZERO,invalid).has("error"),"Invalid rotation weight accepted")
		check(Rotation.blend(PackedFloat32Array([0,0,0,1]),PackedFloat32Array([0,0,0,1]),invalid).is_empty(),"Invalid quaternion blend weight accepted")
	for invalid in [Vector3(INF,0,0),Vector3(0,NAN,0)]:
		check(Rotation.from_angles(invalid).is_empty(),"Nonfinite angles accepted")
		check(Rotation.sample(invalid,Vector3.ZERO,0.5).has("error") and Rotation.sample(Vector3.ZERO,invalid,0.5).has("error"),"Nonfinite endpoint sampled")
	for invalid in [[],[1,2,3],[1,2,3,4,5],[0,0,0,0],[NAN,0,0,1],[0,INF,0,1],[1e30,0,0,0],[1e-30,0,0,0]]:
		var q := PackedFloat32Array(invalid)
		check(Rotation.to_basis(q).has("error"),"Malformed, overflowing or singular matrix accepted")
		check(Rotation.blend(q,q,0.5).is_empty(),"Malformed, overflowing or singular blend accepted")
	check(not Rotation.sample(Vector3.ZERO,Vector3.ZERO,0).has("error"),"Failure contaminated later sampling")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	var identifiers := {}
	for variant in bindings.scenery_effects.variants:
		for model in variant.model_ids:identifiers[int(model)]=true
	check(identifiers.size()==7,"Expected all seven distinct effect resources")
	var report := {};var count := 0
	for identifier in identifiers:
		var reader := AEM.new()
		var decoded := reader.decode(library.read_resource(bindings.resolve(identifier,"mesh"),AEM.MAX_BYTES))
		if decoded.is_empty():check(false,reader.error);continue
		var compiler := Keys.new();var prepared := compiler.prepare(decoded.surfaces)
		if prepared.is_empty():check(false,compiler.error);continue
		var surfaces := []
		for table in prepared.surfaces:
			var frames := []
			for index in range(1,table.times.size()):
				var left := angles_at(table.values,index-1);var right := angles_at(table.values,index)
				for weight in [0.0,0.25,0.5,0.75,1.0]:
					var result := Rotation.sample(left,right,weight)
					check(not result.has("error"),"Rejected supported effect rotation: "+str(identifier)+" "+str(result))
					if result.has("error"):continue
					var basis: Basis=result.basis
					check(abs(basis.determinant()-1.0)<0.00002 and basis.transposed().is_equal_approx(basis.inverse()),"Effect rotation is not orthonormal")
					var frame := []
					for value in result.components:frame.append(bits(value))
					for axis in 3:
						for component in 3:frame.append(bits(basis[axis][component]))
					frames.append(frame);count+=1
			surfaces.append(frames)
		report[str(identifier)]=surfaces
	var destination := OS.get_environment("GOF2_ROTATION_REPORT_DIR")
	if not destination.is_empty():
		var file := FileAccess.open(destination.path_join(library.manifest.profile.edition+"-native-rotations.json"),FileAccess.WRITE)
		check(file!=null,"Cannot write native rotation report")
		if file!=null:file.store_string(JSON.stringify(report)+"\n")
	print(library.manifest.profile.edition,": ",count," effect rotations sampled")

func angles_at(values: PackedFloat32Array, index: int) -> Vector3:
	var start := index*Keys.WIDTH+3
	return Vector3(values[start],values[start+1],values[start+2])

func bits(value: float) -> int:
	return PackedFloat32Array([value]).to_byte_array().decode_u32(0)

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)

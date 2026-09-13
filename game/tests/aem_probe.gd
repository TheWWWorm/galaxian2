extends SceneTree
const AEM = preload("res://src/content/aem.gd")

func _initialize() -> void:
	var report := {}
	for directory in OS.get_cmdline_user_args():
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
		var errors: Array = []
		var counts := {"accepted": 0, "vertices": 0, "submeshes": 0, "keyframes": 0}
		var parser := AEM.new()
		for path in manifest.files:
			if not path.ends_with(".aem"):
				continue
			var result := parser.decode(FileAccess.get_file_as_bytes(directory.path_join(path)))
			if result.is_empty():
				errors.append({"path": path, "error": parser.error})
			else:
				counts.accepted += 1
				counts.vertices += result.vertices
				counts.submeshes += result.surfaces.size()
				counts.keyframes += result.keyframes
		report[manifest.profile.edition] = {"counts": counts, "errors": errors}
	print(JSON.stringify(report, "  "))
	quit()

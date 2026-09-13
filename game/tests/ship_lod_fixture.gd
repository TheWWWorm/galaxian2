extends RefCounted

static func definition() -> Dictionary:
	var bodies := []; var children := []
	for i in 61:
		bodies.append([18,18]);children.append([18,18])
	var sizes := {"body":57,"fill":74,"step":66,"child":51,"child_copy":64,"limit":13,"select":122,"cull":44,"square":19,"detail":68,"detail_low":4,"detail_high":4,"detail_first":4,"detail_pair":8,"limit_setter":17,"body_table":732,"child_table":732}
	var provenance := {}; var offset := 1000
	for key in sizes:
		provenance[key]={"offset":offset,"bytes":sizes[key]}
		offset+=sizes[key]+16
	return {"body_resource_ids":bodies,"child_resource_ids":children,"distances":[300,800],"maximum_distance":2000,"detail_boundaries":[0.2,0.8],"squared_distance_factors":[0.25,0.6,1.0],"threshold_comparison":"greater","maximum_comparison":"greater_or_equal","provenance":provenance}

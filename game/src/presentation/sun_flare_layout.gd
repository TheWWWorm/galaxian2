extends RefCounted
## Original ordinary screen composition, expressed as seven centered sprites.
const Frame=preload("res://src/presentation/opening_sun_frame.gd")

static func compose(screen: Vector2,depth: float,viewport_size: Vector2i,color_type: int,image_sizes: Array) -> Dictionary:
	if image_sizes.size()!=3:return {"error":"Sun flares require three original image sizes"}
	for extent in image_sizes:
		if not extent is Vector2i or extent.x<1 or extent.y<1 or extent.x>8192 or extent.y>8192:return {"error":"Invalid flare image size"}
	var result:=Frame.intensity_at(screen,depth,viewport_size,color_type)
	if result.has("error"):return result
	var intensity: float=result.intensity
	if depth>=0 or screen.x<=-viewport_size.x or screen.x>=2*viewport_size.x or screen.y<=-viewport_size.y or screen.y>=2*viewport_size.y:
		return {"sprites":[],"intensity":0.0,"wash_alpha":0}
	var center:=Vector2(viewport_size.x>>1,viewport_size.y>>1)
	var offset:=center-screen
	var distance:=Frame.single(sqrt(Frame.single(Frame.single(offset.x*offset.x)+Frame.single(offset.y*offset.y))))
	# Preserve the source's fixed-point direction normalization and conversion;
	# cancelling the distance algebraically changes integer sprite positions.
	var direction:=Vector2(-Frame.single(offset.x*65536.0),-Frame.single(offset.y*65536.0))
	if distance>0:direction=Vector2(Frame.single(direction.x/distance),Frame.single(direction.y/distance))
	direction=Vector2(Frame.single(direction.x*distance),Frame.single(direction.y*distance))
	var common_alpha:=int(Frame.single(120.0-Frame.single(50.0-intensity)))&255
	var rows:=[
		{"image":0,"factor":0.5,"scale":1.0,"natural":true},
		{"image":0,"factor":0.25,"scale":0.75},
		{"image":1,"factor":0.75,"scale":0.5},
		{"image":0,"factor":0.125,"scale":1.25,"threshold":true},
		{"image":1,"divisor":11.0,"scale":0.5},
		{"image":2,"factor":0.75,"scale":2.0,"opposite":true},
		{"image":2,"factor":Frame.single(0.2),"scale":0.5,"opposite":true}]
	var sprites:=[]
	for row in rows:
		if row.has("threshold") and Frame.single(50.0-intensity)>=90.0:continue
		var along:=Vector2.ZERO
		for axis in 2:
			var scaled:=Frame.single(direction[axis]/row.divisor) if row.has("divisor") else Frame.single(direction[axis]*row.factor)
			along[axis]=Frame.single(scaled/65536.0)
		var anchor:=Vector2i(center-along if row.has("opposite") else center+along)
		var original: Vector2i=image_sizes[row.image]
		var width:=int(Frame.single(original.x*row.scale))
		var extent:=original if row.get("natural",false) else Vector2i(width,width)
		var alpha: int=(int(Frame.single(90.0-Frame.single(50.0-intensity)))&255) if row.has("threshold") else common_alpha
		sprites.append({"image_index":row.image,"rect":Rect2i(anchor-Vector2i(extent.x>>1,extent.y>>1),extent),"alpha_byte":alpha})
	return {"sprites":sprites,"intensity":intensity,"wash_alpha":int(intensity) if intensity>0 else 0}

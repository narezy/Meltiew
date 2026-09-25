class_name SValue
extends RefCounted
## Property values as they travel in place files and over the network (tagged JSON)
## and as Godot uses them:
##   {"$v3": [x,y,z]} <-> Vector3      {"$v2": [x,y]} <-> Vector2
##   {"$c3": "#rrggbb"} <-> Color       {"$u2": [xs,xo,ys,yo]} <-> UDim2 (PackedFloat32Array, 4)
##   {"$u": [s,o]} <-> PackedFloat32Array (2)   {"$i": "id"} <-> Instance reference (kept as is)


static func decode(v: Variant) -> Variant:
	if v is Dictionary:
		if v.has("$v3"):
			var a: Array = v["$v3"]
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
		if v.has("$v2"):
			var a: Array = v["$v2"]
			return Vector2(float(a[0]), float(a[1]))
		if v.has("$c3"):
			var c: Variant = v["$c3"]
			if c is Array:
				return Color(float(c[0]), float(c[1]), float(c[2]))
			return Color(str(c))
		if v.has("$u2"):
			var a: Array = v["$u2"]
			return PackedFloat32Array([float(a[0]), float(a[1]), float(a[2]), float(a[3])])
		if v.has("$u"):
			var a: Array = v["$u"]
			return PackedFloat32Array([float(a[0]), float(a[1])])
	return v


static func encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR3:
			return {"$v3": [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]}
		TYPE_VECTOR2:
			return {"$v2": [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001)]}
		TYPE_COLOR:
			return {"$c3": "#" + v.to_html(false)}
		TYPE_PACKED_FLOAT32_ARRAY:
			if v.size() == 4:
				return {"$u2": [v[0], v[1], v[2], v[3]]}
			return {"$u": [v[0], v[1]]}
	return v


static func udim2(xs: float, xo: float, ys: float, yo: float) -> PackedFloat32Array:
	return PackedFloat32Array([xs, xo, ys, yo])


## Human-readable value for Studio's Properties panel and the output.
static func describe(v: Variant) -> String:
	match typeof(v):
		TYPE_VECTOR3:
			return "%s, %s, %s" % [_n(v.x), _n(v.y), _n(v.z)]
		TYPE_VECTOR2:
			return "%s, %s" % [_n(v.x), _n(v.y)]
		TYPE_COLOR:
			return "#" + v.to_html(false)
		TYPE_PACKED_FLOAT32_ARRAY:
			if v.size() == 4:
				return "{%s, %s}, {%s, %s}" % [_n(v[0]), _n(v[1]), _n(v[2]), _n(v[3])]
		TYPE_FLOAT:
			return _n(v)
	return str(v)


static func _n(x: float) -> String:
	var s := str(snappedf(x, 0.001))
	return s.trim_suffix(".0")

shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;

// A white rounded speech bubble with a small tail at the bottom middle, always
// facing the camera. `size` is the whole quad in metres (bubble + tail).
uniform vec2 size = vec2(1.0, 0.5);
uniform float radius = 0.12;
uniform float tail = 0.1;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.97);
// The scene's tonemapper greys out plain white; this pushes it back to paper white.
uniform float brightness = 1.45;

void vertex() {
	// Billboard around the node's origin (the tip of the tail).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	// UV (0,0) top-left; work in metres with y going up.
	vec2 p = vec2(UV.x * size.x, (1.0 - UV.y) * size.y);
	float body_h = size.y - tail;
	vec2 c = vec2(size.x * 0.5, tail + body_h * 0.5);
	float d = rounded_box(p - c, vec2(size.x, body_h) * 0.5, radius);
	// Tail: a triangle from the bubble's bottom edge down to the tip at (mid, 0).
	float w = tail * 0.9;
	float t = p.y / max(tail, 0.0001);
	float in_tail = step(abs(p.x - size.x * 0.5), w * t) * step(p.y, tail + 0.01);
	float aa = fwidth(d);
	float a = max(1.0 - smoothstep(-aa, aa, d), in_tail);
	ALBEDO = color.rgb * brightness;
	ALPHA = a * color.a;
}

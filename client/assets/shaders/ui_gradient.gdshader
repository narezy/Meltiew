shader_type canvas_item;
// UIGradient: tints a place's GUI element from c0 to c1 across it, at `angle` radians.

uniform vec4 c0 : source_color = vec4(1.0);
uniform vec4 c1 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float angle = 0.0;
uniform vec2 box = vec2(100.0);
varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 p = local / max(box, vec2(1.0)) - 0.5;
	float t = clamp(dot(p, vec2(cos(angle), sin(angle))) + 0.5, 0.0, 1.0);
	COLOR *= mix(c0, c1, t);
}

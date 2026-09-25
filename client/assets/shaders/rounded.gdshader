shader_type canvas_item;
// Rounds the corners of a TextureRect. radius is in pixels of the control.
uniform float radius = 22.0;
uniform vec2 rect_size = vec2(100.0, 100.0);

void fragment() {
	vec2 p = UV * rect_size;
	vec2 q = abs(p - rect_size * 0.5) - (rect_size * 0.5 - vec2(radius));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	vec4 c = texture(TEXTURE, UV);
	c.a *= clamp(0.5 - d, 0.0, 1.0);
	COLOR = c;
}

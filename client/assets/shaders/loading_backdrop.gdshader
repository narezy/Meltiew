shader_type canvas_item;
// The place's cover behind the loading screen: soft (a blurry mipmap level), darkened toward
// the edges so the icon and the text in the middle stand out.
uniform float blur = 5.5;

void fragment() {
	vec3 c = textureLod(TEXTURE, UV, blur).rgb;
	float v = smoothstep(0.95, 0.15, length((UV - 0.5) * vec2(1.0, 0.8)));
	COLOR = vec4(c * (0.28 + 0.37 * v), 1.0);
}

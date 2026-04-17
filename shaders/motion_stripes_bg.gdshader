shader_type canvas_item;

uniform vec4 color_a : source_color = vec4(0.06, 0.07, 0.11, 1.0);
uniform vec4 color_b : source_color = vec4(0.11, 0.13, 0.19, 1.0);
uniform float scroll_speed : hint_range(0.0, 1.5) = 0.24;
uniform float stripe_scale : hint_range(6.0, 40.0) = 18.0;
uniform float angle : hint_range(0.0, 1.57) = 0.52;

void fragment() {
	vec2 uv = UV;
	float c = cos(angle);
	float s = sin(angle);
	vec2 p = vec2(c * uv.x - s * uv.y, s * uv.x + c * uv.y);
	float t = (p.x + p.y * 0.65) * stripe_scale + TIME * scroll_speed;
	float f = fract(t);
	float band = smoothstep(0.38, 0.5, f) * (1.0 - smoothstep(0.5, 0.62, f));
	vec3 col = mix(color_a.rgb, color_b.rgb, band);
	COLOR = vec4(col, 1.0);
}

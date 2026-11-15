// Multiply pass over the ship: the side away from the Sun is darker, everything dims as the
// Sun gets farther (1/r^2), a vignette, and red emergency lighting when the battery is low.
shader_type canvas_item;
render_mode blend_mul;

uniform vec2 sun_dir = vec2(-1.0, 0.0);   // screen direction towards the Sun (normalised)
uniform float sun_power = 1.0;            // 1 at Earth (1 AU), ~0.43 at Mars (1.52 AU)
uniform vec3 ambient = vec3(1.0);         // colour grade
uniform float emergency = 0.0;            // 0..1 red emergency lights
uniform float time = 0.0;
uniform float blackout = 0.0;             // solar bus tripped: the ship goes dark

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	vec2 c = (world - vec2(240.0, 135.0)) / vec2(240.0, 135.0);
	float side = dot(c * vec2(1.0, 0.56), sun_dir);         // -1 far side .. +1 sun side
	float lit = smoothstep(-1.1, 0.9, side);
	vec3 col = ambient * mix(1.0 - 0.32 * sun_power, 1.0, lit);
	col *= mix(0.72, 1.0, sun_power);                         // weaker sunlight far from the Sun
	float v = length(c * vec2(1.0, 0.9));
	col *= 1.0 - 0.38 * pow(clamp(v * 0.8, 0.0, 1.0), 2.6);  // vignette
	col *= mix(1.0, 0.38, blackout);
	float pulse = 0.75 + 0.25 * sin(time * 4.0);
	col = mix(col, col * vec3(1.0, 0.38, 0.32) * pulse, emergency);
	COLOR = vec4(col, 1.0);
}

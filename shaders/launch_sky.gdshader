// Launch sky, drawn 1:1 into the launch world's 496x286 pixel viewport: a banded gradient with
// 4x4 Bayer dithering between bands (pixel-art style), a pixel Sun with stepped halo rings,
// horizon haze, and twinkling stars once the air thins out.
shader_type canvas_item;

uniform vec3 top_col = vec3(0.24, 0.5, 0.82);
uniform vec3 bottom_col = vec3(0.55, 0.77, 1.0);
uniform vec3 haze_col = vec3(1.0, 0.86, 0.7);
uniform float haze = 1.0;          // warm horizon glow, fades with altitude
uniform float horizon_y = 244.0;   // where the haze sits (pixels)
uniform float stars = 0.0;         // 0..1 star visibility
uniform vec2 sun_pos = vec2(78.0, 54.0);
uniform float sun_power = 1.0;
uniform float time = 0.0;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[x + y * 4]) + 0.5) / 16.0;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = floor(world);
	float b = bayer4(p);
	float t = clamp(p.y / 286.0, 0.0, 1.0);
	float tq = floor(t * 8.0 + b) / 8.0;                       // 8 dithered bands
	vec3 col = mix(top_col, bottom_col, tq);

	float h = exp(-max(horizon_y - p.y, 0.0) / 34.0) * haze;  // haze near the horizon
	col = mix(col, haze_col, floor(h * 5.0 + b) / 5.0 * 0.45);

	float d = length(p - sun_pos);
	float halo = sun_power * exp(-d / 48.0);
	col += vec3(1.0, 0.88, 0.62) * floor(halo * 4.0 + b) / 4.0 * 0.35;
	if (d < 9.0) {
		col = mix(col, vec3(1.0, 0.93, 0.7), sun_power * 0.8);
	}
	if (d < 6.0) {
		col = mix(col, vec3(1.0, 0.99, 0.92), sun_power);
	}

	float s = hash(p);
	if (s > 0.9965 && stars > 0.0) {
		float tw = 0.55 + 0.45 * sin(time * 2.2 + s * 900.0);
		col = mix(col, vec3(0.92, 0.95, 1.0), stars * tw);
	}
	COLOR = vec4(col, 1.0);
}

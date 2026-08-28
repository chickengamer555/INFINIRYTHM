shader_type canvas_item;

// Simple bullet glow shader - optimized for performance
// Creates a soft glow around bullet cores without borders

uniform float glow_intensity : hint_range(0.0, 3.0) = 1.2;
uniform float glow_radius : hint_range(1.0, 8.0) = 3.0;
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool use_original_color = true;

void fragment() {
	vec4 original_color = texture(TEXTURE, UV);
	
	// If pixel is transparent, create glow around it
	if (original_color.a < 0.1) {
		vec4 glow = vec4(0.0);
		float total_alpha = 0.0;
		
		// Simple 8-direction sampling for performance
		vec2 directions[8] = {
			vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
			vec2(0.707, 0.707), vec2(-0.707, 0.707), vec2(0.707, -0.707), vec2(-0.707, -0.707)
		};
		
		for (int i = 0; i < 8; i++) {
			vec2 offset = directions[i] * glow_radius * TEXTURE_PIXEL_SIZE;
			vec4 sample_color = texture(TEXTURE, UV + offset);
			
			if (sample_color.a > 0.1) {
				float distance_factor = 1.0 - (length(offset) / (glow_radius * length(TEXTURE_PIXEL_SIZE)));
				float alpha = sample_color.a * distance_factor * glow_intensity;
				
				if (use_original_color) {
					glow.rgb += sample_color.rgb * alpha;
				} else {
					glow.rgb += glow_color.rgb * alpha;
				}
				total_alpha += alpha;
			}
		}
		
		if (total_alpha > 0.0) {
			glow.rgb /= total_alpha;
			glow.a = min(total_alpha * 0.3, 0.8); // Soft glow alpha
			COLOR = glow;
		} else {
			COLOR = vec4(0.0);
		}
	} else {
		// Keep original pixel
		COLOR = original_color;
	}
}

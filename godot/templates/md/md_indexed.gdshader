shader_type canvas_item;
// Draw an index texture through a palette texture (16 x N, one row per
// 16-colour palette line, e.g. *.pal.png).
//
// Index textures store CRAM indices: 0-15 for single-line graphics (*.idx.png,
// the line is chosen with `palette_line`), or line*16 + colour for sprites
// whose pieces use several lines (0-63). Colour 0 of every line is
// transparent. Swapping the palette texture reproduces Mega Drive palette
// tricks such as team kits and fades without touching the graphics.

uniform sampler2D palette : filter_nearest;
uniform int palette_line = 0;
uniform bool index0_transparent = true;

void fragment() {
	int idx = int(round(texture(TEXTURE, UV).r * 255.0));
	if (index0_transparent && (idx & 15) == 0) {
		discard;
	}
	COLOR = texelFetch(palette, ivec2(idx & 15, palette_line + (idx >> 4)), 0);
}

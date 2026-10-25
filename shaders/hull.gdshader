shader_type spatial;
// Hull surface detail (see hull_common.gdshaderinc). One-sided: faces seen from behind aren't drawn, so a
// part's hidden faces can't flicker through the surface they sit against.
render_mode cull_back;

#include "res://shaders/hull_common.gdshaderinc"

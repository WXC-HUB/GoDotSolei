extends RefCounted

const SHADER := preload("res://shaders/motion_stripes_bg.gdshader")


static func attach(rect: ColorRect, scroll_speed: float = 0.24, stripe_scale: float = 18.0) -> void:
	if rect == null:
		return
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("scroll_speed", scroll_speed)
	m.set_shader_parameter("stripe_scale", stripe_scale)
	rect.material = m

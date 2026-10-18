class_name WorldNPC
extends StaticBody2D
## Человек в мире: метка, имя, зона взаимодействия. Ambient — декорация с репликой.

var npc_id := ""
var ambient := false
var ambient_line := ""


static func make_id(npc_id: String, emoji: String, dname: String) -> WorldNPC:
	var n := WorldNPC.new()
	n.npc_id = npc_id
	n.name = "NPC_" + npc_id
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	n.add_child(shape)
	var face := Tex.spr(Tex.char_for(npc_id), 3.0)
	face.position = Vector2(0, -34)
	n.add_child(face)
	var tag := Label.new()
	tag.text = dname
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_color_override("font_color", Color(1, 1, 1))
	tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	tag.add_theme_constant_override("shadow_offset_x", 1)
	tag.add_theme_constant_override("shadow_offset_y", 1)
	tag.position = Vector2(-40, -84)
	tag.custom_minimum_size = Vector2(90, 0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_child(tag)
	var area := Area2D.new()
	area.name = "Touch"
	var cs := CollisionShape2D.new()
	var cc := CircleShape2D.new()
	cc.radius = 70.0
	cs.shape = cc
	area.add_child(cs)
	n.add_child(area)
	n.add_to_group("interact")
	return n


static func make_ambient(emoji: String, line: String) -> WorldNPC:
	var n := WorldNPC.new()
	n.ambient = true
	n.ambient_line = line
	n.name = "Ambient"
	var idx: int = abs(line.hash()) % 6
	var face := Tex.spr(Tex.ambient_char(idx), 3.0)
	face.position = Vector2(0, -32)
	n.add_child(face)
	var tag := Label.new()
	tag.text = line
	tag.add_theme_font_size_override("font_size", 14)
	tag.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	tag.add_theme_constant_override("shadow_offset_x", 1)
	tag.add_theme_constant_override("shadow_offset_y", 1)
	tag.position = Vector2(-110, -74)
	tag.custom_minimum_size = Vector2(230, 0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_child(tag)
	return n

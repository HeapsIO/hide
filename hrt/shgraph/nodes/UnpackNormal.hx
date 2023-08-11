package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Unpack Normal")
@description("")
@width(120)
@group("Channel")
class UnpackNormal extends  ShaderNodeHxsl {

	static var SRC = {
		@sginput var a : Vec4;
		@sgoutput var output : Vec3;
		function fragment() {
			output = unpackNormal(a);
		}
	};

}
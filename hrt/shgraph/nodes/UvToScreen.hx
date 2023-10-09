package hrt.shgraph.nodes;

using hxsl.Ast;

@name("UV To Screen")
@description("")
@width(100)
@group("UV")
class UvToScreen extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var uv : Vec2;

		@sgoutput var output : Vec2;

		function fragment() {
			output = uvToScreen(uv);
		}
	};

}
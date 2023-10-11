package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Arc Tangent 2")
@description("The output is the arc tangent of a.y / a.x")
@width(80)
@group("Math")
class Atan2 extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Vec2;
		@sgoutput var output : Float;
		function fragment() {
			output = atan(a.y, a.x);
		}
	};
}
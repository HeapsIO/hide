package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Cross")
@description("The output is the cross product of a and b")
@width(80)
@group("Math")
class Cross extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var a : Vec3;
		@sginput var b : Vec3;
		@sgoutput var output : Vec3;
		function fragment() {
			output = cross(a,b);
		}
	};

}
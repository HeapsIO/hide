package hrt.shgraph.nodes;

import hxsl.Types.Vec;
import hxsl.*;

using hxsl.Ast;

@name("Combine")
@description("Create a vector of size 4 from 4 floats")
@group("Channel")
class Combine extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var r : Float;
		@sginput var g : Float;
		@sginput var b : Float;
		@sginput var a : Float;
		@sgoutput var output : Vec4;

		function fragment() {
			output = vec4(r,g,b,a);
		}
	}
}
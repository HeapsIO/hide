package hrt.shgraph.nodes;

import hxsl.Types.Vec;
import hxsl.*;

using hxsl.Ast;

@name("Vec2")
@description("Create a vector of size 2 from 2 floats")
@group("Channel")
class Vec2 extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var x : Float;
		@sginput(0.0) var y : Float;
		@sgoutput var output : Vec2;

		function fragment() {
			output = vec2(x,y);
		}
	}
}
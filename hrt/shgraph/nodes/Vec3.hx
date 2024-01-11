package hrt.shgraph.nodes;

import hxsl.Types.Vec;
import hxsl.*;

using hxsl.Ast;

@name("Vec3")
@description("Create a vector of size 3 from 3 floats")
@group("Channel")
class Vec3 extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var x : Float;
		@sginput(0.0) var y : Float;
		@sginput(0.0) var z : Float;
		@sgoutput var output : Vec3;

		function fragment() {
			output = vec3(x,y,z);
		}
	}
}
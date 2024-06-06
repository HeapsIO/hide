package hrt.shgraph.nodes;

import hxsl.Types.Vec;
import hxsl.*;

using hxsl.Ast;

@name("Combine Alpha")
@description("Create a vector of size 4 from a RGB and an Alpha float")
@group("Channel")
class CombineAlpha extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var rgb : Vec3;
		@sginput(1.0) var a : Float;
		@sgoutput var output : Vec4;

		function fragment() {
			output = vec4(rgb,a);
		}
	}
}
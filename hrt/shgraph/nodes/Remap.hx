package hrt.shgraph.nodes;

@name("Remap")
@description("Remap value in range [inMin, inMax] to range [outMin, outMax]")
@width(100)
@group("Operation")
class Remap extends Operation {

	static var SRC = {
		@sginput(0.0) var input : Vec4;
		@sginput(0.0) var inMin : Vec4;
		@sginput(1.0) var inMax : Vec4;
		@sginput(0.0) var outMin : Vec4;
		@sginput(1.0) var outMax : Vec4;

		@sgoutput var output : Vec4;
		function fragment() {
			output = outMin + (outMax - outMin) * (input - inMin) / (inMax - inMin);
		}
	}
}
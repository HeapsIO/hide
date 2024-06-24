package hrt.shgraph.nodes;

@name("Remap")
@description("Remap value in range [inMin, inMax] to range [outMin, outMax]")
@width(100)
@group("Operation")
class Remap extends Operation {

	static var SRC = {
		@sginput(0.0) var input : Dynamic;
		@sginput(0.0) var inMin : Dynamic;
		@sginput(1.0) var inMax : Dynamic;
		@sginput(0.0) var outMin : Dynamic;
		@sginput(1.0) var outMax : Dynamic;

		@sgoutput var output : Dynamic;
		function fragment() {
			output = outMin + (outMax - outMin) * (input - inMin) / max(inMax - inMin, 1e-5);
		}
	}
}
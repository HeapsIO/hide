package hrt.shgraph;

@name("Random")
@description("[CURRENTLY BROKEN] Generate a random value between min and max using the given seed")
@group("Channel")
class Random extends ShaderNodeHxsl {

	static var SRC = {
		@sginput("calculatedUV") var seed : Vec2;
		@sginput(0.0) var min : Float;
		@sginput(1.0) var max : Float;
		@sgoutput var output : Float;

		// shadernodeHsxl support for other functions is currently broken
		// function pcg(v : Int) : Int
		// {
		// 	var state : Int = v * 0x2C9277B5 + 0xAC564B05;
		// 	var word = ((state >>> ((state >>> 28) + 4)) ^ state) * 0x108EF2D9;
		// 	return (word >>> 22) ^ word;
		// }

		function fragment() {
			//var rand = pcg(pcg(int(seed.x)) + int(seed.y));
			output = 0.0;
		}
	}
}
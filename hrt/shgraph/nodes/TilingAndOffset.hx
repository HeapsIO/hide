package hrt.shgraph.nodes;

@name("Tiling and Offset")
@description("Tiles and offsets the value of input UV by the inputs Tiling and Offset respectively. Output is uv * tiling + offset")
@width(120)
@group("UV")
class TilingAndOffset extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var uv : Vec2;
		@sginput(1.0) var tiling : Vec2;
		@sginput(0.0) var offset : Vec2;

		@sgoutput var output : Vec2;

		function fragment() {
			output = uv * tiling + offset;
		}
	};

}
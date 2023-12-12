package hrt.shgraph.nodes;

@name("Rotate")
@description("Rotate UV around Center by Rotation radians")
@width(100)
@group("UV")
class Rotate extends Operation {

	static var SRC = {
		@sginput(calculatedUV) var uv : Vec2;
		@sginput(0.5) var center : Vec2;
		@sginput(0.0) var rotation : Float;

		@sgoutput var output : Vec2;
		function fragment() {
            var c = cos(rotation);
            var s = sin(rotation);
            output.x = uv.x * c - uv.y * s - center.x * c + center.y * s + center.x;
            output.y = uv.x * s + uv.y * c - center.x * s - center.y * c + center.y;
		}
	}
}
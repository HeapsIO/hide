package hrt.shgraph.nodes;

@name("Rotate")
@description("Rotate UV around Center by Rotation radians")
@width(100)
@group("UV")
class Rotate extends Operation {

	@prop() var unit : ShaderGraph.AngleUnit = Radian;

	static var SRC = {
		@sginput(calculatedUV) var uv : Vec2;
		@sginput(0.5) var center : Vec2;
		@sginput(0.0) var rotation : Float;

		@sgconst var unit : Int;

		@sgoutput var output : Vec2;
		function fragment() {
			var rot = rotation;
			if (unit == 1) {
				rot = rot * 3.141592 / 180.0;
			}
            var c = cos(rot);
            var s = sin(rot);
            output.x = uv.x * c - uv.y * s - center.x * c + center.y * s + center.x;
            output.y = uv.x * s + uv.y * c - center.x * s - center.y * c + center.y;
		}
	}

	override function getConstValue(name: String) : Null<Int> {
		switch (name) {
			case "unit":
				return unit == Radian ? 0 : 1;
			default:
				return null;
		}
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		elements.push(ShaderGraph.getAngleUnitDropdown(this, width));
		return elements;
	}
	#end
}
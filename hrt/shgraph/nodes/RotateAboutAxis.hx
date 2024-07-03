package hrt.shgraph.nodes;

@name("RotateAboutAxis")
@description("Rotate position around normalized rotation axis by Rotation angle")
@width(100)
@group("Math")
class RotateAboutAxis extends Operation {

	@prop() var unit : ShaderGraph.AngleUnit = Radian;

	static var SRC = {
		@sginput var position : Vec3;
        @sginput var axis : Vec3;
		@sginput var rotation : Float;

        @sgconst var unit : Int;

		@sgoutput var output : Vec3;
		function fragment() {
            var rot = rotation;
			if (unit == 1) {
				rot = rot * 3.141592 / 180.0;
			}
            
            var s = sin(rot);
            var c = cos(rot);
            var oneMinusC = 1.0 - c;

            axis = normalize(axis);

            // https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/Rotate-About-Axis-Node.html
            var rotationMatrix = mat3(
				vec3( oneMinusC * axis.x * axis.x + c, oneMinusC * axis.x * axis.y - axis.z * s, oneMinusC * axis.z * axis.x + axis.y * s ),
				vec3( oneMinusC * axis.x * axis.y + axis.z * s, oneMinusC * axis.y * axis.y + c, oneMinusC * axis.y * axis.z - axis.x * s ),
				vec3( oneMinusC * axis.z * axis.x - axis.y * s, oneMinusC * axis.y * axis.z + axis.x * s, oneMinusC * axis.z * axis.z + c )
            );

            output = position * rotationMatrix;
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
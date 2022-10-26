package hrt.shader;

class UVDebug extends hxsl.Shader {

	static var SRC = {

		var pixelColor : Vec4;

        @input var input2 : {
			var uv : Vec2;
        };

		var calculatedUV : Vec2;

        function __init__() {
            calculatedUV = input2.uv;
        }

        function fragment() {
            pixelColor.rgb = vec3(calculatedUV.x % 1.0, calculatedUV.y, 0.0);
        }
	};
}
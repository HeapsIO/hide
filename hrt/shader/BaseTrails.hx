package hrt.shader;

class BaseTrails extends hxsl.Shader {

	static var SRC = {

		@param var uvStretch : Float;
		@const @param var uvRepeat : Int = 0;

		@input var input2 : {
			var uv : Vec2;
		};

		var calculatedUV : Vec2;

		function __init__() {
			calculatedUV = input2.uv;
		}

		function fragment() {
			calculatedUV = calculatedUV * vec2(uvStretch, 1.0);

			switch(uvRepeat) {
				case 0: // Modulo
					calculatedUV.x = calculatedUV.x % 1.0;
				case 1: // Mirror
					calculatedUV.x = calculatedUV.x % 2.0;
					if (calculatedUV.x > 1.0) {
						calculatedUV.x = 2.0-calculatedUV.x;
					}
				case 3: // Clamp
					calculatedUV.x = saturate(calculatedUV.x);
				case 4: {};// None
				default: {};
			}
		}
	};

}
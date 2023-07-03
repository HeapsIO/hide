package hrt.shader;

class TextureRotate extends hxsl.Shader {

	static var SRC = {

		@param @range(0,360) var rotate = 0.0;
		@param var rotateCenter : Vec2 = vec2(0.5,0.5);

		var calculatedUV : Vec2;

        function fragment() {
			var a = rotate * 2 * 3.14159265 / 360.0;
			var m = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
			calculatedUV = (calculatedUV - rotateCenter) * m + rotateCenter;
        }
	};
}
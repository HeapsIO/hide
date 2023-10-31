package hrt.shader;

class TextureMult extends hxsl.Shader {

	static var SRC = {

		var pixelColor : Vec4;
		var calculatedUV : Vec2;
		@param var texture: Sampler2D;

        function fragment() {
			var tex = texture.get(calculatedUV);
			pixelColor.rgba *= tex.rgba;
        }
	};
}
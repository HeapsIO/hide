package hrt.shader;

class SDF extends hxsl.Shader {

	static var SRC = {
		var calculatedUV : Vec2;
        var pixelColor : Vec4;

        @param var sampler: Sampler2D;
        @param var pxRange : Float; // set to distance field's pixel range

        @param var bgColor : Vec4;
        @param var fgColor : Vec4;


        function screenPxRange() : Float {
            var unitRange = vec2(pxRange)/vec2(sampler.size());
            var screenTexSize = vec2(1.0)/fwidth(calculatedUV);
            return max(0.5*dot(unitRange, screenTexSize), 1.0);
        }

        function fragment() {
            var distance : Float = sampler.get(calculatedUV).r;
            var sceenPxDistance = screenPxRange() * (distance - 0.5);
            var opacity : Float = clamp(sceenPxDistance + 0.5, 0.0, 1.0);
            pixelColor = mix(bgColor, fgColor, opacity);
            pixelColor.a *= opacity;
        }
    }
}
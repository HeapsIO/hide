package hrt.shader;

class DissolveBurn extends hxsl.Shader {
	static var SRC = {
        @param var noise : Sampler2D;
        @perInstance @param var noiseScale : Vec2 = vec2(1.0,1.0);
        @perInstance @param var noiseOffset : Vec2 = vec2(0.0,0.0);
        @perInstance @param var dissolveWidth : Float = 0.5;
        
        @param var alphaThreshold : Float = 0.1;
        @perInstance @param var dissolveAmmount : Float = 0.5;
        
        @perInstance @param var colorBurn : Vec4;

		var pixelColor : Vec4;
        var calculatedUV : Vec2;

		function fragment() {
            var col : Vec4 = pixelColor;
            var noiseUV = mod((calculatedUV + noiseOffset) * noiseScale, vec2(1.0,1.0));
            var dissolve = noise.get(noiseUV).r;
            var dissolveAmmountRemmaped = (1.0 - dissolveAmmount* 2.0);
            dissolve +=  dissolveAmmountRemmaped;

            dissolve = (dissolve - 0.5) * 10.0;
            dissolve = clamp(dissolve, 0.0, 1.0);

            var edge = dissolve - (1.0-step(dissolve, dissolveWidth));

            var edgeColor = colorBurn * edge;

            col.rgb *= dissolve;
            col.rgb += edgeColor.rgb;
            col.rgb = clamp(col.rgb, vec3(0.0), vec3(1.0));
            col.a = dissolve;
            if (col.a < alphaThreshold) {
                discard;
            }
			pixelColor = col;
            //pixelColor.rgb = vec3(dissolve);
		}
	};
    }
package hrt.shader;

class HeightGradient extends hxsl.Shader {

	static var SRC = {

		var pixelColor : Vec4;

        /*@input var input2 : {
			var uv : Vec2;
        };*/

        /*function __init__() {
            calculatedUV = input2.uv;
        }*/

		@global var global : {
			var time : Float;
			var pixelSize : Vec2;
			@perObject var modelView : Mat4;
			@perObject var modelViewInverse : Mat4;
		};

		@param var heightRange : Vec2 = vec2(0.0,1.0);
		@param var direction : Vec3 = vec3(0.0,0.0,1.0);
		@param var gradient : Sampler2D;
		@param var alphaMult : Float = 1.0;

		@const var useWorldPosition : Bool = false;
		var transformedPosition : Vec3;

        function fragment() {
			var position = transformedPosition;
			if (!useWorldPosition) {
				transformedPosition -= vec3(global.modelView[0].w, global.modelView[1].w, global.modelView[2].w);
			}

			var d = normalize(direction);
			var position = transformedPosition;
			var heightRemaped = clamp(dot(position, d), heightRange.x, heightRange.y);
			var blend = (heightRemaped-heightRange.x)/abs(heightRange.y - heightRange.x);
			var color = gradient.get(vec2(blend, 0.5));

            pixelColor.rgb = mix(pixelColor.rgb, color.rgb, color.a * alphaMult);

			/*if (abs(calculatedUV.x % 1.0) < 0.05)
                pixelColor.rgb = vec3(1.0,0.0,1.0);
            if (abs(calculatedUV.x % 1.0) > 0.95)
                pixelColor.rgb = vec3(0.0,1.0,1.0);

            if (calculatedUV.x < 0)
                pixelColor.b = 1.0;*/
        }
	};
}
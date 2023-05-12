package hrt.shader;

class MeshWave extends hxsl.Shader {

	static var SRC = {

		@global var global : {
			var time : Float;
		};
		@input var input : {
			var position : Vec3;
			var normal : Vec3;
			var color: Vec3;
		}

		@param var speed : Float = 1.0;
		@param var length : Float = 1.0;
		@param var scale : Float = 1.0;
		@param var fmSpeed : Float = 1.0;
		@param var fmAmplitude : Float = 1.0;

		@param var randomScale : Float = 0.0;
		@param var randomSpeed : Float = 0.0;


		var random : Float;

        /*function __init__() {
            calculatedUV = input2.uv;
        }*/

		function __init__()
		{
			random = 0.5;
		}

		var relativePosition : Vec3;

		function vertex() {
			var rScale = exp((random - 0.5) * randomScale);
			var rSpeed = exp(((random*1.7548912%1.0) - 0.5) * randomSpeed);

			relativePosition.y = relativePosition.y + sin(global.time*rSpeed*speed + relativePosition.x*length + random + sin(global.time*fmSpeed + random) * fmAmplitude) * input.color.r * scale * rScale;
		}
	};
}
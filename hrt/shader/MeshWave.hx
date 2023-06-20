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

		@param var axis : Vec3 = vec3(0.0,1.0,0.0);

		@param var speed : Float = 0.5;
		@param var length : Float = 1.0;
		@param var scale : Float = 1.0;
		@param var fmSpeed : Float = 0.47;
		@param var fmAmplitude : Float = 0.25;

		@param var randomScale : Float = 0.0;
		@param var randomSpeed : Float = 0.12;


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
			var tau = 6.28318530718;
			var rScale = random != 0.5 ? exp((random - 0.5) * randomScale) : 0.5;
			var rSpeed = random != 0.5 ? exp(((random*1.7548912%1.0) - 0.5) * randomSpeed) : 0.5;

			var xScale = 1.0 / max(length, 0.001);

			var carrierSpeed = global.time*rSpeed*speed*tau;
			var dispScale = sin(carrierSpeed + relativePosition.x*xScale + random + sin(carrierSpeed*fmSpeed + random) * fmAmplitude) * input.color.r * scale * rScale;
			relativePosition += dispScale * axis;
		}
	};
}
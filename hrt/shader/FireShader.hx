package hrt.shader;

class FireShader extends hxsl.Shader {
	static var SRC = {

		@global var global : {
			var time : Float;
			var pixelSize : Vec2;
			var modelView : Mat4;
			var modelViewInverse : Mat4;
		};

		var pixelColor : Vec4;
		@param var Color1 : Vec4;
		@param var Color2 : Vec4;
		@param var T_Fire01 : Sampler2D;
		@input var input : {
			var uv : Vec2;
		};
		@param var T1_USpeed : Float;
		@param var T1_VSpeed : Float;
		@param var T2_USpeed : Float;
		@param var T2_VSpeed : Float;
		@param var LerpNoise : Sampler2D;
		@param var T3_USpeed : Float;
		@param var T3_VSpeed : Float;
		@param var Param_3 : Sampler2D;

		function fragment() : Void {
			var output_44_output : Vec2;
			output_44_output = vec2(0.8, 0.5);
			var output_45_output : Vec2;
			output_45_output = input.uv * output_44_output;
			var output_14_output : Vec2;
			output_14_output = mod(output_45_output + vec2(T1_USpeed * global.time, T1_VSpeed * global.time), 1);
			var output_4_rgba : Vec4;
			output_4_rgba = texture(T_Fire01, output_14_output);
			var output_37_output : Vec2;
			output_37_output = vec2(0.8, 0.6);
			var output_40_output : Vec2;
			output_40_output = input.uv * output_37_output;
			var output_17_output : Vec2;
			output_17_output = mod(output_40_output + vec2(T2_USpeed * global.time, T2_VSpeed * global.time), 1);
			var output_15_rgba : Vec4;
			output_15_rgba = texture(T_Fire01, output_17_output);
			var output_9_output : Vec4;
			output_9_output = output_4_rgba * output_15_rgba;
			var output_22_output : Vec4;
			output_22_output = vec4(0.7, 0.7, 0.7, 0.7);
			var output_27_output : Vec2;
			output_27_output = mod(input.uv + vec2(T3_USpeed * global.time, T3_VSpeed * global.time), 1);
			var output_25_rgba : Vec4;
			output_25_rgba = texture(LerpNoise, output_27_output);
			var output_21_output : Vec4;
			output_21_output = mix(output_9_output, output_22_output, output_25_rgba);
			var output_28_output : Vec4;
			output_28_output = output_9_output + output_21_output;
			var output_52_output : Vec2;
			output_52_output = vec2(1, 1);
			var output_53_output : Vec2;
			output_53_output = input.uv * output_52_output;
			var output_73_r : Float;
			{
				var output_73_rgba : Vec4;
				output_73_rgba = texture(Param_3, output_53_output);
				output_73_r = output_73_rgba.x;
			};
			var output_76_output : Float;
			output_76_output = output_73_r + 1;
			var output_80_output : Float;
			output_80_output = mix(0.5, output_73_r, output_76_output);
			var output_67_output : Vec4;
			output_67_output = output_28_output - vec4(output_80_output, output_80_output, output_80_output, 1);
			var output_34_output : Vec4;
			output_34_output = mix(Color1, Color2, output_67_output);
			pixelColor = output_34_output;
		}
	};
}

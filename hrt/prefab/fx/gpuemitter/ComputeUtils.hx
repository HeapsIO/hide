package hrt.prefab.fx.gpuemitter;

class ComputeUtils extends hxsl.Shader {
	public function onUpdate(emitter : GPUEmitter.GPUEmitterObject, buffer : h3d.Buffer, index : Int) {}

	static var SRC = {
		@global var global : {
			var time : Float;
		};

		@global var camera : {
			var position : Vec3;
		}
		
		function random(pos : Vec2) : Float {
			return fract(sin(dot(pos, vec2(12.9898,78.233)))*43758.5453123);
		}

		function random2d(pos : Vec2) : Vec2 {
			return vec2(fract(sin(dot(pos, vec2(12.9898,78.233)))*43758.5453123),
						fract(sin(dot(pos, vec2(1572.9898,132.237)))*157468.33458));
		}

		function random3d(pos : Vec2) : Vec3 {
			return vec3(fract(sin(dot(pos, vec2(12.9898,78.233)))*43758.5453123),
						fract(sin(dot(pos, vec2(1572.9898,132.237)))*157468.33458),
						fract(sin(dot(pos, vec2(14.5757,59.147)))*43756.281));
		}

		function translationMatrix(pos : Vec3) : Mat4 {
			return mat4(
				vec4(1.0, 0.0, 0.0, pos.x),
				vec4(0.0, 1.0, 0.0, pos.y),
				vec4(0.0, 0.0, 1.0, pos.z),
				vec4(0.0, 0.0, 0.0, 1.0)
			);
		}

		function scaleMatrix(scale : Vec3) : Mat4 {
			return mat4(
				vec4(scale.x, 0.0, 0.0, 0.0),
				vec4(0.0, scale.y, 0.0, 0.0),
				vec4(0.0, 0.0, scale.z, 0.0),
				vec4(0.0, 0.0, 0.0, 1.0)
			);
		}

		function sphericalToCartesian(radius : Float, theta : Float, phi : Float) : Vec3 {
			var sTheta = sin(theta);
			return vec3(radius * sTheta * cos(phi), radius * sTheta * sin(phi), radius * cos(theta));
		}
		
		function cartesianToSpherical(pos : Vec3) : Vec3 {
			var radius = length(pos);
			var dir = pos / radius;
			var theta = acos(pos.z / radius);
			var phi = atan(pos.y, pos.x);
			return vec3(radius, theta, phi);
		}

		function alignMatrix(up : Vec3, dir : Vec3) : Mat4 {
			var matrix = mat4(
				vec4(1.0, 0.0, 0.0, 0.0),
				vec4(0.0, 1.0, 0.0, 0.0),
				vec4(0.0, 0.0, 1.0, 0.0),
				vec4(0.0, 0.0, 0.0, 1.0)
			);
			var rotationAxis = cross(up, dir);
			if ( length(rotationAxis) > 1e-6 ) {
				rotationAxis = normalize(rotationAxis);
				var sinangle = -length(cross(dir, up));
				var cosangle = dot(up, dir);
				var cos1 = 1 - cosangle;
				var x = -rotationAxis.x;
				var y = -rotationAxis.y;
				var z = -rotationAxis.z;
				var xx = x * x;
				var yy = y * y;
				var zz = z * z;
				var xcos1 = x * cos1;
				var zcos1 = z * cos1;
				matrix = mat4(
					vec4(cosangle + x * xcos1, y * xcos1 - z * sinangle, x * zcos1 + y * sinangle, 0.0),
					vec4(y * xcos1 + z * sinangle, cosangle + yy * cos1, y * zcos1 - x * sinangle, 0.0),
					vec4(x * zcos1 - y * sinangle, y * zcos1 + x * sinangle, cosangle + z * zcos1, 0.0),
					vec4(0.0, 0.0, 0.0, 1.0)
				);
			}
			return matrix;
		}

		function rotateMatrixZ(angle : Float) : Mat4 {
			return mat4(
				vec4(cos(angle), -sin(angle), 0.0, 0.0),
				vec4(sin(angle), cos(angle), 0.0, 0.0),
				vec4(0.0, 0.0, 1.0, 0.0),
				vec4(0.0, 0.0, 0.0, 1.0)
			);
		}
	}
}
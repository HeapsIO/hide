package hrt.prefab.fx.gpuemitter;

class ComputeUtils extends hxsl.Shader {

	public function onDispatch(emitter : GPUEmitterObject) {}

	public function onRemove(emitter : GPUEmitterObject) {}

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
						fract(sin(dot(pos, vec2(14.5757,59.147)))*4756.281));
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

		function lookAtMatrix( eye : Vec3, at : Vec3, up : Vec3) : Mat4 {
			var ax = normalize(at);
			var ay = cross(up, ax);
			if ( dot(ay, ay) < 1e-6 ) {
				ay.x = ax.y;
				ay.y = ax.z;
				ay.z = ax.x;
			}
			ay = normalize(ay);
			var az = ax.cross(ay);
			var lookAt = mat4(
				vec4(ax.x, ay.x, az.x, eye.x),
				vec4(ax.y, ay.y, az.y, eye.y),
				vec4(ax.z, ay.z, az.z, eye.z),
				vec4(0.0, 0.0, 0.0, 1.0)
			);
			return lookAt;
		}

		function alignMatrix(up : Vec3, dir : Vec3) : Mat4 {
			var matrix = mat4(
				vec4(1.0, 0.0, 0.0, 0.0),
				vec4(0.0, 1.0, 0.0, 0.0),
				vec4(0.0, 0.0, 1.0, 0.0),
				vec4(0.0, 0.0, 0.0, 1.0)
			);
			var rotationAxis = cross(up, dir);
			if ( dot(rotationAxis, rotationAxis) > 1e-6 ) {
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

		function rotateMatrixX(angle : Float) : Mat4 {
			return mat4(
				vec4(1.0, 0.0, 0.0, 0.0),
				vec4(0.0, cos(angle), -sin(angle), 0.0),
				vec4(0.0, sin(angle), cos(angle), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0)
			);
		}

		function rotateMatrixY(angle : Float) : Mat4 {
			return mat4(
				vec4(cos(angle), 0.0, -sin(angle), 0.0),
				vec4(0.0, 1.0, 0.0, 0.0),
				vec4(sin(angle), 0.0, cos(angle), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0)
			);
		}

		function rotateMatrixZ(angle : Float) : Mat4 {
			return mat4(
				vec4(cos(angle), -sin(angle), 0.0, 0.0),
				vec4(sin(angle), cos(angle), 0.0, 0.0),
				vec4(0.0, 0.0, 1.0, 0.0),
				vec4(0.0, 0.0, 0.0, 1.0)
			);
		}

		function quatInitRotation(ax : Float, ay : Float, az : Float) : Vec4 {
			var sinX = ( ax * 0.5 ).sin();
			var cosX = ( ax * 0.5 ).cos();
			var sinY = ( ay * 0.5 ).sin();
			var cosY = ( ay * 0.5 ).cos();
			var sinZ = ( az * 0.5 ).sin();
			var cosZ = ( az * 0.5 ).cos();
			var cosYZ = cosY * cosZ;
			var sinYZ = sinY * sinZ;

			var quat = vec4(0.0);
			quat.x = sinX * cosYZ - cosX * sinYZ;
			quat.y = cosX * sinY * cosZ + sinX * cosY * sinZ;
			quat.z = cosX * cosY * sinZ - sinX * sinY * cosZ;
			quat.w = cosX * cosYZ + sinX * sinYZ;

			return quat;
		}
	}
}
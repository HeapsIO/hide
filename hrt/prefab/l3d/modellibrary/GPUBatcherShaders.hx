package hrt.prefab.l3d.modellibrary;

class CopyModelViews extends hxsl.Shader {
	static var SRC = {
		@param var positions : StorageBuffer<Mat4>;
		@param var positionsOut : RWBuffer<Vec4>;
		@param var stride : Int;
		@param var modelViewPos : Int;

		@param var start : Int;

		@:import h3d.shader.BufferUtils;

		var idx : Int;
		function main() {
			var invocID = computeVar.globalInvocation.x;
			idx = (invocID + start) * stride;
			var tmp = positions[invocID]; //Use tmp variable to avoid flatten error (convert mat4 to 4 Vec4 both on left and right value cause var ID to be disconnected).
			writeMat4(positionsOut, idx + modelViewPos, tmp);
		}
	}
}

class CopyUvTransform extends hxsl.Shader {
	static var SRC = {
		@param var uvTransform : Vec4;
		@param var uvTransformOut : RWBuffer<Vec4>;
		@param var uvTransformPos : Int;

		var idx : Int;
		function main() {
			uvTransformOut[idx + uvTransformPos] = uvTransform;
		}
	}
}

class CopyLibraryParams extends hxsl.Shader {
	static var SRC = {
		@param var libraryParams : Vec4;
		@param var libraryParamsOut : RWBuffer<Vec4>;
		@param var libraryParamsPos : Int;

		var idx : Int;
		function main() {
			libraryParamsOut[idx + libraryParamsPos] = libraryParams;
		}
	}
}

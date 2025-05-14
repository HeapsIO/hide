package hrt.prefab.l3d.modellibrary;

class AtlasShader extends hxsl.Shader {
	static var SRC = {

		@:import h3d.shader.BaseMesh;

		@param @perInstance var uvTransform : Vec4;
		@param @perInstance var libraryParams : Vec4;

		@const var singleTexture : Bool;
		@const var hasNormal : Bool;
		@const var hasPbr : Bool;
		@const var AUTO_LOD : Bool;

		@param var texture : Sampler2D;
		@param var normalMap : Sampler2D;
		@param var specular : Sampler2D;

		@param var textures : Sampler2DArray;
		@param var normalMaps : Sampler2DArray;
		@param var speculars : Sampler2DArray;

		@param var mipStart : Float;
		@param var mipEnd : Float;
		@param var mipPower : Float;
		@param var mipNumber : Float;

		@input var input2 : {
			var tangent : Vec3;
			var uv : Vec2;
		};

		var calculatedUV : Vec2;
		var transformedTangent : Vec4;

		var metalness : Float;
		var roughness : Float;
		var occlusion : Float;

		var mipLevel : Float;

		function unpackPBR(v : Vec4) : Vec4 {
			metalness = v.r;
			roughness = 1 - v.g * v.g;
			occlusion = v.b;
			// no emissive for now
		}

		function __init__vertex() {
			calculatedUV = input2.uv;
			previousTransformedPosition = transformedPosition;
			if( hasNormal )
				transformedTangent = vec4(input2.tangent * global.modelView.mat3(),input2.tangent.dot(input2.tangent) > 0.5 ? 1. : -1.);
			mipLevel = pow(saturate((projectedPosition.z - mipStart) / (mipEnd - mipStart)), mipPower) * mipNumber;
		}

		function fragment() {
			calculatedUV = clamp(calculatedUV.fract(), libraryParams.y, 1.0 - libraryParams.y);
			calculatedUV = calculatedUV * uvTransform.zw + uvTransform.xy;
		}

		function getTexture(sampler : Sampler2D, uv : Vec2) : Vec4 {
			if ( AUTO_LOD )
				return sampler.get(uv);
			else
				return sampler.getLod(uv, mipLevel);
		}

		function getTextureArray(sampler : Sampler2DArray, uv : Vec3) : Vec4 {
			if ( AUTO_LOD )
				return sampler.get(uv);
			else
				return sampler.getLod(uv, mipLevel);
		}

		function __init__fragment() {
			pixelColor = singleTexture ? getTexture(texture, calculatedUV) : getTextureArray(textures, vec3(calculatedUV, libraryParams.x));
			if( hasNormal ) {
				var n = transformedNormal;
				var nf = unpackNormal(singleTexture ? getTexture(normalMap, calculatedUV) : getTextureArray(normalMaps, vec3(calculatedUV, libraryParams.x)));
				var tanX = transformedTangent.xyz.normalize();
				var tanY = n.cross(tanX) * -transformedTangent.w;
				transformedNormal = (nf.x * tanX + nf.y * tanY + nf.z * n).normalize();
			}
			if( hasPbr ) {
				var v = singleTexture ? getTexture(specular, calculatedUV) : getTextureArray(speculars, vec3(calculatedUV, libraryParams.x));
				unpackPBR(v);
			}
		}

	}
}
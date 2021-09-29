package hrt.prefab.rfx;

class SSRShader extends hxsl.Shader {

	static var SRC = {

		@global var camera : {
			var inverseViewProj : Mat4;
			var position : Vec3;
			var viewProj : Mat4;
			var zNear : Float;
			var zFar : Float;
		};

		@global var depthMap:Channel;

		@param var ldrMap:Sampler2D;

		@param var intensity : Float;
		@param var colorMul : Float;
		@param var maxRayDistance : Float;
		@param var startFadeDistance : Float;
		@param var stepsFirstPass : Int;
		@param var stepsSecondPass : Int;
		@param var thickness : Float;

		var projectedPosition:Vec4;
		var pixelColor:Vec4;
		var transformedNormal : Vec3;
		var transformedPosition : Vec3;

		function reflectedRay(ray : Vec3, normal : Vec3) : Vec3 {
			return ray - 2.0 * dot(ray, normal) * normal;
		}

		function fragment() {

			var startRay = projectedPosition.xy / projectedPosition.w;

			var camDir = (transformedPosition - camera.position).normalize();
			var reflectedRay = camDir - 2.0 * dot(camDir, transformedNormal) * transformedNormal;

			var curPosWS = transformedPosition + reflectedRay * maxRayDistance / stepsFirstPass;
			var hitFirstPass = false;
			var curDepth = 0.0;
			@unroll for (i in 0 ... stepsFirstPass) {
				var projPos = vec4(curPosWS, 1.0) * camera.viewProj;
				var curPos = projPos.xy / projPos.w;
				var distToCam = projPos.z / projPos.w;
				curDepth = depthMap.get(screenToUv(curPos));
				if (distToCam > curDepth && curPos.x <= 1.0 && curPos.x >= -1.0 && curPos.y <= 1.0 && curPos.y >= -1.0) {
					var ruv = vec4( curPos, curDepth, 1 );
					var ppos = ruv * camera.inverseViewProj;
					var wpos = ppos.xyz / ppos.w;
					if ((wpos - curPosWS).length() < thickness)
						hitFirstPass = true;
				}
				if (hitFirstPass == false) {
					curPosWS += reflectedRay * maxRayDistance / stepsFirstPass;
				}
			}

			curPosWS -= reflectedRay * maxRayDistance / stepsFirstPass / stepsSecondPass;
			var hitSecondPass = false;
			var curPos = vec2(0.0, 0.0);
			@unroll for (i in 0 ... stepsSecondPass) {
				var projPos = vec4(curPosWS, 1.0) * camera.viewProj;
				curPos = projPos.xy / projPos.w;
				var distToCam = projPos.z / projPos.w;
				curDepth = depthMap.get(screenToUv(curPos));
				if (distToCam < curDepth && curPos.x <= 1.0 && curPos.x >= -1.0 && curPos.y <= 1.0 && curPos.y >= -1.0) {
					var ruv = vec4( curPos, curDepth, 1 );
					var ppos = ruv * camera.inverseViewProj;
					var wpos = ppos.xyz / ppos.w;
					if ((wpos - curPosWS).length() < thickness)
						hitSecondPass = true;
				}
				if (hitSecondPass == false) {
					curPosWS -= reflectedRay * maxRayDistance / stepsFirstPass / stepsSecondPass;
				}
			}

			var fragmentColor = vec3(0.0, 0.0, 0.0);
			var alpha = 0.0;
			if (hitFirstPass && hitSecondPass) {

				fragmentColor = ldrMap.get(screenToUv(curPos)).rgb;
				alpha = 1.0 - saturate(((curPosWS - transformedPosition).length() - startFadeDistance) / (maxRayDistance - startFadeDistance));
				alpha *= intensity;
			}

			pixelColor.rgba *= vec4(fragmentColor * colorMul, alpha);
		}
	}
}

class SSR extends RendererFX {

	public var ssrShader : SSRShader;

	@:s public var intensity : Float = 1.;
	@:s public var colorMul : Float = 1.;
	@:s public var maxRayDistance : Float = 10.;
	@:s public var startFadeDistance : Float = 5.;
	@:s public var steps : Int = 10;
	@:s public var stepsFirstPass : Int = 10;
	@:s public var stepsSecondPass : Int = 10;
	@:s public var thickness : Float = 1.0;

	function new(?parent) {
		super(parent);

		ssrShader = new SSRShader();
	}

	override function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if( step == Forward ) {
			r.mark("SSR");

			ssrShader.ldrMap = r.ctx.getGlobal("ldrMap");

			ssrShader.colorMul = colorMul;
			ssrShader.intensity = intensity;
			ssrShader.maxRayDistance = maxRayDistance;
			ssrShader.startFadeDistance = startFadeDistance;
			ssrShader.stepsFirstPass = stepsFirstPass;
			ssrShader.stepsSecondPass = stepsSecondPass;
			ssrShader.thickness = thickness;

			var ssrPasses : h3d.pass.PassList = r.get("ssr");
			@:privateAccess var it = ssrPasses.current;
			@:privateAcces while (it != null) {
				if (@:privateAccess it.pass.getShaderByName("hrt.prefab.rfx.SSRShader") == null)
					@:privateAccess it.pass.addShader(ssrShader);
				it = it.next;
			}

			r.draw("ssr");
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
		<div class="group" name="SSR">
			<dl>
				<dt>Intensity</dt><dd><input type="range" min="0" max="1" field="intensity"/></dd>
				<dt>Color Mul</dt><dd><input type="range" min="0" max="1" field="colorMul"/></dd>
				<dt>Max ray distance</dt><dd><input type="range" min="0" max="10" field="maxRayDistance"/></dd>
				<dt>Start Fade Distance</dt><dd><input type="range" min="0" max="10" field="startFadeDistance"/></dd>
				<dt>Steps first pass</dt><dd><input type="range" min="1" max="30" step="1" field="stepsFirstPass"/></dd>
				<dt>Steps second pass</dt><dd><input type="range" min="1" max="20" step="1" field="stepsSecondPass"/></dd>
				<dt>Thickness</dt><dd><input type="range" min="0" max="1" field="thickness"/></dd>
			</dl>
		</div>
		'),this);
	}
	#end

	static var _ = Library.register("rfx.ssr", SSR);

}

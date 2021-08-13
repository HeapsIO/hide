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

		@param var hdrMap:Sampler2D;

		@param var maxRayDistance : Float;
		@param var stepsFirstPass : Int;
		@param var stepsSecondPass : Int;

		var projectedPosition:Vec4;
		var pixelColor:Vec4;
		var transformedNormal : Vec3;
		var transformedPosition : Vec3;

		function reflectedRay(ray : Vec3, normal : Vec3) : Vec3 {
			return ray - 2.0 * dot(ray, normal) * normal;
		}

		function fragment() {

			var startRay = screenToUv(projectedPosition.xy / projectedPosition.w);

			var camDir = (transformedPosition - camera.position).normalize();
			var reflectedRay = camDir - 2.0 * dot(camDir, transformedNormal) * transformedNormal;
			var endRayWS = transformedPosition + reflectedRay * maxRayDistance;
			var endRayProjected = vec4(endRayWS, 1.0) * camera.viewProj;
			var endRay = screenToUv(endRayProjected.xy / endRayProjected.w);

			var delta = endRay - startRay;
			var curPos = startRay + delta / stepsFirstPass;
			var curPosWS = transformedPosition + reflectedRay * maxRayDistance / stepsFirstPass;
			var hitFirstPass = false;
			@unroll for (i in 0 ... stepsFirstPass) {

				var projPos = vec4(curPosWS, 1.0) * camera.viewProj;
				var distToCam = projPos.z / projPos.w;
				if (distToCam > depthMap.get(curPos) && curPos.x <= 1.0 && curPos.x >= 0.0 && curPos.y <= 1.0 && curPos.y >= 0.0) {
					hitFirstPass = true;
				}
				if (hitFirstPass == false) {
					curPos += delta / stepsFirstPass;
					curPosWS += reflectedRay * maxRayDistance / stepsFirstPass;
				}
			}

			delta = delta / stepsFirstPass;
			endRay = curPos - delta;
			curPos -= delta / stepsSecondPass;
			curPosWS -= reflectedRay * maxRayDistance / stepsFirstPass / stepsSecondPass;
			var hitSecondPass = false;
			@unroll for (i in 0 ... stepsSecondPass) {
				var projPos = vec4(curPosWS, 1.0) * camera.viewProj;
				var distToCam = projPos.z / projPos.w;
				if (distToCam < depthMap.get(curPos) && curPos.x <= 1.0 && curPos.x >= 0.0 && curPos.y <= 1.0 && curPos.y >= 0.0) {
					hitSecondPass = true;
				}
				if (hitSecondPass == false) {
					curPos -= delta / stepsSecondPass;
					curPosWS -= reflectedRay * maxRayDistance / stepsFirstPass / stepsSecondPass;
				}
			}

			var fragmentColor = vec3(0.0, 0.0, 0.0);
			var alpha = 0.0;
			if (hitFirstPass && hitSecondPass) {
				fragmentColor = hdrMap.get(curPos).rgb;
				alpha = 1.0 - (curPosWS - transformedPosition).length() / maxRayDistance;
			}

			pixelColor.rgba *= vec4(fragmentColor, alpha);
		}
	}
}

class SSR extends RendererFX {

	public var ssrShader : SSRShader;

	@:s public var maxRayDistance : Float = 1.;
	@:s public var steps : Int = 10;
	@:s public var stepsFirstPass : Int = 10;
	@:s public var stepsSecondPass : Int = 10;

	function new(?parent) {
		super(parent);

		ssrShader = new SSRShader();
	}

	override function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if( step == Lighting ) {
			r.mark("SSR");

			var hdrCopy = r.allocTarget("hdrMapCopy", false, 0.5);
			h3d.pass.Copy.run(r.ctx.getGlobal("hdrMap"), hdrCopy);

			ssrShader.hdrMap = hdrCopy;
			ssrShader.maxRayDistance = maxRayDistance;
			ssrShader.stepsFirstPass = stepsFirstPass;
			ssrShader.stepsSecondPass = stepsSecondPass;

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
				<dt>Max ray distance</dt><dd><input type="range" min="0" max="10" field="maxRayDistance"/></dd>
				<dt>Steps first pass</dt><dd><input type="range" min="0" max="10" step="1" field="stepsFirstPass"/></dd>
				<dt>Steps second pass</dt><dd><input type="range" min="0" max="10" step="1" field="stepsSecondPass"/></dd>
			</dl>
		</div>
		'),this);
	}
	#end

	static var _ = Library.register("rfx.ssr", SSR);

}

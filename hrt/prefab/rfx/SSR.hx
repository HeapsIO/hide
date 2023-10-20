package hrt.prefab.rfx;

class SSRShader extends h3d.shader.ScreenShader {
	static var SRC = {

		@global var camera : {
			var inverseViewProj : Mat4;
			var position : Vec3;
		};

		@param var cameraViewProj : Mat4;

		@global var depthMap : Channel;

		@param var hdrMap : Sampler2D;
		@param var roughnessMap : Sampler2D;
		@param var normalMap : Sampler2D;

		@param var intensity : Float;
		@param var colorMul : Float;
		@param var maxRayDistance : Float;
		@param var startFadeDistance : Float;
		@const var stepsFirstPass : Int;
		@const var stepsSecondPass : Int;
		@param var thickness : Float;
		@param var maxRoughness : Float;
		@param var minCosAngle : Float;
		@param var invGamma : Float;

		function rand(co : Vec2) : Float {
			return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
		}

		function reflectedRay(ray : Vec3, normal : Vec3) : Vec3 {
			return ray - 2.0 * dot(ray, normal) * normal;
		}

		var curPos : Vec2;
		function getDepths( worldPos : Vec3) : Vec2 {
			var projPos = vec4(worldPos, 1.0) * cameraViewProj;
			curPos = projPos.xy / projPos.w;
			var distToCam = projPos.z / projPos.w;
			return vec2(distToCam, depthMap.get(screenToUv(curPos)));
		}

		function getWorlPos(uv:Vec2):Vec3 {
			var depth = depthMap.get(uv).r;
			var ruv = vec4(uvToScreen(uv), depth, 1);
			var wpos = ruv * camera.inverseViewProj;
			var result = (wpos.xyz / wpos.w);
			return result;
		};

		function fragment() {
			var normal = normalMap.get(calculatedUV).rgb;

			if (normal.dot(normal) <= 0)
				discard;

			var roughnessFactor = 1 - smoothstep(0.0, maxRoughness, roughnessMap.get(calculatedUV).g);
			if (roughnessFactor <= 0)
				discard;

			var depth = depthMap.get(calculatedUV);

			var initialWPos = getWorlPos(calculatedUV);

			var camDir = (initialWPos - camera.position).normalize();
			var reflectedRay = reflectedRay(camDir, normal);

			var curPosWS = initialWPos + reflectedRay * maxRayDistance / stepsFirstPass;
			var hitFirstPass = false;

			for (i in 0 ... stepsFirstPass) {
				var depths = getDepths(curPosWS);
				var distToCam = depths.r;
				var curDepth = depths.g;
				if (distToCam > curDepth && curPos.x <= 1.0 && curPos.x >= -1.0 && curPos.y <= 1.0 && curPos.y >= -1.0) {
					var ruv = vec4( curPos, curDepth, 1 );
					var ppos = ruv * camera.inverseViewProj;
					var wpos = ppos.xyz / ppos.w;
					if ((wpos - curPosWS).length() < thickness && dot(normalMap.get(screenToUv(curPos)).rgb, normal) < minCosAngle)
						hitFirstPass = true;
				}
				if (hitFirstPass == false) {
					curPosWS += reflectedRay * maxRayDistance / stepsFirstPass;
				}
			}

			if (hitFirstPass == false)
				discard;

			curPosWS -= reflectedRay * maxRayDistance / stepsFirstPass / stepsSecondPass;
			var hitSecondPass = false;
			for (i in 0 ... stepsSecondPass) {
				var depths = getDepths(curPosWS);
				var distToCam = depths.r;
				var curDepth = depths.g;
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

			var fragmentColor = vec3(0.0);
			var alpha = 0.0;
			if (hitFirstPass && hitSecondPass) {
				fragmentColor = hdrMap.getLod(screenToUv(curPos), 0.0).rgb;
				alpha = 1.0 - saturate(((curPosWS - initialWPos).length() - startFadeDistance) / (maxRayDistance - startFadeDistance));
				alpha *= intensity;
			}

			pixelColor.rgba = saturate(vec4(fragmentColor * colorMul, alpha * roughnessFactor));
		}
	}
}

class SSR extends RendererFX {

	public var ssrPass : h3d.pass.ScreenFx<SSRShader>;

	var blurPass = new h3d.pass.Blur();
	var ssr : h3d.mat.Texture;

	@:s public var intensity : Float = 1.;
	@:s public var colorMul : Float = 1.;
	@:s public var maxRayDistance : Float = 10.;
	@:s public var startFadeDistance : Float = 5.;
	@:s public var steps : Int = 10;
	@:s public var stepsFirstPass : Int = 10;
	@:s public var stepsSecondPass : Int = 10;
	@:s public var thickness : Float = 1.0;
	@:s public var blurRadius : Float = 1.0;
	@:s public var randomPower : Float = 0.0;
	@:s public var textureSize : Float = 0.5;
	@:s public var maxRoughness : Float = 0.75;
	@:s public var minAngle : Float = 15;

	function new(?parent) {
		super(parent);
		ssrPass = new h3d.pass.ScreenFx(new SSRShader());
	}

	override function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if( step == Forward ) {
			r.mark("SSR");

			var ssrShader = ssrPass.shader;

			var hdrMap = r.ctx.getGlobal("hdrMap");
			ssrShader.hdrMap = hdrMap;
			@:privateAccess ssrShader.roughnessMap = cast(r, h3d.scene.pbr.Renderer).textures.pbr;

			var normalMap = r.ctx.getGlobal("normalMap").texture;
			ssrShader.normalMap = normalMap;

			ssrShader.colorMul = colorMul;
			ssrShader.intensity = intensity;
			ssrShader.maxRayDistance = maxRayDistance;
			ssrShader.startFadeDistance = startFadeDistance;
			ssrShader.stepsFirstPass = stepsFirstPass;
			ssrShader.stepsSecondPass = stepsSecondPass;
			ssrShader.thickness = thickness;
			ssrShader.maxRoughness = maxRoughness;
			ssrShader.minCosAngle = Math.cos(hxd.Math.degToRad(minAngle));

			ssrShader.cameraViewProj = r.ctx.camera.m;

			ssrPass.setGlobals(r.ctx);

			ssr = r.allocTarget("ssr", false, textureSize, hdrMap.format);
			ssr.clear(0, 0);
			r.ctx.engine.pushTarget(ssr);
			ssrPass.render();
			r.ctx.engine.popTarget();

			blurPass.radius = blurRadius;
			blurPass.apply(r.ctx, ssr);

			h3d.pass.Copy.run(ssr, r.ctx.engine.getCurrentTarget(), Alpha);
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
		<div class="group" name="SSR">
			<dl>
				<dt>Intensity</dt><dd><input type="range" min="0" max="1" field="intensity"/></dd>
				<dt>Color Mul</dt><dd><input type="range" min="0" max="1" field="colorMul"/></dd>
				<dt>Max Roughness</dt><dd><input type="range" min="0" max="1" field="maxRoughness"/></dd>
				<dt>Min Angle</dt><dd><input type="range" min="0" max="90" field="minAngle"/></dd>
				<dt>Max ray distance</dt><dd><input type="range" min="0" max="10" field="maxRayDistance"/></dd>
				<dt>Start Fade Distance</dt><dd><input type="range" min="0" max="10" field="startFadeDistance"/></dd>
				<dt>Steps first pass</dt><dd><input type="range" min="1" max="30" step="1" field="stepsFirstPass"/></dd>
				<dt>Steps second pass</dt><dd><input type="range" min="1" max="20" step="1" field="stepsSecondPass"/></dd>
				<dt>Thickness</dt><dd><input type="range" min="0" max="1" field="thickness"/></dd>
				<dt>Blur radius</dt><dd><input type="range" min="0" max="5" field="blurRadius"/></dd>
				<dt>Texture size</dt><dd><input type="range" min="0" max="1" field="textureSize"/></dd>
			</dl>
		</div>
		'),this);
	}
	#end

	static var _ = Library.register("rfx.ssr", SSR);

}

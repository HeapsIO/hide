package hrt.prefab.rfx;

class SSRShader extends h3d.shader.ScreenShader {
	static var SRC = {

		@global var depthMap : Channel;

		@param var texSize : Vec2;
		@param var hdrMap : Sampler2D;
		@param var roughnessMap : Sampler2D;
		@param var normalMap : Sampler2D;

		@param var cameraView : Mat4;
		@param var cameraInverseView : Mat4;
		@param var cameraProj : Mat4;
		@param var cameraInverseProj : Mat4;
		@param var cameraPos: Vec3;

		@param var intensity : Float;
		@param var colorMul : Float;
		@param var thickness : Float;
		@param var maxRoughness : Float;
		@param var minCosAngle : Float;
		@param var rayMarchingResolution : Float;

		@param var frustum : Buffer<Vec4, 6>;

		@const var batchSample : Bool;
		@const var CHECK_ANGLE : Bool;

		@param var vignettingRadius : Float;
		@param var vignettingSoftness : Float;

		var screenDepth : Float;

		function reflectedRay(ray : Vec3, normal : Vec3) : Vec3 {
			return ray - 2.0 * dot(ray, normal) * normal;
		}

		function getViewPos(uv:Vec2):Vec4 {
			screenDepth = depthMap.getLod(uv, 0).r;
			var ruv = vec4(uvToScreen(uv), screenDepth, 1);
			var vpos = ruv * cameraInverseProj;
			return vpos / vpos.w;
		};

		function intersectViewRayWithFrustum( start : Vec3, dir : Vec3 ) : Vec3 {
			var wStart = vec4(start, 1.0) * cameraInverseView;
			wStart /= wStart.w;
			var wDir = normalize(dir * cameraInverseView.mat3());

			var minT = 1000000.0;
			for ( i in 0...6 ) {
				var plane = frustum[i];
				var num = plane.w - ( plane.x * wStart.x + plane.y * wStart.y + plane.z * wStart.z );
				var denom = plane.x * wDir.x + plane.y * wDir.y + plane.z * wDir.z;
				var t = num / denom;
				if ( denom != 0.0 && t > 0.0 )
					minT = min( minT, t );
			}

			var wEnd = wStart.xyz + wDir * minT;
			var vEnd = vec4(wEnd, 1.0) * cameraView;
			return vEnd.xyz / vEnd.w;
		}

		function fragment() {
			var normal = normalMap.get(calculatedUV).rgb;
			if (normal.dot(normal) <= 0)
				discard;

			var roughnessFactor = 1 - smoothstep(0.0, maxRoughness, roughnessMap.get(calculatedUV).g);
			if (roughnessFactor <= 0)
				discard;

			var positionFrom = getViewPos(calculatedUV);
			var camDir = normalize(positionFrom.xyz);
			var viewNormal = normalize( normal * cameraView.mat3() );
			var reflectedRay = reflectedRay(camDir, viewNormal);
			reflectedRay = normalize(reflectedRay);

			var positionTo = intersectViewRayWithFrustum(positionFrom.xyz, reflectedRay);

			var startFrag = calculatedUV * texSize;
			var roundStartFrag = roundEven(startFrag);

			var endFrag = vec4(positionTo, 1.0) * cameraProj;
			endFrag.xyz /= endFrag.w;
			endFrag.xy = screenToUv(endFrag.xy);
			endFrag.xy *= texSize;
			var roundEndFrag = roundEven(endFrag);

			if ( roundStartFrag.x == roundEndFrag.x && roundStartFrag.y == roundEndFrag.y )
				discard;

			var hit = 0;
			var ray = endFrag.xy - startFrag.xy;
			var rayLength = length(ray);
			var stepCount = ceil(rayLength * rayMarchingResolution);
			var increment = ray / stepCount;
			var frag = startFrag.xy + increment;
			var uv = frag / texSize;

			if (!batchSample) {
				var iStepCount = int( stepCount );
				for ( curStep in 0...iStepCount ) {
					var curPos = getViewPos(uv);
					var viewDistance = (positionFrom.z * positionTo.z) / mix(positionTo.z, positionFrom.z, float( curStep + 1 ) / stepCount );
					var depth = viewDistance - curPos.z;
					if ( depth >= 0.0 && depth < thickness && screenDepth < 1 ) {
						hit = 1;
						break;
					}

					frag += increment;
					uv = frag / texSize;
				}
			} else {
				var iStepCount = int( ceil( stepCount / 4 ) );
				for ( curStep in 0...iStepCount ) {
					var results : Array<Bool, 4> = [false, false, false, false];

					@unroll
					for ( i in 0...4 ) {
						var curPos = getViewPos(uv);
						var viewDistance = (positionFrom.z * positionTo.z) / mix(positionTo.z, positionFrom.z, float( curStep * 4 + i + 1 ) / stepCount );
						var depth = viewDistance - curPos.z;
						results[i] = depth >= 0.0 && depth < thickness && screenDepth < 1;
						frag += increment;
						uv = frag / texSize;
					}

					if (results[0] || results[1] || results[2] || results[3]) {
						hit = 1;
						for ( j in 0...4 ) {
							if (results[j]) {
								uv = (frag - (increment * (4 - j))) / texSize;
								break;
							}
						}
						break;
					}
				}
			}

			if ( hit != 1 )
				discard;

			if ( CHECK_ANGLE ) {
				var reflectionNormal = normalMap.get(uv).rgb;
				if (dot(reflectionNormal, normal) > minCosAngle || reflectionNormal.dot(reflectionNormal) <= 0)
					discard;
			}

			var screenPos = uvToScreen(calculatedUV);
			var dist = length(screenPos);
			var vignetting = 1.0 - smoothstep(vignettingRadius-vignettingSoftness, vignettingRadius, dist);

			var fragmentColor = hdrMap.get(uv).rgb;
			pixelColor = saturate(vec4(fragmentColor * colorMul, intensity * roughnessFactor * vignetting));
		}
	}
}

class SSR extends RendererFX {

	public var ssrPass : h3d.pass.ScreenFx<SSRShader>;

	var blurPass = new h3d.pass.Blur();
	var ssr : h3d.mat.Texture;

	@:s public var intensity : Float = 1.;
	@:s public var colorMul : Float = 1.;
	@:s public var thickness : Float = 1.0;
	@:s public var blurRadius : Float = 1.0;
	@:s public var textureSize : Float = 0.5;
	@:s public var maxRoughness : Float = 0.75;
	@:s public var minAngle : Float = 5.0;
	@:s public var rayMarchingResolution : Float = 0.5;
	@:s public var support4K : Bool = false;
	@:s public var batchSample : Bool = true;
	@:s public var vignettingRadius : Float = 0.1;
	@:s public var vignettingSmoothness : Float = 0.1;

	function new(parent, shared) {
		super(parent, shared);
		ssrPass = new h3d.pass.ScreenFx(new SSRShader());
	}

	override function begin( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if( step == Forward ) {
			r.mark("SSR");

			var ssrShader = ssrPass.shader;

			var hdrMap = r.ctx.getGlobal("hdrMap");
			ssrShader.hdrMap = hdrMap;
			@:privateAccess ssrShader.roughnessMap = cast(r, h3d.scene.pbr.Renderer).textures.pbr;

			var normalMap = r.ctx.getGlobal("normalMap").texture;
			ssrShader.normalMap = normalMap;
			var t = r.ctx.engine.getCurrentTarget();
			ssrShader.texSize = new h3d.Vector((t == null ? r.ctx.engine.width : t.width), (t == null ? r.ctx.engine.height : t.height));
			ssrShader.colorMul = colorMul;
			ssrShader.intensity = intensity;
			ssrShader.thickness = thickness;
			ssrShader.maxRoughness = maxRoughness;
			if ( minAngle == 0 )
				ssrShader.CHECK_ANGLE = false;
			ssrShader.minCosAngle = Math.cos(hxd.Math.degToRad(minAngle));
			var resRescale = 1.0;
			if ( !support4K )
				resRescale = hxd.Math.max(1.0, hxd.Math.max(ssrShader.texSize.x / 2560, ssrShader.texSize.y / 1440));
			ssrShader.rayMarchingResolution = hxd.Math.clamp(rayMarchingResolution / resRescale);
			ssrShader.batchSample = batchSample;

			ssrShader.cameraView = r.ctx.camera.mcam;
			ssrShader.cameraInverseView = r.ctx.camera.getInverseView();
			ssrShader.cameraProj = r.ctx.camera.mproj;
			ssrShader.cameraInverseProj = r.ctx.camera.getInverseProj();
			ssrShader.cameraPos = r.ctx.camera.pos;

			ssrShader.vignettingRadius = vignettingRadius;
			ssrShader.vignettingSoftness = vignettingSmoothness;

			ssrShader.frustum = r.ctx.getCameraFrustumBuffer();

			ssr = r.allocTarget("ssr", false, textureSize / resRescale, hdrMap.format);
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
				<dt>Thickness</dt><dd><input type="range" min="0" max="1" field="thickness"/></dd>
				<dt>Ray marching resolution</dt><dd><input type="range" min="0" max="1" field="rayMarchingResolution"/></dd>
				<dt>Blur radius</dt><dd><input type="range" min="0" max="5" field="blurRadius"/></dd>
				<dt>Texture size</dt><dd><input type="range" min="0" max="1" field="textureSize"/></dd>
				<dt>Support 4K</dt><dd><input type="checkbox" field="support4K"/></dd>
				<dt>Fast sample</dt><dd><input type="checkbox" field="batchSample"/></dd>
				<dt>Vignetting radius</dt><dd><input type="range" min="0" max="1" field="vignettingRadius"/></dd>
				<dt>Vignetting smoothness</dt><dd><input type="range" min="0" max="1" field="vignettingSmoothness"/></dd>
			</dl>
		</div>
		'),this);
	}
	#end

	static var _ = Prefab.register("rfx.ssr", SSR);

}

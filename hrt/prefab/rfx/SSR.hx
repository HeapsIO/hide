package hrt.prefab.rfx;

class SSRShader extends h3d.shader.ScreenShader {
	static var SRC = {

		@global var depthMap : Channel;

		@param var texSize : Vec2;
		@param var hdrMap : Sampler2D;
		@param var roughnessMap : Sampler2D;
		@param var normalMap : Sampler2D;

		@param var cameraView : Mat4;
		@param var cameraProj : Mat4;
		@param var cameraInverseProj : Mat4;
		@param var cameraPos: Vec3;

		@param var intensity : Float;
		@param var colorMul : Float;
		@param var thickness : Float;
		@param var maxRoughness : Float;
		@param var minCosAngle : Float;
		@param var rayMarchingResolution : Float;

		@const var batchSample : Bool;

		function reflectedRay(ray : Vec3, normal : Vec3) : Vec3 {
			return ray - 2.0 * dot(ray, normal) * normal;
		}

		function getViewPos(uv:Vec2):Vec4 {
			var depth = depthMap.getLod(uv, 0).r;
			var ruv = vec4(uvToScreen(uv), depth, 1);
			var vpos = ruv * cameraInverseProj;
			return vpos / vpos.w;
		};

		function fromWposToVpos(wpos : Vec3 ) : Vec3 {
			var vpos = vec4(wpos, 1.0) * cameraView;
			return vpos.xyz / vpos.w;
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
			var viewNormal = normalize(fromWposToVpos(normal + cameraPos));
			var reflectedRay = reflectedRay(camDir, viewNormal);
			reflectedRay /= length(reflectedRay.xy);

			var startFrag = positionFrom * cameraProj;
			startFrag.xyz /= startFrag.w;
			startFrag.xy = screenToUv(startFrag.xy);
			startFrag.xy *= texSize;

			var fragDir = vec4(positionFrom.xyz + reflectedRay, 1.0) * cameraProj;
			fragDir.xyz /= fragDir.w;
			fragDir.xy = screenToUv(fragDir.xy);
			fragDir.xy *= texSize;
			fragDir.xy = normalize(fragDir.xy - startFrag.xy);

			var hit = 0;
			var increment = fragDir.xy / saturate(rayMarchingResolution);
			var frag = startFrag.xy + increment;
			var uv = frag / texSize;

			if (!batchSample) {
				do {
					var positionTo = getViewPos(uv);
					var viewStepLength = distance(positionTo.xy, positionFrom.xy);
					var viewDistance = positionFrom.z + reflectedRay.z * viewStepLength;
					var depth = viewDistance - positionTo.z;

					if (depth >= 0.0 && depth < thickness) {
						hit = 1;
						break;
					}

					frag += increment;
					uv = frag / texSize;

				} while (uv.x >= 0.0 && uv.x < 1.0 && uv.y >= 0.0 && uv.y < 1.0);
			}
			else {
				do {
					var results : Array<Bool, 4> = [false, false, false, false];
					@unroll
					for ( i in 0...4 ) {
						var positionTo = getViewPos(uv);
						var viewStepLength = distance(positionTo.xy, positionFrom.xy);
						var viewDistance = positionFrom.z + reflectedRay.z * viewStepLength;
						var depth = viewDistance - positionTo.z;
						results[i] = depth >= 0.0 && depth < thickness;
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
				} while (uv.x >= 0.0 && uv.x < 1.0 && uv.y >= 0.0 && uv.y < 1.0);
			}


			if (hit != 1)
				discard;

			var reflectionNormal = normalMap.get(uv).rgb;
			if (dot(reflectionNormal, normal) > minCosAngle || reflectionNormal.dot(reflectionNormal) <= 0)
				discard;

			var fragmentColor = hdrMap.get(uv).rgb;
			pixelColor = saturate(vec4(fragmentColor * colorMul, intensity * roughnessFactor));
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

	function new(parent, shared) {
		super(parent, shared);
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
			var t = r.ctx.engine.getCurrentTarget();
			ssrShader.texSize = new h3d.Vector((t == null ? r.ctx.engine.width : t.width), (t == null ? r.ctx.engine.height : t.height));
			ssrShader.colorMul = colorMul;
			ssrShader.intensity = intensity;
			ssrShader.thickness = thickness;
			ssrShader.maxRoughness = maxRoughness;
			ssrShader.minCosAngle = Math.cos(hxd.Math.degToRad(minAngle));
			ssrShader.rayMarchingResolution = rayMarchingResolution;
			var resRescale = 1.0;
			if ( !support4K )
				resRescale = hxd.Math.max(1.0, hxd.Math.max(ssrShader.texSize.x / 2560, ssrShader.texSize.y / 1440));
			ssrShader.rayMarchingResolution /= resRescale;
			ssrShader.batchSample = batchSample;

			ssrShader.cameraView = r.ctx.camera.mcam;
			ssrShader.cameraProj = r.ctx.camera.mproj;
			ssrShader.cameraInverseProj = r.ctx.camera.getInverseProj();
			ssrShader.cameraPos = r.ctx.camera.pos;

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
			</dl>
		</div>
		'),this);
	}
	#end

	static var _ = Prefab.register("rfx.ssr", SSR);

}

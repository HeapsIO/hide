package hrt.prefab2.rfx;

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

		var startRay : Vec2;

		var projectedPosition:Vec4;
		var pixelColor:Vec4;
		var transformedNormal : Vec3;
		var transformedPosition : Vec3;

		function rand(co : Vec2) : Float {
			return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
		}

		function reflectedRay(ray : Vec3, normal : Vec3) : Vec3 {
			return ray - 2.0 * dot(ray, normal) * normal;
		}

		var curPos : Vec2;
		function getDepths( worldPos : Vec3) : Vec2 {
			var projPos = vec4(worldPos, 1.0) * camera.viewProj;
			curPos = projPos.xy / projPos.w;
			var distToCam = projPos.z / projPos.w;
			return vec2(distToCam, depthMap.getLod(screenToUv(curPos), 0.0));
		}

		function fragment() {
			var depths = getDepths(transformedPosition);
			if ( depths.r > depths.g )
				discard;

			startRay = projectedPosition.xy / projectedPosition.w;

			var camDir = (transformedPosition - camera.position).normalize();
			var reflectedRay = reflectedRay(camDir, transformedNormal);

			var curPosWS = transformedPosition + reflectedRay * maxRayDistance / stepsFirstPass;
			var hitFirstPass = false;

			for (i in 0 ... stepsFirstPass) {
				depths = getDepths(curPosWS);
				var distToCam = depths.r;
				var curDepth = depths.g;
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

			if (hitFirstPass == false)
				discard;

			curPosWS -= reflectedRay * maxRayDistance / stepsFirstPass / stepsSecondPass;
			var hitSecondPass = false;
			for (i in 0 ... stepsSecondPass) {
				depths = getDepths(curPosWS);
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
				fragmentColor = ldrMap.getLod(screenToUv(curPos), 0.0).rgb;
				alpha = 1.0 - saturate(((curPosWS - transformedPosition).length() - startFadeDistance) / (maxRayDistance - startFadeDistance));
				alpha *= intensity;
			}

			pixelColor.rgba = saturate(vec4(fragmentColor * colorMul, pixelColor.a * alpha));
		}
	}
}

class ApplySSRShader extends h3d.shader.ScreenShader {
	static var SRC = {

		@param var ssrTexture : Sampler2D;

		@param var colorMul : Float;

		function fragment() {
			var ssr = ssrTexture.get(calculatedUV).rgba;
			var reflectedUV = ssr.rg;
			var alpha = ssr.a;

			pixelColor = ssrTexture.get(calculatedUV).rgba;
		}

	}
}


@:access(h3d.pass.PassList)
@:access(h3d.pass.PassObject)
@:access(h3d.scene.Renderer)
class SSR extends RendererFX {

	public var ssrShader : SSRShader;
	public var applySSRPass : h3d.pass.ScreenFx<ApplySSRShader>;
	var applySSRShader : ApplySSRShader;

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

	function new(?parent, shared: ContextShared) {
		super(parent, shared);

		ssrShader = new SSRShader();
		applySSRShader = new ApplySSRShader();
		applySSRPass = new h3d.pass.ScreenFx(applySSRShader);
		applySSRPass.pass.setBlendMode(Alpha);
		applySSRPass.pass.depthTest = Always;
	}

	var passes : h3d.pass.PassList;
	override function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		if( step == Decals) {
			r.mark("SSR");

			var ldrMap = r.ctx.getGlobal("ldrMap");
			ssrShader.ldrMap = ldrMap;

			ssrShader.colorMul = colorMul;
			ssrShader.intensity = intensity;
			ssrShader.maxRayDistance = maxRayDistance;
			ssrShader.startFadeDistance = startFadeDistance;
			ssrShader.stepsFirstPass = stepsFirstPass;
			ssrShader.stepsSecondPass = stepsSecondPass;
			ssrShader.thickness = thickness;

			passes = r.get("ssr");
			var pbrRenderer = Std.downcast(r, h3d.scene.pbr.Renderer);
			if ( pbrRenderer == null )
				return;
			@:privateAccess pbrRenderer.cullPasses(passes, function(col) return col.inFrustum(r.ctx.camera.frustum));
			var it = passes.current;
			while ( it != null ) {
				if ( it.pass.getShaderByName("hrt.prefab2.rfx.SSRShader") == null )
					it.pass.addShader(ssrShader);
				it = it.next;
			}

			if ( passes.current == null )
				return;
			ssr = r.allocTarget("ssr", false, textureSize, RGBA);
			ssr.clear(0, 0);
			r.ctx.engine.pushTarget(ssr);
			r.defaultPass.draw(passes);
			r.ctx.engine.popTarget();

			blurPass.radius = blurRadius;
			blurPass.apply(r.ctx, ssr);
		}

		if( step == Forward ) {
			if ( passes.current == null )
				return;
			r.mark("SSRApply");
			applySSRShader.colorMul = colorMul;
			applySSRShader.ssrTexture = ssr;
			applySSRPass.render();
		}
	}

	#if editor
	override function edit( ctx : hide.prefab2.EditContext ) {
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
				<dt>Blur radius</dt><dd><input type="range" min="0" max="5" field="blurRadius"/></dd>
				<dt>Texture size</dt><dd><input type="range" min="0" max="1" field="textureSize"/></dd>
			</dl>
		</div>
		'),this);
	}
	#end

	static var _ = Prefab.register("rfx.ssr", SSR);

}

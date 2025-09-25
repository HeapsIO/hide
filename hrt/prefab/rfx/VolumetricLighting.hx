package hrt.prefab.rfx;

class VolumetricLightingShader extends h3d.shader.pbr.DefaultForward {

	static var SRC = {

		@global var global : {
			var time : Float;
		}

		@param var invViewProj : Mat4;

		@param var intensity : Float;

		@param var noiseTurmoil : Float;
		@param var noiseScale : Float;
		@param var noiseLacunarity : Float;
		@param var noisePersistence : Float;
		@param var noiseSharpness : Float;
		@param var noiseOctave : Int;
		@param var noiseTex : Sampler2D;

		@param var halfDepthMap : Sampler2D;

		@param var steps : Int;
		@param var startDistance : Float;
		@param var endDistance : Float;
		@param var maxCamDist : Float = 0.0;
		@param var distanceOpacity : Float;

		@param var ditheringNoise : Sampler2D;
		@param var ditheringSize : Vec2;
		@param var targetSize : Vec2;
		@param var ditheringIntensity : Float;

		@param var color : Vec3;
		@param var fogDensity : Float;
		@param var fogUseNoise : Float;
		@param var fogBottom : Float;
		@param var fogTop : Float;
		@param var fogHeightFalloff : Float;
		@param var fogEnvPower : Float;
		@param var fogEnvColorMult : Float;

		@param var secondFogColor : Vec3;
		@param var secondFogDensity : Float;
		@param var secondFogUseNoise : Float;
		@param var secondFogBottom : Float;
		@param var secondFogTop : Float;
		@param var secondFogHeightFalloff : Float;

		@param var emissiveColor : Vec3;
		@param var emissiveIntensity : Float;

		@param var offsetCamHeight : Float;

		var calculatedUV : Vec2;

		function noise( pos : Vec3 ) : Float {
			var i = floor(pos);
    		var f = fract(pos);
			f = f*f*(3.0-2.0*f);
			var uv = (i.xy+vec2(37.0,239.0)*i.z) + f.xy;
			var rg = noiseTex.getLod( (uv+0.5) / 256.0, 0 ).yx;
			return mix( rg.x, rg.y, f.z );
		}

		function noiseAt( pos : Vec3 ) : Float {
			var amount = 0.;
			if ( noiseOctave > 0 ) {
				var p = pos * 0.1 * noiseScale;
				var t = global.time * noiseTurmoil;
				amount += noise(p - t * vec3(0, 0, 1));
				var tot = 1.;
				var k = noisePersistence;
				p *= noiseLacunarity;
				if ( noiseOctave >= 2 ) {
					amount += noise(p + t * vec3(0, 0, -0.6)) * k;
					k *= noisePersistence;
					p *= noiseLacunarity;
					tot += k;
				}
				if ( noiseOctave >= 3 ) {
					amount += noise(p + t * vec3(-0.9, 0, 1.1)) * k;
					k *= noisePersistence;
					p *= noiseLacunarity;
					tot += k;
				}
				if ( noiseOctave >= 4 ) {
					amount += noise(p + t * vec3(0.8, 0.95,-1.2)) * k;
					k *= noisePersistence;
					p *= noiseLacunarity;
					tot += k;
				}

				if ( noiseOctave >= 5 ) {
					amount += noise(p + t * vec3(0,-0.84,-1.3)) * k;
					tot += k;
					p *= noiseLacunarity;
					k *= noisePersistence;
					tot += k;
				}
				amount = pow(amount / tot, noiseSharpness);
			} else {
				amount = 1.0;
			}
			return amount;
		}

		function indirectLighting() : Vec3 {
			return envColor * irrPower * fogEnvPower;
		}

		function getFogColor() : Vec3 {
			return mix(color, secondFogColor, useSecondColor);
		}

		function directLighting(lightColor : Vec3, lightDirection : Vec3) : Vec3 {
			return lightColor;
		}

		function pointLightIntensity( delta : Vec3, size : Float, invRange4 : Float ) : Float {
			var dist = delta.dot(delta);
			var falloff = saturate(1 - dist*dist * invRange4);
			if( size > 0 ) {
				dist = (dist.sqrt() - size).max(0.);
				dist *= dist;
			}
			falloff *= falloff;
			return falloff * falloff * exp(-extinction * dist);
		}

		var skipShadow : Bool = false;
		function evaluateCascadeShadow() : Float {
			var i = cascadeLightStride;
			var shadow = 1.0;
			var shadowProj = mat3x4(lightInfos[i + 2], lightInfos[i + 3], lightInfos[i + 4]);

			@unroll for ( c in 0...CASCADE_COUNT ) {
				var cascadeScale = lightInfos[i + 5 + 2 * c];
				var shadowPos0 = transformedPosition * shadowProj;
				var shadowPos = i == 0 ? shadowPos0 : shadowPos0 * cascadeScale.xyz + lightInfos[i + 6 + 2 * c].xyz;
				if ( inside(shadowPos) ) {
					var zMax = saturate(shadowPos.z);
					var shadowUv = shadowPos.xy;
					shadowUv.y = 1.0 - shadowUv.y;
					var depth = cascadeShadowMaps[c].get(shadowUv.xy).r;
					shadow -= zMax > depth ? 1.0 : 0.0;
				}
			}

			return skipShadow ? 1.0 : saturate(shadow);
		}

		var useSecondColor : Float;
		function fogAt(pos : Vec3) : Float {
			var n = noiseAt(pos);
			var camOffset = offsetCamHeight * camera.position.z;
			var finalFogTop = fogTop + camOffset;
			var hNorm = smoothstep(0.0, 1.0, (pos.z - fogBottom) / (finalFogTop - fogBottom));
			var firstFog = exp(-hNorm * fogHeightFalloff) * (1.0 - hNorm) * fogDensity;

			var finalSecondFogTop = secondFogTop + camOffset;
			var secondHNorm = smoothstep(0.0, 1.0, (pos.z - secondFogBottom) / (finalSecondFogTop - secondFogBottom));
			var secondFog = exp(-secondHNorm * secondFogHeightFalloff) * (1.0 - secondHNorm) * secondFogDensity;
			firstFog *= mix(1.0, n, fogUseNoise);
			secondFog *= mix(1.0, n, secondFogUseNoise);

			useSecondColor = saturate(secondFog / max(firstFog, secondFog));
			return max(firstFog, secondFog);
		}

		function getWPos() : Vec3 {
			var depth = halfDepthMap.get( fragCoord.xy / halfDepthMap.size() ).r;
			var uv2 = uvToScreen(calculatedUV);
			var temp = vec4(uv2, depth, 1) * invViewProj;
			return temp.xyz / temp.w;
		}

		function getDistBlend(dist: Float) : Float {
			var dfactor = smoothstep(0, 1, dist / endDistance);
			return dfactor * dfactor;
		}

		function integrateStep(stepSize : Float, integrationValues : Vec4) : Vec4 {
			extinction = fogAt(transformedPosition);
			var clampedExtinction = max(extinction, 1e-5);
			var transmittance = exp(-extinction*stepSize);

			var emissiveLum = emissiveIntensity * emissiveColor;
			var luminance = (evaluateLighting() * getFogColor() * mix(vec3(1.0), saturate(envColor), fogEnvColorMult) + emissiveLum) * extinction;
			var integScatt = (luminance - luminance*transmittance) / clampedExtinction;

			integrationValues.rgb += integrationValues.a * integScatt;
			integrationValues.a *= transmittance;

			return integrationValues;
		}

		var camDir : Vec3;
		var envColor : Vec3;
		var extinction : Float;
		var curDist = 0.0;
		function rayMarch() : Vec4 {
			metalness = 0.0;
			emissive = 0.0;
			albedoGamma = vec3(0.0);
			useSecondColor = 0.0;

			var endPos = getWPos();
			camDir = normalize(endPos - camera.position);
			var startPos = camera.position + camDir * startDistance;
			var cameraDistance = length(endPos - startPos);
			if ( dot(camDir, endPos - startPos) < 0.0 )
				discard;
			if ( maxCamDist > 0.0 )
				cameraDistance = min(cameraDistance, maxCamDist);

			envColor = irrDiffuse.getLod(-camDir, 0.0).rgb;
			view = -camDir;

			var stepSize = cameraDistance / float(steps);
			var dithering = ditheringNoise.getLod(calculatedUV * targetSize / ditheringSize, 0.0).r * stepSize * ditheringIntensity;
			startPos += dithering * camDir;

			var integrationValues = vec4(0.0,0.0,0.0,1.0);
			skipShadow = false;
			var transmittanceThreshold = 1e-3;
			for ( i in 0...steps ) {
				transformedPosition = startPos + camDir * curDist;
				if ( integrationValues.a < transmittanceThreshold ) break;
				integrationValues = integrateStep(stepSize, integrationValues);
				curDist += stepSize;
			}

			stepSize = length(endPos - startPos) - curDist;
			if(integrationValues.a > transmittanceThreshold && stepSize > 0.0){
				curDist += stepSize;
				skipShadow = true;
				transformedPosition = startPos + camDir * curDist;
				integrationValues = integrateStep(stepSize, integrationValues);
			}
			if(integrationValues.a < transmittanceThreshold) integrationValues.a = 0.0;

			integrationValues.a = 1.0 - integrationValues.a;
			integrationValues.a = saturate(distanceOpacity * integrationValues.a);

			return integrationValues;
		}

		function fragment() {
			pixelColor.rgba = mix(pixelColor.rgba, rayMarch().rgba, intensity);
		}
	}
}

@:access(h3d.scene.Renderer)
class VolumetricLighting extends RendererFX {

	var pass = new h3d.pass.ScreenFx(new h3d.shader.ScreenShader());
	var halfingDepthPass = new h3d.pass.ScreenFx(new h3d.shader.CheckerboardDepth() );
	var upsamplingPass = new h3d.pass.ScreenFx(new h3d.shader.DepthAwareUpsampling());

	var blurPass = new h3d.pass.Blur();
	var vshader = new VolumetricLightingShader();

	@:s public var intensity : Float = 1.0;

	@:s public var AFTER_FX : Bool = false;
	@:s public var blend : h3d.mat.PbrMaterial.PbrBlend = Alpha;
	@:s public var color : Int = 0xFFFFFF;
	@:s public var steps : Int = 10;
	@:s public var blur : Float = 0.0;
	@:s public var blurDepthThreshold : Float = 10.0;
	@:s public var startDistance : Float = 0.0;
	@:s public var endDistance : Float = 200.0;
	@:s public var maxCamDist : Float = 0.0;
	@:s public var distanceOpacity : Float = 1.0;
	@:s public var ditheringIntensity : Float = 1.0;

	@:s public var noiseScale : Float = 1.0;
	@:s public var noiseLacunarity : Float = 2.0;
	@:s public var noiseSharpness : Float = 1.0;
	@:s public var noisePersistence : Float = 0.5;
	@:s public var noiseTurmoil : Float = 1.0;
	@:s public var noiseOctave : Int = 1;

	@:s public var fogDensity : Float = 1.0;
	@:s public var fogUseNoise : Float = 1.0;
	@:s public var fogHeightFalloff : Float = 1.0;
	@:s public var fogEnvPower : Float = 1.0;
	@:s public var fogBottom : Float = 0.0;
	@:s public var fogTop : Float = 200.0;
	@:s public var fogEnvColorMult : Float = 0.0;

	@:s public var secondFogColor : Int = 0xFFFFFF;
	@:s public var secondFogUseNoise : Float = 1.0;
	@:s public var secondFogDensity : Float = 0.0;
	@:s public var secondFogHeightFalloff : Float = 5.0;
	@:s public var secondFogBottom : Float = 0.0;
	@:s public var secondFogTop : Float = 50.0;

	@:s public var emissiveColor : Int = 0xFFFFFF;
	@:s public var emissiveIntensity : Float = 0.0;

	@:s public var offsetCamHeight : Bool = false;

	var noiseTex : h3d.mat.Texture;

	function execute(r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step) {
		if( step == BeforeTonemapping ) {
			if ( distanceOpacity <= 0.0 )
				return;

			var r = cast(r, h3d.scene.pbr.Renderer);
			r.mark("VolumetricLighting");

			if ( noiseTex == null )
				noiseTex = makeNoiseTex();

			var depth = r.textures.albedo.depthBuffer;

			var prevFilter = depth.filter;
			depth.filter = Nearest;

			var halfDepth = r.allocTarget("halfDepth", false, 0.5, R32F);
			halfDepth.filter = Nearest;
			r.ctx.engine.pushTarget(halfDepth);
			halfingDepthPass.shader.source = depth;
			halfingDepthPass.shader.texRatio = 2.0;
			halfingDepthPass.render();
			r.ctx.engine.popTarget();

			var tex = r.allocTarget("volumetricLighting", false, 0.5, RGBA16F);
			tex.clear(0, 0.0);
			r.ctx.engine.pushTarget(tex);

			vshader.USE_INDIRECT = false;
			if ( pass.getShader(h3d.shader.pbr.DefaultForward) == null )
				pass.addShader(vshader);
			var ls = cast(r.getLightSystem(), h3d.scene.pbr.LightSystem);
			ls.lightBuffer.setBuffers(vshader);
			vshader.halfDepthMap = halfDepth;
			vshader.startDistance = startDistance;
			vshader.endDistance = endDistance;
			vshader.maxCamDist = maxCamDist;
			vshader.distanceOpacity = distanceOpacity;
			vshader.steps = steps;
			vshader.invViewProj = r.ctx.camera.getInverseViewProj();
			if ( vshader.ditheringNoise == null ) {
				// can't wrap the following code in a method in h3d.Engine because of macro.
				var resCache = @:privateAccess r.ctx.engine.resCache;
				var t : h3d.mat.Texture = resCache.get("hrt/prefab/rfx/blueNoise.png");
				if ( t == null ) {
					t = hxd.res.Embed.getResource("hrt/prefab/rfx/blueNoise.png").toImage().toTexture();
					resCache.set("hrt/prefab/rfx/blueNoise.png", t);
				}
				vshader.ditheringNoise = t;
				vshader.ditheringNoise.wrap = Repeat;
			}
			vshader.targetSize.set(tex.width, tex.height);
			vshader.ditheringSize.set(vshader.ditheringNoise.width, vshader.ditheringNoise.height);
			vshader.ditheringIntensity = ditheringIntensity;
			vshader.noiseTex = noiseTex;
			vshader.noiseScale = noiseScale;
			vshader.noiseOctave = noiseOctave;
			vshader.noiseTurmoil = noiseTurmoil;
			vshader.noiseSharpness = noiseSharpness;
			vshader.noisePersistence = noisePersistence;
			vshader.noiseLacunarity = noiseLacunarity;
			vshader.fogEnvPower = fogEnvPower;

			vshader.color.load(h3d.Vector.fromColor(color));
			vshader.fogDensity = fogDensity * 0.002;
			vshader.fogUseNoise = fogUseNoise;
			vshader.fogBottom = fogBottom;
			vshader.fogTop = fogTop;
			vshader.fogEnvColorMult = fogEnvColorMult;
			vshader.fogHeightFalloff = fogHeightFalloff;

			vshader.secondFogColor.load(h3d.Vector.fromColor(secondFogColor));
			vshader.secondFogDensity = secondFogDensity * 0.002;
			vshader.secondFogUseNoise = secondFogUseNoise;
			vshader.secondFogBottom = secondFogBottom;
			vshader.secondFogTop = secondFogTop;
			vshader.secondFogHeightFalloff = secondFogHeightFalloff;

			vshader.emissiveColor.load(h3d.Vector.fromColor(emissiveColor));
			vshader.emissiveIntensity = emissiveIntensity;

			vshader.offsetCamHeight = offsetCamHeight ? 1.0 : 0.0;

			vshader.intensity = intensity;

			pass.pass.setBlendMode(Alpha);
			pass.render();

			r.ctx.engine.popTarget();

			var inverseProj = r.ctx.camera.getInverseProj();

			blurPass.radius = blur;
			blurPass.shader.isDepthDependant = true;
			blurPass.shader.depthTexture = halfDepth;
			blurPass.shader.inverseProj = inverseProj;
			blurPass.shader.depthThreshold = blurDepthThreshold;
			blurPass.apply(r.ctx, tex);

			var b : h3d.mat.BlendMode = switch ( blend ) {
			case None: None;
			case Alpha: Alpha;
			case Add: Add;
			case AlphaAdd: AlphaAdd;
			case Multiply: Multiply;
			case AlphaMultiply: AlphaMultiply;
			}

			r.ctx.engine.pushTarget(r.textures.hdr, 0, 0, NotBound);
			upsamplingPass.pass.setBlendMode(b);
			upsamplingPass.shader.source = tex;
			upsamplingPass.shader.sourceDepth = halfDepth;
			upsamplingPass.shader.destDepth = depth;
			upsamplingPass.shader.inverseProj = inverseProj;
			upsamplingPass.render();
			r.ctx.engine.popTarget();

			depth.filter = prevFilter;
		}
	}

	override function begin(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if ( !AFTER_FX )
			execute(r, step);
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if ( AFTER_FX )
			execute(r, step);
	}

	function makeNoiseTex() : h3d.mat.Texture {
		var rands : Array<Int> = [];
		var rand = new hxd.Rand(0);
		for(x in 0...256)
			for(y in 0...256)
				rands.push(rand.random(256));
		var pix = hxd.Pixels.alloc(256, 256, RGBA);
		for(x in 0...256) {
			for(y in 0...256) {
				var r = rands[x + y * 256];
				var g = rands[((x - 37) & 255) + ((y - 239) & 255) * 256];
				var off = (x + y*256) * 4;
				pix.bytes.set(off, r);
				pix.bytes.set(off+1, g);
				pix.bytes.set(off+3, 255);
			}
		}
		var tex = new h3d.mat.Texture(pix.width, pix.height, [], RGBA);
		tex.uploadPixels(pix);
		tex.wrap = Repeat;
		return tex;
	}

	override function modulate(t : Float) {
		var c : VolumetricLighting = cast super.modulate(t);
		c.intensity = this.intensity * t;
		return c;
	}

	override function transition( r1 : h3d.impl.RendererFX, r2 : h3d.impl.RendererFX ) : h3d.impl.RendererFX.RFXTransition {
		var v1 : VolumetricLighting = cast r1;
		var v2 : VolumetricLighting = cast r2;
		var v = new VolumetricLighting(null, null);

		v.intensity = v1.intensity;
		v.steps = v1.steps;
		v.blur = v1.blur;
		v.blurDepthThreshold = v1.blurDepthThreshold;
		v.startDistance = v1.startDistance;
		v.endDistance = v1.endDistance;
		v.maxCamDist = v1.maxCamDist;
		v.distanceOpacity = v1.distanceOpacity;
		v.ditheringIntensity = v1.ditheringIntensity;
		v.noiseScale = v1.noiseScale;
		v.noiseLacunarity = v1.noiseLacunarity;
		v.noiseSharpness = v1.noiseSharpness;
		v.noisePersistence = v1.noisePersistence;
		v.noiseTurmoil = v1.noiseTurmoil;
		v.noiseOctave = v1.noiseOctave;
		v.fogDensity = v1.fogDensity;
		v.fogUseNoise = v1.fogUseNoise;
		v.fogHeightFalloff = v1.fogHeightFalloff;
		v.fogEnvPower = v1.fogEnvPower;
		v.fogBottom = v1.fogBottom;
		v.fogTop = v1.fogTop;
		v.fogEnvColorMult = v1.fogEnvColorMult;
		v.secondFogUseNoise = v1.secondFogUseNoise;
		v.secondFogDensity = v1.secondFogDensity;
		v.secondFogHeightFalloff = v1.secondFogHeightFalloff;
		v.secondFogBottom = v1.secondFogBottom;
		v.secondFogTop = v1.secondFogTop;
		v.emissiveIntensity = v1.emissiveIntensity;

		v.color = v1.color;
		v.secondFogColor = v1.secondFogColor;
		v.emissiveColor = v1.emissiveColor;
		v.AFTER_FX = v1.AFTER_FX;
		v.offsetCamHeight = v1.offsetCamHeight;
		v.blend = v1.blend;

		return { effect : cast v, setFactor : (f : Float) -> {
			v.intensity = hxd.Math.lerp(v1.intensity, v2.intensity, f);
			v.steps = Std.int(hxd.Math.lerp(v1.steps, v2.steps, f));
			v.blur = hxd.Math.lerp(v1.blur, v2.blur, f);
			v.blurDepthThreshold = hxd.Math.lerp(v1.blurDepthThreshold, v2.blurDepthThreshold, f);
			v.startDistance = hxd.Math.lerp(v1.startDistance, v2.startDistance, f);
			v.endDistance = hxd.Math.lerp(v1.endDistance, v2.endDistance, f);
			v.maxCamDist = hxd.Math.lerp(v1.maxCamDist, v2.maxCamDist, f);
			v.distanceOpacity = hxd.Math.lerp(v1.distanceOpacity, v2.distanceOpacity, f);
			v.ditheringIntensity = hxd.Math.lerp(v1.ditheringIntensity, v2.ditheringIntensity, f);
			v.noiseScale = hxd.Math.lerp(v1.noiseScale, v2.noiseScale, f);
			v.noiseLacunarity = hxd.Math.lerp(v1.noiseLacunarity, v2.noiseLacunarity, f);
			v.noiseSharpness = hxd.Math.lerp(v1.noiseSharpness, v2.noiseSharpness, f);
			v.noisePersistence = hxd.Math.lerp(v1.noisePersistence, v2.noisePersistence, f);
			v.noiseTurmoil = hxd.Math.lerp(v1.noiseTurmoil, v2.noiseTurmoil, f);
			v.noiseOctave = Std.int(hxd.Math.lerp(v1.noiseOctave, v2.noiseOctave, f));
			v.fogDensity = hxd.Math.lerp(v1.fogDensity, v2.fogDensity, f);
			v.fogUseNoise = hxd.Math.lerp(v1.fogUseNoise, v2.fogUseNoise, f);
			v.fogHeightFalloff = hxd.Math.lerp(v1.fogHeightFalloff, v2.fogHeightFalloff, f);
			v.fogEnvPower = hxd.Math.lerp(v1.fogEnvPower, v2.fogEnvPower, f);
			v.fogBottom = hxd.Math.lerp(v1.fogBottom, v2.fogBottom, f);
			v.fogTop = hxd.Math.lerp(v1.fogTop, v2.fogTop, f);
			v.fogEnvColorMult = hxd.Math.lerp(v1.fogEnvColorMult, v2.fogEnvColorMult, f);
			v.secondFogUseNoise = hxd.Math.lerp(v1.secondFogUseNoise, v2.secondFogUseNoise, f);
			v.secondFogDensity = hxd.Math.lerp(v1.secondFogDensity, v2.secondFogDensity, f);
			v.secondFogHeightFalloff = hxd.Math.lerp(v1.secondFogHeightFalloff, v2.secondFogHeightFalloff, f);
			v.secondFogBottom = hxd.Math.lerp(v1.secondFogBottom, v2.secondFogBottom, f);
			v.secondFogTop = hxd.Math.lerp(v1.secondFogTop, v2.secondFogTop, f);
			v.emissiveIntensity = hxd.Math.lerp(v1.emissiveIntensity, v2.emissiveIntensity, f);

			function lerpColor(c1 : Int, c2 : Int, f : Float) {
				var color1 = hrt.impl.ColorSpace.Color.fromInt(c1);
				var color2 = hrt.impl.ColorSpace.Color.fromInt(c2);

				var res = new hrt.impl.ColorSpace.Color();
				res.a = hxd.Math.ceil(hxd.Math.lerp(color1.a, color2.a, f));
				res.r = hxd.Math.ceil(hxd.Math.lerp(color1.r, color2.r, f));
				res.g = hxd.Math.ceil(hxd.Math.lerp(color1.g, color2.g, f));
				res.b = hxd.Math.ceil(hxd.Math.lerp(color1.b, color2.b, f));
				return res.toInt(true);
			}

			v.color = lerpColor(v1.color, v2.color, f);
			v.secondFogColor = lerpColor(v1.secondFogColor, v2.secondFogColor, f);
			v.emissiveColor = lerpColor(v1.emissiveColor, v2.emissiveColor, f);
			v.AFTER_FX = f < 0.5 ? v1.AFTER_FX : v2.AFTER_FX;
			v.offsetCamHeight = f < 0.5 ? v1.offsetCamHeight : v2.offsetCamHeight;
			v.blend = f < 0.5 ? v1.blend : v2.blend;
		} };
	}

	#if editor

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
		ctx.properties.add(new hide.Element(
			'<div class="group" name="Fog">
				<dl>
					<dt>Intensity</dt><dd><input type="range" min="0" max="1" field="intensity"/></dd>
					<dt>Blend</dt>
					<dd>
						<select field="blend">
							<option value="None">None</option>
							<option value="Alpha">Alpha</option>
							<option value="Add">Add</option>
							<option value="AlphaAdd">AlphaAdd</option>
							<option value="Multiply">Multiply</option>
							<option value="AlphaMultiply">AlphaMultiply</option>
						</select>
					</dd>
					<dt>After fx</dt><dd><input type="checkbox" field="AFTER_FX"/></dd>
					<dt>Begin</dt><dd><input type="range" min="0" field="startDistance"/></dd>
					<dt>Start distance</dt><dd><input type="range" min="0" field="startDistance"/></dd>
					<dt>End distance</dt><dd><input type="range" min="0" field="endDistance"/></dd>
					<dt>Distance opacity</dt><dd><input type="range" min="0" max="1" field="distanceOpacity"/></dd>
					<dt>Env power</dt><dd><input type="range" min="0" max="2" field="fogEnvPower"/></dd>
					<dt>Env color mult</dt><dd><input type="range" min="0" max="1" field="fogEnvColorMult"/></dd>
					<dt>Color</dt><dd><input type="color" field="color"/></dd>
					<dt>Density</dt><dd><input type="range" min="0" max="2" field="fogDensity"/></dd>
					<dt>Use noise</dt><dd><input type="range" min="0" max="1" field="fogUseNoise"/></dd>
					<dt>Bottom [m]</dt><dd><input type="range" min="0" max="1000" field="fogBottom"/></dd>
					<dt>Top [m]</dt><dd><input type="range" min="0" max="1000" field="fogTop"/></dd>
					<dt>Height falloff</dt><dd><input type="range" min="0" max="3" field="fogHeightFalloff"/></dd>
					<dt>Follow Camera Height</dt><dd><input type="checkbox" field="offsetCamHeight"/></dd>
				</dl>
			</div>
			<div class="group" name="Second fog">
				<dl>
					<dt>Color</dt><dd><input type="color" field="secondFogColor"/></dd>
					<dt>Density</dt><dd><input type="range" min="0" max="2" field="secondFogDensity"/></dd>
					<dt>Use noise</dt><dd><input type="range" min="0" max="1" field="secondFogUseNoise"/></dd>
					<dt>Bottom [m]</dt><dd><input type="range" min="0" max="1000" field="secondFogBottom"/></dd>
					<dt>Top [m]</dt><dd><input type="range" min="0" max="1000" field="secondFogTop"/></dd>
					<dt>Height falloff</dt><dd><input type="range" min="0" max="3" field="secondFogHeightFalloff"/></dd>
				</dl>
			</div>
			<div class="group" name="Emissive">
				<dl>
					<dt>Emissive color</dt><dd><input type="color" field="emissiveColor"/></dd>
					<dt>Emissive Intensity</dt><dd><input type="range" min="0" max="1" field="emissiveIntensity"/></dd>
				</dl>
			</div>
			<div class="group" name="Noise">
				<dl>
					<dt><font color=#FF0000>Octaves</font></dt><dd><input type="range" step="1" min="0" max="4" field="noiseOctave"/></dd>
					<dt>Scale</dt><dd><input type="range" min="0" max="100" field="noiseScale"/></dd>
					<dt>Turmoil</dt><dd><input type="range" min="0" max="100" field="noiseTurmoil"/></dd>
					<dt>Persistence</dt><dd><input type="range" min="0" max="1" field="noisePersistence"/></dd>
					<dt>Lacunarity</dt><dd><input type="range" min="0" max="2" field="noiseLacunarity"/></dd>
					<dt>Sharpness</dt><dd><input type="range" min="0" max="2" field="noiseSharpness"/></dd>
				</dl>
			</div>
			<div class="group" name="Rendering">
				<dl>
					<dt><font color=#FF0000>Steps</font></dt><dd><input type="range" step="1" min="0" max="255" field="steps"/></dd>
					<dt>Blur</dt><dd><input type="range" step="1" min="0" max="100" field="blur"/></dd>
					<dt>Blur depth threshold</dt><dd><input type="range" field="blurDepthThreshold"/></dd>
					<dt>Dithering intensity</dt><dd><input type="range" min="0" max="1" field="ditheringIntensity"/></dd>
					<dt>Fog quality distance</dt><dd><input type="range" min="0" max="200" field="maxCamDist"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}

	#end

	static var _ = Prefab.register("rfx.volumetricLighting", VolumetricLighting);

}
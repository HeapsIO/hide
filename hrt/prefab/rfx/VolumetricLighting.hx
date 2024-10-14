package hrt.prefab.rfx;

class VolumetricLightingShader extends h3d.shader.pbr.DefaultForward {

	static var SRC = {

		@global var global : {
			var time : Float;
		}

		@param var invViewProj : Mat4;

		@param var noiseTurmoil : Float;
		@param var noiseScale : Float;
		@param var noiseLacunarity : Float;
		@param var noisePersistence : Float;
		@param var noiseSharpness : Float;
		@param var noiseOctave : Int;
		@param var noiseTex : Sampler2D;

		@param var depthMap : Sampler2D;

		@param var steps : Int;
		@param var startDistance : Float;
		@param var endDistance : Float;
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

		var calculatedUV : Vec2;
		var depthInvDimensions : Vec2;

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
			return pow(amount / tot, noiseSharpness);
		}

		function indirectLighting() : Vec3 {
			return envColor * irrPower * fogEnvPower;
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
			return falloff * falloff * exp(-fog * dist);
		}

		var useSecondColor : Float;
		function fogAt(pos : Vec3) : Float {
			var n = noiseAt(pos);
			var hNorm = smoothstep(0.0, 1.0, (pos.z - fogBottom) / (fogTop - fogBottom));
			var firstFog = exp(-hNorm * fogHeightFalloff) * (1.0 - hNorm) * fogDensity;

			var secondHNorm = smoothstep(0.0, 1.0, (pos.z - secondFogBottom) / (secondFogTop - secondFogBottom));
			var secondFog = exp(-secondHNorm * secondFogHeightFalloff) * (1.0 - secondHNorm) * secondFogDensity;
			firstFog *= mix(1.0, n, fogUseNoise);
			secondFog *= mix(1.0, n, secondFogUseNoise);

			useSecondColor = saturate(secondFog / max(firstFog, secondFog));
			return max(firstFog, secondFog);
		}

		function getWPos() : Vec3 {
			var pixels = fragCoord.xy;
			var depth = depthMap.get( pixels * depthInvDimensions ).r;
			var uv2 = uvToScreen(calculatedUV);
			var temp = vec4(uv2, depth, 1) * invViewProj;
			return temp.xyz / temp.w;
		}

		function getDistBlend(dist: Float) : Float {
			var dfactor = smoothstep(0, 1, dist / endDistance);
			return dfactor * dfactor;
		}

		var camDir : Vec3;
		var envColor : Vec3;
		var fog : Float;
		function fragment() {
			metalness = 0.0;
			emissive = 0.0;
			albedoGamma = vec3(0.0);
			useSecondColor = 0.0;

			depthInvDimensions = 1.0 / depthMap.size();
			var endPos = getWPos();

			camDir = normalize(endPos - camera.position);
			var startPos = camera.position + camDir * startDistance;
			var cameraDistance = length(endPos - startPos);
			if ( dot(camDir, endPos - startPos) < 0.0 )
				discard;
			endPos = startPos + camDir * cameraDistance;

			envColor = irrDiffuse.getLod(camDir, 0.0).rgb;
			view = -camDir;

			var stepSize = length(endPos - startPos) / float(steps);
			var dithering = ditheringNoise.getLod(calculatedUV * targetSize / ditheringSize, 0.0).r * stepSize * ditheringIntensity;
			startPos += dithering * camDir;
			var opacity = 0.0;
			var totalScattered = vec3(0.0);
			var opticalDepth = 0.0;
			pixelColor = vec4(1.0);
			var colorAcc = vec4(0.0);
			var curDist = 0.0;
			for ( i in 0...steps ) {
				if ( colorAcc.a > 0.99 )
					break;
				transformedPosition = startPos + camDir * curDist;
				fog = fogAt(transformedPosition);
				var fColor = mix(color, secondFogColor, useSecondColor);
				var stepColor = evaluateLighting() * fColor * mix(vec3(1.0), saturate(envColor), fogEnvColorMult);

				var stepColor = vec4(stepColor * fog, fog);

				colorAcc += stepColor * (1.0 - colorAcc.a) * getDistBlend(curDist) * stepSize;

				curDist += stepSize;
			}
			pixelColor.rgb = colorAcc.rgb /= (0.001 + colorAcc.a);
			pixelColor.a = saturate(distanceOpacity * colorAcc.a);
		}
	};
}

@:access(h3d.scene.Renderer)
class VolumetricLighting extends RendererFX {

	var pass = new h3d.pass.ScreenFx(new h3d.shader.ScreenShader());
	var halfingDepthPass = new h3d.pass.ScreenFx(new h3d.shader.CheckerboardDepth() );
	var upsamplingPass = new h3d.pass.ScreenFx(new h3d.shader.DepthAwareUpsampling());

	var blurPass = new h3d.pass.Blur();
	var vshader = new VolumetricLightingShader();

	@:s public var blend : h3d.mat.PbrMaterial.PbrBlend = Alpha;
	@:s public var color : Int = 0xFFFFFF;
	@:s public var steps : Int = 10;
	@:s public var blur : Float = 0.0;
	@:s public var startDistance : Float = 0.0;
	@:s public var endDistance : Float = 200.0;
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

	var noiseTex : h3d.mat.Texture;

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( step == BeforeTonemapping ) {
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
			vshader.depthMap = halfDepth;
			vshader.startDistance = startDistance;
			vshader.endDistance = endDistance;
			vshader.distanceOpacity = distanceOpacity;
			vshader.steps = steps;
			vshader.invViewProj = r.ctx.camera.getInverseViewProj();
			if ( vshader.ditheringNoise == null ) {
				vshader.ditheringNoise = hxd.res.Embed.getResource("hrt/prefab/rfx/blueNoise.png").toImage().toTexture();
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
			pass.pass.setBlendMode(Alpha);
			pass.render();

			r.ctx.engine.popTarget();

			var inverseProj = r.ctx.camera.getInverseProj();

			blurPass.radius = blur;
			blurPass.shader.isDepthDependant = true;
			blurPass.shader.depthTexture = halfDepth;
			blurPass.shader.inverseProj = inverseProj;
			blurPass.shader.depthThreshold = 10;
			blurPass.apply(r.ctx, tex);

			var b : h3d.mat.BlendMode = switch ( blend ) {
			case None: None;
			case Alpha: Alpha;
			case Add: Add;
			case AlphaAdd: AlphaAdd;
			case Multiply: Multiply;
			case AlphaMultiply: AlphaMultiply;
			}

			upsamplingPass.pass.setBlendMode(b);
			upsamplingPass.shader.source = tex;
			upsamplingPass.shader.sourceDepth = halfDepth;
			upsamplingPass.shader.destDepth = depth;
			upsamplingPass.shader.inverseProj = inverseProj;
			upsamplingPass.render();

			depth.filter = prevFilter;
		}
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

	#if editor

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
		ctx.properties.add(new hide.Element(
			'<div class="group" name="Fog">
				<dl>
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
			<div class="group" name="Noise">
				<dl>
					<dt><font color=#FF0000>Octaves</font></dt><dd><input type="range" step="1" min="1" max="4" field="noiseOctave"/></dd>
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
					<dt>Dithering intensity</dt><dd><input type="range" min="0" max="1" field="ditheringIntensity"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}

	#end

	static var _ = Prefab.register("rfx.volumetricLighting", VolumetricLighting);

}
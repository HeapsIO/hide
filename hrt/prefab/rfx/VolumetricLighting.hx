package hrt.prefab.rfx;

class VolumetricLightingShader extends h3d.shader.pbr.DefaultForward {

	static var SRC = {

		@global var global : {
			var time : Float;
		}

		@global var camera : {
			var position : Vec3;
			var inverseViewProj : Mat4;
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
		@param var color : Vec3;
		@param var startDistance : Float;
		@param var endDistance : Float;
		@param var distanceOpacity : Float;

		@param var ditheringNoise : Sampler2D;
		@param var ditheringSize : Vec2;
		@param var targetSize : Vec2;
		@param var ditheringIntensity : Float;


		@param var fogDensity : Float;
		@param var fogBottom : Float;
		@param var fogTop : Float;
		@param var fogHeightFalloff : Float;
		@param var fogEnvPower : Float;

		var calculatedUV : Vec2;
		function getPosition() : Vec3 {
			var depth = depthMap.get(calculatedUV).r;
			var uv2 = uvToScreen(calculatedUV);
			var temp = vec4(uv2, depth, 1) * invViewProj;
			var originWS = temp.xyz / temp.w;
			return originWS;
		}

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
			return irrDiffuse.getLod(vec3(0.5), 0.0).rgb * irrPower * fogEnvPower;
		}

		function directLighting(lightColor : Vec3, lightDirection : Vec3) : Vec3 {
			return lightColor;
		}

		function fragment() {
			metalness = 0.0;
			emissive = 0.0;
			albedoGamma = vec3(0.0);
			var wPos = getPosition();
			var cameraDistance = length(wPos - camera.position);
			var camDir = normalize(wPos - camera.position);
			view = -camDir;

			if ( cameraDistance < startDistance )
				discard;
			var startPos = camera.position + camDir * startDistance;
			var endPos = camera.position + camDir * min(cameraDistance, endDistance);
			var opacity = 0.0;
			var stepSize = 1.0 / float(steps) * length(endPos - startPos) / (endDistance - startDistance);
			var dithering = ditheringNoise.getLod(calculatedUV * targetSize / ditheringSize, 0.0).r;
			dithering = dithering * ditheringIntensity;
			pixelColor.rgb = vec3(0.0);
			var totalScattered = vec3(0.0);
			var opticalDepth = 0.0;
			for ( i in 0...steps ) {
				transformedPosition = mix(startPos, endPos, (float(i) + dithering) / float(steps));

				var hNorm = smoothstep(0.0, 1.0, (transformedPosition.z - fogBottom) / (fogTop - fogBottom));
				var density = noiseAt(transformedPosition) * exp(-hNorm * fogHeightFalloff) * (1.0 - hNorm);
				density *= stepSize;

				var l = evaluateLighting();
				var transmittance = l * exp(-opticalDepth);
				var d = density * (1.0 - exp(-length(transmittance)));
				opticalDepth += d * fogDensity;
				opacity += d * fogDensity * (1.0 - opacity); 
				totalScattered += density * transmittance;
			}
			pixelColor.rgb = totalScattered;
			pixelColor.a = distanceOpacity * opacity;
		}
	};
}

@:access(h3d.scene.Renderer)
class VolumetricLighting extends RendererFX {

	var pass = new h3d.pass.ScreenFx(new h3d.shader.ScreenShader());
	var blurPass = new h3d.pass.Blur();
	var vshader = new VolumetricLightingShader();

	@:s public var blend : h3d.mat.PbrMaterial.PbrBlend = Alpha;
	@:s public var color : Int = 0xFFFFFF;
	@:s public var steps : Int = 10;
	@:s public var textureSize : Float = 0.5;
	@:s public var blur : Float = 0.0;
	@:s public var startDistance : Float = 0.0;
	@:s public var endDistance : Float = 200.0;
	@:s public var distanceOpacity : Float = 1.0;
	@:s public var ditheringIntensity : Float = 1.0;
	@:s public var ditheringNoise : String;

	@:s public var noiseScale : Float = 1.0;
	@:s public var noiseLacunarity : Float = 2.0;
	@:s public var noiseSharpness : Float = 1.0;
	@:s public var noisePersistence : Float = 0.5;
	@:s public var noiseTurmoil : Float = 1.0;
	@:s public var noiseOctave : Int = 1;

	@:s public var fogDensity : Float = 1.0;
	@:s public var fogHeightFalloff : Float = 1.0;
	@:s public var fogEnvPower : Float = 1.0;
	@:s public var fogBottom : Float = 0.0;
	@:s public var fogTop : Float = 200.0;

	var noiseTex : h3d.mat.Texture;

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( step == BeforeTonemapping ) {
			var r = cast(r, h3d.scene.pbr.Renderer);
			r.mark("VolumetricLighting");

			if ( noiseTex == null )
				noiseTex = makeNoiseTex();

			var tex = r.allocTarget("volumetricLighting", false, textureSize, RGBA16F);
			tex.clear(0, 0.0);
			r.ctx.engine.pushTarget(tex);

			vshader.USE_INDIRECT = false;
			if ( pass.getShader(h3d.shader.pbr.DefaultForward) == null )
				pass.addShader(vshader);
			var ls = cast(r.getLightSystem(), h3d.scene.pbr.LightSystem);
			ls.lightBuffer.setBuffers(vshader);
			vshader.depthMap = @:privateAccess r.textures.depth;
			vshader.startDistance = startDistance;
			vshader.endDistance = endDistance;
			vshader.distanceOpacity = distanceOpacity;
			vshader.steps = steps;
			vshader.invViewProj = r.ctx.camera.getInverseViewProj();
			vshader.color.load(h3d.Vector.fromColor(color));
			var noise = ditheringNoise != null ? hxd.res.Loader.currentInstance.load(ditheringNoise).toTexture() : h3d.mat.Texture.fromColor(0);
			noise.wrap = Repeat;
			vshader.ditheringNoise = noise;
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
			vshader.fogDensity = fogDensity;
			vshader.fogBottom = fogBottom;
			vshader.fogTop = fogTop;
			vshader.fogHeightFalloff = fogHeightFalloff;
			pass.pass.setBlendMode(Alpha);
			pass.render();

			r.ctx.engine.popTarget();

			blurPass.radius = blur;
			blurPass.apply(r.ctx, tex);

			var b : h3d.mat.BlendMode = switch ( blend ) {
			case None: None; 
			case Alpha: Alpha; 
			case Add: Add; 
			case AlphaAdd: AlphaAdd; 
			case Multiply: Multiply; 
			case AlphaMultiply: AlphaMultiply; 
			}
			h3d.pass.Copy.run(tex, h3d.Engine.getCurrent().getCurrentTarget(), b);
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
					<dt>Density</dt><dd><input type="range" min="0" max="2" field="fogDensity"/></dd>
					<dt>Bottom [m]</dt><dd><input type="range" min="0" max="1000" field="fogBottom"/></dd>
					<dt>Top [m]</dt><dd><input type="range" min="0" max="1000" field="fogTop"/></dd>
					<dt>Height falloff</dt><dd><input type="range" min="0" max="3" field="fogHeightFalloff"/></dd>
					<dt>Env power</dt><dd><input type="range" min="0" max="2" field="fogEnvPower"/></dd>
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
					<dt><font color=#FF0000>Texture size</font></dt><dd><input type="range" min="0" max="1" field="textureSize"/></dd>
					<dt>Blur</dt><dd><input type="range" step="1" min="0" max="100" field="blur"/></dd>
					<dt>Blue noise</dt><dd><input type="texturepath" field="ditheringNoise"/></dd>
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
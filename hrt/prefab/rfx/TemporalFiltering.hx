package hrt.prefab.rfx;

class TemporalFilteringShader extends h3d.shader.ScreenShader {

	static var SRC = {

		@const var VARIANCE_CLIPPING : Bool;
		@const var YCOCG : Bool;
		@const var CATMULL_ROM : Bool;
		@const var VELOCITY : Bool;

		@param var velocityBuffer : Sampler2D;
		@param var prevFrame : Sampler2D;
		@param var curFrame : Sampler2D;
		@param var amount : Float;

		@param var prevCamMat : Mat4;
		@param var cameraInverseViewProj : Mat4;

		@const var PACKED_DEPTH : Bool;
		@param var depthChannel : Channel;
		@param var depthTexture : Sampler2D;

		@const var KEEP_SKY_ALPHA : Bool;

		var isSky : Bool;

		function rgb2ycocg( rgb : Vec3 ) : Vec3 {
			if( YCOCG ) {
				var co = rgb.r - rgb.b;
				var t = rgb.b + co / 2.0;
				var cg = rgb.g - t;
				var y = t + cg / 2.0;
				return vec3(y, co, cg);
			}
			else
				return rgb;
		}

		function ycocg2rgb( ycocg : Vec3 ) : Vec3 {
			if( YCOCG ) {
				var t = ycocg.r - ycocg.b / 2.0;
				var g = ycocg.b + t;
				var b = t - ycocg.g / 2.0;
				var r = ycocg.g + b;
				return vec3(r, g, b);
			}
			else
				return ycocg;
		}

		function clipAABB( aabb_min : Vec3, aabb_max : Vec3, p : Vec4, q : Vec4) : Vec4	{
			// note: only clips towards aabb center (but fast!)
			var p_clip = 0.5 * (aabb_max + aabb_min);
			var e_clip = 0.5 * (aabb_max - aabb_min) + 0.00000001;

			var v_clip = q - vec4(p_clip, p.w);
			var v_unit = v_clip.xyz / e_clip;
			var a_unit = abs(v_unit);
			var ma_unit = max(max(a_unit.x, a_unit.y), a_unit.z);

			if (ma_unit > 1.0)
			{
				return vec4(p_clip, p.w) + v_clip / ma_unit;
			}
			else
			{
				return q;// point inside aabb
			}
		}

		// Reduce blurriness from billinear filter
		// https://gist.github.com/TheRealMJP/c83b8c0f46b63f3a88a5986f4fa982b1
		// https://vec3.ca/bicubic-filtering-in-fewer-taps/
		function sampleCatmullRom( tex : Sampler2D, uv : Vec2 ) : Vec4 {
			var texSize = tex.textureSize();

			var samplePos = uv * texSize;
			var texPos1 = floor(samplePos - 0.5) + 0.5;

			var f = samplePos - texPos1;

			var w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
			var w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
			var w2 = f * (0.5 + f * (2.0 - 1.5 * f));
			var w3 = f * f * (-0.5 + 0.5 * f);

			// Work out weighting factors and sampling offsets that will let us use bilinear filtering to
			// simultaneously evaluate the middle 2 samples from the 4x4 grid.
			var w12 = w1 + w2;
			var offset12 = w2 / (w1 + w2);

			// Compute the final UV coordinates we'll use for sampling the texture
			var texPos0 = texPos1 - 1;
			var texPos3 = texPos1 + 2;
			var texPos12 = texPos1 + offset12;

			texPos0 /= texSize;
			texPos3 /= texSize;
			texPos12 /= texSize;

			var result = vec4(0.0);
			result += tex.getLod(vec2(texPos0.x, texPos0.y), 0.0) * w0.x * w0.y;
			result += tex.getLod(vec2(texPos12.x, texPos0.y), 0.0) * w12.x * w0.y;
			result += tex.getLod(vec2(texPos3.x, texPos0.y), 0.0) * w3.x * w0.y;

			result += tex.getLod(vec2(texPos0.x, texPos12.y), 0.0) * w0.x * w12.y;
			result += tex.getLod(vec2(texPos12.x, texPos12.y), 0.0) * w12.x * w12.y;
			result += tex.getLod(vec2(texPos3.x, texPos12.y), 0.0) * w3.x * w12.y;

			result += tex.getLod(vec2(texPos0.x, texPos3.y), 0.0) * w0.x * w3.y;
			result += tex.getLod(vec2(texPos12.x, texPos3.y), 0.0) * w12.x * w3.y;
			result += tex.getLod(vec2(texPos3.x, texPos3.y), 0.0) * w3.x * w3.y;

			return vec4(result.rgb, result.a);
		}

		function getPixelPosition( uv : Vec2 ) : Vec3 {
			var d = PACKED_DEPTH ? unpack(depthTexture.get(uv)) : depthChannel.get(uv).r;
			var tmp = vec4(uvToScreen(uv), d, 1) * cameraInverseViewProj;
			tmp.xyz /= tmp.w;
			isSky = d == 1.0;
			return tmp.xyz;
		}

		function fragment() {
			var curSample = curFrame.get(calculatedUV);
			var curColor = rgb2ycocg(curSample.rgb);

			var prevUV : Vec2;

			if ( VELOCITY ) {
				var velocity = velocityBuffer.get(calculatedUV).xy;
				prevUV = calculatedUV + velocity;
				isSky = (PACKED_DEPTH ? unpack(depthTexture.get(calculatedUV)) : depthChannel.get(calculatedUV).r) == 1.0;
			}
			else {
				var curPos = getPixelPosition(calculatedUV);
				var prevPos = vec4(curPos, 1.0) * prevCamMat;
				prevPos.xyz /= prevPos.w;
				prevUV = screenToUv(prevPos.xy);
			}

			var prevSample = max((CATMULL_ROM) ? sampleCatmullRom(prevFrame, prevUV) : prevFrame.getLod(prevUV, 0), 0.0);
			var prevColor = rgb2ycocg(prevSample.rgb);

			if ( VARIANCE_CLIPPING ) {
				var invResolution = 1 / curFrame.textureSize();

				var lt = rgb2ycocg(curFrame.getLod(calculatedUV + (vec2(-1.0,  1.0 ) * invResolution ), 0).rgb);
				var ct = rgb2ycocg(curFrame.getLod(calculatedUV + (vec2( 0.0,  1.0 ) * invResolution ), 0).rgb);
				var rt = rgb2ycocg(curFrame.getLod(calculatedUV + (vec2( 1.0,  1.0 ) * invResolution ), 0).rgb);
				var lc = rgb2ycocg(curFrame.getLod(calculatedUV + (vec2(-1.0,  0.0 ) * invResolution ), 0).rgb);
				var rc = rgb2ycocg(curFrame.getLod(calculatedUV + (vec2( 1.0,  0.0 ) * invResolution ), 0).rgb);
				var lb = rgb2ycocg(curFrame.getLod(calculatedUV + (vec2(-1.0, -1.0 ) * invResolution ), 0).rgb);
				var cb = rgb2ycocg(curFrame.getLod(calculatedUV + (vec2( 0.0, -1.0 ) * invResolution ), 0).rgb);
				var rb = rgb2ycocg(curFrame.getLod(calculatedUV + (vec2( 1.0, -1.0 ) * invResolution ), 0).rgb);

				var neighborMin = min(lt, min(ct, min(rt, min(lc, min(curColor, min(rc, min(lb, min(cb, rb))))))));
				var neighborMax = max(lt, max(ct, max(rt, max(lc, max(curColor, max(rc, max(lb, max(cb, rb))))))));
				var neighborAvg = (lt + ct + rt + lc + curColor + rc + lb + cb + rb) / 9.0;

				var neighborMin2 = min(min(min(min(lc, curColor), ct), rc), cb);
				var neighborMax2 = max(max(max(max(lc, curColor), ct), rc), cb);
				var neighborAvg2 = (lc + curColor + ct + rc + cb ) / 5.0;

				neighborMin = (neighborMin + neighborMin2 ) * 0.5;
				neighborMax = (neighborMax + neighborMax2 ) * 0.5;
				neighborAvg = (neighborAvg + neighborAvg2 ) * 0.5;

				prevColor = clipAABB(neighborMin, neighborMax, vec4(neighborAvg, 1), vec4(prevColor, 1)).xyz;
			}

			var blendFactor = amount;

			if ( ( prevUV.x > 1.0 || prevUV.x < 0.0 || prevUV.y > 1.0 || prevUV.y < 0.0 ) || isSky )
				blendFactor = 0.0;

			pixelColor.rgb = ycocg2rgb(mix(curColor, prevColor, blendFactor));

			if ( KEEP_SKY_ALPHA )
				pixelColor.a = isSky ? curSample.a : 1.0;
			else
				pixelColor.a = 1.0;
		}
	}
}

@:access(h3d.scene.Renderer)
class TemporalFiltering extends hrt.prefab.rfx.RendererFX {

	@:s public var amount : Float;
	@:s public var varianceClipping : Bool = true;
	@:s public var ycocg : Bool = true;
	@:s public var catmullRom : Bool = true;
	@:s public var velocity : Bool = false;
	@:s public var jitterPattern : FrustumJitter.Pattern = Still;
	@:s public var jitterScale : Float = 1;
	@:s public var renderMode : String = "AfterTonemapping";
	@:s public var keepSkyAlpha : Bool = false;

	public var frustumJitter = new FrustumJitter();
	public var pass = new h3d.pass.ScreenFx(new TemporalFilteringShader());
	public var jitterMat = new h3d.Matrix();
	var curMatNoJitter = new h3d.Matrix();
	var curMatJittered = new h3d.Matrix();

	var tmp = new h3d.Matrix();
	public function getMatrixJittered( camera : h3d.Camera ) : h3d.Matrix {
		tmp.identity();
		tmp.multiply(camera.mproj, jitterMat);
		tmp.multiply(camera.mcam, tmp);
		return tmp;
	}

	override function start( r:h3d.scene.Renderer) {
		r.ctx.computeVelocity = velocity;
	}

	override function begin( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		if( step == MainDraw ) {
			var ctx = r.ctx;
			var s = pass.shader;

			frustumJitter.curPattern = jitterPattern;
			frustumJitter.patternScale = jitterScale;
			frustumJitter.update();

			var prevJitterOffsetX = -frustumJitter.prevSample.x / ctx.engine.width;
			var prevJitterOffsetY = frustumJitter.prevSample.y / ctx.engine.height;
			var jitterOffsetX = -frustumJitter.curSample.x / ctx.engine.width;
			var jitterOffsetY = frustumJitter.curSample.y / ctx.engine.height;

			curMatNoJitter.load(ctx.camera.m);
			ctx.camera.jitterOffsetX = jitterOffsetX;
			ctx.camera.jitterOffsetY = jitterOffsetY;
			ctx.camera.update();
			curMatJittered.load(ctx.camera.m);
			@:privateAccess ctx.cameraJitterOffsets.set( jitterOffsetX, jitterOffsetY, prevJitterOffsetX, prevJitterOffsetY );
			s.cameraInverseViewProj.initInverse(curMatNoJitter);
		}
	}

	override function end( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		var ctx = r.ctx;

		if( ( step == AfterTonemapping && renderMode == "AfterTonemapping") || (step == BeforeTonemapping && renderMode == "BeforeTonemapping" ) ) {
			r.mark("TemporalFiltering");
			var output : h3d.mat.Texture = ctx.engine.getCurrentTarget();
			var depthMap : Dynamic = ctx.getGlobal("depthMap");
			var prevFrame = r.allocTarget("prevFrame", false, 1.0, output.format);
			if ( !prevFrame.flags.has(WasCleared) ) {
				prevFrame.flags.set(WasCleared);
				prevFrame.clear(0);
			}
			var curFrame = r.allocTarget("curFrame", false, 1.0, output.format);
			h3d.pass.Copy.run(output, curFrame);

			var s = pass.shader;
			s.curFrame = curFrame;
			s.curFrame.filter = Linear;
			s.prevFrame = prevFrame;
			s.prevFrame.filter = Linear;
			s.amount = amount;

			s.PACKED_DEPTH = depthMap.packed != null && depthMap.packed == true;
			if( s.PACKED_DEPTH ) {
				s.depthTexture = depthMap.texture;
			}
			else {
				s.depthChannel = depthMap.texture;
				s.depthChannelChannel = depthMap.channel == null ? hxsl.Channel.R : depthMap.channel;
			}

			s.VARIANCE_CLIPPING = varianceClipping;
			s.YCOCG = ycocg;
			s.CATMULL_ROM = catmullRom;
			s.VARIANCE_CLIPPING = varianceClipping;
			if ( velocity ) {
				s.velocityBuffer = ctx.getGlobal("velocity");
				s.velocityBuffer.filter = Nearest;
				s.VELOCITY = velocity;
			}

			s.KEEP_SKY_ALPHA = keepSkyAlpha;

			r.setTarget(output, NotBound);
			pass.render();

			h3d.pass.Copy.run(output, prevFrame);
			s.prevCamMat.load(curMatNoJitter);

			ctx.camera.jitterOffsetX = 0;
			ctx.camera.jitterOffsetY = 0;

			// Remove Jitter for effects post TAA
			r.ctx.camera.update();
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<dl>
				<dt>Amount</dt><dd><input type="range" min="0" max="1" field="amount"/></dd>
				<dt>Variance Clipping</dt><dd><input type="checkbox" field="varianceClipping"/></dd>
				<dt>Ycocg</dt><dd><input type="checkbox" field="ycocg"/></dd>
				<dt>CatmullRom</dt><dd><input type="checkbox" field="catmullRom"/></dd>
				<dt>Velocity</dt><dd><input type="checkbox" field="velocity"/></dd>
				<div class="group" name="Jitter">
					<dt>Pattern</dt>
						<dd>
							<select field="jitterPattern">
								<option value="Still">Still</option>
								<option value="Uniform2">Uniform2</option>
								<option value="Uniform4">Uniform4</option>
								<option value="Uniform4_Helix">Uniform4 Helix</option>
								<option value="Uniform4_DoubleHelix">Uniform4 DoubleHelix</option>
								<option value="SkewButterfly">SkewButterfly</option>
								<option value="Rotated4">Rotated4</option>
								<option value="Rotated4_Helix">Rotated4 Helix</option>
								<option value="Rotated4_Helix2">Rotated4 Helix2</option>
								<option value="Poisson10">Poisson10</option>
								<option value="Pentagram">Pentagram</option>
								<option value="Halton_2_3_x8">Halton_2_3_x8</option>
								<option value="Halton_2_3_x16">Halton_2_3_x16</option>
								<option value="Halton_2_3_x32">Halton_2_3_x32</option>
								<option value="Halton_2_3_x256">Halton_2_3_x256</option>
								<option value="MotionPerp2">MotionPerp2</option>
								<option value="MotionVPerp2">MotionVPerp2</option>
							</select>
						</dd>
					<dt>Scale</dt><dd><input type="range" min="0" max="2" field="jitterScale"/></dd>
				</div>
				<div class="group" name="Rendering">
					<dt>Render Mode</dt>
						<dd><select field="renderMode">
							<option value="BeforeTonemapping">Before Tonemapping</option>
							<option value="AfterTonemapping">After Tonemapping</option>
						</select></dd>
					<dt>Keep sky alpha</dt><dd><input type="checkbox" field="keepSkyAlpha"/></dd>
				</div>
			</dl>
		'),this, function(pname) {
			ctx.onChange(this,pname);
		});
	}
	#end

	static var _ = Prefab.register("rfx.temporalFiltering", TemporalFiltering);

}
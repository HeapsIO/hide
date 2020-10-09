package hrt.prefab.rfx;

typedef TemporalFilteringProps = {
	var amount : Float;
	var varianceClipping : Bool;
	var ycocg : Bool;
	var unjitter : Bool;
	var jitterPattern : FrustumJitter.Pattern;
	var jitterScale : Float;
	var renderMode : String;
}

class TemporalFilteringShader extends h3d.shader.ScreenShader {

	static var SRC = {

		@const var VARIANCE_CLIPPING : Bool;
		@const var YCOCG : Bool;
		@const var UNJITTER : Bool;

		@param var prevFrame : Sampler2D;
		@param var curFrame : Sampler2D;
		@param var resolution : Vec2;
		@param var amount : Float;
		@param var jitterUV : Vec2;
		@param var prevJitterUV : Vec2;

		@param var prevCamMat : Mat4;
		@param var cameraInverseViewProj : Mat4;

		@const var PACKED_DEPTH : Bool;
		@param var depthChannel : Channel;
		@param var depthTexture : Sampler2D;

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

		function clipToAABB( cOld : Vec3, cNew : Vec3, centre : Vec3, halfSize : Vec3 ) : Vec3 {
			var a = abs(cOld - centre);
			if( a.r <= halfSize.r && a.g <= halfSize.g && a.b <= halfSize.b ) {
				return cOld;
			}
			else {
				var dir = (cNew - cOld);
				var near = centre - sign(dir) * halfSize;
				var tAll = (near - cOld) / dir;
				var t = 1.0;
				if( tAll.x >= 0.0 && tAll.x < t ) t = tAll.x;
				if( tAll.y >= 0.0 && tAll.y < t ) t = tAll.y;
				if( tAll.z >= 0.0 && tAll.z < t ) t = tAll.z;

				if( t >= 1.0 ) {
					return cOld;
				}
				else
					return cOld + dir * t;
			}
		}

		function getPixelPosition( uv : Vec2 ) : Vec3 {
			var d = PACKED_DEPTH ? unpack(depthTexture.get(uv)) : depthChannel.get(uv).r;
			var tmp = vec4(uvToScreen(uv), d, 1) * cameraInverseViewProj;
			tmp.xyz /= tmp.w;
			return tmp.xyz;
		}

		function fragment() {
			var unJitteredUV = calculatedUV;
			if( UNJITTER )
				unJitteredUV -= jitterUV * 0.5;

			var curPos = getPixelPosition(calculatedUV);
			var prevPos = vec4(curPos, 1.0) * prevCamMat;
			prevPos.xyz /= prevPos.w;

			// Discard Pixels outside bounds
			if( abs(prevPos.x) > 1.0 || abs(prevPos.y) > 1.0 )
				discard;

			var prevUV = screenToUv(prevPos.xy);
			var prevColor = prevFrame.get(prevUV).rgb;
			var curColor = curFrame.get(unJitteredUV).rgb;

			// Neighborhood clipping [MALAN 2012][KARIS 2014]
			if( VARIANCE_CLIPPING ) {
				var offsets : Array<Vec2, 4> = [ vec2(-1.0,0.0), vec2(1.0,0.0), vec2(0.0,-1.0), vec2(0.0, 1.0) ];
				var m1 = rgb2ycocg(curColor);
				var m2 = m1 * m1;
				for( i in 0 ... 4 ) {
					var c = rgb2ycocg(curFrame.getLod(unJitteredUV + (offsets[i] / resolution), 0).rgb);
					m1 += c;
					m2 += c * c;
				}
				m1 /= 5.0;
				m2 = sqrt(m2 / 5.0 - m1 * m1);
				prevColor = ycocg2rgb(clipToAABB(rgb2ycocg(prevColor), rgb2ycocg(curColor), m1, m2));
			}

			pixelColor.rgb = mix(curColor, prevColor, amount);
			pixelColor.a = 1.0;
		}
	}
}

class TemporalFiltering extends hrt.prefab.rfx.RendererFX {

	var frustumJitter = new FrustumJitter();
	public var pass = new h3d.pass.ScreenFx(new TemporalFilteringShader());
	var curMatNoJitter = new h3d.Matrix();
	var jitterMat = new h3d.Matrix();

	public function new(?parent) {
		super(parent);
		props = ({
			amount : 0.0,
			varianceClipping : true,
			ycocg : true,
			unjitter : true,
			jitterPattern : Still,
			jitterScale : 1.0,
			renderMode : "AfterTonemapping",
		} : TemporalFilteringProps);
	}

	override function begin( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		if( step == MainDraw ) {
			var ctx = r.ctx;
			var p : TemporalFilteringProps = props;
			var s = pass.shader;

			frustumJitter.curPattern = p.jitterPattern;
			frustumJitter.patternScale = p.jitterScale;
			frustumJitter.update();

			// Translation Matrix for Jittering
			jitterMat.identity();
			jitterMat.translate(frustumJitter.curSample.x / ctx.engine.width, frustumJitter.curSample.y / ctx.engine.height);

			s.prevJitterUV.set(-frustumJitter.prevSample.x / ctx.engine.width, frustumJitter.prevSample.y / ctx.engine.height);
			s.jitterUV.set(-frustumJitter.curSample.x / ctx.engine.width, frustumJitter.curSample.y / ctx.engine.height);

			ctx.camera.update();
			curMatNoJitter.load(ctx.camera.m);
			ctx.camera.mproj.multiply(ctx.camera.mproj, jitterMat);
			ctx.camera.m.multiply(ctx.camera.mcam, ctx.camera.mproj);
			s.cameraInverseViewProj.initInverse(curMatNoJitter);
		}
	}

	override function end( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		var p : TemporalFilteringProps = props;
		if( ( step == AfterTonemapping && p.renderMode == "AfterTonemapping") || (step == BeforeTonemapping && p.renderMode == "BeforeTonemapping" ) ) {
			r.mark("TemporalFiltering");
			var output : h3d.mat.Texture = r.ctx.engine.getCurrentTarget();
			var depthMap : Dynamic = r.ctx.getGlobal("depthMap");
			var prevFrame = r.allocTarget("prevFrame", false, 1.0, output.format);
			var curFrame = r.allocTarget("curFrame", false, 1.0, output.format);
			h3d.pass.Copy.run(output, curFrame);

			var s = pass.shader;
			s.curFrame = curFrame;
			s.prevFrame = prevFrame;
			s.amount = p.amount;

			s.PACKED_DEPTH = depthMap.packed != null && depthMap.packed == true;
			if( s.PACKED_DEPTH ) {
				s.depthTexture = depthMap.texture;
			}
			else {
				s.depthChannel = depthMap.texture;
				s.depthChannelChannel = depthMap.channel == null ? hxsl.Channel.R : depthMap.channel;
			}

			s.resolution.set(output.width, output.height);
			s.VARIANCE_CLIPPING = p.varianceClipping;
			s.YCOCG = p.ycocg;
			s.UNJITTER = p.unjitter;

			r.setTarget(output);
			pass.render();

			h3d.pass.Copy.run(output, prevFrame);
			s.prevCamMat.load(curMatNoJitter);
			r.ctx.camera.m.load(curMatNoJitter);
			@:privateAccess r.ctx.camera.needInv = true;
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<dl>
				<dt>Amount</dt><dd><input type="range" min="0" max="1" field="amount"/></dd>
				<dt>Variance Clipping</dt><dd><input type="checkbox" field="varianceClipping"/></dd>
				<dt>Ycocg</dt><dd><input type="checkbox" field="ycocg"/></dd>
				<dt>Unjitter</dt><dd><input type="checkbox" field="unjitter"/></dd>
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
				</div>
			</dl>
		'),props);
	}
	#end

	static var _ = hrt.prefab.Library.register("rfx.temporalFiltering", TemporalFiltering);

}
package hrt.prefab.rfx;

class KuwaharaShader extends hrt.shader.PbrShader {

	static var SRC = {

		@param var startDist : Float;
		@param var endDist : Float;
		@param var startOpacity : Float;
		@param var endOpacity : Float;
		@param var scaledRadius : Int;

		@param var ldrCopy : Sampler2D;

		function fragment() {			
			var size = ldrCopy.size();
			var invSize = 1.0 / size;
			var n = float((scaledRadius + 1) * (scaledRadius + 1));
			var m0 = vec3(0.0);
			var m1 = vec3(0.0);
			var m2 = vec3(0.0);
			var m3 = vec3(0.0);
			
			var s0 = vec3(0.0);
			var s1 = vec3(0.0);
			var s2 = vec3(0.0);
			var s3 = vec3(0.0);

			for ( j in -scaledRadius...1 )  {
				for ( i in -scaledRadius...1 )  {
					var c = ldrCopy.get(calculatedUV + vec2(i,j) * invSize).rgb;
					m0 += c;
					s0 += c * c;
				}
			}

			for ( j in -scaledRadius...1 )  {
				for ( i in 0...scaledRadius + 1)  {
					var c = ldrCopy.get(calculatedUV + vec2(i,j) * invSize).rgb;
					m1 += c;
					s1 += c * c;
				}
			}

			for ( j in 0...scaledRadius + 1 )  {
				for ( i in 0...scaledRadius + 1)  {
					var c = ldrCopy.get(calculatedUV + vec2(i,j) * invSize).rgb;
					m2 += c;
					s2 += c * c;
				}
			}

			for ( j in 0... scaledRadius + 1 )  {
				for ( i in -scaledRadius...1 )  {
					var c = ldrCopy.get(calculatedUV + vec2(i,j) * invSize).rgb;
					m3 += c;
					s3 += c * c;
				}
			}


			var minSigma2 = 1e+10;
			m0 /= n;
			s0 = abs(s0 / n - m0 * m0);

			var filteredColor = vec3(0.0);

			var sigma2 = s0.r + s0.g + s0.b;
			if (sigma2 < minSigma2) {
				minSigma2 = sigma2;
				filteredColor = vec3(m0);
			}

			m1 /= n;
			s1 = abs(s1 / n - m1 * m1);

			sigma2 = s1.r + s1.g + s1.b;
			if (sigma2 < minSigma2) {
				minSigma2 = sigma2;
				filteredColor = vec3(m1);
			}

			m2 /= n;
			s2 = abs(s2 / n - m2 * m2);

			sigma2 = s2.r + s2.g + s2.b;
			if (sigma2 < minSigma2) {
				minSigma2 = sigma2;
				filteredColor = vec3(m2);
			}

			m3 /= n;
			s3 = abs(s3 / n - m3 * m3);

			sigma2 = s3.r + s3.g + s3.b;
			if (sigma2 < minSigma2) {
				minSigma2 = sigma2;
				filteredColor = vec3(m3);
			}

			var wPos = getPosition();
			var dist = distance(camera.position, wPos);
			var opacity = mix(startOpacity, endOpacity, smoothstep(startDist, endDist, dist));
			pixelColor = vec4(filteredColor, opacity);
		}
	}
}

@:access(h3d.scene.Renderer)
class KuwaharaFilter extends RendererFX {

	@:s var radius : Int = 4;
	@:s var startDist : Float = 0.0;
	@:s var endDist : Float = 100.0;

	@:s var startOpacity : Float = 0.0;
	@:s var endOpacity : Float = 1.0;

	var pass = new h3d.pass.ScreenFx(new KuwaharaShader());

	override function begin(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if ( step == AfterTonemapping ) {
			var ldrCopy = r.allocTarget("ldrCopy", true, 1.0);
			h3d.pass.Copy.run(r.ctx.engine.getCurrentTarget(), ldrCopy);
			pass.shader.ldrCopy = ldrCopy;

			pass.shader.scaledRadius = Std.int(radius * hxd.Math.max(ldrCopy.width / 1920, ldrCopy.height / 1080));
			pass.shader.startOpacity = startOpacity;
			pass.shader.endOpacity = endOpacity;
			pass.shader.startDist = startDist;
			pass.shader.endDist = endDist;
			pass.pass.setBlendMode(Alpha);
			pass.render();
		}
	}

	#if editor

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
		ctx.properties.add(new hide.Element(
			'<div class="group" name="Filter">
				<dl>
					<dt>Radius</dt><dd><input type="range" min="1" step="1" field="radius"/></dd>
				</dl>
			</div>
			<div class="group" name="Fade">
				<dl>
					<dt>Start dist</dt><dd><input type="range" min="0" field="startDist"/></dd>
					<dt>End dist</dt><dd><input type="range" min="0" field="endDist"/></dd>
					<dt>Start opacity</dt><dd><input type="range" min="0" field="startOpacity"/></dd>
					<dt>End opacity</dt><dd><input type="range" min="0" field="endOpacity"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}

	#end

	static var _ = Prefab.register("rfx.kuwaharaFilter", KuwaharaFilter);

}
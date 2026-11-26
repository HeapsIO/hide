package hrt.prefab.rfx;

class KuwaharaRowSumShader extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var texture : Sampler2D;
		@param var radius : Int;

		function fragment() {
			var invSize = 1.0 / texture.size();
			var sum = vec4(0.0);
			for ( i in -radius...1 ) {
				var c = texture.get(calculatedUV + vec2(i,0) * invSize).rgb;
				sum += vec4(c, dot(c, c));
			}
			pixelColor = sum;
		}
	}
}

class KuwaharaShader extends hrt.shader.PbrShader {

	static var SRC = {

		@param var startDist : Float;
		@param var endDist : Float;
		@param var startOpacity : Float;
		@param var endOpacity : Float;
		@param var scaledRadius : Int;

		@param var texture : Sampler2D;

		function getFilteredColor() : Vec3 {
			var size = texture.size();
			var invSize = 1.0 / size;
			var invN = 1.0 /float((scaledRadius + 1) * (scaledRadius + 1));
			var m0 = vec3(0.0);
			var m1 = vec3(0.0);
			var m2 = vec3(0.0);
			var m3 = vec3(0.0);

			var s0 = 0.0;
			var s1 = 0.0;
			var s2 = 0.0;
			var s3 = 0.0;

			var rightOffset = vec2(scaledRadius, 0) * invSize;
			for ( j in -scaledRadius...scaledRadius + 1 )  {
				var uv = calculatedUV + vec2(0,j) * invSize;
				var left = texture.get(uv);
				var right = texture.get(uv + rightOffset);
				if ( j <= 0 ) {
					m0 += left.rgb;
					s0 += left.a;
					m1 += right.rgb;
					s1 += right.a;
				}
				if ( j >= 0 ) {
					m2 += right.rgb;
					s2 += right.a;
					m3 += left.rgb;
					s3 += left.a;
				}
			}

			var minSigma2 = 1e+10;
			m0 *= invN;

			var filteredColor = vec3(0.0);

			var sigma2 = abs(s0 * invN - dot(m0, m0));
			if (sigma2 < minSigma2) {
				minSigma2 = sigma2;
				filteredColor = vec3(m0);
			}

			m1 *= invN;

			sigma2 = abs(s1 * invN - dot(m1, m1));
			if (sigma2 < minSigma2) {
				minSigma2 = sigma2;
				filteredColor = vec3(m1);
			}

			m2 *= invN;

			sigma2 = abs(s2 * invN - dot(m2, m2));
			if (sigma2 < minSigma2) {
				minSigma2 = sigma2;
				filteredColor = vec3(m2);
			}

			m3 *= invN;

			sigma2 = abs(s3 * invN - dot(m3, m3));
			if (sigma2 < minSigma2) {
				minSigma2 = sigma2;
				filteredColor = vec3(m3);
			}
			return filteredColor;
		}

		function fragment() {
			var filteredColor = getFilteredColor();
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
	var rowSumPass = new h3d.pass.ScreenFx(new KuwaharaRowSumShader());

	function renderRowSums(r : h3d.scene.Renderer) {
		var source = r.ctx.engine.getCurrentTarget();
		var rowSums = r.allocTarget("kuwaharaRowSums", false, 1.0, hxd.PixelFormat.RGBA16F);
		rowSumPass.shader.texture = source;
		rowSumPass.shader.radius = Std.int(radius * hxd.Math.max(source.width / 1920, source.height / 1080));
		r.ctx.engine.pushTarget(rowSums);
		rowSumPass.render();
		r.ctx.engine.popTarget();
		return rowSums;
	}

	function execute(r : h3d.scene.Renderer) {
		r.mark("Kuwahara");
		r.ctx.engine.driver.beginEvent("Kuwahara");

		var rowSums = renderRowSums(r);
		pass.shader.texture = rowSums;

		pass.shader.scaledRadius = Std.int(radius * hxd.Math.max(rowSums.width / 1920, rowSums.height / 1080));
		pass.shader.startOpacity = startOpacity;
		pass.shader.endOpacity = endOpacity;
		pass.shader.startDist = startDist;
		pass.shader.endDist = endDist;
		pass.pass.setBlendMode(Alpha);
		pass.render();
		r.ctx.engine.driver.endEvent();
	}

	override function begin(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if ( step == AfterTonemapping )
			execute(r);
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
					<dt>Start opacity</dt><dd><input type="range" min="0" max="1" field="startOpacity"/></dd>
					<dt>End opacity</dt><dd><input type="range" min="0" max="1" field="endOpacity"/></dd>
				</dl>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}

	#end

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		super.edit2(ctx);

		ctx.build(
			<root>
				<category("Filter")>
					<slider min={1} field={radius} />
				</category>
				<category("Fade")>
					<slider min={0.0} field={startDist} />
					<slider min={0.0} field={endDist} />
					<range(0,1) field={startOpacity} />
					<range(0,1) field={endOpacity} />
				</category>
			</root>
		);
	}

	static var _ = Prefab.register("rfx.kuwaharaFilter", KuwaharaFilter);

}
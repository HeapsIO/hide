package hrt.prefab.rfx;

import hxsl.Eval;
import h3d.pass.Copy;

class DualFilterDown extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var source : Sampler2D;
		@param var halfPixel : Vec2;

		function fragment() {
			var sum = vec3(0,0,0);
			sum += texture(source, calculatedUV).rgb * 4.0;
			sum += texture(source, calculatedUV + halfPixel.xy).rgb;
			sum += texture(source, calculatedUV - halfPixel.xy).rgb;
			sum += texture(source, calculatedUV + vec2(halfPixel.x, -halfPixel.y)).rgb;
			sum += texture(source, calculatedUV - vec2(halfPixel.x, -halfPixel.y)).rgb;
			pixelColor.rgb = max(sum / 8.0, 0.0);
		}
	};
}

class DualFilterUp extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var source : Sampler2D;
		@param var halfPixel : Vec2;

		function fragment() {
			var sum = vec3(0,0,0);
			sum += texture(source, calculatedUV + vec2(-halfPixel.x * 2.0, 0.0)).rgb;
			sum += texture(source, calculatedUV + vec2(-halfPixel.x, halfPixel.y)).rgb * 2.0;
			sum += texture(source, calculatedUV + vec2(0.0, halfPixel.y * 2.0)).rgb;
			sum += texture(source, calculatedUV + vec2(halfPixel.x, halfPixel.y)).rgb * 2.0;
			sum += texture(source, calculatedUV + vec2(halfPixel.x * 2.0, 0.0)).rgb;
			sum += texture(source, calculatedUV + vec2(halfPixel.x, -halfPixel.y)).rgb * 2.0;
			sum += texture(source, calculatedUV + vec2(0.0, -halfPixel.y * 2.0)).rgb;
			sum += texture(source, calculatedUV + vec2(-halfPixel.x, -halfPixel.y)).rgb * 2.0;
			pixelColor.rgb = sum / 12.0;
		}
	};
}

class Threshold extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var hdr : Sampler2D;
		@param var threshold : Float;
        @param var intensity : Float;
		@param var maxIntensity : Float;

		@const var USE_TEMPORAL_FILTER : Bool;
		@const var PREVENT_GHOSTING : Bool;
		@param var prev : Sampler2D;
		@param var prevCamMat : Mat4;
		@param var cameraInverseViewProj : Mat4;
		@param var strength : Float;

		function fragment() {
			var curVal = max(hdr.get(calculatedUV).rgb - threshold, 0.0) * intensity;
			pixelColor.rgb = min(curVal, maxIntensity);

			if( USE_TEMPORAL_FILTER ) {
				var pixelPos = vec4(uvToScreen(calculatedUV), 1, 1) * cameraInverseViewProj;
				pixelPos.xyz /= max(pixelPos.w, 1e-16);
				var prevPos = vec4(pixelPos.xyz, 1.0) * prevCamMat;
				prevPos.xyz /= max(prevPos.w, 1e-16);
				var prevUV = screenToUv(prevPos.xy);
				var blendStrengh = strength * ceil(1 - max(abs(prevPos.x), abs(prevPos.y)));
				var prevVal = prev.get(prevUV).rgb;
				pixelColor.rgb = mix(curVal, prevVal, blendStrengh);
			}
		}
	};
}

@:access(h3d.scene.Renderer)
class TemporalBloom extends RendererFX {

	@:s public var size : Float;
	@:s public var downScaleCount : Int;
	@:s public var threshold : Float;
    @:s public var intensity : Float = 1;
	@:s public var maxValue : Float;
	@:s public var useTemporalFilter : Bool = true;
	@:s public var temporalStrength : Float;

	var thresholdPass = new h3d.pass.ScreenFx(new Threshold());
	var downScale = new h3d.pass.ScreenFx(new DualFilterDown());
	var upScale = new h3d.pass.ScreenFx(new DualFilterUp());

	var prevResult : h3d.mat.Texture;
	var prevCamMat : h3d.Matrix;

	var tonemap = new Bloom.BloomTonemap();

	function new(parent, shared: ContextShared) {
		super(parent, shared);
		size = 0.5;
		downScaleCount = 5;
		threshold = 0.5;
		maxValue = 100.0;
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( step == BeforeTonemapping ) {
			r.mark("TBloom");
			var ctx = r.ctx;

			var source = r.allocTarget("source", false, size, RGBA16F);
			ctx.engine.pushTarget(source);
			thresholdPass.shader.hdr = ctx.getGlobal("hdrMap");
			thresholdPass.shader.threshold = threshold;
            thresholdPass.shader.intensity = intensity;
			thresholdPass.shader.maxIntensity = maxValue;
			if( useTemporalFilter ) {
				if ( prevCamMat == null ) {
					prevCamMat = new h3d.Matrix();
					prevCamMat.load(ctx.camera.m);
				}
				thresholdPass.shader.USE_TEMPORAL_FILTER = true;
				prevResult = r.allocTarget("pr", false, size, RGBA16F);
				if ( !prevResult.flags.has(WasCleared) ) {
					prevResult.clear(0);
					prevResult.flags.set(WasCleared);
				}
				thresholdPass.shader.prev = prevResult;
				thresholdPass.shader.prevCamMat.load(prevCamMat);
				thresholdPass.shader.cameraInverseViewProj.load(ctx.camera.getInverseViewProj());
				thresholdPass.shader.strength = temporalStrength;
				thresholdPass.render();
				ctx.engine.popTarget();
				Copy.run(source, prevResult);
				prevCamMat.load(ctx.camera.m);
			}
			else {
				thresholdPass.shader.USE_TEMPORAL_FILTER = false;
				thresholdPass.render();
				ctx.engine.popTarget();
			}

			var curSize = size;
			var curTarget : h3d.mat.Texture = source;
			for( i in 0 ... downScaleCount ) {
				curSize *= 0.5;
				var prevTarget = curTarget;
				curTarget = r.allocTarget("dso_"+i, false, curSize, RGBA16F);
				ctx.engine.pushTarget(curTarget);
				downScale.shader.source = prevTarget;
				downScale.shader.halfPixel.set(1.0 / prevTarget.width, 1.0 / prevTarget.height);
				downScale.render();
				ctx.engine.popTarget();
			}
			for( i in 0 ... downScaleCount ) {
				curSize *= 2.0;
				var prevTarget = curTarget;
				curTarget = r.allocTarget("uso_"+i, false, curSize, RGBA16F);
				ctx.engine.pushTarget(curTarget);
				upScale.shader.source = prevTarget;
				upScale.shader.halfPixel.set(1.0 / prevTarget.width, 1.0 / prevTarget.height);
				upScale.render();
				ctx.engine.popTarget();
			}

			tonemap.bloomTexture = curTarget;
			r.addShader(tonemap);
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
		<div class="group" name="Bloom">
			<dl>
				<dt>Threshold</dt><dd><input type="range" min="0" max="1" field="threshold"/></dd>
				<dt>Intensity</dt><dd><input type="range" min="0" max="1" field="intensity"/></dd>
				<dt>Max</dt><dd><input type="range" min="0" max="100" field="maxValue"/></dd>
				<dt>Texture Size</dt><dd><input type="range" min="0" max="1" field="size"/></dd>
				<dt>DownScale/UpScale Count</dt><dd><input type="range" min="1" max="5" field="downScaleCount" step="1"/></dd>
			</dl>
		</div>
		<div class="group" name="Temporal Filtering">
			<dl>
			<dt>Enable</dt><dd><input type="checkbox" field="useTemporalFilter"/></dd>
			<dt>Strength</dt><dd><input type="range" min="0" max="1" field="temporalStrength"/></dd>
			</dl>
		</div>
		'),this, (pname: String) -> {
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("rfx.temporalbloom", TemporalBloom);

}
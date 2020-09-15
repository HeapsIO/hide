package hrt.prefab.rfx;

class DistanceBlurShader extends PbrShader {

	static var SRC = {

		@param var nearStartDistance : Float;
		@param var nearEndDistance : Float;
		@param var nearStartIntensity : Float;
		@param var nearEndIntensity : Float;

		@param var farStartDistance : Float;
		@param var farEndDistance : Float;
		@param var farStartIntensity : Float;
		@param var farEndIntensity : Float;

		@param var blurredTexture : Sampler2D;

		@const var DEBUG : Bool = false;

		function fragment() {
			var origin = getPosition();
			var distance = (origin - camera.position).length();
			
			if( distance < nearEndDistance ) {
				var nearIntensityFactor = clamp((distance - nearStartDistance) / (nearEndDistance - nearStartDistance), 0, 1);
				var nearIntensity = mix(nearStartIntensity, nearEndIntensity, nearIntensityFactor);
				pixelColor = DEBUG ? vec4(vec3(nearIntensity), 1.0) : vec4(blurredTexture.get(calculatedUV).rgb, nearIntensity);
			}
			else if( distance > farStartDistance ) {
				var farIntensityFactor = clamp((distance - farStartDistance) / (farEndDistance - farStartDistance), 0, 1);
				var farIntensity = mix(farStartIntensity, farEndIntensity, farIntensityFactor);
				pixelColor = DEBUG ? vec4(vec3(farIntensity), 1.0) : vec4(blurredTexture.get(calculatedUV).rgb, farIntensity);
			}
			else 
				discard;
		}
	};

	public function new() {
		super();
	}

}

typedef DistanceBlurProps = {

	var nearStartDistance : Float;
	var nearEndDistance : Float;
	var nearStartIntensity : Float;
	var nearEndIntensity : Float;

 	var farStartDistance : Float;
	var farEndDistance : Float;
	var farStartIntensity : Float;
	var farEndIntensity : Float;

	var showDebug : Bool;
}

class DistanceBlur extends RendererFX {

	var blurPass = new h3d.pass.ScreenFx(new DistanceBlurShader());
	var lbrBlur = new h3d.pass.Blur(9);

	public function new(?parent) {
		super(parent);
		props = ({
			nearStartDistance : 0,
			nearEndDistance : 10,
			nearStartIntensity : 1,
			nearEndIntensity : 0,
			farStartDistance : 100,
			farEndDistance : 500,
			farStartIntensity : 0,
			farEndIntensity : 1,
			showDebug : false,
		} : DistanceBlurProps);

		blurPass.pass.setBlendMode(Alpha);
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		var p : DistanceBlurProps = props;
		if( step == AfterTonemapping ) {
			var ctx = r.ctx;
			blurPass.shader.nearStartDistance = p.nearStartDistance;
			blurPass.shader.nearEndDistance = p.nearEndDistance;
			blurPass.shader.nearStartIntensity = p.nearStartIntensity;
			blurPass.shader.nearEndIntensity = p.nearEndIntensity;
			blurPass.shader.farStartDistance = p.farStartDistance;
			blurPass.shader.farEndDistance = p.farEndDistance;
			blurPass.shader.farStartIntensity = p.farStartIntensity;
			blurPass.shader.farEndIntensity = p.farEndIntensity;
			blurPass.shader.DEBUG = #if editor p.showDebug #else false #end;

			var lbrBlurred : h3d.mat.Texture = ctx.getGlobal("ldrBlurred");
			if( lbrBlurred == null ) {
				var ldr : h3d.mat.Texture = ctx.getGlobal("ldrMap");
				lbrBlurred = r.allocTarget("ldrBlurred", false, 0.25, RGBA);
				r.copy(ldr, lbrBlurred);
				lbrBlur.apply(ctx, lbrBlurred);
			}
			blurPass.shader.blurredTexture = lbrBlurred;
			blurPass.setGlobals(ctx);
			blurPass.render();
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
				<div class="group" name="Near Blur">
					<dt>Start Distance</dt><dd><input type="range" min="0" max="1000" field="nearStartDistance"/></dd>
					<dt>End Distance</dt><dd><input type="range" min="0" max="1000" field="nearEndDistance"/></dd>
					<dt>Start Opacity</dt><dd><input type="range" min="0" max="1" field="nearStartIntensity"/></dd>
					<dt>End Opacity</dt><dd><input type="range" min="0" max="1" field="nearEndIntensity"/></dd>
				</div>
				<div class="group" name="Far Blur">
					<dt>Start Distance</dt><dd><input type="range" min="0" max="1000" field="farStartDistance"/></dd>
					<dt>End Distance</dt><dd><input type="range" min="0" max="1000" field="farEndDistance"/></dd>
					<dt>Start Opacity</dt><dd><input type="range" min="0" max="1" field="farStartIntensity"/></dd>
					<dt>End Opacity</dt><dd><input type="range" min="0" max="1" field="farEndIntensity"/></dd>
				</div>
				<div class="group" name="Debug">
					<dt>Show Debug</dt><dd><input type="checkbox" field="showDebug"/></dd>
				</div>
		'),props);
	}
	#end

	static var _ = Library.register("rfx.distanceBlur", DistanceBlur);

}
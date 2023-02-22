package hrt.prefab2.rfx;

class DistanceBlurShader extends hrt.shader.PbrShader {

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
		@const var affectSky : Bool = false;

		var currentPosition : Vec3;
		var blurAmount : Float;

		function __init__fragment() {{
			currentPosition = getPosition();
			var distance = (currentPosition - camera.position).length();
			blurAmount = 0;
			if(affectSky || depthMap.get(calculatedUV) < 1) {
				if( distance < nearEndDistance ) {
					var nearIntensityFactor = clamp((distance - nearStartDistance) / (nearEndDistance - nearStartDistance), 0, 1);
					blurAmount = mix(nearStartIntensity, nearEndIntensity, nearIntensityFactor);
				}
				else if( distance > farStartDistance ) {
					var farIntensityFactor = clamp((distance - farStartDistance) / (farEndDistance - farStartDistance), 0, 1);
					blurAmount = mix(farStartIntensity, farEndIntensity, farIntensityFactor);
				}
			}
		}}

		function fragment() {
			if( blurAmount <= 0.004 ) discard;
			pixelColor = DEBUG ? vec4(blurAmount.xxx, 1.0) : vec4(blurredTexture.get(calculatedUV).rgb, blurAmount);
		}

	};

	public function new() {
		super();
	}

}

class DistanceBlur extends RendererFX {

	var blurPass = new h3d.pass.ScreenFx(new DistanceBlurShader());
	var lbrBlur = new h3d.pass.Blur();

	@:s public var nearStartDistance : Float;
	@:s public var nearEndDistance : Float;
	@:s public var nearStartIntensity : Float = 1;
	@:s public var nearEndIntensity : Float;

	@:s public var farStartDistance : Float;
	@:s public var farEndDistance : Float;
	@:s public var farStartIntensity : Float;
	@:s public var farEndIntensity : Float = 1;

	@:s public var showDebug : Bool;
	@:s public var blurTextureSize : Float;
	@:s public var blurRange : Int;

	function new(?parent) {
		super(parent);
		nearEndDistance = 10;
		farStartDistance = 100;
		farEndDistance = 500;
		blurTextureSize = 0.5;
		blurRange = 6;
		blurPass.pass.setBlendMode(Alpha);
	}

	override function end(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( !checkEnabled() ) return;
		if( step == AfterTonemapping ) {
			var ctx = r.ctx;
			blurPass.shader.nearStartDistance = nearStartDistance;
			blurPass.shader.nearEndDistance = nearEndDistance;
			blurPass.shader.nearStartIntensity = nearStartIntensity;
			blurPass.shader.nearEndIntensity = nearEndIntensity;
			blurPass.shader.farStartDistance = farStartDistance;
			blurPass.shader.farEndDistance = farEndDistance;
			blurPass.shader.farStartIntensity = farStartIntensity;
			blurPass.shader.farEndIntensity = farEndIntensity;
			blurPass.shader.DEBUG = #if editor showDebug #else false #end;

			var ldr : h3d.mat.Texture = ctx.getGlobal("ldrMap");
			var lbrBlurred = r.allocTarget("ldrBlurred", false, blurTextureSize, RGBA);
			r.copy(ldr, lbrBlurred);
			lbrBlur.radius = blurRange;
			lbrBlur.apply(ctx, lbrBlurred);

			blurPass.shader.blurredTexture = lbrBlurred;
			blurPass.setGlobals(ctx);
			blurPass.render();
		}
	}

	#if editor
	override function edit( ctx : hide.prefab2.EditContext ) {
		ctx.properties.add(new hide.Element('
				<div class="group" name="Near Blur">
					<dt>Start Distance</dt><dd><input type="range" min="0" max="20" field="nearStartDistance"/></dd>
					<dt>End Distance</dt><dd><input type="range" min="0" max="20" field="nearEndDistance"/></dd>
					<dt>Start Opacity</dt><dd><input type="range" min="0" max="1" field="nearStartIntensity"/></dd>
					<dt>End Opacity</dt><dd><input type="range" min="0" max="1" field="nearEndIntensity"/></dd>
				</div>
				<div class="group" name="Far Blur">
					<dt>Start Distance</dt><dd><input type="range" min="0" max="50" field="farStartDistance"/></dd>
					<dt>End Distance</dt><dd><input type="range" min="0" max="50" field="farEndDistance"/></dd>
					<dt>Start Opacity</dt><dd><input type="range" min="0" max="1" field="farStartIntensity"/></dd>
					<dt>End Opacity</dt><dd><input type="range" min="0" max="1" field="farEndIntensity"/></dd>
				</div>
				<div class="group" name="Blur">
					<dt>Texture Size</dt><dd><input type="range" min="0" max="1" field="blurTextureSize"/></dd>
					<dt>Range</dt><dd><input type="range" min="0" max="20" step="2" field="blurRange"/></dd>
				</div>
				<div class="group" name="Debug">
					<dt>Show Debug</dt><dd><input type="checkbox" field="showDebug"/></dd>
				</div>
		'),this);
		super.edit(ctx);
	}
	#end

	static var _ = Prefab.register("rfx.distanceBlur", DistanceBlur);

}
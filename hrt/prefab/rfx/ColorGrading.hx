package hrt.prefab.rfx;

typedef ColorGradingProps = {
	var size : Int;
	var texturePath : String;
	var intensity : Float;
}

class ColorGradingTonemap extends hxsl.Shader {
	static var SRC = {

		@param var pixelSize : Vec2;
		@param var size : Int;
		@param var intensity : Float;
		@param var lut : Sampler2D;
		var hdrColor : Vec4;
		var pixelColor : Vec4;

		function fragment() {
			var uv = min(pixelColor.rgb, vec3(1,1,1));
			var innerWidth = size - 1.0;
			var sliceSize = 1.0 / size;
			var slicePixelSize = sliceSize / size;
			var sliceInnerSize = slicePixelSize * innerWidth;
			var blueSlice0 = min(floor(uv.b * innerWidth), innerWidth);
			var blueSlice1 = min(blueSlice0 + 1.0, innerWidth);
			var xOffset = slicePixelSize * 0.5 + uv.r * sliceInnerSize;
			var yOffset = sliceSize * 0.5 + uv.g * (1.0 - sliceSize);
			var s0 = vec2(xOffset + (blueSlice0 * sliceSize), yOffset);
			var s1 = vec2(xOffset + (blueSlice1 * sliceSize), yOffset);
			var slice0Color = texture(lut, s0).rgb;
			var slice1Color = texture(lut, s1).rgb;
			var bOffset = mod(uv.b * innerWidth, 1.0);
			pixelColor.rgb = mix(pixelColor.rgb, mix(slice0Color, slice1Color, bOffset), intensity);
		}
	}
}

class ColorGrading extends RendererFX {

	var tonemap = new ColorGradingTonemap();

	public function new(?parent) {
		super(parent);
		props = ({
			size : 16,
			texturePath : null,
			intensity : 1.0,
		} : ColorGradingProps);
	}

	override function end( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		if( step == BeforeTonemapping ) {
			r.mark("ColorGrading");
			var p : ColorGradingProps = props;
			tonemap.pixelSize = new h3d.Vector(1.0/r.ctx.engine.width, 1.0/r.ctx.engine.height);
			tonemap.intensity = p.intensity;
			tonemap.size = p.size;
			if( p.texturePath != null )
				tonemap.lut = hxd.res.Loader.currentInstance.load(p.texturePath).toTexture();
			if( tonemap.lut != null && p.intensity > 0 )
				r.addShader(tonemap);
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<div class="group" name="Color Grading">
				<dl>
					<dt>LUT</dt><dd><input type="texturepath" field="texturePath"/></dd>
					<dt>Size</dt><dd><input type="range" min="1" max="256" step="1" field="size"/></dd>
					<dt>Intensity</dt><dd><input type="range" min="0" max="1" field="intensity"/></dd>
				</dl>
			</div>
		'),props);
	}
	#end

	static var _ = Library.register("rfx.colorGrading", ColorGrading);

}
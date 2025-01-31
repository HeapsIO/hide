package hrt.prefab.rfx;

import hxd.Pixels;

class ColorGradingFunc extends hxsl.Shader {
	static var SRC = {
		function getColorGrading(base : Vec3, lut : Sampler2D, size : Float) : Vec3 {
			var innerWidth = size - 1.0;
			var sliceSize = 1.0 / size;
			var slicePixelSize = sliceSize / size;
			var sliceInnerSize = slicePixelSize * innerWidth;
			var blueSlice0 = min(floor(base.b * innerWidth), innerWidth);
			var blueSlice1 = min(blueSlice0 + 1.0, innerWidth);
			var xOffset = slicePixelSize * 0.5 + base.r * sliceInnerSize;
			var yOffset = sliceSize * 0.5 + base.g * (1.0 - sliceSize);
			var s0 = vec2(xOffset + (blueSlice0 * sliceSize), yOffset);
			var s1 = vec2(xOffset + (blueSlice1 * sliceSize), yOffset);
			var slice0Color = texture(lut, s0).rgb;
			var slice1Color = texture(lut, s1).rgb;
			var bOffset = mod(base.b * innerWidth, 1.0);
			return mix(slice0Color, slice1Color, bOffset);
		}
	}
}

class ColorGradingTonemap extends hxsl.Shader {
	static var SRC = {

		@param var size : Int;
		@param var intensity : Float;
		@param var lut : Sampler2D;
		var hdrColor : Vec4;
		var pixelColor : Vec4;

		@:import ColorGradingFunc;

		function fragment() {
			var colorGrading = getColorGrading(pixelColor.rgb, lut, size);
			pixelColor.rgb = mix(pixelColor.rgb, colorGrading, intensity);
		}
	}
}
@:access(h3d.scene.Renderer)
class ColorGrading extends RendererFX {

	var tonemap = new ColorGradingTonemap();
	public var customLut : h3d.mat.Texture;

	@:s var size : Int = 16;
	@:s var texturePath : String;
	@:s public var intensity : Float = 1;

	public function getLutTexture() {
		if( texturePath == null ) return null;
		return hxd.res.Loader.currentInstance.load(texturePath).toTexture();
	}

	override function end( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		if( !checkEnabled() ) return;
		if( step == BeforeTonemapping ) {
			r.mark("ColorGrading");
			tonemap.intensity = intensity;
			tonemap.size = size;
			tonemap.lut = customLut != null ? customLut : getLutTexture();
			if( tonemap.lut != null && intensity > 0 )
				r.addShader(tonemap);
		}
	}

	#if editor

	override function edit( ctx : hide.prefab.EditContext ) {

		var e = new hide.Element('
			<div class="group" name="Color Grading">
				<dl>
					<dt>LUT</dt><dd><input type="texturepath" field="texturePath"/></dd>
					<dt>Size</dt><dd><input type="range" min="1" max="256" step="1" field="size"/></dd>
					<dt>Intensity</dt><dd><input type="range" min="0" max="1" field="intensity"/></dd>
				</dl>
			</div>
			<div class="group" name="Debug">
				<div align="center" >
					<input type="button" value="Create default" class="createDefault" />
				</div>
			</div>
		');

		var but = e.find(".createDefault");
		but.click(function(_) {
			function saveTexture( name : String ) {
				var step = hxd.Math.ceil(255/(size - 1));
				var p = hxd.Pixels.alloc(size * size, size, RGBA);
				for( r in 0 ... size ) {
					for( g in 0 ... size ) {
						for( b in 0 ... size ) {
							p.setPixel(r + b * size, g, 255 << 24 | ((r*step) << 16) | ((g*step) << 8 ) | (b*step));
						}
					}
				}
				var path = ctx.ide.getPath(name);
				sys.io.File.saveBytes(path, p.toPNG());
				p.dispose();
			}
			ctx.ide.chooseFileSave("defaultLUT.png", saveTexture);
		});

		ctx.properties.add(e, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Prefab.register("rfx.colorGrading", ColorGrading);

}
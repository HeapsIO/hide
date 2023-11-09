package hide.view;

private class ImageViewerShader extends hxsl.Shader {

	static var SRC = {

		@param var compressedTex : Sampler2D;
		@param var uncompressedTex : Sampler2D;
		@param var textureCube : SamplerCube;
		@param var textureArray : Sampler2DArray;
		@param var layer : Float;
		@param var mipLod : Float;
		@param var exposure : Float;
		@param var comparisonFactor : Float;

		@const var channels : Int;
		@const var isCube : Bool;
		@const var isArray : Bool;

		var pixelColor : Vec4;
		var calculatedUV : Vec2;
		var transformedNormal : Vec3;

		function fragment() {
			if( isCube )
				pixelColor = textureCube.getLod(transformedNormal, mipLod);
			else if( isArray )
				pixelColor = textureArray.getLod(vec3(calculatedUV, layer), mipLod);
			else {
				if (calculatedUV.x > comparisonFactor)
					pixelColor = uncompressedTex.getLod(calculatedUV, mipLod);
				else
					pixelColor = compressedTex.getLod(calculatedUV, mipLod);
			}
			pixelColor.rgb *= pow(2, exposure);
			switch( channels ) {
			case 0, 15:
				// nothing
			case 1:
				pixelColor = vec4(pixelColor.rrr, 1.);
			case 2:
				pixelColor = vec4(pixelColor.ggg, 1.);
			case 4:
				pixelColor = vec4(pixelColor.bbb, 1.);
			case 8:
				pixelColor = vec4(pixelColor.aaa, 1.);
			default:
				if( channels & 1 == 0 ) pixelColor.r = 0;
				if( channels & 2 == 0 ) pixelColor.g = 0;
				if( channels & 4 == 0 ) pixelColor.b = 0;
				if( channels & 8 == 0 ) pixelColor.a = 1;
			}
		}

	}

}

enum ViewMode {
	Compressed;
	Uncompressed;
	Comparison;
}

class Image extends FileView {

	var bmp : h2d.Bitmap;
	var sliderBmp : h2d.Bitmap;
	var scene : hide.comp.Scene;
	var viewMode : ViewMode = Compressed;
	var interactive : h2d.Interactive;
	var tools : hide.comp.Toolbar;
	var sliderTexture : Null<h3d.mat.Texture>;

	override function onDisplay() {
		element.html('
			<div class="flex vertical">
				<div class="toolbar"></div>
				<div class="heaps-scene">
				</div>
			</div>
		');

		cleanUp();

		scene = new hide.comp.Scene(config, null, element.find(".heaps-scene"));

		this.saveDisplayKey = state.path;
		this.viewMode = getDisplayState("ViewMode");
		if (this.viewMode == null)
			this.viewMode = Compressed;

		var shader = new ImageViewerShader();

		tools = new hide.comp.Toolbar(null,element.find(".toolbar"));

		tools.addSeparator();

		var tgCompressed = tools.addToggle("file-zip-o", "Show compressed texture", "", function (e) {
			tools.element.find(".show-uncompressed").removeAttr("checked");
			tools.element.find(".show-comparison").removeAttr("checked");

			if (bmp != null) {
				this.saveDisplayState("ViewMode", Compressed);
				this.viewMode = Compressed;
				
				applyShaderConfiguration(shader);
			}
		}, this.viewMode.match(Compressed));
		tgCompressed.element.addClass("show-compressed");

		var tgUncompressed = tools.addToggle("file-image-o", "Show uncompressed texture", "", function (e) {
			tools.element.find(".show-compressed").removeAttr("checked");
			tools.element.find(".show-comparison").removeAttr("checked");

			if (bmp != null) {
				this.saveDisplayState("ViewMode", Uncompressed);
				this.viewMode = Uncompressed;

				applyShaderConfiguration(shader);
			}

		}, this.viewMode.match(Uncompressed));
		tgUncompressed.element.addClass("show-uncompressed");

		var tgComparison = tools.addToggle("arrows-h", "Show comparison between compressed and uncompressed texture", "", function (e) {
			tools.element.find(".show-uncompressed").removeAttr("checked");
			tools.element.find(".show-compressed").removeAttr("checked");
			
			if (bmp != null) {
				this.saveDisplayState("ViewMode", Comparison);
				this.viewMode = Comparison;

				applyShaderConfiguration(shader);
			}
			
		}, this.viewMode.match(Comparison));
		tgComparison.element.addClass("show-comparison");

		tools.addSeparator();

		tools.addPopup(null, "Compression", (e) -> new hide.comp.SceneEditor.CompressionPopup(null, e, state.path), null);

		tools.addSeparator();
		
		scene.onReady = function() {
			scene.loadTexture(state.path, state.path, function(compressedTexture) {
				scene.loadTexture(state.path, state.path, function(uncompressedTexture) {
					var path = hide.Ide.inst.appPath + "/res/sliderTexture.png";
					scene.loadTexture(path, path, function(sliderTexture) {
						this.sliderTexture = sliderTexture;
						onTexturesLoaded(compressedTexture, uncompressedTexture, shader, tgCompressed, tgUncompressed, tgComparison);
					}, false);
				}, false, true);
			}, false);
		};
	}

	override function onRebuild() {
		if ( scene != null ) {
			scene.dispose();
			scene = null;
		}
		super.onRebuild();
	}

	override function onResize() {
		if( bmp == null ) return;
		var scale = Math.min(1,Math.min((contentWidth - 20) / bmp.tile.width, (contentHeight - 20) / bmp.tile.height));
		bmp.setScale(scale * js.Browser.window.devicePixelRatio);
		bmp.x = -Std.int(bmp.tile.width * bmp.scaleX) >> 1;
		bmp.y = -Std.int(bmp.tile.height * bmp.scaleY) >> 1;
	}

	public function onTexturesLoaded(compressedTexture: Null<h3d.mat.Texture>, uncompressedTexture: Null<h3d.mat.Texture>, shader : ImageViewerShader, tgCompressed : hide.comp.Toolbar.ToolToggle, tgUncompressed : hide.comp.Toolbar.ToolToggle, tgComparison : hide.comp.Toolbar.ToolToggle) {
		for( i in 0...4 ) {
			var name = "RGBA".charAt(i);
			tools.addToggle("", "Channel "+name, name, function(b) {
				shader.channels &= ~(1 << i);
				if( b ) shader.channels |= 1 << i;
			});
		}

		if( !compressedTexture.flags.has(Cube) ) {
			bmp = new h2d.Bitmap(h2d.Tile.fromTexture(compressedTexture), scene.s2d);
			bmp.addShader(shader);
			if( compressedTexture.layerCount > 1 ) {
				shader.isArray = true;
				shader.textureArray = cast(compressedTexture, h3d.mat.TextureArray);
				tools.addRange("Layer", function(f) shader.layer = f, 0, 0, compressedTexture.layerCount-1, 1);
			} else
			shader.compressedTex = compressedTexture;
			shader.uncompressedTex = uncompressedTexture;
			shader.comparisonFactor = 0.5;
			new hide.view.l3d.CameraController2D(scene.s2d);
		} else {
			var r = new h3d.scene.fwd.Renderer();
			var ls = new h3d.scene.fwd.LightSystem();
			ls.ambientLight.set(1,1,1,1);
			scene.s3d.lightSystem = ls;
			scene.s3d.renderer = r;
			var sp = new h3d.prim.Sphere(1,64,64);
			sp.addNormals();
			sp.addUVs();
			shader.textureCube = compressedTexture;
			shader.isCube = true;
			var sp = new h3d.scene.Mesh(sp, scene.s3d);
			sp.material.texture = compressedTexture;
			sp.material.mainPass.addShader(shader);
			sp.material.shadows = false;
			new h3d.scene.CameraController(5,scene.s3d);
		}

		if( compressedTexture.flags.has(MipMapped) ) {
			compressedTexture.mipMap = Linear;
			tools.addRange("MipMap", function(f) shader.mipLod = f, 0, 0, compressedTexture.mipLevels - 1);
		}

		if( hxd.Pixels.isFloatFormat(compressedTexture.format) ) {
			tools.addRange("Exposure", function(f) shader.exposure = f, 0, -10, 10);
		}

		applyShaderConfiguration(shader);
		onResize();
	}

	public function applyShaderConfiguration(shader : ImageViewerShader) {
		switch (this.viewMode) {
			case  Compressed:
				{
					shader.comparisonFactor = 1;

					if (interactive != null)
						interactive.remove();

					if (sliderBmp != null)
						sliderBmp.alpha = 0;
				}

			case Uncompressed:
				{
					shader.comparisonFactor = 0;

					if (interactive != null)
						interactive.remove();

					if (sliderBmp != null)
						sliderBmp.alpha = 0;
				}

			case Comparison:
				{
					if (sliderBmp == null)
						sliderBmp = new h2d.Bitmap(h2d.Tile.fromTexture(sliderTexture), bmp);
					else 
						sliderBmp.alpha = 1;

					bmp.addChild(sliderBmp);
					sliderBmp.height = bmp.tile.height;
			
					var bounds = new h2d.col.Bounds();
					sliderBmp.getSize(bounds);
			
					if (interactive != null)
						interactive.remove();

					interactive = new h2d.Interactive(bmp.tile.width,bmp.tile.height,bmp);
					interactive.propagateEvents = true;
					interactive.x = bmp.tile.dx;
					interactive.y = bmp.tile.dy;
			
					sliderBmp.x = bmp.tile.width / 2.0 - bounds.width / 2.0;
					shader.comparisonFactor = 0.5;
					var clicked = false;
			
					function updateSlider(e: hxd.Event) {
						if (!clicked)
							return;
			
						sliderBmp.x = e.relX - bounds.width / 2.0;
						shader.comparisonFactor = e.relX / interactive.width;
					}
			
					interactive.onPush = function (e) {
						clicked = true;
						updateSlider(e);
					}
			
					interactive.onRelease = function (e) {
						clicked = false;
					}
			
					interactive.onMove = function (e) {
						updateSlider(e);
					};
				}
			
				default:
					trace("Not implemented yet");
		}
	}

	public function cleanUp() {
		if (scene != null)
			scene.dispose();

		sliderBmp = null;
		bmp = null;
		interactive = null;
		sliderTexture = null;
	}

	static var _ = FileTree.registerExtension(Image,hide.Ide.IMG_EXTS.concat(["envd","envs"]),{ icon : "picture-o" });

}
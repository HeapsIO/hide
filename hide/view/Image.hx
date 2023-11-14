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
	var shader : ImageViewerShader;
	var viewMode : ViewMode = Compressed;
	var interactive : h2d.Interactive;
	var tools : hide.comp.Toolbar;
	var sliderTexture : Null<h3d.mat.Texture>;

	override function onDisplay() {
		cleanUp();

		element.html('
			<div class="flex vertical">
				<div class="toolbar"></div>
				<div class="scene-partition" style="display: flex; flex-direction: row; flex: 1; overflow: hidden;">
					<div class="heaps-scene"></div>
					<div class="image-properties">
						<div class="title">Image compression</div>
						<div class="compression-infos"></div>
						<input type="button" class="reset-preview" value="Reset preview"/>
						<input type="button" class="save-compression" value="Save"/>
					</div>
				</div>
			</div>
		');
	
		scene = new hide.comp.Scene(config, null, element.find(".heaps-scene"));

		function addField(parent: Element, label:String, selectClass:String, options:Array<String>) {
			var field = new Element('<div class="field">
				<label>${label}</label>
				<select class="${selectClass}">
				</select>
			</div>');

			var select = field.find(".select-format");
			for (opt in options) {
				select.append(new Element('<option value="${opt}">${opt}</option>'));
			}

			parent.append(field);
		}

		var compressionInfo = element.find(".compression-infos");
		addField(compressionInfo, "Format :", "select-format", ["none", "BC1", "BC2", "BC3", "RGBA", "R16F", "RG16F", "RGBA16F", "R32F", "RG32F", "RGBA32F", "R16U", "RG16U", "RGBA16U"] );
		
		var mipsField = new Element('<div class="field">
			<label>Mip maps :</label>
			<input type="checkbox" class="mips-checkbox"></input>
		</div>');
		compressionInfo.append(mipsField);

		var sizeField = new Element('<div class="field">
			<label>Size :</label>
			<input type="text" class="size"></input>
		</div>');
		compressionInfo.append(sizeField);

		var alphaField = new Element('<div class="field">
			<label>Alpha :</label>
			<input type="text" class="alpha-threshold"></input>
		</div>');
		compressionInfo.append(alphaField);

		var format = compressionInfo.find(".select-format");
		var mips = compressionInfo.find(".mips-checkbox");
		var size = compressionInfo.find(".size");
		var alpha = compressionInfo.find(".alpha-threshold");

		var fs:hxd.fs.LocalFileSystem = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		@:privateAccess var textureConvertRule = fs.convert.getConvertRule(state.path);

		var convertRuleEmpty = textureConvertRule == null || textureConvertRule.cmd == null || textureConvertRule.cmd.params == null;
		
		format.val(convertRuleEmpty ? "none" : textureConvertRule.cmd.params.format);
		format.on("change", function(_) {
			createPreviewTexture(format, alpha, mips, size);

			// Alpha treshold make sense for BC1 format
			if (format.val() != "BC1")
				alpha.parent().css({"display":"none"});
			else 
				alpha.parent().css({"display":"flex"});
		});

		alpha.val(convertRuleEmpty || Reflect.field(textureConvertRule.cmd.params, "alpha") == null ? "undefined" : textureConvertRule.cmd.params.alpha);
		alpha.on("change", function(_) {
			createPreviewTexture(format, alpha, mips, size);
		});

		// Alpha treshold make sense for BC1 format
		if (format.val() != "BC1")
			alpha.parent().css({"display":"none"});
		else 
			alpha.parent().css({"display":"flex"});

		// Alpha treshold make sense for BC1 format
		if (format.val() != "BC1")
			alpha.parent().css({"display":"none"});

		size.val(convertRuleEmpty || Reflect.field(textureConvertRule.cmd.params, "size") == null ? "undefined" : textureConvertRule.cmd.params.size);
		size.on("change", function(_) {
			createPreviewTexture(format, alpha, mips, size);
		});

		if (!convertRuleEmpty && textureConvertRule.cmd.params.mips)
			mips.prop("checked", true);
		else
			mips.removeProp("checked");

		mips.on("change", function(_) {
			createPreviewTexture(format, alpha, mips, size);
		});

		this.saveDisplayKey = state.path;
		this.viewMode = getDisplayState("ViewMode");
		if (this.viewMode == null)
			this.viewMode = Compressed;

		var dirPos = state.path.lastIndexOf("/");
		var dirPath = dirPos < 0 ? state.path : state.path.substr(0, dirPos + 1);

		var resetPreview = element.find(".reset-preview");
		resetPreview.on("click", function(_) {
			format.val(convertRuleEmpty ? "none" : textureConvertRule.cmd.params.format);
			alpha.val(convertRuleEmpty || Reflect.field(textureConvertRule.cmd.params, "alpha") == null ? "undefined" : textureConvertRule.cmd.params.alpha);
			size.val(convertRuleEmpty || Reflect.field(textureConvertRule.cmd.params, "size") == null ? "undefined" : textureConvertRule.cmd.params.size);

			if (convertRuleEmpty && textureConvertRule.cmd.params.mips)
				mips.prop("checked", true);
			else
				mips.removeProp("checked");

			// Alpha treshold make sense for BC1 format
			if (format.val() != "BC1")
				alpha.parent().css({"display":"none"});
			else 
				alpha.parent().css({"display":"flex"});

			createPreviewTexture(format, alpha, mips, size);
		});

		var saveCompression = element.find(".save-compression");
		saveCompression.on("click", function(_) {
			var bytes = new haxe.io.BytesOutput();
			var convertRule = { };

			if (format.val() == "none") {
				convertRule = { convert : "none" };
			}
			else {
				convertRule = { convert : "dds", format : format.val(), mips : mips.is(':checked') };
				
				if (size.val() != "undefined")
					Reflect.setField(convertRule, "size", size.val());

				if (alpha.val() != "undefined")
					Reflect.setField(convertRule, "alpha", alpha.val());
			}

			var propsFilePath = ide.getPath(dirPath + "props.json");
			if (sys.FileSystem.exists(propsFilePath)) {
				var propsJson = haxe.Json.parse(sys.io.File.getContent(propsFilePath));

				if (Reflect.hasField(propsJson, "fs.convert")) {
					var fsConvertObj = Reflect.getProperty(propsJson, "fs.convert");
					Reflect.setField(fsConvertObj, state.path, convertRule);
				}

				var data = haxe.Json.stringify(propsJson, "\t");
				bytes.writeString(data);
				hxd.File.saveBytes(propsFilePath, bytes.getBytes());
			} else {
				var fsConvertObj = { };
				var pathObj = { };

				Reflect.setProperty(pathObj, state.path, convertRule);
				Reflect.setProperty(fsConvertObj, "fs.convert", pathObj);

				var data = haxe.Json.stringify(fsConvertObj, "\t");
				bytes.writeString(data);
				hxd.File.saveBytes(propsFilePath, bytes.getBytes());
			}

			// todo : trigger converter
			// var localEntry = @:privateAccess new hxd.fs.LocalFileSystem.LocalEntry(fs, name, state.path, Ide.inst.getPath(state.path));
			// fs.convert.run(localEntry);
		});

		shader = new ImageViewerShader();

		tools = new hide.comp.Toolbar(null,element.find(".toolbar"));

		tools.addSeparator();

		var tgCompressed = tools.addToggle("file-zip-o", "Show compressed texture", "", function (e) {
			tools.element.find(".show-uncompressed").removeAttr("checked");
			tools.element.find(".show-comparison").removeAttr("checked");

			if (bmp != null) {
				this.saveDisplayState("ViewMode", Compressed);
				this.viewMode = Compressed;
				
				applyShaderConfiguration();
			}
		}, this.viewMode.match(Compressed));
		tgCompressed.element.addClass("show-compressed");

		var tgUncompressed = tools.addToggle("file-image-o", "Show uncompressed texture", "", function (e) {
			tools.element.find(".show-compressed").removeAttr("checked");
			tools.element.find(".show-comparison").removeAttr("checked");

			if (bmp != null) {
				this.saveDisplayState("ViewMode", Uncompressed);
				this.viewMode = Uncompressed;

				applyShaderConfiguration();
			}

		}, this.viewMode.match(Uncompressed));
		tgUncompressed.element.addClass("show-uncompressed");

		var tgComparison = tools.addToggle("arrows-h", "Show comparison between compressed and uncompressed texture", "", function (e) {
			tools.element.find(".show-uncompressed").removeAttr("checked");
			tools.element.find(".show-compressed").removeAttr("checked");
			
			if (bmp != null) {
				this.saveDisplayState("ViewMode", Comparison);
				this.viewMode = Comparison;

				applyShaderConfiguration();
			}
			
		}, this.viewMode.match(Comparison));
		tgComparison.element.addClass("show-comparison");

		tools.addSeparator();
		
		scene.onReady = function() {
			scene.loadTexture(state.path, state.path, function(compressedTexture) {
				scene.loadTexture(state.path, state.path, function(uncompressedTexture) {
					var path = hide.Ide.inst.appPath + "/res/sliderTexture.png";
					scene.loadTexture(path, path, function(sliderTexture) {
						this.sliderTexture = sliderTexture;
						uncompressedTexture.filter = Nearest;
						onTexturesLoaded(compressedTexture, uncompressedTexture);
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

	public function onTexturesLoaded(compressedTexture: Null<h3d.mat.Texture>, uncompressedTexture: Null<h3d.mat.Texture>) {
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
			tools.addRange("MipMap", function(f) shader.mipLod = f, 0, 0, compressedTexture.mipLevels - 1, "mipmap");
		}

		if( hxd.Pixels.isFloatFormat(compressedTexture.format) ) {
			tools.addRange("Exposure", function(f) shader.exposure = f, 0, -10, 10);
		}

		applyShaderConfiguration();
		onResize();
	}

	public function applyShaderConfiguration() {
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
		shader = null;
	}
	
	public function replaceImage(path : String) {
		var bytes = sys.io.File.getBytes(path);
		var res = hxd.res.Any.fromBytes(path, bytes);
		var t = res.toTexture();

		if (bmp != null) {
			bmp.remove();
			bmp = null;
		}

		if( !t.flags.has(Cube) ) {
			bmp = new h2d.Bitmap(h2d.Tile.fromTexture(t), scene.s2d);
			bmp.addShader(shader);
			if( t.layerCount > 1 ) {
				shader.isArray = true;
				shader.textureArray = cast(t, h3d.mat.TextureArray);
				tools.addRange("Layer", function(f) shader.layer = f, 0, 0, t.layerCount-1, 1);
			} else
			shader.compressedTex = t;
		} else {
			var r = new h3d.scene.fwd.Renderer();
			var ls = new h3d.scene.fwd.LightSystem();
			ls.ambientLight.set(1,1,1,1);
			scene.s3d.lightSystem = ls;
			scene.s3d.renderer = r;
			var sp = new h3d.prim.Sphere(1,64,64);
			sp.addNormals();
			sp.addUVs();
			shader.textureCube = t;
			shader.isCube = true;
			var sp = new h3d.scene.Mesh(sp, scene.s3d);
			sp.material.texture = t;
			sp.material.mainPass.addShader(shader);
			sp.material.shadows = false;
			new h3d.scene.CameraController(5,scene.s3d);
		}

		tools.element.find(".hide-range").remove();

		if( t.flags.has(MipMapped) ) {
			t.mipMap = Linear;
			tools.addRange("MipMap", function(f) shader.mipLod = f, 0, 0, t.mipLevels - 1, "mipmap");
		}

		if( hxd.Pixels.isFloatFormat(t.format) ) {
			tools.addRange("Exposure", function(f) shader.exposure = f, 0, -10, 10);
		}

		applyShaderConfiguration();
		onResize();
	}

	public function createPreviewTexture(format: Element, alpha: Element, mips: Element, size: Element) {
		var dirPos = state.path.lastIndexOf("/");
		var name = dirPos < 0 ? state.path : state.path.substr(dirPos + 1);
		var tmpPath = StringTools.replace(Sys.getEnv("TEMP"), "\\","/") + "/tempTexture.dds";

		if (format.val().toString() != "none") {
			var comp = new hxd.fs.Convert.CompressIMG("png,tga,jpg,jpeg,dds,envd,envs","dds");
			comp.srcPath = Ide.inst.getPath(state.path);
			comp.dstPath = Ide.inst.getPath(tmpPath);
			comp.originalFilename = name;
			var val = mips.val();
			comp.params = { alpha:Std.parseInt(alpha.val()), format:format.val().toString(), mips:mips.is(':checked'), size:Std.parseInt(size.val()) };
			comp.convert();
		}
		else {
			tmpPath = state.path;
		}
			
		replaceImage(Ide.inst.getPath(tmpPath));
	}

	static var _ = FileTree.registerExtension(Image,hide.Ide.IMG_EXTS.concat(["envd","envs"]),{ icon : "picture-o" });

}
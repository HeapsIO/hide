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
	var sliderBmp : h2d.Graphics;
	var scene : hide.comp.Scene;
	var shader : ImageViewerShader;
	var viewMode : ViewMode = Compressed;
	var interactive : h2d.Interactive;
	var tools : hide.comp.Toolbar;
	var cam : Dynamic;

	override function onDisplay() {
		cleanUp();

		element.html('
			<div class="flex vertical">
				<div class="toolbar"></div>
				<div class="scene-partition" style="display: flex; flex-direction: row; flex: 1; overflow: hidden;">
				<div class="heaps-scene"></div>
				<div class="image-properties">
					<div class="title">Image compression</div>
					<div class="compression-infos">
						<p class="comp-tex-weight">Compressed texture weight : missing info </p>
						<p class="uncomp-tex-weight">Uncompressed texture weight : missing info</p>
					</div>
						<div class="preview-btns">
							<input type="button" class="reset-preview" value="Reset preview" title="Reset preview compression."/>
							<input type="button" class="save-compression" value="Save" title="Save current compression options into a props.json file."/>
						</div>
						<input type="button" class="reset-compression" value="Reset compression" title="Remove the current compression\'s rules applied to this texture, from props.json file."/>
					</div>
				</div>
				<div class="identifiers">
					<label>Compressed</label>
					<label>Uncompressed</label>
				</div>
			</div>
		');

		scene = new hide.comp.Scene(config, null, element.find(".heaps-scene"));

		function addField(parent: Element, label:String, title:String, selectClass:String, options:Array<String>) {
			var field = new Element('<div class="field">
				<label>${label}</label>
				<select class="${selectClass}" title="${title}">
				</select>
			</div>');

			var select = field.find(".select-format");
			for (opt in options) {
				select.append(new Element('<option value="${opt}">${opt}</option>'));
			}

			parent.append(field);
		}

		var compressionInfo = element.find(".compression-infos");
		var nativeFormat = new Element('<div class="field">
		<label>Native format :</label>
		<label class="native-format">Unknown</label>
		</div>');
		compressionInfo.append(nativeFormat);

		addField(compressionInfo, "Format :", "Compression format used to compress texture", "select-format", ["none", "BC1", "BC2", "BC3", "RGBA", "R16F", "RG16F", "RGBA16F", "R32F", "RG32F", "RGBA32F", "R16U", "RG16U", "RGBA16U"] );

		var alphaField = new Element('<div class="field alpha">
			<label>Alpha :</label>
			<input type="checkbox" class="use-alpha" title="Does the BC1 format use alpha"></input>
			<input type="number" class="alpha-threshold" placeholder="Alpha threshold" title="Alpha threshold value"></input>
		</div>');
		compressionInfo.append(alphaField);

		var mipsField = new Element('<div class="field">
		<label>Mip maps :</label>
		<input type="checkbox" class="mips-checkbox" title="Generate mip maps for the texture"></input>
		</div>');
		compressionInfo.append(mipsField);

		var sizeField = new Element('<div class="field">
		<label>Size :</label>
		<input type="number" class="size"></input>
		<label class="max-size">/ 128 px</label>
		</div>');
		compressionInfo.append(sizeField);

		var format = compressionInfo.find(".select-format");
		var mips = compressionInfo.find(".mips-checkbox");
		var size = compressionInfo.find(".size");
		var useAlpha = compressionInfo.find(".use-alpha");
		var alpha = compressionInfo.find(".alpha-threshold");

		format.on("change", function(_) {
			createPreviewTexture(format, useAlpha, alpha, mips, size);

			// Alpha treshold make sense for BC1 format
			if (format.val() != "BC1")
				alpha.parent().css({"display":"none"});
			else
				alpha.parent().css({"display":"flex"});
		});

		useAlpha.on("change", function(_) {
			if (useAlpha.is(':checked')) {
				alpha.removeAttr("disabled");

				if (alpha.val() == null || alpha.val() == "")
					alpha.val(128);
			}
			else {
				alpha.prop("disabled", true);
			}

			createPreviewTexture(format, useAlpha, alpha, mips, size);
		});

		alpha.on("change", function(_) {
			createPreviewTexture(format, useAlpha, alpha, mips, size);
		});

		size.on("change", function(_) {
			createPreviewTexture(format, useAlpha, alpha, mips, size);
		});

		mips.on("change", function(_) {
			createPreviewTexture(format, useAlpha, alpha, mips, size);
		});

		var fs:hxd.fs.LocalFileSystem = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		@:privateAccess var textureConvertRule = fs.convert.getConvertRule(state.path);

		var convertRuleEmpty = textureConvertRule == null || textureConvertRule.cmd == null || textureConvertRule.cmd.params == null;

		this.saveDisplayKey = state.path;
		this.viewMode = getDisplayState("ViewMode");
		if (this.viewMode == null)
			this.viewMode = Compressed;

		var identifiers = element.find(".identifiers");
		identifiers.css(this.viewMode.match(ViewMode.Comparison) ? {"visibility":"inherit"} : {"visibility":"hidden"});

		var dirPos = state.path.lastIndexOf("/");
		var dirPath = dirPos < 0 ? state.path : state.path.substr(0, dirPos + 1);
		var name = dirPos < 0 ? state.path : state.path.substr(dirPos + 1);
		var propsFilePath = ide.getPath(dirPath + "props.json");

		var resetPreview = element.find(".reset-preview");
		resetPreview.on("click", function(_) {
			var texMaxSize = getTextureMaxSize();
			format.val(convertRuleEmpty ? "none" : textureConvertRule.cmd.params.format);
			alpha.val(convertRuleEmpty || Reflect.field(textureConvertRule.cmd.params, "alpha") == null ? null : textureConvertRule.cmd.params.alpha);
			size.val(convertRuleEmpty || Reflect.field(textureConvertRule.cmd.params, "size") == null ? texMaxSize : textureConvertRule.cmd.params.size);

			if (!convertRuleEmpty && Reflect.field(textureConvertRule.cmd.params, "alpha") != null) {
				useAlpha.prop("checked", true);
				alpha.removeAttr("disabled");
				alpha.val(128);
			}
			else {
				useAlpha.prop("checked", false);
				alpha.prop("disabled", true);
				alpha.val(null);
			}

			if (!convertRuleEmpty && textureConvertRule.cmd.params.mips)
				mips.prop("checked", true);
			else
				mips.removeProp("checked");

			// Alpha treshold make sense for BC1 format
			if (format.val() != "BC1")
				alpha.parent().css({"display":"none"});
			else
				alpha.parent().css({"display":"flex"});

			createPreviewTexture(format, useAlpha, alpha, mips, size);
		});

		var saveCompression = element.find(".save-compression");
		saveCompression.on("click", function(_) {
			var texMaxSize = getTextureMaxSize();
			var bytes = new haxe.io.BytesOutput();
			var convertRule = { };

			if (format.val() == "none") {
				convertRule = { convert : "none", priority: 10000000 };
			}
			else {
				convertRule = { convert : "dds", format : format.val(), mips : mips.is(':checked'), priority: 10000000 };

				if (size.val() != texMaxSize)
					Reflect.setField(convertRule, "size", size.val());

				if (useAlpha.is(':checked'))
					Reflect.setField(convertRule, "alpha", alpha.val());
			}

			if (sys.FileSystem.exists(propsFilePath)) {
				var propsJson = haxe.Json.parse(sys.io.File.getContent(propsFilePath));

				if (Reflect.hasField(propsJson, "fs.convert")) {
					var fsConvertObj = Reflect.getProperty(propsJson, "fs.convert");
					Reflect.setField(fsConvertObj, state.path, convertRule);
				}
				else {
					var fsConvertObj = {} ;
					Reflect.setField(fsConvertObj, state.path, convertRule);
					Reflect.setProperty(propsJson, "fs.convert", fsConvertObj);
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

			@:privateAccess fs.convert.configs.clear();
			@:privateAccess fs.convert.loadConfig(state.path);

			var localEntry = @:privateAccess new hxd.fs.LocalFileSystem.LocalEntry(fs, name, state.path, Ide.inst.getPath(state.path));
			fs.convert.run(localEntry);
		});

		var resetCompression = element.find(".reset-compression");
		resetCompression.on("click", function(_) {
			if (!sys.FileSystem.exists(propsFilePath))
				ide.message('The file ${propsFilePath} does not exist !');

			var rulesObj = haxe.Json.parse(sys.io.File.getContent(propsFilePath));

			var fsConvertObj = Reflect.getProperty(rulesObj, "fs.convert");
			if (fsConvertObj == null || Reflect.getProperty(fsConvertObj, state.path) == null)
				ide.message('The file ${propsFilePath} does not contain compression rule for ${state.path} !');
			else {
				if(!ide.confirm('Do you really want to remove ${state.path} from ${propsFilePath} ?'))
					return;

				Reflect.deleteField(fsConvertObj, state.path);

				if (Reflect.fields(fsConvertObj).length == 0)
					Reflect.deleteField(rulesObj, "fs.convert");

				if (Reflect.fields(rulesObj).length == 0) {
					sys.FileSystem.deleteFile(propsFilePath);
					updateImageCompressionInfos();
					replaceImage(ide.getPath(state.path));
					return;
				}
			}

			var bytes = new haxe.io.BytesOutput();
			var data = haxe.Json.stringify(rulesObj, "\t");
			bytes.writeString(data);
			hxd.File.saveBytes(propsFilePath, bytes.getBytes());

			updateImageCompressionInfos();
			replaceImage(ide.getPath(state.path));
		});

		shader = new ImageViewerShader();
		tools = new hide.comp.Toolbar(null,element.find(".toolbar"));

		tools.addSeparator();

		var tgCompressed = tools.addToggle("show-compressed", "file-zip-o", "Show compressed texture", "", function (e) {
			tools.element.find(".show-uncompressed").removeAttr("checked");
			tools.element.find(".show-comparison").removeAttr("checked");

			if (bmp != null) {
				this.saveDisplayState("ViewMode", Compressed);
				this.viewMode = Compressed;

				var identifiers = element.find(".identifiers");
				identifiers.css(this.viewMode.match(ViewMode.Comparison) ? {"visibility":"inherit"} : {"visibility":"hidden"});

				applyShaderConfiguration();
			}
		}, this.viewMode.match(Compressed), null, false);
		tgCompressed.element.addClass("show-compressed");

		var tgUncompressed = tools.addToggle("show-uncompressed","file-image-o", "Show uncompressed texture", "", function (e) {
			tools.element.find(".show-compressed").removeAttr("checked");
			tools.element.find(".show-comparison").removeAttr("checked");

			if (bmp != null) {
				this.saveDisplayState("ViewMode", Uncompressed);
				this.viewMode = Uncompressed;

				var identifiers = element.find(".identifiers");
				identifiers.css(this.viewMode.match(ViewMode.Comparison) ? {"visibility":"inherit"} : {"visibility":"hidden"});

				applyShaderConfiguration();
			}

		}, this.viewMode.match(Uncompressed), null, false);
		tgUncompressed.element.addClass("show-uncompressed");

		var tgComparison = tools.addToggle("show-comparison","arrows-h", "Show comparison between compressed and uncompressed texture", "", function (e) {
			tools.element.find(".show-uncompressed").removeAttr("checked");
			tools.element.find(".show-compressed").removeAttr("checked");

			if (bmp != null) {
				this.saveDisplayState("ViewMode", Comparison);
				this.viewMode = Comparison;

				var identifiers = element.find(".identifiers");
				identifiers.css(this.viewMode.match(ViewMode.Comparison) ? {"visibility":"inherit"} : {"visibility":"hidden"});

				applyShaderConfiguration();
			}

		}, this.viewMode.match(Comparison), null, false);
		tgComparison.element.addClass("show-comparison");

		tools.addSeparator();

		// We don't want to load old texture from cache because convert rule might
		// have been changed
		@:privateAccess fs.fileCache.remove(state.path);

		scene.onReady = function() {
			scene.loadTexture(state.path, state.path, function(compressedTexture) {
				scene.loadTexture(state.path, state.path, function(uncompressedTexture) {
					onTexturesLoaded(compressedTexture, uncompressedTexture);
				}, onError, false, true);
			}, onError, false);
		};
	}

	override function onActivate() {
		if (tools != null)
			tools.refreshToggles();
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

		var cam2d = Std.downcast(cam, hide.view.l3d.CameraController2D);
		if (cam2d != null) {
			@:privateAccess cam2d.curPos.set(bmp.tile.width / 2, bmp.tile.width / 2, (1 / bmp.tile.width) * 500);
		}
		else {
			bmp.setScale(scale * js.Browser.window.devicePixelRatio);
			bmp.x = -Std.int(bmp.tile.width * bmp.scaleX) >> 1;
			bmp.y = -Std.int(bmp.tile.height * bmp.scaleY) >> 1;
		}

		updateSliderVisual();
	}

	public function onTexturesLoaded(compressedTexture: Null<h3d.mat.Texture>, uncompressedTexture: Null<h3d.mat.Texture>) {
		uncompressedTexture.filter = Nearest;

		scene.element.on("wheel", function(_) {
			updateSliderVisual();
		});

		for( i in 0...4 ) {
			var name = "RGBA".charAt(i);
			tools.addToggle("Channel"+name, "", "Channel "+name, name, function(b) {
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
			this.cam = new hide.view.l3d.CameraController2D(scene.s2d);
		} else {
			var r = new h3d.scene.fwd.Renderer();
			var ls = new h3d.scene.fwd.LightSystem();
			ls.ambientLight.set(1,1,1);
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
			this.cam = new h3d.scene.CameraController(5,scene.s3d);
		}

		if( compressedTexture.flags.has(MipMapped) ) {
			compressedTexture.mipMap = Linear;
			tools.addRange("MipMap", function(f) shader.mipLod = f, 0, 0, compressedTexture.mipLevels - 1, "mipmap");
		}

		if( hxd.Pixels.isFloatFormat(compressedTexture.format) ) {
			tools.addRange("Exposure", function(f) shader.exposure = f, 0, -10, 10);
		}

		var compTexMemSize = element.find(".comp-tex-weight");
		compTexMemSize.text('Compressed texture weight : ${@:privateAccess floatToStringPrecision(compressedTexture.mem.memSize(compressedTexture) / (1024 * 1024)) } mb');

		updateImageCompressionInfos();
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
						drawSlider();
					else
						sliderBmp.alpha = 1;

					bmp.addChild(sliderBmp);

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
						sliderBmp.x = e.relX - (bounds.width * sliderBmp.scaleX) / 2.0;
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

		if (bmp != null && !bmp.tile.isDisposed())
			bmp.tile.dispose();

		bmp = null;
		interactive = null;
		shader = null;
	}

	public function updateImageCompressionInfos() {
		var compressionInfo = element.find(".compression-infos");

		// Compression infos fields
		var format = compressionInfo.find(".select-format");
		var mips = compressionInfo.find(".mips-checkbox");
		var size = compressionInfo.find(".size");
		var useAlpha = compressionInfo.find(".use-alpha");
		var alpha = compressionInfo.find(".alpha-threshold");
		var maxSize = compressionInfo.find(".max-size");
		var nativeFormat = compressionInfo.find(".native-format");

		var dirPos = state.path.lastIndexOf("/");
		var name = dirPos < 0 ? state.path : state.path.substr(dirPos + 1);

		// We want to clear file system because we don't want to load texture from older texture's convert rules
		var fs:hxd.fs.LocalFileSystem = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		@:privateAccess fs.convert.configs.clear();
		@:privateAccess fs.convert.loadConfig(state.path);

		var localEntry = @:privateAccess new hxd.fs.LocalFileSystem.LocalEntry(fs, name, state.path, Ide.inst.getPath(state.path));

		try {
			fs.convert.run(localEntry);
		}
		catch (e) onError();

		@:privateAccess var texConvRule = fs.convert.getConvertRule(state.path);
		var convertRuleEmpty = texConvRule == null || texConvRule.cmd == null || texConvRule.cmd.params == null;

		format.val(convertRuleEmpty ? "none" : texConvRule.cmd.params.format);

		if (!convertRuleEmpty) {
			if (Reflect.field(texConvRule.cmd.params, "alpha") != null) {
				useAlpha.prop("checked", true);
				alpha.removeAttr("disabled");
				alpha.val(128);
			}
			else {
				useAlpha.removeProp("checked");
				alpha.prop("disabled", true);
				alpha.val(null);
			}
		}

		alpha.val(convertRuleEmpty || Reflect.field(texConvRule.cmd.params, "alpha") == null ? null : texConvRule.cmd.params.alpha);

		// Alpha treshold make sense for BC1 format
		if (format.val() != "BC1")
			alpha.parent().css({"display":"none"});
		else
			alpha.parent().css({"display":"flex"});

		var strMaxSize = getTextureMaxSize();
		size.val(convertRuleEmpty || Reflect.field(texConvRule.cmd.params, "size") == null ? strMaxSize : texConvRule.cmd.params.size);

		if (!convertRuleEmpty && texConvRule.cmd.params.mips)
			mips.prop("checked", true);
		else
			mips.removeProp("checked");

		var texMaxSize = getTextureMaxSize();

		maxSize.text('/${texMaxSize} px');
		if(size.val() == null || size.val() == "")
			size.val(texMaxSize);

		var uncompTWeight = element.find(".uncomp-tex-weight");
		uncompTWeight.text('Uncompressed texture weight : ${getTextureMemSize(state.path)} mb');

		nativeFormat.text(getTextureNativeFormat(state.path).getName());
	}

	public function replaceImage(path : String) {
		var bytes = sys.io.File.getBytes(path);
		var res = hxd.res.Any.fromBytes(path, bytes);
		var t = res.toTexture();

		if (bmp != null) {
			if (!bmp.tile.isDisposed())
				bmp.tile.dispose();

			bmp.remove();
			bmp = null;
		}

		if( !t.flags.has(Cube) ) {
			bmp = new h2d.Bitmap(h2d.Tile.fromTexture(t), scene.s2d);
			drawSlider();
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
			ls.ambientLight.set(1,1,1);
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
		}

		tools.element.find(".hide-range").remove();

		if( t.flags.has(MipMapped) ) {
			t.mipMap = Linear;
			tools.addRange("MipMap", function(f) shader.mipLod = f, 0, 0, t.mipLevels - 1, "mipmap");
		}

		if( hxd.Pixels.isFloatFormat(t.format) ) {
			tools.addRange("Exposure", function(f) shader.exposure = f, 0, -10, 10);
		}

		var compTexMemSize = element.find(".comp-tex-weight");
		compTexMemSize.text('Compressed texture weight : ${@:privateAccess floatToStringPrecision(t.mem.memSize(t) / (1024 * 1024)) } mb');

		applyShaderConfiguration();
		onResize();
	}

	public function createPreviewTexture(format: Element, useAlpha: Element, alpha: Element, mips: Element, size: Element) {
		var dirPos = state.path.lastIndexOf("/");
		var name = dirPos < 0 ? state.path : state.path.substr(dirPos + 1);
		var tmpPath = StringTools.replace(Sys.getEnv("TEMP"), "\\","/") + "/tempTexture.dds";

		if (format.val().toString() != "none") {
			var comp = new hxd.fs.Convert.CompressIMG("png,tga,jpg,jpeg,dds,envd,envs","dds");
			comp.srcPath = Ide.inst.getPath(state.path);
			comp.dstPath = Ide.inst.getPath(tmpPath);
			comp.originalFilename = name;

			if (useAlpha.is(':checked'))
				comp.params = { format:format.val().toString(), mips:mips.is(':checked'), size:Std.parseInt(size.val()) };
			else
				comp.params = { alpha:Std.parseInt(alpha.val()), format:format.val().toString(), mips:mips.is(':checked'), size:Std.parseInt(size.val()) };

			try {
				comp.convert();
			}
			catch(e) onError();
		}
		else {
			tmpPath = state.path;
		}

		replaceImage(Ide.inst.getPath(tmpPath));
	}

	public function getTextureMaxSize(): Int {
		var path = ide.getPath(state.path);
		var bytes = sys.io.File.getBytes(path);
		var res = hxd.res.Any.fromBytes(path, bytes);
		var t = res.toTexture();

		return t.width;
	}

	public function getTextureMemSize(path: String) {
		// Return texture mem size in MB
		var p = ide.getPath(path);
		var bytes = sys.io.File.getBytes(p);
		var res = hxd.res.Any.fromBytes(p, bytes);
		var t = res.toTexture();

		return @:privateAccess floatToStringPrecision(t.mem.memSize(t) / (1024 * 1024));
	}

	public function getTextureNativeFormat(path: String) {
		var p = ide.getPath(path);
		var bytes = sys.io.File.getBytes(p);
		var res = hxd.res.Any.fromBytes(p, bytes);
		var t = res.toTexture();

		return t.format;
	}

	public function floatToStringPrecision(number:Float, ?precision=2) {
		number *= Math.pow(10, precision);
		return Math.round(number) / Math.pow(10, precision);
	}

	public function updateSliderVisual() {
		var cam2d = Std.downcast(cam, hide.view.l3d.CameraController2D);
		if (cam2d != null && sliderBmp != null) {
			var oldWidth = sliderBmp.getSize().width;
			@:privateAccess sliderBmp.scaleX = (1 / (cam2d.curPos.z)) * 2;
			var offset = sliderBmp.getSize().width - oldWidth;
			sliderBmp.x -= offset / 4;
		}

		// todo : handle slider zoom for cam 3d
	}

	public function drawSlider() {
		if (sliderBmp == null)
			sliderBmp = new h2d.Graphics(scene.s2d);

		sliderBmp.clear();
		sliderBmp.beginFill(0xFFFFFF, 1);
		sliderBmp.drawRect(0,0,2, shader.compressedTex.height);
		sliderBmp.endFill();

		updateSliderVisual();
	}

	public function onError() {
		Ide.inst.quickError('Can\'t load texture with this compression parameters, original texture is loaded instead!');
	}

	static var _ = FileTree.registerExtension(Image,hide.Ide.IMG_EXTS.concat(["envd","envs"]),{ icon : "picture-o" });

}
package hide.view;

private class MSDFViewerShader extends h3d.shader.AlphaMSDF {
	static var SRC = {

		@param var comparisonFactor : Float;

		function fragment() {
			if (calculatedUV.x > comparisonFactor)
				pixelColor = texture.get(calculatedUV);
			else {
				pixelColor.rgb = vec3(1.0);					
				var sample = texture.get(calculatedUV);
				var sd = median(sample.r, sample.g, sample.b);
				var screenPxDistance = screenPxRange(calculatedUV)*(sd - 0.5);
				pixelColor.a = clamp(screenPxDistance + 0.5, 0.0, 1.0);
			}
		}
	}
}

enum MSDFViewMode {
	MSDF;
	Raw;
	Comparison;
}

class MSDFView extends FileView {

	var bmp : h2d.Bitmap;
	var sliderBmp : h2d.Graphics;
	var shader : MSDFViewerShader;
	var scene : hide.comp.Scene;
	var viewMode : MSDFViewMode = MSDF;
	var interactive : h2d.Interactive;
	var tools : hide.comp.Toolbar;
	var cam : Dynamic;
	var currentSize : Float = 0;

	override function onDisplay() {
		cleanUp();

		element.html('
			<div class="flex vertical">
				<div class="toolbar"></div>
				<div class="scene-partition" style="display: flex; flex-direction: row; flex: 1; overflow: hidden;">
					<div class="heaps-scene"></div>
					<div class="image-properties">
						<div class="title">MSDF infos</div>
						<div class="msdf-infos">
							<p class="tex-weight">Texture weight : missing info </p>
							<p class="current-size">Current size : 0 px </p>
							<p>Resize : 
								<input type="number" class="size" value=0 style="width:7ch;"></input>
								<input type="button" class="save-size" value="Save" title="Save current size options into a props.json file."/>
							</p>
						</div>
					</div>
				</div>
				<div class="identifiers">
					<label>MSDF</label>
					<label>Raw</label>
				</div>
			</div>
		');

		scene = new hide.comp.Scene(config, null, element.find(".heaps-scene"));
		var msdfInfos = element.find(".msdf-infos");
		var resize = msdfInfos.find(".size");
		var currentSizeField = msdfInfos.find(".current-size");

		var fs:hxd.fs.LocalFileSystem = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);

		var dirPos = state.path.lastIndexOf("/");
		var dirPath = dirPos < 0 ? state.path : state.path.substr(0, dirPos + 1);
		var name = dirPos < 0 ? state.path : state.path.substr(dirPos + 1);
		var propsFilePath = ide.getPath(dirPath + "props.json");

		var saveSize = element.find(".save-size");
		saveSize.on("click", function(_) {
			if (resize.val() == currentSize)
				return;

			var bytes = new haxe.io.BytesOutput();
			var convertRule = { convert : "png", priority: 10000000 };

				Reflect.setField(convertRule, "size", resize.val());

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
			currentSize = resize.val();
			currentSizeField.text('Current size : ${currentSize} px');

			replaceTexture(@:privateAccess localEntry.file);
		});

		this.saveDisplayKey = state.path;
		this.viewMode = getDisplayState("ViewMode");
		if (this.viewMode == null)
			this.viewMode = MSDF;

		var identifiers = element.find(".identifiers");
		identifiers.css(this.viewMode.match(MSDFViewMode.Comparison) ? {"visibility":"inherit"} : {"visibility":"hidden"});

		shader = new MSDFViewerShader();
		tools = new hide.comp.Toolbar(null,element.find(".toolbar"));

		tools.addSeparator();

		var tgMSDF = tools.addToggle("show-msdf", "file-zip-o", "Show MSDF", "", function (e) {
			tools.element.find(".show-raw").removeAttr("checked");
			tools.element.find(".show-comparison").removeAttr("checked");

			if (bmp != null) {
				this.saveDisplayState("ViewMode", MSDF);
				this.viewMode = MSDF;

				var identifiers = element.find(".identifiers");
				identifiers.css(this.viewMode.match(MSDFViewMode.Comparison) ? {"visibility":"inherit"} : {"visibility":"hidden"});

				applyShaderConfiguration();
			}
		}, this.viewMode.match(MSDF), null, false);
		tgMSDF.element.addClass("show-msdf");

		var tgRaw = tools.addToggle("show-raw","file-image-o", "Show Raw", "", function (e) {
			tools.element.find(".show-msdf").removeAttr("checked");
			tools.element.find(".show-comparison").removeAttr("checked");

			if (bmp != null) {
				this.saveDisplayState("ViewMode", Raw);
				this.viewMode = Raw;

				var identifiers = element.find(".identifiers");
				identifiers.css(this.viewMode.match(MSDFViewMode.Comparison) ? {"visibility":"inherit"} : {"visibility":"hidden"});

				applyShaderConfiguration();
			}

		}, this.viewMode.match(Raw), null, false);
		tgRaw.element.addClass("show-raw");

		var tgComparison = tools.addToggle("show-comparison","arrows-h", "Show comparison between MSDF and Raw", "", function (e) {
			tools.element.find(".show-raw").removeAttr("checked");
			tools.element.find(".show-msdf").removeAttr("checked");

			if (bmp != null) {
				this.saveDisplayState("ViewMode", Comparison);
				this.viewMode = Comparison;

				var identifiers = element.find(".identifiers");
				identifiers.css(this.viewMode.match(MSDFViewMode.Comparison) ? {"visibility":"inherit"} : {"visibility":"hidden"});

				applyShaderConfiguration();
			}

		}, this.viewMode.match(Comparison), null, false);
		tgComparison.element.addClass("show-comparison");

		tools.addSeparator();

		// We don't want to load old texture from cache because convert rule might
		// have been changed
		@:privateAccess fs.fileCache.remove(state.path);

		scene.onReady = function() {
			scene.loadTexture(state.path, state.path, function(texture) {
				onTextureLoaded(texture);
			}, false);
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

	public function onTextureLoaded(texture: Null<h3d.mat.Texture>) {
		scene.element.on("wheel", function(_) {
			updateSliderVisual();
		});

		bmp = new h2d.Bitmap(h2d.Tile.fromTexture(texture), scene.s2d);
		bmp.smooth = true;
		bmp.addShader(shader);
		shader.texture = texture;
		shader.blur = 1.0;
		shader.comparisonFactor = 0.5;
		this.cam = new hide.view.l3d.CameraController2D(scene.s2d);

		var texMemSize = element.find(".tex-weight");
		texMemSize.text('Texture weight : ${@:privateAccess floatToStringPrecision(texture.mem.memSize(texture) / (1024 * 1024)) } mb');

		currentSize = texture.width;
		
		var resize = element.find(".resize");
		resize.val(currentSize);
		var currentSizeField = element.find(".current-size");
		currentSizeField.text('Current size : ${currentSize} px');

		applyShaderConfiguration();
		onResize();
	}

	public function applyShaderConfiguration() {
		switch (this.viewMode) {
			case  MSDF:
				{
					shader.comparisonFactor = 1;

					if (interactive != null)
						interactive.remove();

					if (sliderBmp != null)
						sliderBmp.alpha = 0;
				}

			case Raw:
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
		sliderBmp.drawRect(0,0,2, shader.texture.height);
		sliderBmp.endFill();

		updateSliderVisual();
	}

	public function replaceTexture(path : String) {
		var bytes = sys.io.File.getBytes(path);
		var res = hxd.res.Any.fromBytes(path, bytes);
		var texture = res.toTexture();

		if (bmp != null) {
			if (!bmp.tile.isDisposed())
				bmp.tile.dispose();
			bmp.remove();
			bmp = null;
		}

		tools.element.find(".hide-range").remove();

		bmp = new h2d.Bitmap(h2d.Tile.fromTexture(texture), scene.s2d);
		bmp.smooth = true;
		bmp.addShader(shader);
		shader.texture = texture;
		shader.blur = 1.0;
		shader.comparisonFactor = 0.5;
		this.cam = new hide.view.l3d.CameraController2D(scene.s2d);

		var texMemSize = element.find(".tex-weight");
		texMemSize.text('Texture weight : ${@:privateAccess floatToStringPrecision(texture.mem.memSize(texture) / (1024 * 1024)) } mb');
		currentSize = texture.width;
		var resize = element.find(".resize");
		resize.val(currentSize);
		var currentSizeField = element.find(".current-size");
		currentSizeField.text('Current size : ${currentSize} px');

		applyShaderConfiguration();
		onResize();
	}

	static var _ = FileTree.registerExtension(MSDFView,["svg"],{ icon : "picture-o" });

}
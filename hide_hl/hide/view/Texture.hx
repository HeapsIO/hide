package hide.view;
import hrt.ui.*;

#if hui
private class TextureViewerShader extends hxsl.Shader {

	static var SRC = {

		@param var compressedTex : Sampler2D;
		@param var uncompressedTex : Sampler2D;
		@param var textureCube : SamplerCube;
		@param var textureArray : Sampler2DArray;
		@param var layer : Float;
		@param var mipLod : Float;
		@param var exposure : Float;
		@param var comparisonFactor : Float;
		@param var useGammaCorrection = false;
		@param var rangeMin = 0.;
		@param var rangeMax = 1.;

		@const var channels : Int;
		@const var isCube : Bool;
		@const var isArray : Bool;

		@:import h3d.shader.ColorSpaces;

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

			pixelColor.rgb = srgb2linear(pixelColor.rgb);
			pixelColor.rgb = vec3(invLerp(pixelColor.r, rangeMin, rangeMax),
				invLerp(pixelColor.g, rangeMin, rangeMax),
				invLerp(pixelColor.b, rangeMin, rangeMax));
			if (useGammaCorrection)
				pixelColor.rgb = linear2srgb(pixelColor.rgb);
		}

	}
}

class HuiHistogramRange extends HuiElement {
	static var SRC = <hui-histogram-range>
		<hui-input-box id="input-range-start" class="group-start"/>
		<hui-element id="range" class="group">
			<hui-element id="gauge"></hui-element>
			<hui-icon("diamond") class="handle" id="handle-range-start"/>
			<hui-icon("diamond") class="handle" id="handle-range-end"/>
		</hui-element>
		<hui-input-box id="input-range-end" class="group"/>
		<hui-button class="group"><hui-icon("back_arrow")/></hui-button>
		<hui-button class="group"><hui-icon("histogram")/></hui-button>
		<hui-toggle class="group-end" id="linear-tog"><hui-icon("gamma")/></hui-toggle>
	</hui-histogram-range>

	var curMin = 0.;
	var curMax = 1.;
	public function new(view: Texture, ?parent) {
		super(parent);
		initComponent();

		function refresh() {
			var min = @:privateAccess view.shader.rangeMin;
			var max = @:privateAccess view.shader.rangeMax;

			var remappedMin = (min - curMin) * 1 / (curMax - curMin);
			var remappedMax = (max - curMin) * 1 / (curMax - curMin);

			handleRangeStart.setPosition(-8 + (remappedMin * range.calculatedWidth), handleRangeStart.y);
			handleRangeEnd.setPosition(-8 + (remappedMax * range.calculatedWidth), handleRangeEnd.y);
			gauge.x = handleRangeStart.x + handleRangeStart.getSize().width / 2;
			gauge.setWidth(Std.int(handleRangeEnd.x - handleRangeStart.x));
			inputRangeStart.text = '${hxd.Math.round(min * 100) / 100}';
			inputRangeEnd.text = '${hxd.Math.round(max * 100) / 100}';
		}

		function onChange(isTempChange) {
			if (isTempChange)
				return;

			var newRangeMin = Std.parseFloat(inputRangeStart.text);
			var newRangeMax = Std.parseFloat(inputRangeEnd.text);

			@:privateAccess view.shader.rangeMin = newRangeMin;
			@:privateAccess view.shader.rangeMax = newRangeMax;

			curMin = newRangeMin;
			curMax = newRangeMax;
			refresh();
		}

		inputRangeStart.text = '${@:privateAccess view.shader.rangeMin}';
		inputRangeEnd.text = '${@:privateAccess view.shader.rangeMax}';
		inputRangeStart.onChange = inputRangeEnd.onChange = onChange;

		linearTog.toggled = true;
		linearTog.onClick = (_) -> {
			linearTog.toggled = !linearTog.toggled;
			@:privateAccess view.shader.useGammaCorrection = !linearTog.toggled;
		}

		handleRangeStart.onPush = (e) -> {
			if (e.button != 0)
				return;

			handleRangeStart.interactive.startCapture((e) -> {
				if (e.kind == ERelease || e.kind == EReleaseOutside) {
					handleRangeStart.interactive.stopCapture();
					return;
				}

				@:privateAccess view.shader.rangeMin = hxd.Math.clamp(((getScene().mouseX - range.absX) / range.calculatedWidth) * (curMax - curMin), curMin, @:privateAccess view.shader.rangeMax);
				refresh();
			});

			e.propagate = false;
		}

		handleRangeEnd.onPush = (e) -> {
			if (e.button != 0)
				return;

			handleRangeEnd.interactive.startCapture((e) -> {
				if (e.kind == ERelease || e.kind == EReleaseOutside) {
					handleRangeEnd.interactive.stopCapture();
					return;
				}

				@:privateAccess view.shader.rangeMax = hxd.Math.clamp(((getScene().mouseX - range.absX) / range.calculatedWidth) * (curMax - curMin), @:privateAccess view.shader.rangeMin, curMax);
				refresh();
			});

			e.propagate = false;
		}

		range.onAfterReflow = refresh;
	}
}

class Texture extends HuiView<{path: String}> {
	static var SRC = <texture>
		<hui-split-container id="container" direction={hrt.ui.HuiSplitContainer.Direction.Horizontal} anchor-to={hrt.ui.HuiSplitContainer.AnchorTo.End} save-display-key="texutre-panel-split">
			<hui-element id="viewer">
				<hui-text("Compressed") id="compressed-label"/>
				<hui-text("Uncompressed") id="uncompressed-label"/>
			</hui-element>
			<hui-element id="details">
				<hui-category("Compression")>
					<hui-element class="horizontal"><hui-text("Compressed texture weight") class="label"/><hui-text("1 MB") class="value" id="weight-compressed-el"/></hui-element>
					<hui-element class="horizontal"><hui-text("Uncompressed texture weight") class="label"/><hui-text("10 MB") class="value" id="weight-uncompressed-el"/></hui-element>
					<hui-element class="horizontal"><hui-text("Format") class="label"/><hui-select class="value" id="format-sel"/></hui-element>
					<hui-element class="horizontal" id="alpha-line"><hui-text("Alpha") class="label"/><hui-checkbox id="use-alpha"/><hui-input-box class="value" id="alpha-input"/></hui-element>
					<hui-element class="horizontal" id="mips-line"><hui-text("Mip Maps") class="label"/><hui-checkbox id="mips"/></hui-element>
					<hui-element class="horizontal"><hui-text("Size") class="label"/><hui-input-box id="size" class="value"/><hui-text("/ 512 px") id="max-size-el"/></hui-element>
					<hui-element class="horizontal"><hui-text("Filter") class="label"/><hui-select id="filter-sel" class="value"/></hui-element>
					<hui-button class="full" id="reset-soft-btn"><hui-text("Reset Preview")/></hui-button>
					<hui-button class="full" id="reset-full-btn"><hui-text("Reset Compression")/></hui-button>
				</hui-category>
			</hui-element>
		</hui-split-container>
	</texture>

	static var _ = HuiView.register("texture", Texture);

	static public var fitCmd = new hrt.ui.HuiCommands.HuiCommand("Fit", {key: hxd.Key.F});

	static var COMPARE_SLIDER_COLOR = 0xFFFFFFFF;
	static var COMPARE_SLIDER_WIDTH = 2;

	static var TRANSPARENT_TEX_PATH = 'ui/transparent_tiles_dark.png';
	static var MIN_ZOOM = 0.01;
	static var DEFAULT_FILTER = "POINT";
	static var FILTERS = ["Point", "Box"];
	static var FITLER_PARAMS = ["POINT", "FANT"];

	public var bmp : h2d.Bitmap;
	var params : Dynamic = null;
	var sliderBmp : h2d.Graphics;
	var shader : TextureViewerShader;
	var propsFilePath : String = "";
	var zoom : Float = 1;
	var flipped : Bool = false;
	var pan : h2d.col.Point = new h2d.col.Point(0, 0);
	var onDrag : (e : hxd.Event) -> Void;

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		registerCommand(HuiCommands.save, View, () -> { save();});
		registerCommand(fitCmd, View, () -> { fit();});

		var dirPos = state.path.lastIndexOf("/");
		var dirPath = dirPos < 0 ? state.path : state.path.substr(0, dirPos + 1);
		propsFilePath = dirPath + "props.json";

		// Create params from current texture conversion rule
		var texConvRule = getConvertRule();
		params = convertRuleToParams(texConvRule);

		viewer.backgroundType = "hui";
		var tex = HuiRes.loader.load(TRANSPARENT_TEX_PATH).toImage().toTexture();
		tex.wrap = Repeat;
		viewer.huiBg.setTexture(tex);
		viewer.huiBg.imageMode = CssParser.BackgroundImageMode.Repeat;

		compressedLabel.visible = uncompressedLabel.visible = false;


		viewer.onAfterReflow = () -> {
			refresh();
		}

		viewer.onWheel = (e : hxd.Event) -> {
			var amount = e.wheelDelta * -0.1;
			var newZoom = hxd.Math.max(zoom + amount, MIN_ZOOM);

			var absX = (e.relX - pan.x) / zoom;
			var absY = (e.relY - pan.y) / zoom;

			pan.x = e.relX - absX * newZoom;
			pan.y = e.relY - absY * newZoom;
			zoom = newZoom;

			refresh();
		}

		viewer.onPush = (e : hxd.Event) -> {
			if (e.button == 2 || onDrag != null)
				return;

			if (e.button == 1 && sliderBmp.visible) {
				onDrag = (e) -> {
					var newFactor = ((e.relX - pan.x) / zoom) / bmp.tile.width;
					shader.comparisonFactor = hxd.Math.clamp(newFactor);
					refresh();
				}
			}
			else if (e.button == 0) {
				var originDrag = new h2d.col.Point(e.relX, e.relY);
				var originPan = pan.clone();
				onDrag = (e) -> {
					var dx = e.relX - originDrag.x;
					pan.x = originPan.x + dx;
					var dy = e.relY - originDrag.y;
					pan.y = originPan.y + dy;
					refresh();
				}
			}
		}

		viewer.onMove = (e : hxd.Event) -> {
			if (onDrag != null)
				onDrag(e);
		}

		viewer.onRelease = (e : hxd.Event) -> {
			onDrag = null;
		}

		load(state.path);

		buildToolbar();

		var items = [ for (k in @:privateAccess hxd.fs.Convert.CompressIMG.TEXCONV_FMT.keys()) { label: k, value: k } ];
		items.sort((a, b) -> Reflect.compare(a.label, b.label));
		items.insert(0, { label: "None", value : null });
		formatSel.items = items;

		filterSel.items = [for (idx in 0...FILTERS.length) {  label: FILTERS[idx], value: FITLER_PARAMS[idx] }];

		resetSoftBtn.onClick = (_) -> {
			var oldParams = params;
			var newParams = convertRuleToParams(texConvRule);
			undo.record((undo) -> {
				params = undo ? oldParams : newParams;
			}, true);
			params = newParams;
			refreshTexture();
			refreshInspector();
		}

		resetFullBtn.onClick = (_) -> {
			if (sys.FileSystem.exists(propsFilePath)) {
				var rulesObj = haxe.Json.parse(sys.io.File.getContent(propsFilePath));

				var fsConvertObj = Reflect.getProperty(rulesObj, "fs.convert");
				var path = Ide.inst.getRelPath(state.path);
				if (fsConvertObj != null && Reflect.getProperty(fsConvertObj, path) != null) {
					// if(!Ide..confirm('Do you really want to remove ${state.path} from ${propsFilePath} ?'))
					// 	return;

					Reflect.deleteField(fsConvertObj, path);

					if (Reflect.fields(fsConvertObj).length == 0)
						Reflect.deleteField(rulesObj, "fs.convert");

					if (Reflect.fields(rulesObj).length == 0) {
						sys.FileSystem.deleteFile(propsFilePath);
						params = convertRuleToParams(getConvertRule());
						refreshInspector();
						refreshTexture();
						return;
					}
				}

				var bytes = new haxe.io.BytesOutput();
				var data = hide.Ide.inst.toJSON(rulesObj);
				bytes.writeString(data);
				hxd.File.saveBytes(propsFilePath, bytes.getBytes());
			}
		}

		formatSel.onValueChanged = filterSel.onValueChanged = mips.onValueChanged = useAlpha.onValueChanged = onValueChanged;
		alphaInput.onChange = size.onChange = (isTempChange) -> {
			if (isTempChange)
				return;
			onValueChanged();
		}

		refreshInspector();

		// Center the texture after the first flow refresh
		haxe.Timer.delay(fit, 0);
	}

	override function getViewName():String {
		return state.path.split("/").splice(-1, 2).join("/");
	}

	override function requestClose(cb: (canClose:Bool) -> Void) {
		if (hasUnsavedChanges) {
			uiBase.confirm("Save change before closing ?", Save | DontSave | Cancel, (choice: hrt.ui.HuiConfirmPopup.ConfirmButton) -> {
				switch (choice) {
					case Save:
						execCommand(HuiCommands.save);
						cb(true);
					case DontSave:
						cb(true);
					case Cancel:
						cb(false);
					default:
						throw "???";
				}
			});
		} else {
			cb(true);
		}
	}

	override function getToolbarWidgets() : Array<HuiElement> {
		var widgets : Array<HuiElement> = [];

		var helpBtn = new HuiButton();
		helpBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiHelpPopup(this.registeredCommands), { object: Element(helpBtn), directionX: StartInside, directionY: EndOutside });
		};

		var compressedBtn = new HuiToggle();
		compressedBtn.dom.addClass("group-start");
		compressedBtn.toggled = true;
		new HuiIcon("raw_off", compressedBtn);
		widgets.push(compressedBtn);

		var uncompressedBtn = new HuiToggle();
		uncompressedBtn.dom.addClass("group");
		new HuiIcon("raw", uncompressedBtn);
		widgets.push(uncompressedBtn);

		var compareBtn = new HuiToggle();
		compareBtn.dom.addClass("group-end");
		new HuiIcon("compare", compareBtn);
		widgets.push(compareBtn);

		compressedBtn.onClick = (_) -> {
			if (compressedBtn.toggled) return;
			compressedBtn.toggled = !compressedBtn.toggled;
			uncompressedBtn.toggled = false;
			compareBtn.toggled = false;
			shader.comparisonFactor = 1;
			sliderBmp.visible = uncompressedLabel.visible = compressedLabel.visible = false;
		}

		uncompressedBtn.onClick = (_) -> {
			if (uncompressedBtn.toggled) return;
			uncompressedBtn.toggled = !uncompressedBtn.toggled;
			compressedBtn.toggled = false;
			compareBtn.toggled = false;
			shader.comparisonFactor = 0;
			sliderBmp.visible = uncompressedLabel.visible = compressedLabel.visible = false;
		}

		compareBtn.onClick = (_) -> {
			if (compareBtn.toggled) return;
			compareBtn.toggled = !compareBtn.toggled;
			uncompressedBtn.toggled = false;
			compressedBtn.toggled = false;
			sliderBmp.visible = uncompressedLabel.visible = compressedLabel.visible = true;
		}

		var rChannelBtn = new HuiToggle();
		rChannelBtn.toggled = true;
		rChannelBtn.dom.addClass("group-start");
		new HuiText("R", rChannelBtn);
		rChannelBtn.onClick = (_) -> {
			rChannelBtn.toggled = !rChannelBtn.toggled;
			setChannelVisible(0, rChannelBtn.toggled);
		}
		widgets.push(rChannelBtn);

		var gChannelBtn = new HuiToggle();
		gChannelBtn.toggled = true;
		gChannelBtn.dom.addClass("group");
		new HuiText("G", gChannelBtn);
		gChannelBtn.onClick = (_) -> {
			gChannelBtn.toggled = !gChannelBtn.toggled;
			setChannelVisible(1, gChannelBtn.toggled);
		}
		widgets.push(gChannelBtn);

		var bChannelBtn = new HuiToggle();
		bChannelBtn.toggled = true;
		bChannelBtn.dom.addClass("group");
		new HuiText("B", bChannelBtn);
		bChannelBtn.onClick = (_) -> {
			bChannelBtn.toggled = !bChannelBtn.toggled;
			setChannelVisible(2, bChannelBtn.toggled);
		}
		widgets.push(bChannelBtn);

		var aChannelBtn = new HuiToggle();
		aChannelBtn.toggled = true;
		aChannelBtn.dom.addClass("group-end");
		new HuiText("A", aChannelBtn);
		aChannelBtn.onClick = (_) -> {
			aChannelBtn.toggled = !aChannelBtn.toggled;
			setChannelVisible(3, aChannelBtn.toggled);
		}
		widgets.push(aChannelBtn);

		var flipBtn = new HuiToggle();
		flipBtn.toggled = false;
		new HuiIcon("vertical_arrows", flipBtn);
		flipBtn.onClick = (_) -> {
			flipBtn.toggled = !flipBtn.toggled;
			flipped = !flipped;
			refresh();
		}
		widgets.push(flipBtn);

		var resetZoomBtn = new HuiButton();
		resetZoomBtn.dom.addClass("group-start");
		new HuiIcon("scale1_1", resetZoomBtn);
		resetZoomBtn.onClick = (_) -> {
			zoom = 1;
			refresh();
		}
		widgets.push(resetZoomBtn);

		var fitBtn = new HuiButton();
		fitBtn.dom.addClass("group");
		new HuiIcon("fullscreen", fitBtn);
		fitBtn.onClick = (_) -> {
			fit();
		}
		widgets.push(fitBtn);

		var zoomInputBox = new HuiInputBox();
		zoomInputBox.dom.setId("zoom-input-box");
		zoomInputBox.dom.addClass("group-end");
		zoomInputBox.text = '${zoom * 100}%';
		zoomInputBox.onChange = (isTempChange) -> {
			if (isTempChange)
				return;
			zoom = Std.parseFloat(zoomInputBox.text) / 100;
			refresh();
		}
		zoomInputBox.dom.addClass("group");
		widgets.push(zoomInputBox);

		var mipSel = new HuiSelect();
		mipSel.dom.setId("mip-sel");
		if (shader.compressedTex.mipLevels > 0) {
			var h = shader.compressedTex.height;
			var w = shader.compressedTex.width;
			mipSel.items = [ for (idx in 0...shader.compressedTex.mipLevels) { label: 'Mip $idx - ${hxd.Math.imax(w >> idx, 1)}x${hxd.Math.imax(h >> idx, 1)}', value: idx}];
			mipSel.value = 0;
		}
		else {
			mipSel.visible = false;
		}
		mipSel.onValueChanged = () -> {
			shader.mipLod = mipSel.value;
		}
		widgets.push(mipSel);

		var histogram = new HuiHistogramRange(this);
		widgets.push(histogram);

		new HuiIcon("question_mark", helpBtn);
		widgets.push(helpBtn);

		return widgets;
	}

	function save() {
		if (!hasUnsavedChanges)
			return;

		undo.markClean();
		hasUnsavedChanges = false;

		var bytes = new haxe.io.BytesOutput();
		var convertRule = paramsToConvertRule(params);
		var path = Ide.inst.getRelPath(state.path);
		var dirPos = state.path.lastIndexOf("/");
		var dirPath = dirPos < 0 ? state.path : state.path.substr(0, dirPos + 1);
		var name = dirPos < 0 ? state.path : state.path.substr(dirPos + 1);
		if (sys.FileSystem.exists(propsFilePath)) {
			var propsJson = haxe.Json.parse(sys.io.File.getContent(propsFilePath));

			if (Reflect.hasField(propsJson, "fs.convert")) {
				var fsConvertObj = Reflect.getProperty(propsJson, "fs.convert");
				Reflect.setField(fsConvertObj, path, convertRule);
			}
			else {
				var fsConvertObj = {};
				Reflect.setField(fsConvertObj, path, convertRule);
				Reflect.setProperty(propsJson, "fs.convert", fsConvertObj);
			}

			var data = hide.Ide.inst.toJSON(propsJson);
			bytes.writeString(data);
			hxd.File.saveBytes(propsFilePath, bytes.getBytes());
		} else {
			var fsConvertObj = { };
			var pathObj = { };

			Reflect.setProperty(pathObj, path, convertRule);
			Reflect.setProperty(fsConvertObj, "fs.convert", pathObj);
			var data = hide.Ide.inst.toJSON(fsConvertObj);
			bytes.writeString(data);
			hxd.File.saveBytes(propsFilePath, bytes.getBytes());
		}

		var fs : hxd.fs.LocalFileSystem = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		@:privateAccess fs.convert.configs.clear();
		@:privateAccess fs.fileCache.remove(path);
		@:privateAccess fs.convert.loadConfig(path);
		var localEntry = @:privateAccess new hxd.fs.LocalFileSystem.LocalEntry(fs, name, path, state.path);
		fs.convert.run(localEntry);
		hxd.res.Loader.currentInstance.cleanCache();
	}

	function refresh() {
		this.bmp.scaleX = this.bmp.scaleY = zoom;
		this.bmp.x = pan.x;
		this.bmp.y = pan.y;
		if (flipped) {
			this.bmp.scaleY *= -1;
			this.bmp.y += this.bmp.getSize().height;
		}

		var zoomWidget = Std.downcast(toolbar.getWidget("zoom-input-box"), HuiInputBox);
		zoomWidget?.text = '${hxd.Math.round(zoom * 100)}%';

		sliderBmp.clear();
		sliderBmp.lineStyle(COMPARE_SLIDER_WIDTH, COMPARE_SLIDER_COLOR, 1);

		var x = shader.comparisonFactor * bmp.tile.width;
		sliderBmp.moveTo(x, 0);
		sliderBmp.lineTo(x, bmp.tile.height);
	}

	function refreshInspector() {
		weightUncompressedEl.text = '${@:privateAccess floatToStringPrecision(shader.uncompressedTex.mem.memSize(shader.uncompressedTex) / (1024 * 1024)) } MB';
		weightCompressedEl.text = '${getTextureMemSize(shader.compressedTex)} MB';

		formatSel.value = params.format;
		filterSel.value = params.filter;
		mips.value = params.mips;
		alphaLine.visible = formatSel.value == "BC1";
		mipsLine.visible = formatSel.value != null;
		useAlpha.value = params.alpha;
		alphaInput.disabled = !params.alpha;
		alphaInput.text = '${params.alphaThreshold}';

		var h = shader.compressedTex.height;
		var w = shader.compressedTex.width;
		var mipSel = Std.downcast(toolbar.getWidget("mip-sel"), HuiSelect);
		if (mipSel != null) {
			mipSel.items = [ for (idx in 0...shader.compressedTex.mipLevels) { label: 'Mip $idx - ${hxd.Math.imax(w >> idx, 1)}x${hxd.Math.imax(h >> idx, 1)}', value: idx}];
			mipSel.value = 0;
		}

		var texMaxSize = getTextureMaxSize();
		size.text = '${params.size}';
		maxSizeEl.text = '/ ${texMaxSize} px';
	}

	function refreshTexture() {
		var dirPos = state.path.lastIndexOf("/");
		var name = dirPos < 0 ? state.path : state.path.substr(dirPos + 1);
		var tmpPath = StringTools.replace(Sys.getEnv("TEMP"), "\\","/") + "/tempTexture.dds";

		if (formatSel.value != null) {
			var comp = new hxd.fs.Convert.CompressIMG("png,tga,jpg,jpeg,dds,envd,envs","dds");
			comp.srcPath = Ide.inst.getPath(state.path);
			comp.dstPath = Ide.inst.getPath(tmpPath);
			comp.originalFilename = name;
			comp.params = paramsToConvertRule(params);

			try {
				comp.convert();
			}
			catch(e) onError();
		}
		else {
			tmpPath = state.path;
		}

		var bytes = sys.io.File.getBytes(tmpPath);
		var res = hxd.res.Any.fromBytes(tmpPath, bytes);
		var t = res.toTexture();

		if (bmp != null) {
			if (!bmp.tile.isDisposed())
				bmp.tile.dispose();
		}

		bmp.tile = h2d.Tile.fromTexture(t);
		// drawSlider();
		// bmp.addShader(shader);
		// if (t.layerCount > 1) {
		// 	shader.isArray = true;
		// 	shader.textureArray = cast(t, h3d.mat.TextureArray);
		// 	tools.addRange("Layer", function(f) shader.layer = f, 0, 0, t.layerCount-1, 1);
		// }
		// else
			shader.compressedTex = t;

		// TODO: display cube texture

		// tools.element.find(".hide-range").remove();

		// if( t.flags.has(MipMapped) ) {
		// 	t.mipMap = Linear;
		// 	tools.addRange("MipMap", function(f) shader.mipLod = f, 0, 0, t.mipLevels - 1, "mipmap");
		// }

		// if( hxd.Pixels.isFloatFormat(t.format) ) {
		// 	tools.addRange("Exposure", function(f) shader.exposure = f, 0, -10, 10);
		// }

		// var compTexMemSize = element.find(".comp-tex-weight");
		// compTexMemSize.text('Compressed texture weight : ${@:privateAccess floatToStringPrecision(t.mem.memSize(t) / (1024 * 1024)) } MB');

		// applyShaderConfiguration();
		// onResize();
	}

	function onValueChanged() {
		var oldParams = params;
		var newParams = {
			format: formatSel.value,
			filter: filterSel.value,
			mips: mips.value,
			alpha: useAlpha.value,
			alphaThreshold: Std.parseInt(alphaInput.text),
			size: Std.parseInt(size.text)
		};

		undo.record((undo) -> {
			params = undo ? oldParams : newParams;
			refreshTexture();
			refreshInspector();
		}, true);

		params = newParams;

		refreshTexture();
		refreshInspector();
	}

	function load(path : String) {
		if (bmp == null) {
			bmp = new h2d.Bitmap(null, viewer);
			shader = new TextureViewerShader();
			bmp.addShader(shader);
			for (idx in 0...4)
				setChannelVisible(idx, true);
			shader.comparisonFactor = 1;
			sliderBmp = new h2d.Graphics(bmp);
			sliderBmp.visible = false;
		}

		var compressedTex = hxd.res.Loader.currentInstance.load(Ide.inst.getRelPath(path)).toImage().toTexture();
		bmp.tile = h2d.Tile.fromTexture(compressedTex);

		var bytes = sys.io.File.getBytes(path);
		var uncompressedTex = hxd.res.Any.fromBytes(path, bytes).toImage().toTexture();

		shader.compressedTex = compressedTex;
		shader.uncompressedTex = uncompressedTex;
	}

	function fit() {
		this.zoom = viewer.calculatedHeight / this.bmp.tile.height;
		refresh();
		this.pan.x = (viewer.calculatedWidth / 2) - (this.bmp.getSize().width / 2);
		this.pan.y = (viewer.calculatedHeight / 2) - (this.bmp.getSize().height / 2);
		refresh();
	}

	function setChannelVisible(channelIdx : Int, visible : Bool) {
		shader.channels &= ~(1 << channelIdx);
		if (visible) shader.channels |= 1 << channelIdx;
	}

	function getTextureMemSize(tex: h3d.mat.Texture) {
		return @:privateAccess floatToStringPrecision(tex.mem.memSize(tex) / (1024 * 1024));
	}

	function floatToStringPrecision(number:Float, ?precision=2) {
		number *= Math.pow(10, precision);
		return Math.round(number) / Math.pow(10, precision);
	}

	function filterToParam(f : String) {
		return FITLER_PARAMS[FILTERS.indexOf(f)];
	}

	function paramToFilter(p : String) {
		return FILTERS[FITLER_PARAMS.indexOf(p)];
	}

	function getConvertRule() {
		// Load current texture convert rule
		// (We want to clear file system because we don't want to load texture from older texture's convert rules)
		var relPath = Ide.inst.getRelPath(state.path);
		var fs : hxd.fs.LocalFileSystem = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		@:privateAccess fs.convert.configs.clear();
		@:privateAccess fs.convert.loadConfig(state.path);
		var localEntry = @:privateAccess new hxd.fs.LocalFileSystem.LocalEntry(fs, name, state.path, Ide.inst.getPath(state.path));
		try { fs.convert.run(localEntry); }
		catch (e) onError();
		return @:privateAccess fs.convert.getConvertRule(relPath);
	}

	function paramsToConvertRule(params: Dynamic) {
		if (params.format == null)
			return { convert : "none", priority: 10000000 };

		var	convertRule = { convert : "dds", format : params.format, mips : params.mips, priority: 10000000 };
		if (params.size != getTextureMaxSize()) {
			Reflect.setField(convertRule, "size", params.size);
			Reflect.setField(convertRule, "filter", params.filter);
		}
		if (params.alpha)
			Reflect.setField(convertRule, "alpha", params.alphaThreshold);
		return convertRule;
	}

	function convertRuleToParams(rule : hxd.fs.FileConverter.ConvertRule) {
		var convertRuleEmpty = rule == null || rule.cmd == null || rule.cmd.params == null;
		return params = {
			format: convertRuleEmpty ? null : rule.cmd.params.format,
			filter: (convertRuleEmpty || rule.cmd.params.filter == null) ? DEFAULT_FILTER : rule.cmd.params.filter,
			mips: (!convertRuleEmpty && rule.cmd.params?.mips),
			alpha: (!convertRuleEmpty && rule.cmd.params?.alpha),
			alphaThreshold: (!convertRuleEmpty && rule.cmd.params?.alpha != null) ? rule.cmd.params?.alpha : 128,
			size: (convertRuleEmpty || rule.cmd.params?.size == null) ? getTextureMaxSize() : rule.cmd.params.size
		}
	}

	function getTextureMaxSize(): Int {
		var path = Ide.inst.getPath(state.path);
		var bytes = sys.io.File.getBytes(path);
		var res = hxd.res.Any.fromBytes(path, bytes);
		var t = res.toTexture();

		return t.width;
	}

	function onError() {
		Ide.showError('Can\'t load texture with this compression parameters, original texture is loaded instead!');
	}
}
#end
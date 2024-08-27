package hrt.prefab.l2d;

class Text extends Object2D {

	// parameters
	@:s var color : Int = 0xFFFFFF;
	@:s var size : Int = 12;
	@:s var cutoff : Float = 0.5;
	@:s var smoothing : Float = 1 / 32;
	@:s var align : Int = 0;

	@:s var maxWidth : Float = 0;

	@:s var pathFont : String;

	// TextShadow
	@:s var enableTextShadow : Bool = false;
	@:s var tsDx: Float = 0;
	@:s var tsDy: Float = 0;
	@:s var tsColor: Int;
	@:s var tsAlpha: Float = 1;

	// DropShadow
	@:s var enableDropShadow : Bool = false;
	@:s var dsDistance: Float = 0;
	@:s var dsAngle: Float = 0;
	@:s var dsColor: Int;
	@:s var dsAlpha: Float = 1;
	@:s var dsRadius: Float = 0;
	@:s var dsGain: Float = 1;
	@:s var dsQuality: Float = 1;
	@:s var dsSmoothColor: Bool = true;

	#if editor
	@:s var text : String = "";
	#end

	override public function load(v:Dynamic) {
		super.load(v);
		if( v.blendMode == null )
			blendMode = Alpha;
	}

	override public function copy(other:Prefab) {
		super.copy(other);
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		var h2dText = (cast local2d : h2d.HtmlText);
		h2dText.visible = visible;
		h2dText.textColor = color;
		h2dText.maxWidth = maxWidth > 0 ? maxWidth : null;

		if (enableTextShadow) {
			h2dText.dropShadow = {
				dx: tsDx,
				dy: tsDy,
				color: tsColor,
				alpha: tsAlpha
			};
		} else {
			h2dText.dropShadow = null;
		}

		if (enableDropShadow) {
			h2dText.filter = new h2d.filter.DropShadow(
				dsDistance,
				dsAngle,
				dsColor,
				dsAlpha,
				dsRadius,
				dsGain,
				dsQuality,
				dsSmoothColor
			);
		} else
			h2dText.filter = null;

		h2dText.textAlign = switch (align) {
			case 1:
				Center;
			case 2:
				Right;
			default:
				Left;
		}
		var font = loadFont();
		if (font != null)
			h2dText.font = font;
		#if editor
			if (propName == null || propName == "text") {
				h2dText.text = text;
			}
			var int = Std.downcast(h2dText.getChildAt(0),h2d.Interactive);
			if( int != null ) {
				@:privateAccess {
					h2dText.rebuild();
					int.width = h2dText.calcWidth;
					int.height = h2dText.calcHeight;
					switch (h2dText.textAlign) {
						case Center:
							int.x = -int.width/2;
						case Right:
							int.x = -int.width;
						default:
							int.x = 0;
					}
				}
			}
		#end
	}

	override function makeObject(parent2d:h2d.Object):h2d.Object {
		var h2dText = new h2d.HtmlText(hxd.res.DefaultFont.get(), parent2d);
		h2dText.text = "";
		h2dText.smooth = true;
		return h2dText;
	}

	public dynamic function loadFont() : h2d.Font {
		var f = defaultLoadFont(pathFont, size, cutoff, smoothing);
		if (f == null) {
			if (pathFont != null && pathFont.length > 0) {
				var font = hxd.res.Loader.currentInstance.load(pathFont).to(hxd.res.BitmapFont);
				return font.toSdfFont(size, MultiChannel, cutoff, smoothing);
			} else {
				return null;
			}
		}
		else return f;
	}

	public static dynamic function defaultLoadFont( pathFont : String, size : Int, cutoff : Float, smoothing : Float ) : h2d.Font {
		return null;
	}

	#if editor

	override function makeInteractive():h2d.Interactive {
		if(local2d == null)
			return null;
		var text = cast(local2d, h2d.Text);
		@:privateAccess { text.rebuild(); text.updateSize(); }
		@:privateAccess var int = new h2d.Interactive(text.calcWidth, text.calcHeight);
		text.addChildAt(int, 0);
		int.propagateEvents = true;
		return int;
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		var parameters = new hide.Element('<div class="group" name="Parameters"></div>');

		var gr = new hide.Element('<dl></dl>').appendTo(parameters);

		new hide.Element('<dt>Align</dt>').appendTo(gr);
		var element = new hide.Element('<dd></dd>').appendTo(gr);
		var leftAlign = new hide.Element('<input type="button" style="width: 50px" value="Left" /> ').appendTo(element);
		var middleAlign = new hide.Element('<input type="button" style="width: 50px" value="Center" /> ').appendTo(element);
		var rightAlign = new hide.Element('<input type="button" style="width: 50px" value="Right" /> ').appendTo(element);
		inline function updateDisabled() {
			leftAlign.removeAttr("disabled");
			middleAlign.removeAttr("disabled");
			rightAlign.removeAttr("disabled");
			switch (align) {
				case 1:
					middleAlign.attr("disabled", "true");
				case 2:
					rightAlign.attr("disabled", "true");
				default:
					leftAlign.attr("disabled", "true");
			}
		}
		leftAlign.on("click", function(e) {
			align = 0;
			updateDisabled();
			ctx.onChange(this, "align");
		});
		middleAlign.on("click", function(e) {
			align = 1;
			updateDisabled();
			ctx.onChange(this, "align");
		});
		rightAlign.on("click", function(e) {
			align = 2;
			updateDisabled();
			ctx.onChange(this, "align");
		});
		updateDisabled();

		new hide.Element('<dt>Font</dt>').appendTo(gr);
		var element = new hide.Element('<dd></dd>').appendTo(gr);
		var fileInput = new hide.Element('<input type="text" field="pathFont" style="width:165px" />').appendTo(element);

		var tfile = new hide.comp.FileSelect(["fnt"], null, fileInput);
		if (this.pathFont != null && this.pathFont.length > 0) tfile.path = this.pathFont;
		tfile.onChange = function() {
			this.pathFont = tfile.path;
			updateInstance("src");
		}

		new hide.Element('<dt>Color</dt><dd><input type="color" field="color" /></dd>').appendTo(gr);
		new hide.Element('<dt>Size</dt><dd><input type="range" min="1" max="50" step="1" field="size" /></dd>').appendTo(gr);
		new hide.Element('<dt>Cutoff</dt><dd><input type="range" min="0" max="1" field="cutoff" /></dd>').appendTo(gr);
		new hide.Element('<dt>Smoothing</dt><dd><input type="range" min="0" max="1" field="smoothing" /></dd>').appendTo(gr);
		new hide.Element('<dt>Max Width</dt><dd><input type="range" min="0" max="500" field="maxWidth" /></dd>').appendTo(gr);

		ctx.properties.add(parameters, this, function(pname) {
			ctx.onChange(this, pname);
		});

		ctx.properties.add(new hide.Element('<div class="group" name="Text Shadow (double render)">
			<dl>
				<dt>Enable</dt><dd><input type="checkbox" field="enableTextShadow" /></dd><br />
				<dt>DX</dt><dd><input type="range" min="-50" max="50" step="1" field="tsDx" /></dd>
				<dt>DY</dt><dd><input type="range" min="-50" max="50" step="1" field="tsDy" /></dd>
				<dt>Color</dt><dd><input type="color" field="tsColor" /></dd>
				<dt>Alpha</dt><dd><input type="range" min="0" max="1" step="0.01" field="tsAlpha" /></dd>
			</dl></div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});

		ctx.properties.add(new hide.Element('<div class="group" name="Drop Shadow">
			<dl>
				<dt>Enable</dt><dd><input type="checkbox" field="enableDropShadow" /></dd><br />
				<dt>Distance</dt><dd><input type="range" min="-50" max="50" step="1" field="dsDistance" /></dd>
				<dt>Angle</dt><dd><input type="range" min="-1.571" max="1.571" step="0.0524" field="dsAngle" /></dd>
				<dt>Color</dt><dd><input type="color" field="dsColor" /></dd>
				<dt>Alpha</dt><dd><input type="range" min="0" max="1" step="0.01" field="dsAlpha" /></dd>
				<dt>Radius</dt><dd><input type="range" min="0" max="50" step="1" field="dsRadius" /></dd>
				<dt>Gain</dt><dd><input type="range" min="0.1" max="50" step="0.1" field="dsGain" /></dd>
				<dt>Quality</dt><dd><input type="range" min="0" max="1" step="0.01" field="dsQuality" /></dd>
				<dt>Smooth Color</dt><dd><input type="checkbox" field="dsSmoothColor" /></dd>
			</dl></div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});

		ctx.properties.add(new hide.Element('<div class="group" name="Responsive">
			<dl>
				<dt>Text</dt><dd><input type="text" field="text" /></dd>
			</dl></div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "square", name : "Text" };
	}

	#end

	static var _ = Prefab.register("text", Text);

}
package hrt.prefab.fx2d;

class Text extends Object2D {

	// parameters

	var color : Int = 16777215;
	var size : Int = 12;
	var cutoff : Float = 0.5;
	var smoothing : Float = 1 / 32;
	var align : Int = 0;

	var pathFont : String;

	#if editor
	var text : String = "";
	#end

	override public function load(v:Dynamic) {
		super.load(v);
		if (v.blendMode == null)
			blendMode = Alpha;
		this.color = v.color;
		this.size = v.size;
		this.cutoff = v.cutoff;
		this.smoothing = v.smoothing;
		this.pathFont = v.pathFont;
		this.align = v.align;
	}

	override function save() {
		var o : Dynamic = super.save();
		o.color = color;
		o.size = size;
		o.cutoff = cutoff;
		o.smoothing = smoothing;
		o.pathFont = pathFont;
		o.align = align;
		return o;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, propName);
		var h2dText = (cast ctx.local2d : h2d.Text);
		h2dText.visible = visible;
		h2dText.color = h3d.Vector.fromColor(color);
		h2dText.color.w = 1;
		
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

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var h2dText = new h2d.Text(hxd.res.DefaultFont.get(), ctx.local2d);
		h2dText.text = "";
		h2dText.smooth = true;
		ctx.local2d = h2dText;
		ctx.local2d.name = name;
		updateInstance(ctx);
		return ctx;
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

	override function makeInteractive(ctx:Context):h2d.Interactive {
		var local2d = ctx.local2d;
		if(local2d == null)
			return null;
		var text = cast(local2d, h2d.Text);
		@:privateAccess { text.rebuild(); text.updateSize(); }
		@:privateAccess var int = new h2d.Interactive(text.calcWidth, text.calcHeight);
		text.addChildAt(int, 0);
		int.propagateEvents = true;
		return int;
	}

	override function edit( ctx : EditContext ) {
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
			updateInstance(ctx.getContext(this), "align");
		});
		middleAlign.on("click", function(e) {
			align = 1;
			updateDisabled();
			updateInstance(ctx.getContext(this), "align");
		});
		rightAlign.on("click", function(e) {
			align = 2;
			updateDisabled();
			updateInstance(ctx.getContext(this), "align");
		});
		updateDisabled();

		new hide.Element('<dt>Font</dt>').appendTo(gr);
		var element = new hide.Element('<dd></dd>').appendTo(gr);
		var fileInput = new hide.Element('<input type="text" field="pathFont" style="width:165px" />').appendTo(element);

		var tfile = new hide.comp.FileSelect(["fnt"], null, fileInput);
		if (this.pathFont != null && this.pathFont.length > 0) tfile.path = this.pathFont;
		tfile.onChange = function() {
			this.pathFont = tfile.path;
			updateInstance(ctx.getContext(this), "src");
		}

		new hide.Element('<dt>Color</dt><dd><input type="color" field="color" /></dd>').appendTo(gr);
		new hide.Element('<dt>Size</dt><dd><input type="range" min="1" max="50" step="1" field="size" /></dd>').appendTo(gr);
		new hide.Element('<dt>Cutoff</dt><dd><input type="range" min="0" max="1" field="cutoff" /></dd>').appendTo(gr);
		new hide.Element('<dt>Smoothing</dt><dd><input type="range" min="0" max="1" field="smoothing" /></dd>').appendTo(gr);
		
		ctx.properties.add(parameters, this, function(pname) {
			ctx.onChange(this, pname);
		});

		ctx.properties.add(new hide.Element('<div class="group" name="Responsive">
			<dl>
				<dt>Text (not saved)</dt><dd><input type="text" field="text" /></dd>
			</dl></div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Text" };
	}

	#end

	static var _ = Library.register("text", Text);

}
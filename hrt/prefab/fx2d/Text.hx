package hrt.prefab.fx2d;

class Text extends Object2D {

	// parameters

	var h2dText : h2d.Text;
	var color : Int = 16777215;
	var size : Int = 12;
	var cutoff : Float = 0.5;
	var smoothing : Float = 1 / 32;

	var pathFont : String;

	override public function load(v:Dynamic) {
		super.load(v);
		if (v.blendMode == null)
			blendMode = Alpha;
		this.color = v.color;
		this.size = v.size;
		this.cutoff = v.cutoff;
		this.smoothing = v.smoothing;
		this.pathFont = v.pathFont;
	}

	override function save() {
		var o : Dynamic = super.save();
		o.color = color;
		o.size = size;
		o.cutoff = cutoff;
		o.smoothing = smoothing;
		o.pathFont = pathFont;
		return o;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, propName);
		h2dText.visible = visible;
		h2dText.color = h3d.Vector.fromColor(color);
		h2dText.color.w = 1;
		if (pathFont != null && pathFont.length > 0) {
			var font = hxd.res.Loader.currentInstance.load(pathFont).to(hxd.res.BitmapFont);
			h2dText.font = font.toSdfFont(size, Alpha, cutoff, smoothing);
		}
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		h2dText = new h2d.Text(hxd.res.DefaultFont.get(), ctx.local2d);
		h2dText.text = "Lorem ipsum dolor";
		h2dText.smooth = true;
		ctx.local2d = h2dText;
		ctx.local2d.name = name;
		ctx.cleanup = function() { h2dText = null; }
		updateInstance(ctx);
		return ctx;
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		
		var parameters = new hide.Element('<div class="group" name="Parameters"></div>');

		var gr = new hide.Element('<dl></dl>').appendTo(parameters);

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
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Text" };
	}

	#end

	static var _ = Library.register("text", Text);

}
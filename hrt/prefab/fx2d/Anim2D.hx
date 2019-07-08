package hrt.prefab.fx2d;

class Anim2D extends Object2D {

	// parameters
	var src : String;

	var widthFrame : Int = 10;
	var heightFrame : Int = 10;
	var fpsAnimation : Int = 30;
	var nbFrames : Int = 30;
	
	var loop : Bool = false;

	var h2dAnim : h2d.Anim;
	var tex : h3d.mat.Texture;

	override public function load(v:Dynamic) {
		super.load(v);
		this.src = v.src;
		this.widthFrame = v.widthFrame;
		this.heightFrame = v.heightFrame;
		this.fpsAnimation = v.fpsAnimation;
		this.nbFrames = v.nbFrames;
		this.loop = v.loop;
	}

	override function save() {
		var o : Dynamic = super.save();
		o.src = src;
		o.widthFrame = widthFrame;
		o.heightFrame = heightFrame;
		o.fpsAnimation = fpsAnimation;
		o.nbFrames = nbFrames;
		o.loop = loop;
		return o;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, propName);
		
		if (propName == null || (propName == "src" || propName == "widthFrame" || propName == "heightFrame" || propName == "nbFrames")) {
			if (tex != null) {
				tex = null;
			}
			if (src != null) {
				tex = ctx.loadTexture(src);
				var t = h2d.Tile.fromTexture(tex);
				var tiles = [];
				var nbFrameRow = Std.int(t.width / widthFrame);
				for( y in 0...Std.int(t.height / heightFrame) )
					for( x in 0...nbFrameRow)
						if (y * nbFrameRow + x <= nbFrames)
							tiles.push( t.sub(x * widthFrame, y * heightFrame, widthFrame, heightFrame, -(widthFrame / 2), -(heightFrame / 2)) );
				h2dAnim.play(tiles);
			} else {
				h2dAnim.play([]);
			}
		}
		if (propName == null || propName == "fpsAnimation") {
			h2dAnim.speed = fpsAnimation;
		}
		if (propName == null || propName == "loop") {
			h2dAnim.loop = loop;
		}
		h2dAnim.blendMode = blendMode;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		h2dAnim = new h2d.Anim([], fpsAnimation, ctx.local2d);
		ctx.local2d = h2dAnim;
		ctx.local2d.name = name;
		ctx.cleanup = function() { h2dAnim = null; }
		updateInstance(ctx);
		return ctx;
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		ctx.properties.add(new hide.Element('<div class="group" name="Frames">
			<dl>
				<dt>Background</dt><dd><input type="texturepath" field="src" style="width:165px"/></dd>
				<dt>Width Frame</dt><dd><input type="range" min="0" max="100" step="1" field="widthFrame"/></dd>
				<dt>Height Frame</dt><dd><input type="range" min="0" max="100" step="1" field="heightFrame"/></dd>
				<dt>FPS</dt><dd><input type="range" min="0" max="60" step="1" field="fpsAnimation"/></dd>
				<dt>nbFrames</dt><dd><input type="range" min="0" max="120" step="1" field="nbFrames"/></dd>
				<dt>Loop</dt><dd><input type="checkbox" field="loop"/></dd>
			</dl></div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Anim2D" };
	}

	#end

	static var _ = Library.register("anim2D", Anim2D);

}
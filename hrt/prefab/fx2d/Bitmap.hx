package hrt.prefab.fx2d;

class Bitmap extends Object2D {

	// parameters
	var color : Int = 16777215;

	var src : String;

	var dx : Float = 0;
	var dy : Float = 0;

	var tex : h3d.mat.Texture;

	override public function load(v:Dynamic) {
		super.load(v);
		this.color = v.color;
		this.src = v.src;
		this.dx = v.dx;
		this.dy = v.dy;
	}

	override function save() {
		var o : Dynamic = super.save();
		o.color = color;
		o.src = src;
		o.dx = dx;
		o.dy = dy;
		return o;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		super.updateInstance(ctx, propName);
		var bmp = (cast ctx.local2d : h2d.Bitmap);
		bmp.visible = visible;
		if (propName == null || propName == "src") {
			if (tex != null) {
				tex = null;
			}
			if (src != null) {
				tex = ctx.loadTexture(src);
				bmp.tile = h2d.Tile.fromTexture(this.tex);
			} else {
				bmp.tile = null;
			}
		}
		bmp.color = h3d.Vector.fromColor(color);
		bmp.color.w = 1;
		if (bmp.tile != null) {
			var cRatio = getCenterRatio(dx, dy);
			bmp.tile.setCenterRatio(cRatio[0], cRatio[1]);
		}
		bmp.blendMode = blendMode;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var bmp = new h2d.Bitmap(null, ctx.local2d);
		bmp.smooth = true;
		ctx.local2d = bmp;
		ctx.local2d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	static public function getCenterRatio(dx : Float, dy : Float) {
		return [0.5 + hxd.Math.clamp(dx, -0.5, 0.5), 0.5 + hxd.Math.clamp(dy, -0.5, 0.5)];
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		ctx.properties.add(new hide.Element('<div class="group" name="Parameters">
			<dl>
				<dt>Color</dt><dd><input type="color" field="color" /></dd>
				<dt>Background</dt><dd><input type="texturepath" field="src" style="width:165px"/></dd>
				<dt>Bg Pivot DX</dt><dd><input type="range" min="-0.5" max="0.5" field="dx"/></dd>
				<dt>Bg Pivot DY</dt><dd><input type="range" min="-0.5" max="0.5" field="dy"/></dd>
			</dl></div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "square", name : "Bitmap" };
	}

	#end

	static var _ = Library.register("bitmap", Bitmap);

}
package hrt.prefab2.l2d;

class Bitmap extends Object2D {

	// parameters
	@:s var color : Int = 0xFFFFFF;
	@:s var src : String;
	@:s var dx : Float = 0;
	@:s var dy : Float = 0;

	var tex : h3d.mat.Texture;

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		var bmp = (cast local2d : h2d.Bitmap);
		bmp.visible = visible;
		if (propName == null || propName == "src") {
			if (tex != null) {
				tex = null;
			}
			if (src != null) {
				tex = shared.loadTexture(src);
				bmp.tile = h2d.Tile.fromTexture(this.tex);
			} else {
				bmp.tile = h2d.Tile.fromColor(0xFF00FF,32,32,0.5);
			}
		}
		bmp.color = h3d.Vector.fromColor(color);
		bmp.color.w = 1;
		var cRatio = getCenterRatio(dx, dy);
		bmp.tile.setCenterRatio(cRatio[0], cRatio[1]);
		bmp.blendMode = blendMode;
		#if editor
		var int = Std.downcast(bmp.getChildAt(0),h2d.Interactive);
		if( int != null ) {
			int.width = bmp.tile.width;
			int.height = bmp.tile.height;
			int.x = bmp.tile.dx;
			int.y = bmp.tile.dy;
		}
		#end
	}

	override function makeObject2d(parent2d:h2d.Object):h2d.Object {
		var bmp = new h2d.Bitmap(null, parent2d);
		bmp.smooth = true;
		return bmp;
	}

	static public function getCenterRatio(dx : Float, dy : Float) {
		return [0.5 + hxd.Math.clamp(dx, -0.5, 0.5), 0.5 + hxd.Math.clamp(dy, -0.5, 0.5)];
	}

	#if editor

	override function makeInteractive():h2d.Interactive {
		if(local2d == null)
			return null;
		var bmp = cast(local2d, h2d.Bitmap);
		var int = new h2d.Interactive(bmp.tile.width, bmp.tile.height);
		bmp.addChildAt(int, 0);
		int.propagateEvents = true;
		int.x = bmp.tile.dx;
		int.y = bmp.tile.dy;
		return int;
	}

	override function edit( ctx : hide.prefab2.EditContext ) {
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

	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "square", name : "Bitmap" };
	}

	#end

	static var _ = Prefab.register("bitmap", Bitmap);

}
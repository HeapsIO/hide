package hrt.prefab.l2d;

class Gradient extends Object2D {
    @:s var gradient: hrt.impl.Gradient.GradientData = hrt.impl.Gradient.getDefaultGradientData();
    @:s var dx: Float;
    @:s var dy: Float;

	override function makeObject(parent2d:h2d.Object):h2d.Object {
		var bmp = new h2d.Bitmap(null, parent2d);
		bmp.smooth = true;
		return bmp;
	}

    override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		var bmp = (cast local2d : h2d.Bitmap);
		bmp.visible = visible;
        if (bmp.tile == null) {
            bmp.tile = h2d.Tile.fromTexture(hrt.impl.Gradient.textureFromData(gradient));
            bmp.tile.setSize(64,64);
        } else {
            @:privateAccess bmp.tile.setTexture(hrt.impl.Gradient.textureFromData(gradient));
        }

        var cRatio = Bitmap.getCenterRatio(dx,dy);
		bmp.tile.setCenterRatio(cRatio[0], cRatio[1]);

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


    override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
        ctx.properties.add(new hide.Element('<div class="group" name="Parameters">
            <dl>
                <dt>Gradient</dt><dd><input type="gradient" field="gradient"/></dd>
                <dt>Bg Pivot DX</dt><dd><input type="range" min="-0.5" max="0.5" field="dx"/></dd>
                <dt>Bg Pivot DY</dt><dd><input type="range" min="-0.5" max="0.5" field="dy"/></dd>
            </dl></div>'), this, function(pname) {
            ctx.onChange(this, pname);
        });
    }

    override function getHideProps() : hide.prefab.HideProps {
		return { icon : "eyedropper", name : "Gradient" };
	}

	#end

	static var _ = Prefab.register("gradient", Gradient);
}
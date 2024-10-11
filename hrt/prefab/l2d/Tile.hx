package hrt.prefab.l2d;

class Tile extends Bitmap {

	@:s var size : Int;
	@:s var posX : Int = 0;
	@:s var posY : Int = 0;
	@:s var sizeX : Int = 1;
	@:s var sizeY : Int = 1;

	public function new(parent,shared) {
		super(parent,shared);
		sizeX = sizeY = 32;
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);
		var bmp = (cast local2d : h2d.Bitmap);
		bmp.tile = h2d.Tile.fromTexture(bmp.tile.getTexture()).sub(posX*size,posY*size,sizeX*size,sizeY*size);
		var cRatio = Bitmap.getCenterRatio(dx, dy);
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

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);

		ctx.properties.add(new hide.Element('<div class="group" name="Tile">
			<dl>
				<dt>Size</dt><dd><input field="size" class="small"/></dd>
				<dt>Position</dt><dd>
					<input type="number" field="posX" class="small"/>
					<input type="number" field="posY" class="small"/>
				</dd>
				<dt>Size</dt><dd>
					<input type="number" field="sizeX" class="small"/>
					<input type="number" field="sizeY" class="small"/>
				</dd>
			</dl></div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "plus-square-o", name : "Tile" };
	}

	#end

	static var _ = Prefab.register("tile", Tile);

}
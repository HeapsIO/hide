package hrt.prefab2.l2d;

class Blur extends Prefab {

	@:s public var radius : Float = 1.;
	@:s public var quality : Float = 1;
	@:s public var gain : Float = 1.;
	@:s public var linear : Float = 0.;

	// mostly testing
	@:s public var image : String;
	@:s public var zoom : Int = 1;

	var pass : h3d.pass.Blur;

	var bitmap : h2d.Bitmap;

	public function makeFilter() {
		var f = new h2d.filter.Blur(radius, gain, quality);
		f.linear = linear;
		return f;
	}

	public function apply( t : h3d.mat.Texture, ctx : h3d.impl.RenderContext ) {
		if( radius == 0 )
			return t;
		if( pass == null )
			pass = new h3d.pass.Blur();
		pass.quality = quality;
		pass.radius = radius;
		pass.gain = gain;
		pass.linear = linear;
		pass.apply(ctx, t);
		return t;
	}

	override function makeInstance() {
		bitmap = new h2d.Bitmap(null, shared.tempInstanciateLocal2d);
		syncBitmap();
		bitmap.visible = false;
	}

	function syncBitmap() {
		var t;
		if( image != null )
			t = h2d.Tile.fromTexture(shared.loadTexture(image));
		else {
			t = h2d.Tile.fromTexture(h3d.mat.Texture.genChecker(16));
			t.setSize(256, 256);
		}
		t.dx = -t.iwidth>>1;
		t.dy = -t.iheight>>1;
		bitmap.tile = t;
		bitmap.filter = makeFilter();
		bitmap.smooth = true;
		bitmap.tileWrap = image == null;
		bitmap.setScale(zoom);
	}

	#if editor
	override function getHideProps() : hide.prefab2.HideProps {
		return { name : "Blur", icon : "bullseye" };
	}

	override function edit( ctx : hide.prefab2.EditContext ) {
		var e : hide.Element = null;
		function sync( bmp : h2d.Bitmap ) {
			var k = @:privateAccess Std.downcast(bmp.filter, h2d.filter.Blur).pass.getKernelSize();
			e.find("[name=fetches]").text( (k + k) +"x" );
		}
		e = ctx.properties.add(new hide.Element('
			<dl>
				<dt>Radius</dt><dd><input type="range" min="0" max="30" field="radius"/></dd>
				<dt>Gain</dt><dd><input type="range" min="0.5" max="1.5" field="gain"/></dd>
				<dt>Linear</dt><dd><input type="range" min="0" max="1" field="linear"/></dd>
				<dt>Quality</dt><dd><input type="range" min="0" max="1" field="quality"/></dd>
			</dl>
			<br/>
			<dl>
				<dt>Fetches</dt><dd name="fetches"></dd>
				<dt>Test Texture</dt><dd><input type="texturepath" field="image"/></dd>
				<dt>Display zoom</dt><dd><input type="range" min="1" max="8" step="1" field="zoom"/></dd>
			</dl>
		'),this,function(f) {
			sync(bitmap);
		});
		bitmap.visible = true;
		ctx.cleanups.push(function() bitmap.visible = false);
		sync(bitmap);
	}
	#end

	static var _ = Prefab.register("blur", Blur);

}
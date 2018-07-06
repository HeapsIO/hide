package hide.prefab;

class Blur extends Prefab {

	public var radius : Float = 1.;
	public var quality : Float = 1;
	public var gain : Float = 1.;
	public var linear : Float = 0.;

	// mostly testing
	public var image : String;
	public var zoom : Int = 1;

	var pass : h3d.pass.Blur;

	override function load(o:Dynamic) {
		radius = o.radius;
		quality = o.quality;
		gain = o.gain;
		linear = o.linear;
		image = o.image;
		zoom = o.zoom;
	}

	override function save() {
		return {
			radius:radius,
			quality:quality,
			gain:gain,
			linear:linear,
			image : image,
			zoom : zoom,
		};
	}

	override function getHideProps() : HideProps {
		return { name : "Blur", icon : "bullseye" };
	}

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

	override function makeInstance( ctx : Context ) {
		ctx = ctx.clone(this);
		var bmp = new h2d.Bitmap(null, ctx.local2d);
		syncBitmap(bmp, ctx);
		bmp.visible = false;
		ctx.local2d = bmp;
		return ctx;
	}

	function syncBitmap( bmp : h2d.Bitmap, ctx : Context ) {
		var t;
		if( image != null )
			t = h2d.Tile.fromTexture(ctx.loadTexture(image));
		else {
			t = h2d.Tile.fromTexture(h3d.mat.Texture.genChecker(16));
			t.setSize(256, 256);
		}
		bmp.tile = t;
		bmp.filter = makeFilter();
		bmp.smooth = true;
		bmp.tileWrap = image == null;
		bmp.setScale(zoom);
		bmp.x = -(t.width * zoom) >> 1;
		bmp.y = -(t.height * zoom) >> 1;
	}

	override function edit( ctx : EditContext ) {
		#if editor
		var e : hide.Element;
		function sync( bmp : h2d.Bitmap ) {
			var k = @:privateAccess Std.instance(bmp.filter, h2d.filter.Blur).pass.getKernelSize();
			e.find("[name=fetches]").text( (k + k) +"x" );
		}
		e = ctx.properties.add(new hide.Element('
			<dl>
				<dt>Reduce Size</dt><dd><input type="range" min="0" max="8" step="1" field="size"/></dd>
				<dt>Quality</dt><dd><input type="range" min="1" max="4" step="1" field="quality"/></dd>
				<dt>Passes</dt><dd><input type="range" min="0" max="10" step="1" field="passes"/></dd>
				<dt>Sigma</dt><dd><input type="range" min="0" max="5" field="sigma"/></dd>
				<dt>Gain</dt><dd><input type="range" min="0.5" max="1.5" field="gain"/></dd>
			</dl>
			<br/>
			<dl>
				<dt>Fetches</dt><dd name="fetches"></dd>
				<dt>Test Texture</dt><dd><input type="texturepath" field="image"/></dd>
				<dt>Display zoom</dt><dd><input type="range" min="1" max="8" step="1" field="zoom"/></dd>
			</dl>
		'),this,function(f) {
			var ctx = ctx.getContext(this);
			var bmp = cast(ctx.local2d, h2d.Bitmap);
			syncBitmap(bmp, ctx);
			sync(bmp);
		});
		var bmp = cast(ctx.getContext(this).local2d, h2d.Bitmap);
		bmp.visible = true;
		ctx.cleanups.push(function() bmp.visible = false);
		sync(bmp);
		#end
	}


	static var _ = Library.register("blur", Blur);

}
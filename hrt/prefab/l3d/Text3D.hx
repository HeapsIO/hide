package hrt.prefab.l3d;

import h2d.col.Point;

class Text3DPrimitive extends h2d.TileGroup.TileLayerContent {

	public var thickness = 0.;
	public var thicknessX = 0.;
	public var thicknessY = 0.;
	public var cutoff = 0.5;
	public var image : hxd.res.Image;

	override public function add( x : Float, y : Float, r : Float, g : Float, b : Float, a : Float, t : h2d.Tile ) {
		@:privateAccess {
			var sx = x + t.dx;
			var sy = y + t.dy;
			tmp.push(sx);
			tmp.push(sy);
			tmp.push(0);
			tmp.push(0);
			tmp.push(0);
			tmp.push(1);
			tmp.push(t.u);
			tmp.push(t.v);

			tmp.push(sx + t.width);
			tmp.push(sy);
			tmp.push(0);
			tmp.push(0);
			tmp.push(0);
			tmp.push(1);
			tmp.push(t.u2);
			tmp.push(t.v);

			tmp.push(sx);
			tmp.push(sy + t.height);
			tmp.push(0);
			tmp.push(0);
			tmp.push(0);
			tmp.push(1);
			tmp.push(t.u);
			tmp.push(t.v2);

			tmp.push(sx + t.width);
			tmp.push(sy + t.height);
			tmp.push(0);
			tmp.push(0);
			tmp.push(0);
			tmp.push(1);
			tmp.push(t.u2);
			tmp.push(t.v2);

			var x = x + t.dx, y = y + t.dy;
			if( x < xMin ) xMin = x;
			if( y < yMin ) yMin = y;
			x += t.width;
			y += t.height;
			if( x > xMax ) xMax = x;
			if( y > yMax ) yMax = y;

		}
	}

	override public function alloc(engine:h3d.Engine) {
		if( tmp == null ) {
			clear();
			return;
		}
		var data = isSolid() ? buildSolid() : tmp;
		if( data.length > 0 ) {
			buffer = data.length < useAllocatorLimit
				? hxd.impl.Allocator.get().ofFloats(data, hxd.BufferFormat.POS3D_NORMAL_UV)
				: h3d.Buffer.ofFloats(data, hxd.BufferFormat.POS3D_NORMAL_UV);
		}
	}

	override public function render( engine : h3d.Engine ) {
		if( tmp == null || tmp.length == 0) return;
		if( buffer == null || buffer.isDisposed() ) alloc(engine);
		if( buffer == null ) return;
		if( isSolid() )
			engine.renderTriBuffer(buffer);
		else
			engine.renderQuadBuffer(buffer, 0, buffer.vertices >> 1);
	}

	function buildSolid() {
		var out = new hxd.FloatBuffer();
		var pixels = image.getPixels(RGBA);
		var i = 0;
		while( i < tmp.length ) {
			var x0 = tmp[i], y0 = tmp[i + 1], x1 = tmp[i + 24], y1 = tmp[i + 25];
			var u0 = tmp[i + 6] * pixels.width, v0 = tmp[i + 7] * pixels.height;
			var u1 = tmp[i + 30] * pixels.width, v1 = tmp[i + 31] * pixels.height;
			if( u1 > u0 && v1 > v0 )
				buildGlyph(out, pixels, x0, y0, (x1 - x0) / (u1 - u0), (y1 - y0) / (v1 - v0), u0, v0, u1, v1);
			i += 32;
		}
		return out;
	}

	function buildGlyph( out : hxd.FloatBuffer, pixels : hxd.Pixels, x : Float, y : Float, sx : Float, sy : Float, u0 : Float, v0 : Float, u1 : Float, v1 : Float ) {
		var loops = [];
		for( contour in traceContours(pixels, u0, v0, u1, v1) ) {
			var loop = simplify(contour, 0.05);
			var area = 0.;
			for( k in 0...loop.length ) {
				var p = loop[k], q = loop[(k + 1) % loop.length];
				area += p.x * q.y - q.x * p.y;
			}
			area *= 0.5;
			if( Math.abs(area) < 0.25 )
				continue;
			for( p in loop )
				p.set(x + (p.x - u0) * sx, y + (p.y - v0) * sy);
			loops.push({ pts : loop, area : area, holes : [] });
		}

		inline function vert( px : Float, py : Float, pz : Float, nrmX : Float, nrmY : Float, nrmZ : Float, side : Float ) {
			out.push(px);
			out.push(py);
			out.push(pz);
			out.push(nrmX);
			out.push(nrmY);
			out.push(nrmZ);
			out.push(side);
			out.push(0);
		}
		var dx = thicknessX, dy = thicknessY, dz = -thickness;

		var outers = [for( l in loops ) if( l.area > 0 ) l];
		for( h in loops ) {
			if( h.area > 0 )
				continue;
			var best = null, bestArea = Math.POSITIVE_INFINITY;
			for( o in outers )
				if( o.area < bestArea && (o.pts : h2d.col.Polygon).contains(h.pts[0]) ) {
					best = o;
					bestArea = o.area;
				}
			if( best != null )
				best.holes.push(h.pts);
		}

		var earcut = new hxd.earcut.Earcut();
		for( o in outers ) {
			var pts = o.pts.copy();
			var holes = [];
			for( h in o.holes ) {
				holes.push(pts.length);
				for( p in h )
					pts.push(p);
			}
			var tris = earcut.triangulate(pts, holes);
			var k = 0;
			while( k < tris.length ) {
				var a = pts[tris[k]], b = pts[tris[k + 1]], c = pts[tris[k + 2]];
				k += 3;
				if( (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) < 0 ) {
					var swap = b;
					b = c;
					c = swap;
				}
				vert(a.x, a.y, 0, 0, 0, 1, 0);
				vert(b.x, b.y, 0, 0, 0, 1, 0);
				vert(c.x, c.y, 0, 0, 0, 1, 0);
				vert(a.x + dx, a.y + dy, dz, 0, 0, -1, 0);
				vert(c.x + dx, c.y + dy, dz, 0, 0, -1, 0);
				vert(b.x + dx, b.y + dy, dz, 0, 0, -1, 0);
			}
		}

		for( l in loops ) {
			var pts = l.pts;
			var n = pts.length;
			var normals = [for( k in 0...n ) {
				var p = pts[k], q = pts[(k + 1) % n];
				var ex = q.x - p.x, ey = q.y - p.y;
				new h3d.Vector(thickness * ey, -thickness * ex, ey * dx - ex * dy).normalized();
			}];
			for( k in 0...n ) {
				var p = pts[k], q = pts[(k + 1) % n];
				var nc = normals[k], np = normals[(k + n - 1) % n], nn = normals[(k + 1) % n];
				var na = nc.dot(np) > 0.8 ? nc.add(np).normalized() : nc;
				var nb = nc.dot(nn) > 0.8 ? nc.add(nn).normalized() : nc;
				vert(p.x, p.y, 0, na.x, na.y, na.z, 1);
				vert(p.x + dx, p.y + dy, dz, na.x, na.y, na.z, 1);
				vert(q.x, q.y, 0, nb.x, nb.y, nb.z, 1);
				vert(q.x, q.y, 0, nb.x, nb.y, nb.z, 1);
				vert(p.x + dx, p.y + dy, dz, na.x, na.y, na.z, 1);
				vert(q.x + dx, q.y + dy, dz, nb.x, nb.y, nb.z, 1);
			}
		}
	}

	function traceContours( pixels : hxd.Pixels, u0 : Float, v0 : Float, u1 : Float, v1 : Float ) {
		var step = 0.5;
		var nx = Math.ceil((u1 - u0) / step) + 3;
		var ny = Math.ceil((v1 - v0) / step) + 3;
		var values = new hxd.FloatBuffer(nx * ny);
		for( j in 0...ny )
			for( i in 0...nx )
				values[i + j * nx] = i == 0 || j == 0 || i == nx - 1 || j == ny - 1 ? -1 : sample(pixels, u0 + (i - 1) * step, v0 + (j - 1) * step) - cutoff;

		var points = new Map<Int, Point>();
		var next = new Map<Int, Int>();
		var cx = [0, 1, 1, 0], cy = [0, 0, 1, 1];
		var crossings = [];
		for( j in 0...ny - 1 )
			for( i in 0...nx - 1 ) {
				crossings.resize(0);
				var center = 0.;
				for( k in 0...4 ) {
					var i0 = i + cx[k], j0 = j + cy[k];
					var i1 = i + cx[(k + 1) & 3], j1 = j + cy[(k + 1) & 3];
					var a = values[i0 + j0 * nx], b = values[i1 + j1 * nx];
					center += a;
					if( (a > 0) == (b > 0) )
						continue;
					var id = j0 == j1 ? (hxd.Math.imin(i0, i1) + j0 * nx) * 2 : (i0 + hxd.Math.imin(j0, j1) * nx) * 2 + 1;
					if( !points.exists(id) ) {
						var t = a / (a - b);
						points.set(id, new Point(u0 + (i0 + (i1 - i0) * t - 1) * step, v0 + (j0 + (j1 - j0) * t - 1) * step));
					}
					crossings.push(a > 0 ? id : -id - 1);
				}
				var n = crossings.length;
				for( k in 0...n )
					if( crossings[k] >= 0 )
						next.set(crossings[k], -crossings[(k + (center > 0 ? 1 : n - 1)) % n] - 1);
			}

		var contours = [];
		for( start in [for( k in next.keys() ) k] ) {
			if( !next.exists(start) )
				continue;
			var contour = [];
			var e = start;
			do {
				contour.push(points.get(e));
				var n = next.get(e);
				next.remove(e);
				e = n;
			} while( e != start && next.exists(e) );
			contours.push(contour);
		}
		return contours;
	}

	static function simplify( pts : Array<Point>, eps : Float ) {
		var out = [];
		var n = pts.length;
		var a = 0;
		while( a < n ) {
			out.push(pts[a]);
			var e = a + 1;
			while( e < n ) {
				var pa = pts[a], pb = pts[(e + 1) % n];
				var dx = pb.x - pa.x, dy = pb.y - pa.y;
				var len = dx * dx + dy * dy;
				var ok = true;
				for( m in a + 1...e + 1 ) {
					var p = pts[m];
					var t = len == 0 ? 0 : hxd.Math.clamp(((p.x - pa.x) * dx + (p.y - pa.y) * dy) / len);
					var ex = pa.x + dx * t - p.x, ey = pa.y + dy * t - p.y;
					if( ex * ex + ey * ey > eps * eps ) {
						ok = false;
						break;
					}
				}
				if( !ok )
					break;
				e++;
			}
			a = e;
		}
		return out;
	}

	override function getBounds() {
		var bounds = new h3d.col.Bounds();
		if (xMax > xMin && yMax > yMin) {
			bounds.setMin(new h3d.col.Point(xMin + Math.min(thicknessX, 0), yMin + Math.min(thicknessY, 0), -thickness));
			bounds.setMax(new h3d.col.Point(xMax + Math.max(thicknessX, 0), yMax + Math.max(thicknessY, 0), 0.1));
		}
		return bounds;
	}

	override public function getCollider() : h3d.col.Collider {
		return getBounds();
	}

	static function sample( pixels : hxd.Pixels, x : Float, y : Float ) {
		var fx = x - 0.5, fy = y - 0.5;
		var ix = hxd.Math.iclamp(Math.floor(fx), 0, pixels.width - 2);
		var iy = hxd.Math.iclamp(Math.floor(fy), 0, pixels.height - 2);
		var tx = fx - ix, ty = fy - iy;
		var bytes = pixels.bytes;
		var p = pixels.offset + (ix + iy * pixels.width) * 4;
		var stride = pixels.width * 4;
		inline function channel( c : Int ) {
			var a = bytes.get(p + c), b = bytes.get(p + 4 + c);
			var d = bytes.get(p + stride + c), e = bytes.get(p + stride + 4 + c);
			var top = a + (b - a) * tx, bottom = d + (e - d) * tx;
			return top + (bottom - top) * ty;
		}
		var r = channel(0), g = channel(1), b = channel(2);
		return Math.max(Math.min(r, g), Math.min(Math.max(r, g), b)) / 255;
	}

	inline function isSolid() {
		return thickness > 0 && image != null;
	}
}

class SignedDistanceField3D extends hxsl.Shader {

	static var SRC = {

		@param var alphaCutoff : Float = 0.5;
		@param var smoothing : Float = 0.04166666666666666666666666666667; // 1/24
		var pixelColor : Vec4;
		@param var color : Vec4;

		function median(r : Float, g : Float, b : Float) : Float {
			return max(min(r, g), min(max(r, g), b));
		}

		function fragment() {
			pixelColor = vec4(
				color.rgb,
				smoothstep(
					alphaCutoff - smoothing,
					alphaCutoff + smoothing,
					median(pixelColor.r, pixelColor.g, pixelColor.b)
				)
			);
			if (pixelColor.a <= 0.0)
				discard;
		}
	}

}

class Text3DSideColor extends hxsl.Shader {

	static var SRC = {

		@input var input : { var uv : Vec2; };
		@param var sideColor : Vec4;
		var pixelColor : Vec4;
		var side : Float;

		function vertex() {
			side = input.uv.x;
		}

		function fragment() {
			pixelColor.rgb = mix(pixelColor.rgb, sideColor.rgb, side);
		}
	}

}

class Text3DMesh extends h3d.scene.Mesh {

	public var font(get, set) : h2d.Font;
	public var text(get, set): String;

	var text2d : h2d.Text = null;

	public function new(parent : h3d.scene.Object) {
		text2d = new h2d.Text(hxd.res.DefaultFont.get(), null);
		var prim = new Text3DPrimitive();
		super(prim, parent);
		checkText2DPrim();
	}

	function checkText2DPrim() {
		@:privateAccess {
			if (text2d.glyphs.content != primitive) {
				text2d.glyphs.content.dispose();
				text2d.glyphs.content = Std.downcast(primitive, Text3DPrimitive);
			}
		}
	}

	function get_font() { return text2d.font; }
	function set_font(f) {
		text2d.font = f;
		// `Text.set_font` resets our primitive so we have to set it again
		checkText2DPrim();
		return f;
	}

	function get_text() { return text2d.text; }
	function set_text( text : String ) {
		text2d.text = text;
		@:privateAccess text2d.initGlyphs(text);
		return text;
	}
}

@:prefabIcon(HuiRes.ui.icons.prefab.text_3d)
@:prefabName("Text 3D")
class Text3D extends Object3D {

	@:s var color : Int = 0xFFFFFF;
	@:s var size : Int = 12;
	@:s var cutoff : Float = 0.5;
	@:s var smoothing : Float = 1 / 32;
	@:s var letterSpacing : Float = 0;
	@:s var align : Int = 0;
	@:s var thickness : Float = 0;
	@:s var thicknessX : Float = 0;
	@:s var thicknessY : Float = 0;
	@:s var sideColor : Int = 0xFFFFFF;
	@:s var pathFont : String;

	@:s public var contentText : String = "Empty string";

	#if editor

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "font", name : "Text3D" };
	}

	override function edit( ctx : hide.prefab.EditContext ) {
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
			updateInstance("pathFont");
		}
        new hide.Element('<dt>Align</dt>').appendTo(gr);
		var element = new hide.Element('<dd></dd>').appendTo(gr);
		var leftAlign = new hide.Element('<input type="button" style="width: 50px" value="Left" /> ').appendTo(element);
		var middleAlign = new hide.Element('<input type="button" style="width: 50px" value="Center" /> ').appendTo(element);
		var rightAlign = new hide.Element('<input type="button" style="width: 50px" value="Right" /> ').appendTo(element);
		leftAlign.on("click", function(e) {
			align = 0;
			leftAlign.attr("disabled", "true");
			middleAlign.removeAttr("disabled");
			rightAlign.removeAttr("disabled");
			updateInstance("align");
		});
		middleAlign.on("click", function(e) {
			align = 1;
			leftAlign.removeAttr("disabled");
			middleAlign.attr("disabled", "true");
			rightAlign.removeAttr("disabled");
			updateInstance("align");
		});
		rightAlign.on("click", function(e) {
			align = 2;
			leftAlign.removeAttr("disabled");
			middleAlign.removeAttr("disabled");
			rightAlign.attr("disabled", "true");
			updateInstance("align");
		});

		new hide.Element('<dt>Color</dt><dd><input type="color" field="color" /></dd>').appendTo(gr);
		new hide.Element('<dt>Size</dt><dd><input type="range" min="1" max="50" step="1" field="size" /></dd>').appendTo(gr);
		new hide.Element('<dt>Cutoff</dt><dd><input type="range" min="0" max="1" field="cutoff" /></dd>').appendTo(gr);
		new hide.Element('<dt>Smoothing</dt><dd><input type="range" min="0" max="1" field="smoothing" /></dd>').appendTo(gr);
		new hide.Element('<dt>Letter Spacing</dt><dd><input type="range" min="-5" max="5" field="letterSpacing" /></dd>').appendTo(gr);
		new hide.Element('<dt>Thickness</dt><dd><input type="range" min="0" max="10" field="thickness" /></dd>').appendTo(gr);
		new hide.Element('<dt>Thickness X</dt><dd><input type="range" min="-10" max="10" field="thicknessX" /></dd>').appendTo(gr);
		new hide.Element('<dt>Thickness Y</dt><dd><input type="range" min="-10" max="10" field="thicknessY" /></dd>').appendTo(gr);
		new hide.Element('<dt>Side Color</dt><dd><input type="color" field="sideColor" /></dd>').appendTo(gr);

		ctx.properties.add(parameters, this, function(pname) {
			ctx.onChange(this, pname);
		});

		ctx.properties.add(new hide.Element('<div class="group" name="Responsive">
			<dl>
				<dt>Text</dt><dd><input type="text" field="contentText" /></dd>
			</dl></div>'), this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function edit2(ctx : hrt.prefab.EditContext2) {
		super.edit2(ctx);

		ctx.build(
			<category("Parameters")>
				<input label="Text" field={contentText}/>
				<file type="font" field={pathFont}/>
				<select([{label: "Left", value: 0}, {label: "Center", value: 1}, {label: "Right", value: 2}]) id="alignment" field={align}/>
				<color field={color}/>
				<slider min={0} field={size}/>
				<range(0, 1) field={cutoff}/>
				<range(0, 1) field={smoothing}/>
				<slider field={letterSpacing}/>
				<range(0, 10) field={thickness}/>
				<range(-10, 10) field={thicknessX}/>
				<range(-10, 10) field={thicknessY}/>
				<color field={sideColor}/>
			</category>
		);
	}

	#end

	override function updateInstance(?propName : String) {
		super.updateInstance(propName);
		if (pathFont == null || pathFont.length == 0) {
			return;
		}
		var text = loadText();
		if (text == null || text.length == 0)
			return;
		var mesh : Text3DMesh = cast local3d;
		var h2dFont = loadFont();
		mesh.font = h2dFont;
		var text2d = @:privateAccess mesh.text2d;
		text2d.letterSpacing = letterSpacing;
		text2d.smooth = true;
        text2d.textAlign = switch (align) {
			case 1:
				h2d.Text.Align.Center;
			case 2:
				h2d.Text.Align.Right;
			default:
				h2d.Text.Align.Left;
		}
		var prim : Text3DPrimitive = cast mesh.primitive;
		prim.thickness = thickness;
		prim.thicknessX = thicknessX;
		prim.thicknessY = thicknessY;
		prim.cutoff = cutoff;
		prim.image = thickness > 0 ? hxd.res.Loader.currentInstance.load(h2dFont.tile.getTexture().name).toImage() : null;
		mesh.text = text;
		@:privateAccess {
			text2d.glyphs.setDefaultColor(color, 1);
		}
		var shader = mesh.material.mainPass.getShader(SignedDistanceField3D);
		if (shader != null) {
			mesh.material.mainPass.removeShader(shader);
		}
		var sides = mesh.material.mainPass.getShader(Text3DSideColor);
		if (sides != null) {
			mesh.material.mainPass.removeShader(sides);
		}
		if (thickness > 0) {
			mesh.material.texture = null;
			mesh.material.blendMode = None;
			mesh.material.shadows = true;
			mesh.material.color.setColor(0xFF000000 | color);
			sides = new Text3DSideColor();
			sides.sideColor = h3d.Vector4.fromColor(sideColor);
			mesh.material.mainPass.addShader(sides);
		} else {
			mesh.material.texture = h2dFont.tile.getTexture();
			mesh.material.blendMode = Alpha;
			mesh.material.color.setColor(0xFFFFFFFF);
			mesh.material.shadows = false;
			mesh.material.mainPass.setPassName("afterTonemapping");
			shader = new SignedDistanceField3D();
			shader.alphaCutoff = cutoff;
			shader.smoothing = smoothing;
			shader.color = h3d.Vector4.fromColor(color);
			mesh.material.mainPass.addShader(shader);
		}
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

	public dynamic function loadText() : String {
		var str = defaultLoadText(contentText);
		if (str == null) {
			return contentText;
		}
		else return str;
	}

	public static dynamic function defaultLoadText(id: String) : String {
		return null;
	}

	override function makeObject(parent3d : h3d.scene.Object) : h3d.scene.Object {
		var mesh = new Text3DMesh(parent3d);
		mesh.material.blendMode = Alpha;
		return mesh;
	}

	static var _ = Prefab.register("text3d", Text3D);
}
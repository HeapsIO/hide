package hrt.prefab.l3d;

import h2d.col.Point;

class Text3DPrimitive extends h2d.TileGroup.TileLayerContent {

	override public function add( x : Float, y : Float, r : Float, g : Float, b : Float, a : Float, t : h2d.Tile ) {
		@:privateAccess {
			var sx = x + t.dx;
			var sy = y + t.dy;
			tmp.push(sx);
			tmp.push(sy);
			tmp.push(1);
			tmp.push(0);
			tmp.push(0);
			tmp.push(1);
			tmp.push(t.u);
			tmp.push(t.v);

			tmp.push(sx + t.width);
			tmp.push(sy);
			tmp.push(1);
			tmp.push(0);
			tmp.push(0);
			tmp.push(1);
			tmp.push(t.u2);
			tmp.push(t.v);

			tmp.push(sx);
			tmp.push(sy + t.height);
			tmp.push(1);
			tmp.push(0);
			tmp.push(0);
			tmp.push(1);
			tmp.push(t.u);
			tmp.push(t.v2);

			tmp.push(sx + t.width);
			tmp.push(sy + t.height);
			tmp.push(1);
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
		if( tmp.length > 0 ) {
			buffer = tmp.length < useAllocatorLimit
				? hxd.impl.Allocator.get().ofFloats(tmp, hxd.BufferFormat.POS3D_NORMAL_UV)
				: h3d.Buffer.ofFloats(tmp, hxd.BufferFormat.POS3D_NORMAL_UV);
		}
	}

	override public function render( engine : h3d.Engine ) {
		if( tmp == null || tmp.length == 0) return;
		if( buffer == null || buffer.isDisposed() ) alloc(engine);
		engine.renderQuadBuffer(buffer, 0, buffer.vertices >> 1);
	}

	override function getBounds() {
		return h3d.col.Bounds.fromValues(xMin, yMin, 0, xMax, yMax, 0.1);
	}

	override public function getCollider() : h3d.col.Collider {
		return getBounds();
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
			pixelColor = vec4(color.r, color.g, color.b, smoothstep(alphaCutoff - smoothing, alphaCutoff + smoothing, median(pixelColor.r, pixelColor.g, pixelColor.b)));
			if (pixelColor.a <= 0.0)
				discard;
		}
	}

}

class Text3D extends Object3D {

	@:s var color : Int = 0xFFFFFF;
	@:s var size : Int = 12;
	@:s var cutoff : Float = 0.5;
	@:s var smoothing : Float = 1 / 32;
	@:s var letterSpacing : Float = 0;
	@:s var align : Int = 0;
	@:s var pathFont : String;

	@:s public var contentText : String = "Empty string";

	public var text2d : h2d.Text = null;

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
		var mesh : h3d.scene.Mesh = cast local3d;
		var h2dFont = loadFont();
		text2d.font = h2dFont;
		text2d.letterSpacing = letterSpacing;
		text2d.text = text;
		text2d.smooth = true;
        text2d.textAlign = switch (align) {
			case 1:
				h2d.Text.Align.Center;
			case 2:
				h2d.Text.Align.Right;
			default:
				h2d.Text.Align.Left;
		}
		@:privateAccess text2d.glyphs.content = (cast mesh.primitive : Text3DPrimitive);
		@:privateAccess {
			text2d.initGlyphs(text);
			text2d.glyphs.setDefaultColor(color, 1);
			mesh.primitive = text2d.glyphs.content;
			mesh.material.texture = h2dFont.tile.getTexture();
			mesh.material.shadows = false;
			mesh.material.mainPass.setPassName("afterTonemapping");
			var shader = mesh.material.mainPass.getShader(SignedDistanceField3D);
			if (shader != null) {
				mesh.material.mainPass.removeShader(shader);
			}
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
		var mesh = new h3d.scene.Mesh(new Text3DPrimitive(), parent3d);
		mesh.material.blendMode = Alpha;
		text2d = new h2d.Text(hxd.res.DefaultFont.get(), findFirstLocal2d());
		@:privateAccess text2d.glyphs.content = new Text3DPrimitive();
		text2d.name = name;
		return mesh;
	}

	static var _ = Prefab.register("text3d", Text3D);
}
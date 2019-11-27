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
	
	override public function render( engine : h3d.Engine ) {
		if( tmp == null || tmp.length == 0) return;
		super.render(engine);
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
		}
	}

}

class Text3D extends Object3D {

	var color : Int = 16777215;
	var size : Int = 12;
	var cutoff : Float = 0.5;
	var smoothing : Float = 1 / 32;
	var letterSpacing : Float = 0;
	var align : Int = 0;
	
	var pathFont : String;

	public var contentText : String = "Empty string";

	public function new( ?parent ) {
		super(parent);
		type = "text3d";
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		this.color = obj.color;
		this.size = obj.size;
		this.cutoff = obj.cutoff;
		this.smoothing = obj.smoothing;
		this.pathFont = obj.pathFont;
		this.contentText = obj.contentText;
		this.align = obj.align;
	}

	#if editor

	override function save() {
		var obj : Dynamic = super.save();
		obj.color = color;
		obj.size = size;
		obj.cutoff = cutoff;
		obj.smoothing = smoothing;
		obj.pathFont = pathFont;
		obj.contentText = contentText;
		obj.align = align;
		return obj;
	}

	override function getHideProps() : HideProps {
		return { icon : "font", name : "Text3D" };
	}

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
			updateInstance(ctx.getContext(this), "pathFont");
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
			updateInstance(ctx.getContext(this), "align");
		});
		middleAlign.on("click", function(e) {
			align = 1;
			leftAlign.removeAttr("disabled");
			middleAlign.attr("disabled", "true");
			rightAlign.removeAttr("disabled");
			updateInstance(ctx.getContext(this), "align");
		});
		rightAlign.on("click", function(e) {
			align = 2;
			leftAlign.removeAttr("disabled");
			middleAlign.removeAttr("disabled");
			rightAlign.attr("disabled", "true");
			updateInstance(ctx.getContext(this), "align");
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

	#end
	
	override function updateInstance( ctx : Context, ?propName : String) {
		super.updateInstance(ctx, propName);
		if (pathFont == null || pathFont.length == 0) {
			return;
		}
		if (contentText == null || contentText.length == 0)
			return;
		var mesh : h3d.scene.Mesh = cast ctx.local3d;
		var font = hxd.res.Loader.currentInstance.load(pathFont).to(hxd.res.BitmapFont);
		var h2dFont = font.toSdfFont(size, MultiChannel, cutoff, smoothing);
		var h2dText = (cast ctx.local2d : h2d.Text);
		h2dText.font = h2dFont;
		h2dText.letterSpacing = letterSpacing;
		h2dText.text = contentText;
		h2dText.smooth = true;
        h2dText.textAlign = switch (align) {
			case 1:
				Center;
			case 2:
				Right;
			default:
				Left;
		}
		@:privateAccess h2dText.glyphs.content = (cast mesh.primitive : Text3DPrimitive);
		@:privateAccess {
			h2dText.initGlyphs(contentText);
			h2dText.glyphs.setDefaultColor(color, 1);
			mesh.primitive = h2dText.glyphs.content;
			mesh.material.texture = h2dFont.tile.getTexture();
			mesh.material.shadows = false;
			mesh.material.mainPass.setPassName("overlay");
			mesh.material.mainPass.depth(false, LessEqual);
			
			var shader = mesh.material.mainPass.getShader(SignedDistanceField3D);
			if (shader != null) {
				mesh.material.mainPass.removeShader(shader);
			}
			shader = new SignedDistanceField3D();
			shader.alphaCutoff = cutoff;
			shader.smoothing = smoothing;
			shader.color = h3d.Vector.fromColor(color);
			mesh.material.mainPass.addShader(shader);
		}
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var mesh = new h3d.scene.Mesh(new Text3DPrimitive(), ctx.local3d);
		mesh.material.blendMode = Alpha;
		ctx.local3d = mesh;
		ctx.local3d.name = name;
		var h2dText = new h2d.Text(hxd.res.DefaultFont.get(), ctx.local2d);
		@:privateAccess h2dText.glyphs.content = new Text3DPrimitive();
		ctx.local2d = h2dText;
		ctx.local2d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	static var _ = Library.register("text3d", Text3D);
}
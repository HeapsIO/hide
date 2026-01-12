package hrt.ui;

#if hui
class BackgroundShader extends hxsl.Shader {
	static var SRC = {
		@param var size : Vec2;
		@param var smoothSpan = 0.0;
		@param var borderRadius : Vec4;
		@param var borderBevel : Vec4;
		@param var borderSkew : Vec2;
		@param var margins : Vec4;  // top, right, bottom, left

		@param var backgroundColor : Vec4;

		@const @param var useShadow : Bool;
		@param var shadowOffset : Vec2;
		@param var shadowBlurRadius : Float;
		@param var shadowSpreadRadius : Float;
		@param var shadowColor : Vec4;

		@const @param var useImage : Bool;
		@const(4) @param var imgScaleMode : Int;
		@const(4) @param var imgBlendMode : Int;
		@param var imgBounds : Vec4;
		@param var imgTex : Sampler2D;
		@param var imgAngle : Float;
		@param var imgAlpha : Float = 1.0;
		@param var imgScale : Float = 1.0;
		@param var imgOffset : Vec2;

		@const @param var useGradient : Bool;
		@const(4) @param var gradBlendMode : Int;
		@param var gradColor1 : Vec4;  // bottom (css defines linear gradient bottom to top by default)
		@param var gradColor2 : Vec4;  // top
		@param var gradAngle : Float;
		@param var gradAlpha : Float = 1.0;

		@const @param var useBorderTex : Bool;
		@param var borderTex : Sampler2D;

		@const @param var useOutline : Bool;
		@param var outlineColor : Vec4;
		@param var outlineThickness : Vec4; // top, right, bottom, left
		@const @param var separateThicknesses: Bool;
		@param var outlineOffset : Float;

		@const @param var pixelPerfect : Bool = true;

		var calculatedUV : Vec2;
		var pixelColor : Vec4;

		function fragment() {
			var pos = (calculatedUV - 0.5) * size;
			var smooth = smoothSpan;

			var baseAlpha = pixelColor.a;

			var dist = 0.0;
			var marginSize = vec2(margins.y + margins.w, margins.x + margins.z);
			var rectSize = (size - marginSize) * 0.5;
			var offset = margins.yz - marginSize/2;
			pos += offset;
			var relPos = pos / rectSize;

			if(useShadow) {
				var dist = boxSDF(pos - shadowOffset, rectSize - shadowBlurRadius * 0.5) - shadowBlurRadius * 0.5 - shadowSpreadRadius;
				pixelColor = vec4(shadowColor.rgb, shadowColor.a * smoothstep(-shadowBlurRadius, shadowBlurRadius , -dist));
			}

			var alpha = 1.0;
			var outlineAlpha = 0.0;

			if (!pixelPerfect) {
				var dist = boxSDF(pos, rectSize);
				alpha = saturate(-dist/smoothSpan);

				// https://www.desmos.com/calculator/fgpiqhvjvr
				if(useOutline) {
					var w: Float;
					if (separateThicknesses)
						w = getSmoothThickness(pos, rectSize, vec4(borderRadius), outlineThickness);
					else
						w = outlineThickness.x;
					var usedSmooth = (w == 0) ? 0.001 : smoothSpan;
					var ws = (w - usedSmooth) / 2;
					var a = 1 + min(0, ws / usedSmooth - abs((-dist - ws - outlineOffset) / usedSmooth - 1));
					outlineAlpha = saturate(a);
				}

			} else {
				// https://www.desmos.com/calculator/1l2bp1uoos

				var outline = 0.0;
				if (useOutline) {
					if (separateThicknesses)
						outline = getSmoothThickness(pos, rectSize, vec4(borderRadius), outlineThickness);
					else
						outline = outlineThickness.x;
				}

				var halfBorderWidth = (outline-1) / 2.0;
				var remaining = fract(halfBorderWidth)+0.5;
				var boxSize = rectSize - remaining;

				if (outline == 0.0) {
					boxSize += 1.0;
				}

				var dist = boxSDF(pos, boxSize);

				if(useOutline) {
					alpha = dist > 0 ? 0.0 : 1.0;
					outlineAlpha = saturate(1+halfBorderWidth-abs(dist+floor(halfBorderWidth)));
				} else {
					alpha = saturate(0.5-dist);
				}
			}

			var fillColor = backgroundColor;

			if(useBorderTex) {
				var width = borderTex.size().y;
				var d = clamp(dist, 0.5-width, -0.5);
				var g = d / width;
				var bgr = borderTex.get(vec2(0, 1-g));
				fillColor = alphaBlend(fillColor, bgr, 1.0);
			}

			if(useImage) {
				var tuv = vec2(0);
				var pos = rotate(pos, imgAngle);
				var tsize = imgBounds.zw - imgBounds.xy;
				var imgSize = imgTex.size() * tsize * imgScale;
				var tOffset = imgOffset / imgTex.size();

				if(imgScaleMode == 0) // Center
					tuv = saturate(pos / imgSize + 0.5);
				else if(imgScaleMode == 1) { // Fit
					var r = rectSize / imgSize;
					var scale = max(r.x, r.y) * imgScale;
					tuv = 0.5 * pos / (scale * imgSize) + 0.5;
				}
				else if(imgScaleMode == 2) // Repeat
					tuv = pos / imgSize + 0.5;
				else // Stretch
					tuv = relPos * 0.5 + 0.5;
				var c = imgTex.get(imgBounds.xy + tOffset + tuv * tsize);
				fillColor = blendMode(fillColor, c, imgAlpha * c.a, imgBlendMode);
			}

			if(useGradient) {
				var rpt = rotate(relPos, gradAngle);
				var g = mix(gradColor1, gradColor2, 0.5 - rpt.y*0.5);
				fillColor = blendMode(fillColor, g, gradAlpha, gradBlendMode);
			}

			if(useShadow)
				pixelColor = alphaBlend(pixelColor, fillColor, alpha);
			else
				pixelColor = vec4(fillColor.rgb, fillColor.a * alpha);

			pixelColor = alphaBlend(pixelColor, outlineColor, outlineAlpha);

			pixelColor.a *= baseAlpha;
		}

		function boxSDF(pos: Vec2, size: Vec2) : Float {
			// map coordinates to top-left, top-right, bottom-right and bottom-left quadrants respectively
			var index = if (pos.x < 0) {
				pos.y < 0 ? 0 : 3;
			} else {
				pos.y < 0 ? 1 : 2;
			}

			var skew = borderSkew[(index == 0 || index == 3) ? 0 : 1];
			var bevel = borderBevel[index];
			var radius = borderRadius[index];

			// select the right sdf function depending on which corner value is the most
			// relevant for our current quadrant
			if (skew > 0) {
				return sdParallelogram(pos, size, borderSkew);
			} else if (bevel > radius) {
				return sdBevelBox(pos, size, vec4(borderBevel));
			} else {
				return sdRoundBox(pos, size, vec4(borderRadius));
			}
		}

		function alphaBlend(back: Vec4, front: Vec4, a: Float) : Vec4 {
			var fa = front.a * a;
			var na = fa + back.a * (1 - fa);
			var nc = saturate((front.rgb * fa + back.rgb*back.a*(1 - fa)) / na);
			return vec4(nc, na);
		}

		function blendMode(back: Vec4, front: Vec4, a: Float, mode: Int) : Vec4 {
			var fa = front.a * a;
			var na = fa + back.a * (1 - fa);
			var nc = vec3(0);
			if(mode == 1)
				nc = mix(back.rgb, front.rgb + back.rgb, fa);
			else if(mode == 2)
				nc = mix(back.rgb, front.rgb * back.rgb, fa);
			else
				nc = saturate((front.rgb * fa + back.rgb*back.a*(1 - fa)) / na);
			return vec4(nc, na);
		}


		function rotate(n: Vec2, angle: Float) : Vec2 {
			var cosa = cos(angle);
			var sina = sin(angle);
			n.xy = vec2(
				cosa * n.x - sina * n.y,
				cosa * n.y + sina * n.x);
			return n;
		}

		// Copied from https://www.shadertoy.com/view/4llXD7 but with different order of r values to match CSS
		function sdRoundBox( p : Vec2, b : Vec2, r : Vec4 ) : Float {
			var r = r; // Avoid hxsl bug
			r.xy = (p.x > 0.0) ? r.yz : r.xw;
			r.x  = (p.y > 0.0) ? r.y  : r.x;
			var q = abs(p) - b + r.x;
			return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
		}

		function sdBevelBox( p : Vec2, b : Vec2, r : Vec4 ) : Float {
			var r = r; // Avoid hxsl bug
			r.xy = (p.x > 0.0) ? r.yz : r.xw;
			r.x  = (p.y > 0.0) ? r.y  : r.x;
    		var q = abs(p) - b + r.x;
    		var t = max(q, 0.0);
    		var d = abs(t.x) + abs(t.y) - r.x;
    		return min(max(q.x, q.y), 0.0) + d;
		}

		function sdParallelogram( p : Vec2, b : Vec2, sk : Vec2) : Float {
			// manage size and offset for sk.y
			b.x -= abs(sk.y) / 2;
			p.x += abs(sk.y) / 2;
			// manage size and offset for sk.x
			b.x -= abs(sk.x) / 2;
			p.x -= abs(sk.x) / 2;

			var sk = p.x > 0 ? sk.y : sk.x;
			var e = vec2(sk,b.y);
    		var e2 = sk * sk + b.y * b.y;

   			p = (p.y < 0.0) ? -p : p;
    		// horizontal edge
    		var w = p - e;
			w.x -= clamp(w.x, -b.x, b.x);
    		var d = vec2(dot(w,w), -w.y);

    		// vertical edge
    		var s = p.x * e.y - p.y * e.x;
    		p = (s < 0.0) ? -p:p;
    		var v = p - vec2(b.x, 0);
			v -= e * clamp(dot(v,e) / e2, -1.0, 1.0);
    		d = min(d, vec2(dot(v,v), b.x * b.y -abs(s)));
    		return sqrt(d.x) * sign(-d.y);
		}

		function getSmoothThickness( p : Vec2, b : Vec2, r : Vec4, t : Vec4 ) : Float {
			var dist = sdRoundBox(p, b, r);
			r.xy = (p.x > 0.0) ? r.yz : r.xw;
			r.x  = (p.y > 0.0) ? r.y  : r.x;

			var q2 = abs(p) - b;
			var roundDist = abs(dist - (min(max(q2.x, q2.y), 0.0) + length(max(q2, 0.0))));
			var subRatio = (r.x > 0) ? roundDist / (length(vec2(r.x, r.x)) - r.x) : 0;

			var hor  = (p.y > 0.0) ? t.z : t.x;
			var vert = (p.x > 0.0) ? t.y : t.w;
			var princ = (q2.x > q2.y) ? vert : hor;
			var sub   = (q2.x > q2.y) ? hor  : vert;
			return princ * (1 - (subRatio / 2)) + sub * (subRatio / 2);
		}
	}

	public function new() {
		super();
		backgroundColor.setColor(0);
		gradColor1.setColor(0);
		gradColor2.setColor(0);
		outlineColor.setColor(0);
		imgBounds.set(0, 0, 1, 1);
		margins.set(0, 0, 0, 0);
		borderRadius.set(0, 0, 0, 0);
		borderBevel.set(0, 0, 0, 0);
		borderSkew.set(0, 0);
	}
}

@:parser(hrt.ui.CssParser)
class HuiBackground extends h2d.ScaleGrid implements h2d.domkit.Object {

	@:p public var smoothSpan(never, set) : Float;
	function set_smoothSpan(v) { shader.pixelPerfect = v == 0.0; shader.smoothSpan = hxd.Math.max(0.001, v); return v; }

	// Actual order: top-left, top-right, bottom-right, bottom-left, like CSS
	@:p(boxF) public var borderRadius : { left : Float, top : Float, right : Float, bottom : Float };
	@:p(boxF) public var borderBevel : { left : Float, top : Float, right : Float, bottom : Float };
	public var borderSkew : { left: Float, right: Float };

	@:p(bgBorderStyle) public var borderStyle(never, set) : Null<Array<CssParser.BorderStyle>>;
	function set_borderStyle(v : Null<Array<CssParser.BorderStyle>>) {
		if (v == null)
			return null;

		for (e in v) {
			switch (e) {
				case CssParser.BorderStyle.Radius(top, right, bottom, left):
					borderRadius = {left: left, top: top, right: right, bottom: bottom};
				case CssParser.BorderStyle.Bevel(top, right, bottom, left):
					borderBevel = {left: left, top: top, right: right, bottom: bottom};
				case CssParser.BorderStyle.Skew(left, right):
					borderSkew = {left: left, right: right};
			}
		}
		return v;
	}

	@:p(box) public var margin(never, set) : { left : Int, top : Int, right : Int, bottom : Int };
	function set_margin(v) {
		if( v == null )
			_margin.set(0, 0, 0, 0);
		else
			_margin.set(v.top, v.right, v.bottom, v.left);
		return v;
	}
	var _margin : h3d.Vector4 = new h3d.Vector4(0.0,0.0,0.0,0.0);

	@:p public var marginLeft(never, set) : Int;
	function set_marginLeft(v) { shader.margins.w = v; return v; }
	@:p public var marginRight(never, set) : Int;
	function set_marginRight(v) { shader.margins.y = v; return v; }
	@:p public var marginTop(never, set) : Int;
	function set_marginTop(v) { shader.margins.x = v; return v; }
	@:p public var marginBottom(never, set) : Int;
	function set_marginBottom(v) { shader.margins.z = v; return v; }

	@:p(color) @:t(color) public var background(never, set) : Int;
	function set_background(v) {
		shader.backgroundColor.setColor(v);
		return v;
	}
	@:p public var backgroundAlpha(never, set) : Float;
	function set_backgroundAlpha(v) {
		shader.backgroundColor.a = v;
		return v;
	}

	@:p(bgShadow) public var shadow(never, set) : { offsetX: Float, offsetY: Float, blurRadius: Float, spreadRadius: Float, color: Int };
	function set_shadow(s) {
		shader.useShadow = s != null;
		if(s != null) {
			shader.shadowColor.setColor(s.color);
			shadowOffsetX = s.offsetX;
			shadowOffsetY = s.offsetY;
			shadowBlurRadius = s.blurRadius;
			shadowSpreadRadius = s.spreadRadius;
		}
		return s;
	}

	@:p(color) @:t(color) public var shadowColor(never, set) : Int;
	function set_shadowColor(v) {
		shader.shadowColor.setColor(v);
		return v;
	}
	@:p @:t public var shadowAlpha(never, set) : Float;
	function set_shadowAlpha(v) {
		return shader.shadowColor.a = v;
	}

	@:p @:t public var shadowOffsetX(never, set): Float;
	function set_shadowOffsetX(v) {
		return shader.shadowOffset.x = v;
	}

	@:p @:t public var shadowOffsetY(never, set): Float;
	function set_shadowOffsetY(v) {
		return shader.shadowOffset.y = v;
	}

	@:p @:t public var shadowBlurRadius(never, set) : Float;
	function set_shadowBlurRadius(v) {
		return shader.shadowBlurRadius = v;
	}

	@:p @:t public var shadowSpreadRadius(never, set) : Float;
	function set_shadowSpreadRadius(v) {
		// set minimum to 0.5 to get anti aliased corners
		return shader.shadowSpreadRadius = hxd.Math.max(v, 0.5);
	}

	function setTexture(t: h3d.mat.Texture) {
		if(t == null) {
			shader.useImage = false;
			shader.imgTex = null;
		}
		else {
			shader.useImage = true;
			shader.imgTex = t;
		}
	}

	@:p(bgImage) public var image(never, set) : { path: String, mode: CssParser.BackgroundImageMode };
	function set_image(v) {
		if(v != null) {
			try {
				setTexture(hxd.res.Loader.currentInstance.load(v.path).toTexture());
				imageMode = v.mode;
				shader.imgBounds.set(0,0,1,1);
			} catch(e: Dynamic) { }
		}
		return v;
	}

	@:p(tile) public var imageTile(default, set) : h2d.Tile;
	function set_imageTile(t : h2d.Tile) {
		if(t != null) {
			setTexture(t.getTexture());
			@:privateAccess shader.imgBounds.set(t.u, t.v, t.u2, t.v2);
		}
		return this.imageTile = t;
	}

	@:p(tilePos) var imageTilePos(never, set) : { p : Int, ?y : Int };
	function set_imageTilePos(pos : Null<{ p : Int, ?y : Int }>) {
		if (imageTile == null) return pos;
		if (pos == null) pos = {p:0};
		var tex = imageTile.getTexture();
		if (pos.y == null && imageTile.iwidth == tex.width)
			imageTile.setPosition(0, pos.p * imageTile.iheight);
		else
			imageTile.setPosition(pos.p * imageTile.iwidth, pos.y * imageTile.iheight);
		imageTile = imageTile;
		return pos;
	}

	@:p var imageTilePosX(never, set) : Null<Int>;
	function set_imageTilePosX(x : Int) {
		if (imageTile == null) return x;
		imageTile.setPosition(x * imageTile.iwidth, imageTile.iy);
		imageTile = imageTile;
		return x;
	}

	@:p var imageTilePosY(never, set) : Null<Int>;
	function set_imageTilePosY(y : Int) {
		if (imageTile == null) return y;
		imageTile.setPosition(imageTile.ix, y * imageTile.iheight);
		imageTile = imageTile;
		return y;
	}

	@:p var imageOffsetX(default, set) : Int = 0;
	function set_imageOffsetX(x: Int) {
		shader.imgOffset.set(x, imageOffsetY);
		return imageOffsetX = x;
	}
	@:p var imageOffsetY(default, set) : Int = 0;
	function set_imageOffsetY(y: Int) {
		shader.imgOffset.set(imageOffsetX, y);
		return imageOffsetY = y;
	}

	@:p public var imageAlpha(never, set) : Null<Float>;
	function set_imageAlpha(v) { return shader.imgAlpha = v != null ? v : 1.0; }
	@:p(angleRad) public var imageAngle(never, set) : Float;
	function set_imageAngle(v) { return shader.imgAngle = v; }
	@:p public var imageScale(never, set) : Null<Float>;
	function set_imageScale(v) { return shader.imgScale = v != null ? v : 1.0; }
	@:p(bgBlend) public var imageBlend(never, set) : Null<CssParser.BackgroundBlendMode>;
	function set_imageBlend(v) { shader.imgBlendMode = cast v; return v; }
	@:p(bgImageMode) public var imageMode(never, set) : Null<CssParser.BackgroundImageMode>;
	function set_imageMode(v) { shader.imgScaleMode = cast v; return v; }

	@:p(bgGradient) public var gradient(never, set) : { angle: Float, color1: Int, color2: Int };
	function set_gradient(v) {
		if(v == null)
			shader.useGradient = false;
		else {
			shader.useGradient = true;
			shader.gradAngle = hxd.Math.degToRad(v.angle);
			shader.gradColor1.setColor(v.color1);
			shader.gradColor2.setColor(v.color2);
		}
		return v;
	}
	@:p(color) @:t(color) public var gradientColor1(never, set) : Int;
	function set_gradientColor1(v) { shader.gradColor1.setColor(v); return v; }
	@:p(color) @:t(color) public var gradientColor2(never, set) : Int;
	function set_gradientColor2(v) { shader.gradColor2.setColor(v); return v; }
	@:p(angleRad) public var gradientAngle(never, set) : Float;
	function set_gradientAngle(v) { shader.gradAngle = v; return v; }
	@:p public var gradientAlpha(never, set) : Null<Float>;
	function set_gradientAlpha(v) { shader.gradAlpha = v != null ? v : 1; return v; }

	@:p(bgBlend) public var gradientBlend(never, set) : Null<CssParser.BackgroundBlendMode>;
	function set_gradientBlend(v) {
		shader.gradBlendMode = cast v ;
		return v;
	}


	@:p(path) public var borderTex(never, set) : String;
	function set_borderTex(v) {
		if(v == null)
			shader.useBorderTex = false;
		else {
			try {
				shader.borderTex = hxd.res.Loader.currentInstance.load(v).toTexture();
				shader.borderTex.wrap = Repeat;
				shader.useBorderTex = true;
			} catch(e : Dynamic) { }
		}
		return v;
	}

	@:p(bgOutline) public var outline(never, set) : { thick: Float, color: Int };
	function set_outline(v) {
		if(v == null)
			shader.useOutline = false;
		else {
			shader.useOutline = true;
			shader.outlineColor.setColor(v.color);
			shader.outlineThickness.set(v.thick, v.thick, v.thick, v.thick);
			shader.separateThicknesses = false;
		}
		return v;
	}
	@:p(color) @:t(color) public var outlineColor(never, set) : Int;
	function set_outlineColor(v) { shader.outlineColor.setColor(v); return v; }

	@:p(boxF) @:t(boxF) public var outlineThickness(never, set) : { left : Float, top : Float, right : Float, bottom : Float };
	function set_outlineThickness(v) {
		if( v == null ) {
			shader.outlineThickness.set(0, 0, 0, 0);
			shader.separateThicknesses = false;
		} else {
			shader.outlineThickness.set(v.top, v.right, v.bottom, v.left);
			shader.separateThicknesses = v.left != v.top || v.left != v.right || v.left != v.bottom;
		}
		return v;
	}

	@:p public var outlineOffset(never, set) : Float;
	function set_outlineOffset(v) { return shader.outlineOffset = v; }
	@:p public var outlineAlpha(never, set) : Float;
	function set_outlineAlpha(v) { return shader.outlineColor.a = v; }


	var shader : BackgroundShader;

	public function new(?tile : h2d.Tile, ?parent) {
		super(h2d.Tile.fromColor(0), 0, 0, 0, 0, parent);
		shader = new BackgroundShader();
		blendMode = Alpha;
		initComponent();
		addShader(shader);
	}

	override function checkUpdate() {
		// skip super.checkUpdate()
	}

	override function draw( ctx ) {
		x = 0;
		y = 0;
		var flowParent = Std.downcast(parent, h2d.Flow);

		var shadowExtraMargin = 0.0;
		if (shader.useShadow) {
			shadowExtraMargin = hxd.Math.ceil(hxd.Math.max(hxd.Math.abs(shader.shadowOffset.x), hxd.Math.abs(shader.shadowOffset.y)) + shader.shadowSpreadRadius + shader.shadowBlurRadius);
		}
		if (flowParent != null && this == @:privateAccess flowParent.background) {
			width = @:privateAccess flowParent.flowCeil(flowParent.calculatedWidth);
			height = @:privateAccess flowParent.flowCeil(flowParent.calculatedHeight);

			width += 2 * shadowExtraMargin;
			height += 2* shadowExtraMargin;
			x -= shadowExtraMargin;
			y -= shadowExtraMargin;
		}

		calcAbsPos();

		shader.size.set(width, height);

		shader.margins.load(_margin);
		shader.margins.x += shadowExtraMargin;
		shader.margins.y += shadowExtraMargin;
		shader.margins.z += shadowExtraMargin;
		shader.margins.w += shadowExtraMargin;

		if(borderRadius != null) {
			var maxRad = hxd.Math.min(width, height) / 2;
			var v = borderRadius;
			inline function clamp(v: Float) {
				return hxd.Math.min(v, maxRad);
			}
			shader.borderRadius.set(clamp(v.top), clamp(v.right), clamp(v.bottom), clamp(v.left));
		}
		else
			shader.borderRadius.set(0, 0, 0, 0);

		if(borderBevel != null) {
			var maxBev = hxd.Math.min(width, height) / 2;
			var v = borderBevel;
			inline function clamp(v: Float) {
				return hxd.Math.min(v, maxBev);
			}
			shader.borderBevel.set(clamp(v.top), clamp(v.right), clamp(v.bottom), clamp(v.left));
		}
		else
			shader.borderBevel.set(0, 0, 0, 0);

		if (borderSkew != null) {
			var maxSkew = width / 4;
			var v = borderSkew;
			inline function clamp(v: Float) {
				return hxd.Math.min(v, maxSkew);
			}
			shader.borderSkew.set(clamp(v.left), clamp(v.right));
		}
		else
			shader.borderSkew.set(0, 0);

		super.draw(ctx);
	}
}

#end
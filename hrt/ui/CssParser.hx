package hrt.ui;

#if hui
import domkit.CssValue;

typedef BackgroundShadow = { offsetX: Float, offsetY: Float, blurRadius: Float, spreadRadius: Float, color: Int, inset: Bool };

enum TextTransform {
	Capitalize;
	Uppercase;
	Lowercase;
}

enum BorderStyle {
	Radius(top: Float, ?right: Float, ?bot: Float, ?left: Float);
	Bevel(top: Float, ?right: Float, ?bot: Float, ?left: Float);
	Skew(left: Float, ?right: Float);
}

enum abstract BackgroundImageMode(Int) {
	public var Center = 0;
	public var Fit = 1;
	public var Repeat = 2;
	public var Stretch = 3;
}

enum abstract BackgroundBlendMode(Int) {
	public var Alpha = 0;
	public var Add = 1;
	public var Multiply = 2;
}

typedef BoxF = {
	top : Float,
	right : Float,
	bottom : Float,
	left : Float,
}

class CssParser extends h2d.domkit.BaseComponents.CustomParser {

	function parseTextTransform(v : domkit.CssValue) : TextTransform {
		return switch( v ) {
			case VIdent("capitalize"): Capitalize;
			case VIdent("uppercase"): Uppercase;
			case VIdent("lowercase"): Lowercase;
			case VIdent("none"): null;
			default: invalidProp();
		}
	}

	function parseBgType(value : CssValue) {
		return switch(value) {
		case VIdent("none") | VIdent("default"):
			null;
		case VIdent("hui"): "hui";
		default:
			invalidProp();
		}
	}

	function parseBgShadow(value : CssValue) : BackgroundShadow {
		var inset = false;
		var values : Array<CssValue> = null;

		switch(value) {
			case VGroup(v):
				values = v;
			case VIdent("none"):
				return null;
			default:
				invalidProp();
		}

		switch (values[0]) {
			case VIdent("inset"):
				inset = true;
				values.shift();
			default:
		}

		if (values.length < 3)
			invalidProp();

		return {
			inset: inset,
			offsetX: parseFloat(values[0]),
			offsetY: parseFloat(values[1]),
			blurRadius: values.length > 3 ? parseFloat(values[2]) : 0.0,
			spreadRadius: values.length > 4 ? parseFloat(values[3]) : 0.0,
			color: parseColor(values[values.length-1]),
		}
	}

	function parseBgImage(value : CssValue) {
		return switch(value) {
		case VString(path):
			{ path: path, mode: Center };
		case VGroup([VString(path), mode]):
			{ path: path, mode: parseBgImageMode(mode) };
		case VIdent("none"):
			null;
		default:
			invalidProp();
		}
	}

	function parseBgImageMode(value: CssValue) : BackgroundImageMode{
		return switch(parseIdent(value)) {
			case "fit" : Fit;
			case "center" : Center;
			case "repeat" : Repeat;
			case "stretch" : Stretch;
			case x:
				return invalidProp("should be fit|center|repeat|stretch");
		}
	}

	function parseBgGradient(value: CssValue) {
		return switch(value) {
		case VIdent("none"): null;
		case VCall("linear", [a, c1, c2]):
			{ angle: parseAngleDeg(a), color1: parseColor(c1), color2: parseColor(c2) };
		default:
			invalidProp();
		}
	}

	function parseBgOutline(value: CssValue) {
		return switch(value) {
		case VIdent("none"): null;
		case VGroup([VInt(thick), color]):
			{ thick: 0.0 + thick, color: parseColor(color) };
		case VGroup([VFloat(thick), color]):
			{ thick: thick, color: parseColor(color) };
		default:
			invalidProp();
		}
	}

	function parseBgBlend(value: CssValue) : Null<BackgroundBlendMode> {
		return switch(value) {
		case VIdent("none") | VIdent("alpha"): Alpha;
		case VIdent("add"): Add;
		case VIdent("multiply"): Multiply;
		default:
			invalidProp();
		}
	}

	function parseBgBorderStyle(value: CssValue) : Null<Array<BorderStyle>> {
		function parse(value: CssValue) : Null<BorderStyle>{

			return switch(value) {
				case VCall("radius", v):
					var box = parseBoxF(VGroup(v));
					Radius(box.top, box.right, box.bottom, box.left);
				case VCall("bevel", v):
					var box = parseBoxF(VGroup(v));
					Bevel(box.top, box.right, box.bottom, box.left);
				case VCall("skew", [v]):
					Skew(parseFloat(v), parseFloat(v));
				case VCall("skew", [l, r]):
					var left = l.match(VIdent("none")) ? 0 : parseFloat(l);
					var right = r.match(VIdent("none")) ? 0 : parseFloat(r);
					Skew(left, right);
				default:
					invalidProp();
			}
		}

		return switch(value) {
			case VGroup(arr):
				[for (a in arr) parse(a)];
			default:
				[parse(value)];
		}
	}

	function parseBoxF(value: CssValue): BoxF {
		switch( value ) {
			case VFloat(_), VInt(_):
				var v = parseFloat(value);
				return { top : v, right : v, bottom : v, left : v };
			case VGroup([v]):
				return { top : parseFloat(v), right : parseFloat(v), bottom : parseFloat(v), left : parseFloat(v) };
			case VGroup([v, h]):
				return { top : parseFloat(v), right : parseFloat(h), bottom : parseFloat(v), left : parseFloat(h) };
			case VGroup([v, h, k]):
				return { top : parseFloat(v), right : parseFloat(h), bottom : parseFloat(k), left : parseFloat(h) };
			case VGroup([v, h, k, l]):
				return { top : parseFloat(v), right : parseFloat(h), bottom : parseFloat(k), left : parseFloat(l) };
			default:
				return invalidProp();
		}
	}

	public function transitionBoxF(a: BoxF, b: BoxF, p : Float ) {
		if( a == null || b == null )
			return b;
		inline function lerp(a: Float, b: Float) {
			return (b - a) * p + a;
		}
		return {
			top : lerp(a.top, b.top),
			right : lerp(a.right, b.right),
			bottom : lerp(a.bottom, b.bottom),
			left : lerp(a.left, b.left),
		}
	}

	override function loadResource( path : String ) {
		#if macro
		return true;
		#else
		return try {
			var f = HuiRes.loader.load(path);
			if( f.entry.isDirectory ) invalidProp("Resource should be a file "+path);
			return f;
		} catch( e : hxd.res.NotFound ) {
			invalidProp("Resource not found "+path);
		}
		#end
	}

	override function parseFont( value : CssValue ) {
		var path = null;
		var sdf = null;
		var offset: Null<Int> = null, offsetChar = 0;
		var lineHeight : Null<Float> = null, baseLine: Null<Int> = null;
		var scale : Null<Float> = null;
		switch(value) {
			case VIdent("default"):
				#if macro
				return false;
				#else
				return hxd.res.DefaultFont.get();
				#end
			case VGroup(args):
				var args = args.copy();
				path = parsePath(args[0]);
				while (args[1] != null && args[1].match(VCall(_))) {
					switch( args[1] ) {
					case VCall("offset", [VIdent("auto")]):
						offsetChar = -1;
					case VCall("offset", [VString(c)]) if( c.length == 1 ):
						offsetChar = c.charCodeAt(0);
					case VCall("offset", [v]):
						offset = parseInt(v);
					case VCall("line-height", [v]):
						lineHeight = parseFloat(v);
					case VCall("base-line", [v]):
						baseLine = parseInt(v);
					case VCall("scale", [v]):
						scale = parseFloat(v);
					default:
						break;
					}
					args.splice(1,1);
				}
				if( args[1] != null ) {
					sdf = {
						size: parseInt(args[1]),
						channel: args.length >= 3 ? switch(args[2]) {
							case VIdent("red"): h2d.Font.SDFChannel.Red;
							case VIdent("green"): h2d.Font.SDFChannel.Green;
							case VIdent("blue"): h2d.Font.SDFChannel.Blue;
							case VIdent("multi"): h2d.Font.SDFChannel.MultiChannel;
							default: h2d.Font.SDFChannel.Alpha;
						} : h2d.Font.SDFChannel.Alpha,
						cutoff: args.length >= 4 ? parseFloat(args[3]) : 0.5,
						smooth: args.length >= 5 ? parseFloat(args[4]) : 1.0/32.0
					};
					h2d.domkit.BaseComponents.CustomParser.adjustSdfParams(sdf);
				}
			default:

				path = parsePath(value);
		}
		var res = loadResource(path);
		#if macro
		return res;
		#else
		var fnt;

		if(sdf != null)
			return res.to(hxd.res.BitmapFont).toSdfFont(sdf.size, sdf.channel, sdf.cutoff, sdf.smooth);
		else
			return getBitmapFont(res, scale, offset, offsetChar, baseLine, lineHeight);
		#end
	}

	#if !macro
	var bitmapFontCache: Map<String, h2d.Font> = [];
	function getBitmapFont(res: hxd.res.Resource, scale: Null<Float>, offset: Null<Float>, offsetChar: Null<Int>, baseLine: Null<Int>, lineHeight: Null<Float>) {
		if (scale == null && offset == null && offsetChar == null && baseLine == null && lineHeight == null)
			return res.to(hxd.res.BitmapFont).toFont();
		var key = '$res|$scale|$offset|$offsetChar|$baseLine|$lineHeight';

		var fnt = bitmapFontCache.get(key);
		if (fnt != null) {
			return fnt;
		}

		fnt = res.to(hxd.res.BitmapFont).toFont().clone();

		var defChar = offsetChar <= 0 ? fnt.getChar("A".code) ?? fnt.getChar("0".code) ?? fnt.getChar("a".code) : fnt.getChar(offsetChar);
		if( offsetChar != 0 && defChar != null )
			offset = -Math.ceil(defChar.t.dy) + Std.int(@:privateAccess fnt.offsetY);
		if( offset != null || baseLine != null) {
			var prev = @:privateAccess fnt.offsetY;
			fnt.setOffset(0,offset);
			@:privateAccess fnt.lineHeight += offset - prev;
			@:privateAccess fnt.baseLine = fnt.calcBaseLine() + baseLine;
		}
		if (scale != null) {
			fnt.resizeTo(hxd.Math.round(fnt.size * scale));
		}
		if( lineHeight != null && defChar != null ) {
			@:privateAccess fnt.lineHeight = Math.ceil(defChar.t.height * lineHeight);
		}
		bitmapFontCache.set(key, fnt);
		return fnt;
	}
	#end
}

#end
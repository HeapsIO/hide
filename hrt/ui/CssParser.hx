package hrt.ui;

import domkit.CssValue;

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

	function parseBgShadow(value : CssValue) {
		return switch(value) {
		case VGroup([x, y, color]):
			var x = parseFloat(x);
			var y = parseFloat(y);
			var c = parseColor(color);
			{ offsetX: x, offsetY: y, blurRadius: 0.0, spreadRadius: 0.0, color: c };
		case VGroup([x, y, blur, color]):
			var x = parseFloat(x);
			var y = parseFloat(y);
			var b = parseFloat(blur);
			var c = parseColor(color);
			{ offsetX: x, offsetY: y, blurRadius: b, spreadRadius: 0.0, color: c };
		case VGroup([x, y, blur, spread, color]):
			var x = parseFloat(x);
			var y = parseFloat(y);
			var b = parseFloat(blur);
			var s = parseFloat(spread);
			var c = parseColor(color);
			{ offsetX: x, offsetY: y, blurRadius: b, spreadRadius: s, color: c };
		case VIdent("none"):
			null;
		default:
			invalidProp();
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
}
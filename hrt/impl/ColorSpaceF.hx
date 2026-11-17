package hrt.impl;

import h3d.Vector4;

typedef ColorModeF = {
	name : String,
	toRGBA : (value : Vector4, out : Vector4) -> Vector4,
	fromRGBA : (rgba : Vector4, out : Vector4) -> Vector4,
};

/**
	Conversions between float RGBA colors and other color spaces.
	All components are in [0, 1], alpha is kept in w. `out` can be the input vector.
**/
class ColorSpaceF {

	public static function RGBAtoRGBA(rgba : Vector4, out : Vector4) : Vector4 {
		if (out == null)
			out = new Vector4();
		out.load(rgba);
		return out;
	}

	static function getHue(r : Float, g : Float, b : Float, max : Float, delta : Float) : Float {
		if (delta == 0)
			return 0.0;

		var h = if (max == r) hxd.Math.ufmod((g - b) / delta, 6)
			else if (max == g) (b - r) / delta + 2
			else (r - g) / delta + 4;
		return h / 6.0;
	}

	static function hueToRGBA(hue : Float, chroma : Float, m : Float, alpha : Float, out : Vector4) : Vector4 {
		if (out == null)
			out = new Vector4();

		var h = hxd.Math.ufmod(hue, 1.0) * 6.0;
		var x = chroma * (1 - Math.abs(hxd.Math.ufmod(h, 2) - 1));

		var r = 0.0;
		var g = 0.0;
		var b = 0.0;

		if (h < 1) { r = chroma; g = x; }
		else if (h < 2) { r = x; g = chroma; }
		else if (h < 3) { g = chroma; b = x; }
		else if (h < 4) { g = x; b = chroma; }
		else if (h < 5) { r = x; b = chroma; }
		else { r = chroma; b = x; }

		out.set(r + m, g + m, b + m, alpha);
		return out;
	}

	public static function RGBAtoHSV(rgba : Vector4, out : Vector4) : Vector4 {
		var max = Math.max(rgba.r, Math.max(rgba.g, rgba.b));
		var min = Math.min(rgba.r, Math.min(rgba.g, rgba.b));
		var delta = max - min;

		if (out == null)
			out = new Vector4();
		out.set(getHue(rgba.r, rgba.g, rgba.b, max, delta), max == 0 ? 0 : delta / max, max, rgba.a);
		return out;
	}

	public static function HSVtoRGBA(hsv : Vector4, out : Vector4) : Vector4 {
		var chroma = hsv.z * hsv.y;
		return hueToRGBA(hsv.x, chroma, hsv.z - chroma, hsv.w, out);
	}

	public static function RGBAtoHSL(rgba : Vector4, out : Vector4) : Vector4 {
		var max = Math.max(rgba.r, Math.max(rgba.g, rgba.b));
		var min = Math.min(rgba.r, Math.min(rgba.g, rgba.b));
		var delta = max - min;
		var l = (max + min) / 2;

		if (out == null)
			out = new Vector4();
		out.set(getHue(rgba.r, rgba.g, rgba.b, max, delta), delta == 0 ? 0 : delta / (1 - Math.abs(2 * l - 1)), l, rgba.a);
		return out;
	}

	public static function HSLtoRGBA(hsl : Vector4, out : Vector4) : Vector4 {
		var chroma = (1 - Math.abs(2 * hsl.z - 1)) * hsl.y;
		return hueToRGBA(hsl.x, chroma, hsl.z - chroma / 2, hsl.w, out);
	}

	public static var colorModes : Array<ColorModeF> = [
		{ name : "RGB", toRGBA : RGBAtoRGBA, fromRGBA : RGBAtoRGBA },
		{ name : "HSV", toRGBA : HSVtoRGBA, fromRGBA : RGBAtoHSV },
		{ name : "HSL", toRGBA : HSLtoRGBA, fromRGBA : RGBAtoHSL },
	];
}

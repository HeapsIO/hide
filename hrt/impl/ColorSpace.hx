package hrt.impl;

import h3d.Vector4;
import h3d.Vector4;

typedef ColorMode = {
	name: String,
	valueToARGB : (value : Vector4,  outColor : Color) -> Color,
	ARGBToValue : (color : Color, outVector: Vector4) -> Vector4
};

class Color {
	public var r : Int = 0;
	public var g : Int = 0;
	public var b : Int = 0;
	public var a : Int = 0;

	inline public function new(r:Int = 0, g:Int = 0, b:Int = 0, a:Int = 0) {
		this.r = r;
		this.g = g;
		this.b = b;
		this.a = a;
	}

	inline static public function fromInt(rgb: Int, withAlpha: Bool = true) : Color {
		return new Color(
			(rgb >> 16) & 0xFF,
			(rgb >> 8) & 0xFF,
			(rgb >> 0) & 0xFF,
			withAlpha ? (rgb >> 24) & 0xFF : 255
		);
	}
}

class ColorSpace {
    public static function iRGBtofRGB(color : Color, outVector: Vector4) : Vector4 {
		if (outVector == null)
			outVector = new Vector4();
		outVector.set(color.r/255.0, color.g/255.0, color.b/255.0, color.a/255.0);
		return outVector;
	}

	public static function fRGBtoiRGB(color : Vector4, outColor : Color) {
		if (outColor == null)
			outColor = new Color();
		outColor.r = Std.int(color.r*255.0);
		outColor.g = Std.int(color.g*255.0);
		outColor.b = Std.int(color.b*255.0);
		outColor.a = Std.int(color.a*255.0);
		return outColor;
	}

	public static function iRGBtoHSV(color: Color, outVector: Vector4 = null) : Vector4 {
		var r = color.r / 255.0;
		var g = color.g / 255.0;
		var b = color.b / 255.0;
		var a = color.a / 255.0;

		var Cmax = Math.max(r, Math.max(g, b));
		var Cmin = Math.min(r, Math.min(g, b));
		var D = Cmax - Cmin;

		var H = if(D == 0) 0.0
				else if(Cmax == r) hxd.Math.ufmod((g - b)/D, 6) * 60.0
				else if (Cmax == g) ((b - r)/D + 2) * 60.0
				else ((r - g)/D + 4) * 60.0;

		H = H / 360.0;
		H = Math.min(Math.max(H, 0.0), 1.0);

		var S = if (Cmax == 0) 0 else D/Cmax;

		var V = Cmax;

		var A = a;

		if (outVector == null)
			outVector = new Vector4();
		outVector.set(H, S, V, A);
		return outVector;
	}

	public static function HSVtoiRGB(hsv:Vector4, outColor : Color) {
		if (outColor == null)
			outColor = new Color();
		var h = hsv.x * 360.0;
		var s = hsv.y;
		var v = hsv.z;

		var C = v * s;
		var X = C * (1 - Math.abs(hxd.Math.ufmod((h / 60.0),2) - 1));
		var m = v - C;

		var r = 0.0;
		var g = 0.0;
		var b = 0.0;

		if (h < 60) {r = C; g = X;}
		else if (h < 120) {r = X; g = C;}
		else if (h < 180) {g = C; b = X;}
		else if (h < 240) {g = X; b = C;}
		else if (h < 300) {r = X; b = C;}
		else {r = C; b = X;};

		outColor.r = Std.int(Math.round((r+m)*255));
		outColor.g = Std.int(Math.round((g+m)*255));
		outColor.b = Std.int(Math.round((b+m)*255));
		outColor.a = Std.int(hsv.w * 255);

		return outColor;
	}

	public static function iRGBtoHSL(color : Color, outVector: Vector4 = null) : Vector4 {
		var r = color.r / 255.0;
		var g = color.g / 255.0;
		var b = color.b / 255.0;
		var a = color.a / 255.0;

		var Cmax = Math.max(r, Math.max(g, b));
		var Cmin = Math.min(r, Math.min(g, b));
		var D = Cmax - Cmin;

		var H = if(D == 0) 0.0
				else if(Cmax == r) hxd.Math.ufmod((g - b)/D, 6) * 60.0
				else if (Cmax == g) ((b - r)/D + 2) * 60.0
				else ((r - g)/D + 4) * 60.0;

		H = H / 360.0;
		H = Math.min(Math.max(H, 0.0), 1.0);

		var L = (Cmax + Cmin) / 2;
		var S = if (D == 0) 0 else D / (1 - Math.abs(2 * L - 1));

		if (outVector == null)
			outVector = new Vector4();
		outVector.set(H, S, L, a);
		return outVector;
	}

	public static function HSLtoiRGB(hsl : Vector4, outColor : Color) {
		if (outColor == null)
			outColor = new Color();
		var h = hsl.x * 360.0;
		var s = hsl.y;
		var l = hsl.z;

		var C = (1 - Math.abs(2*l-1)) * s;
		var X = C * (1 - Math.abs(hxd.Math.ufmod((h / 60.0),2) - 1));
		var m = l - C/2.0;

		var r = 0.0;
		var g = 0.0;
		var b = 0.0;

		if (h < 60) {r = C; g = X;}
		else if (h < 120) {r = X; g = C;}
		else if (h < 180) {g = C; b = X;}
		else if (h < 240) {g = X; b = C;}
		else if (h < 300) {r = X; b = C;}
		else {r = C; b = X;};

		outColor.r = Std.int(Math.round((r+m)*255));
		outColor.g = Std.int(Math.round((g+m)*255));
		outColor.b = Std.int(Math.round((b+m)*255));
		outColor.a = Std.int(hsl.w * 255);
		return outColor;
	}



	public static function iRGBtoXYZ(color : Color, outVector: Vector4 = null) : Vector4 {
		outVector = iRGBtofRGB(color, outVector);

		inline function linearize(v:Float) : Float {
			return v <= 0.04045 ? v/12.92 : hxd.Math.pow((v + 0.055) / 1.055, 2.4);
		}

		outVector.x = linearize(outVector.x);
		outVector.y = linearize(outVector.y);
		outVector.z = linearize(outVector.z);

		var x = outVector.x * 0.4124 + outVector.y * 0.3576 + outVector.z * 0.1805;
		var y = outVector.x * 0.2126 + outVector.y * 0.7152 + outVector.z * 0.0722;
		var z = outVector.x * 0.0193 + outVector.y * 0.1192 + outVector.z * 0.9505;


		outVector.set(x,y,z,outVector.a);

		return outVector;
	}

	static var tmpVector : Vector4 = new Vector4();
	public static function XYZtoiRGB(value: Vector4, outColor : Color) : Color {
		if (outColor == null)
			outColor = new Color();

		var x = value.r * 0.9505;
		var y = value.g * 1.0;
		var z = value.b * 1.0890;

		var r = value.x * 3.2406 + value.y * -1.5372 + value.z * -0.4986;
		var g = value.x * -0.9689 + value.y * 1.8758 + value.z * 0.0415;
		var b = value.x * 0.0557 + value.y * -0.2040 + value.z * 1.0570;

		// var r = value.x * 2.36461385 + value.y * -0.89654057 + value.z * -0.46807328;
		// var g = value.x * -0.51516621 + value.y * 1.4264081 + value.z * 0.0887581;
		// var b = value.x * 0.0052037 + value.y * -0.01440816 + value.z * 1.00920446;

		inline function delinearize(v:Float) : Float {
			return hxd.Math.clamp(v <= 0.0031308 ? 12.92 * v : 1.055 * hxd.Math.pow(v, 1.0/2.4) - 0.055);
		}

		tmpVector.set(delinearize(r),delinearize(g),delinearize(b),value.a);
		return fRGBtoiRGB(tmpVector, outColor);
	}

	static final Xn = 95.0489;
	static final Yn = 100;
	static final Zn = 108.8840;

	public static function LABtoiRGB(value: Vector4, outColor : Color) : Color {
		// lab -> XYZ
		inline function fn(t:Float) : Float {
			var d = 6.0/29.0;
			return t>d ? t*t*t : 3 * d * d * (t - 4.0 / 29.0);
		}
		var l = value.x * 100.0;
		var a = value.y * 255.0 - 128.0;
		var b = value.z * 255.0 - 128.0;

		tmpVector.x = Xn * fn((l + 16) / 116.0 + a / 500);
		tmpVector.y = Yn * fn((l + 16) / 116.0);
		tmpVector.z = Zn * fn((l + 16) / 116.0 - b / 200);

		tmpVector.x /= 100.0;
		tmpVector.y /= 100.0;
		tmpVector.z /= 100.0;


		return XYZtoiRGB(tmpVector, outColor);
	}

	public static function iRGBtoLAB(color : Color, outVector: Vector4 = null) : Vector4 {
		tmpVector = iRGBtoXYZ(color, tmpVector);

		inline function fn(t:Float) : Float {
			var d = 6.0/29.0;
			return (t > d * d * d) ? hxd.Math.pow(t, 1.0/3.0) : t / 3.0 * d * d + 4 / 29.0;
		}

		var L = 116.0 * fn(tmpVector.y*100.0 / Yn) - 16.0;
		var a = 500.0 * (fn(tmpVector.x*100.0 / Xn) - fn(tmpVector.y*100.0/Yn));
		var b = 200.0 * (fn(tmpVector.y*100.0 / Yn) - fn(tmpVector.z*100.0/Zn));

		if (outVector == null)
			outVector = new Vector4();
		outVector.set(
			hxd.Math.clamp(L/100.0),
			hxd.Math.clamp((a+128.0)/255.0),
			hxd.Math.clamp((b+128.0)/255.0),
			outVector.a
		);
		return outVector;
	}

	public static function iRGBtoHCL(color: Color, outVector: Vector4 = null) : Vector4 {
		outVector = iRGBtoLAB(color, outVector);


		var a = outVector.y * 255.0 - 128.0;
		var b = outVector.z * 255.0 - 128.0;

		var chroma = hxd.Math.sqrt(a * a + b * b) / 100.0;
		var hue = ((hxd.Math.atan2(b, a) + hxd.Math.PI * 2.0) % (hxd.Math.PI * 2.0)) / (hxd.Math.PI * 2.0);
		var luminance = outVector.x;

		outVector.x = hue;
		outVector.y = chroma;
		outVector.z = luminance;

		return outVector;
	}

	public static function HCLtoiRGB(value: Vector4, outColor : Color) : Color {

		tmpVector.x = value.z;

		var a = value.x * hxd.Math.PI * 2.0;
		tmpVector.y = hxd.Math.cos(a) * value.y * 100.0;
		tmpVector.z = hxd.Math.sin(a) * value.y * 100.0;

		tmpVector.y = hxd.Math.clamp((tmpVector.y+128.0)/255.0);
		tmpVector.z = hxd.Math.clamp((tmpVector.z+128.0)/255.0);

		tmpVector.a = value.a;


		return LABtoiRGB(tmpVector, outColor);
	}



	public static var colorModes : Array<ColorMode> = [
		{name:"RGB", valueToARGB: fRGBtoiRGB, ARGBToValue: iRGBtofRGB},
		{name:"HSV", valueToARGB: HSVtoiRGB, ARGBToValue: iRGBtoHSV},
		{name:"HSL", valueToARGB: HSLtoiRGB, ARGBToValue: iRGBtoHSL},
		{name:"XYZ", valueToARGB: XYZtoiRGB, ARGBToValue: iRGBtoXYZ},
		{name:"LAB", valueToARGB: LABtoiRGB, ARGBToValue: iRGBtoLAB},
		{name:"HCL", valueToARGB: HCLtoiRGB, ARGBToValue: iRGBtoHCL},

	];
}
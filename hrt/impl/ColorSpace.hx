package hrt.impl;

import h3d.Vector;

typedef ColorMode = {
	name: String, 
	valueToARGB : (value : Vector,  outColor : Color) -> Color, 
	ARGBToValue : (color : Color, outVector: Vector) -> Vector
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
    public static function iRGBtofRGB(color : Color, outVector: Vector) : Vector {
		if (outVector == null)
			outVector = new Vector();
		outVector.set(color.r/255.0, color.g/255.0, color.b/255.0, color.a/255.0);
		return outVector;
	}

	public static function fRGBtoiRGB(color : Vector, outColor : Color) {
		if (outColor == null)
			outColor = new Color();
		outColor.r = Std.int(color.r*255.0);
		outColor.g = Std.int(color.g*255.0); 
		outColor.b = Std.int(color.b*255.0);
		outColor.a = Std.int(color.a*255.0);
		return outColor;
	}

	public static function iRGBtoHSV(color: Color, outVector: Vector = null) : Vector {
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
			outVector = new Vector();
		outVector.set(H, S, V, A);
		return outVector;
	}

	public static function HSVtoiRGB(hsv:Vector, outColor : Color) {
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

	public static function iRGBtoHSL(color : Color, outVector: Vector = null) : Vector {
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
			outVector = new Vector();
		outVector.set(H, S, L, a);
		return outVector;
	}

	public static function HSLtoiRGB(hsl : Vector, outColor : Color) {
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

	public static var colorModes : Array<ColorMode> = [
		{name:"RGB", valueToARGB: fRGBtoiRGB, ARGBToValue: iRGBtofRGB},
		{name:"HSV", valueToARGB: HSVtoiRGB, ARGBToValue: iRGBtoHSV},
		{name:"HSL", valueToARGB: HSLtoiRGB, ARGBToValue: iRGBtoHSL},
	];
}
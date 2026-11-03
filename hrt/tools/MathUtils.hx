package hrt.tools;

class MathUtils {
	static public function roundToSignificantFigures(value: Float, numDigits: Int ) : Float {
		if (value == 0)
			return 0;
		var digits = hxd.Math.ceil(hxd.Math.log10(hxd.Math.abs(value)));
		var power = numDigits - digits;

		var scale = hxd.Math.pow(10, power);
		if (scale == 0)
			return 0;
		return hxd.Math.round(value * scale) / scale;
	}

	/**
		Returns the value rounded to `decimals` decimals. If the rounded value differs from the actual value,
		all the decimals up to `decimals` are displayed followed by "..." to indicate that the actual value has more digits.
	**/
	static public function formatDecimals(value : Float, decimals : Null<Int>) : String {
		if (decimals == null || !Math.isFinite(value))
			return Std.string(value);

		var dec = hxd.Math.imin(decimals, 15);
		var p = Math.pow(10, dec);
		var scaled = Math.fround(Math.abs(value) * p);

		// Relative tolerance so float64 arithmetic noise (e.g. 0.1 + 0.2 = 0.30000000000000004) isn't reported as extra digits.
		// Float64 epsilon is ~2.2e-16, so 1e-12 leaves room for accumulated error from repeated operations
		var exact = Math.abs(Math.abs(value) - scaled / p) <= Math.abs(value) * 1e-12;

		var intPart = Math.ffloor(scaled / p);
		// Kept as a Float : Std.int would overflow with more than 9 decimals
		var fracDigits = dec > 0 ? Std.string(scaled - intPart * p) : "";
		while (fracDigits.length < dec)
			fracDigits = "0" + fracDigits;

		if (exact) {
			var end = fracDigits.length;
			while (end > 0 && fracDigits.charCodeAt(end - 1) == "0".code)
				end--;
			fracDigits = fracDigits.substr(0, end);
		}

		var str = (value < 0 ? "-" : "") + Std.string(intPart);
		if (fracDigits.length > 0)
			str += "." + fracDigits;
		if (!exact)
			str += "...";
		return str;
	}
}

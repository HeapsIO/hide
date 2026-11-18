package hide.tools;

class StringUtils {
	public static function camelToSpaceCase(str:String):String {
		var wasCap = false;
		var finalString = "";
		for (charIndex in 0...str.length) {
			var char = str.charAt(charIndex);

			if (charIndex == 0) {
				finalString += char.toUpperCase();
				wasCap = true;
				continue;
			}

			var isCap = (char.toUpperCase() == char);

			if (isCap && !wasCap) {
				finalString += " ";
			}

			if (isCap && wasCap) {
				finalString += char.toUpperCase();
				continue;
			}

			finalString += char;

			wasCap = isCap;
		}
		return finalString;
	}
}

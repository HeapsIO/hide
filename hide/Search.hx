package hide;

typedef SearchRanges = Array<Int>;

typedef SearchQuery = Array<String>;

class Search {
	public static function createSearchQuery(search: String, spaceIsAnd: Bool = true) : SearchQuery {
		if (search == null || search == "")
			return null;

		return if (spaceIsAnd) {
			StringTools.trim(search).split(" ");
		} else {
			[search];
		}
	}

	public static function computeSearchRanges(haystack: String, query: SearchQuery, caseSensitive: Bool = false) : SearchRanges {
		if (query == null)
			return null;

		var ranges : SearchRanges = [];
		for (needle in query) {
			var startPos = ranges[0] == 0 ? ranges[1] : 0;
			while(true) {
				var pos = haystack.toLowerCase().indexOf(needle, startPos);
				if (pos < 0)
					return null;

				// skip the ranges we already matched
				for (i in 0...ranges.length>>1) {
					if (pos >= ranges[2*i] && pos < ranges[2*i+1]) {
						startPos = ranges[2*i+1];
						continue;
					}
				}

				ranges.push(pos);
				ranges.push(pos + needle.length);
				break;
			}
		}
		if (ranges.length==0)
			return null;

		// Sort the array of ranges
		for (i in 0...ranges.length >> 1) {
			for (j in i*2...ranges.length >> 1) {
				if (ranges[i*2] > ranges[j*2]) {
					var swap1 = ranges[i*2];
					var swap2 = ranges[i*2+1];

					ranges[i*2] = ranges[j*2];
					ranges[i*2+1] = ranges[j*2+1];

					ranges[j*2] = swap1;
					ranges[j*2+1] = swap2;
				}
			}
		}
		return ranges;
	}

	public static function splitSearchRanges(string: String, ranges: SearchRanges, openToken: String = "<span class='search-hl'>", closeToken: String = "</span>") : String {
		var lastPos = 0;
		var finalName = "";
		for (i in 0...(ranges.length>>1)) {
			var index = i * 2;
			var len = ranges[index+1] - ranges[index];
			if (len > 0) {
				var first = string.substr(lastPos, ranges[index] - lastPos);
				var match = string.substr(ranges[index], len);
				finalName += first + openToken + match + closeToken;
			}
			lastPos = ranges[index+1];
		}
		finalName += string.substr(lastPos);
		return finalName;
	}
}
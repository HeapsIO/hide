package hide;
using StringTools;

typedef SearchRanges = Array<Int>;

typedef SearchQuery = Array<String>;

typedef FuzzySearchResult = {lastCharPos: Int, distance: Int};
typedef BatchFuzzySearchAsyncResult = {pos: Int, lastCharPos: Int, distance: Int};
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

	public static function computeSearchRanges(text: String, query: SearchQuery, caseSensitive: Bool = false) : SearchRanges {
		if (query == null)
			return null;

		text = text.toLowerCase();

		var ranges : SearchRanges = [];
		for (needle in query) {
			var startPos = ranges[0] == 0 ? ranges[1] : 0;
			while(true) {
				var pos = text.indexOf(needle, startPos);
				if (pos < 0)
					return null;

				// skip the ranges we already matched
				var shouldContinue = false;
				for (i in 0...ranges.length>>1) {
					if (pos >= ranges[2*i] && pos < ranges[2*i+1]) {
						startPos = ranges[2*i+1];
						shouldContinue = true;
						break;
					}
				}
				if (shouldContinue) {
					continue;
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

	static var tmpColumn0: Array<Int> = [];
	static var tmpColumn1: Array<Int> = [];
	static var tmpColumn2: Array<Int> = [];

	// based on https://ccc.inaoep.mx/~villasen/bib/Navarro_Review_on_Approximate_Matching_p31-navarro.pdf
	public static function fuzzySearch(text: String, needle: String) : FuzzySearchResult {
		for (i in 0...needle.length+1) {
			tmpColumn2[i] = i;
			tmpColumn0[i] = i;
		}

		var colMinus2 = tmpColumn2;
		var colMinus1 = tmpColumn0;
		var currentColumn = tmpColumn1;


		var minPos = -1;
		var minDist = needle.length + 1;

		var prevChartext = -1;

		for (j in 1...text.length+1) {
			currentColumn[0] = 0;

			var chartext = text.fastCodeAt(j-1);

			var prevCharNeedle = -1;
			for (i in 1...needle.length+1) {
				var charNeedle = needle.fastCodeAt(i-1);
				if (chartext == charNeedle) {
					currentColumn[i] = colMinus1[i-1];
				}
				// substitution rule
				else if (i > 1 && j > 1 && prevCharNeedle == chartext && charNeedle == prevChartext) {
					currentColumn[i] = colMinus2[i-2] + 1;
				}
				else {
					currentColumn[i] = min3(currentColumn[i-1], colMinus1[i], colMinus1[i-1]) + 1;
				}

				prevCharNeedle = charNeedle;
			}

			prevChartext = chartext;

			if (currentColumn[needle.length] < minDist) {
				minPos = j-1;
				minDist = currentColumn[needle.length];
			}

			// rotate the three columns
			var tmp = currentColumn;
			currentColumn = colMinus2;
			colMinus2 = colMinus1;
			colMinus1 = tmp;
		}

		return {lastCharPos: minPos, distance: minDist};
	}

	/**
		Timeslice many fuzzySearch operations by taking around maxTimePerFrame and calling onProgress with the partial results each time.
		Progress correspond to the last `texts` index processed, if equals texts.length, the process is finished. return false to cancel the search
	**/
	public static function batchFuzzySearchAsync(texts: Array<String>, needle: String, maxTimePerFrame: Float, maxDistance: Int,  onProgress: (results: Array<BatchFuzzySearchAsyncResult>, progress: Int) -> Bool) {
		var pos = 0;
		var texts = texts.copy();
		var results : Array<BatchFuzzySearchAsyncResult> = [];

		var schedule = () -> return;

		function process() {
			var startTime = haxe.Timer.stamp();
			while(pos < texts.length) {
				var elapsed = haxe.Timer.stamp() - startTime;

				if (elapsed > maxTimePerFrame) {
					schedule();
					return;
				}

				var res = fuzzySearch(texts[pos], needle);
				if (res.distance < maxDistance) {
					results.push({pos: pos, distance: res.distance, lastCharPos: res.lastCharPos});
				}

				pos += 1;
			}

			onProgress(results, pos);
		}

		schedule = () -> {
			results.sort((a, b) -> Reflect.compare(a.distance, b.distance));
			if (onProgress(results, pos))
				haxe.Timer.delay(process, 0);
		}

		schedule();
	}

	inline static function min3(a,b,c) {
		return if (a <= b && a <= c) {
			a;
		} else if (b <= a && b <= c) {
			b;
		} else c;
	}



}
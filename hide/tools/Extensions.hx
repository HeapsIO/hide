package hide.tools;

@:genericClassPerMethod
class ArrayExtensions {
	/**
		Iterate over all items starting from a random index. Use findRand to interrupt search
	**/
	public static function iterRand<T>(a: Array<T>, func: Int->T->Void) {
		var len = a.length;
		var offset = Std.random(len);
		for(i in 0...len) {
			var idx = (i + offset) % len;
			var item = a[idx];
			func(idx, item);
		}
	}

	/**
		Iterate over all items starting from a random index, until func returns a non-null value
	**/
	public static function findRand<T, R>(a: Array<T>, ?rnd: hxd.Rand, func: Int->T->R) : R {
		var len = a.length;
		var offset = rnd != null ? rnd.random(len) : Std.random(len);
		var ret : R = null;
		for(i in 0...len) {
			var idx = (i + offset) % len;
			var item = a[idx];
			ret = func(idx, item);
			if(ret != null) {
				break;
			}
		}
		return ret;
	}

	static public function last<T>(a: Array<T>) {
		return a[a.length - 1];
	}

	static public function clear<T>(a: Array<T>) {
		a.splice(0, a.length);
	}

	static public function fill<T>(to: Array<T>, from: Array<T>) {
		for(i in 0...from.length)
			to[i] = from[i];
		while(to.length > from.length)
			to.pop();
	}

	static public function unshiftUnique<T>(a: Array<T>, item: T) {
		if(a.indexOf(item) < 0)
			a.unshift(item);
	}

	static public function pushUnique<T>(a: Array<T>, item: T) {
		if(a.indexOf(item) < 0)
			a.push(item);
	}

	static public function appendUnique<T>(a: Array<T>, items: Array<T>) {
		for(item in items) {
			pushUnique(a, item);
		}
	}

	public static function shuffle<T>( a : Array<T>, ?rnd: hxd.Rand) {
		var len = a.length;
		for( i in 0...len ) {
			var y = rnd != null ? rnd.random(len) : Std.random(len);
			var tmp = a[i];
			a[i] = a[y];
			a[y] = tmp;
		}
	}

	public static function pickRandom<T>(a: Array<T>) {
		if(a.length == 0) return null;
		return a[Std.random(a.length)];
	}

	@:generic
	public static function pickWeightIndex<T>(array: Array<T>, ?rnd: hxd.Rand, weight: T -> Float) : Int {
		if(array.length == 0) return -1;
		var total = 0.0;
		for(i in 0...array.length)
			total += weight(array[i]);
		if(total == 0)
			return rnd != null ? rnd.random(array.length) : Std.random(array.length);
		var rval = rnd != null ? rnd.rand() : Math.random();
		var acc = 0.0;
		for(i in 0...array.length) {
			acc += weight(array[i]) / total;
			if(acc >= rval)
				return i;
		}
		return array.length-1;
	}

	@:generic
	public static function pickWeight<T>(array: Array<T>, ?rnd: hxd.Rand, weight: T -> Float) : T {
		if(array.length == 0)
			return null;
		return array[pickWeightIndex(array, rnd, weight)];
	}

	static public function reverseFor<T>(a: Array<T>, func: T->Void) {
		var i = a.length;
		while (i-- > 0)
			func(a[i]);
	}

	static public function removeIf<T>(a: Array<T>, func: T->Bool) {
		var i = a.length;
		while (i-- > 0) {
			if(func(a[i])) {
				a.remove(a[i]);
			}
		}
	}

	// Don't make this Iterable<T> (causes a cast on arrays)
	public static function find<T>( it : Array<T>, f : T -> Bool ) : Null<T> {
		var ret = null;
		for( v in it ) {
			if(f(v)) {
				ret = v;
				break;
			}
		}
		return ret;
	}

	// Don't make this Iterable<T> (causes a cast on arrays)
	public static function filterCount<T>( it : Array<T>, count: Int, f : T -> Bool ) : Array<T> {
		var ret = [];
		for( v in it ) {
			if(f(v)) {
				ret.push(v);
				if(ret.length == count)
					break;
			}
		}
		return ret;
	}

	@:generic
	public static function bubbleSort<T>(array : Array<T>, greater: T->T->Bool) {
		var swapped = false;
		do {
			swapped = false;
			for (i in 0...array.length-1) {
				if (greater(array[i], array[i + 1])) {
					var tmp = array[i];
					array[i] = array[i + 1];
					array[i + 1] = tmp;
					swapped = true;
				}
			}
		} while (swapped);
	}

	@:generic
	public static function sortAsc<T>(array : Array<T>, field: T->Float) {
		bubbleSort(array, (a, b) -> field(a) > field(b));
	}

	@:generic
	public static function sortDesc<T>(array : Array<T>, field: T->Float) {
		bubbleSort(array, (a, b) -> field(a) < field(b));
	}

	public static function any<T>( it : Array<T>, f : T -> Bool ) : Bool {
		return find(it, f) != null;
	}
	public static function exists<T>( it : Array<T>, f : T -> Bool ) : Bool {
		return find(it, f) != null;
	}

	public static function all<T>( it : Array<T>, f : T -> Bool ) : Bool {
		return find(it, e -> !f(e)) == null;
	}

	public static function isEmpty<T>(array : Array<T>) : Bool {
		return array.length <= 0;
	}

	public static function sum<T>(array : Array<T>, f : T -> Float) : Float {
		var sum = 0.;
		for (e in array)
			sum += f(e);
		return sum;
	}

	// Don't make this Iterable<T> (causes a cast on arrays)
	public static function count<T>( it : Array<T>, f : T -> Bool ) : Int {
		var ret = 0;
		for( v in it ) {
			if(f(v)) {
				++ret;
			}
		}
		return ret;
	}

	// Don't make this Iterable<T> (causes a cast on arrays)
	public static function has<A>( it : Array<A>, elt : A ) : Bool {
		var ret = false;
		for( x in it ) {
			if( x == elt ) {
				ret = true;
			}
		}
		return ret;
	}
	static public function enumHas<A: EnumValue>(  it : Array<A>, elt : A ) : Bool {
		var ret = false;
		for( x in it ) {
			if( Type.enumEq(x, elt) )
				ret = true;
		}
		return ret;
	}
	static public function enumContains<A: EnumValue>(  it : Array<A>, elt : A ) : Bool {
		return enumHas(it, elt);
	}

	@:generic
	static public function append<T>(a: Array<T>, b: Array<T>) {
		for(e in b) {
			a.push(e);
		}
		return a;
	}

	/*
	 * Find the element inside the array and return a reference to it
	 * If we could not find it, add it and return a reference to it
	 */
	@:generic
	static public function findOrAdd<T>(a: Array<T>, elem: T) : T {
		if (!a.contains(elem)) {
			a.push(elem);
		}
		return elem;
	}

	@:generic
	static public function filterFindOrAdd<T>(a: Array<T>, elem: T, func: T -> Bool) {
		if (find(a, func) == null) {
			a.push(elem);
		}
		return elem;
	}

	@:generic
	static public function split<T>(a: Array<T>, numGroups: Int): Array<Array<T>> {
		var groups = [for(_ in 0...numGroups) []];
        if(a.length >= 2) {
            for(i in 0...a.length)
                groups[Math.round((numGroups - 1) * i / (a.length - 1))].push(a[i]);
		}
		else if(a.length == 1)
			groups[0].push(a[0]);
		return groups;
	}

	@:generic
	static public function groupBy<T,K>(array: Array<T>, func: T->K): Map<K, Array<T>> {
		var map : Map<K, Array<T>> = new Map();
		for(e in array) {
			var k = func(e);
			var g = map.get(k);
			if(g == null) {
				g = [];
				map.set(k, g);
			}
			g.push(e);
		}
		return map;
	}

	static public function getAll<A,B>(array: Array<A>, f : A -> B): Array<B> {
		var ret : Array<B> = [];
		for(e in array) {
			var b = f(e);
			if(b != null)
				ret.push(b);
		}
		return ret;
	}
}

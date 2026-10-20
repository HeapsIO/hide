package hrt.prefab.fx;

typedef ParamDef = {
	> hrt.prefab.Props.PropDef,
	?animate: Bool,
	?groupName: String
}

class EmitterHelper {

	/** `m.rotate(0, 0, angle)`: the same matrix (the terms `rotate` adds are zeros), without its 4 other sin/cos and the full multiply **/
	public static inline function rotateZ( m : h3d.Matrix, angle : Float ) {
		var c = Math.cos(angle);
		var s = Math.sin(angle);
		var a = m._11, b = m._12;
		m._11 = a * c - b * s; m._12 = a * s + b * c;
		a = m._21; b = m._22;
		m._21 = a * c - b * s; m._22 = a * s + b * c;
		a = m._31; b = m._32;
		m._31 = a * c - b * s; m._32 = a * s + b * c;
		a = m._41; b = m._42;
		m._41 = a * c - b * s; m._42 = a * s + b * c;
	}

	/**
		Sorts the list of `head` by `cmp` as `ListSort.sort` does (stable: the same order), its new head returned, its
		`prev` null. Its first `k` nodes are the particles added since the last sort, at any depth: sorted apart, then
		merged in. The others are about in order from the last sort: an insertion sort, `ListSort.sort` past `budget`
		moves (the camera turned). Exact whatever `k`: on equal keys, the first nodes stay first.
	**/
	public static inline function depthSort<T:{prev:T, next:T}>( head : T, k : Int, budget : Int, cmp : T -> T -> Int ) : T {
		var rest = head;
		for( i in 0...k ) {
			if( rest == null ) break;
			rest = rest.next;
		}
		var fresh : T = null;
		if( rest != head ) {
			fresh = head;
			if( rest != null ) {
				rest.prev.next = null;
				rest.prev = null;
			}
			fresh = haxe.ds.ListSort.sort(fresh, cmp);
		}
		return merge(fresh, insertionSort(rest, budget, cmp), cmp);
	}

	/** `ListSort.sort` of a list about in order: a node goes before the ones it goes before in the merge (`cmp(p, cur) > 0`) **/
	static inline function insertionSort<T:{prev:T, next:T}>( head : T, budget : Int, cmp : T -> T -> Int ) : T {
		var cur = head == null ? null : head.next;
		while( cur != null ) {
			var next = cur.next;
			var p = cur.prev;
			if( cmp(p, cur) > 0 ) {
				p.next = next;
				if( next != null )
					next.prev = p;
				while( p.prev != null && cmp(p.prev, cur) > 0 && --budget >= 0 )
					p = p.prev;
				cur.prev = p.prev;
				cur.next = p;
				if( p.prev != null )
					p.prev.next = cur;
				else
					head = cur;
				p.prev = cur;
				if( budget < 0 ) {
					head = haxe.ds.ListSort.sort(head, cmp);
					break;
				}
			}
			cur = next;
		}
		// `ListSort.sort` sets the `prev` of the head to the tail
		if( head != null )
			head.prev = null;
		return head;
	}

	/** The stable merge of two sorted lists, `a` first on equal keys **/
	static inline function merge<T:{prev:T, next:T}>( a : T, b : T, cmp : T -> T -> Int ) : T {
		var head : T = null, tail : T = null;
		while( a != null || b != null ) {
			var e;
			if( b == null || (a != null && cmp(a, b) <= 0) ) {
				e = a;
				a = a.next;
			} else {
				e = b;
				b = b.next;
			}
			if( tail == null )
				head = e;
			else
				tail.next = e;
			e.prev = tail;
			tail = e;
		}
		return head;
	}
}

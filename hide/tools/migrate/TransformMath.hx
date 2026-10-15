package hide.tools.migrate;

/**
	Matrix helpers of the transform re-bakes of `Upgrade0`: the exact forms of an old animated transform,
	checked at fixed values of the curves. `classes` tells, per component, which curve animates it: the
	components of the same class have the same curve (or curves with the same data), -1 when none does.
**/
class TransformMath {

	/** Values of the curves the forms are checked at, by class **/
	static var SCALES = [[1.7, 0.6, 2.3], [0.4, 2.9, 1.3], [-0.8, 1.5, 0.3]];
	static var ANGLES = [[21.2, -74.5, 166.1], [-133.7, 38.9, 97.3], [251.3, 12.4, -58.6]];
	static var PERMS = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]];

	static function rotation( r : Array<Float> ) {
		var m = new h3d.Matrix();
		m.initRotation(hxd.Math.degToRad(r[0]), hxd.Math.degToRad(r[1]), hxd.Math.degToRad(r[2]));
		return m;
	}

	static function same( a : h3d.Matrix, b : h3d.Matrix ) {
		for( e in [a._11 - b._11, a._12 - b._12, a._13 - b._13, a._21 - b._21, a._22 - b._22, a._23 - b._23, a._31 - b._31, a._32 - b._32, a._33 - b._33] )
			if( Math.abs(e) > 1e-9 ) return false;
		return true;
	}

	static function values( classes : Array<Int>, sample : Array<Float>, def : Float ) {
		return [for( c in classes ) c < 0 ? def : sample[c]];
	}

	/**
		The permutation `p` of the scale components such that base rotation * scale(v) = scale(v[p]) * base
		rotation, for any value `v` of the curves. Null when there is none: the base rotation shears the
		animated scale.
	**/
	public static function scalePermutation( rot : Array<Float>, classes : Array<Int> ) : Null<Array<Int>> {
		var rb = rotation(rot);
		var a = new h3d.Matrix(), b = new h3d.Matrix();
		for( p in PERMS ) {
			var ok = true;
			for( s in SCALES ) {
				var v = values(classes, s, 1);
				a.initScale(v[0], v[1], v[2]);
				a.multiply(rb, a);
				b.initScale(v[p[0]], v[p[1]], v[p[2]]);
				b.multiply(b, rb);
				if( !same(a, b) ) {
					ok = false;
					break;
				}
			}
			if( ok ) return p;
		}
		return null;
	}

	/** The euler triples of the same rotation as `rot`: itself, the other branch, quarter turns, the gimbal family **/
	static function triples( rot : Array<Float> ) : Array<Array<Float>> {
		var ref = rotation(rot);
		var cands = [rot, [rot[0] + 180, 180 - rot[1], rot[2] + 180]];
		for( i in 0...4 ) for( j in 0...4 ) for( k in 0...4 )
			cands.push([i * 90. - 180, j * 90. - 180, k * 90. - 180]);
		for( i in -4...5 ) {
			cands.push([rot[0] + i * 90, rot[1], rot[2] + i * 90]);
			cands.push([rot[0] + i * 90, rot[1], rot[2] - i * 90]);
		}
		var out = [];
		inline function equal( a : Array<Float>, b : Array<Float> ) {
			return Lambda.foreach([0, 1, 2], i -> Math.abs(Math.cos(hxd.Math.degToRad(a[i] - b[i])) - 1) < 1e-12);
		}
		for( c in cands )
			if( same(rotation(c), ref) && !Lambda.exists(out, o -> equal(o, c)) )
				out.push(c);
		return out;
	}

	/**
		Base rotation * rotation(r) as euler angles affine in the curves: angle `j` is `base[j] + sign[j] * r[perm[j]]`
		(`base[j]` alone when no curve animates component `perm[j]`), `base` an euler triple of the base rotation,
		for any value `r` of the curves (degrees). Null when there is none.
	**/
	public static function rotationForm( rot : Array<Float>, classes : Array<Int> ) : Null<{ base : Array<Float>, perm : Array<Int>, sign : Array<Float> }> {
		var rb = rotation(rot);
		var a = new h3d.Matrix();
		var signs = [for( k in 0...8 ) [k & 1 == 0 ? 1. : -1., k & 2 == 0 ? 1. : -1., k & 4 == 0 ? 1. : -1.]];
		for( base in triples(rot) )
			for( p in PERMS )
				for( sg in signs ) {
					if( Lambda.exists([0, 1, 2], j -> classes[p[j]] < 0 && sg[j] < 0) ) continue;
					var ok = true;
					for( s in ANGLES ) {
						var r = values(classes, s, 0);
						a.multiply(rb, rotation(r));
						if( !same(a, rotation([for( j in 0...3 ) base[j] + sg[j] * r[p[j]]])) ) {
							ok = false;
							break;
						}
					}
					if( ok ) return { base: base, perm: p, sign: sg };
				}
		return null;
	}
}

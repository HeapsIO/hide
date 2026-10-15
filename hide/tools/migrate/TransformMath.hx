package hide.tools.migrate;

/**
	Matrix helpers of the transform re-bakes of `Upgrade0`: the exact forms of an old animated transform,
	checked at fixed values of the curves, and the decomposition of the sampled ones. `classes` tells, per component, which curve animates it: the
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

	/** The smallest multiple of the loop periods, 0 when there is none (or not under 16 times the longest one) **/
	public static function commonPeriod( periods : Array<Float> ) : Float {
		var longest = 0.;
		for( p in periods ) if( p > longest ) longest = p;
		if( longest <= 0 ) return 0;
		for( k in 1...17 ) {
			var c = longest * k;
			if( Lambda.foreach(periods, p -> p > 0 && Math.abs(c / p - Math.round(c / p)) < 1e-6) )
				return c;
		}
		return 0;
	}

	public static function scaleMatrix( s : Array<Float> ) {
		var m = new h3d.Matrix();
		m.initScale(s[0], s[1], s[2]);
		return m;
	}

	/**
		Scale and euler angles (radians, closest to `prev`) of a matrix (its 3x3 part), `signs` telling
		the sign of each scale. `error`: what the rebuilt matrix misses of it.
	**/
	public static function decompose( m : h3d.Matrix, prev : Array<Float>, signs : Array<Float> ) : { s : Array<Float>, r : Array<Float>, error : Float, m : h3d.Matrix } {
		var rows = [[m._11, m._12, m._13], [m._21, m._22, m._23], [m._31, m._32, m._33]];
		var det = m._11 * (m._22 * m._33 - m._23 * m._32) - m._12 * (m._21 * m._33 - m._23 * m._31) + m._13 * (m._21 * m._32 - m._22 * m._31);
		var sg = [for( v in signs ) v < 0 ? -1. : 1.];
		if( (sg[0] * sg[1] * sg[2] < 0) != (det < 0) )
			sg = [-sg[0], -sg[1], -sg[2]];
		var s = [for( i in 0...3 ) sg[i] * Math.sqrt(rows[i][0] * rows[i][0] + rows[i][1] * rows[i][1] + rows[i][2] * rows[i][2])];
		var r = [for( i in 0...3 ) [for( j in 0...3 ) s[i] == 0 ? (i == j ? 1. : 0.) : rows[i][j] / s[i]]];
		inline function closest( a : Float, ref : Float ) {
			var tau = Math.PI * 2;
			return a + Math.round((ref - a) / tau) * tau;
		}
		var cands = [];
		var cy = Math.sqrt(r[0][0] * r[0][0] + r[0][1] * r[0][1]);
		if( cy > 1e-6 ) {
			var y = Math.atan2(-r[0][2], cy);
			cands.push([Math.atan2(r[1][2], r[2][2]), y, Math.atan2(r[0][1], r[0][0])]);
			cands.push([Math.atan2(-r[1][2], -r[2][2]), Math.PI - y, Math.atan2(-r[0][1], -r[0][0])]);
		} else {
			var z = prev[2];
			if( -r[0][2] > 0 ) // y = 90
				cands.push([z + Math.atan2(r[1][0], r[1][1]), Math.PI / 2, z]);
			else
				cands.push([Math.atan2(-r[1][0], r[1][1]) - z, -Math.PI / 2, z]);
		}
		var best = null, bestD = Math.POSITIVE_INFINITY;
		for( c in cands ) {
			var a = [for( i in 0...3 ) closest(c[i], prev[i])];
			var dist = 0.;
			for( i in 0...3 ) dist += (a[i] - prev[i]) * (a[i] - prev[i]);
			if( dist < bestD ) {
				bestD = dist;
				best = a;
			}
		}
		// error of the rebuilt matrix
		var check = new h3d.Matrix();
		check.initScale(s[0], s[1], s[2]);
		check.rotate(best[0], best[1], best[2]);
		var err = 0.;
		var scaleRef = Math.max(1e-6, Math.max(Math.abs(s[0]), Math.max(Math.abs(s[1]), Math.abs(s[2]))));
		for( e in [check._11 - m._11, check._12 - m._12, check._13 - m._13, check._21 - m._21, check._22 - m._22, check._23 - m._23, check._31 - m._31, check._32 - m._32, check._33 - m._33] )
			err = Math.max(err, Math.abs(e) / scaleRef);
		return { s: s, r: best, error: err, m: check };
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

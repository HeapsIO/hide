package hide.tools.migrate;

/** Matrix helpers of the transform re-bakes of `Upgrade0` **/
class TransformMath {

	/** Whether base rotation * R_k(a) is the euler angles `rot` with `s * a` added to angle `j`, for any `a`. **/
	public static function rotationMatches( rot : Array<Float>, k : Int, j : Int, s : Float ) {
		var m1 = new h3d.Matrix(), m2 = new h3d.Matrix(), r = new h3d.Matrix();
		for( a in [0.37, 1.3, 2.9, -2.2] ) {
			var b = [for( v in rot ) hxd.Math.degToRad(v)];
			m1.initRotation(b[0], b[1], b[2]);
			r.initRotation(k == 0 ? a : 0, k == 1 ? a : 0, k == 2 ? a : 0);
			m1.multiply(m1, r);
			b[j] += s * a;
			m2.initRotation(b[0], b[1], b[2]);
			for( e in [m1._11 - m2._11, m1._12 - m2._12, m1._13 - m2._13, m1._21 - m2._21, m1._22 - m2._22, m1._23 - m2._23, m1._31 - m2._31, m1._32 - m2._32, m1._33 - m2._33] )
				if( Math.abs(e) > 1e-9 ) return false;
		}
		return true;
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
}

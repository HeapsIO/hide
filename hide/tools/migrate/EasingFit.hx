package hide.tools.migrate;

import hrt.prefab.fx.Easing;

typedef EasingMatch = { ease : Easing, a : Float, b : Float, error : Float };

/**
	The easing a curve over [0, 1] (the particle life) is close to: `curve(t) ~ lerp(a, b, ease(t))`.
	The error is the largest distance to the curve, relative to the range of its values.
**/
class EasingFit {

	static inline var SAMPLES = 201;

	/**
		The easing closest to `curve`, null when none is within `tol`. Its ends at the values of the curve
		at 0 and 1 when one is (the keys of the curve), else the bounds of a minimax fit.
	**/
	public static function fit( curve : hrt.prefab.Curve, tol : Float ) : Null<EasingMatch> {
		var v = [for( i in 0...SAMPLES ) curve.getVal(i / (SAMPLES - 1))];
		var mn = v[0], mx = v[0];
		for( x in v ) {
			if( x < mn ) mn = x;
			if( x > mx ) mx = x;
		}
		var range = mx - mn;
		if( range <= 1e-9 * Math.max(1, Math.abs(mx)) )
			return null;
		var ends : EasingMatch = null, best : EasingMatch = null;
		for( e in Easing.ALL ) {
			var es = [for( i in 0...SAMPLES ) e.eval(i / (SAMPLES - 1))];
			var a = v[0], b = v[SAMPLES - 1];
			var err = error(v, es, a, b - a) / range;
			if( err <= tol && (ends == null || err < ends.error) )
				ends = { ease: e, a: a, b: b, error: err };
			if( ends == null ) {
				var f = minimax(v, es, range);
				if( f.error <= tol && (best == null || f.error < best.error) )
					best = { ease: e, a: f.a, b: f.a + f.k, error: f.error };
			}
		}
		return ends ?? best;
	}

	static function error( v : Array<Float>, es : Array<Float>, a : Float, k : Float ) {
		var m = 0.;
		for( i in 0...SAMPLES ) {
			var d = Math.abs(v[i] - a - k * es[i]);
			if( d > m ) m = d;
		}
		return m;
	}

	/** `v ~ a + k * es` with the smallest largest error: least squares reweighted by the errors (Lawson) **/
	static function minimax( v : Array<Float>, es : Array<Float>, range : Float ) {
		var w = [for( i in 0...SAMPLES ) 1.0 / SAMPLES];
		var best = { a: 0., k: 0., error: Math.POSITIVE_INFINITY };
		for( it in 0...40 ) {
			var sw = 0., sx = 0., sy = 0., sxx = 0., sxy = 0.;
			for( i in 0...SAMPLES ) {
				var x = es[i], y = v[i], q = w[i];
				sw += q; sx += q * x; sy += q * y; sxx += q * x * x; sxy += q * x * y;
			}
			var d = sw * sxx - sx * sx;
			var k = Math.abs(d) < 1e-15 ? 0. : (sw * sxy - sx * sy) / d;
			var a = (sy - k * sx) / sw;
			var err = error(v, es, a, k) / range;
			if( err < best.error )
				best = { a: a, k: k, error: err };
			// far from any tolerance, not worth refining
			if( it == 0 && err > 0.5 )
				break;
			var tot = 0.;
			for( i in 0...SAMPLES ) {
				w[i] *= Math.abs(v[i] - a - k * es[i]) + 1e-9 * range;
				tot += w[i];
			}
			for( i in 0...SAMPLES ) w[i] /= tot;
		}
		return best;
	}
}

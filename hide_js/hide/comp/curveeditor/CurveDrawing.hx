package hide.comp.curveeditor;

#if (domkit && js)

import hide.kit.Curve;

typedef CurveBounds = {
	minX : Float,
	maxX : Float,
	minY : Float,
	maxY : Float
};

typedef CurveView = {
	> CurveBounds,
	w : Float,
	h : Float,
	pad : Float
};

class CurveDrawing {
	static inline var SAMPLES = 256;

	public static function x(view: CurveView, t: Float) {
		return view.pad + (t - view.minX) / (view.maxX - view.minX) * (view.w - view.pad * 2);
	}

	public static function y(view: CurveView, v: Float) {
		return view.h - view.pad - (v - view.minY) / (view.maxY - view.minY) * (view.h - view.pad * 2);
	}

	/** The value of `t` at `time`, `side` -1 / 1 for the min / max of its random band **/
	public static function trackValue(t: CurveTrack, time: Float, side: Int = 0) {
		return t.data.getVal(time) + side * t.spreadAt(time);
	}

	public static function frame(tracks: Array<CurveTrack>, maxTime: Float) : CurveBounds {
		var end = maxTime;
		if (!Math.isFinite(end)) {
			end = 1.;
			for (t in tracks)
				if (t.data != null && t.data.keys.length > 0)
					end = Math.max(end, t.data.keys[t.data.keys.length - 1].time);
		}
		var bounds = { minX: 0., maxX: end, minY: 0., maxY: 1. };
		for (t in tracks) {
			if (t.data == null)
				continue;
			for (side in (t.spread == null ? [0] : [-1, 1]))
				for (i in 0...SAMPLES + 1) {
					var v = trackValue(t, i / SAMPLES * end, side);
					bounds.minY = Math.min(bounds.minY, v);
					bounds.maxY = Math.max(bounds.maxY, v);
				}
		}
		return bounds;
	}

	/** The curves of `tracks` and their bands: the `bands` between two tracks, the min and the max of a random curve **/
	public static function drawTracks(svg: SVG, tracks: Array<CurveTrack>, bands: Array<CurveBand>, view: CurveView, maxTime: Float, samples: Int, ?active: CurveTrack) {
		var t0 = Math.max(view.minX, 0);
		var t1 = Math.min(view.maxX, maxTime);
		if (t1 <= t0)
			return;
		for (b in bands)
			if (b.a.data != null && b.b.data != null)
				band(svg, view, t0, t1, samples, b.a, 0, b.b, 0);
		for (t in tracks) {
			if (t.data == null)
				continue;
			if (t.spread != null)
				band(svg, view, t0, t1, samples, t, -1, t, 1);
			for (side in (t.spread == null ? [0] : [0, -1, 1])) {
				var line = svg.polygon(svg.element, points(view, t0, t1, samples, t, side));
				line.addClass(side == 0 ? "main" : "extreme");
				line.toggleClass("other", active != null && t != active);
			}
		}
	}

	static function band(svg: SVG, view: CurveView, t0: Float, t1: Float, samples: Int, a: CurveTrack, sideA: Int, b: CurveTrack, sideB: Int) {
		var back = points(view, t0, t1, samples, b, sideB);
		back.reverse();
		svg.polygon2(svg.element, points(view, t0, t1, samples, a, sideA).concat(back)).addClass("band");
	}

	static function points(view: CurveView, t0: Float, t1: Float, samples: Int, track: CurveTrack, side: Int) {
		var pts = [];
		for (i in 0...samples + 1) {
			var t = hxd.Math.lerp(t0, t1, i / samples);
			pts.push(new h2d.col.Point(x(view, t), y(view, trackValue(track, t, side))));
		}
		return pts;
	}
}

#end

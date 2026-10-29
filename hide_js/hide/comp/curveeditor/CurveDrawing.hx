package hide.comp.curveeditor;

#if (domkit && js)

import hide.kit.Curve;

typedef DisplayRange = {
	from : Float,
	to : Float
};

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
	static inline var SAMPLES = 64;

	public static function x(view: CurveView, t: Float) {
		return view.pad + (t - view.minX) / (view.maxX - view.minX) * (view.w - view.pad * 2);
	}

	public static function y(view: CurveView, v: Float) {
		return view.h - view.pad - (v - view.minY) / (view.maxY - view.minY) * (view.h - view.pad * 2);
	}

	public static function getDisplayRanges(t: CurveTrack) : Array<DisplayRange> {
		var rs : Array<DisplayRange> = [for (r in t.ranges) { from: r.from.v(), to: r.to.v() }];
		return switch (rs.length) {
			case 0: [{ from: 0, to: 1 }];
			case 2: [{ from: (rs[0].from + rs[1].from) * 0.5, to: (rs[0].to + rs[1].to) * 0.5 }].concat(rs);
			default: rs;
		}
	}

	public static function trackDisplay(t: CurveTrack, v: Float) {
		var r = getDisplayRanges(t)[0];
		return hxd.Math.lerp(r.from, r.to, v);
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
			for (r in getDisplayRanges(t))
				for (i in 0...SAMPLES + 1) {
					var v = hxd.Math.lerp(r.from, r.to, t.data.getVal(i / SAMPLES * end));
					bounds.minY = Math.min(bounds.minY, v);
					bounds.maxY = Math.max(bounds.maxY, v);
				}
		}
		return bounds;
	}

	/** The curves of `tracks` and their bands: the `bands` between two tracks, the min and the max of a random curve **/
	public static function drawTracks(svg: SVG, tracks: Array<CurveTrack>, bands: Array<CurveBand>, view: CurveView, maxTime: Float, ?active: CurveTrack) {
		var t0 = Math.max(view.minX, 0);
		var t1 = Math.min(view.maxX, maxTime);
		if (t1 <= t0)
			return;
		for (b in bands)
			if (b.a.data != null && b.b.data != null)
				band(svg, view, t0, t1, b.a.data, getDisplayRanges(b.a)[0], b.b.data, getDisplayRanges(b.b)[0]);
		for (t in tracks) {
			if (t.data == null)
				continue;
			var rs = getDisplayRanges(t);
			if (rs.length == 3)
				band(svg, view, t0, t1, t.data, rs[1], t.data, rs[2]);
			for (i => r in rs) {
				var line = svg.polygon(svg.element, points(view, t0, t1, t.data, r));
				line.addClass(i == 0 ? "main" : "extreme");
				line.toggleClass("other", active != null && t != active);
			}
		}
	}

	static function band(svg: SVG, view: CurveView, t0: Float, t1: Float, c0: hrt.impl.Curve, r0: DisplayRange, c1: hrt.impl.Curve, r1: DisplayRange) {
		var back = points(view, t0, t1, c1, r1);
		back.reverse();
		svg.polygon2(svg.element, points(view, t0, t1, c0, r0).concat(back)).addClass("band");
	}

	static function points(view: CurveView, t0: Float, t1: Float, curve: hrt.impl.Curve, r: DisplayRange) {
		var pts = [];
		for (i in 0...SAMPLES + 1) {
			var t = hxd.Math.lerp(t0, t1, i / SAMPLES);
			pts.push(new h2d.col.Point(x(view, t), y(view, hxd.Math.lerp(r.from, r.to, curve.getVal(t)))));
		}
		return pts;
	}
}

#end

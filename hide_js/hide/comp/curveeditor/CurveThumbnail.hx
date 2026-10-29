package hide.comp.curveeditor;

#if (domkit && js)

import hide.kit.Curve;

class CurveThumbnail {
	public var svg(default, null) : js.html.svg.SVGElement;

	var drawing : SVG;
	var tracks : Array<CurveTrack>;
	var bands : Array<CurveBand>;
	var maxTime : Float;

	public function new(tracks: Array<CurveTrack>, bands: Array<CurveBand>, maxTime: Float) {
		this.tracks = tracks;
		this.bands = bands;
		this.maxTime = maxTime;
		drawing = new SVG();
		svg = cast drawing.element[0];
		svg.setAttribute("viewBox", "0 0 1 1");
		svg.setAttribute("preserveAspectRatio", "none");
		refresh();
	}

	public function refresh() {
		drawing.clear();
		var bounds = CurveDrawing.frame(tracks, maxTime);
		var view : CurveDrawing.CurveView = { minX: bounds.minX, maxX: bounds.maxX, minY: bounds.minY, maxY: bounds.maxY, w: 1, h: 1, pad: 0 };
		var zero = CurveDrawing.y(view, 0);
		drawing.line(drawing.element, 0, zero, 1, zero).addClass("zero");
		CurveDrawing.drawTracks(drawing, tracks, bands, view, maxTime);
	}
}

#end

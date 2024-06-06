package hide.comp;
import hide.Element;

class SVG extends Component {

	var document : js.html.HTMLDocument = null;

	public function new(?parent:Element,?el) {
		document = parent == null ? js.Browser.document : parent[0].ownerDocument;
		if( el == null ) el = new Element(document.createElementNS('http://www.w3.org/2000/svg', 'svg'));
		super(parent,el);
		element.attr("width", "100%");
		element.attr("height", "100%");
	}

	public function clear() {
		element.empty();
	}

	public function add(el: Element) {
		element.append(el);
	}

	public function make(?parent: Element, name: String, ?attr: Dynamic, ?style: Dynamic) {
		var e = document.createElementNS('http://www.w3.org/2000/svg', name);
		var el = new Element(e);
		if(attr != null)
			el.attr(attr);
		if(style != null)
			el.css(style);
		if(parent != null)
			parent.append(el);
		return el;
	}

	public function circle(?parent: Element, x:Float, y:Float, radius:Float, ?style:Dynamic) {
		return make(parent, "circle", {cx:x, cy:y, r:radius}, style);
	}

	public function rect(?parent: Element, x:Float, y:Float, width:Float, height:Float, ?style:Dynamic) {
		return make(parent, "rect", {x:x, y:y, width:width, height:height}, style);
	}

	public function line(?parent: Element, x1:Float, y1:Float, x2:Float, y2:Float, ?style:Dynamic) {
		return make(parent, "line", {x1:x1, y1:y1, x2:x2, y2:y2}, style);
	}

	public function curve(?parent: Element, x1:Float, y1:Float, x2:Float, y2:Float, xTurn:Float, yTurn:Float, ?style:Dynamic) {
		return make(parent, "path", {d : 'M ${x1} ${y1} Q ${xTurn} ${yTurn}, ${x1 + (x2-x1)/2} ${y1 + (y2-y1)/2}, T ${x2} ${y2}'}, style);
	}

	public function straightCurve(?parent: Element, x1: Float, y1: Float, x2: Float, y2: Float, advance: Float, round: Float, ?style:Dynamic) {

		var dx = (x2 - advance) - (x1 + advance);
		var dy = y2 - y1;
		var len = hxd.Math.max(0.001, hxd.Math.distance(dx, dy));


		var diagXOffset = dx/len * advance * round;
		var diagYOffset = dy/len * advance * round;

		return make(parent, "path",
			{d : '
				M ${x1} ${y1}
				L ${x1+advance * (1.0-round)} ${y1}
				Q ${x1+advance} ${y1}, ${x1+advance+diagXOffset} ${y1+diagYOffset}
				L ${x2-advance-diagXOffset} ${y2-diagYOffset}
				Q ${x2-advance} ${y2}, ${x2-advance * (1.0-round)} ${y2}
				L ${x2} ${y2}
				'}, style);
	}

	public function foreignObject(?parent: Element, x:Float, y:Float, width:Float, height:Float, ?style:Dynamic) {
		return make(parent, "foreignObject", {x:x, y:y, width:width, height:height}, style);
	}

	public function polygon(?parent: Element, points: Array<h2d.col.Point>, ?style:Dynamic) {
		// TODO: Use https://www.w3schools.com/graphics/svg_polygon.asp
		var lines = ['M${points[0].x},${points[0].y} '];
		for(i in 1...points.length) {
			lines.push('L${points[i].x},${points[i].y} ');
		}
		return make(parent, "path", {d: lines.join("")}, style);
	}

	public function group(?parent: Element, ?className: String, ?attr: Dynamic) {
		var g = make(parent, "g", attr);
		if(className != null)
			g.addClass(className);
		return g;
	}

	public function text(?parent: Element, x: Float, y: Float, text: String, ?style: Dynamic) {
		var e = make(parent, "text", {x:x, y:y}, style);
		e.text(text);
		return e;
	}
}
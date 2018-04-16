package hide.comp;

class CurveEditor extends Component {

	public var xScale = 200.;
	public var yScale = 30.;
	public var xOffset = 0.;
	public var yOffset = 0.;

	public var curve : hide.prefab.Curve;

	var svg : hide.comp.SVG;
	var width = 0;
	var height = 0;

	public function new(root, curve : hide.prefab.Curve) {
		super(root);
		this.curve = curve;
		svg = new hide.comp.SVG(root);
		svg.element.resize((e) -> refresh());
		svg.element.addClass("hide-curve-editor");
	}

	inline function xt(x: Float) return (x + xOffset) * xScale;
	inline function yt(y: Float) return (y + yOffset) * yScale + height/2;
	inline function ixt(px: Float) return px / xScale - xOffset;
	inline function iyt(py: Float) return (py - height/2) / yScale - yOffset;

	public function refresh(?animKey: hide.prefab.Curve.CurveKey) {
		width = Math.round(svg.element.width());
		height = Math.round(svg.element.height());
		var root = svg.element;
		svg.clear();
		if(animKey == null) {
			untyped window.gc();
		}

		var graph = svg.group(root, "graph"); //, {transform: 'translate(0, ${height/2})'});
		var background = svg.group(graph, "background");
		// svg.line(background, 0, 0, width, 0).addClass("axis");

		// var gridSteps = Math.ceil(curve.duration);
		// var hgrid = svg.group(root, "hgrid");
		// for(i in 0...gridSteps) {
		//     svg.line(hgrid, xt(i), 0, xt(i), height);
		// }

		var minX = Math.floor(ixt(0));
		var maxX = Math.ceil(ixt(width));
		var hgrid = svg.group(root, "hgrid");
		for(ix in minX...(maxX+1)) {
			var l = svg.line(hgrid, xt(ix), 0, xt(ix), height).attr({
				"shape-rendering": "crispEdges"
			});
			if(ix == 0)
				l.addClass("axis");
		}

		var minY = Math.floor(iyt(0));
		var maxY = Math.ceil(iyt(height));
		var vgrid = svg.group(root, "vgrid");
		for(iy in minY...(maxY+1)) {
			var l = svg.line(vgrid, 0, yt(iy), width, yt(iy)).attr({
				"shape-rendering": "crispEdges"
			});
			if(iy == 0)
				l.addClass("axis");
		}

		var curveGroup = svg.group(root, "curve");
		var vectorsGroup = svg.group(root, "vectors");
		var handlesGroup = svg.group(root, "handles");
		var size = 7;

		for(ik in 0...curve.keys.length-1) {
			var pt = curve.keys[ik];
			var nextPt = curve.keys[ik+1];
			svg.line(curveGroup, xt(pt.time), yt(pt.value), xt(nextPt.time), yt(nextPt.value));
		}


		function addRect(x: Float, y: Float) {
			return svg.rect(handlesGroup, x - Math.floor(size/2), y - Math.floor(size/2), size, size).attr({
				"shape-rendering": "crispEdges"
			});
		}

		for(key in curve.keys) {
			if(animKey != null && key != animKey)
				continue;
			var kx = xt(key.time);
			var ky = yt(key.value);
			function addHandle(handle) {
				if(handle == null) return null;
				var px = xt(key.time + handle.dt);
				var py = yt(key.value + handle.dv);
				svg.line(vectorsGroup, kx, ky, px, py);
				var circle = svg.circle(handlesGroup, px, py, size/2);
				return circle;
			}
			var pHandle = addHandle(key.prevHandle);
			var nHandle = addHandle(key.nextHandle);
			var keyHandle = addRect(kx, ky);

			if(animKey != null)
				continue;
			keyHandle.mousedown(function(e) {
				var startT = key.time;
				var startV = key.value;
				var offx = e.clientX - keyHandle.offset().left;
				var offy = e.clientY - keyHandle.offset().top;
				var offset = svg.element.offset();
				root.mousemove(function(e) {
					var lx = e.clientX - offset.left - offx;
					var ly = e.clientY - offset.top - offy;
					var nkx = ixt(lx);
					var nky = iyt(ly);
					key.time = nkx;
					key.value = nky;
					refresh(key);
					// keyHandle.attr({
					// 	x: lx,
					// 	y: ly});
					// pHandle.attr({
					// 	cx: xt(nkx + key.prevHandle.dt),
					// 	cy: yt(nky + key.prevHandle.dv)});
					// nHandle.attr({
					// 	cx: xt(nkx + key.nextHandle.dt),
					// 	cy: yt(nky + key.nextHandle.dv)});
				});
				root.mouseup(function(e) {
					root.off("mousemove");
					root.off("mouseup");
					refresh();
				});
			});
			pHandle.mousedown(function(e) {
				var startT = key.prevHandle.dt;
				var startV = key.prevHandle.dv;
				var offx = e.clientX - pHandle.offset().left;
				var offy = e.clientY - pHandle.offset().top;
				var offset = svg.element.offset();
				var nhLen = hxd.Math.distance(key.nextHandle.dt * xScale, key.nextHandle.dv * yScale);
				var phLen = hxd.Math.distance(key.prevHandle.dt * xScale, key.prevHandle.dv * yScale);
				root.mousemove(function(e) {
					var lx = e.clientX - offset.left - offx;
					var ly = e.clientY - offset.top - offy;
					var ndt = ixt(lx) - key.time;
					var ndv = iyt(ly) - key.value;
					key.prevHandle.dt = ndt;
					key.prevHandle.dv = ndv;
					var angle = Math.atan2(ly - ky, lx - kx);
					key.nextHandle.dt = Math.cos(angle + Math.PI) * nhLen / xScale;
					key.nextHandle.dv = Math.sin(angle + Math.PI) * nhLen / yScale;
					refresh(key);					
				});
				root.mouseup(function(e) {
					root.off("mousemove");
					root.off("mouseup");
					refresh();
				});
			});
		}
	}
}
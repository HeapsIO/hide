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

	var refreshTimer : haxe.Timer = null;

	public function new(root, curve : hide.prefab.Curve) {
		super(root);
		this.curve = curve;
		svg = new hide.comp.SVG(root);
		var root = svg.element;
		root.resize((e) -> refresh());
		root.addClass("hide-curve-editor");
		root.mousedown(function(e) {
			if(e.which == 2) {
				var lastX = e.clientX;
				var lastY = e.clientY;
				root.mousemove(function(e) {
					var dt = (e.clientX - lastX) / xScale;
					var dv = (e.clientY - lastY) / yScale;
					xOffset += dt;
					yOffset += dv;
					lastX = e.clientX;
					lastY = e.clientY;
					refresh(true);
				});
				root.mouseup(function(e) {
					root.off("mousemove");
					root.off("mouseup");
					refresh();
					e.preventDefault();
					e.stopPropagation();
				});
				e.preventDefault();
				e.stopPropagation();
			}
		});
		root.on("mousewheel", function(e) {
			var step = e.originalEvent.wheelDelta > 0 ? 1.0 : -1.0;
			if(hxd.Key.isDown(hxd.Key.SHIFT))
				yScale *= Math.pow(1.125, step);
			else
				xScale *= Math.pow(1.125, step);
			refresh();
		});
	}

	inline function xt(x: Float) return (x + xOffset) * xScale;
	inline function yt(y: Float) return (y + yOffset) * yScale + height/2;
	inline function ixt(px: Float) return px / xScale - xOffset;
	inline function iyt(py: Float) return (py - height/2) / yScale - yOffset;

	public function refresh(?anim: Bool = false, ?animKey: hide.prefab.Curve.CurveKey) {
		width = Math.round(svg.element.width());
		height = Math.round(svg.element.height());
		var root = svg.element;
		svg.clear();
		if(!anim && animKey == null) {
			if(refreshTimer != null) {
				refreshTimer.stop();
			}
			refreshTimer = haxe.Timer.delay(function() {
				refreshTimer = null;
				untyped window.gc();
			}, 100);
		}

		var graph = svg.group(root, "graph");
		var background = svg.group(graph, "background");

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
			if(anim && (animKey == null || key != animKey))
				continue;
			var kx = xt(key.time);
			var ky = yt(key.value);
			var keyHandle = addRect(kx, ky);
			if(anim || animKey == null) {
				keyHandle.mousedown(function(e) {
					if(e.which != 1) return;
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
						refresh(true, key);
					});
					root.mouseup(function(e) {
						root.off("mousemove");
						root.off("mouseup");
						refresh();
					});
				});
			}
			function addHandle(handle: hide.prefab.Curve.CurveHandle) {
				if(handle == null) return null;
				var px = xt(key.time + handle.dt);
				var py = yt(key.value + handle.dv);
				svg.line(vectorsGroup, kx, ky, px, py);
				var circle = svg.circle(handlesGroup, px, py, size/2);
				if(anim || animKey == null) {
					circle.mousedown(function(e) {
						if(e.which != 1) return;
						var offx = e.clientX - circle.offset().left;
						var offy = e.clientY - circle.offset().top;
						var offset = svg.element.offset();
						var other = handle == key.prevHandle ? key.nextHandle : key.prevHandle;
						var otherLen = hxd.Math.distance(other.dt * xScale, other.dv * yScale);
						root.mousemove(function(e) {
							var lx = e.clientX - offset.left - offx;
							var ly = e.clientY - offset.top - offy;
							var ndt = ixt(lx) - key.time;
							var ndv = iyt(ly) - key.value;
							handle.dt = ndt;
							handle.dv = ndv;
							var angle = Math.atan2(ly - ky, lx - kx);
							other.dt = Math.cos(angle + Math.PI) * otherLen / xScale;
							other.dv = Math.sin(angle + Math.PI) * otherLen / yScale;
							refresh(true, key);					
						});
						root.mouseup(function(e) {
							root.off("mousemove");
							root.off("mouseup");
							refresh();
						});
					});
				}
				return circle;
			}
			var pHandle = addHandle(key.prevHandle);
			var nHandle = addHandle(key.nextHandle);
		}
	}
}
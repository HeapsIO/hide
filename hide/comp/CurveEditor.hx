package hide.comp;

class CurveEditor extends Component {

	public var xScale = 200.;
	public var yScale = 30.;
	public var xOffset = 0.;
	public var yOffset = 0.;

	public var curve : hide.prefab.Curve;
	public var undo : hide.ui.UndoHistory;

	var svg : hide.comp.SVG;
	var width = 0;
	var height = 0;
	var gridGroup : Element;
	var graphGroup : Element;
	var selectGroup : Element;

	var refreshTimer : haxe.Timer = null;

	var selectedKeys: Array<hide.prefab.Curve.CurveKey> = [];

	public function new(parent, curve : hide.prefab.Curve, undo) {
		super(parent);
		this.undo = undo;
		this.curve = curve;
		var div = new Element("<div></div>");
		div.attr({ tabindex: "1" });
		div.css({ width: "100%", height: "100%" });

		div.appendTo(parent);
		div.focus();
		svg = new hide.comp.SVG(div);
		var root = svg.element;
		//root.attr("tabindex", "1");

		gridGroup = svg.group(root, "grid");
		graphGroup = svg.group(root, "graph");
		selectGroup = svg.group(root, "selection-overlay");

		root.resize((e) -> refresh());
		root.addClass("hide-curve-editor");
		root.mousedown(function(e) {
			var offset = root.offset();
			var px = e.clientX - offset.left;
			var py = e.clientY - offset.top;
			e.preventDefault();
			e.stopPropagation();
			div.focus();
			if(e.which == 1) {
				if(e.ctrlKey) {
					addPoint(ixt(px), iyt(py));
				}
				else {
					startSelectRect(px, py);
				}
			}
			else if(e.which == 2) {
				// Pan
				startPan(e);
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
		div.keydown(function(e) {
			if(e.keyCode == 46) {
				var backup = curve.keys.copy();
				var selBackup = selectedKeys.copy();
				var newVal = [for(k in curve.keys) if(selectedKeys.indexOf(k) < 0) k];
				curve.keys = newVal;
				selectedKeys = [];
				refresh();
				e.preventDefault();
				e.stopPropagation();
				undo.change(Custom(function(undo) {
					if(undo) {
						curve.keys = backup;
						selectedKeys = selBackup;
					}
					else {
						curve.keys = newVal;
						selectedKeys = [];
					}
					refresh();
				}));
			}
		});
	}

	function addPoint(time: Float, ?val: Float) {
		var index = 0;
		for(ik in 0...curve.keys.length) {
			var key = curve.keys[ik];
			if(time > key.time)
				index = ik + 1;
		}

		if(val == null)
			val = curve.getVal(time);

		var prev = curve.keys[index-1];
		var next = curve.keys[index];

		var key : hide.prefab.Curve.CurveKey = {
			time: time,
			value: val,
			prevHandle: { dt : prev != null ? (prev.time - time) / 4 : -0.5, dv : 0. },
			nextHandle: { dt : next != null ? (next.time - time) / 4 : 0.5, dv : 0. },
		};
		curve.keys.insert(index, key);
		refresh();
	}

	function startSelectRect(p1x: Float, p1y: Float) {
		var offset = root.offset();
		var selX = p1x;
		var selY = p1y;
		var selW = 0.;
		var selH = 0.;
		startDrag(root, function(e) {
			var p2x = e.clientX - offset.left;
			var p2y = e.clientY - offset.top;
			selX = hxd.Math.min(p1x, p2x);
			selY = hxd.Math.min(p1y, p2y);
			selW = hxd.Math.abs(p2x-p1x);
			selH = hxd.Math.abs(p2y-p1y);
			selectGroup.empty();
			svg.rect(selectGroup, selX, selY, selW, selH);
		}, function(e) {
			selectGroup.empty();
			var minT = ixt(selX);
			var minV = iyt(selY);
			var maxT = ixt(selX + selW);
			var maxV = iyt(selY + selH);
			selectedKeys = [for(key in curve.keys)
				if(key.time >= minT && key.time <= maxT && key.value >= minV && key.value <= maxV) key];
			refresh();
		});
	}

	function startPan(e) {
		var lastX = e.clientX;
		var lastY = e.clientY;
		startDrag(root, function(e) {
			var dt = (e.clientX - lastX) / xScale;
			var dv = (e.clientY - lastY) / yScale;
			xOffset += dt;
			yOffset += dv;
			lastX = e.clientX;
			lastY = e.clientY;
			refresh(true);
		}, function(e) {
			refresh();
		});
	}

	inline function xt(x: Float) return (x + xOffset) * xScale;
	inline function yt(y: Float) return (y + yOffset) * yScale + height/2;
	inline function ixt(px: Float) return px / xScale - xOffset;
	inline function iyt(py: Float) return (py - height/2) / yScale - yOffset;

	public function startDrag(el: Element, onMove, onStop) {
		el.mousemove(onMove);
		el.mouseup(function(e) {
			el.off("mousemove");
			el.off("mouseup");
			e.preventDefault();
			e.stopPropagation();
			onStop(e);
		});
	}

	function copyKey(key: hide.prefab.Curve.CurveKey): hide.prefab.Curve.CurveKey {
		return cast haxe.Json.parse(haxe.Json.stringify(key));
	}

	function addUndo(key: hide.prefab.Curve.CurveKey, prev : hide.prefab.Curve.CurveKey) {
		var idx = curve.keys.indexOf(key);
		var newVal = copyKey(key);
		undo.change(Custom(function(undo) {
			if(undo) {
				curve.keys[idx] = prev;
			}
			else {
				curve.keys[idx] = newVal;
			}
			selectedKeys = [];
			refresh();
		}));
	}

	public function refresh(?anim: Bool = false, ?animKey: hide.prefab.Curve.CurveKey) {
		width = Math.round(svg.element.width());
		height = Math.round(svg.element.height());
		gridGroup.empty();
		graphGroup.empty();
		selectGroup.empty();

		if(refreshTimer != null)
			refreshTimer.stop();
		if(!anim) {
			refreshTimer = haxe.Timer.delay(function() {
				refreshTimer = null;
				untyped window.gc();
			}, 100);
		}

		var minX = Math.floor(ixt(0));
		var maxX = Math.ceil(ixt(width));
		var hgrid = svg.group(gridGroup, "hgrid");
		for(ix in minX...(maxX+1)) {
			var l = svg.line(hgrid, xt(ix), 0, xt(ix), height).attr({
				"shape-rendering": "crispEdges"
			});
			if(ix == 0)
				l.addClass("axis");
		}

		var minY = Math.floor(iyt(0));
		var maxY = Math.ceil(iyt(height));
		var vgrid = svg.group(gridGroup, "vgrid");
		for(iy in minY...(maxY+1)) {
			var l = svg.line(vgrid, 0, yt(iy), width, yt(iy)).attr({
				"shape-rendering": "crispEdges"
			});
			if(iy == 0)
				l.addClass("axis");
		}


		var curveGroup = svg.group(graphGroup, "curve");
		var vectorsGroup = svg.group(graphGroup, "vectors");
		var handlesGroup = svg.group(graphGroup, "handles");
		var selection = svg.group(graphGroup, "selection");
		var size = 7;

		// Draw curve
		{
			var keys = curve.keys;
			var lines = ['M ${xt(keys[0].time)},${yt(keys[0].value)}'];
			for(ik in 1...keys.length) {
				var prev = keys[ik-1];
				var cur = keys[ik];
				lines.push('C ${xt(prev.time + prev.nextHandle.dt)}, ${yt(prev.value + prev.nextHandle.dv)}
					${xt(cur.time + cur.prevHandle.dt)}, ${yt(cur.value + cur.prevHandle.dv)}
					${xt(cur.time)}, ${yt(cur.value)} ');
			}
			svg.make(curveGroup, "path", {d: lines.join("")});
		}


		function addRect(x: Float, y: Float) {
			return svg.rect(handlesGroup, x - Math.floor(size/2), y - Math.floor(size/2), size, size).attr({
				"shape-rendering": "crispEdges"
			});
		}

		for(key in curve.keys) {
			var kx = xt(key.time);
			var ky = yt(key.value);
			var keyHandle = addRect(kx, ky);
			if(selectedKeys.indexOf(key) >= 0) {
				keyHandle.addClass("selected");
			}
			if(!anim) {
				keyHandle.mousedown(function(e) {
					if(e.which != 1) return;
					var backup = copyKey(key);
					e.preventDefault();
					e.stopPropagation();
					var offx = e.clientX - keyHandle.offset().left;
					var offy = e.clientY - keyHandle.offset().top;
					var offset = svg.element.offset();
					startDrag(root, function(e) {
						var lx = e.clientX - offset.left - offx;
						var ly = e.clientY - offset.top - offy;
						var nkx = ixt(lx);
						var nky = iyt(ly);
						key.time = nkx;
						key.value = nky;
						refresh(true, key);
					}, function(e) {
						selectedKeys = [key];
						refresh();
						addUndo(key, backup);
					});
					selectedKeys = [key];
					refresh();
				});
			}
			function addHandle(next: Bool) {
				var handle = next ? key.nextHandle : key.prevHandle;
				var other = next ? key.prevHandle : key.nextHandle;
				if(handle == null) return null;
				var px = xt(key.time + handle.dt);
				var py = yt(key.value + handle.dv);
				svg.line(vectorsGroup, kx, ky, px, py);
				var circle = svg.circle(handlesGroup, px, py, size/2);
				if(anim)
					return circle;
				circle.mousedown(function(e) {
					if(e.which != 1) return;
					e.preventDefault();
					e.stopPropagation();
					var backup = copyKey(key);
					var offx = e.clientX - circle.offset().left;
					var offy = e.clientY - circle.offset().top;
					var offset = svg.element.offset();
					var otherLen = hxd.Math.distance(other.dt * xScale, other.dv * yScale);
					startDrag(root, function(e) {
						var lx = e.clientX - offset.left - offx;
						var ly = e.clientY - offset.top - offy;
						if(next && lx < kx || !next && lx > kx)
							lx = kx;
						var ndt = ixt(lx) - key.time;
						var ndv = iyt(ly) - key.value;
						handle.dt = ndt;
						handle.dv = ndv;
						var angle = Math.atan2(ly - ky, lx - kx);
						other.dt = Math.cos(angle + Math.PI) * otherLen / xScale;
						other.dv = Math.sin(angle + Math.PI) * otherLen / yScale;
						refresh(true, key);
					}, function(e) {
						refresh();
						addUndo(key, backup);
					});
				});
				return circle;
			}
			if(!anim || animKey == key) {
				var pHandle = addHandle(false);
				var nHandle = addHandle(true);
			}
		}

		if(selectedKeys.length > 1) {
			var bounds = new h2d.col.Bounds();
			for(key in selectedKeys)
				bounds.addPoint(new h2d.col.Point(xt(key.time), yt(key.value)));
			var margin = 12.5;
			bounds.xMin -= margin;
			bounds.yMin -= margin;
			bounds.xMax += margin;
			bounds.yMax += margin;
			var rect = svg.rect(selection, bounds.x, bounds.y, bounds.width, bounds.height).attr({
				"shape-rendering": "crispEdges"
			});
			if(!anim) {
				rect.mousedown(function(e) {
					if(e.which != 1) return;
					e.preventDefault();
					e.stopPropagation();
					// var offx = e.clientX - rect.offset().left;
					// var offy = e.clientY - rect.offset().top;
					var selection = selectedKeys.copy();
					var backup = [for(k in selection) { idx: curve.keys.indexOf(k), val: Reflect.copy(k) }];
					var lastX = e.clientX;
					var lastY = e.clientY;
					var offset = svg.element.offset();
					startDrag(root, function(e) {
						var dx = e.clientX - lastX;
						var dy = e.clientY - lastY;
						for(key in selectedKeys) {
							key.time += dx / xScale;
							key.value += dy / yScale;
						}
						lastX = e.clientX;
						lastY = e.clientY;
						// var lx = e.clientX - offset.left - offx;
						// var ly = e.clientY - offset.top - offy;
						// var nkx = ixt(lx);
						// var nky = iyt(ly);
						// key.time = nkx;
						// key.value = nky;
						refresh(true);
					}, function(e) {
						refresh();
						var newVals = selection.copy();
						undo.change(Custom(function(undo) {
							if(undo) {
								for(b in backup) {
									var k = curve.keys[b.idx];
									k.time = b.val.time;
									k.value = b.val.value;
								}
							}
							else {
								for(b in backup) {
									var k = curve.keys[b.idx];
									k.time = newVals[b.idx].time;
									k.value = newVals[b.idx].value;
								}
							}
							refresh();
						}));
					});
					refresh();
				});
			}
		}
	}
}
package hide.comp;

typedef CurveKey = hide.prefab.Curve.CurveKey;

class CurveEditor extends Component {

	public var xScale = 200.;
	public var yScale = 30.;
	public var xOffset = 0.;
	public var yOffset = 0.;

	public var curve(default, set) : hide.prefab.Curve;
	public var undo : hide.ui.UndoHistory;

	public var lockViewX = false;
	public var lockViewY = false;

	var svg : hide.comp.SVG;
	var width = 0;
	var height = 0;
	var gridGroup : Element;
	var graphGroup : Element;
	var selectGroup : Element;

	var refreshTimer : haxe.Timer = null;
	var lastValue : Dynamic;
	var lastMode : hide.prefab.Curve.CurveKeyMode = Constant;

	var selectedKeys: Array<CurveKey> = [];

	public function new(undo, ?parent) {
		super(parent,null);
		this.undo = undo;
		element.addClass("hide-curve-editor");
		element.attr({ tabindex: "1" });
		element.css({ width: "100%", height: "100%" });
		element.focus();
		svg = new hide.comp.SVG(element);
		var div = this.element;
		var root = svg.element;
		height = Math.round(svg.element.height());
		if(height == 0 && parent != null)
			height = Math.round(parent.height());
		width = Math.round(svg.element.width());

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
					addKey(ixt(px), iyt(py));
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
		element.keydown(function(e) {
			if(e.key == "z") {
				zoomAll();
				refresh();
			}
		});
		root.contextmenu(function(e) {
			e.preventDefault();
			return false;
		});
		root.on("mousewheel", function(e : js.jquery.Event) {
			var step = (e:Dynamic).originalEvent.wheelDelta > 0 ? 1.0 : -1.0;
			var changed = false;
			if(e.shiftKey) {
				if(!lockViewY) {
					yScale *= Math.pow(1.125, step);
					changed = true;
				}
			}
			else {
				if(!lockViewX) {
					xScale *= Math.pow(1.125, step);
					changed = true;
				}
			}
			if(changed) {
				e.preventDefault();
				e.stopPropagation();
				refresh();
			}
		});
		div.keydown(function(e) {
			if(curve == null) return;
			if(e.keyCode == 46) {
				beforeChange();				
				var newVal = [for(k in curve.keys) if(selectedKeys.indexOf(k) < 0) k];
				curve.keys = newVal;
				selectedKeys = [];
				e.preventDefault();
				e.stopPropagation();
				afterChange();
			}
			if(e.key == "z") {
				zoomAll();
			}
		});
	}

	public dynamic function onChange(anim: Bool) {

	}

	public dynamic function onKeyMove(key: CurveKey, prevTime: Float, prevVal: Float) {

	}

	function set_curve(curve: hide.prefab.Curve) {
		this.curve = curve;
		lastValue = haxe.Json.parse(haxe.Json.stringify(curve.save()));
		var view = getDisplayState("view");
		if(view != null) {
			if(!lockViewX) {
				xOffset = view.xOffset;
				xScale = view.xScale;
			}
			if(!lockViewY) {
				yOffset = view.yOffset;
				yScale = view.yScale;
			}
		}
		else {
			zoomAll();
		}
		refresh();
		return curve;
	}

	function addKey(time: Float, ?val: Float) {
		beforeChange();		
		if(curve.clampMin != curve.clampMax)
			val = hxd.Math.clamp(val, curve.clampMin, curve.clampMax);
		curve.addKey(time, val);
		afterChange();
	}

	function fixKey(key : CurveKey) {
		var index = curve.keys.indexOf(key);
		var prev = curve.keys[index-1];
		var next = curve.keys[index+1];

		inline function addPrevH() {
			if(key.prevHandle == null)
				key.prevHandle = { dt: prev != null ? (prev.time - key.time) / 3 : -0.5, dv: 0};
		}
		inline function addNextH() {
			if(key.nextHandle == null)
				key.nextHandle = { dt: next != null ? (next.time - key.time) / 3 : -0.5, dv: 0};
		}
		switch(key.mode) {
			case Aligned:
				addPrevH();
				addNextH();
				var pa = hxd.Math.atan2(key.prevHandle.dv, key.prevHandle.dt);
				var na = hxd.Math.atan2(key.nextHandle.dv, key.nextHandle.dt);
				if(hxd.Math.abs(hxd.Math.angle(pa - na)) < Math.PI - (1./180.)) {
					key.nextHandle.dt = -key.prevHandle.dt;
					key.nextHandle.dv = -key.prevHandle.dv;
				}
			case Free:
				addPrevH();
				addNextH();
			case Linear:
				key.nextHandle = null;
				key.prevHandle = null;
			case Constant:
				key.nextHandle = null;
				key.prevHandle = null;
		}

		if(key.time < 0)
			key.time = 0;

		if(prev != null && key.time < prev.time)
			key.time = prev.time + 0.01;
		if(next != null && key.time > next.time)
			key.time = next.time - 0.01;

		if(curve.clampMin != curve.clampMax) {
			key.value = hxd.Math.clamp(key.value, curve.clampMin, curve.clampMax);
		}

		if(false) {
			// TODO: This sorta works but is annoying.
			// Doesn't yet prevent backwards handles
			if(next != null && key.nextHandle != null) {
				var slope = key.nextHandle.dv / key.nextHandle.dt;
				slope = hxd.Math.clamp(slope, -1000, 1000);
				if(key.nextHandle.dt + key.time > next.time) {
					key.nextHandle.dt = next.time - key.time;
					key.nextHandle.dv = slope * key.nextHandle.dt;
				}
			}
			if(prev != null && key.prevHandle != null) {
				var slope = key.prevHandle.dv / key.prevHandle.dt;
				slope = hxd.Math.clamp(slope, -1000, 1000);
				if(key.prevHandle.dt + key.time < prev.time) {
					key.prevHandle.dt = prev.time - key.time;
					key.prevHandle.dv = slope * key.prevHandle.dt;
				}
			}
		}
	}

	function startSelectRect(p1x: Float, p1y: Float) {
		var offset = element.offset();
		var selX = p1x;
		var selY = p1y;
		var selW = 0.;
		var selH = 0.;
		startDrag(function(e) {
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
			var minV = iyt(selY + selH);
			var maxT = ixt(selX + selW);
			var maxV = iyt(selY);
			selectedKeys = [for(key in curve.keys)
				if(key.time >= minT && key.time <= maxT && key.value >= minV && key.value <= maxV) key];
			refreshGraph();
		});
	}

	function saveView() {
		saveDisplayState("view", {
			xOffset: xOffset,
			yOffset: yOffset,
			xScale: xScale,
			yScale: yScale
		});
	}

	function startPan(e) {
		var lastX = e.clientX;
		var lastY = e.clientY;
		startDrag(function(e) {
			var dt = (e.clientX - lastX) / xScale;
			var dv = (e.clientY - lastY) / yScale;
			if(!lockViewX)
				xOffset -= dt;
			if(!lockViewY)
				yOffset += dv;
			lastX = e.clientX;
			lastY = e.clientY;
			setPan(xOffset, yOffset);
		}, function(e) {
			saveView();
		});
	}

	public function setPan(xoff, yoff) {
		xOffset = xoff;
		yOffset = yoff;
		refreshGrid();
		graphGroup.attr({transform: 'translate(${xt(0)},${yt(0)})'});
	}

	public function setYZoom(yMin: Float, yMax: Float) {
		var margin = 20;
		yScale = (height - margin*2) / (yMax - yMin);
		yOffset = (yMax + yMin) / 2.0;
	}

	public function setXZoom(xMin: Float, xMax: Float) {
		var margin = 20;
		xScale = (width - margin*2) / (xMax - xMin);
		xOffset = xMin;
	}

	public function zoomAll() {
		var bounds = curve.getBounds();
		if(bounds.width <= 0) {
			bounds.xMin = 0.0;
			bounds.xMax = 1.0;
		}
		if(bounds.height <= 0) {
			if(curve.clampMax != curve.clampMin) {
				bounds.yMin = curve.clampMin;
				bounds.yMax = curve.clampMax;
			}
			else {
				bounds.yMin = -1.0;
				bounds.yMax = 1.0;
			}
		}
		if(!lockViewY) {
			setYZoom(bounds.yMin, bounds.yMax);
		}
		if(!lockViewX) {
			setYZoom(bounds.xMax, bounds.xMax);
		}
		saveView();
	}

	inline function xt(x: Float) return Math.round((x - xOffset) * xScale);
	inline function yt(y: Float) return Math.round((-y + yOffset) * yScale + height/2);
	inline function ixt(px: Float) return px / xScale + xOffset;
	inline function iyt(py: Float) return -(py - height/2) / yScale + yOffset;

	function startDrag(onMove: js.jquery.Event->Void, onStop: js.jquery.Event->Void) {
		var el = new Element(element[0].ownerDocument.body);
		el.on("mousemove.curveeditor", onMove);
		el.on("mouseup.curveeditor", function(e: js.jquery.Event) {
			el.off("mousemove.curveeditor");
			el.off("mouseup.curveeditor");
			e.preventDefault();
			e.stopPropagation();
			onStop(e);
		});
	}

	function copyKey(key: CurveKey): CurveKey {
		return cast haxe.Json.parse(haxe.Json.stringify(key));
	}

	function beforeChange() {
		lastValue = haxe.Json.parse(haxe.Json.stringify(curve.save()));
	}

	function afterChange() {
		var newVal = haxe.Json.parse(haxe.Json.stringify(curve.save()));
		var oldVal = lastValue;
		undo.change(Custom(function(undo) {
			if(undo) {
				curve.load(oldVal);
			}
			else {
				curve.load(newVal);
			}
			lastValue = haxe.Json.parse(haxe.Json.stringify(curve.save()));
			selectedKeys = [];
			refresh();
			onChange(false);
		}));
		refresh();
		onChange(false);
	}

	public function refresh(?anim: Bool) {
		if(false) {
			// Auto-gc
			if(refreshTimer != null)
				refreshTimer.stop();
			if(!anim) {
				refreshTimer = haxe.Timer.delay(function() {
					refreshTimer = null;
					untyped window.gc();
				}, 500);
			}
		}

		refreshGrid();
		refreshGraph(anim);
	}

	public function refreshGrid() {
		width = Math.round(svg.element.width());
		height = Math.round(svg.element.height());

		gridGroup.empty();
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

		var minY = Math.floor(iyt(height));
		var maxY = Math.ceil(iyt(0));
		var vgrid = svg.group(gridGroup, "vgrid");
		var vstep = 1;
		while((maxY - minY) / vstep > 10)
			vstep *= 10;

		inline function hline(iy) {
			return svg.line(vgrid, 0, yt(iy), width, yt(iy)).attr({
				"shape-rendering": "crispEdges"
			});
		}

		inline function hlabel(str, iy) {
			svg.text(vgrid, 1, yt(iy), str);
		}

		var minS = Math.floor(minY / vstep);
		var maxS = Math.ceil(maxY / vstep);
		for(i in minS...(maxS+1)) {
			var iy = i * vstep;
			var l = hline(iy);
			if(iy == 0)
				l.addClass("axis");	
			hlabel("" + iy, iy);
		}
	}

	public function refreshGraph(?anim: Bool = false, ?animKey: CurveKey) {
		if(curve == null)
			return;

		graphGroup.empty();
		var graphOffX = xt(0);
		var graphOffY = yt(0);
		graphGroup.attr({transform: 'translate($graphOffX, $graphOffY)'});

		var curveGroup = svg.group(graphGroup, "curve");
		var vectorsGroup = svg.group(graphGroup, "vectors");
		var handlesGroup = svg.group(graphGroup, "handles");
		var tangentsHandles = svg.group(handlesGroup, "tangents");
		var keyHandles = svg.group(handlesGroup, "keys");
		var selection = svg.group(graphGroup, "selection");
		var size = 7;

		// Draw curve
		if(curve.keys.length > 0) {
			var keys = curve.keys;
			var lines = ['M ${xScale*(keys[0].time)},${-yScale*(keys[0].value)}'];
			for(ik in 1...keys.length) {
				var prev = keys[ik-1];
				var cur = keys[ik];
				if(prev.mode == Constant) {
					lines.push('L ${xScale*(prev.time)} ${-yScale*(prev.value)}
					L ${xScale*(cur.time)} ${-yScale*(prev.value)}
					L ${xScale*(cur.time)} ${-yScale*(cur.value)}');
				}
				else {
					lines.push('C
						${xScale*(prev.time + (prev.nextHandle != null ? prev.nextHandle.dt : 0.))},${-yScale*(prev.value + (prev.nextHandle != null ? prev.nextHandle.dv : 0.))}
						${xScale*(cur.time + (cur.prevHandle != null ? cur.prevHandle.dt : 0.))}, ${-yScale*(cur.value + (cur.prevHandle != null ? cur.prevHandle.dv : 0.))}
						${xScale*(cur.time)}, ${-yScale*(cur.value)} ');
				}
			}
			svg.make(curveGroup, "path", {d: lines.join("")});
			// var pts = curve.sample(200);
			// var poly = [];
			// for(i in 0...pts.length) {
			// 	var x = xScale * (curve.duration * i / (pts.length - 1));
			// 	var y = yScale * (pts[i]);
			// 	poly.push(new h2d.col.Point(x, y));
			// }
			// svg.polygon(curveGroup, poly);
		}


		function addRect(group, x: Float, y: Float) {
			return svg.rect(group, x - Math.floor(size/2), y - Math.floor(size/2), size, size).attr({
				"shape-rendering": "crispEdges"
			});
		}

		for(key in curve.keys) {
			var kx = xScale*(key.time);
			var ky = -yScale*(key.value);
			var keyHandle = addRect(keyHandles, kx, ky);
			var selected = selectedKeys.indexOf(key) >= 0;
			if(selected)
				keyHandle.addClass("selected");
			if(!anim) {
				keyHandle.mousedown(function(e) {
					if(e.which != 1) return;
					e.preventDefault();
					e.stopPropagation();
					var offset = element.offset();
					beforeChange();
					startDrag(function(e) {
						var lx = e.clientX - offset.left;
						var ly = e.clientY - offset.top;
						var nkx = ixt(lx);
						var nky = iyt(ly);
						var prevTime = key.time;
						var prevVal = key.value;
						key.time = nkx;
						key.value = nky;
						fixKey(key);
						refreshGraph(true, key);
						onKeyMove(key, prevTime, prevVal);
						onChange(true);
					}, function(e) {
						selectedKeys = [key];
						fixKey(key);
						afterChange();
					});
					selectedKeys = [key];
					refreshGraph();
				});
				keyHandle.contextmenu(function(e) {
					e.preventDefault();
					function setMode(m: hide.prefab.Curve.CurveKeyMode) {
						key.mode = m;
						lastMode = m;
						fixKey(key);
						refreshGraph();
					}
					new ContextMenu([
						{ label : "Mode", menu :[
							{ label : "Aligned", checked: key.mode == Aligned, click : setMode.bind(Aligned) },
							{ label : "Free", checked: key.mode == Free, click : setMode.bind(Free) },
							{ label : "Linear", checked: key.mode == Linear, click : setMode.bind(Linear) },
							{ label : "Constant", checked: key.mode == Constant, click : setMode.bind(Constant) },
						] }
					]);
					return false;
				});
			}
			function addHandle(next: Bool) {
				var handle = next ? key.nextHandle : key.prevHandle;
				var other = next ? key.prevHandle : key.nextHandle;
				if(handle == null) return null;
				var px = xScale*(key.time + handle.dt);
				var py = -yScale*(key.value + handle.dv);
				var line = svg.line(vectorsGroup, kx, ky, px, py);
				var circle = svg.circle(tangentsHandles, px, py, size/2);
				if(selected) {
					line.addClass("selected");
					circle.addClass("selected");
				}
				if(anim)
					return circle;
				circle.mousedown(function(e) {
					if(e.which != 1) return;
					e.preventDefault();
					e.stopPropagation();
					var offset = element.offset();
					var otherLen = hxd.Math.distance(other.dt * xScale, other.dv * yScale);
					beforeChange();
					startDrag(function(e) {
						var lx = e.clientX - offset.left;
						var ly = e.clientY - offset.top;
						var abskx = xt(key.time);
						var absky = yt(key.value);
						if(next && lx < abskx || !next && lx > abskx)
						 	lx = kx;
						var ndt = ixt(lx) - key.time;
						var ndv = iyt(ly) - key.value;
						handle.dt = ndt;
						handle.dv = ndv;
						if(key.mode == Aligned) {
							var angle = Math.atan2(absky - ly, lx - abskx);
							other.dt = Math.cos(angle + Math.PI) * otherLen / xScale;
							other.dv = Math.sin(angle + Math.PI) * otherLen / yScale;
						}
						fixKey(key);
						refreshGraph(true, key);
						onChange(true);
					}, function(e) {
						afterChange();
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
				bounds.addPoint(new h2d.col.Point(xScale*(key.time), -yScale*(key.value)));
			var margin = 12.5;
			bounds.xMin -= margin;
			bounds.yMin -= margin;
			bounds.xMax += margin;
			bounds.yMax += margin;
			var rect = svg.rect(selection, bounds.x, bounds.y, bounds.width, bounds.height).attr({
				"shape-rendering": "crispEdges"
			});
			if(!anim) {
				beforeChange();
				rect.mousedown(function(e) {
					if(e.which != 1) return;
					e.preventDefault();
					e.stopPropagation();
					var lastX = e.clientX;
					var lastY = e.clientY;
					startDrag(function(e) {
						var dx = e.clientX - lastX;
						var dy = e.clientY - lastY;
						for(key in selectedKeys) {
							key.time += dx / xScale;
							key.value -= dy / yScale;
						}
						lastX = e.clientX;
						lastY = e.clientY;
						refreshGraph(true);
						onChange(true);
					}, function(e) {
						afterChange();
					});
					refreshGraph();
				});
			}
		}
	}
}
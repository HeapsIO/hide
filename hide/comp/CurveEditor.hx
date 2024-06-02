package hide.comp;

import hrt.prefab.Curve;

typedef CurveKey = hrt.prefab.Curve.CurveKey;

interface CurveEditorComponent {
	function refresh(?anim: Bool = false): Void;
	function setPan(): Void;
	function onSelectionEnd(minT: Float, minV: Float, maxT: Float, MaxV: Float):Void;
	function beforeChange(): Void;
	function afterChange() : Void;
}

class EventsEditor extends Component implements CurveEditorComponent
{
	public var fxEditor : hide.view.FXEditor;
	public var curveEditor : CurveEditor;
	public var events : Array<hrt.prefab.fx.Event.IEvent> = [];

	var lastValue : Array<Float>;
	var svg : SVG;
	var eventGroup: Element;

	public function new(?parent, fxEditor: hide.view.FXEditor, curveEditor: CurveEditor) {
		super(parent, null);

		this.fxEditor = fxEditor;
		this.curveEditor = curveEditor;
		this.curveEditor.components.push(this);

		svg = @:privateAccess this.curveEditor.svg;
	}

	public function setPan() { }

	public function refreshOverview() {
		refresh(false);
	}

	public function refresh(?anim:Bool = false) {
		if (eventGroup != null)
			eventGroup.empty();

		eventGroup = svg.group(@:privateAccess this.curveEditor.graphGroup, "events");

		var eventCount = 0;

		function drawEvent(event:hrt.prefab.fx.Event.IEvent, eventCount: Int, ?style: Dynamic) {
			var yOrigin = 20;
			var eventHeight = 18;
			var spacing = 2;
			var fontSize = 12;

			if (@:privateAccess fxEditor.sceneEditor.curEdit == null)
				return;

			var infos = event.getDisplayInfo(@:privateAccess fxEditor.sceneEditor.curEdit);
			var element = event.getEventPrefab();

			var yPos = yOrigin + (eventHeight + spacing) * eventCount;
			var evtBody = svg.rect(eventGroup, event.time * this.curveEditor.xScale, yPos, ((infos.length == 0 || infos.loop) ? 5000.0 : infos.length)  * this.curveEditor.xScale, eventHeight, style);
			var evtLabel = svg.text(eventGroup, event.time * this.curveEditor.xScale + 5, yPos + fontSize, infos.label, { 'font-size':fontSize});

			evtBody.addClass("event");
			evtBody.addClass(element.type);

			evtBody.click(function(e) {
				@:privateAccess this.fxEditor.sceneEditor.showProps(element);
			});

			evtBody.contextmenu(function(e) {
				if (event.lock || event.hidden)
					return;

				e.preventDefault();
				e.stopPropagation();
				new hide.comp.ContextMenu([
					{
						label: "Delete", click: function() {
							events.remove(event);
							@:privateAccess fxEditor.sceneEditor.deleteElements([element], refreshOverview);
						}
					}
				]);
			});

			evtBody.mousedown(function(e) {
				if (event.lock || event.hidden)
					return;

				var offsetX = e.clientX - @:privateAccess this.curveEditor.xt(event.time);
				e.preventDefault();
				e.stopPropagation();
				if(e.button == 2) {
				}
				else {
					var prevVal = event.time;
					@:privateAccess fxEditor.startDrag(function(e) {
						var x = @:privateAccess this.curveEditor.ixt(e.clientX - offsetX);
						x = hxd.Math.max(0, x);
						x = untyped parseFloat(x.toFixed(5));
						event.time = x;
						refresh();
					}, function(e) {
						this.curveEditor.undo.change(Field(event, "time", prevVal), refreshOverview);
					});
				}
			});
		}

		var isSquareRect = svg.element.find(".selection").children().length > 0;
		for (event in events) {
			var style = { 'stroke-width':'1px', 'opacity':'0.7', 'stroke':'black', 'cursor': isSquareRect ? 'default' : 'pointer', 'pointer-events': isSquareRect ? 'none':'all'};

			if (event.lock)
				style = { 'stroke-width':'1px', 'opacity':'0.2', 'stroke':'black', 'cursor': isSquareRect ? 'default' : 'pointer', 'stroke-dasharray': '5, 3', 'pointer-events': isSquareRect ? 'none':'all' };

			if (event.selected)
				style = { 'stroke-width':'1px', 'opacity':'1', 'stroke':'#d59320', 'cursor': isSquareRect ? 'default' : 'pointer', 'pointer-events': isSquareRect ? 'none':'all'};

			if (event.hidden)
				continue;

			drawEvent(event, eventCount++, style);
		}
	}

	public function onSelectionEnd(minT:Float, minV:Float, maxT:Float, maxV:Float) {
		var yOrigin = -20;
		var eventHeight = 18;
		var spacing = 2;
		var idx = 0;

		for (evt in events) {
			var infos = evt.getDisplayInfo(@:privateAccess fxEditor.sceneEditor.curEdit);
			evt.selected = false;

			if (evt.hidden || evt.lock) {
				idx++;
				continue;
			}

			var yScale = @:privateAccess this.curveEditor.yScale;

			var y1 = (yOrigin / yScale - ((eventHeight - spacing) * idx) / yScale);
			var y2 = y1 - eventHeight / yScale;
			var x1 = evt.time;
			var x2 = x1 + (infos.length == 0 ? 5000 : infos.length);
			var a = new h2d.col.Point(x1, y1);
			var b = new h2d.col.Point(x2, y1);
			var c = new h2d.col.Point(x1, y2);
			var d = new h2d.col.Point(x2, y2);

			var eventRect: h2d.col.Bounds = new h2d.col.Bounds();
			eventRect.addPoint(a);
			eventRect.addPoint(b);
			eventRect.addPoint(c);
			eventRect.addPoint(d);

			var selection: h2d.col.Bounds = new h2d.col.Bounds();
			selection.addPoint(new h2d.col.Point(minT, maxV));
			selection.addPoint(new h2d.col.Point(maxT, maxV));
			selection.addPoint(new h2d.col.Point(minT, minV));
			selection.addPoint(new h2d.col.Point(maxT, minV));

			if(eventRect.collideBounds(selection)) {
				evt.selected = true;
				@:privateAccess this.curveEditor.selectedElements.push({ event:evt, pos:idx, length:infos.length});
			}

			idx++;
		}
	}

	public function beforeChange() {
		lastValue = [for (e in events) e.time ];
	}

	public function afterChange() {
		var newVal = [for (e in events) e.time ];
		var oldVal = lastValue;
		@:privateAccess this.curveEditor.undo.change(Custom(function(undo) {
			if(undo) {
				for (i in 0...events.length)
					events[i].time = oldVal[i];
			}
			else {
				for (i in 0...events.length)
					events[i].time = newVal[i];
			}

			lastValue = [for (e in events) e.time ];
			refresh();
		}));
		refresh();
	}
}

class OverviewEditor extends Component implements CurveEditorComponent
{
	public var curveEditor : CurveEditor;

	var svg : SVG;
	var overviewGroup: Element;
	var overviewKeys: Element;
	var overviewSelection: Element;

	public function new(?parent, curveEditor: CurveEditor) {
		super(parent, null);

		this.curveEditor = curveEditor;
		this.curveEditor.components.push(this);

		svg = @:privateAccess this.curveEditor.svg;
	}

	function startSelectRect(p1x: Float, p1y: Float) {
		var offset = svg.element.offset();
		var selX = p1x;
		var selY = p1y;
		var selW = 0.;
		var selH = 0.;

		@:privateAccess this.curveEditor.startDrag(function(e) {
			var p2x = e.clientX - offset.left;
			var p2y = e.clientY - offset.top;
			selX = hxd.Math.min(p1x, p2x);
			selY = hxd.Math.min(p1y, p2y);
			selW = hxd.Math.abs(p2x-p1x);
			selH = hxd.Math.abs(p2y-p1y);

			overviewSelection.empty();
			overviewSelection.attr({transform: 'translate(0, 0)'});

			svg.rect(overviewSelection, selX, selY, selW, selH);
		}, function(e) {
			overviewSelection.empty();
			var minT = @:privateAccess this.curveEditor.ixt(selX);
			var maxT = @:privateAccess this.curveEditor.ixt(selX + selW);

			@:privateAccess this.curveEditor.selectedElements = [];
			for (c in this.curveEditor.curves){
				c.selected = false;

				if (c.hidden || c.lock || c.blendMode == CurveBlendMode.Blend || c.blendMode == CurveBlendMode.RandomBlend)
					continue;

				for (key in c.keys) {
					if(key.time >= minT && key.time <= maxT) {
						c.selected = true;
						@:privateAccess this.curveEditor.selectedElements.push(key);
					}
				}
			}

			this.curveEditor.refresh();
		});
	}

	public function setPan() {
		if (overviewKeys != null)
			overviewKeys.attr({transform: 'translate(${@:privateAccess this.curveEditor.xt(0)}, 0)'});

		if (overviewSelection != null)
			overviewSelection.attr({transform: 'translate(${@:privateAccess this.curveEditor.xt(0)}, 0)'});
	}

	public function refresh(?anim:Bool = false) {
		var width = Math.round(svg.element.width());
		var xScale = @:privateAccess this.curveEditor.xScale;
		var yScale = @:privateAccess this.curveEditor.yScale;
		var tlHeight = @:privateAccess this.curveEditor.tlHeight;
		var overviewHeight = 30;

		if (overviewGroup != null) {
			overviewGroup.empty();
			overviewGroup.remove();
		}

		overviewGroup = svg.group(this.curveEditor.componentsGroup, "overview");

		var overview = svg.rect(overviewGroup, 0, tlHeight, width, overviewHeight);
		overviewKeys = svg.group(overviewGroup, "overview-keys");
		overviewSelection = svg.group(overviewGroup, "overview-selection");
		overviewGroup.mousedown(function(e) {
			var offset = svg.element.offset();
			var px = e.clientX - offset.left;
			var py = e.clientY - offset.top;
			e.preventDefault();
			e.stopPropagation();
			overview.focus();
			if(e.which == 1) {
				if(e.which == 1) {
					if(e.ctrlKey) {
						addKey(@:privateAccess this.curveEditor.ixt(px));
					}
					else {
						startSelectRect(px, py);
					}
				}
			}
		});

		svg.line(overviewGroup, 0, tlHeight + overviewHeight, width, tlHeight + overviewHeight,{ stroke:'#000000', 'stroke-width':'1px' });
		setPan();

		function addDiamound(group, x: Float, y: Float, ?style: Dynamic) {
			var size = 6;
			var points = [
				new h2d.col.Point(x + size,y),
				new h2d.col.Point(x,y - size),
				new h2d.col.Point(x - size,y),
				new h2d.col.Point(x,y + size),
				new h2d.col.Point(x + size,y)
			];

			return svg.polygon(group, points, style).attr({
				"shape-rendering": "crispEdges"
			});
		}

		function addCurveKeysToOverview(curve: Curve, ?style: Dynamic) {
			for(key in curve.keys) {
				var kx = xScale*(key.time);
				var ky = -yScale*(key.value);

				var keyEvent = addDiamound(overviewKeys, kx, tlHeight + overviewHeight / 2.0,style);
				keyEvent.addClass("key-event");

				var selected = @:privateAccess this.curveEditor.selectedElements.indexOf(key) >= 0;
				if(selected)
					keyEvent.addClass("selected");

				keyEvent.mousedown(function(e) {
					if (curve.lock || curve.hidden) return;

					for (c in this.curveEditor.curves)
						c.selected = false;

					curve.selected = true;

					if(e.which != 1) return;

					e.preventDefault();
					e.stopPropagation();
					var offset = element.offset();
					@:privateAccess this.curveEditor.beforeChange();
					var startT = key.time;

					@:privateAccess this.curveEditor.startDrag(function(e) {
						var lx = e.clientX - offset.left;
						var nkx = @:privateAccess this.curveEditor.ixt(lx);
						var prevTime = key.time;
						key.time = nkx;
						if(e.ctrlKey) {
							key.time = Math.round(key.time * 10) / 10.;
							key.value = Math.round(key.value * 10) / 10.;
						}
						if(e.shiftKey)
							key.time = startT;
						@:privateAccess this.curveEditor.fixKey(key);
						this.curveEditor.refreshGraph(true, key);
						this.curveEditor.onKeyMove(key, prevTime, null);
						this.curveEditor.onChange(true);
					}, function(e) {
						@:privateAccess this.curveEditor.selectedElements = [key];
						@:privateAccess this.curveEditor.fixKey(key);
						@:privateAccess this.curveEditor.afterChange();
					});
					@:privateAccess this.curveEditor.selectedElements = [key];
					this.curveEditor.refreshGraph();
				});
			}
		}

		for (curve in this.curveEditor.curves){
			if (curve.hidden)
				continue;

			var style: Dynamic = { 'fill-opacity' : curve.selected ? 1 : 0.5};

			if (curve.lock || curve.blendMode == CurveBlendMode.Blend)
				style = { 'fill-opacity' : curve.selected ? 1 : 0.5};

			if (curve.hidden || curve.blendMode == CurveBlendMode.RandomBlend)
				style = { 'fill-opacity' : 0};

			// We don't want to show keys in overview if the
			// concerned curve is a blended one
			if (curve.blendMode != CurveBlendMode.Blend && curve.blendMode != CurveBlendMode.RandomBlend )
				addCurveKeysToOverview(curve, style);
		}

		var selectedKeys = @:privateAccess this.curveEditor.selectedElements.filter(item -> item is CurveKey);
		var selectedEvents = @:privateAccess this.curveEditor.selectedElements.filter(item -> !(item is CurveKey));
		if(selectedKeys.length > 1 || selectedEvents.length > 1) {
			var bounds = new h2d.col.Bounds();
			for(key in selectedKeys)
				bounds.addPoint(new h2d.col.Point(xScale*(key.time), tlHeight + overviewHeight / 2.0));
			var margin = 12.5;
			bounds.xMin -= margin;
			bounds.yMin -= margin;
			bounds.xMax += margin;
			bounds.yMax += margin;
			var rect = svg.rect(overviewSelection, bounds.x, bounds.y, bounds.width, bounds.height).attr({
				"shape-rendering": "crispEdges"
			});

			if (!anim) {
				rect.mousedown(function(e) {
					if(e.which != 1) return;
					@:privateAccess this.curveEditor.beforeChange();
					e.preventDefault();
					e.stopPropagation();
					var deltaX = 0;
					var lastX = e.clientX;

					@:privateAccess this.curveEditor.startDrag(function(e) {
						var dx = e.clientX - lastX;
						if(@:privateAccess this.curveEditor.lockKeyX || e.shiftKey)
							dx = 0;
						for(key in selectedKeys) {
							key.time += dx / xScale;
							if(@:privateAccess this.curveEditor.lockKeyX || e.shiftKey)
								key.time -= deltaX / xScale;

							@:privateAccess this.curveEditor.fixKey(key);
						}

						for(evt in selectedEvents) {
							evt.event.time += dx / xScale;
							if(@:privateAccess this.curveEditor.lockKeyX || e.shiftKey)
								evt.event.time -= deltaX / xScale;
						}

						deltaX += dx;
						if(@:privateAccess this.curveEditor.lockKeyX || e.shiftKey) {
							lastX -= deltaX;
							deltaX = 0;
						}
						else
							lastX = e.clientX;

						this.curveEditor.refreshGraph(true);
						this.curveEditor.onChange(true);
					}, function(e) {
						@:privateAccess this.curveEditor.afterChange();
					});
					this.curveEditor.refreshGraph();
				});
			}
		}
	}

	public function addKey(time: Float) {
		@:privateAccess this.curveEditor.beforeChange();

		for (c in this.curveEditor.curves)
			if (c.selected || this.curveEditor.curves.length == 1) {
				var previousKeyVal = c.getVal(time);
				c.addKey(time, previousKeyVal, c.keyMode);
			}

		@:privateAccess this.curveEditor.afterChange();
	}

	public function onSelectionEnd(minT:Float, minV:Float, maxT:Float, MaxV:Float) {}

	public function beforeChange() {}

	public function afterChange() {}
}

class CurveEditor extends hide.comp.Component {

	public static var CURVE_COLORS: Array<Int> = [
		0xff3352,
		0x8bdc00,
		0x2890ff,
		0x4cccff
	];

	public var xScale = 200.;
	public var yScale = 30.;
	public var xOffset = 0.;
	public var yOffset = 0.;

	public var curves(default, set) : Array<hrt.prefab.Curve>;
	public var undo : hide.ui.UndoHistory;

	public var lockViewX = false;
	public var lockViewY = false;
	public var lockKeyX = false;
	public var maxLength = 0.0;
	public var evaluator : hrt.prefab.fx.Evaluator;

	public var components : Array<CurveEditorComponent> = [];
	public var componentsGroup : Element;

	var enableTimeMarker = true;

	var svg : hide.comp.SVG;
	var width = 0;
	var height = 0;
	var tlGroup : Element;
	var markersGroup : Element;
	var gridGroup : Element;
	var graphGroup : Element;
	var selectGroup : Element;
	var overlayGroup : Element;

	var tlHeight = 20;

	var lastValue : Dynamic;

	var selectedElements: Array<Dynamic> = [];

	var currentTime: Float = 0.;
	var duration: Float = 2000.;

	public function new(undo, ?parent, enableTimeMarker = true) {
		super(parent,null);
		this.undo = undo;
		this.enableTimeMarker = enableTimeMarker;

		element.addClass("hide-curve-editor");
		element.attr({ tabindex: "1" });
		element.css({ width: "100%", height: "100%" });
		svg = new hide.comp.SVG(element);
		var div = this.element;
		var root = svg.element;
		height = Math.round(svg.element.height());
		if(height == 0 && parent != null)
			height = Math.round(parent.height());
		width = Math.round(svg.element.width());

		gridGroup = svg.group(root, "grid");
		graphGroup = svg.group(root, "graph");
		overlayGroup = svg.group(root, "overlaygroup");
		selectGroup = svg.group(root, "selection-overlay");
		componentsGroup = svg.group(root, "components");
		tlGroup = svg.group(root, "tlgroup");
		markersGroup = svg.group(root, "markers").css({'pointer-events':'none'});

		evaluator = new hrt.prefab.fx.Evaluator([]);

		var sMin = 0.0;
		var sMax = 0.0;
		tlGroup.mousedown(function(e) {
			var lastX = e.clientX;
			var shift = e.shiftKey;
			var ctrl = e.ctrlKey;
			var xoffset = svg.element.offset().left;

			function updateMouse(e: js.jquery.Event) {
				var dt = (e.clientX - lastX) / xScale;
				if(e.which == 1) {
					// if(shift) {
					// 	sMax = ixt(e.clientX - xoffset);
					// }
					// else if(ctrl) {
					// 	previewMax = ixt(e.clientX - xoffset);
					// }
					//else {
						currentTime = ixt(e.clientX - xoffset);
						currentTime = hxd.Math.max(currentTime, 0);
					//}
				}
			}

			startDrag(function(e) {
				updateMouse(e);
				lastX = e.clientX;
				refreshTimeline(currentTime);
				refreshOverlay(duration);
			}, function(e) {
				updateMouse(e);

				// if(previewMax < previewMin + 0.1) {
				// 	previewMin = 0;
				// 	previewMax = data.duration == 0 ? 5000 : data.duration;
				// }

				element.off("mousemove");
				element.off("mouseup");
				e.preventDefault();
				e.stopPropagation();
				refreshTimeline(currentTime);
				refreshOverlay(duration);
				//afterPan(false);
			});

			// 	if(hxd.Math.abs(sMax - sMin) < 1e-5) {
			// 		selectMin = 0;
			// 		selectMax = 0;
			// 	}
			// 	else {
			// 		selectMax = hxd.Math.max(sMin, sMax);
			// 		selectMin = hxd.Math.min(sMin, sMax);
			// 	}
			// }

			// if(data.markers != null) {
			// 	var marker = data.markers.find(m -> hxd.Math.abs(xt(clickTime) - xt(m.t)) < 4);
			// 	if(marker != null) {
			// 		var prevVal = marker.t;
			// 		startDrag(function(e) {
			// 			updateMouse(e);
			// 			var x = ixt(e.clientX - xoffset);
			// 			x = hxd.Math.max(0, x);
			// 			x = untyped parseFloat(x.toFixed(5));
			// 			marker.t = x;
			// 			refreshTimeline(true);
			// 		}, function(e) {
			// 			undo.change(Field(marker, "t", prevVal), refreshTimeline.bind(false));
			// 		});
			// 		e.preventDefault();
			// 		e.stopPropagation();
			// 		return;
			// 	}
			// }

			e.preventDefault();
			e.stopPropagation();
		});

		// var wheelTimer : haxe.Timer = null;
		// timeline.on("mousewheel", function(e) {
		// 	var step = e.originalEvent.wheelDelta > 0 ? 1.0 : -1.0;
		// 	xScale *= Math.pow(1.125, step);
		// 	e.preventDefault();
		// 	e.stopPropagation();
		// 	refreshTimeline(false);
		// 	if(wheelTimer != null)
		// 		wheelTimer.stop();
		// 	wheelTimer = haxe.Timer.delay(function() {
		// 		this.curveEditor.xOffset = xOffset;
		// 		this.curveEditor.xScale = xScale;
		// 		this.curveEditor.refresh();
		// 		afterPan(false);
		// 	}, 50);
		// });

		// selectMin = 0.0;
		// selectMax = 0.0;
		// previewMin = 0.0;
		// previewMax = data.duration == 0 ? 5000 : data.duration;
		// refreshTimeline(false);

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
			if((e.key == "z" || e.key == "f") && !e.ctrlKey) {
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
			else if (e.altKey){
				if(!lockViewX) {
					xScale *= Math.pow(1.125, step);
					changed = true;
				}
			}
			else {
				yScale *= Math.pow(1.125, step);
				xScale *= Math.pow(1.125, step);
				changed = true;
			}
			if(changed) {
				e.preventDefault();
				e.stopPropagation();
				saveView();
				refresh();
			}
		});
		div.keydown(function(e) {
			if(curves == null) return;
			if(e.keyCode == 46) {
				beforeChange();
				var newVal = [for(c in curves) [for(k in c.keys) if(selectedElements.indexOf(k) < 0) k]];

				for (i in 0...curves.length)
					curves[i].keys = newVal[i];

				selectedElements = [];
				e.preventDefault();
				e.stopPropagation();
				afterChange();
			}
			/*if(e.key == "z") {
				zoomAll();
			}*/
		});

		this.curves = [];
	}

	public dynamic function onChange(anim: Bool) {

	}

	public dynamic function onKeyMove(key: CurveKey, prevTime: Float, prevVal: Float) {

	}

	public dynamic function requestXZoom(xmin: Float, xmax: Float) {

	}

	function set_curves(curves: Array<hrt.prefab.Curve>) {
		this.curves = curves;

		var maxLength = 0.0;
		for (c in curves){
			if (c.maxTime > maxLength)
				maxLength = c.maxTime;
		}

		@:privateAccess lastValue = [for (c in curves) c.serialize()];
		refresh();
		return curves;
	}

	function addKey(time: Float, ?val: Float) {
		beforeChange();

		for (c in curves)
			if (c.selected || curves.length == 1) {
				if(c.minValue < c.maxValue)
					val = hxd.Math.clamp(val, c.minValue, c.maxValue);

				c.addKey(time, val, c.keyMode);
			}

		afterChange();
	}

	function addPreviewKey(time: Float, ?val: Float) {
		beforeChange();
		for (c in curves)
			if (c.selected) {
				if(c.minValue < c.maxValue)
					val = hxd.Math.clamp(val, c.minValue, c.maxValue);

				c.addPreviewKey(time, val);
			}

		afterChange();
	}

	function fixKeys(keys : Array<CurveKey>) {
		for (k in keys)
			fixKey(k);
	}

	function fixKey(key : CurveKey) {
		for (c in curves) {
			if (!c.selected)
				continue;

			var index = c.keys.indexOf(key);

			// Meaning that this key isn't appartening to this curve
			if (index == -1)
				continue;

			var prev = c.keys[index-1];
			var next = c.keys[index+1];

			inline function addPrevH() {
				if(key.prevHandle == null)
					key.prevHandle = new hrt.prefab.Curve.CurveHandle(prev != null ? (prev.time - key.time) / 3 : -0.5, 0);
			}

			inline function addNextH() {
				if(key.nextHandle == null)
					key.nextHandle = new hrt.prefab.Curve.CurveHandle(next != null ? (next.time - key.time) / 3 : -0.5, 0);
			}

			switch(key.mode) {
				case Aligned:
					addPrevH();
					addNextH();
					// var pa = hxd.Math.atan2(key.prevHandle.dv, key.prevHandle.dt);
					// var na = hxd.Math.atan2(key.nextHandle.dv, key.nextHandle.dt);

					// if(hxd.Math.abs(hxd.Math.angle(pa - na)) < Math.PI - (1./180.)) {
					// 	key.nextHandle.dt = -key.prevHandle.dt;
					// 	key.nextHandle.dv = -key.prevHandle.dv;
					// }
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
			if(maxLength > 0 && key.time > maxLength)
				key.time = maxLength;
			if(key.time > c.maxTime)
				key.time = c.maxTime;
			if(prev != null && key.time < prev.time)
				key.time = prev.time + 0.01;
			if(next != null && key.time > next.time)
				key.time = next.time - 0.01;

			if(c.minValue < c.maxValue)
				key.value = hxd.Math.clamp(key.value, c.minValue, c.maxValue);

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

			selectedElements = [];
			for (c in curves){
				c.selected = false;

				if (c.hidden || c.lock || c.blendMode == CurveBlendMode.Blend ||  c.blendMode == CurveBlendMode.RandomBlend)
					continue;

				for (key in c.keys)
					if(key.time >= minT && key.time <= maxT && key.value >= minV && key.value <= maxV) {
						c.selected = true;
						selectedElements.push(key);
					}
			}

			onSelectionEnd(minT, minV, maxT, maxV);
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

	function applyView () {
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
			refreshTimeline();
			refreshOverlay();
			setComponentsPan();
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
		// If there is some components attached to curve, it takes some place
		// on svg, so we add bigger margin on Y axis.
		var margin = this.components.length == 0 ? 30.0 : 60.0;
		yScale = (height - margin * 2.0) / (yMax - yMin);
		yOffset = (yMax + yMin) * 0.5;
	}

	public function setXZoom(xMin: Float, xMax: Float) {
		var margin = 10.0;
		xScale = (width - margin * 2.0) / (xMax - xMin);
		xOffset = xMin;
	}

	public function zoomAll() {
		if (curves.length == 0)
			return;

		// Compute a surrounding box that encapsulate all the visible curves
		var bounds = new h2d.col.Bounds();
		for (c in curves) {
			if (c.hidden)
				continue;

			c.getBounds(bounds);
		}

		if(bounds.width <= 0) {
			bounds.xMin = 0.0;
			bounds.xMax = 1.0;
		}

		if(bounds.height <= 0) {
			bounds.yMin = -1.0;
			bounds.yMax = 1.0;
		}

		if(!lockViewY) {
			setYZoom(bounds.yMin, bounds.yMax);
		}
		if(!lockViewX) {
			setXZoom(bounds.xMin, bounds.xMax);
		}
		else {
			requestXZoom(bounds.xMin, bounds.xMax);
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
		@:privateAccess lastValue = [for (c in curves) c.serialize()];

		for (c in components)
			c.beforeChange();
	}

	function afterChange() {
		@:privateAccess var newVal = [for (c in curves) c.serialize()];
		var oldVal = lastValue;
		undo.change(Custom(function(undo) {
			if(undo) {
				for (i in 0...curves.length)
					curves[i].load(oldVal[i]);
			}
			else {
				for (i in 0...curves.length)
					curves[i].load(newVal[i]);
			}
			@:privateAccess lastValue = [for (c in curves) c.serialize()];
			selectedElements = [];
			refresh();
			onChange(false);
		}));

		for (c in components)
			c.afterChange();

		refresh();
		onChange(false);
	}

	public function refresh(?anim: Bool) {
		applyView();
		refreshGrid();
		refreshGraph(anim);
		refreshTimeline();
		refreshOverlay();
	}

	public function refreshGrid() {
		width = Math.round(svg.element.width());
		height = Math.round(svg.element.height());

		gridGroup.empty();

		var minY = Math.floor(iyt(height));
		var maxY = Math.ceil(iyt(0));
		var vgrid = svg.group(gridGroup, "vgrid");

		var minX = Math.floor(ixt(0));
		var maxX = Math.ceil(ixt(width));
		var hgrid = svg.group(gridGroup, "hgrid");

		tlGroup.empty();
		svg.rect(tlGroup, 0, 0, width, tlHeight).addClass("timeline");

		inline function xHline(ix) {
			return svg.line(hgrid, xt(ix), 0, xt(ix), height).attr({
				"shape-rendering": "crispEdges"
			});
		}

		inline function yHline(iy) {
			return svg.line(vgrid, 0, yt(iy), width, yt(iy)).attr({
				"shape-rendering": "crispEdges"
			});
		}

		inline function xHlabel(str, ix) {
			svg.text(tlGroup, xt(ix), 14, str, {'text-anchor':'middle'});
		}

		inline function yHlabel(str, iy) {
			svg.text(vgrid, 1, yt(iy), str);
		}

		var vstep = 0.1;
		while((maxY - minY) / vstep > 21)
			vstep *= 2;

		var minS = Math.floor(minY / vstep);
		var maxS = Math.ceil(maxY / vstep);
		for(i in minS...(maxS+1)) {
			var iy = i * vstep;
			var l = yHline(iy);

			var interY = (i + 0.5) * vstep;
			var interl = yHline(interY);
			interl.addClass("interline");

			if(iy == 0)
				l.addClass("axis");
			yHlabel("" + hxd.Math.fmt(iy), iy);
		}

		var hstep = 0.1;
		while((maxX - minX) / hstep > 21)
			hstep *= 2;

		minS = Math.floor(minX / hstep);
		maxS = Math.ceil(maxX / hstep);
		for(i in minS...(maxS+1)) {
			var ix = i * hstep;
			var l = xHline(ix);

			var interX = (i + 0.5) * hstep;
			var interl = xHline(interX);
			interl.addClass("interline");

			if(ix == 0)
				l.addClass("axis");

			xHlabel("" + hxd.Math.fmt(ix), ix);
		}

		if(maxLength > 0)
			svg.rect(gridGroup, xt(maxLength), 0, width - xt(maxLength), height, { opacity: 0.4});
	}

	public function refreshTimeline(?currentTime : Float) {
		markersGroup.empty();

		if (!Math.isNaN(currentTime))
			this.currentTime = currentTime;

		function drawLabel(?parent: Element, x:Float, y:Float, width:Float, height:Float, ?style:Dynamic) {
			var a = new h2d.col.Point(x - width / 2.0, y - height / 2.0);
			var b = new h2d.col.Point(x + width / 2.0, y - height / 2.0);
			var c = new h2d.col.Point(x + width / 2.0, y + height / 2.0);
			var d = new h2d.col.Point( x - width / 2.0,y + height / 2.0);
			var points: Array<h2d.col.Point> = [ a, b, c, d, a, b];
			svg.polygon(parent, points, style);
		}

		// Draw timeline marker
		if (!enableTimeMarker)
			return;

		var labelWidth = 18;
		var labelHeight = 10;
		var rounderCurrTime = Math.round(this.currentTime * 10) / 10.0;
		svg.line(markersGroup, xt(this.currentTime), svg.element.height(), xt(this.currentTime), labelHeight / 2.0, { stroke:'#426dae', 'stroke-width':'2px' });
		drawLabel(markersGroup, xt(this.currentTime), labelHeight / 2.0 + (tlHeight - labelHeight) / 2.0, labelWidth, labelHeight, { fill:'#426dae', stroke: '#426dae', 'stroke-width':'5px', 'stroke-linejoin':'round'});
		svg.text(markersGroup, xt(this.currentTime), 14, '${rounderCurrTime}', { 'fill':'#e7ecf5', 'text-anchor':'middle', 'font':'10px sans-serif'});


		function drawMaker(x: Float) {
			svg.line(markersGroup, xt(x), svg.element.height(), xt(x), labelHeight / 2.0, { stroke: '#260f00', 'stroke-width' : '2px'});
		}

		drawMaker(0);

	}

	public function refreshOverlay(?duration: Float) {
		overlayGroup.empty();

		if (!Math.isNaN(duration))
			this.duration = duration;

		var minX = xt(0) - 1;
		var maxX = xt(this.duration == 0 ? 5000 : this.duration);
		svg.line(overlayGroup, xt(1), svg.element.height(), xt(1), 0, { stroke:'#000000', 'stroke-width':'1px', 'stroke-dasharray':'10, 5' });
		svg.line(overlayGroup, minX, svg.element.height(), minX, 0, { stroke:'#000000', 'stroke-width':'1px' });
		svg.line(overlayGroup, maxX, svg.element.height(), maxX, 0, { stroke:'#000000', 'stroke-width':'1px' });
		svg.rect(overlayGroup, 0, 0, Math.max(0,xt(0)), svg.element.height(), { 'fill':'#000000', opacity:0.3});
		svg.rect(overlayGroup, maxX, 0, svg.element.width(), svg.element.height(), { 'fill':'#000000', opacity:0.3});
	}

	public function refreshGraph(?anim: Bool = false, ?animKey: CurveKey) {
		if(curves == null)
			return;

		graphGroup.empty();
		var graphOffX = xt(0);
		var graphOffY = yt(0);
		graphGroup.attr({transform: 'translate($graphOffX, $graphOffY)'});

		//topbarKeys.empty();
		//topbarKeys.attr({transform: 'translate($graphOffX, 0)'});

		var curveGroup = svg.group(graphGroup, "curve");
		var vectorsGroup = svg.group(graphGroup, "vectors");
		var handlesGroup = svg.group(graphGroup, "handles");
		var keyHandles = svg.group(handlesGroup, "keys");
		var tangentsHandles = svg.group(handlesGroup, "tangents");
		var selection = svg.group(graphGroup, "selection");
		var size = 3;

		function addCircle(group, x: Float, y: Float, ?style: Dynamic) {
			return svg.circle(group, x, y , size, style).attr({
				"shape-rendering": "crispEdges"
			});
		}

		function editPopup(curve: Curve, key: CurveKey, top: Float, left: Float) {
			var popup = new Element('<div class="keyPopup">
					<div class="line"><label>Time</label><input class="x" type="number" value="0" step="0.1"/></div>
					<div class="line"><label>Value</label><input class="y" type="number" value="0" step="0.1"/></div>
					<div class="line">
						<label>Mode</label>
						<select>
							<option value="0">Aligned</option>
							<option value="1">Free</option>
							<option value="2">Linear</option>
							<option value="3">Constant</option>
						</select>
					</div>
				</div>').appendTo(element);
			popup.css({top: top, left: left});
			popup.focusout(function(e) {
				haxe.Timer.delay(function() {
					if(popup.find(':focus').length == 0)
						popup.remove();
				}, 0);
			});

			function setMode(m: hrt.prefab.Curve.CurveKeyMode) {
					key.mode = m;
					curve.keyMode = m;
					fixKey(key);
					refreshGraph();
			}

			var select = popup.find("select");
			select.val(Std.string(key.mode));
			select.change(function(val) {
				setMode(cast Std.parseInt(select.val()));
			});

			function afterEdit() {
				refreshGraph(false);
				onChange(false);
			}

			var xel = popup.find(".x");
			xel.val(hxd.Math.fmt(key.time));
			xel.change(function(e) {
				var f = Std.parseFloat(xel.val());
				if(f != null) {
					undo.change(Field(key, "time", key.time), afterEdit);
					key.time = f;
					afterEdit();
				}
			});
			var yel = popup.find(".y");
			yel.val(hxd.Math.fmt(key.value));
			yel.change(function(e) {
				var f = Std.parseFloat(yel.val());
				if(f != null) {
					undo.change(Field(key, "value", key.value), afterEdit);
					key.value = f;
					afterEdit();
				}
			});
			popup.find("input").first().focus();
			popup.focus();
			return popup;
		}

		function drawCurve(curve : Curve, ?style: Dynamic) {
			// Draw curve
			if(curve.keys.length > 0) {
				var keys = curve.keys;
				if(false) {  // Bezier draw, faster but less accurate
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
				}
				else {
					var pts = [];

					// Basic value of xScale is 200
					var num : Int = Std.int(Math.min(5000, 500 * cast (xScale / 200.0)));
					pts.resize(num);
					var v = curve.makeVal();
					if (v == null) throw "wtf";
					var duration = curve.duration;
					for (i in 0...num) {
						pts[i] = evaluator.getFloat(v, duration * i/(num-1));
					}
					var poly = [];

					for(i in 0...pts.length) {
						var x = xScale * (curve.duration * i / (pts.length - 1));
						var y = yScale * (-pts[i]);
						poly.push(new h2d.col.Point(x, y));
					}

					svg.polygon(curveGroup, poly, style);
				}
			}
		}

		function drawKeys(curve : Curve, ?style: Dynamic) {
			for(key in curve.previewKeys) {
				var kx = xScale*(key.time);
				var ky = -yScale*(key.value);
				var keyHandle = addCircle(keyHandles, kx, ky, style);
				keyHandle.addClass("preview");
			}
			for(key in curve.keys) {
				var kx = xScale*(key.time);
				var ky = -yScale*(key.value);
				var keyHandle = addCircle(keyHandles, kx, ky, style);

				if(curve.lock)
					keyHandle.addClass("no-hover");

				var selected = selectedElements.indexOf(key) >= 0;
				if(selected)
					keyHandle.addClass("selected");
				if(!anim) {
					keyHandle.mousedown(function(e) {
						if (curve.lock || curve.hidden) return;

						for (c in curves)
							c.selected = false;

						curve.selected = true;

						if(e.which != 1) return;

						e.preventDefault();
						e.stopPropagation();
						var offset = element.offset();
						beforeChange();
						var startT = key.time;
						var startV = key.value;

						startDrag(function(e) {

							var lx = e.clientX - offset.left;
							var ly = e.clientY - offset.top;
							var nkx = ixt(lx);
							var nky = iyt(ly);
							var prevTime = key.time;
							var prevVal = key.value;
							key.time = nkx;
							key.value = nky;
							if(e.ctrlKey) {
								key.time = Math.round(key.time * 10) / 10.;
								key.value = Math.round(key.value * 10) / 10.;
							}
							if(lockKeyX || e.altKey)
								key.value = startV;
							if(e.shiftKey)
								key.time = startT;
							fixKey(key);
							refreshGraph(true, key);
							onKeyMove(key, prevTime, prevVal);
							onChange(true);
						}, function(e) {
							selectedElements = [key];
							fixKey(key);
							afterChange();
						});
						selectedElements = [key];
						refreshGraph();
					});
					keyHandle.contextmenu(function(e) {
						if (curve.lock || curve.hidden) return false;

						for (c in curves)
							c.selected = false;

						curve.selected = true;
						var offset = element.offset();
						var popup = editPopup(curve, key, e.clientY - offset.top - 50, e.clientX - offset.left);
						e.preventDefault();
						return false;
					});
				}
				function addHandle(next: Bool) {
					var handle = next ? key.nextHandle : key.prevHandle;
					var other = next ? key.prevHandle : key.nextHandle;
					if(handle == null) return null;
					var px = xScale*(key.time + handle.dt);
					var py = -yScale*(key.value + handle.dv);
					var line = svg.line(vectorsGroup, kx, ky, px, py, style);
					var circle = svg.circle(tangentsHandles, px, py, size, style);
					if(selected) {
						line.addClass("selected");
						circle.addClass("selected");
					}
					if(anim)
						return circle;
					circle.mousedown(function(e) {
						if (curve.lock || curve.hidden) return;

						for (c in curves)
							c.selected = false;

						curve.selected = true;

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
		}

		function drawBlendArea(curve : Curve, ?style: Dynamic) {
			if (curve.blendMode == CurveBlendMode.RandomBlend) {
				var c1: Curve = cast curve.children[0];
				var c2: Curve = cast curve.children[1];

				var sampleSize = 500 * cast (xScale / 200.0);
				var poly = [];

				var ptsC1 = c1.sample(sampleSize);
				for(i in 0...ptsC1.length) {
					var x = xScale * (c1.duration * i / (ptsC1.length - 1));
					var y = yScale * (-ptsC1[i]);
					poly.push(new h2d.col.Point(x, y));
				}

				var ptsC2 = c2.sample(sampleSize);

				var idx = ptsC2.length-1;
				while (idx >= 0) {
					var x = xScale * (c2.duration * idx / (ptsC2.length - 1));
					var y = yScale * (-ptsC2[idx]);
					poly.push(new h2d.col.Point(x, y));
					idx--;
				}

				var blendAreaStyle: Dynamic = { opacity : 0.1 , fill : '#FFFFFF', stroke : '#000000'};
				if (c1.lock && c2.lock) blendAreaStyle = { opacity : 0.05 , fill : '#FFFFFF', stroke : '#000000'};
				if (c1.hidden && c2.hidden) blendAreaStyle = { opacity : 0 , fill : '#FFFFFF', stroke : '#000000'};

				svg.polygon(curveGroup, poly, blendAreaStyle).attr("pointer-events","none");
			}
		}

		for (curve in curves){
			var colorInt = curve.color;
			if (curve.blendMode == Blend) {
				var root = curve.getRoot();
				var params = Std.downcast(root, hrt.prefab.fx.FX)?.parameters;
				if (params != null) {
					for (p in params) {
						if (p.name == curve.blendParam) {
							colorInt = p.color;
							break;
						}
					}
				}
			}
			var color = '#${StringTools.hex(colorInt)}';
			var curveStyle: Dynamic = { opacity : curve.selected ? 1 : 0.5, stroke : color, "stroke-width":'${curve.selected ? 2 : 1}px'};
			var keyStyle: Dynamic = { opacity : curve.selected ? 1 : 0.5};
			var eventStyle: Dynamic = { 'fill-opacity' : curve.selected ? 1 : 0.5};

			if (curve.lock) {
				curveStyle = { opacity : curve.selected ? 1 : 0.5 , stroke : color, "stroke-width":'${curve.selected ? 2 : 1}px', "stroke-dasharray":"5, 3"};
				keyStyle = { opacity : curve.selected ? 1 : 0.5, 'cursor':'default'};
				eventStyle = { 'fill-opacity' : curve.selected ? 1 : 0.5};
			}

			if (curve.blendMode == CurveBlendMode.Blend) {
				curveStyle = { opacity : curve.selected ? 1 : 0.5 , stroke : color, "stroke-width":'${curve.selected ? 2 : 1}px', "stroke-dasharray":"20,10,5,5,5,10"};
				keyStyle = { opacity : curve.selected ? 1 : 0.5};
				eventStyle = { 'fill-opacity' : curve.selected ? 1 : 0.5};
			}

			if (curve.hidden || curve.blendMode == CurveBlendMode.RandomBlend) {
				curveStyle = { opacity : 0};
				keyStyle = { opacity : 0};
				eventStyle = { 'fill-opacity' : 0};
			}

			drawCurve(curve, curveStyle);

			// Draw the area where random blend curves will be picked
			drawBlendArea(curve);

			// Blend curve are controlled with parent curve
			// so we don't want to allow user to use keys on this.s
			if (curve.blendMode == CurveBlendMode.None)
				drawKeys(curve, keyStyle);
		}

		var selectedKeys = selectedElements.filter(item -> item is CurveKey);
		var selectedEvents = selectedElements.filter(item -> !(item is CurveKey));
		if(selectedKeys.length > 1 || selectedEvents.length > 1) {
			var bounds = new h2d.col.Bounds();

			for(key in selectedKeys)
				bounds.addPoint(new h2d.col.Point(xScale*(key.time), -yScale*(key.value)));

			var yOrigin = 20;
			var eventHeight = 18;
			var spacing = 2;
			var evtCpt = 0;
			for(evt in selectedEvents) {
				var y1 = yOrigin + ((eventHeight + spacing) * evt.pos);
				var y2 = y1 + eventHeight;
				var x1 = evt.event.time;
				var x2 = x1 + (evt.length == 0 ? 5000 : evt.length);
				bounds.addPoint(new h2d.col.Point(xScale*(x1), y1));
				bounds.addPoint(new h2d.col.Point(xScale*(x1), y2));
				bounds.addPoint(new h2d.col.Point(xScale*(x2), y1));
				bounds.addPoint(new h2d.col.Point(xScale*(x2), y2));

				evtCpt++;
			}

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
					var deltaX = 0;
					var deltaY = 0;
					var lastX = e.clientX;
					var lastY = e.clientY;
					startDrag(function(e) {
						var dx = e.clientX - lastX;
						var dy = e.clientY - lastY;
						if(lockKeyX || e.shiftKey)
							dx = 0;
						if(e.altKey)
							dy = 0;
						for(key in selectedElements) {
							key.time += dx / xScale;
							if(lockKeyX || e.shiftKey)
								key.time -= deltaX / xScale;
							key.value -= dy / yScale;
							if(e.altKey)
								key.value += deltaY / yScale;
						}

						fixKeys(cast selectedEvents);

						for(el in selectedEvents) {
							el.event.time += dx / xScale;
							if(lockKeyX || e.shiftKey)
								el.time -= deltaX / xScale;
						}

						deltaX += dx;
						deltaY += dy;
						if(lockKeyX || e.shiftKey) {
							lastX -= deltaX;
							deltaX = 0;
						}
						else
							lastX = e.clientX;
						if(e.altKey) {
							lastY -= deltaY;
							deltaY = 0;
						}
						else
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

		refreshComponents(anim);
	}

	public function onSelectionEnd(minT: Float, minV: Float, maxT: Float, maxV: Float) {
		for (c in components)
			c.onSelectionEnd(minT, minV, maxT, maxV);
	}

	public function setComponentsPan() {
		for (comp in this.components) {
			comp.setPan();
		}
	}

	public function refreshComponents(?anim:Bool = false) {
		for (comp in this.components) {
			comp.refresh(anim);
		}
	}
}
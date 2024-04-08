package hide.view;

import haxe.Timer;

import haxe.rtti.Meta;
import js.jquery.JQuery;
import h2d.col.Point;
import h2d.col.IPoint;
import hide.comp.SVG;
import hide.view.shadereditor.Box;
import hrt.shgraph.ShaderNode;
import hrt.shgraph.ShaderType;
using Lambda;
import hrt.shgraph.ShaderType.SType;

enum EdgeState { None; FromInput; FromOutput; }

typedef Edge = { from : Box, outputFrom : Int, to : Box, inputTo : Int, elt : JQuery };

@:access(hide.view.shadereditor.Box)
class Graph extends FileView {

	var parent : JQuery;
	var editor : SVG;
	var editorMatrix : JQuery;
	var statusBar : JQuery;
	var statusClose : JQuery;


	var listOfBoxes : Array<Box> = [];
	var listOfEdges : Array<Edge> = [];

	var transformMatrix : Array<Float> = [1, 0, 0, 1, 0, 0];
	var isPanning : Bool = false;
	static var MAX_ZOOM = 1.3;
	static var CENTER_OFFSET_Y = 0.1; // percent of height

	// used for moving when mouse is close to borders
	static var BORDER_SIZE = 50;
	static var SPEED_BORDER_MOVE = 0.05;
	var timerUpdateView : Timer;

	// used for selection
	var listOfBoxesSelected : Array<Box> = [];
	var listOfBoxesToMove : Array<Box> = [];
	var undoSave : Any;
	var recSelection : JQuery;
	var startRecSelection : h2d.col.Point;
	var lastClickDrag : h2d.col.Point;
	var lastClickPan : h2d.col.Point;

	// used to build edge
	static var NODE_TRIGGER_NEAR = 2000.0;
	var isCreatingLink : EdgeState = None;
	var edgeStyle = {stroke : ""};
	var startLinkBox : Box;
	var endLinkBox : Box;
	var startLinkNodeId : Int;
	var endLinkNodeId : Int;
	var currentLink : JQuery; // draft of edge

	// used for deleting
	var currentEdge : Edge;

	// aaaaaa
	var domain : hrt.shgraph.ShaderGraph.Domain;

	override function onDisplay() {
		element.html('
			<div class="flex vertical" >
				<div class="flex-elt graph-view" tabindex="0" >
					<div class="heaps-scene" tabindex="1" >
					</div>
					<div id="rightPanel" class="tabs" >
					</div>
				</div>
			</div>');
		parent = element.find(".heaps-scene");
		editor = new SVG(parent);
		editor.element.attr("id", "graph-root");
		var status = new Element('<div id="status-bar" ><div id="close">-- close --</div><pre></pre></div>');
		statusBar = status.appendTo(parent).find("pre");
		statusClose = status.find("#close");
		statusClose.hide();
		statusClose.on("click", function(e) {
			statusBar.html("");
			statusClose.hide();
		});
		statusBar.on("wheel", (e) -> { e.stopPropagation(); });

		editorMatrix = editor.group(editor.element);

		// rectangle Selection
		parent.on("mousedown", function(e) {

			if (e.button == 0) {
				startRecSelection = new Point(lX(e.clientX), lY(e.clientY));
				if (currentEdge != null) {
					currentEdge.elt.removeClass("selected");
					currentEdge = null;
				}

				clearSelectionBoxes();
				return;
			}
			if (e.button == 1) {
				lastClickPan = new Point(e.clientX, e.clientY);
				isPanning = true;
				return;
			}
		});

		parent.on("mousemove", function(e : js.jquery.Event) {
			e.preventDefault();
			e.cancelBubble=true;
    		e.returnValue=false;
			mouseMoveFunction(e.clientX, e.clientY);
		});

		var document = new Element(js.Browser.document);
		document.on("mouseup", function(e) {
			if(timerUpdateView != null)
				stopUpdateViewPosition();
			if (e.button == 0) {

				// Stop rectangle selection
				lastClickDrag = null;
				startRecSelection = null;
				if (recSelection != null) {
					recSelection.remove();
					recSelection = null;
					for (b in listOfBoxes)
						if (b.selected)
							listOfBoxesSelected.push(b);
					return;
				}

				return;
			}

			// Stop panning
			if (e.button == 1) {
				lastClickDrag = null;
				isPanning = false;
				return;
			}
		});

		// Zoom control
		parent.on("wheel", function(e) {
			if (e.originalEvent.deltaY < 0) {
				zoom(1.1, e.clientX, e.clientY);
			} else {
				zoom(0.9, e.clientX, e.clientY);
			}
		});

		listOfBoxes = [];
		listOfEdges = [];

		updateMatrix();
	}

	function mouseMoveFunction(clientX : Int, clientY : Int) {
		if (isCreatingLink != None) {
			startUpdateViewPosition();
			createLink(clientX, clientY);
			return;
		}
		// Moving edge
		if (currentEdge != null) {
			var distOutput = distanceToElement(currentEdge.from.outputs[currentEdge.outputFrom], clientX, clientY);
			var distInput = distanceToElement(currentEdge.to.inputs[currentEdge.inputTo], clientX, clientY);

			if (distOutput > distInput) {
				replaceEdge(FromOutput, currentEdge.to.inputs[currentEdge.inputTo], clientX, clientY);
			} else {
				replaceEdge(FromInput, currentEdge, clientX, clientY);
			}
			currentEdge = null;
			return;
		}
		if (isPanning) {
			pan(new Point(clientX - lastClickPan.x, clientY - lastClickPan.y));
			lastClickPan.x = clientX;
			lastClickPan.y = clientY;
			return;
		}
		// Edit rectangle selection
		if (startRecSelection != null) {
			startUpdateViewPosition();
			var endRecSelection = new h2d.col.Point(lX(clientX), lY(clientY));
			var xMin = startRecSelection.x;
			var xMax = endRecSelection.x;
			var yMin = startRecSelection.y;
			var yMax = endRecSelection.y;

			if (startRecSelection.x > endRecSelection.x) {
				xMin = endRecSelection.x;
				xMax = startRecSelection.x;
			}
			if (startRecSelection.y > endRecSelection.y) {
				yMin = endRecSelection.y;
				yMax = startRecSelection.y;
			}

			if (recSelection != null) recSelection.remove();
			recSelection = editor.rect(editorMatrix, xMin, yMin, xMax - xMin, yMax - yMin).addClass("rect-selection");

			for (box in listOfBoxes) {
				if (isInside(box, new Point(xMin, yMin), new Point(xMax, yMax))) {
					box.setSelected(true);
				} else {
					box.setSelected(false);
				}
			}
			return;
		}

		// Move selected boxes
		if (listOfBoxesSelected.length > 0 && lastClickDrag != null) {
			startUpdateViewPosition();
			var dx = (lX(clientX) - lastClickDrag.x);
			var dy = (lY(clientY) - lastClickDrag.y);


			for (b in listOfBoxesToMove) {
				moveBox(b, b.getX() + dx, b.getY() + dy);
			}
			lastClickDrag.x = lX(clientX);
			lastClickDrag.y = lY(clientY);
			return;
		}
	}

	dynamic function updatePosition(box : Box) { }

	function moveBox(b: Box, x: Float, y: Float) {
		b.setPosition(x, y);
		updatePosition(b);
		// move edges from and to this box
		for (edge in listOfEdges) {
			if (edge.from == b || edge.to == b) {
				edge.elt.remove();
				edgeStyle.stroke = edge.from.outputs[edge.outputFrom].css("fill");
				edge.elt = createCurve( edge.from.outputs[edge.outputFrom], edge.to.inputs[edge.inputTo]);

				edge.elt.on("mousedown", function(e) {
					e.stopPropagation();
					clearSelectionBoxes();
					this.currentEdge = edge;
					currentEdge.elt.addClass("selected");
				});
			}
		}
	}

	function beginMove(e: js.html.MouseEvent) {
		lastClickDrag = new Point(lX(e.clientX), lY(e.clientY));

		var boxesToMove : Map<Box, Bool> = [];

		for (b in listOfBoxesSelected) {
			boxesToMove.set(b, true);

			if (b.comment != null && !e.shiftKey) {
				var min = inline new Point(b.getX(), b.getY());
				var max = inline new Point(b.getX() + b.comment.width, b.getY() + b.comment.height);

				for (bb in listOfBoxes) {
					if (isFullyInside(bb, min, max)) {
						boxesToMove.set(bb, true);
					}
				}
			}
		}

		listOfBoxesToMove = [for (k in boxesToMove.keys()) k];
		undoSave = saveMovedBoxes();

		trace(listOfBoxesToMove);
	}

	function saveMovedBoxes() {
		var save : Map<Int, {x: Float, y: Float}> = [];
		for (b in listOfBoxesToMove) {
			save.set(b.nodeInstance.id, {x:b.getX(), y: b.getY()});
		}
		return save;
	}

	function endMove() {
		if (lastClickDrag == null)
			return;

		lastClickDrag = null;

		if (undoSave != null) {
			var before : Map<Int, {x: Float, y: Float}> = undoSave;
			var after : Map<Int, {x: Float, y: Float}> = saveMovedBoxes();

			undo.change(Custom(function(undo) {
				var toApply = undo ? before : after;
				for (id => pos in toApply) {
					var box = listOfBoxes.find((e) -> e.nodeInstance.id == id);
					moveBox(box, pos.x ,pos.y);
				}
			}));
			undoSave = null;
		}

		listOfBoxesToMove = [];
	}

	function addBox(p : Point, nodeClass : Class<ShaderNode>, node : ShaderNode) : Box {

		var className = std.Type.getClassName(nodeClass);
		className = className.substr(className.lastIndexOf(".") + 1);

		var box = new Box(this, editorMatrix, p.x, p.y, node);
		var elt = box.getElement();
		elt.get(0).onmousedown = function(e: js.html.MouseEvent) {
			if (e.button != 0)
				return;
			e.stopPropagation();

			if (!box.selected) {
				if (!e.ctrlKey) {
					// when not group selection and click on box not selected
					clearSelectionBoxes();
					listOfBoxesSelected = [box];
				} else
					listOfBoxesSelected.push(box);
				box.setSelected(true);
			}
			beginMove(e);
		};
		elt.mouseup(function(e) {
			if (e.button != 0)
				return;
			endMove();
		});
		listOfBoxes.push(box);

		for (inputId => input in box.getInstance().getInputs()) {
			var defaultValue : String = null;
			switch (input.def) {
				case Const(defValue):
					defaultValue= Reflect.getProperty(box.getInstance().defaults, '${input.name}');
					if (defaultValue == null) {
						defaultValue = '$defValue';
					}
				default:
			}
			var grNode = box.addInput(this, input.name, defaultValue, input.type);
			if (defaultValue != null) {
				var fieldEditInput = grNode.find("input");
				fieldEditInput.on("change", function(ev) {
					var tmpValue = Std.parseFloat(fieldEditInput.val());
					if (Math.isNaN(tmpValue) ) {
						fieldEditInput.addClass("error");
					} else {
						// Store the value as a string anyway
						Reflect.setField(box.getInstance().defaults, '${input.name}', '$tmpValue');
						fieldEditInput.val(tmpValue);
						fieldEditInput.removeClass("error");
					}
				});
			}
			grNode.find(".node").attr("field", inputId);
			grNode.on("mousedown", function(e : js.jquery.Event) {
				e.stopPropagation();
				var node = grNode.find(".node");
				if (node.attr("hasLink") != null) {
					replaceEdge(FromOutput, node, e.clientX, e.clientY);
					return;
				}
				isCreatingLink = FromInput;
				startLinkNodeId = inputId;
				startLinkBox = box;
				edgeStyle.stroke = node.css("fill");
			});
		}
		for (outputId => info in box.getInstance().getOutputs()) {
			var grNode = box.addOutput(this, info.name, info.type);
			grNode.find(".node").attr("field", outputId);
			grNode.on("mousedown", function(e) {
				e.stopPropagation();
				var node = grNode.find(".node");
				isCreatingLink = FromOutput;
				startLinkNodeId = outputId;
				startLinkBox = box;
				edgeStyle.stroke = node.css("fill");
			});
		}

		box.generateProperties(this, config);

		return box;
	}

	function removeBox(box : Box, trackChanges = true) {
		removeEdges(box);
		box.dispose();
		listOfBoxes.remove(box);
	}

	function removeEdges(box : Box) {
		var length = listOfEdges.length;
		for (i in 0...length) {
			var edge = listOfEdges[length-i-1];
			if (edge.from == box || edge.to == box) {
				removeEdge(edge); // remove edge from listOfEdges
			}
		}
	}

	function removeEdge(edge : Edge) {
		edge.elt.remove();
		edge.to.inputs[edge.inputTo].removeAttr("hasLink");
		edge.to.inputs[edge.inputTo].parent().removeClass("hasLink");
		listOfEdges.remove(edge);
	}

	function replaceEdge(state : EdgeState, ?edge : Edge, ?node : JQuery, x : Int, y : Int) {
		switch (state) {
			case FromOutput:
				for (e in listOfEdges) {
					if (e.to.inputs[e.inputTo].is(node)) {
						isCreatingLink = FromOutput;
						startLinkNodeId = e.outputFrom;
						startLinkBox = e.from;
						edgeStyle.stroke = e.from.outputs[e.outputFrom].css("fill");
						removeEdge(e);
						createLink(x, y);
						return;
					}
				}
			case FromInput:
				for (e in listOfEdges) {
					if (e.to == edge.to && e.inputTo == edge.inputTo && e.from == edge.from && e.outputFrom == edge.outputFrom) {
						isCreatingLink = FromInput;
						startLinkNodeId = e.inputTo;
						startLinkBox = e.to;
						edgeStyle.stroke = e.from.outputs[e.outputFrom].css("fill");
						removeEdge(e);
						createLink(x, y);
						return;
					}
				}
			default:
				return;
		}
	}

	function error(str : String, ?idBox : Int) {
		statusBar.html(str);
		statusClose.show();
		statusBar.addClass("error");

		new Element(".box").removeClass("error");
		if (idBox != null) {
			var elt = new Element('#${idBox}');
			elt.addClass("error");
		}
	}

	function info(str : String) {
		statusBar.html(str);
		statusClose.show();
		statusBar.removeClass("error");
		new Element(".box").removeClass("error");
	}

	function createEdgeInEditorGraph(edge) {
		listOfEdges.push(edge);
		edge.to.inputs[edge.inputTo].attr("hasLink", "true");
		edge.to.inputs[edge.inputTo].parent().addClass("hasLink");

		edge.elt.on("mousedown", function(e) {
			e.stopPropagation();
			clearSelectionBoxes();
			this.currentEdge = edge;
			currentEdge.elt.addClass("selected");
		});
	}

	function createLink(clientX : Int, clientY : Int) {

		var nearestId = -1;
		var minDistNode = NODE_TRIGGER_NEAR;

		// checking nearest box
		var nearestBox = null;
		var minDist = 999999999999999.0;
		for (i in 0...listOfBoxes.length) {
			if (listOfBoxes[i].comment != null)
				continue;
			var tmpDist = distanceToBox(listOfBoxes[i], clientX, clientY);
			if (tmpDist < minDist) {
				minDist = tmpDist;
				nearestBox = listOfBoxes[i];
			}
		}
		if (nearestBox == null)
			return;

		// checking nearest node in the nearest box
		if (isCreatingLink == FromInput) {
			for (id => o in nearestBox.outputs) {
				var newMin = distanceToElement(o, clientX, clientY);
				if (newMin < minDistNode) {
					nearestId = id;
					minDistNode = newMin;
				}
			}
		} else {
			// input has one edge at most
			for (id => i in nearestBox.inputs) {
				var newMin = distanceToElement(i, clientX, clientY);
				if (newMin < minDistNode) {
					nearestId = id;
					minDistNode = newMin;
				}
			}
		}

		if (minDistNode < NODE_TRIGGER_NEAR && nearestId >= 0) {
			endLinkNodeId = nearestId;
			endLinkBox = nearestBox;
		} else {
			endLinkNodeId = -1;
			endLinkBox = null;
			minDistNode = null;
		}

		// create edge
		if (currentLink != null) currentLink.remove();
		if (isCreatingLink == FromInput) {
			currentLink = createCurve(startLinkBox.inputs[startLinkNodeId], endLinkBox?.outputs[endLinkNodeId], minDistNode, clientX, clientY, true);
		}
		else {
			currentLink = createCurve(startLinkBox.outputs[startLinkNodeId], endLinkBox?.inputs[endLinkNodeId], minDistNode, clientX, clientY, true);
		}
	}

	function createCurve(start : JQuery, end : JQuery, ?distance : Float, ?x : Float, ?y : Float, ?isDraft : Bool) {
		var offsetEnd;
		var offsetStart = start.offset();
		if (end != null) {
			offsetEnd = end.offset();
		} else {
			offsetEnd = { top : y, left : x };
		}

		if (isCreatingLink == FromInput) {
			var tmp = offsetStart;
			offsetStart = offsetEnd;
			offsetEnd = tmp;
		}
		var startX = lX(offsetStart.left) + Box.NODE_RADIUS;
		var startY = lY(offsetStart.top) + Box.NODE_RADIUS;
		var diffDistanceY = offsetEnd.top - offsetStart.top;
		var signCurveY = ((diffDistanceY > 0) ? -1 : 1);
		diffDistanceY = Math.abs(diffDistanceY);
		var valueCurveX = 100;
		var valueCurveY = 1;
		var maxDistanceY = 900;

		var curve = editor.curve(null,
							startX,
							startY,
							lX(offsetEnd.left) + Box.NODE_RADIUS,
							lY(offsetEnd.top) + Box.NODE_RADIUS,
							startX + valueCurveX * (Math.min(maxDistanceY, diffDistanceY)/maxDistanceY),
							startY + signCurveY * valueCurveY * (Math.min(maxDistanceY, diffDistanceY)/maxDistanceY),
							edgeStyle)
							.addClass("edge");
		editorMatrix.prepend(curve);
		if (isDraft)
			curve.addClass("draft");

		return curve;
	}

	function clearSelectionBoxes() {
		for(b in listOfBoxesSelected) b.setSelected(false);
		listOfBoxesSelected = [];
		if (this.currentEdge != null) {
			currentEdge.elt.removeClass("selected");
		}
	}

	function startUpdateViewPosition() {
		if (timerUpdateView != null)
			return;
		timerUpdateView = new Timer(0);
		timerUpdateView.run = function() {
			var posCursor = new Point(ide.mouseX - parent.offset().left, ide.mouseY - parent.offset().top);
			var wasUpdated = false;
			if (posCursor.x < BORDER_SIZE) {
				pan(new Point((BORDER_SIZE - posCursor.x)*SPEED_BORDER_MOVE, 0));
				wasUpdated = true;
			}
			if (posCursor.y < BORDER_SIZE) {
				pan(new Point(0, (BORDER_SIZE - posCursor.y)*SPEED_BORDER_MOVE));
				wasUpdated = true;
			}
			var rightBorder = parent.width() - BORDER_SIZE;
			if (posCursor.x > rightBorder) {
				pan(new Point((rightBorder - posCursor.x)*SPEED_BORDER_MOVE, 0));
				wasUpdated = true;
			}
			var botBorder = parent.height() - BORDER_SIZE;
			if (posCursor.y > botBorder) {
				pan(new Point(0, (botBorder - posCursor.y)*SPEED_BORDER_MOVE));
				wasUpdated = true;
			}
			mouseMoveFunction(ide.mouseX, ide.mouseY);
		};
	}

	function stopUpdateViewPosition() {
		if (timerUpdateView != null) {
			timerUpdateView.stop();
			timerUpdateView = null;
		}
	}

	function getGraphDims(?boxes) {
		if( boxes == null )
			boxes = listOfBoxes;
		if( boxes.length == 0 ) return null;
		var xMin = boxes[0].getX();
		var yMin = boxes[0].getY();
		var xMax = xMin + boxes[0].getWidth();
		var yMax = yMin + boxes[0].getHeight();
		for (i in 1...boxes.length) {
			var b = boxes[i];
			xMin = Math.min(xMin, b.getX());
			yMin = Math.min(yMin, b.getY());
			xMax = Math.max(xMax, b.getX() + b.getWidth());
			yMax = Math.max(yMax, b.getY() + b.getHeight());
		}
		var center = new IPoint(Std.int(xMin + (xMax - xMin)/2), Std.int(yMin + (yMax - yMin)/2));
		center.y += Std.int(editor.element.height()*CENTER_OFFSET_Y);
		return {
			xMin : xMin,
			yMin : yMin,
			xMax : xMax,
			yMax : yMax,
			center : center,
		};
	}

	function centerView() {
		if (listOfBoxes.length == 0) return;
		var dims = getGraphDims();
		var scale = Math.min(1, Math.min((editor.element.width() - 50) / (dims.xMax - dims.xMin), (editor.element.height() - 50) / (dims.yMax - dims.yMin)));

		transformMatrix[4] = editor.element.width()/2 - dims.center.x;
		transformMatrix[5] = editor.element.height()/2 - dims.center.y;

		transformMatrix[0] = scale;
		transformMatrix[3] = scale;

		var x = editor.element.width()/2;
		var y = editor.element.height()/2;

		transformMatrix[4] = x - (x - transformMatrix[4]) * scale;
		transformMatrix[5] = y - (y - transformMatrix[5]) * scale;

		updateMatrix();
	}

	function clampView() {
		if (listOfBoxes.length == 0) return;
		var dims = getGraphDims();

		var width = editor.element.width();
		var height = editor.element.height();
		var scale = transformMatrix[0];

		if( transformMatrix[4] + dims.xMin * scale > width )
			transformMatrix[4] = width - dims.xMin * scale;
		if( transformMatrix[4] + dims.xMax * scale < 0 )
			transformMatrix[4] = -1 * dims.xMax * scale;
		if( transformMatrix[5] + dims.yMin * scale > height )
			transformMatrix[5] = height - dims.yMin * scale;
		if( transformMatrix[5] + dims.yMax * scale < 0 )
			transformMatrix[5] = -1 * dims.yMax * scale;
	}

	function updateMatrix() {
		editorMatrix.attr({transform: 'matrix(${transformMatrix.join(' ')})'});
	}

	function zoom(scale : Float, x : Int, y : Int) {
		if (scale > 1 && transformMatrix[0] > MAX_ZOOM) {
			return;
		}

		transformMatrix[0] *= scale;
		transformMatrix[3] *= scale;

		x -= Std.int(editor.element.offset().left);
		y -= Std.int(editor.element.offset().top);

		transformMatrix[4] = x - (x - transformMatrix[4]) * scale;
		transformMatrix[5] = y - (y - transformMatrix[5]) * scale;

		clampView();
		updateMatrix();
	}

	function pan(p : Point) {
		transformMatrix[4] += p.x;
		transformMatrix[5] += p.y;

		clampView();
		updateMatrix();
	}

	function isVisible() : Bool {
		return editor.element.is(":visible");
	}

	// Useful method
	function isInside(b : Box, min : Point, max : Point) {
		if (max.x < b.getX() || min.x > b.getX() + b.getWidth())
			return false;
		if (max.y < b.getY() || min.y > b.getY() + b.getHeight())
			return false;

		return true;
	}

	function isFullyInside(b: Box, min : Point, max : Point) {
		if (min.x > b.getX() || max.x < b.getX() + b.getWidth())
			return false;
		if (min.y > b.getY() || max.y < b.getY() + b.getHeight())
			return false;

		return true;
	}

	function distanceToBox(b : Box, x : Int, y : Int) {
		var dx = Math.max(Math.abs(lX(x) - (b.getX() + (b.getWidth() / 2))) - b.getWidth() / 2, 0);
		var dy = Math.max(Math.abs(lY(y) - (b.getY() + (b.getHeight() / 2))) - b.getHeight() / 2, 0);
		return dx * dx + dy * dy;
	}
	function distanceToElement(element : JQuery, x : Int, y : Int) {
		if (element == null)
			return NODE_TRIGGER_NEAR+1;
		var dx = Math.max(Math.abs(x - (element.offset().left + element.width() / 2)) - element.width() / 2, 0);
		var dy = Math.max(Math.abs(y - (element.offset().top + element.height() / 2)) - element.height() / 2, 0);
		return dx * dx + dy * dy;
	}
	function gX(x : Float) : Float {
		return x*transformMatrix[0] + transformMatrix[4];
	}
	function gY(y : Float) : Float {
		return y*transformMatrix[3] + transformMatrix[5];
	}
	function gPos(x : Float, y : Float) : Point {
		return new Point(gX(x), gY(y));
	}
	function lX(x : Float) : Float {
		var screenOffset = editor.element.offset();
		x -= screenOffset.left;
		return (x - transformMatrix[4])/transformMatrix[0];
	}
	function lY(y : Float) : Float {
		var screenOffset = editor.element.offset();
		y -= screenOffset.top;
		return (y - transformMatrix[5])/transformMatrix[3];
	}
	function lPos(x : Float, y : Float) : Point {
		return new Point(lX(x), lY(y));
	}

}
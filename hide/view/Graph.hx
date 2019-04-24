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
import hrt.shgraph.ShaderType.SType;

enum EdgeState { None; FromInput; FromOutput; }
typedef NodeInfo = { name : String, description : String, key : String };

typedef Edge = { from : Box, nodeFrom : JQuery, to : Box, nodeTo : JQuery, elt : JQuery };

class Graph extends FileView {

	var parent : JQuery;
	var editor : SVG;
	var editorMatrix : JQuery;
	var statusBar : JQuery;

	var listOfClasses : Map<String, Array<NodeInfo>>;
	var addMenu : JQuery;
	var selectedNode : JQuery;

	var contextMenu : JQuery;

	var listOfBoxes : Array<Box> = [];
	var listOfEdges : Array<Edge> = [];

	var transformMatrix : Array<Float> = [1, 0, 0, 1, 0, 0];
	var isPanning : Bool = false;
	static var MAX_ZOOM = 1.2;

	// used for moving when mouse is close to borders
	static var BORDER_SIZE = 75;
	static var SPEED_BORDER_MOVE = 0.05;
	var timerUpdateView : Timer;

	// used for selection
	var listOfBoxesSelected : Array<Box> = [];
	var recSelection : JQuery;
	var startRecSelection : h2d.col.Point;
	var lastClickDrag : h2d.col.Point;
	var lastClickPan : h2d.col.Point;

	// used to build edge
	static var NODE_TRIGGER_NEAR = 2000.0;
	var isCreatingLink : EdgeState = None;
	var startLinkBox : Box;
	var endLinkBox : Box;
	var startLinkGrNode : JQuery;
	var endLinkNode : JQuery;
	var currentLink : JQuery; // draft of edge

	// used for deleting
	var currentEdge : Edge;

	override function onDisplay() {
		element.html('
			<div class="flex vertical">
				<div class="flex-elt graph-view">
					<div class="heaps-scene" tabindex="0" >
					</div>
					<div id="rightPanel" class="tabs">
					</div>
				</div>
			</div>');
		parent = element.find(".heaps-scene");
		editor = new SVG(parent);
		statusBar = new Element('<div id="status-bar" ><span> </span></div>').appendTo(parent).find("span");

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


		parent.on("mouseup", function(e) {
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

		parent.on("keydown", function(e) {

			if (e.keyCode == 46) {
				if (currentEdge != null) {
					removeEdge(currentEdge);
				}
				if (listOfBoxesSelected.length > 0) {
					for (b in listOfBoxesSelected) {
						removeBox(b);
					}
					clearSelectionBoxes();
				}
				return;
			} else if (e.keyCode == 32) {

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
			startUpdateViewPosition();
			// TODO: handle moving edge => disconnect closest node
			// try to use the same code when user clicks on input node already connected and here
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

			for (b in listOfBoxesSelected) {
				b.setPosition(b.getX() + dx, b.getY() + dy);
				updatePosition(b.getId(), b.getX(), b.getY());
				// move edges from and to this box
				for (edge in listOfEdges) {
					if (edge.from == b || edge.to == b) {
						edge.elt.remove();
						edge.elt = createCurve(edge.nodeFrom, edge.nodeTo);

						edge.elt.on("mousedown", function(e) {
							e.stopPropagation();
							clearSelectionBoxes();
							this.currentEdge = edge;
							currentEdge.elt.addClass("selected");
						});
					}
				}
			}
			lastClickDrag.x = lX(clientX);
			lastClickDrag.y = lY(clientY);
			return;
		}
	}

	dynamic function updatePosition(id : Int, x : Float, y : Float) { }

	function addBox(p : Point, nodeClass : Class<ShaderNode>, node : ShaderNode) {

		var className = std.Type.getClassName(nodeClass);
		className = className.substr(className.lastIndexOf(".") + 1);

		var box = new Box(editor, editorMatrix, p.x, p.y, node);
		var elt = box.getElement();
		elt.mousedown(function(e) {
			if (e.button != 0)
				return;
			e.stopPropagation();

			lastClickDrag = new Point(lX(e.clientX), lY(e.clientY));
			if (!box.selected) {
				if (!e.ctrlKey) {
					// when not group selection and click on box not selected
					clearSelectionBoxes();
					listOfBoxesSelected = [box];
				} else
					listOfBoxesSelected.push(box);
				box.setSelected(true);
			}
		});
		elt.mouseup(function(e) {
			if (e.button != 0)
				return;
			lastClickDrag = null;
			if (listOfBoxesSelected.length == 1 && box.selected && !e.ctrlKey) {
				clearSelectionBoxes();
			}
		});
		listOfBoxes.push(box);


		var fields = std.Type.getInstanceFields(nodeClass);

		var metas = haxe.rtti.Meta.getFields(nodeClass);
		var metasParent = haxe.rtti.Meta.getFields(std.Type.getSuperClass(nodeClass));
		for (f in fields) {
			var m = Reflect.field(metas, f);
			if (m == null) {
				m = Reflect.field(metasParent, f);
				if (m == null) continue;
			}
			if (Reflect.hasField(m, "input")) {
				var inputMeta : Array<Dynamic> = Reflect.field(m, "input");
				var name : String = (m.input != null && m.input.length > 0) ? inputMeta[0] : "input";

				var defaultValue = null;
				if (m.input.length >= 2 && inputMeta[1]) {
					defaultValue = Reflect.field(box.getInstance(), 'prop_${f}');
					if (defaultValue == null) {
						defaultValue = "0";
					}
				}
				var grNode = box.addInput(editor, name, defaultValue);
				if (defaultValue != null) {
					var fieldEditInput = grNode.find("input");
					fieldEditInput.on("change", function(ev) {
						var tmpValue = Std.parseFloat(fieldEditInput.val());
						if (Math.isNaN(tmpValue) ) {
							fieldEditInput.addClass("error");
						} else {
							Reflect.setField(box.getInstance(), 'prop_${f}', tmpValue);
							fieldEditInput.val(tmpValue);
							fieldEditInput.removeClass("error");
						}
					});
				}
				grNode.find(".node").attr("field", f);
				grNode.on("mousedown", function(e : js.jquery.Event) {
					e.stopPropagation();
					var node = grNode.find(".node");
					if (node.attr("hasLink") != null) {
						isCreatingLink = FromOutput;
						for (edge in listOfEdges) {
							if (edge.nodeTo.is(node)) {
								startLinkGrNode = edge.nodeFrom.parent();
								startLinkBox = edge.from;
								setAvailableInputNodes(edge.from, edge.nodeFrom.attr("field"));
								removeEdge(edge);
								createLink(e.clientX, e.clientY);
								return;
							}
						}
					}
					isCreatingLink = FromInput;
					startLinkGrNode = grNode;
					startLinkBox = box;
					setAvailableOutputNodes(box, grNode.find(".node").attr("field"));
				});
			} else if (Reflect.hasField(m, "output")) {
				var name : String = (m.output != null && m.output.length > 0) ? Reflect.field(m, "output")[0] : "output";
				var grNode = box.addOutput(editor, name);
				grNode.find(".node").attr("field", f);
				grNode.on("mousedown", function(e) {
					e.stopPropagation();
					isCreatingLink = FromOutput;
					startLinkGrNode = grNode;
					startLinkBox = box;
					setAvailableInputNodes(box, startLinkGrNode.find(".node").attr("field"));
				});
			}
		}
		box.generateProperties(editor);
	}

	function removeBox(box : Box) {
		var length = listOfEdges.length;
		for (i in 0...length) {
			var edge = listOfEdges[length-i-1];
			if (edge.from == box || edge.to == box) {
				removeEdge(edge); // remove edge from listOfEdges
			}
		}
		box.dispose();
		listOfBoxes.remove(box);
	}

	function removeEdge(edge : Edge) {
		edge.elt.remove();
		edge.nodeTo.removeAttr("hasLink");
		edge.nodeTo.parent().removeClass("hasLink");
		listOfEdges.remove(edge);
	}

	function setAvailableInputNodes(boxOutput : Box, field : String) {
		var type = boxOutput.getInstance().getOutputType(field);
		var sType : SType;
		if (type == null) {
			sType = boxOutput.getInstance().getOutputInfo(field);
		} else {
			sType = ShaderType.getType(type);
		}

		for (box in listOfBoxes) {
			for (input in box.inputs) {
				if (box.getInstance().checkTypeAndCompatibilyInput(input.attr("field"), sType)) {
					input.addClass("nodeMatch");
				}
			}
		}
	}

	function setAvailableOutputNodes(boxInput : Box, field : String) {
		for (box in listOfBoxes) {
			for (output in box.outputs) {
				var outputField = output.attr("field");
				var type = box.getInstance().getOutputType(outputField);
				var sType : SType;
				if (type == null) {
					sType = box.getInstance().getOutputInfo(outputField);
				} else {
					sType = ShaderType.getType(type);
				}
				if (boxInput.getInstance().checkTypeAndCompatibilyInput(field, sType)) {
					output.addClass("nodeMatch");
				}
			}
		}
	}

	function clearAvailableNodes() {
		editor.element.find(".nodeMatch").removeClass("nodeMatch");
	}

	function error(str : String, ?idBox : Int) {
		statusBar.html(str);
		statusBar.addClass("error");

		new Element(".box").removeClass("error");
		if (idBox != null) {
			var elt = new Element('#${idBox}');
			elt.addClass("error");
		}
	}

	function info(str : String) {
		statusBar.html(str);
		statusBar.removeClass("error");
		new Element(".box").removeClass("error");
	}

	function createEdgeInEditorGraph(edge) {
		listOfEdges.push(edge);
		edge.nodeTo.attr("hasLink", "true");
		edge.nodeTo.parent().addClass("hasLink");

		edge.elt.on("mousedown", function(e) {
			e.stopPropagation();
			clearSelectionBoxes();
			this.currentEdge = edge;
			currentEdge.elt.addClass("selected");
		});
	}

	function createLink(clientX : Int, clientY : Int) {

		var nearestNode = null;
		var minDistNode = NODE_TRIGGER_NEAR;

		// checking nearest box
		var nearestBox = listOfBoxes[0];
		var minDist = distanceToBox(nearestBox, clientX, clientY);
		for (i in 1...listOfBoxes.length) {
			var tmpDist = distanceToBox(listOfBoxes[i], clientX, clientY);
			if (tmpDist < minDist) {
				minDist = tmpDist;
				nearestBox = listOfBoxes[i];
			}
		}

		// checking nearest node in the nearest box
		if (isCreatingLink == FromInput) {
			var startIndex = 0;
			while (startIndex < nearestBox.outputs.length && !nearestBox.outputs[startIndex].hasClass("nodeMatch")) {
				startIndex++;
			}
			if (startIndex < nearestBox.outputs.length) {
				nearestNode = nearestBox.outputs[startIndex];
				minDistNode = distanceToElement(nearestNode, clientX, clientY);
				for (i in startIndex+1...nearestBox.outputs.length) {
					if (!nearestBox.outputs[i].hasClass("nodeMatch"))
						continue;
					var tmpDist = distanceToElement(nearestBox.outputs[i], clientX, clientY);
					if (tmpDist < minDistNode) {
						minDistNode = tmpDist;
						nearestNode = nearestBox.outputs[i];
					}
				}
			}
		} else {
			// input has one edge at most
			var startIndex = 0;
			while (startIndex < nearestBox.inputs.length && !nearestBox.inputs[startIndex].hasClass("nodeMatch")) {
				startIndex++;
			}
			if (startIndex < nearestBox.inputs.length) {
				nearestNode = nearestBox.inputs[startIndex];
				minDistNode = distanceToElement(nearestNode, clientX, clientY);
				for (i in startIndex+1...nearestBox.inputs.length) {
					if (!nearestBox.inputs[i].hasClass("nodeMatch"))
						continue;
					var tmpDist = distanceToElement(nearestBox.inputs[i], clientX, clientY);
					if (tmpDist < minDistNode) {
						minDistNode = tmpDist;
						nearestNode = nearestBox.inputs[i];
					}
				}
			}
		}
		if (minDistNode < NODE_TRIGGER_NEAR) {
			endLinkNode = nearestNode;
			endLinkBox = nearestBox;
		} else {
			endLinkNode = null;
			endLinkBox = null;
		}

		// create edge
		if (currentLink != null) currentLink.remove();
		currentLink = createCurve(startLinkGrNode.find(".node"), nearestNode, minDistNode, clientX, clientY, true);

	}

	function createCurve(start : JQuery, end : JQuery, ?distance : Float, ?x : Float, ?y : Float, ?isDraft : Bool) {
		var offsetEnd;
		var offsetStart = start.offset();
		if (distance == null || distance < NODE_TRIGGER_NEAR) {
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
							startY + signCurveY * valueCurveY * (Math.min(maxDistanceY, diffDistanceY)/maxDistanceY))
							.addClass("edge");
		editorMatrix.prepend(curve);
		if (isDraft)
			curve.addClass("draft");

		return curve;
	}

	function customContextMenu( elts : Array<Element> ) {
		closeCustomContextMenu();

		if (elts.length == 0) return;

		contextMenu = new Element('
		<div id="context-menu">
			<div id="options"></div>
		</div>').appendTo(parent);

		var options = contextMenu.find("#options");

		var posCursor = new IPoint(Std.int(ide.mouseX - parent.offset().left), Std.int(ide.mouseY - parent.offset().top));

		contextMenu.on("mousedown", function(e) {
			e.stopPropagation();
		});

		contextMenu.on("click", function(e) {
			closeCustomContextMenu();
			e.stopPropagation();
		});

		for (elt in elts) {
			elt.appendTo(options);
		}

		contextMenu.css("left", Math.min(posCursor.x, element.width() - contextMenu.width() - 5));
		contextMenu.css("top", Math.min(posCursor.y, element.height() - contextMenu.height() - 5));
	}

	function closeCustomContextMenu() {
		if (contextMenu != null) {
			contextMenu.remove();
			contextMenu = null;
		}
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

	function centerView() {
		var xMin = listOfBoxes[0].getX();
		var yMin = listOfBoxes[0].getY();
		var xMax = xMin + listOfBoxes[0].getWidth();
		var yMax = yMin + listOfBoxes[0].getHeight();
		for (i in 1...listOfBoxes.length) {
			var b = listOfBoxes[i];
			xMin = Math.min(xMin, b.getX());
			yMin = Math.min(yMin, b.getY());
			xMax = Math.max(xMax, b.getX() + b.getWidth());
			yMax = Math.max(yMax, b.getY() + b.getHeight());
		}
		var center = new IPoint(Std.int(xMin + (xMax - xMin)/2), Std.int(yMin + (yMax - yMin)/2));
		var scale = Math.min(MAX_ZOOM, Math.min((editor.element.width() - 50) / (xMax - xMin), (editor.element.height() - 50) / (yMax - yMin)));

		transformMatrix[4] = editor.element.width()/2 - center.x;
		transformMatrix[5] = editor.element.height()/2 - center.y;

		transformMatrix[0] = scale;
		transformMatrix[3] = scale;

		var x = editor.element.width()/2;
		var y = editor.element.height()/2;

		transformMatrix[4] = x - (x - transformMatrix[4]) * scale;
		transformMatrix[5] = y - (y - transformMatrix[5]) * scale;

		updateMatrix();
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

		updateMatrix();
	}

	function pan(p : Point) {
		transformMatrix[4] += p.x;
		transformMatrix[5] += p.y;

		updateMatrix();
	}

	function IsVisible() : Bool {
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
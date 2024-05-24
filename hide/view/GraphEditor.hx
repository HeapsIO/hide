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

import hide.view.GraphInterface.IGraphEditor;
import hide.view.GraphInterface.IGraphNode;
import hide.view.GraphInterface.Edge;

enum EdgeState { None; FromInput; FromOutput; }

typedef UndoFn = (isUndo : Bool) -> Void;
typedef UndoBuffer = Array<UndoFn>;
typedef SelectionUndoSave = {newSelections: Map<Int, Bool>, buffer: UndoBuffer};

typedef CopySelectionData = {
	nodes: Array<{id: Int, serData: Dynamic}>,
	edges: Array<Edge>,
};

@:access(hide.view.shadereditor.Box)
class GraphEditor extends hide.comp.Component {
	public var editor : hide.view.GraphInterface.IGraphEditor;
	var heapsScene : JQuery;
	var editorDisplay : SVG;
	var editorMatrix : JQuery;
	public var config : hide.Config;


	public var previewsScene : hide.comp.Scene;

	var boxes : Map<Int, Box> = [];

	var transformMatrix : Array<Float> = [1, 0, 0, 1, 0, 0];
	var isPanning : Bool = false;
	static var MAX_ZOOM = 2.0;
	static var CENTER_OFFSET_Y = 0.1; // percent of height

	// used for moving when mouse is close to borders
	static var BORDER_SIZE = 50;
	static var SPEED_BORDER_MOVE = 0.05;
	var timerUpdateView : Timer;
	// used for selection
	var boxesSelected : Map<Int, Bool> = [];
	var boxesToMove : Map<Int, Bool> = [];
	var undoSave : Any;
	var recSelection : JQuery;
	var startRecSelection : h2d.col.Point;
	var lastClickDrag : h2d.col.Point;
	var lastClickPan : h2d.col.Point;

	// used to build edge
	static final NODE_TRIGGER_NEAR = 2000.0;

	var selectedNode : JQuery;

	// used for deleting

	// aaaaaa
	var domain : hrt.shgraph.ShaderGraph.Domain;

	var addMenu : JQuery;

	var edgeCreationCurve : JQuery = null;
	var edgeCreationOutput : Null<Int> = null;
	var edgeCreationInput : Null<Int> = null;
	var edgeCreationMode : EdgeState = None;
	var lastCurveX : Float = 0;
	var lastCurveY : Float = 0;

	public var currentUndoBuffer : UndoBuffer = [];



	var outputsToInputs : hrt.tools.OneToMany = new hrt.tools.OneToMany();
	// Maps a packIO of an input to it's visual link in the graph
	var edges : Map<Int, JQuery> = [];

	public function new(config: hide.Config, editor: hide.view.GraphInterface.IGraphEditor, parent: Element = null) {
		super(parent, new Element('
		<div class="flex vertical" >
			<div class="flex-elt graph-view" tabindex="0" >
				<div class="heaps-scene" tabindex="1" >
				</div>
			</div>
		</div>'));
		this.config = config;
		this.editor = editor;
	}

	public function addUndo(fn: UndoFn) {
		currentUndoBuffer.push(fn);
		fn(false);
	}

	public function commitUndo() {
		if (currentUndoBuffer.length <= 0) {
			return;
		}
		var buffer = currentUndoBuffer;
		editor.getUndo().change(Custom(execUndo.bind(buffer)));
		currentUndoBuffer = [];
	}

	public function execUndo(buffer: UndoBuffer, isUndo : Bool) {
		if (isUndo) {
			for (i in 0...buffer.length) {
				buffer[buffer.length - i - 1](isUndo);
			}
		} else {
			for (i in 0...buffer.length) {
				buffer[i](isUndo);
			}
		}
	}



	public function onDisplay() {
		heapsScene = element.find(".heaps-scene");
		editorDisplay = new SVG(heapsScene);
		editorDisplay.element.attr("id", "graph-root");


		editorMatrix = editorDisplay.group(editorDisplay.element);

		var keys = new hide.ui.Keys(element);
		keys.register("delete", deleteSelection);
		keys.register("sceneeditor.focus", centerView);
		keys.register("copy", copySelection);
		keys.register("paste", paste);
		keys.register("cut", cutSelection);
		keys.register("shadergraph.hide", onHide);
		keys.register("selectAll", selectAll);
		keys.register("shadergraph.comment", commentFromSelection);
		keys.register("duplicateInPlace", duplicateSelection);
		keys.register("duplicate", duplicateSelection);

		var miniPreviews = new Element('<div class="mini-preview"></div>');
		heapsScene.prepend(miniPreviews);
		previewsScene = new hide.comp.Scene(config, null, miniPreviews);
		previewsScene.onReady = onMiniPreviewReady;
		previewsScene.onUpdate = onMiniPreviewUpdate;

		// rectangle Selection
		var rawheaps = heapsScene.get(0);
		rawheaps.addEventListener("pointerdown", function(e) {

			if (e.button == 0) {
				startRecSelection = new Point(lX(e.clientX), lY(e.clientY));
				// if (currentEdge != null) {
				// 	currentEdge.elt.removeClass("selected");
				// 	currentEdge = null;
				// }

				var save : SelectionUndoSave ={newSelections: new Map<Int, Bool>(), buffer: new UndoBuffer()};
				undoSave = save;

				closeAddMenu();
				clearSelectionBoxesUndo(save.buffer);
				finalizeUserCreateEdge();
				rawheaps.setPointerCapture(e.pointerId);
				e.stopPropagation();
				return;
			}
			if (e.button == 1) {
				lastClickPan = new Point(e.clientX, e.clientY);
				isPanning = true;
				return;
			}

			if (e.button == 2) {
				openAddMenu();
				e.preventDefault();
				e.stopPropagation();
			}
		});

		heapsScene.on("contextmenu", function(e) {
			e.preventDefault();
		});

		heapsScene.on("pointermove", function(e : js.jquery.Event) {
			e.preventDefault();
			e.cancelBubble=true;
    		e.returnValue=false;
			mouseMoveFunction(e.clientX, e.clientY);
		});

		var document = new Element(js.Browser.document);
		document.on("pointerup", function(e) {
			if(timerUpdateView != null)
				stopUpdateViewPosition();
			if (e.button == 0) {
				// Stop rectangle selection
				if (edgeCreationInput != null || edgeCreationOutput != null) {
					if (edgeCreationInput != null && edgeCreationOutput != null) {
						finalizeUserCreateEdge();
						e.stopPropagation();
						return;
					}
					else {
						openAddMenu();
						e.stopPropagation();
						return;
					}
				}
				lastClickDrag = null;
				startRecSelection = null;
				if (recSelection != null) {
					recSelection.remove();
					recSelection = null;

					var save : SelectionUndoSave = undoSave;

					for (id => _ in save.newSelections) {
						opSelect(id, true, save.buffer);
					}
					currentUndoBuffer = save.buffer;
					commitUndo();
					undoSave = null;
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
		heapsScene.on("wheel", function(e) {
			if (e.originalEvent.deltaY < 0) {
				zoom(1.1, e.clientX, e.clientY);
			} else {
				zoom(0.9, e.clientX, e.clientY);
			}
		});

		boxes = [];
		outputsToInputs.clear();

		updateMatrix();

		reloadInternal();
	}

	var reloadQueued = false;
	public function reload() {
		reloadQueued = true;
	}

	function reloadInternal() {
		reloadQueued = false;
		boxesSelected.clear();
		for (box in boxes) {
			box.dispose();
		}
		boxes.clear();
		outputsToInputs.clear();

		for (e in edges) {
			e.remove();
		}
		edges.clear();

		var nodes = editor.getNodes();
		for (node in nodes) {
			addBox(node);
		}

		var edges = editor.getEdges();
		for (edge in edges) {
			createEdge(edge);
		}
	}

	var boxToPreview : Map<Box, h2d.Bitmap>;
	var miniPreviewInitTimeout = 0;
	function onMiniPreviewReady() {
		if (previewsScene.s2d == null) {
			miniPreviewInitTimeout ++;
			if (miniPreviewInitTimeout > 10)
				throw "Couldn't initialize background previews";
			haxe.Timer.delay(() -> onMiniPreviewReady, 100);
			return;
		}
		var bg = new h2d.Flow(previewsScene.s2d);
		bg.fillHeight = true;
		bg.fillWidth = true;
		bg.backgroundTile = h2d.Tile.fromColor(0x333333);
		boxToPreview = [];

		var identity : h3d.Matrix = new h3d.Matrix();
		identity.identity();
		@:privateAccess previewsScene.s2d.renderer.globals.set("camera.viewProj", identity);
		@:privateAccess previewsScene.s2d.renderer.globals.set("camera.position", identity.getPosition());
	}

	/** If this function returns false, the preview update will be skipped**/
	public dynamic function onPreviewUpdate() : Bool {
		return true;
	}

	/** Called for each visible preview in the graph editor **/
	public dynamic function onNodePreviewUpdate(node: IGraphNode, bitmap: h2d.Bitmap) : Void {

	}

	function onMiniPreviewUpdate(dt: Float) {
		@:privateAccess
		/*if (sceneEditor?.scene?.s3d?.renderer?.ctx?.time != null) {
			sceneEditor.scene.s3d.renderer.ctx.time = previewsScene.s3d.renderer.ctx.time;
		}*/

		if (reloadQueued) {
			reloadInternal();
			return;
		}

		if (!onPreviewUpdate())
			return;

		var newBoxToPreview : Map<Box, h2d.Bitmap> = [];
		for (box in boxes) {
			if (box.info.preview == null) {
				continue;
			}
			var preview = boxToPreview.get(box);
			if (preview == null) {
				var bmp = new h2d.Bitmap(h2d.Tile.fromColor(0xFF00FF,1,1), previewsScene.s2d);
				bmp.blendMode = None;
				preview = bmp;
			} else {
				boxToPreview.remove(box);
			}
			newBoxToPreview.set(box,preview);
		}

		for (preview in boxToPreview) {
			preview.remove();
		}
		boxToPreview = newBoxToPreview;

		var sceneW = editorDisplay.element.width();
		var sceneH = editorDisplay.element.height();

		for (box => preview in boxToPreview) {
			preview.visible = box.info.preview.getVisible();
			if (!preview.visible)
				continue;

			preview.x = gX(box.x);
			preview.y = gY(box.y + box.getHeight());
			preview.scaleX = transformMatrix[0] * box.width / preview.tile.width;
			preview.scaleY = transformMatrix[3] * box.width / preview.tile.height;

			if (preview.x + preview.scaleX < 0 || preview.x > sceneW || preview.y + preview.scaleY < 0 || preview.y > sceneH) {
				preview.visible = false;
				continue;
			}

			onNodePreviewUpdate(box.node, preview);
		}
	}


	function deleteSelection() {
		cleanupCreateEdge();

		currentUndoBuffer = [];

		if (boxesSelected.iterator().hasNext()) {

			for (id => _ in boxesSelected) {
				var box = boxes.get(id);
				opSelect(id, false, currentUndoBuffer);
				removeBoxEdges(box, currentUndoBuffer);
				opBox(box.node, false, currentUndoBuffer);
			}

			commitUndo();
		}
	}

	function opMove(box: Box, x: Float, y: Float, undoBuffer: UndoBuffer) {
		box.node.getPos(Box.tmpPoint);
		var prevX = Box.tmpPoint.x;
		var prevY = Box.tmpPoint.y;
		if (prevX == x && prevY == y)
			return;
		var id = box.node.getId();
		function exec(isUndo: Bool) {
			var x = !isUndo ? x : prevX;
			var y = !isUndo ? y : prevY;
			var box = boxes[id];
			Box.tmpPoint.set(x,y);
			box.node.setPos(Box.tmpPoint);
			moveBox(box, x, y);
		}
		exec(false);
		undoBuffer.push(exec);
	}

	public function opResize(box: Box, w: Float, h: Float, undoBuffer: UndoBuffer) {
		box.info.comment.getSize(Box.tmpPoint);
		var id = box.node.getId();
		var prevW = Box.tmpPoint.x;
		var prevH = Box.tmpPoint.y;
		function exec(isUndo : Bool) {
			var box = boxes.get(id);
			var vw = !isUndo ? w : prevW;
			var vh = !isUndo ? h : prevH;
			Box.tmpPoint.set(vw, vh);
			box.info.comment.setSize(Box.tmpPoint);
			box.width = Std.int(vw);
			box.height = Std.int(vh);
			box.refreshBox();
		}

		exec(false);
		undoBuffer.push(exec);
	}

	function opSelect(id: Int, doSelect: Bool, undoBuffer: UndoBuffer) {
		var exec = function(isUndo: Bool) {
			if (!doSelect) isUndo = !isUndo;
			if (!isUndo) {
				boxesSelected.set(id, true);
				var box = boxes[id];
				box.setSelected(true);
			} else {
				boxesSelected.remove(id);
				var box = boxes[id];
				box.setSelected(false);
			}
		}
		undoBuffer.push(exec);
		exec(false);
	}

	static var lastOpenAddMenuPoint = new Point();
	function openAddMenu(x : Int = 0, y : Int = 0) {

		var boundsWidth = Std.int(element.width());
		var boundsHeight = Std.int(element.height());

		lastOpenAddMenuPoint.set(lX(ide.mouseX), lY(ide.mouseY));

		var posCursor = new Point(Std.int(ide.mouseX - heapsScene.offset().left) + x, Std.int(ide.mouseY - heapsScene.offset().top) + y);
		if( posCursor.x < 0 )
			posCursor.x = 0;
		if( posCursor.y < 0)
			posCursor.y = 0;

		if (addMenu != null) {
			var menuWidth = Std.parseInt(addMenu.css("width")) + 10;
			var menuHeight = Std.parseInt(addMenu.css("height")) + 10;
			if( posCursor.x + menuWidth > boundsWidth )
				posCursor.x = boundsWidth - menuWidth;
			if( posCursor.y + menuHeight > boundsHeight )
				posCursor.y = boundsHeight - menuHeight;

			var input = addMenu.find("#search-input");
			input.val("");
			addMenu.show();
			input.focus();

			addMenu.css("left", posCursor.x);
			addMenu.css("top", posCursor.y);

			for (c in addMenu.find("#results").children().elements()) {
				c.show();
			}
			return;
		}

		addMenu = new Element('
		<div id="add-menu">
			<div class="search-container">
				<div class="icon" >
					<i class="ico ico-search"></i>
				</div>
				<div class="search-bar" >
					<input type="text" id="search-input" autocomplete="off" >
				</div>
			</div>
			<div id="results">
			</div>
		</div>').appendTo(heapsScene);

		addMenu.on("pointerdown", function(e) {
			e.stopPropagation();
		});

		addMenu.on("blur", function(e) {
			closeAddMenu();
		});

		var results = addMenu.find("#results");
		results.on("wheel", function(e) {
			e.stopPropagation();
		});

		var nodes = editor.getAddNodesMenu();
		var prevGroup = null;
		for (i => node in nodes) {
			if (node.group != prevGroup) {
				new Element('
				<div class="group" >
					<span> ${node.group} </span>
				</div>').appendTo(results);
				prevGroup = node.group;
			}

			new Element('
				<div node="$i" >
					<span> ${node.name} </span> <span> ${node.description} </span>
				</div>').appendTo(results);
		}

		var menuWidth = Std.parseInt(addMenu.css("width")) + 10;
		var menuHeight = Std.parseInt(addMenu.css("height")) + 10;
		if( posCursor.x + menuWidth > boundsWidth )
			posCursor.x = boundsWidth - menuWidth;
		if( posCursor.y + menuHeight > boundsHeight )
			posCursor.y = boundsHeight - menuHeight;
		addMenu.css("left", posCursor.x);
		addMenu.css("top", posCursor.y);

		var input = addMenu.find("#search-input");
		input.focus();
		var divs = new Element("#results > div");
		input.on("keydown", function(ev) {
			if (ev.keyCode == 38 || ev.keyCode == 40) {
				ev.stopPropagation();
				ev.preventDefault();

				if (this.selectedNode != null)
					this.selectedNode.removeClass("selected");

				var selector = "div[node]:not([style*='display: none'])";
				var elt = this.selectedNode;

				if (ev.keyCode == 38) {
					do {
						elt = elt.prev();
					} while (elt.length > 0 && !elt.is(selector));
				} else if (ev.keyCode == 40) {
					do {
						elt = elt.next();
					} while (elt.length > 0 && !elt.is(selector));
				}
				if (elt.length == 1) {
					this.selectedNode = elt;
				}
				if (this.selectedNode != null)
					this.selectedNode.addClass("selected");

				var offsetDiff = this.selectedNode.offset().top - results.offset().top;
				if (offsetDiff > 225) {
					results.scrollTop((offsetDiff-225)+results.scrollTop());
				} else if (offsetDiff < 35) {
					results.scrollTop(results.scrollTop()-(35-offsetDiff));
				}
			}
		});

		function doAdd() {
			var key = Std.parseInt(this.selectedNode.attr("node"));
			//var posCursor = new Point(lX(ide.mouseX - 25), lY(ide.mouseY - 10));

			var instance = nodes[key].onConstructNode();

			var createLinkInput = edgeCreationInput;
			var createLinkOutput = edgeCreationOutput;
			var fromInput = createLinkInput != null;


			if (createLinkInput != null) {
				createLinkOutput = packIO(instance.getId(), 0);
			}
			else if (createLinkOutput != null) {
				createLinkInput = packIO(instance.getId(), 0);
			}

			var pos = new h2d.col.Point();
			pos.load(lastOpenAddMenuPoint);
			if (createLinkInput != null) {
				pos.set(lastCurveX, lastCurveY);
			}
			cleanupCreateEdge();

			instance.setPos(pos);
			opBox(instance, true, currentUndoBuffer);
			if (createLinkInput != null && createLinkOutput != null) {
				var box = boxes[instance.getId()];
				var x = (fromInput ? @:privateAccess box.width : 0) - Box.NODE_RADIUS;
				var y = box.getNodeHeight(0) - Box.NODE_RADIUS;
				opMove(boxes[instance.getId()], pos.x - x, pos.y - y, currentUndoBuffer);
				opEdge(createLinkOutput, createLinkInput, true, currentUndoBuffer);
			}

			commitUndo();
			closeAddMenu();
		}

		input.on("keyup", function(ev) {
			if (ev.keyCode == 38 || ev.keyCode == 40) {
				return;
			}

			if (ev.keyCode == 13) {
				doAdd();
			} else {
				if (this.selectedNode != null)
					this.selectedNode.removeClass("selected");
				var value = StringTools.trim(input.val());
				var children = divs.elements();
				var isFirst = true;
				var lastGroup = null;
				for (elt in children) {
					if (elt.hasClass("group")) {
						lastGroup = elt;
						elt.hide();
						continue;
					}
					if (value.length == 0 || elt.children().first().html().toLowerCase().indexOf(value.toLowerCase()) != -1) {
						if (isFirst) {
							this.selectedNode = elt;
							isFirst = false;
						}
						elt.show();
						if (lastGroup != null)
							lastGroup.show();
					} else {
						elt.hide();
					}
				}
				if (this.selectedNode != null)
					this.selectedNode.addClass("selected");
			}
		});
		divs.on("pointerover", function(ev) {
			if (ev.currentTarget.classList.contains("group")) {
				return;
			}
			if (this.selectedNode != null)
				this.selectedNode.removeClass("selected");
			this.selectedNode = new Element(ev.currentTarget); // Todo : not make this jquery
			this.selectedNode.addClass("selected");
		});
		divs.on("pointerup", function(ev) {
			if (ev.currentTarget.classList.contains("group")) {
				return;
			}

			doAdd();
			ev.stopPropagation();
		});
	}

	function closeAddMenu() {
		if (addMenu != null) {
			addMenu.hide();
			//heapsScene.focus();
		}
	}

	function mouseMoveFunction(clientX : Int, clientY : Int) {
		if (addMenu?.is(":visible"))
			return;
		if (edgeCreationInput != null || edgeCreationOutput != null) {
			startUpdateViewPosition();
			createLink(clientX, clientY);
			return;
		}
		// Moving edge
		/*if (currentEdge != null) {
			var distOutput = distanceToElement(currentEdge.from.outputs[currentEdge.outputFrom], clientX, clientY);
			var distInput = distanceToElement(currentEdge.to.inputs[currentEdge.inputTo], clientX, clientY);

			if (distOutput > distInput) {
				replaceEdge(FromOutput, currentEdge.to.inputs[currentEdge.inputTo], clientX, clientY);
			} else {
				replaceEdge(FromInput, currentEdge, clientX, clientY);
			}
			currentEdge = null;
			return;
		}*/
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
			recSelection = editorDisplay.rect(editorMatrix, xMin, yMin, xMax - xMin, yMax - yMin).addClass("rect-selection");

			var save : SelectionUndoSave = undoSave;

			for (box in boxes) {
				var shouldSelect = isInside(box, new Point(xMin, yMin), new Point(xMax, yMax));
				if (shouldSelect) {
					if (box.info.comment != null) {
						shouldSelect = isFullyInside(box, new Point(xMin, yMin), new Point(xMax, yMax));
					}
				}

				if (shouldSelect) {
					box.setSelected(true);
					save.newSelections.set(box.node.getId(), true);
				} else {
					box.setSelected(false);
					save.newSelections.remove(box.node.getId());
				}
			}
			return;
		}

		// Move selected boxes
		if (boxesSelected.iterator().hasNext() && lastClickDrag != null) {
			startUpdateViewPosition();
			var dx = (lX(clientX) - lastClickDrag.x);
			var dy = (lY(clientY) - lastClickDrag.y);


			for (id => _  in boxesToMove) {
				var b = boxes.get(id);
				moveBox(b, b.x + dx, b.y + dy);
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

		var id = b.node.getId();
		// move edges from and to this box
		for (i => _ in b.info.inputs) {
			var input = packIO(id, i);
			var output = outputsToInputs.getLeft(input);
			if (output != null) {
				clearEdge(input);
				var visual = createCurve(output, input);
				edges.set(input, visual);
			}
		}

		for (i => _ in b.info.outputs) {
			var output = packIO(id, i);
			for (input in outputsToInputs.iterRights(output)) {
				clearEdge(input);
				var visual = createCurve(output, input);
				edges.set(input, visual);
			}
		}
	}

	function beginMove(e: js.html.MouseEvent) {
		lastClickDrag = new Point(lX(e.clientX), lY(e.clientY));

		boxesToMove.clear();

		for (id => _ in boxesSelected) {
			var b = boxes.get(id);
			boxesToMove.set(id, true);

			if (b.info.comment != null && !e.shiftKey) {
				var bounds = inline b.getBounds();
				var min = inline new Point(bounds.x, bounds.y);
				var max = inline new Point(bounds.x + bounds.w, bounds.y + bounds.h);

				for (bb in boxes) {
					if (isFullyInside(bb, min, max)) {
						boxesToMove.set(bb.node.getId(), true);
					}
				}
			}
		}
	}

	function saveMovedBoxes() {
		var save : Map<Int, {x: Float, y: Float}> = [];
		for (id => _ in boxesToMove) {
			var b = boxes[id];
			b.node.getPos(Box.tmpPoint);
			save.set(b.node.getId(), {x:Box.tmpPoint.x, y: Box.tmpPoint.y});
		}
		return save;
	}

	function endMove() {
		if (lastClickDrag == null)
			return;

		lastClickDrag = null;

		for (id => _ in boxesToMove) {
			for (id => _ in boxesToMove) {
				var b = boxes[id];
				opMove(b, b.x, b.y, currentUndoBuffer);
			}
		}

		commitUndo();
		boxesToMove = [];
	}

	static function edgeFromPack(output: Int, input: Int) : Edge {
		var output = unpackIO(output);
		var input = unpackIO(input);

		return {nodeFromId: output.nodeId, outputFromId: output.ioId, nodeToId: input.nodeId, inputToId: input.ioId};
	}

	function selectAll() {
		for (id => _ in boxes) {
			opSelect(id, true, currentUndoBuffer);
		}
		commitUndo();
	}


	function commentFromSelection() {
		if (boxesSelected.empty())
			return;

		var commentNode = editor.createCommentNode();
		if (commentNode == null)
			return;
		var comment = commentNode.getInfo().comment;
		if (comment == null)
			throw "createCommentNode node is not a comment";

		var bounds = inline new h2d.col.Bounds();
		for (id => _ in boxesSelected) {
			var box = boxes[id];

			box.node.getPos(Box.tmpPoint);
			bounds.addPos(Box.tmpPoint.x, Box.tmpPoint.y);
			var previewHeight = (box.info.preview?.getVisible() ?? false) ? box.width : 0;
			bounds.addPos(Box.tmpPoint.x + box.width, Box.tmpPoint.y + box.getHeight() + previewHeight);
		}

		var border = 10;
		bounds.xMin -= border;
		bounds.yMin -= border + 34;
		bounds.xMax += border;
		bounds.yMax += border;


		Box.tmpPoint.set(bounds.xMin, bounds.yMin);
		commentNode.setPos(Box.tmpPoint);
		Box.tmpPoint.set(bounds.width, bounds.height);
		comment.setSize(Box.tmpPoint);

		opBox(commentNode, true, currentUndoBuffer);
		commitUndo();
	}

	function onHide() {
		if (boxesSelected.empty())
			return;

		var viz = false;
		for (id => _ in boxesSelected) {
			if (boxes[id].info.preview?.getVisible() == true ?? false) {
				viz = true;
				break;
			}
		}
		for (id => _  in boxesSelected) {
			var box = boxes.get(id);
			if (box.info.preview == null)
				continue;
			opPreview(box, !viz, currentUndoBuffer);
		}

		commitUndo();
	}

	public function opPreview(box: Box, show: Bool, undoBuffer: UndoBuffer) : Void {
		var prev = box.info.preview.getVisible();
		if (prev == show)
			return;
		function exec(isUndo: Bool) {
			var v = !isUndo ? show : prev;
			box.info.preview.setVisible(v);
		}
		exec(false);
		undoBuffer.push(exec);
	}

	public function opBox(node: IGraphNode, doAdd: Bool, undoBuffer: UndoBuffer) : Void {
		var data = editor.serializeNode(node);

		var exec = function(isUndo : Bool) : Void {
			if (!doAdd) isUndo = !isUndo;
			if (!isUndo) {
				var node = editor.unserializeNode(data, false);
				addBox(node);
				editor.addNode(node);
			}
			else {
				var id = node.getId();
				var box = boxes.get(id);

				box.dispose();
				var id = box.node.getId();
				boxes.remove(id);

				editor.removeNode(id);

				// Sanity check
				for (i => _ in box.info.inputs) {
					var inputIO = packIO(box.node.getId(), i);
					var outputIO = outputsToInputs.getLeft(inputIO);
					if (outputIO != null)
						throw "box has remaining inputs, operation is not atomic";
				}

				for (i => _ in box.info.outputs) {
					var outputIO = packIO(box.node.getId(), i);
					for (inputIO in outputsToInputs.iterRights(outputIO)) {
						throw "box has remaining outputs, operation is not atomic";
					}
				}
			}
		}
		undoBuffer.push(exec);
		exec(false);
	}

	public function opComment(box: Box, newComment: String, undoBuffer: UndoBuffer) : Void {
		var id = box.node.getId();
		var prev = box.info.comment.getComment();
		if (newComment == prev)
			return;
		function exec(isUndo : Bool) {
			var box = boxes.get(id);
			var v = !isUndo ? newComment : prev;

			box.info.comment.setComment(v);
			box.element.find(".comment-title").get(0).innerText = v;
		}
		exec(false);
		undoBuffer.push(exec);
	}



	function opEdge(output: Int, input: Int, doAdd: Bool, undoBuffer: UndoBuffer) : Void {
		var edge = edgeFromPack(output, input);
		var previousFrom : Null<Int> = outputsToInputs.getLeft(input);
		var prevEdge = null;
		if (previousFrom != null && doAdd) {
			prevEdge = edgeFromPack(previousFrom, edgeCreationInput);
		}

		if (editor.canAddEdge(edge)) {
			var exec = function (isUndo : Bool) : Void {
				if (!doAdd) isUndo = !isUndo;
				if (!isUndo) {
					if (prevEdge != null)
						removeEdge(prevEdge);
					createEdge(edge);
				}
				else {
					removeEdge(edge);
					if (prevEdge != null) {
						createEdge(prevEdge);
					}
				}
			}
			undoBuffer.push(exec);
			exec(false);
		}
	}

	function finalizeUserCreateEdge() {
		if (edgeCreationOutput != null && edgeCreationInput != null) {
			opEdge(edgeCreationOutput, edgeCreationInput, true, currentUndoBuffer);
		}
		commitUndo();
		cleanupCreateEdge();
	}

	function cleanupCreateEdge() {
		edgeCreationOutput = null;
		edgeCreationInput = null;
		edgeCreationCurve?.remove();
		edgeCreationCurve = null;
		edgeCreationMode = None;
	}

	static var tmpPoint = new h2d.col.Point();
	function addBox(node : IGraphNode) : Box {
		node.editor = this;
		var box = new Box(this, editorMatrix, node);
		node.getPos(Box.tmpPoint);
		box.setPosition(Box.tmpPoint.x, Box.tmpPoint.y);

		var elt = box.getElement();
		elt.get(0).onpointerdown = function(e: js.html.MouseEvent) {
			if (e.button != 0)
				return;
			e.stopPropagation();

			if (!box.selected) {
				if (!e.ctrlKey) {
					// when not group selection and click on box not selected
					clearSelectionBoxesUndo(currentUndoBuffer);
				}
				opSelect(box.node.getId(), true, currentUndoBuffer);
				commitUndo();
			}
			beginMove(e);
		};
		elt.get(0).onpointerup = function(e) {
			if (e.button != 0)
				return;
			endMove();
		};
		boxes.set(box.node.getId(), box);

		for (inputId => input in box.info.inputs) {
			var defaultValue : String = input.defaultParam?.get();
			//defaultValue= Reflect.getProperty(box.getInstance().defaults, '${input.name}');

			var grNode = box.addInput(this, input.name, defaultValue, input.color);
			if (defaultValue != null) {
				var fieldEditInput = grNode.find("input");
				fieldEditInput.on("change", function(ev) {
					var prevValue = Std.parseFloat(input.defaultParam.get()) ?? 0.0;
					var tmpValue = Std.parseFloat(fieldEditInput.val());
					if (Math.isNaN(tmpValue) ) {
						fieldEditInput.addClass("error");
						fieldEditInput.val(prevValue);
					} else {
						var id = box.node.getId();
						function exec(isUndo : Bool) {
							var box = boxes.get(id);
							var val = isUndo ? prevValue : tmpValue;
							// 50 shades of curse
							var input = box.inputs[inputId].parent().find("input");
							input.val(val);
							box.info.inputs[inputId].defaultParam.set(Std.string(val));
						}

						fieldEditInput.removeClass("error");
						exec(false);
						editor.getUndo().change(Custom(exec));
					}
				});
				fieldEditInput.get(0).addEventListener("pointerdown", function(e) {
					e.stopPropagation();
					fieldEditInput.get(0).setPointerCapture(e.pointerId);
				});

				fieldEditInput.get(0).addEventListener("pointermove", function(e) {
					e.stopPropagation();
				});
			}
			grNode.find(".node").attr("field", inputId);
			grNode.get(0).addEventListener("pointerdown", function(e) {
				e.stopPropagation();
				heapsScene.get(0).setPointerCapture(e.pointerId);
				edgeCreationInput = packIO(box.node.getId(), inputId);
				edgeCreationMode = FromInput;
			});
		}
		for (outputId => info in box.info.outputs) {
			var grNode = box.addOutput(this, info.name, info.color);
			grNode.find(".node").attr("field", outputId);
			grNode.get(0).addEventListener("pointerdown", function(e) {
				e.stopPropagation();
				heapsScene.get(0).setPointerCapture(e.pointerId);
				edgeCreationOutput = packIO(box.node.getId(), outputId);
				edgeCreationMode = FromOutput;
			});
		}

		box.generateProperties(this);

		return box;
	}

	inline static function packIO(id: Int, ioId: Int) {
		return ioId << 24 | id;
	}

	inline static function unpackIO(io:Int) {
		return {
			nodeId: io & 0xFFFFFF,
			ioId: io >> 24,
		};
	}

	function clearEdge(id: Int) {
		var e = edges.get(id);
		if (e == null)
			return;
		e.remove();
		edges.remove(id);

		var io = unpackIO(id);
	}

	function removeBoxEdges(box : Box, ?undoBuffer : UndoBuffer) {
		var id = box.getInstance().getId();
		for (i => _ in box.info.inputs) {
			var inputIO = packIO(id, i);
			var outputIO = outputsToInputs.getLeft(inputIO);
			if (outputIO != null) {
				opEdge(outputIO, inputIO, false, undoBuffer);
			}
		}

		for (i => _ in box.info.outputs) {
			var outputIO = packIO(id, i);
			for (inputIO in outputsToInputs.iterRights(outputIO)) {
				opEdge(outputIO, inputIO, false, undoBuffer);
			}
		}
	}

	/** Asserts that editor.canAddEdge(edge) == true **/
	function createEdge(edge : GraphInterface.Edge){
		editor.addEdge(edge);
		var output = packIO(edge.nodeFromId, edge.outputFromId);
		var input = packIO(edge.nodeToId, edge.inputToId);
		var prev = outputsToInputs.getLeft(input);
		if(prev != null)
			throw "No input should be present";
		outputsToInputs.insert(output, input);

		var inputElem = boxes.get(edge.nodeToId).inputs[edge.inputToId];

		inputElem.attr("hasLink", "true");
		inputElem.parent().addClass("hasLink");

		var visual = createCurve(output, input);
		edges.set(input, visual);
		return prev;
	}

	function removeEdge(edge : GraphInterface.Edge) {
		var id = packIO(edge.nodeToId, edge.inputToId);
		outputsToInputs.removeRight(id);
		clearEdge(id);

		var input = boxes[edge.nodeToId].inputs[edge.inputToId];
		input.removeAttr("hasLink");
		input.parent().removeClass("hasLink");

		editor.removeEdge(edge.nodeToId, edge.inputToId);
	}

	/*function replaceEdge(state : EdgeState, ?edge : Edge, ?node : JQuery, x : Int, y : Int) {
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
	}*/

	function error(str : String, ?idBox : Int) {
		Ide.inst.quickError(str);
	}

	function info(str : String) {
		Ide.inst.quickMessage(str);
	}

	/*function createEdgeInEditorGraph(edge) {
		listOfEdges.push(edge);
		edge.to.inputs[edge.inputTo].attr("hasLink", "true");
		edge.to.inputs[edge.inputTo].parent().addClass("hasLink");

		edge.elt.on("mousedown", function(e) {
			e.stopPropagation();
			clearSelectionBoxes();
			this.currentEdge = edge;
			currentEdge.elt.addClass("selected");
		});
	}*/

	function createLink(clientX : Int, clientY : Int) {

		var nearestId = -1;
		var minDistNode = NODE_TRIGGER_NEAR;

		// checking nearest box
		var nearestBox = null;
		var minDist = 999999999999999.0;
		for (i => b in boxes) {
			if (b.info.comment != null)
				continue;
			var tmpDist = distanceToBox(b, clientX, clientY);
			if (tmpDist < minDist) {
				minDist = tmpDist;
				nearestBox = b;
			}
		}
		if (nearestBox == null)
			return;

		// checking nearest node in the nearest box
		if (edgeCreationMode == FromInput) {
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

		var val = null;
		if (minDistNode < NODE_TRIGGER_NEAR && nearestId >= 0) {
			val = packIO(nearestBox.node.getId(), nearestId);
		}

		if (edgeCreationMode == FromInput) {
			edgeCreationOutput = val;
		} else {
			edgeCreationInput = val;
		}

		// create edge
		if (edgeCreationCurve != null) edgeCreationCurve.remove();
		edgeCreationCurve = createCurve(edgeCreationOutput, edgeCreationInput, minDistNode, clientX, clientY, true);
	}

	function serializeSelection() : String {
		var data : CopySelectionData = {
			nodes:  [],
			edges: [],
		};
		for (nodeId => _ in boxesSelected) {
			var box = boxes[nodeId];
			data.nodes.push({id: nodeId, serData: editor.serializeNode(box.node)});
			for (inputId => _ in box.info.inputs) {
				var output = outputsToInputs.getLeft(packIO(nodeId, inputId));
				if (output != null) {
					var unpack = unpackIO(output);
					if ( boxesSelected.get(unpack.nodeId) != null) {
						data.edges.push({nodeFromId: unpack.nodeId, outputFromId: unpack.ioId, nodeToId: nodeId, inputToId: inputId});
					}
				}
			}
		}

		if (!data.nodes.empty()) {
			return haxe.Json.stringify(data);
		}
		return null;
	}

	function copySelection() {
		var str = serializeSelection();
		if (str != null) {
			Ide.inst.setClipboard(str);
		}
	}

	function cutSelection() {
		copySelection();
		deleteSelection();
	}

	function duplicateSelection() {
		var str = serializeSelection();
		createFromString(str, currentUndoBuffer);
		commitUndo();
	}

	function createFromString(str: String, undoBuffer: UndoBuffer) {
		var nodes : Array<IGraphNode> = [];
		var idRemap : Map<Int, Int> = [];
		var edges : Array<Edge> = [];
		try {
			var data : CopySelectionData = haxe.Json.parse(str);
			for (nodeInfo in data.nodes) {
				var node = editor.unserializeNode(nodeInfo.serData, true);
				nodes.push(node);
				var newId = node.getId();
				idRemap.set(nodeInfo.id, newId);
			}
			for (e in data.edges) {
				edges.push({nodeFromId: e.nodeFromId, nodeToId: e.nodeToId, outputFromId: e.outputFromId, inputToId: e.inputToId});
			}
		}
		catch (e) {
			Ide.inst.quickError('Could not paste content of clipboard ($e) "$str"');
			return;
		}

		if (nodes.length <= 0)
			return;

		// center of all the boxes
		var offset = new h2d.col.Point(0,0);
		var pt = Box.tmpPoint;
		for (count => node in nodes) {
			node.getPos(pt);
			offset.set(offset.x + (pt.x - offset.x) / (count + 1),offset.y + (pt.y - offset.y) / (count + 1));
		}

		clearSelectionBoxesUndo(undoBuffer);

		for (node in nodes) {
			node.getPos(pt);
			pt -= offset;
			pt.x += lX(ide.mouseX);
			pt.y += lY(ide.mouseY);
			node.setPos(pt);
			opBox(node, true, undoBuffer);
			opSelect(node.getId(), true, undoBuffer);
		}

		for (edge in edges) {
			var newFromId = idRemap.get(edge.nodeFromId);
			var newToId = idRemap.get(edge.nodeToId);
			opEdge(packIO(newFromId, edge.outputFromId), packIO(newToId, edge.inputToId), true, undoBuffer);
		}
	}

	function paste() {
		var nodes : Array<IGraphNode> = [];
		var idRemap : Map<Int, Int> = [];
		var edges : Array<Edge> = [];
		try {
			var cb = Ide.inst.getClipboard();
			var data : CopySelectionData = haxe.Json.parse(cb);
			for (nodeInfo in data.nodes) {
				var node = editor.unserializeNode(nodeInfo.serData, true);
				nodes.push(node);
				var newId = node.getId();
				idRemap.set(nodeInfo.id, newId);
			}
			for (e in data.edges) {
				edges.push({nodeFromId: e.nodeFromId, nodeToId: e.nodeToId, outputFromId: e.outputFromId, inputToId: e.inputToId});
			}
		}
		catch (e) {
			Ide.inst.quickError('Could not paste content of clipboard ($e)');
			return;
		}

		if (nodes.length <= 0)
			return;

		// center of all the boxes
		var offset = new h2d.col.Point(0,0);
		var pt = Box.tmpPoint;
		for (count => node in nodes) {
			node.getPos(pt);
			offset.set(offset.x + (pt.x - offset.x) / (count + 1),offset.y + (pt.y - offset.y) / (count + 1));
		}


		currentUndoBuffer = [];

		clearSelectionBoxesUndo(currentUndoBuffer);

		for (node in nodes) {
			node.getPos(pt);
			pt -= offset;
			pt.x += lX(ide.mouseX);
			pt.y += lY(ide.mouseY);
			node.setPos(pt);
			opBox(node, true, currentUndoBuffer);
			opSelect(node.getId(), true, currentUndoBuffer);
		}

		for (edge in edges) {
			var newFromId = idRemap.get(edge.nodeFromId);
			var newToId = idRemap.get(edge.nodeToId);
			opEdge(packIO(newFromId, edge.outputFromId), packIO(newToId, edge.inputToId), true, currentUndoBuffer);
		}


		commitUndo();
	}

	function createCurve(packedOutput: Null<Int>, packedInput: Null<Int>, ?distance : Float, ?x : Float, ?y : Float, ?isDraft : Bool) {
		var offsetEnd = {top : y ?? 0.0, left : x ?? 0.0};
		if (packedInput != null) {
			var input = unpackIO(packedInput);
			var node = boxes[input.nodeId].inputs[input.ioId];
			offsetEnd = node.offset();
		}
		var offsetStart = {top : y ?? 0.0, left : x ?? 0.0};
		if (packedOutput != null) {
			var output = unpackIO(packedOutput);
			var node = boxes[output.nodeId].outputs[output.ioId];
			offsetStart = node.offset();
		}

		if (x != null && y != null) {
			lastCurveX = lX(x);
			lastCurveY = lY(y);
		}

		var startX = lX(offsetStart.left) + Box.NODE_RADIUS;
		var startY = lY(offsetStart.top) + Box.NODE_RADIUS;
		var endX = lX(offsetEnd.left) + Box.NODE_RADIUS;
		var endY = lY(offsetEnd.top) + Box.NODE_RADIUS;
		var diffDistanceY = offsetEnd.top - offsetStart.top;
		var signCurveY = ((diffDistanceY > 0) ? -1 : 1);
		diffDistanceY = Math.abs(diffDistanceY);
		var valueCurveX = 100;
		var valueCurveY = 1;
		var maxDistanceY = 900;

		var curve = editorDisplay.curve(null,
							startX,
							startY,
							endX,
							endY,
							startX + valueCurveX * (Math.min(maxDistanceY, diffDistanceY)/maxDistanceY),
							startY + signCurveY * valueCurveY * (Math.min(maxDistanceY, diffDistanceY)/maxDistanceY),
							{})
							.addClass("edge");
		editorMatrix.prepend(curve);
		if (isDraft)
			curve.addClass("draft");
		else if (packedOutput != null && packedInput != null) {
			curve.on("pointerdown", function(e) {

				if (e.button == 0) {
					opEdge(packedOutput, packedInput, false, currentUndoBuffer);

					heapsScene.get(0).setPointerCapture(e.pointerId);

					var mx = lX(e.clientX);
					var my = lY(e.clientY);
					if (hxd.Math.distance(mx - startX, my - startY, 0) < hxd.Math.distance(mx - endX, my - endY, 0)) {
						edgeCreationInput = packedInput;
						edgeCreationMode = FromInput;
					} else {
						edgeCreationOutput = packedOutput;
						edgeCreationMode = FromOutput;
					}


					e.preventDefault();
					e.stopPropagation();
				}
				else if (e.button == 2) {
					new hide.comp.ContextMenu([
						{label: "Delete ?", click: function() {
								var edge = edgeFromPack(packedOutput, packedInput);
								opEdge(packedOutput, packedInput, false, currentUndoBuffer);
								commitUndo();
							}
						},
					]);
					e.preventDefault();
					e.stopPropagation();
				}


			});
		}

		return curve;
	}

	function clearSelectionBoxesUndo(undoBuffer: UndoBuffer) {
		for (id => _ in boxesSelected) {
			opSelect(id, false, undoBuffer);
		}
	}

	function startUpdateViewPosition() {
		if (timerUpdateView != null)
			return;
		timerUpdateView = new Timer(0);
		timerUpdateView.run = function() {
			var posCursor = new Point(ide.mouseX - heapsScene.offset().left, ide.mouseY - heapsScene.offset().top);
			var wasUpdated = false;
			if (posCursor.x < BORDER_SIZE) {
				pan(new Point((BORDER_SIZE - posCursor.x)*SPEED_BORDER_MOVE, 0));
				wasUpdated = true;
			}
			if (posCursor.y < BORDER_SIZE) {
				pan(new Point(0, (BORDER_SIZE - posCursor.y)*SPEED_BORDER_MOVE));
				wasUpdated = true;
			}
			var rightBorder = heapsScene.width() - BORDER_SIZE;
			if (posCursor.x > rightBorder) {
				pan(new Point((rightBorder - posCursor.x)*SPEED_BORDER_MOVE, 0));
				wasUpdated = true;
			}
			var botBorder = heapsScene.height() - BORDER_SIZE;
			if (posCursor.y > botBorder) {
				pan(new Point(0, (botBorder - posCursor.y)*SPEED_BORDER_MOVE));
				wasUpdated = true;
			}
		};
	}

	function stopUpdateViewPosition() {
		if (timerUpdateView != null) {
			timerUpdateView.stop();
			timerUpdateView = null;
		}
	}

	function getGraphDims() {
		if(!boxes.iterator().hasNext()) return {xMin : -1.0, yMin : -1.0, xMax : 1.0, yMax : 1.0, center : new IPoint(0,0)};
		var xMin = 1000000.0;
		var yMin = 1000000.0;
		var xMax = -1000000.0;
		var yMax = -1000000.0;
		for (b in boxes) {
			b.node.getPos(Box.tmpPoint);
			var x = Box.tmpPoint.x;
			var y = Box.tmpPoint.y;
			xMin = Math.min(xMin, x);
			yMin = Math.min(yMin, y);
			xMax = Math.max(xMax, x + b.width);
			yMax = Math.max(yMax, y + b.getHeight());
		}
		var center = new IPoint(Std.int(xMin + (xMax - xMin)/2), Std.int(yMin + (yMax - yMin)/2));
		center.y += Std.int(editorDisplay.element.height()*CENTER_OFFSET_Y);
		return {
			xMin : xMin,
			yMin : yMin,
			xMax : xMax,
			yMax : yMax,
			center : center,
		};
	}

	public function centerView() {
		if (!boxes.iterator().hasNext()) return;
		var dims = getGraphDims();
		var scale = Math.min(1, Math.min((editorDisplay.element.width() - 50) / (dims.xMax - dims.xMin), (editorDisplay.element.height() - 50) / (dims.yMax - dims.yMin)));

		transformMatrix[4] = editorDisplay.element.width()/2 - dims.center.x;
		transformMatrix[5] = editorDisplay.element.height()/2 - dims.center.y;

		transformMatrix[0] = scale;
		transformMatrix[3] = scale;

		var x = editorDisplay.element.width()/2;
		var y = editorDisplay.element.height()/2;

		transformMatrix[4] = x - (x - transformMatrix[4]) * scale;
		transformMatrix[5] = y - (y - transformMatrix[5]) * scale;

		updateMatrix();
	}

	function clampView() {
		if (boxes.iterator().hasNext()) return;
		var dims = getGraphDims();

		var width = editorDisplay.element.width();
		var height = editorDisplay.element.height();
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

		x -= Std.int(editorDisplay.element.offset().left);
		y -= Std.int(editorDisplay.element.offset().top);

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
		return editorDisplay.element.is(":visible");
	}

	// Useful method
	function isInside(b : Box, min : Point, max : Point) {
		var bounds = inline b.getBounds();
		if (max.x < bounds.x || min.x > bounds.x + bounds.w)
			return false;
		if (max.y < bounds.y || min.y > bounds.y + bounds.h)
			return false;

		return true;
	}

	function isFullyInside(b: Box, min : Point, max : Point) {
		var bounds = inline b.getBounds();
		if (min.x > bounds.x || max.x < bounds.x + bounds.w)
			return false;
		if (min.y > bounds.y || max.y < bounds.y + bounds.h)
			return false;

		return true;
	}

	function distanceToBox(b : Box, x : Int, y : Int) {
		var bounds = inline b.getBounds();
		var dx = Math.max(Math.abs(lX(x) - (bounds.x + (bounds.w / 2))) - bounds.w / 2, 0);
		var dy = Math.max(Math.abs(lY(y) - (bounds.y + (bounds.h / 2))) - bounds.h / 2, 0);
		return dx * dx + dy * dy;
	}
	function distanceToElement(element : JQuery, x : Int, y : Int) {
		if (element == null)
			return NODE_TRIGGER_NEAR+1;
		var dx = Math.max(Math.abs(x - (element.offset().left + element.width() / 2)) - element.width() / 2, 0);
		var dy = Math.max(Math.abs(y - (element.offset().top + element.height() / 2)) - element.height() / 2, 0);
		return dx * dx + dy * dy;
	}
	public function gX(x : Float) : Float {
		return x*transformMatrix[0] + transformMatrix[4];
	}
	public function gY(y : Float) : Float {
		return y*transformMatrix[3] + transformMatrix[5];
	}
	public function gPos(x : Float, y : Float) : Point {
		return new Point(gX(x), gY(y));
	}
	public function lX(x : Float) : Float {
		var screenOffset = editorDisplay.element.offset();
		x -= screenOffset.left;
		return (x - transformMatrix[4])/transformMatrix[0];
	}
	public function lY(y : Float) : Float {
		var screenOffset = editorDisplay.element.offset();
		y -= screenOffset.top;
		return (y - transformMatrix[5])/transformMatrix[3];
	}
	public function lPos(x : Float, y : Float) : Point {
		return new Point(lX(x), lY(y));
	}

}
package hide.view;

using hxsl.Ast.Type;

import haxe.rtti.Rtti;
import haxe.rtti.Meta;
import hxsl.DynamicShader;
import hxsl.SharedShader;
import hide.comp.SceneEditor;
import js.jquery.JQuery;
import h2d.col.Point;
import h2d.col.IPoint;
import hide.comp.SVG;
import hide.view.shadereditor.Box;
import hrt.shgraph.ShaderGraph;
import hrt.shgraph.ShaderNode;
import hrt.shgraph.ShaderType;
import hrt.shgraph.ShaderType.SType;

enum EdgeState { None; FromInput; FromOutput; }
typedef NodeInfo = { name : String, description : String, key : String };

typedef Edge = { from : Box, nodeFrom : JQuery, to : Box, nodeTo : JQuery, elt : JQuery };

class ShaderEditor extends FileView {

	var parent : JQuery;
	static var editor : SVG;
	var editorMatrix : JQuery;


	var listOfClasses = new Map<String, Array<NodeInfo>>();
	var addMenu : JQuery;
	var selectedNode : JQuery;

	var listOfBoxes : Array<Box> = [];
	var listOfEdges : Array<Edge> = [];

	static var transformMatrix : Array<Float> = [1, 0, 0, 1, 0, 0];
	var isPanning : Bool = false;

	// used for selection
	var listOfBoxesSelected : Array<Box> = [];
	var recSelection : JQuery;
	var startRecSelection : h2d.col.IPoint;
	var firstClickDrag : h2d.col.IPoint;

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

	// used to preview
	var sceneEditor : SceneEditor;

	var root : hrt.prefab.Prefab;
	var obj : h3d.scene.Object;
	var plight : hrt.prefab.Prefab;
	var light : h3d.scene.Object;
	var lightDirection : h3d.Vector;

	static var shaderGraph : ShaderGraph;

	var shaderGenerated : DynamicShader;

	override function onDisplay() {
		shaderGraph = new ShaderGraph(getPath());
		addMenu = null;
		element.html('
			<div class="flex vertical">
				<div class="flex-elt shader-view">
					<div class="heaps-scene">
					</div>
					<div class="tabs">
						<span>Parameters</span>
						<div class="tab expand" name="Scene" icon="sitemap">
							<div class="hide-block" style="height:50%">
								<div class="hide-scene-tree hide-list">
								</div>
							</div>
							<div class="hide-scroll"></div>
						</div>
					</div>
				</div>
			</div>');
		parent = element.find(".heaps-scene");
		editor = new SVG(parent);
		var preview = new Element('<div id="preview" ></div>');
		preview.on("mousedown", function(e) { e.stopPropagation(); });
		preview.on("wheel", function(e) { e.stopPropagation(); });
		parent.append(preview);

		var def = new hrt.prefab.Library();
		new hrt.prefab.RenderProps(def).name = "renderer";
		var l = new hrt.prefab.Light(def);
		l.name = "sunLight";
		l.kind = Directional;
		l.power = 1.5;
		var q = new h3d.Quat();
		q.initDirection(new h3d.Vector(-1,-1.5,-3));
		var a = q.toEuler();
		l.rotationX = Math.round(a.x * 180 / Math.PI);
		l.rotationY = Math.round(a.y * 180 / Math.PI);
		l.rotationZ = Math.round(a.z * 180 / Math.PI);
		l.shadows.mode = Dynamic;
		l.shadows.size = 1024;
		root = def;

		sceneEditor = new hide.comp.SceneEditor(this, root);
		sceneEditor.editorDisplay = false;
		sceneEditor.onRefresh = onRefresh;
		sceneEditor.onUpdate = update;
		sceneEditor.view.keys = new hide.ui.Keys(null); // Remove SceneEditor Shortcuts
		sceneEditor.view.keys.register("save", function() {
			save();
			skipNextChange = true;
			modified = false;
		});

		editorMatrix = editor.group(editor.element);

		// rectangle Selection
		parent.on("mousedown", function(e) {

			closeAddMenu();

			if (e.button == 0) {
				startRecSelection = new IPoint(e.offsetX, e.offsetY);
				if (currentEdge != null) {
					currentEdge.elt.removeClass("selected");
					currentEdge = null;
				}

				clearSelectionBoxes();
			}
			if (e.button == 1) {
				firstClickDrag = new IPoint(e.clientX, e.clientY);
				isPanning = true;
			}
		});

		parent.on("mousemove", function(e : js.jquery.Event) {
			e.preventDefault();
			e.cancelBubble=true;
    		e.returnValue=false;

			if (isCreatingLink != None) {
				createLink(e);
				return;
			}
			// Moving edge
			if (currentEdge != null) {
				// TODO: handle moving edge => disconnect closest node
				// try to use the same code when user clicks on input node already connected and here
			}
			if (isPanning) {
				pan(new Point(e.clientX - firstClickDrag.x, e.clientY - firstClickDrag.y));
				firstClickDrag.x = e.clientX;
				firstClickDrag.y = e.clientY;
				return;
			}
			// Edit rectangle selection
			if (startRecSelection != null) {
				var endRecSelection = new h2d.col.IPoint(e.offsetX, e.offsetY);
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
				recSelection = editor.rect(editor.element, xMin, yMin, xMax - xMin, yMax - yMin).addClass("rect-selection");

				for (box in listOfBoxes) {
					if (isInside(box, new IPoint(xMin, yMin), new IPoint(xMax, yMax))) {
						box.setSelected(true);
					} else {
						box.setSelected(false);
					}
				}
				return;
			}

			// Move selected boxes
			if (listOfBoxesSelected.length > 0 && firstClickDrag != null) {
				var dx = (e.clientX - firstClickDrag.x)/transformMatrix[0];
				var dy = (e.clientY - firstClickDrag.y)/transformMatrix[3];

				for (b in listOfBoxesSelected) {
					b.setPosition(b.getX() + dx, b.getY() + dy);
					shaderGraph.setPosition(b.getId(), b.getX(), b.getY());
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
				firstClickDrag.x = e.clientX;
				firstClickDrag.y = e.clientY;
				return;
			}
		});

		parent.on("mouseup", function(e) {
			if (e.button == 0) {
				// Stop link creation
				if (isCreatingLink != None) {
					if (startLinkBox != null && endLinkBox != null) {
						createEdgeInShaderGraph();
					} else {
						if (currentLink != null) currentLink.remove();
						currentLink = null;
					}
					startLinkBox = endLinkBox = null;
					startLinkGrNode = endLinkNode = null;
					isCreatingLink = None;
					clearAvailableNodes();
				}

				// Stop rectangle selection
				firstClickDrag = null;
				startRecSelection = null;
				if (recSelection != null) {
					recSelection.remove();
					recSelection = null;
					for (b in listOfBoxes)
						if (b.selected)
							listOfBoxesSelected.push(b);
				}
			}

			// Stop panning
			if (e.button == 1) {
				firstClickDrag = null;
				isPanning = false;
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

		new Element("body").on("keydown", function(e) {

			if (e.shiftKey && e.keyCode != 16) {
				openAddMenu();

				return;
			}

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
			} else if (e.keyCode == 32) {
				var s = new SharedShader("");
				s.data = shaderGraph.buildFragment();
				s.initialize();

				if (shaderGenerated != null)
					for (m in obj.getMaterials())
						m.mainPass.removeShader(shaderGenerated);

				shaderGenerated = new DynamicShader(s);
				for (m in obj.getMaterials()) {
					m.mainPass.addShader(shaderGenerated);
				}
			} else if (e.keyCode == 83 && e.ctrlKey) { // CTRL+S : save
				shaderGraph.save();
			}
		});

		var mapOfNodes = ShaderNode.registeredNodes;
		for (key in mapOfNodes.keys()) {
			var metas = haxe.rtti.Meta.getType(mapOfNodes[key]);
			if (metas.group == null) {
				continue;
			}
			var group = metas.group[0];

			if (listOfClasses[group] == null)
				listOfClasses[group] = new Array<NodeInfo>();

			listOfClasses[group].push({ name : (metas.name != null) ? metas.name[0] : key , description : (metas.description != null) ? metas.description[0] : "" , key : key });
		}

		for (key in listOfClasses.keys()) {
			listOfClasses[key].sort(function (a, b): Int {
				if (a.name < b.name) return -1;
				else if (a.name > b.name) return 1;
				return 0;
			});
		}

		listOfBoxes = [];
		listOfEdges = [];

		new Element("svg").ready(function(e) {

			for (node in shaderGraph.getNodes()) {
				addBox(new Point(node.x, node.y), std.Type.getClass(node.instance), node.instance);
			}

			for (box in listOfBoxes) {
				for (key in box.getShaderNode().getInputsKey()) {
					var input = box.getShaderNode().getInput(key);
					if (input != null) {
						var fromBox : Box = null;
						for (boxFrom in listOfBoxes) {
							if (boxFrom.getId() == input.node.id) {
								fromBox = boxFrom;
								break;
							}
						}
						var nodeFrom = fromBox.getElement().find('[field=${input.getKey()}]');
						var nodeTo = box.getElement().find('[field=${key}]');
						createEdgeInEditorGraph({from: fromBox, nodeFrom: nodeFrom, to : box, nodeTo: nodeTo, elt : createCurve(nodeFrom, nodeTo) });
					}
				}
			}
		});

	}

	function update(dt : Float) {

	}

	function onRefresh() {

		plight = root.getAll(hrt.prefab.Light)[0];
		if( plight != null ) {
			this.light = sceneEditor.context.shared.contexts.get(plight).local3d;
			lightDirection = this.light.getDirection();
		}

		var sphere = new h3d.prim.Sphere(1, 32, 32);
		sphere.addNormals();
		var mesh = new h3d.scene.Mesh(sphere, sceneEditor.scene.s3d);
		mesh.material.mainPass.enableLights = true;
		mesh.material.shadows = true;
		mesh.material.color.load(new h3d.Vector(1, 1, 1));
		obj = mesh;

		element.find("#preview").first().append(sceneEditor.scene.element);
	}

	function addNode(p : Point, nodeClass : Class<ShaderNode>) {
		var node = shaderGraph.addNode(p.x, p.y, nodeClass);

		addBox(p, nodeClass, node);
	}

	function addBox(p : Point, nodeClass : Class<ShaderNode>, node : ShaderNode) {

		var className = std.Type.getClassName(nodeClass);
		className = className.substr(className.lastIndexOf(".") + 1);

		var box = new Box(editor, editorMatrix, p.x, p.y, node);
		var elt = box.getElement();
		elt.mousedown(function(e) {
			if (e.button != 0)
				return;
			e.stopPropagation();

			firstClickDrag = new IPoint(e.clientX, e.clientY);
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
			firstClickDrag = null;
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
				var name : String = (m.input != null && m.input.length > 0) ? Reflect.field(m, "input")[0] : "input";
				var grNode = box.addInput(editor, name);
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
								createLink(e);
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
		box.generateParameters(editor);
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
		shaderGraph.removeNode(box.getId());
	}

	function removeEdge(edge : Edge) {
		edge.elt.remove();
		edge.nodeTo.removeAttr("hasLink");
		shaderGraph.removeEdge(edge.to.getId(), edge.nodeTo.attr("field"));
		listOfEdges.remove(edge);
	}

	function setAvailableInputNodes(boxOutput : Box, field : String) {
		var type = boxOutput.getShaderNode().getOutputType(field);
		var sType : SType;
		if (type == null) {
			sType = boxOutput.getShaderNode().getOutputInfo(field);
		} else {
			sType = ShaderType.getType(type);
		}

		for (box in listOfBoxes) {
			for (input in box.inputs) {
				if (box.getShaderNode().checkTypeAndCompatibilyInput(input.attr("field"), sType)) {
					input.addClass("nodeMatch");
				}
			}
		}
	}

	function setAvailableOutputNodes(boxInput : Box, field : String) {
		for (box in listOfBoxes) {
			for (output in box.outputs) {
				var outputField = output.attr("field");
				var type = box.getShaderNode().getOutputType(outputField);
				var sType : SType;
				if (type == null) {
					sType = box.getShaderNode().getOutputInfo(outputField);
				} else {
					sType = ShaderType.getType(type);
				}
				if (boxInput.getShaderNode().checkTypeAndCompatibilyInput(field, sType)) {
					output.addClass("nodeMatch");
				}
			}
		}
	}

	function clearAvailableNodes() {
		editor.element.find(".nodeMatch").removeClass("nodeMatch");
	}

	function createEdgeInShaderGraph() {
		var startLinkNode = startLinkGrNode.find(".node");
		if (isCreatingLink == FromInput) {
			var tmpBox = startLinkBox;
			startLinkBox = endLinkBox;
			endLinkBox = tmpBox;

			var tmpNode = startLinkNode;
			startLinkNode = endLinkNode;
			endLinkNode = tmpNode;
		}

		var newEdge = { from: startLinkBox, nodeFrom : startLinkNode, to : endLinkBox, nodeTo : endLinkNode, elt : currentLink };
		if (endLinkNode.attr("hasLink") != null) {
			for (edge in listOfEdges) {
				if (edge.nodeTo.is(endLinkNode)) {
					removeEdge(edge);
					break;
				}
			}
		}
		shaderGraph.addEdge({ idOutput: startLinkBox.getId(), nameOutput: startLinkNode.attr("field"), idInput: endLinkBox.getId(), nameInput: endLinkNode.attr("field") });
		createEdgeInEditorGraph(newEdge);
		currentLink.removeClass("draft");
		currentLink = null;
	}

	function createEdgeInEditorGraph(edge) {
		listOfEdges.push(edge);
		edge.nodeTo.attr("hasLink", "true");

		edge.elt.on("mousedown", function(e) {
			e.stopPropagation();
			clearSelectionBoxes();
			this.currentEdge = edge;
			currentEdge.elt.addClass("selected");
		});
	}

	function createLink(e : js.jquery.Event) {

		var nearestNode = null;
		var minDistNode = NODE_TRIGGER_NEAR;

		// checking nearest box
		var nearestBox = listOfBoxes[0];
		var minDist = distanceToBox(nearestBox, e.clientX, e.clientY);
		for (i in 1...listOfBoxes.length) {
			var tmpDist = distanceToBox(listOfBoxes[i], e.clientX, e.clientY);
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
				minDistNode = distanceToElement(nearestNode, e.clientX, e.clientY);
				for (i in startIndex+1...nearestBox.outputs.length) {
					if (!nearestBox.outputs[i].hasClass("nodeMatch"))
						continue;
					var tmpDist = distanceToElement(nearestBox.outputs[i], e.clientX, e.clientY);
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
				minDistNode = distanceToElement(nearestNode, e.clientX, e.clientY);
				for (i in startIndex+1...nearestBox.inputs.length) {
					if (!nearestBox.inputs[i].hasClass("nodeMatch"))
						continue;
					var tmpDist = distanceToElement(nearestBox.inputs[i], e.clientX, e.clientY);
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
		currentLink = createCurve(startLinkGrNode.find(".node"), nearestNode, minDistNode, e.clientX, e.clientY, true);

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

	function openAddMenu() {
		if (addMenu != null) {
			var input = addMenu.find("#search-input");
			input.val("");
			addMenu.show();
			input.focus();
			var posCursor = new IPoint(Std.int(ide.mouseX - parent.offset().left), Std.int(ide.mouseY - parent.offset().top));

			addMenu.css("left", posCursor.x);
			addMenu.css("top", posCursor.y);
			return;
		}

		addMenu = new Element('
		<div id="add-menu">
			<div class="search-container">
				<div class="icon" >
					<i class="fa fa-search"></i>
				</div>
				<div class="search-bar" >
					<input type="text" id="search-input" >
				</div>
			</div>
			<div id="results">
			</div>
		</div>').appendTo(parent);

		var posCursor = new IPoint(Std.int(ide.mouseX - parent.offset().left), Std.int(ide.mouseY - parent.offset().top));

		addMenu.css("left", posCursor.x);
		addMenu.css("top", posCursor.y);

		addMenu.on("mousedown", function(e) {
			e.stopPropagation();
		});

		var results = addMenu.find("#results");
		results.on("wheel", function(e) {
			e.stopPropagation();
		});

		var keys = listOfClasses.keys();
		var sortedKeys = [];
		for (k in keys) {
			sortedKeys.push(k);
		}
		sortedKeys.sort(function (a, b) {
			if (a < b) return -1;
			if (a > b) return 1;
			return 0;
		});

		for (key in sortedKeys) {
			new Element('
				<div class="group" >
					<span> ${key} </span>
				</div>').appendTo(results);
			for (node in listOfClasses[key]) {
				new Element('
					<div node="${node.key}" >
						<span> ${node.name} </span> <span> ${node.description} </span>
					</div>').appendTo(results);
			}
		}

		var input = addMenu.find("#search-input");
		input.focus();
		var divs = new Element("#results > div");
		input.on("keydown", function(ev) {
			if (ev.keyCode == 38 || ev.keyCode == 40) {
				ev.stopPropagation();
				ev.preventDefault();

				if (selectedNode != null)
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
		input.on("keyup", function(ev) {
			if (ev.keyCode == 38 || ev.keyCode == 40) {
				return;
			}

			if (ev.keyCode == 13) {
				var key = this.selectedNode.attr("node");
				var posCursor = new Point(ide.mouseX - parent.offset().left - 25, ide.mouseY - parent.offset().top - 10);
				addNode(posCursor, ShaderNode.registeredNodes[key]);
				closeAddMenu();
			} else {
				if (this.selectedNode != null)
					this.selectedNode.removeClass("selected");
				var value = input.val();
				var children = divs.elements();
				var isFirst = true;
				var lastGroup = null;
				for (elt in children) {
					if (elt.hasClass("group")) {
						lastGroup = elt;
						elt.hide();
						continue;
					}
					if (elt.children().first().html().toLowerCase().indexOf(value.toLowerCase()) != -1) {
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
		divs.mouseover(function(ev) {
			if (ev.getThis().hasClass("group")) {
				return;
			}
			this.selectedNode.removeClass("selected");
			this.selectedNode = ev.getThis();
			this.selectedNode.addClass("selected");
		});
		divs.mouseup(function(ev) {
			if (ev.getThis().hasClass("group")) {
				return;
			}
			var key = ev.getThis().attr("node");
			var posCursor = new Point(Std.int(ide.mouseX - parent.offset().left - 25), Std.int(ide.mouseY - parent.offset().top - 10));
			addNode(posCursor, ShaderNode.registeredNodes[key]);
			closeAddMenu();
		});
	}

	function closeAddMenu() {
		if (addMenu != null)
			addMenu.hide();
	}

	function clearSelectionBoxes() {
		for(b in listOfBoxesSelected) b.setSelected(false);
		listOfBoxesSelected = [];
		if (this.currentEdge != null) {
			currentEdge.elt.removeClass("selected");
		}
	}

	function updateMatrix() {
		editorMatrix.attr({transform: 'matrix(${transformMatrix.join(' ')})'});
	}

	function zoom(scale : Float, x : Int, y : Int) {
		if (scale > 1 && transformMatrix[0] > 1.2) {
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

	// Useful method
	function isInside(b : Box, min : IPoint, max : IPoint) {
		if (max.x < gX(b.getX()) || min.x > gX(b.getX() + b.getWidth()))
			return false;
		if (max.y < gY(b.getY()) || min.y > gY(b.getY() + b.getHeight()))
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
	static function gX(x : Float) : Float {
		return x*transformMatrix[0] + transformMatrix[4];
	}
	static function gY(y : Float) : Float {
		return y*transformMatrix[3] + transformMatrix[5];
	}
	static function gPos(x : Float, y : Float) : Point {
		return new Point(gX(x), gY(y));
	}
	static function lX(x : Float) : Float {
		var screenOffset = editor.element.offset();
		x -= screenOffset.left;
		return (x - transformMatrix[4])/transformMatrix[0];
	}
	static function lY(y : Float) : Float {
		var screenOffset = editor.element.offset();
		y -= screenOffset.top;
		return (y - transformMatrix[5])/transformMatrix[3];
	}
	static function lPos(x : Float, y : Float) : Point {
		return new Point(lX(x), lY(y));
	}

	static var _ = FileTree.registerExtension(ShaderEditor,["shader"],{ icon : "scribd" });

}
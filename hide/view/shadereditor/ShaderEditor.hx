package hide.view.shadereditor;

import hxsl.DynamicShader;
import h3d.Vector;
import hrt.shgraph.ShaderParam;
import hrt.shgraph.ShaderException;
import haxe.Timer;
using hxsl.Ast.Type;

import haxe.rtti.Meta;
import hide.comp.SceneEditor;
import js.jquery.JQuery;
import h2d.col.Point;
import h2d.col.IPoint;
import hide.view.shadereditor.Box;
import hrt.shgraph.ShaderGraph;
import hrt.shgraph.ShaderNode;

typedef NodeInfo = { name : String, description : String, key : String };

class ShaderEditor extends hide.view.Graph {

	var parametersList : JQuery;
	var draggedParamId : Int;

	var addMenu : JQuery;
	var selectedNode : JQuery;
	var listOfClasses : Map<String, Array<NodeInfo>>;

	// used to preview
	var sceneEditor : SceneEditor;

	var root : hrt.prefab.Prefab;
	var obj : h3d.scene.Object;
	var plight : hrt.prefab.Prefab;
	var light : h3d.scene.Object;
	var lightDirection : h3d.Vector;

	var shaderGraph : ShaderGraph;

	var timerCompileShader : Timer;
	var COMPILE_SHADER_DEBOUNCE : Int = 100;
	var VIEW_VISIBLE_CHECK_TIMER : Int = 500;
	var currentShader : DynamicShader;

	override function onDisplay() {
		super.onDisplay();
		saveDisplayKey = "ShaderGraph:" + getPath().split("\\").join("/").substr(0,-1);
		shaderGraph = new ShaderGraph(getPath());
		addMenu = null;

		element.find("#rightPanel").html('
						<span>Parameters</span>
						<div class="tab expand" name="Scene" icon="sitemap">
							<div class="hide-block" >
								<div id="parametersList" class="hide-scene-tree hide-list">
								</div>
							</div>
							<div class="options-block hide-block">
								<input id="createParameter" type="button" value="Add parameter" />
								<input id="launchCompileShader" type="button" value="Compile shader" />
								<input id="saveShader" type="button" value="Save" />
								<input id="changeModel" type="button" value="Change Model" />
								<input id="centerView" type="button" value="Center View" />
							</div>
						</div>)');
		parent.on("drop", function(e) {
			var posCursor = new Point(lX(ide.mouseX - 25), lY(ide.mouseY - 10));
			var node = Std.instance(shaderGraph.addNode(posCursor.x, posCursor.y, ShaderParam), ShaderParam);
			node.parameterId = draggedParamId;
			var paramShader = shaderGraph.getParameter(draggedParamId);
			node.variable = paramShader.variable;
			node.setName(paramShader.name);
			setDisplayValue(node, paramShader.type, paramShader.defaultValue);
			node.computeOutputs();
			addBox(posCursor, ShaderParam, node);
		});

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
		sceneEditor.onUpdate = function(dt : Float) {};
		sceneEditor.view.keys = new hide.ui.Keys(null); // Remove SceneEditor Shortcuts
		sceneEditor.view.keys.register("save", function() {
			save();
			skipNextChange = true;
			modified = false;
		});

		editorMatrix = editor.group(editor.element);

		element.on("mousedown", function(e) {
			closeAddMenu();
			closeCustomContextMenu();
		});

		parent.on("mouseup", function(e) {
			if (e.button == 0) {
				// Stop link creation
				if (isCreatingLink != None) {
					if (startLinkBox != null && endLinkBox != null && createEdgeInShaderGraph()) {

					} else {
						if (currentLink != null) currentLink.remove();
						currentLink = null;
					}
					startLinkBox = endLinkBox = null;
					startLinkGrNode = endLinkNode = null;
					isCreatingLink = None;
					clearAvailableNodes();
					return;
				}
				return;
			}
		});

		parent.on("keydown", function(e) {

			if (e.shiftKey && e.keyCode != 16) {
				if (addMenu == null || !addMenu.is(":visible"))
					openAddMenu();

				return;
			}
			if (e.keyCode == 83 && e.ctrlKey) { // CTRL+S : save
				shaderGraph.save();
			}
		});

		parent.on("contextmenu", function(e) {
			var elements = [];

			var addNode = new Element("<div> Add node </div>");
			addNode.on("click", function(e) {
				contextMenuAddNode(Std.parseInt(contextMenu.css("left")), Std.parseInt(contextMenu.css("top")));
			});
			elements.push(addNode);

			var deleteNode = new Element("<div> Delete nodes </div>");
			deleteNode.on("click", function(e) {
				if (listOfBoxesSelected.length > 0) {
					if (ide.confirm("Delete all theses nodes ?")) {
						for (b in listOfBoxesSelected) {
							removeBox(b);
						}
						clearSelectionBoxes();
					}
				}
			});
			elements.push(deleteNode);

			customContextMenu(elements);
			e.preventDefault();
			return false;
		});

		element.find("#createParameter").on("click", function() {
			function createElement(name : String, type : Type) : Element {
				var elt = new Element('
					<div>
						<span> ${name} </span>
					</div>');
				elt.on("click", function() {
					createParameter(type);
				});
				return elt;
			}

			customContextMenu([
				createElement("Number", TFloat),
				createElement("Color", TVec(4, VFloat)),
				createElement("Texture", TSampler2D)
				]);
		});

		element.find("#launchCompileShader").on("click", function() {
			launchCompileShader();
		});

		element.find("#saveShader").on("click", function() {
			save();
		});

		element.find("#changeModel").on("click", function() {
			ide.chooseFile(["fbx"], function(path) {
				if( path == null ) return; // cancel
				sceneEditor.scene.s3d.removeChild(obj);
				obj = sceneEditor.scene.loadModel(path, true);
				saveDisplayState("customModel", path);
				sceneEditor.scene.s3d.addChild(obj);
				compileShader();
			});
		});

		element.find("#centerView").on("click", function() {
			centerView();
		});

		parametersList = element.find("#parametersList");

		editorMatrix.on("change", "input, select", function(ev) {
			try {
				shaderGraph.nodeUpdated(ev.target.closest(".box").id);
				launchCompileShader();
			} catch (e : Dynamic) {
				if (Std.is(e, ShaderException)) {
					error(e.msg, e.idBox);
				}
			}
		});

		addMenu = null;
		listOfClasses = new Map<String, Array<NodeInfo>>();
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

		updateMatrix();

		new Element("svg").ready(function(e) {

			for (node in shaderGraph.getNodes()) {
				var paramNode = Std.instance(node.instance, ShaderParam);
				if (paramNode != null) {
					var paramShader = shaderGraph.getParameter(paramNode.parameterId);
					paramNode.setName(paramShader.name);
					setDisplayValue(paramNode, paramShader.type, paramShader.defaultValue);
					shaderGraph.nodeUpdated(paramNode.id);
					addBox(new Point(node.x, node.y), ShaderParam, paramNode);
				} else {
					addBox(new Point(node.x, node.y), std.Type.getClass(node.instance), node.instance);
				}
			}

			new Element(".nodes").ready(function(e) {
				if (IsVisible()) {
					centerView();
					generateEdges();
				}
			});


			for (p in shaderGraph.parametersAvailable) {
				addParameter(p.id, p.name, p.type, p.defaultValue);
			}
		});
	}

	override function save() {
		var content = shaderGraph.save();
		currentSign = haxe.crypto.Md5.encode(content);
		sys.io.File.saveContent(getPath(), content);
		super.save();
		info("Shader saved");
	}

	function onRefresh() {

		plight = root.getAll(hrt.prefab.Light)[0];
		if( plight != null ) {
			this.light = sceneEditor.context.shared.contexts.get(plight).local3d;
			lightDirection = this.light.getDirection();
		}

		var saveCustomModel = getDisplayState("customModel");
		if (saveCustomModel != null)
			obj = sceneEditor.scene.loadModel(saveCustomModel, true);
		else
			obj = sceneEditor.scene.loadModel("fx/Common/PrimitiveShapes/Sphere.fbx", true);
		sceneEditor.scene.s3d.addChild(obj);

		element.find("#preview").first().append(sceneEditor.scene.element);

		if (IsVisible()) {
			launchCompileShader();
		} else {
			var timer = new Timer(VIEW_VISIBLE_CHECK_TIMER);
			timer.run = function() {
				if (IsVisible()) {
					centerView();
					generateEdges();
					launchCompileShader();
					timer.stop();
				}
			}
		}
	}

	function generateEdges() {
		for (box in listOfBoxes) {
			for (key in box.getInstance().getInputsKey()) {
				var input = box.getInstance().getInput(key);
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
	}

	function addParameter(id : Int, name : String, type : Type, ?value : Dynamic) {
		var elt = new Element('<div id="param_${id}" class="parameter" draggable="true" ></div>').appendTo(parametersList);
		var content = new Element('<div class="content" ></div>');
		content.hide();
		var defaultValue = new Element("<div><span>Default: </span></div>").appendTo(content);

		var typeName = "";
		switch(type) {
			case TFloat:
				var parentRange = new Element('<input type="range" type="range" min="-1" max="1" />').appendTo(defaultValue);
				var range = new hide.comp.Range(null, parentRange);
				var rangeInput = @:privateAccess range.f;
				rangeInput.on("mousedown", function(e) {
					elt.attr("draggable", "false");
				});
				rangeInput.on("mouseup", function(e) {
					elt.attr("draggable", "true");
				});
				if (value != null && value.length > 0) range.value = value;
				range.onChange = function(temp) {
					if (!shaderGraph.setParameterDefaultValue(id, range.value))
						return;
					var param = shaderGraph.getParameter(id);
					for (b in listOfBoxes) {
						var shaderParam = Std.instance(b.getInstance(), ShaderParam);
						if (shaderParam != null && shaderParam.parameterId == id) {
							setDisplayValue(shaderParam, param.type, param.defaultValue);
							b.generateProperties(editor);
						}
					}
					updateParam(param);
				};
				typeName = "Number";
			case TVec(4, VFloat):
				var parentPicker = new Element('<div style="width: 35px; height: 25px; display: inline-block;"></div>').appendTo(defaultValue);
				var picker = new hide.comp.ColorPicker(true, parentPicker);

				var start : h3d.Vector;
				if (value != null)
					start = h3d.Vector.fromArray(value);
				else
					start = h3d.Vector.fromArray([0, 0, 0, 1]);
				picker.value = start.toColor();

				picker.onChange = function(move) {
					var vecColor = h3d.Vector.fromColor(picker.value);
					if (!shaderGraph.setParameterDefaultValue(id, [vecColor.x, vecColor.y, vecColor.z, vecColor.w]))
						return;
					var param = shaderGraph.getParameter(id);
					for (b in listOfBoxes) {
						var shaderParam = Std.instance(b.getInstance(), ShaderParam);
						if (shaderParam != null && shaderParam.parameterId == id) {
							setDisplayValue(shaderParam, param.type, param.defaultValue);
							b.generateProperties(editor);
						}
					}
					updateParam(param);
				};
				typeName = "Color";
			case TSampler2D:
				var parentSampler = new Element('<input type="texturepath" field="sampler2d" />').appendTo(defaultValue);

				var tselect = new hide.comp.TextureSelect(null, parentSampler);
				if (value != null && value.length > 0) tselect.path = value;
				tselect.onChange = function() {
					if (!shaderGraph.setParameterDefaultValue(id, tselect.path))
						return;
					var param = shaderGraph.getParameter(id);
					for (b in listOfBoxes) {
						var shaderParam = Std.instance(b.getInstance(), ShaderParam);
						if (shaderParam != null && shaderParam.parameterId == id) {
							setDisplayValue(shaderParam, param.type, param.defaultValue);
							b.generateProperties(editor);
						}
					}
					updateParam(param);
				}
				typeName = "Texture";
			default:
		}

		var header = new Element('<div class="header">
									<div class="title">
										<i class="fa fa-chevron-right" ></i>
										<input class="input-title" type="input" value="${name}" />
									</div>
									<div class="type">
										<span>${typeName}</span>
									</div>
								</div>');

		header.appendTo(elt);
		content.appendTo(elt);
		var actionBtns = new Element('<div class="action-btns" ></div>').appendTo(content);
		var deleteBtn = new Element('<input type="button" value="Delete" />');
		deleteBtn.on("click", function() {
			for (b in listOfBoxes) {
				var shaderParam = Std.instance(b.getInstance(), ShaderParam);
				if (shaderParam != null && shaderParam.parameterId == id) {
					error("This parameter is used in the graph.");
					return;
				}
			}
			shaderGraph.removeParameter(id);
			elt.remove();
		});
		deleteBtn.appendTo(actionBtns);

		var inputTitle = elt.find(".input-title");
		inputTitle.on("click", function(e) {
			e.stopPropagation();
		});
		inputTitle.on("change", function(e) {
			var newName = inputTitle.val();
			if (shaderGraph.setParameterTitle(id, newName)) {
				for (b in listOfBoxes) {
					var shaderParam = Std.instance(b.getInstance(), ShaderParam);
					if (shaderParam != null && shaderParam.parameterId == id) {
						shaderParam.setName(newName);
					}
				}
			}
		});
		elt.find(".header").on("click", function() {
			toggleParameter(elt);
		});

		elt.on("dragstart", function(e) {
			draggedParamId = id;
		});

		return elt;
	}

	function setDisplayValue(node : ShaderParam, type : Type, defaultValue : Dynamic) {
		switch (type) {
			case TSampler2D:
				node.setDisplayValue('file://${ide.getPath(defaultValue)}');
			case TVec(4, VFloat):
				var vec = Vector.fromArray(defaultValue);
				var hexa = StringTools.hex(vec.toColor(),8);
				var hexaFormatted = "";
				if (hexa.length == 8) {
					hexaFormatted = hexa.substr(2, 6) + hexa.substr(0, 2);
				} else {
					hexaFormatted = hexa;
				}
				node.setDisplayValue('#${hexaFormatted}');
			default:
				node.setDisplayValue(defaultValue);
		}
	}

	function toggleParameter( elt : JQuery, ?b : Bool) {
		if (b != null) {
			if (b) {
				elt.find(".content").show();
				var icon = elt.find(".fa");
				icon.removeClass("fa-chevron-right");
				icon.addClass("fa-chevron-down");
			} else {
				elt.find(".content").hide();
				var icon = elt.find(".fa");
				icon.addClass("fa-chevron-right");
				icon.removeClass("fa-chevron-down");
			}
		} else {
			elt.find(".content").toggle();
			var icon = elt.find(".fa");
			if (icon.hasClass("fa-chevron-right")) {
				icon.removeClass("fa-chevron-right");
				icon.addClass("fa-chevron-down");
			} else {
				icon.addClass("fa-chevron-right");
				icon.removeClass("fa-chevron-down");
			}
		}
	}

	function createParameter(type : Type) {
		var paramShaderID = shaderGraph.addParameter(type);
		var paramShader = shaderGraph.getParameter(paramShaderID);

		var elt = addParameter(paramShaderID, paramShader.name, type, null);

		elt.find(".input-title").focus();
	}

	function launchCompileShader() {
		if (timerCompileShader != null) {
			timerCompileShader.stop();
		}
		timerCompileShader = new Timer(COMPILE_SHADER_DEBOUNCE);
		timerCompileShader.run = function() {
			compileShader();
			timerCompileShader.stop();
		};
	}

	function compileShader() {
		var newShader : DynamicShader = null;
		try {
			sceneEditor.scene.setCurrent();
			var timeStart = Date.now().getTime();

			if (currentShader != null)
				for (m in obj.getMaterials())
					m.mainPass.removeShader(currentShader);

			var shaderGraphDef = shaderGraph.compile();
			newShader = new hxsl.DynamicShader(shaderGraphDef.shader);
			for (init in shaderGraphDef.inits) {
				setParamValue(newShader, init.variable, init.value);
			}
			for (m in obj.getMaterials()) {
				m.mainPass.addShader(newShader);
			}
			@:privateAccess sceneEditor.scene.render(sceneEditor.scene.engine);
			currentShader = newShader;
			info('Shader compiled in  ${Date.now().getTime() - timeStart}ms');

		} catch (e : Dynamic) {
			if (Std.is(e, String)) {
				var str : String = e;
				if (str.split(":")[0] == "An error occurred compiling the shaders") {
					var strSplitted = str.split("(output_");
					var idBox = strSplitted[1].split("_")[0];
					var idBoxParsed = Std.parseInt(idBox);
					if (Std.string(idBoxParsed) == idBox) {
						error("Compilation of shader failed > Invalid inputs", idBoxParsed);
					} else {
						error("Compilation of shader failed > " + str);
					}
					if (newShader != null)
						for (m in obj.getMaterials())
							m.mainPass.removeShader(newShader);
					if (currentShader != null) {
						for (m in obj.getMaterials()) {
							m.mainPass.addShader(currentShader);
						}
					}
					return;
				}
			} else if (Std.is(e, ShaderException)) {
				error(e.msg, e.idBox);
				return;
			}
			error("Compilation of shader failed > " + e);
			if (newShader != null)
				for (m in obj.getMaterials())
					m.mainPass.removeShader(newShader);
			if (currentShader != null) {
				for (m in obj.getMaterials()) {
					m.mainPass.addShader(currentShader);
				}
			}
		}
	}

	function updateParam(param : Parameter) {
		setParamValue(currentShader, param.variable, param.defaultValue);
	}

	function setParamValue(shader : DynamicShader, variable : hxsl.Ast.TVar, value : Dynamic) {
		try {
			switch (variable.type) {
				case TSampler2D:
					shader.setParamValue(variable, hxd.Res.load(value).toTexture());
				default:
					if (variable.name.toLowerCase().indexOf("color") != -1) {
						shader.setParamValue(variable, Vector.fromArray(value));
					} else {
						shader.setParamValue(variable, value);
					}
			}
		} catch (e : Dynamic) {
			// The parameter is not used
		}
	}

	function addNode(p : Point, nodeClass : Class<ShaderNode>) {
		var node = shaderGraph.addNode(p.x, p.y, nodeClass);

		addBox(p, nodeClass, node);

		return node;
	}

	function createEdgeInShaderGraph() : Bool {
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
		try {
			if (shaderGraph.addEdge({ idOutput: startLinkBox.getId(), nameOutput: startLinkNode.attr("field"), idInput: endLinkBox.getId(), nameInput: endLinkNode.attr("field") })) {
				createEdgeInEditorGraph(newEdge);
				currentLink.removeClass("draft");
				currentLink = null;
				launchCompileShader();
				return true;
			} else {
				error("This edge creates a cycle.");
				return false;
			}
		} catch (e : Dynamic) {
			if (Std.is(e, ShaderException)) {
				error(e.msg, e.idBox);
			}
			return false;
		}
	}

	function openAddMenu(?x : Int, ?y : Int) {
		if (x == null) x = 0;
		if (y == null) y = 0;
		if (addMenu != null) {
			var input = addMenu.find("#search-input");
			input.val("");
			addMenu.show();
			input.focus();
			var posCursor = new IPoint(Std.int(ide.mouseX - parent.offset().left) + x, Std.int(ide.mouseY - parent.offset().top) + y);

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
					<input type="text" id="search-input" autocomplete="off" >
				</div>
			</div>
			<div id="results">
			</div>
		</div>').appendTo(parent);

		var posCursor = new IPoint(Std.int(ide.mouseX - parent.offset().left) + x, Std.int(ide.mouseY - parent.offset().top) + y);

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
		input.on("keyup", function(ev) {
			if (ev.keyCode == 38 || ev.keyCode == 40) {
				return;
			}

			if (ev.keyCode == 13) {
				var key = this.selectedNode.attr("node");
				var posCursor = new Point(lX(ide.mouseX - 25), lY(ide.mouseY - 10));
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
			if (this.selectedNode != null)
				this.selectedNode.removeClass("selected");
			this.selectedNode = ev.getThis();
			this.selectedNode.addClass("selected");
		});
		divs.mouseup(function(ev) {
			if (ev.getThis().hasClass("group")) {
				return;
			}
			var key = ev.getThis().attr("node");
			var posCursor = new Point(lX(ide.mouseX - 25), lY(ide.mouseY - 10));
			addNode(posCursor, ShaderNode.registeredNodes[key]);
			closeAddMenu();
		});
	}

	function closeAddMenu() {
		if (addMenu != null) {
			addMenu.hide();
			parent.focus();
		}
	}


	// CONTEXT MENU
	function contextMenuAddNode(x : Int, y : Int) {
		var elements = [];
		var searchItem = new Element("<div class='grey-item' >Search</div>");
		searchItem.on("click", function() {
			openAddMenu(-40, -16);
		});
		elements.push(searchItem);

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
			var group = new Element('<div> ${key} </div>');
			group.on("click", function(e) {
				var eltsGroup = [];
				var goBack = new Element("<div class='grey-item' > <i class='fa fa-chevron-left' /> Go back </div>");
				goBack.on("click", function(e) {
					contextMenuAddNode(Std.parseInt(contextMenu.css("left")), Std.parseInt(contextMenu.css("top")));
				});
				eltsGroup.push(goBack);
				for (node in listOfClasses[key]) {
					var itemNode = new Element('
						<div >
							<span> ${node.name} </span>
						</div>');
					itemNode.on("click", function() {
						var posCursor = new Point(lX(ide.mouseX - 25), lY(ide.mouseY - 10));
						addNode(posCursor, ShaderNode.registeredNodes[node.key]);
					});
					eltsGroup.push(itemNode);
				}
				customContextMenu(eltsGroup, Std.parseInt(contextMenu.css("left")), Std.parseInt(contextMenu.css("top")));
			});
			elements.push(group);
		}
		customContextMenu(elements, x, y);
	}

	// Graph methods

	override function addBox(p : Point, nodeClass : Class<ShaderNode>, node : ShaderNode) : Box {
		var box = super.addBox(p, nodeClass, node);

		if (nodeClass == ShaderParam) {
			var paramId = Std.instance(node, ShaderParam).parameterId;
			box.getElement().on("dblclick", function(e) {
				var parametersElements = parametersList.find(".parameter");
				for (elt in parametersElements.elements()) {
					toggleParameter(elt, false);
				}
				var elt = parametersList.find("#param_" + paramId);
				if (elt != null && elt.length > 0)
					toggleParameter(elt, true);
				var offsetScroll = elt.offset().top - parametersList.offset().top;
				if (offsetScroll < 0 || offsetScroll + elt.height() > parametersList.height()) {
					parametersList.scrollTop(parametersList.scrollTop() + offsetScroll);
				}
			});
		}

		return box;
	}

	override function removeBox(box : Box) {
		super.removeBox(box);
		shaderGraph.removeNode(box.getId());
	}

	override function removeEdge(edge : Graph.Edge) {
		super.removeEdge(edge);
		shaderGraph.removeEdge(edge.to.getId(), edge.nodeTo.attr("field"));
		launchCompileShader();
	}

	override function updatePosition(id : Int, x : Float, y : Float) {
		shaderGraph.setPosition(id, x, y);
	}


	static var _ = FileTree.registerExtension(ShaderEditor,["hlshader"],{ icon : "scribd" });

}
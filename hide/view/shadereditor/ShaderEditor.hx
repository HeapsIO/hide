package hide.view.shadereditor;

import hrt.shgraph.nodes.SubGraph;
import hxsl.DynamicShader;
import h3d.Vector;
import hrt.shgraph.ShaderParam;
import hrt.shgraph.ShaderException;
import haxe.Timer;
using hxsl.Ast.Type;

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
	var defaultLight : hrt.prefab.Light;

	var root : hrt.prefab.Prefab;
	var obj : h3d.scene.Object;
	var prefabObj : hrt.prefab.Prefab;
	var shaderGraph : ShaderGraph;

	var lastSnapshot : haxe.Json;

	var timerCompileShader : Timer;
	var COMPILE_SHADER_DEBOUNCE : Int = 100;
	var VIEW_VISIBLE_CHECK_TIMER : Int = 500;
	var currentShader : DynamicShader;
	var currentShaderDef : hrt.prefab.ContextShared.ShaderDef;

	override function onDisplay() {
		super.onDisplay();
		shaderGraph = new ShaderGraph(state.path);
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
								<input id="togglelight" type="button" value="Toggle Default Lights" />
							</div>
						</div>)');
		parent.on("drop", function(e) {
			var posCursor = new Point(lX(ide.mouseX - 25), lY(ide.mouseY - 10));
			var node = Std.downcast(shaderGraph.addNode(posCursor.x, posCursor.y, ShaderParam), ShaderParam);
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
		defaultLight = new hrt.prefab.Light(def);
		defaultLight.name = "sunLight";
		defaultLight.kind = Directional;
		defaultLight.power = 1.5;
		var q = new h3d.Quat();
		q.initDirection(new h3d.Vector(-1,-1.5,-3));
		var a = q.toEuler();
		defaultLight.rotationX = Math.round(a.x * 180 / Math.PI);
		defaultLight.rotationY = Math.round(a.y * 180 / Math.PI);
		defaultLight.rotationZ = Math.round(a.z * 180 / Math.PI);
		defaultLight.shadows.mode = Dynamic;
		defaultLight.shadows.size = 1024;
		root = def;

		sceneEditor = new hide.comp.SceneEditor(this, root);
		sceneEditor.editorDisplay = false;
		sceneEditor.onRefresh = onRefresh;
		sceneEditor.onUpdate = function(dt : Float) {};
		sceneEditor.objectAreSelectable = false;
		sceneEditor.view.keys = new hide.ui.Keys(null); // Remove SceneEditor Shortcuts

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

		element.on("keydown", function(e) {
			if (e.ctrlKey && e.keyCode == 83) {
				save();
				return;
			}
		});
		element.on("keyup", function(e) {
			if (e.keyCode == 32) {
				if (addMenu == null || !addMenu.is(":visible"))
					openAddMenu(-40, -70);
			}
		});

		keys = new hide.ui.Keys(element);
		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());
		keys.register("sceneeditor.focus", centerView);

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
			ide.chooseFile(["fbx", "l3d", "prefab"], function(path) {
				sceneEditor.scene.setCurrent();
				if( prefabObj != null ) {
					sceneEditor.deleteElements([prefabObj], false, false);
					prefabObj = null;
				}
				else {
					sceneEditor.scene.s3d.removeChild(obj);
				}
				loadPreviewPrefab(path);
				saveDisplayState("customModel", path);
				if( prefabObj == null )
					sceneEditor.scene.s3d.addChild(obj);
				compileShader();
			});
		});

		element.find("#centerView").on("click", function() {
			centerView();
		})
			.prop("title", 'Center around full graph (${config.get("key.sceneeditor.focus")})');

		element.find("#togglelight").on("click", toggleDefaultLight);

		parametersList = element.find("#parametersList");

		editorMatrix.on("click", "input, select", function(ev) {
			beforeChange();
		});

		editorMatrix.on("change", "input, select", function(ev) {
			try {
				var idBox = ev.target.closest(".box").id;
				for (b in listOfBoxes) {
					if (b.getId() == idBox) {
						var subGraph = Std.downcast(b.getInstance(), hrt.shgraph.nodes.SubGraph);
						if (subGraph != null) {
							if (ev.currentTarget.getAttribute('field') != "filesubgraph") {
								break;
							}
							var length = listOfEdges.length;
							for (i in 0...length) {
								var edge = listOfEdges[length-i-1];
								if (edge.from == b || edge.to == b) {
									removeShaderGraphEdge(edge);
								}
							}
							refreshBox(b);
							afterChange();
							return;
						}
						break;
					}
				}
				shaderGraph.nodeUpdated(idBox);
				afterChange();
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

		new Element("svg").ready(function(e) {
			refreshShaderGraph();
			if (IsVisible()) {
				centerView();
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

	function loadPreviewPrefab(path : String) {
		if( path == null )
			return;
		prefabObj = null;
		var ext = haxe.io.Path.extension(path).toLowerCase();
		var relative = ide.makeRelative(path);
		if( ext == "fbx" )
			obj = sceneEditor.scene.loadModel(path, true);
		else if( hrt.prefab.Library.getPrefabType(relative) != null ) {
			var ref = new hrt.prefab.Reference(root);
			ref.source = relative;
			sceneEditor.addElements([ref], false, true, false);
			prefabObj = ref;
			obj = sceneEditor.getContext(prefabObj).local3d;
		}
	}

	function onRefresh() {
		var saveCustomModel = getDisplayState("customModel");
		if (saveCustomModel != null)
			loadPreviewPrefab(saveCustomModel);
		else {
			// obj = sceneEditor.scene.loadModel("res/PrimitiveShapes/Sphere.fbx", true);
			var sp = new h3d.prim.Sphere(1, 128, 128);
			sp.addNormals();
			sp.addUVs();
			obj = new h3d.scene.Mesh(sp);
		}
		if( prefabObj == null )
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
		@:privateAccess sceneEditor.scene.window.checkResize();
	}

	function toggleDefaultLight() {
		sceneEditor.setEnabled([defaultLight], !defaultLight.enabled);
	}

	function refreshShaderGraph(readyEvent : Bool = true) {

		listOfBoxes = [];
		listOfEdges = [];

		var saveToggleParams = new Map<Int, Bool>();
		for (pElt in parametersList.find(".parameter").elements()) {
			saveToggleParams.set(Std.parseInt(pElt.get()[0].id.split("_")[1]), pElt.find(".content").css("display") != "none");
		}
		parametersList.empty();
		editorMatrix.empty();

		updateMatrix();

		for (node in shaderGraph.getNodes()) {
			var shaderPreview = Std.downcast(node.instance, hrt.shgraph.nodes.Preview);
			if (shaderPreview != null) {
				shaderPreview.config = config;
				shaderPreview.shaderGraph = shaderGraph;
				addBox(new Point(node.x, node.y), std.Type.getClass(node.instance), shaderPreview);
				continue;
			}
			var paramNode = Std.downcast(node.instance, ShaderParam);
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

		if (readyEvent) {
			new Element(".nodes").ready(function(e) {
				if (IsVisible()) {
					generateEdges();
				}
			});
		} else {
			generateEdges();
		}


		for (p in shaderGraph.parametersAvailable) {
			var pElt = addParameter(p.id, p.name, p.type, p.defaultValue);
			if (saveToggleParams.get(p.id)) {
				toggleParameter(pElt, true);
			}
		}

		launchCompileShader();
	}

	function generateEdgesFromBox(box : Box) {
		for (outputKey in box.getInstance().getOutputInfoKeys()) {
			var output = box.getInstance().getOutput(outputKey);
			if (output != null) {
				for (b in listOfBoxes) {
					for (key in b.getInstance().getInputsKey()) {
						var input = b.getInstance().getInput(key);
						if (input != null && input.node.id == box.getId()) {
							var nodeFrom = box.getElement().find('[field=${outputKey}]');
							var nodeTo = b.getElement().find('[field=${key}]');
							createEdgeInEditorGraph({from: box, nodeFrom: nodeFrom, to : b, nodeTo: nodeTo, elt : createCurve(nodeFrom, nodeTo) });
						}
					}
				}
			}
		}
	}

	function generateEdgesToBox(box : Box) {
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

	function generateEdges() {
		for (box in listOfBoxes) {
			generateEdgesToBox(box);
		}
	}

	function refreshBox(box : Box) {
		var length = listOfEdges.length;
		for (i in 0...length) {
			var edge = listOfEdges[length-i-1];
			if (edge.from == box || edge.to == box) {
				super.removeEdge(edge);
			}
		}
		var indexInputStartLink = -1;
		if (startLinkBox == box) {
			var nodeInputJQuery = startLinkGrNode.find(".node");
			for (i in 0...box.inputs.length) {
				if (box.inputs[i].is(nodeInputJQuery)) {
					indexInputStartLink = i;
					break;
				}
			}
		}
		var newBox : Box = addBox(new Point(box.getX(), box.getY()), std.Type.getClass(box.getInstance()), box.getInstance());
		box.dispose();
		listOfBoxes.remove(box);
		generateEdgesToBox(newBox);
		generateEdgesFromBox(newBox);
		if (indexInputStartLink >= 0) {
			startLinkBox = newBox;
			startLinkGrNode = newBox.inputs[indexInputStartLink].parent();
		}
		return newBox;
	}

	function addParameter(id : Int, name : String, type : Type, ?value : Dynamic) {

		var elt = new Element('<div id="param_${id}" class="parameter" draggable="true" ></div>').appendTo(parametersList);
		var content = new Element('<div class="content" ></div>');
		content.hide();
		var defaultValue = new Element("<div><span>Default: </span></div>").appendTo(content);

		var typeName = "";
		switch(type) {
			case TFloat:
				var parentRange = new Element('<input type="range" min="-1" max="1" />').appendTo(defaultValue);
				var range = new hide.comp.Range(null, parentRange);
				var rangeInput = @:privateAccess range.f;
				rangeInput.on("mousedown", function(e) {
					elt.attr("draggable", "false");
					beforeChange();
				});
				rangeInput.on("mouseup", function(e) {
					elt.attr("draggable", "true");
					afterChange();
				});
				if (value == null) value = 0;
				range.value = value;
				shaderGraph.setParameterDefaultValue(id, value);
				range.onChange = function(moving) {
					if (!shaderGraph.setParameterDefaultValue(id, range.value))
						return;
					setBoxesParam(id);
					updateParam(id);
				};
				typeName = "Number";
			case TVec(4, VFloat):
				var parentPicker = new Element('<div style="width: 35px; height: 25px; display: inline-block;"></div>').appendTo(defaultValue);
				var picker = new hide.comp.ColorPicker(true, parentPicker);


				if (value == null)
					value = [0, 0, 0, 1];
				var start : h3d.Vector = h3d.Vector.fromArray(value);
				shaderGraph.setParameterDefaultValue(id, value);
				picker.value = start.toColor();
				picker.onChange = function(move) {
					var vecColor = h3d.Vector.fromColor(picker.value);
					if (!shaderGraph.setParameterDefaultValue(id, [vecColor.x, vecColor.y, vecColor.z, vecColor.w]))
						return;
					setBoxesParam(id);
					updateParam(id);
				};
				picker.element.on("dragstart.spectrum", function() {
					beforeChange();
				});
				picker.element.on("dragstop.spectrum", function() {
					afterChange();
				});
				typeName = "Color";
			case TSampler2D:
				var parentSampler = new Element('<input type="texturepath" field="sampler2d" />').appendTo(defaultValue);

				var tselect = new hide.comp.TextureSelect(null, parentSampler);
				if (value != null && value.length > 0) tselect.path = value;
				tselect.onChange = function() {
					beforeChange();
					if (!shaderGraph.setParameterDefaultValue(id, tselect.path))
						return;
					afterChange();
					setBoxesParam(id);
					updateParam(id);
				}
				typeName = "Texture";
			default:
		}

		var header = new Element('<div class="header">
									<div class="title">
										<i class="ico ico-chevron-right" ></i>
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
				var shaderParam = Std.downcast(b.getInstance(), ShaderParam);
				if (shaderParam != null && shaderParam.parameterId == id) {
					error("This parameter is used in the graph.");
					return;
				}
			}
			beforeChange();
			shaderGraph.removeParameter(id);
			afterChange();
			elt.remove();
		});
		deleteBtn.appendTo(actionBtns);

		var inputTitle = elt.find(".input-title");
		inputTitle.on("click", function(e) {
			e.stopPropagation();
		});
		inputTitle.on("keydown", function(e) {
			e.stopPropagation();
		});
		inputTitle.on("change", function(e) {
			var newName = inputTitle.val();
			if (shaderGraph.setParameterTitle(id, newName)) {
				for (b in listOfBoxes) {
					var shaderParam = Std.downcast(b.getInstance(), ShaderParam);
					if (shaderParam != null && shaderParam.parameterId == id) {
						beforeChange();
						shaderParam.setName(newName);
						afterChange();
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

	function setBoxesParam(id : Int) {
		var param = shaderGraph.getParameter(id);
		for (b in listOfBoxes) {
			var shaderParam = Std.downcast(b.getInstance(), ShaderParam);
			if (shaderParam != null && shaderParam.parameterId == id) {
				setDisplayValue(shaderParam, param.type, param.defaultValue);
				b.generateProperties(editor);
			}
		}
	}

	function setDisplayValue(node : ShaderParam, type : Type, defaultValue : Dynamic) {
		switch (type) {
			case TSampler2D:
				if (defaultValue != null && defaultValue.length > 0)
					node.setDisplayValue('file://${ide.getPath(defaultValue)}');
			case TVec(4, VFloat):
				if (defaultValue != null && defaultValue.length > 0) {
					var vec = Vector.fromArray(defaultValue);
					var hexa = StringTools.hex(vec.toColor(),8);
					var hexaFormatted = "";
					if (hexa.length == 8) {
						hexaFormatted = hexa.substr(2, 6) + hexa.substr(0, 2);
					} else {
						hexaFormatted = hexa;
					}
					node.setDisplayValue('#${hexaFormatted}');
				}
			default:
				node.setDisplayValue(defaultValue);
		}
	}

	function toggleParameter( elt : JQuery, ?b : Bool) {
		if (b != null) {
			if (b) {
				elt.find(".content").show();
				var icon = elt.find(".ico");
				icon.removeClass("ico-chevron-right");
				icon.addClass("ico-chevron-down");
			} else {
				elt.find(".content").hide();
				var icon = elt.find(".ico");
				icon.addClass("ico-chevron-right");
				icon.removeClass("ico-chevron-down");
			}
		} else {
			elt.find(".content").toggle();
			var icon = elt.find(".ico");
			if (icon.hasClass("ico-chevron-right")) {
				icon.removeClass("ico-chevron-right");
				icon.addClass("ico-chevron-down");
			} else {
				icon.addClass("ico-chevron-right");
				icon.removeClass("ico-chevron-down");
			}
		}
	}

	function createParameter(type : Type) {
		beforeChange();
		var paramShaderID = shaderGraph.addParameter(type);
		afterChange();
		var paramShader = shaderGraph.getParameter(paramShaderID);

		var elt = addParameter(paramShaderID, paramShader.name, type, null);
		updateParam(paramShaderID);

		elt.find(".input-title").focus();
	}

	function launchCompileShader() {
		if (timerCompileShader != null) {
			timerCompileShader.stop();
		}
		timerCompileShader = new Timer(COMPILE_SHADER_DEBOUNCE);
		timerCompileShader.run = function() {
			timerCompileShader.stop();
			compileShader();
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
			sceneEditor.scene.render(sceneEditor.scene.engine);
			currentShader = newShader;
			currentShaderDef = shaderGraphDef;
			info('Shader compiled in  ${Date.now().getTime() - timeStart}ms');

		} catch (e : Dynamic) {
			if (Std.is(e, String)) {
				var str : String = e;
				trace(str);
				if (str.split(":")[0] == "An error occurred compiling the shaders") {
					var strSplitted = str.split("(output_");
					if (strSplitted.length >= 2) {
						var idBox = strSplitted[1].split("_")[0];
						var idBoxParsed = Std.parseInt(idBox);
						if (Std.string(idBoxParsed) == idBox) {
							error("Compilation of shader failed > Invalid inputs", idBoxParsed);
						} else {
							error("Compilation of shader failed > " + str);
						}
					} else {
						var nameOutput = str.split("(")[1].split(" =")[0];
						var errorSent = false;
						for (b in listOfBoxes) {
							var shaderOutput = Std.downcast(b.getInstance(), hrt.shgraph.ShaderOutput);
							if (shaderOutput != null) {
								if (shaderOutput.variable.name == nameOutput) {
									error("Compilation of shader failed > Invalid inputs", shaderOutput.id);
									errorSent = true;
									break;
								}
							}
							if (!errorSent) {
								error("Compilation of shader failed > " + str);
							}
						}
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
			trace(e.stack);
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

	function updateParam(id : Int) {
		sceneEditor.scene.setCurrent();
		var param = shaderGraph.getParameter(id);
		setParamValueByName(currentShader, param.name, param.defaultValue);
		for (b in listOfBoxes) {
			var previewBox = Std.downcast(b.getInstance(), hrt.shgraph.nodes.Preview);
			if (previewBox != null) {
				previewBox.setParamValueByName(param.variable.name, param.defaultValue);
			}
		}
	}

	function setParamValueByName(shader : DynamicShader, varName : String, value : Dynamic) {
		if (currentShaderDef == null) return;
		for (init in currentShaderDef.inits) {
			if (init.variable.name == varName) {
				setParamValue(shader, init.variable, value);
				return;
			}
		}
	}

	function setParamValue(shader : DynamicShader, variable : hxsl.Ast.TVar, value : Dynamic) {
		@:privateAccess ShaderGraph.setParamValue(sceneEditor.context.shared, shader, variable, value);
	}

	function addNode(p : Point, nodeClass : Class<ShaderNode>) {
		beforeChange();

		var node = shaderGraph.addNode(p.x, p.y, nodeClass);
		afterChange();

		var shaderPreview = Std.downcast(node, hrt.shgraph.nodes.Preview);
		if (shaderPreview != null) {
			shaderPreview.config = config;
			shaderPreview.shaderGraph = shaderGraph;
			addBox(p, nodeClass, shaderPreview);
			return node;
		}

		var subGraphNode = Std.downcast(node, hrt.shgraph.nodes.SubGraph);
		if (subGraphNode != null) {
			subGraphNode.loadGraphShader();
			addBox(p, nodeClass, subGraphNode);
			return node;
		}

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
					super.removeEdge(edge);
					removeShaderGraphEdge(edge);
					break;
				}
			}
		}
		try {
			beforeChange();
			if (shaderGraph.addEdge({ idOutput: startLinkBox.getId(), nameOutput: startLinkNode.attr("field"), idInput: endLinkBox.getId(), nameInput: endLinkNode.attr("field") })) {
				afterChange();
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

		var boundsWidth = Std.parseInt(element.css("width"));
		var boundsHeight = Std.parseInt(element.css("height"));

		var posCursor = new IPoint(Std.int(ide.mouseX - parent.offset().left) + x, Std.int(ide.mouseY - parent.offset().top) + y);
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
		</div>').appendTo(parent);

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
					if (value.length == 0 || elt.children().first().html().toLowerCase().indexOf(value.toLowerCase()) == 1) {
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
				var goBack = new Element("<div class='grey-item' > <i class='ico ico-chevron-left' /> Go back </div>");
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

	function beforeChange() {
		lastSnapshot = haxe.Json.parse(shaderGraph.save());
	}

	function afterChange() {
		var newVal = haxe.Json.parse(shaderGraph.save());
		var oldVal = lastSnapshot;
		undo.change(Custom(function(undo) {
			if (undo)
				shaderGraph.load(oldVal);
			else
				shaderGraph.load(newVal);
			refreshShaderGraph(false);
		}));
	}

	function removeShaderGraphEdge(edge : Graph.Edge) {
		shaderGraph.removeEdge(edge.to.getId(), edge.nodeTo.attr("field"));
	}

	function removeEdgeSubGraphUpdate(edge : Graph.Edge) {
		var subGraph = Std.downcast(edge.to.getInstance(), hrt.shgraph.nodes.SubGraph);
		if (subGraph != null) {
			var field = "";
			if (isCreatingLink == FromInput) {
				field = edge.nodeTo.attr("field");
			} else {
				field = edge.nodeFrom.attr("field");
			}
			var newBox = refreshBox(edge.to);
			subGraph.loadGraphShader();

			clearAvailableNodes();
			if (isCreatingLink == FromInput) {
				setAvailableOutputNodes(newBox, field);
			} else {
				setAvailableInputNodes(edge.from, field);
			}
		}
	}

	// Graph methods

	override function addBox(p : Point, nodeClass : Class<ShaderNode>, node : ShaderNode) : Box {
		var box = super.addBox(p, nodeClass, node);

		if (nodeClass == ShaderParam) {
			var paramId = Std.downcast(node, ShaderParam).parameterId;
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
		} else if (nodeClass == SubGraph) {
			var subGraphNode = Std.downcast(node, SubGraph);
			if (subGraphNode.pathShaderGraph != null) {
				var filename = subGraphNode.pathShaderGraph.split("/").pop();
				box.setTitle("SubGraph: " + filename.split(".")[0]);
			}
		}

		return box;
	}

	override function removeBox(box : Box) {
		beforeChange();
		var isSubShader = Std.is(box.getInstance(), SubGraph);
		var length = listOfEdges.length;
		for (i in 0...length) {
			var edge = listOfEdges[length-i-1];
			if (edge.from == box || edge.to == box) {
				super.removeEdge(edge);
				removeShaderGraphEdge(edge);
				if (!isSubShader) removeEdgeSubGraphUpdate(edge);
			}
		}
		shaderGraph.removeNode(box.getId());
		afterChange();
		box.dispose();
		listOfBoxes.remove(box);
		launchCompileShader();
	}

	override function removeEdge(edge : Graph.Edge) {
		super.removeEdge(edge);
		beforeChange();
		removeShaderGraphEdge(edge);
		afterChange();
		removeEdgeSubGraphUpdate(edge);
		launchCompileShader();
	}

	override function updatePosition(box : Box) {
		var previewBox = Std.downcast(box.getInstance(), hrt.shgraph.nodes.Preview);
		if (previewBox != null){
			previewBox.onMove(gX(box.getX()), gY(box.getY()), transformMatrix[0]);
		}
		shaderGraph.setPosition(box.getId(), box.getX(), box.getY());
	}

	override function updateMatrix() {
		super.updateMatrix();
		for (b in listOfBoxes) {
			var previewBox = Std.downcast(b.getInstance(), hrt.shgraph.nodes.Preview);
			if (previewBox != null){
				previewBox.onMove(gX(b.getX()), gY(b.getY()), transformMatrix[0]);
			}
		}
	}

	override function getDefaultContent() {
		var p = { nodes: [], edges: [], parameters: [] };
		return haxe.io.Bytes.ofString(ide.toJSON(p));
	}

	override function onDragDrop(items : Array<String>, isDrop : Bool) {
		var valid = false;
		var offset = 0;
		for (i in items) {
			if (i.indexOf("hlshader") != -1 && i != state.path) {
				if (isDrop) {
					var posCursor = new Point(lX(ide.mouseX - 25 + offset), lY(ide.mouseY - 10 + offset));
					var node : SubGraph = cast addNode(posCursor, SubGraph);
					@:privateAccess node.pathShaderGraph = i;
					node.loadGraphShader();
					offset += 25;
				}
				valid = true;
			}
		}
		if (valid && isDrop) {
			refreshShaderGraph();
		}
		return valid;
	}

	static var _ = FileTree.registerExtension(ShaderEditor,["hlshader"],{ icon : "scribd", createNew: "Shader Graph" });

}
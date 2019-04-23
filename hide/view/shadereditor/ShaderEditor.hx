package hide.view.shadereditor;

import hrt.shgraph.ShaderException;
import haxe.Timer;
using hxsl.Ast.Type;

import haxe.rtti.Meta;
import hxsl.Shader;
import hxsl.SharedShader;
import hide.comp.SceneEditor;
import js.jquery.JQuery;
import h2d.col.Point;
import h2d.col.IPoint;
import hide.view.shadereditor.Box;
import hrt.shgraph.ShaderGraph;
import hrt.shgraph.ShaderNode;

class ShaderEditor extends hide.view.Graph {

	var parametersList : JQuery;

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
	var shaderGenerated : Shader;

	override function onDisplay() {
		super.onDisplay();
		shaderGraph = new ShaderGraph(getPath());
		addMenu = null;

		element.find("#rightPanel").append(new Element('
						<span>Parameters</span>
						<div class="tab expand" name="Scene" icon="sitemap">
							<div class="hide-block" >
								<div id="parametersList" class="hide-scene-tree hide-list">
								</div>
							</div>
							<div class="options-block hide-block">
								<input id="addParameter" type="button" value="Add parameter" />
								<input id="launchCompileShader" type="button" value="Compile shader" />
								<input id="saveShader" type="button" value="Save" />
							</div>
						</div>)'));


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
				openAddMenu();

				return;
			}
			if (e.keyCode == 83 && e.ctrlKey) { // CTRL+S : save
				shaderGraph.save();
			}
		});

		element.find("#addParameter").on("click", function() {
			function createElement(name : String, type : Type) : Element {
				var elt = new Element('
					<div>
						<span> ${name} </span>
					</div>');
				elt.on("click", function() {
					addParameter(type);
				});
				return elt;
			}

			customContextMenu([
				createElement("Boolean", TBool),
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
		listOfClasses = new Map<String, Array<Graph.NodeInfo>>();
		var mapOfNodes = ShaderNode.registeredNodes;
		for (key in mapOfNodes.keys()) {
			var metas = haxe.rtti.Meta.getType(mapOfNodes[key]);
			if (metas.group == null) {
				continue;
			}
			var group = metas.group[0];

			if (listOfClasses[group] == null)
				listOfClasses[group] = new Array<Graph.NodeInfo>();

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
				addBox(new Point(node.x, node.y), std.Type.getClass(node.instance), node.instance);
			}

			new Element(".nodes").ready(function(e) {

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

			});
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

		obj = sceneEditor.scene.loadModel("fx/Common/PrimitiveShapes/Sphere.fbx", true);
		sceneEditor.scene.s3d.addChild(obj);

		element.find("#preview").first().append(sceneEditor.scene.element);

		launchCompileShader();
	}

	function addParameter(type : Type, ?title : String, ?value : Dynamic) {

		//TODO: link with shadergraph
		//TODO: drag to graph
		//TODO: edit => edit everywhere
		//TODO: type sampler => file choosen

		var exist = (title != null);

		var elt = new Element('<div class="parameter"></div>').appendTo(parametersList);
		var content = new Element('<div class="content" ></div>');
		var defaultValue = new Element("<div><span>Default: </span></div>").appendTo(content);
		if (!exist) content.hide();

		var typeName = "";

		switch(type) {
			case TBool:
				var checkbox = new Element('<input type="checkbox" />');
				checkbox.prop("checked", ${(value != null && value == "true") ? true : false});
				defaultValue.append(checkbox);
				typeName = "Boolean";
			default:
				defaultValue.append(new Element('<input type="text" value="${(value != null) ? value : ""}" />'));
				typeName = "String";
		}

		var header = new Element('<div class="header">
									<div class="title">
										<i class="fa fa-chevron-right" ></i>
										<input class="input-title" type="input" value="${(title != null) ? title : ""}" />
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
			elt.remove();
		});
		deleteBtn.appendTo(actionBtns);


		var inputTitle = elt.find(".input-title");
		inputTitle.on("click", function(e) {
			e.stopPropagation();
		});
		inputTitle.on("change", function(e) {
		});
		elt.find(".header").on("click", function(ev) {
			elt.find(".content").toggle();
			var icon = elt.find(".fa");
			if (icon.hasClass("fa-chevron-right")) {
				icon.removeClass("fa-chevron-right");
				icon.addClass("fa-chevron-down");
			} else {
				icon.addClass("fa-chevron-right");
				icon.removeClass("fa-chevron-down");
			}
		});
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
		var saveShader : Shader = null;
		if (shaderGenerated != null)
			saveShader = shaderGenerated.clone();
		try {
			var timeStart = Date.now().getTime();
			var s = new SharedShader("");
			s.data = shaderGraph.buildFragment();
			@:privateAccess s.initialize();

			if (shaderGenerated != null)
				for (m in obj.getMaterials())
					m.mainPass.removeShader(shaderGenerated);

			shaderGenerated = new hxsl.DynamicShader(s);
			for (m in obj.getMaterials()) {
				m.mainPass.addShader(shaderGenerated);
			}
			@:privateAccess sceneEditor.scene.render(sceneEditor.scene.engine);
			info('Shader compiled in  ${Date.now().getTime() - timeStart}ms');

		} catch (e : Dynamic) {
			if (Std.is(e, String)) {
				var str : String = e;
				if (str.split(":")[0] == "An error occurred compiling the shaders") { // aie
					error("Compilation of shader failed > " + str);
					if (shaderGenerated != null)
						for (m in obj.getMaterials())
							m.mainPass.removeShader(shaderGenerated);
					if (saveShader != null) {
						shaderGenerated = saveShader;
						for (m in obj.getMaterials()) {
							m.mainPass.addShader(shaderGenerated);
						}
					}
					return;
				}
			} else if (Std.is(e, ShaderException)) {
				error(e.msg, e.idBox);
				return;
			}
			error("Compilation of shader failed > " + e);
			if (shaderGenerated != null)
				for (m in obj.getMaterials())
					m.mainPass.removeShader(shaderGenerated);
			if (saveShader != null) {
				shaderGenerated = saveShader;
				for (m in obj.getMaterials()) {
					m.mainPass.addShader(shaderGenerated);
				}
			}
		}
	}

	function addNode(p : Point, nodeClass : Class<ShaderNode>) {
		var node = shaderGraph.addNode(p.x, p.y, nodeClass);

		addBox(p, nodeClass, node);
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
		if (addMenu != null)
			addMenu.hide();
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
package hide.view.shadereditor;

import hrt.shgraph.nodes.SubGraph;
import hxsl.DynamicShader;
import h3d.Vector;
import hrt.shgraph.ShaderParam;
import hrt.shgraph.ShaderException;
import haxe.Timer;
using hxsl.Ast.Type;
using Lambda;

import hide.comp.SceneEditor;
import js.jquery.JQuery;
import h2d.col.Point;
import h2d.col.IPoint;
import hide.view.shadereditor.Box;
import hrt.shgraph.ShaderGraph;
import hrt.shgraph.ShaderNode;

typedef NodeInfo = { name : String, description : String, key : String };

typedef SavedClipboard = {
	nodes : Array<{
		pos : Point,
		nodeType : Class<ShaderNode>,
		props : Dynamic,
	}>,
	edges : Array<{ fromIdx : Int, fromOutputId : Int, toIdx : Int, toInputId : Int }>,
}

class PreviewShaderBase extends hxsl.Shader {
	static var SRC = {

		@input var input : {
			var position : Vec2;
		};


		@global var camera : {
			var viewProj : Mat4;
			var position : Vec3;
		};

		var relativePosition : Vec3;
		var transformedPosition : Vec3;
		var projectedPosition : Vec4;
		var transformedNormal : Vec3;
		var fakeNormal : Vec3;
		var depth : Float;


		function __init__() {
			depth = 0.0;
			relativePosition = vec3(input.position, 0.0);
			transformedPosition = vec3(input.position, 0.0);
			projectedPosition = vec4(input.position, 0.0, 0.0);
			fakeNormal = vec3(0,0,-1);
			transformedNormal = vec3(0,0,-1);
		}


	}
}

class PreviewShaderParticle extends hxsl.Shader {
	static var SRC = {

		@global var global : {
			var time : Float;
		};

		var particleRandom : Float;
        var particleLifeTime : Float;
        var particleLife : Float;

		function __init__() {
			particleLife = mod(global.time, 1.0);
			particleLifeTime = 1.0;
			particleRandom = hash12(vec2(floor(global.time)));
		}

		function hash12(p: Vec2) : Float
		{
			p = sign(p)*(floor(abs(p))+floor(fract(abs(p))*1000.0)/1000.0);
			var p3  = fract(vec3(p.xyx) * .1031);
			p3 += dot(p3, p3.yzx + 33.33);
			return fract((p3.x + p3.y) * p3.z);
		}
	}
}


class Preview extends h2d.Bitmap {

	public var shaderDef(default, set) : hrt.prefab.Cache.ShaderDef;
	public var shader : DynamicShader;

	function rebuildShader() {
		if (shader != null) {
			removeShader(shader);
		}
		if (shaderDef == null)
			return;
		shader = new DynamicShader(shaderDef.shader);
		addShader(shader);
	}

	function set_shaderDef(v: hrt.prefab.Cache.ShaderDef) {
		shaderDef = v;
		rebuildShader();
		return v;
	}

	public function new(parent: h2d.Object) {
		super(h2d.Tile.fromColor(0xFF00FF,1,1), parent);
		this.blendMode = None;
		var shaderBase = new PreviewShaderBase();
		addShader(shaderBase);
		addShader(new PreviewShaderParticle());
		var props = new h3d.shader.pbr.PropsValues();
		addShader(props);
	}

}

typedef ClassRepoEntry =
{
	/**
		Class of the node
	**/
	cl: Class<ShaderNode>,

	/**
		Group where the node is in the search
	**/
	group: String,

	/**
		Displayed name in the seach box
	**/
	nameSearch: String,

	/**
		Description of the node in the search box
	**/
	description: String,

	/**
		Custom name for the node that will be created
	**/
	?nameOverride: String,

	/**
		Arguments passed to the constructor when the node is created
	**/
	args: Array<Dynamic>
};

class ShaderEditor extends hide.view.Graph {

	var parametersList : JQuery;
	var domainSelection : JQuery;

	var draggedParamId : Int;

	var addMenu : JQuery;
	var selectedNode : JQuery;
	var classRepository : Array<ClassRepoEntry>;

	var previewsScene : hide.comp.Scene;
	var previewParamDirty : Bool = true;
	var currentShaderPreviewsDef : hrt.prefab.Cache.ShaderDef;

	// used to preview
	var sceneEditor : SceneEditor;
	var defaultLight : hrt.prefab.Light;
	var lightsAreOn = true;

	var root : hrt.prefab.Prefab;
	var obj : h3d.scene.Object;
	var prefabObj : hrt.prefab.Prefab;
	var shaderGraph : ShaderGraph;
	var currentGraph : Graph;

	var lastSnapshot : haxe.Json;

	var timerCompileShader : Timer;
	var COMPILE_SHADER_DEBOUNCE : Int = 100;
	var VIEW_VISIBLE_CHECK_TIMER : Int = 500;
	var currentShader : DynamicShader;
	var currentShaderDefMainPreview : hrt.prefab.Cache.ShaderDef;



	static var clipboard : SavedClipboard = null;
	static var lastCopyEditor : ShaderEditor = null;

	override function onDisplay() {
		super.onDisplay();

		shaderGraph = cast hide.Ide.inst.loadPrefab(state.path, null,  true);

		domain = Fragment;

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
								<select id="domainSelection"></select>
								<input id="launchCompileShader" type="button" value="Compile shader" />

								<input id="saveShader" type="button" value="Save" />
								<div>
									<input id="changeModel" type="button" value="Change Model" />
									<input id="removeModel" type="button" value="Remove Model" />
								</div>
								<input id="centerView" type="button" value="Center Graph" />
								<div>
									Display Compiled
									<input id="displayHxsl" type="button" value="Hxsl" />
									<input id="displayGlsl" type="button" value="Glsl" />
									<input id="displayHlsl" type="button" value="Hlsl" />
									<input id="display2" type="button" value="2" />
								</div>
								<input id="togglelight" type="button" value="Toggle Default Lights" />
								<input id="refreshGraph" type="button" value="Refresh Shader Graph" />
							</div>
						</div>)');
		parent.on("drop", function(e) {
			var posCursor = new Point(lX(ide.mouseX - 25), lY(ide.mouseY - 10));
			var node = Std.downcast(currentGraph.addNode(posCursor.x, posCursor.y, ShaderParam, []), ShaderParam);
			node.parameterId = draggedParamId;
			var paramShader = shaderGraph.getParameter(draggedParamId);
			node.variable = paramShader.variable;
			node.setName(paramShader.name);
			setDisplayValue(node, paramShader.type, paramShader.defaultValue);
			addBox(posCursor, ShaderParam, node);
		});

		var parentScene = element.find(".heaps-scene");
		var miniPreviews = new Element('<div class="mini-preview"></div>');
		parentScene.prepend(miniPreviews);
		previewsScene = new hide.comp.Scene(config, null, miniPreviews);
		previewsScene.onReady = onMiniPreviewReady;
		previewsScene.onUpdate = onMiniPreviewUpdate;


		var preview = new Element('<div id="preview" ></div>');
		preview.on("mousedown", function(e) { e.stopPropagation(); });
		preview.on("wheel", function(e) { e.stopPropagation(); });
		parent.append(preview);

		var savedLightState = getDisplayState("useDefaultLights");
		if( savedLightState != null ) {
			lightsAreOn = savedLightState;
		} else {
			lightsAreOn == true;
		}

		domainSelection = element.find("#domainSelection");
		for (domain in haxe.EnumTools.getConstructors(hrt.shgraph.ShaderGraph.Domain)) {
			domainSelection.append('<option value="$domain">$domain</option>');
		};

		domainSelection.val(haxe.EnumTools.EnumValueTools.getName(domain));

		domainSelection.on("change", (e) -> {
			var domainString : String = domainSelection.val();
			var domain = haxe.EnumTools.createByName(hrt.shgraph.ShaderGraph.Domain, domainString);
			setDomain(domain);
		});

		var def = new hrt.prefab.Prefab(null, null);
		new hrt.prefab.RenderProps(def, null).name = "renderer";
		defaultLight = new hrt.prefab.Light(def, null);
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
		defaultLight.enabled = lightsAreOn;
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
		});

		parent.on("mouseup", function(e) {
			if (e.button == 0) {
				// Stop link creation
				if (isCreatingLink != None) {
					if (startLinkBox != null && endLinkBox != null) {
						createEdgeInShaderGraph();
						cleanupLinkCreation();
					} else {
						openAddMenu();
					}

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

		function reloadFullView() {
			var shouldRebuild = true;
			if( modified )
				shouldRebuild = ide.confirm("Reload without saving?");
			if( shouldRebuild ) {
				rebuild();
				modified = false;
			}
		}

		keys = new hide.ui.Keys(element);
		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());
		keys.register("delete", deleteSelection);
		keys.register("duplicate", duplicateSelection);
		keys.register("copy", onCopy);
		keys.register("shadergraph.hide", onHide);
		keys.register("shadergraph.comment", commentFromSelection);
		keys.register("paste", onPaste);
		keys.register("sceneeditor.focus", centerView);
		keys.register("view.refresh", reloadFullView);

		parent.on("contextmenu", function(e) {
			e.preventDefault();
			openAddMenu();
			return false;
		});

		var newParamCtxMenu : Array<hide.comp.ContextMenu.ContextMenuItem> = [
			{ label : "Number", click : () -> createParameter(TFloat) },
			{ label : "Vec2", click : () -> createParameter(TVec(2, VFloat)) },
			{ label : "Vec3", click : () -> createParameter(TVec(3, VFloat)) },
			{ label : "Color", click : () -> createParameter(TVec(4, VFloat)) },
			{ label : "Texture", click : () -> createParameter(TSampler(T2D,false)) },
		];

		parametersList = element.find("#parametersList");
		parametersList.on("contextmenu", function(e) {
			e.preventDefault();
			e.stopPropagation();
			new hide.comp.ContextMenu([
				{
					label : "Add Parameter",
					menu : newParamCtxMenu,
				},
			]);
		});

		element.find("#createParameter").on("click", function() {
			new hide.comp.ContextMenu(newParamCtxMenu);
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
				sceneEditor.resetCamera(1.05);
				launchCompileShader();
			});
		});

		element.find("#removeModel").on("click", resetPreviewDefault);

		element.find("#centerView").on("click", function() {
			centerView();
		})
			.prop("title", 'Center on full graph (${config.get("key.sceneeditor.focus")})');

		element.find("#togglelight").on("click", toggleDefaultLight);

		element.find("#refreshGraph").on("click", reloadFullView)
			.prop("title", 'Refresh the Shader (${config.get("key.view.refresh")})');

		element.find("#displayHxsl").on("click", () -> displayCompiled("hxsl"));
		element.find("#displayGlsl").on("click", () -> displayCompiled("glsl"));
		element.find("#displayHlsl").on("click", () -> displayCompiled("hlsl"));

		element.find("#display2").on("click", () -> {
			@:privateAccess info(
				hxsl.Printer.shaderToString(shaderGraph.compile(domain).shader.data, true)
			);});

		editorMatrix.on("click", "input, select", function(ev) {
			beforeChange();
		});

		editorMatrix.on("change", "input, select", function(ev) {
			try {
				var idBox = ev.target.closest(".box").id;
				//shaderGraph.nodeUpdated(idBox);
				afterChange();
				launchCompileShader();
			} catch (e : Dynamic) {
				if (Std.isOfType(e, ShaderException)) {
					error(e.msg, e.idBox);
				}
			}
		});

		addMenu = null;

		classRepository = [];

		for (node in ShaderNode.registeredNodes) {
			var metas = haxe.rtti.Meta.getType(node);
			if (metas.group == null) {
				continue;
			}
			var group = metas.group != null ? metas.group[0] : "Other";
			var name = metas.name != null ? metas.name[0] : "unknown";
			var description = metas.description != null ? metas.description[0] : "";

			classRepository.push({nameSearch : name, group : group, description: description, args: [], cl: node});

			var inst = std.Type.createEmptyInstance(node);
			var aliases = inst.getAliases(name, group, description);
			if (aliases != null) {
				for (alias in aliases) {
					classRepository.push(
						{
							nameSearch : alias.nameSearch ?? alias.nameOverride ?? name,
							nameOverride : alias.nameOverride,
							description: alias.description ?? description,
							args: alias.args ?? [],
							cl: node,
							group: alias.group ?? group
						}
					);
				}
			}
		}

		var libPaths : Array<String> = config.get("shadergraph.libfolders", ["shaders"]);
		for( lpath in libPaths ) {
			var basePath = ide.getPath(lpath);
			if( !sys.FileSystem.exists(basePath) || !sys.FileSystem.isDirectory(basePath) )
				continue;
			for( c in sys.FileSystem.readDirectory(basePath) ) {
				var relPath = ide.makeRelative(basePath + "/" + c);
				if(
					this.state.path.toLowerCase() != relPath.toLowerCase()
					&& haxe.io.Path.extension(relPath).toLowerCase() == "shgraph"
				) {
					var group = 'SubGraph from $lpath';

					var fileName = new haxe.io.Path(relPath).file;

					classRepository.push({nameSearch: fileName, description: "", args: [relPath], cl: SubGraph, group: group});
				}
			}
		}

		classRepository.sort((a,b) -> {
			if (a.group == b.group) {
				return Reflect.compare(a.nameSearch, b.nameSearch);
			}
			return Reflect.compare(a.group, b.group);
		});

		new Element("svg").ready(function(e) {
			refreshShaderGraph();
			if (isVisible()) {
				centerView();
			}
		});
	}

	function cleanupLinkCreation() {
		startLinkBox = endLinkBox = null;
		startLinkNodeId = endLinkNodeId = -1;
		isCreatingLink = None;

		if (currentLink != null) currentLink.remove();
		currentLink = null;
	}

	override function save() {
		var content = shaderGraph.saveToText();
		currentSign = ide.makeSignature(content);
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
		else if( hrt.prefab.Prefab.getPrefabType(relative) != null ) {
			var ref = new hrt.prefab.Reference(root, null);
			ref.source = relative;
			sceneEditor.addElements([ref], false, true, false);
			prefabObj = ref;
			obj = sceneEditor.getObject(prefabObj);
		}
	}

	function resetPreviewDefault() {
		sceneEditor.scene.setCurrent();
		if( prefabObj != null ) {
			sceneEditor.deleteElements([prefabObj], false, false);
			prefabObj = null;
		}
		else {
			sceneEditor.scene.s3d.removeChild(obj);
		}
		removeDisplayState("customModel");

		var sp = new h3d.prim.Sphere(1, 128, 128);
		sp.addNormals();
		sp.addUVs();
		sp.addTangents();
		obj = new h3d.scene.Mesh(sp);
		sceneEditor.scene.s3d.addChild(obj);
		sceneEditor.resetCamera(1.05);
		launchCompileShader();
	}

	function onRefresh() {
		if (sceneEditor.scene.s3d == null) {
			Timer.delay(onRefresh, 250);
			return;
		}
		var saveCustomModel = getDisplayState("customModel");
		if (saveCustomModel != null)
			loadPreviewPrefab(saveCustomModel);
		else {
			// obj = sceneEditor.scene.loadModel("res/PrimitiveShapes/Sphere.fbx", true);
			var sp = new h3d.prim.Sphere(1, 128, 128);
			sp.addNormals();
			sp.addUVs();
			var mesh = new h3d.scene.Mesh(sp);
			obj = mesh;
		}
		for (m in obj.getMaterials()) {
			var sh = new PreviewShaderParticle();
			m.mainPass.addShader(sh);
		}
		if( prefabObj == null )
			sceneEditor.scene.s3d.addChild(obj);
		sceneEditor.resetCamera(1.05);

		element.find("#preview").first().append(sceneEditor.scene.element);

		if (isVisible()) {
			launchCompileShader();
		} else {
			var timer = new Timer(VIEW_VISIBLE_CHECK_TIMER);
			timer.run = function() {
				if (isVisible()) {
					centerView();
					generateEdges();
					launchCompileShader();
					timer.stop();
				}
			}
		}
		@:privateAccess
		if( sceneEditor.scene.window != null )
			sceneEditor.scene.window.checkResize();
	}

	function toggleDefaultLight() {
		if( lightsAreOn ) {
			lightsAreOn = false;
			defaultLight.enabled = lightsAreOn;
			sceneEditor.deleteElements([defaultLight], true, false);
		} else {
			lightsAreOn = true;
			defaultLight.enabled = lightsAreOn;
			sceneEditor.addElements([defaultLight], true, false);
		}
		saveDisplayState("useDefaultLights", lightsAreOn);
	}

	function setDomain(domain: hrt.shgraph.ShaderGraph.Domain) {
		this.domain = domain;
		refreshShaderGraph(true);
	}

	function refreshShaderGraph(readyEvent : Bool = true) {
		listOfBoxes = [];
		listOfEdges = [];

		currentGraph = shaderGraph.getGraph(domain);

		var saveToggleParams = new Map<Int, Bool>();
		for (pElt in parametersList.find(".parameter").elements()) {
			saveToggleParams.set(Std.parseInt(pElt.get()[0].id.split("_")[1]), pElt.find(".content").css("display") != "none");
		}
		parametersList.empty();
		editorMatrix.empty();

		updateMatrix();

		for (node in currentGraph.getNodes()) {
			var paramNode = Std.downcast(node.instance, ShaderParam);
			if (paramNode != null) {
				var paramShader = shaderGraph.getParameter(paramNode.parameterId);
				paramNode.setName(paramShader.name);
				setDisplayValue(paramNode, paramShader.type, paramShader.defaultValue);
				//shaderGraph.nodeUpdated(paramNode.id);
				addBox(new Point(node.x, node.y), ShaderParam, paramNode);
			} else {
				addBox(new Point(node.x, node.y), std.Type.getClass(node.instance), node.instance);
			}
			var subGraphNode = Std.downcast(node.instance, SubGraph);
			if( subGraphNode != null ) {
				var found = false;
				for( el in watches ) {
					if( el.path == subGraphNode.pathShaderGraph ) {
						found = true;
						break;
					}
				}
				if( !found )
					watch(subGraphNode.pathShaderGraph, rebuild, { keepOnRebuild: false });
			}
		}

		if (readyEvent) {
			new Element(".nodes").ready(function(e) {
				if (isVisible()) {
					generateEdges();
				}
			});
		} else {
			generateEdges();
		}


		for (k in shaderGraph.parametersKeys) {
			var pElt = addParameter(shaderGraph.parametersAvailable.get(k), shaderGraph.parametersAvailable.get(k).defaultValue);
			if (saveToggleParams.get(shaderGraph.parametersAvailable.get(k).id)) {
				toggleParameter(pElt, true);
			}
		}

		launchCompileShader();
	}

	function generateEdgesFromBox(box : Box) {

		for (b in listOfBoxes) {
			for (inputId => connection in b.getInstance().connections) {
				if (connection == null) continue;
				if (connection.from.id == box.getId()) {
					var nodeFrom = box.outputs[connection.outputId];
					var nodeTo = b.inputs[inputId];
					edgeStyle.stroke = nodeFrom.css("fill");
					createEdgeInEditorGraph({from: box, outputFrom: connection.outputId, to : b, inputTo: inputId, elt : createCurve(nodeFrom, nodeTo) });
				}

			}
		}
	}

	function generateEdgesToBox(box : Box) {
		for (inputId => connection in box.getInstance().connections) {
			if (connection == null) continue;
			var fromBox : Box = null;
			for (boxFrom in listOfBoxes) {
				if (boxFrom.getId() == connection.from.id) {
					fromBox = boxFrom;
					break;
				}
			}
			var nodeFrom = fromBox.outputs[connection.outputId];
			var nodeTo = box.inputs[inputId];
			edgeStyle.stroke = nodeFrom.css("fill");
			createEdgeInEditorGraph({from: fromBox, outputFrom: connection.outputId, to : box, inputTo: inputId, elt : createCurve(nodeFrom, nodeTo) });
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
		var newBox : Box = addBox(new Point(box.getX(), box.getY()), std.Type.getClass(box.getInstance()), box.getInstance());
		box.dispose();
		listOfBoxes.remove(box);
		generateEdgesToBox(newBox);
		generateEdgesFromBox(newBox);
		if (startLinkBox == box) {
			startLinkBox = newBox;
		}
		return newBox;
	}

	function moveParameter(parameter : Parameter, up : Bool) {
		var parameterElt = parametersList.find("#param_" + parameter.id);
		var parameterPrev = shaderGraph.parametersAvailable.get(shaderGraph.parametersKeys[shaderGraph.parametersKeys.indexOf(parameter.id) + (up? -1 : 1)]);
		var parameterPrevElt = parametersList.find("#param_" + parameterPrev.id);
		if (up)
			parameterElt.insertBefore(parameterPrevElt);
		else
			parameterElt.insertAfter(parameterPrevElt);
		shaderGraph.parametersKeys.remove(parameter.id);
		shaderGraph.parametersKeys.insert(shaderGraph.parametersKeys.indexOf(parameterPrev.id) + (up? 0 : 1), parameter.id);
		shaderGraph.checkParameterIndex();
	}

	function moveParameterTo(paramA: Parameter, paramB: Parameter, after: Bool) {
		if (paramA == paramB)
			return;
		var aElt = parametersList.find("#param_" + paramA.id);
		var bElt = parametersList.find("#param_" + paramB.id);

		if (!after) {
			aElt.insertBefore(bElt);
		} else {
			aElt.insertAfter(bElt);
		}

		shaderGraph.parametersKeys.remove(paramA.id);
		shaderGraph.parametersKeys.insert(shaderGraph.parametersKeys.indexOf(paramB.id)+ (after ? 1 : 0) , paramA.id);

		shaderGraph.checkParameterIndex();
	}

	function addParameter(parameter : Parameter, ?value : Dynamic) {

		var elt = new Element('<div id="param_${parameter.id}" class="parameter" draggable="true" ></div>').appendTo(parametersList);
		elt.on("click", function(e) {e.stopPropagation();});
		elt.on("contextmenu", function(e) {
			var elements = [];
			e.stopPropagation();
			var newCtxMenu : Array<hide.comp.ContextMenu.ContextMenuItem> = [
				{ label : "Move up", click : () -> {
					beforeChange();
					moveParameter(parameter, true);
					afterChange();
				}, enabled: shaderGraph.parametersKeys.indexOf(parameter.id) > 0},
				{ label : "Move down", click : () -> {
					beforeChange();
					moveParameter(parameter, false);
					afterChange();
				}, enabled: shaderGraph.parametersKeys.indexOf(parameter.id) < shaderGraph.parametersKeys.length-1}
			];
			new hide.comp.ContextMenu(newCtxMenu);
			e.preventDefault();

		});
		var content = new Element('<div class="content" ></div>');
		content.hide();
		var defaultValue = new Element("<div><span>Default: </span></div>").appendTo(content);

		var typeName = "";
		switch(parameter.type) {
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
				shaderGraph.setParameterDefaultValue(parameter.id, value);
				range.onChange = function(moving) {
					if (!shaderGraph.setParameterDefaultValue(parameter.id, range.value))
						return;
					setBoxesParam(parameter.id);
					updateParam(parameter.id);
				};
				typeName = "Number";
			case TVec(4, VFloat):
				var parentPicker = new Element('<div style="width: 35px; height: 25px; display: inline-block;"></div>').appendTo(defaultValue);
				var picker = new hide.comp.ColorPicker.ColorBox(null, parentPicker, true, true);


				if (value == null)
					value = [0, 0, 0, 1];
				var start : h3d.Vector = h3d.Vector.fromArray(value);
				shaderGraph.setParameterDefaultValue(parameter.id, value);
				picker.value = start.toColor();
				picker.onChange = function(move) {
					var vecColor = h3d.Vector4.fromColor(picker.value);
					if (!shaderGraph.setParameterDefaultValue(parameter.id, [vecColor.x, vecColor.y, vecColor.z, vecColor.w]))
						return;
					setBoxesParam(parameter.id);
					updateParam(parameter.id);
				};
				/*picker.element.on("dragstart.spectrum", function() {
					beforeChange();
				});
				picker.element.on("dragstop.spectrum", function() {
					afterChange();
				});*/
			case TVec(n, VFloat):
				if (value == null)
					value = [for (i in 0...n) 0.0];

				shaderGraph.setParameterDefaultValue(parameter.id, value);
				//var row = new Element('<div class="flex"/>').appendTo(defaultValue);

				for( i in 0...n ) {
					var parentRange = new Element('<input type="range" min="-1" max="1" />').appendTo(defaultValue);
					var range = new hide.comp.Range(null, parentRange);
					range.value = value[i];

					var rangeInput = @:privateAccess range.f;
					rangeInput.on("mousedown", function(e) {
						elt.attr("draggable", "false");
						beforeChange();
					});
					rangeInput.on("mouseup", function(e) {
						elt.attr("draggable", "true");
						afterChange();
					});

					range.onChange = function(move) {
						value[i] = range.value;
						if (!shaderGraph.setParameterDefaultValue(parameter.id, value))
							return;
						setBoxesParam(parameter.id);
						updateParam(parameter.id);
					};
					//if(min == null) min = isColor ? 0.0 : -1.0;
					//if(max == null)	max = 1.0;
					//e.attr("min", "" + min);
					//e.attr("max", "" + max);
				}
				typeName = "Vec" + n;
			case TSampler(_):
				var parentSampler = new Element('<input type="texturepath" field="sampler2d"/>').appendTo(defaultValue);

				var tselect = new hide.comp.TextureChoice(null, parentSampler);
				tselect.value = value;
				tselect.onChange = function(undo: Bool) {
					beforeChange();
					if (!shaderGraph.setParameterDefaultValue(parameter.id, tselect.value))
						return;
					afterChange();
					setBoxesParam(parameter.id);
					updateParam(parameter.id);
				}
				typeName = "Texture";

			default:
		}

		var header = new Element('<div class="header">
									<div class="title">
										<i class="ico ico-chevron-right" ></i>
										<input class="input-title" type="input" value="${parameter.name}" />
									</div>
									<div class="type">
										<span>${typeName}</span>
									</div>
								</div>');

		var internal = new Element('<div><input type="checkbox" name="internal" id="internal"></input><label for="internal">Internal</label><div>').appendTo(content).find("#internal");
		internal.prop("checked", parameter.internal ?? false);

		internal.on('change', function(e) {
			beforeChange();
			parameter.internal = internal.prop("checked");
			afterChange();
		});

		var perInstanceCb = new Element('<div><input type="checkbox" name="perinstance"/><label for="perinstance">Per instance</label><div>');
		var shaderParams : Array<ShaderParam> = [];
		for (b in listOfBoxes) {
			var tmpShaderParam = Std.downcast(b.getInstance(), ShaderParam);
			if (tmpShaderParam != null && tmpShaderParam.parameterId == parameter.id) {
				shaderParams.push(tmpShaderParam);
				break;
			}
		}

		var checkbox = perInstanceCb.find("input");
		if (shaderParams.length > 0)
			checkbox.prop("checked", shaderParams[0].perInstance);
		checkbox.on("change", function() {
			beforeChange();
			var checked : Bool = checkbox.prop("checked");
			for (shaderParam in shaderParams)
				shaderParam.perInstance = checked;
			afterChange();
			compileShader();
		});
		perInstanceCb.appendTo(content);

		header.appendTo(elt);
		content.appendTo(elt);
		var actionBtns = new Element('<div class="action-btns" ></div>').appendTo(content);
		var deleteBtn = new Element('<input type="button" value="Delete" />');
		deleteBtn.on("click", function() {
			for (b in listOfBoxes) {
				var shaderParam = Std.downcast(b.getInstance(), ShaderParam);
				if (shaderParam != null && shaderParam.parameterId == parameter.id) {
					error("This parameter is used in the graph.");
					return;
				}
			}
			beforeChange();
			shaderGraph.removeParameter(parameter.id);
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
			if (shaderGraph.setParameterTitle(parameter.id, newName)) {
				for (b in listOfBoxes) {
					var shaderParam = Std.downcast(b.getInstance(), ShaderParam);
					if (shaderParam != null && shaderParam.parameterId == parameter.id) {
						beforeChange();
						shaderParam.setName(newName);
						afterChange();
					}
				}
			}
		});
		inputTitle.on("focus", function() { inputTitle.select(); } );

		elt.find(".header").on("click", function() {
			toggleParameter(elt);
		});

		elt.on("dragstart", function(e) {
			draggedParamId = parameter.id;
		});

		inline function isAfter(e) {
			return e.clientY > (elt.offset().top + elt.outerHeight() / 2.0);
		}

		elt.on("dragover", function(e : js.jquery.Event) {
			var after = isAfter(e);
			elt.toggleClass("hovertop", !after);
			elt.toggleClass("hoverbot", after);
			e.preventDefault();
		});

		elt.on("dragleave", function(e) {
			elt.toggleClass("hovertop", false);
			elt.toggleClass("hoverbot", false);
		});

		elt.on("dragenter", function(e) {
			e.preventDefault();
		});

		elt.on("drop", function(e) {
			elt.toggleClass("hovertop", false);
			elt.toggleClass("hoverbot", false);
			var other = shaderGraph.getParameter(draggedParamId);
			var after = isAfter(e);
			moveParameterTo(other, parameter, after);
		});

		return elt;
	}

	function setBoxesParam(id : Int) {
		var param = shaderGraph.getParameter(id);
		for (b in listOfBoxes) {
			var shaderParam = Std.downcast(b.getInstance(), ShaderParam);
			if (shaderParam != null && shaderParam.parameterId == id) {
				setDisplayValue(shaderParam, param.type, param.defaultValue);
				b.generateProperties(this, config);
			}
		}
	}

	function setDisplayValue(node : ShaderParam, type : Type, defaultValue : Dynamic) {
		switch (type) {
			case TSampler(_):
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

		var elt = addParameter(paramShader, null);
		updateParam(paramShaderID);

		elt.find(".input-title").focus();
	}

	function launchCompileShader() {
		if (timerCompileShader != null) {
			timerCompileShader.stop();
		}
		timerCompileShader = new Timer(COMPILE_SHADER_DEBOUNCE);
		timerCompileShader.run = function() {
			if (obj != null) {
				if (previewsScene.engine == null || @:privateAccess previewsScene.window == null) {
					return;
				}
				previewsScene.setCurrent();
				timerCompileShader.stop();
				compileShader();
			}
		};
	}

	function displayCompiled(type : String) {
		var text = "\n";

		var def = shaderGraph.compile(null);

		if( def != null) {
			text += switch( type ) {
				case "hxsl": hxsl.Printer.shaderToString(def.shader.data);
				case "glsl": hxsl.GlslOut.compile(def.shader.data);
				case "hlsl": new hxsl.HlslOut().run(def.shader.data);
				default: "";
			}
		}
		info(text);
		trace('Compiled shader:$text');
	}

	function compileShader() {
		var newShader : DynamicShader = null;
		try {
			sceneEditor.scene.setCurrent();
			var timeStart = Date.now().getTime();

			if (currentShader != null)
				for (m in obj.getMaterials())
					m.mainPass.removeShader(currentShader);

			var shaderGraphDef = shaderGraph.compile(null);
			newShader = new hxsl.DynamicShader(shaderGraphDef.shader);
			for (init in shaderGraphDef.inits) {
				setParamValue(newShader, init.variable, init.value);
			}
			for (m in obj.getMaterials()) {
				m.mainPass.addShader(newShader);
			}
			sceneEditor.scene.render(sceneEditor.scene.engine);
			currentShader = newShader;
			currentShaderDefMainPreview = shaderGraphDef;//{shader: shaderGraphDef, inits:[]};

			previewParamDirty = true;

			info('Shader compiled in  ${Date.now().getTime() - timeStart}ms');

		} catch (e : Dynamic) {
			if (Std.isOfType(e, String)) {
				var str : String = e;
				trace(str);

				error("Compilation of shader failed > " + str);
			} else if (Std.isOfType(e, ShaderException)) {
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

		currentShaderPreviewsDef = shaderGraph.compile(domain);
	}

	function updateParam(id : Int) {
		sceneEditor.scene.setCurrent();
		var param = shaderGraph.getParameter(id);
		setParamValueByName(currentShader, param.name, param.defaultValue);
		previewParamDirty = true;
		for (b in listOfBoxes) {
			// TODO
			// var previewBox = b.getInstance();//Std.downcast(b.getInstance(), hrt.shgraph.nodes.Preview);
			// if (previewBox != null) {
			// 	previewBox.setParamValueByName(param.variable.name, param.defaultValue);
			// }
		}
	}

	function setParamValueByName(shader : DynamicShader, varName : String, value : Dynamic) {
		if (currentShaderDefMainPreview == null) return;
		for (init in currentShaderDefMainPreview.inits) {
			if (init.variable.name == varName) {
				setParamValue(shader, init.variable, value);
				return;
			}
		}
	}

	function setParamValue(shader : DynamicShader, variable : hxsl.Ast.TVar, value : Dynamic) {
		@:privateAccess ShaderGraph.setParamValue(shader, variable, value);
	}

	var boxToPreview : Map<Box, Preview>;
	var timeout = 0;
	function onMiniPreviewReady() {
		if (previewsScene.s2d == null) {
			timeout ++;
			if (timeout > 10)
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

	function onMiniPreviewUpdate(dt: Float) {

		@:privateAccess
		if (sceneEditor?.scene?.s3d?.renderer?.ctx?.time != null) {
			sceneEditor.scene.s3d.renderer.ctx.time = previewsScene.s3d.renderer.ctx.time;
		}


		var newBoxToPreview : Map<Box, Preview> = [];
		for (box in listOfBoxes) {
			var preview = boxToPreview.get(box);
			if (preview == null) {
				var bmp = new Preview(previewsScene.s2d);
				bmp.shaderDef = currentShaderPreviewsDef;
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

		var updateShaderParams = false;
		if (previewParamDirty) {
			updateShaderParams = true;
			previewParamDirty = false;
		}

		var select = null;
		if (currentShaderPreviewsDef != null) {
			select = currentShaderPreviewsDef.inits.find((e) -> e.variable.name == hrt.shgraph.Variables.previewSelectName);
		}
		for (box => preview in boxToPreview) {
			preview.visible = box.getInstance().shouldShowPreview();
			if (!preview.visible)
				continue;
			if (preview.shaderDef != currentShaderPreviewsDef) {
				preview.shaderDef = currentShaderPreviewsDef;
			}
			if (preview.shader != null && updateShaderParams) {
				for (init in currentShaderPreviewsDef.inits) {
					if (init == select) {
						setParamValue(preview.shader, init.variable, box.getId() + 1);
					}
					else {
						var param = shaderGraph.parametersAvailable.find((v) -> v.name == init.variable.name);
						if (param != null) {
							setParamValue(preview.shader, init.variable,  param.defaultValue);
						}
						else {
						}
					}
				}
			}
			preview.x = gX(box.getX());
			preview.y = gY(box.getY() + box.getHeight());
			preview.scaleX = transformMatrix[0] * box.getWidth();
			preview.scaleY = transformMatrix[3] * box.getWidth();

		}
	}

	function initSpecifics(node : Null<ShaderNode>) {
		if( node == null )
			return;
	}

	function addNode(p : Point, nodeClass : Class<ShaderNode>, args : Array<Dynamic>) {
		beforeChange();

		var node = currentGraph.addNode(p.x, p.y, nodeClass, args);

		initSpecifics(node);

		var box = addBox(p, nodeClass, node);

		if (isCreatingLink != None) {
			if (startLinkBox != null) {
				endLinkBox = box;
				endLinkNodeId = 0;
				createEdgeInShaderGraph();
			}
			else if (endLinkBox != null) {
				startLinkBox = box;
				startLinkNodeId = 0;
				createEdgeInShaderGraph();
			}
		}

		afterChange();

		return node;
	}

	function addSubGraph(p : Point, path : String) {
		var node : SubGraph = cast addNode(p, SubGraph, [path]);
		// node.loadGraphShader();
		return node;
	}

	function createEdgeInShaderGraph() : Bool {
		if (isCreatingLink == FromInput) {
			var tmpBox = startLinkBox;
			startLinkBox = endLinkBox;
			endLinkBox = tmpBox;

			var tmpNodeId = startLinkNodeId;
			startLinkNodeId = endLinkNodeId;
			endLinkNodeId = tmpNodeId;
		}

		var newEdge = { from: startLinkBox, outputFrom : startLinkNodeId, to : endLinkBox, inputTo : endLinkNodeId, elt : currentLink };
		for (edge in listOfEdges) {
			if (edge.to == newEdge.to && edge.inputTo == newEdge.inputTo) {
				super.removeEdge(edge);
				removeShaderGraphEdge(edge);
				break;
			}
		}
		try {
			beforeChange();
			var outputId = newEdge.outputFrom;
			var inputId = newEdge.inputTo;

			var edge = {
				outputNodeId: startLinkBox.getId(),
				nameOutput: startLinkBox.getInstance().getOutputs()[outputId].name,
				outputId: outputId,
				inputNodeId: endLinkBox.getId(),
				inputId: inputId,
				nameInput: endLinkBox.getInstance().getInputs()[inputId].name
			};
			trace(edge);

			if (currentGraph.addEdge(edge))
			{
				afterChange();
				createEdgeInEditorGraph(newEdge);
				currentLink.removeClass("draft");
				currentLink = null;
				isCreatingLink = None;
				launchCompileShader();
				refreshBox(endLinkBox);
				return true;
			} else {
				error("This edge creates a cycle.");
				return false;
			}
		} catch (e : Dynamic) {
			if (Std.isOfType(e, ShaderException)) {
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

		var prevGroup = null;
		for (i => node in classRepository) {
			if (node.group != prevGroup) {
				new Element('
				<div class="group" >
					<span> ${node.group} </span>
				</div>').appendTo(results);
				prevGroup = node.group;
			}

			new Element('
				<div node="$i" >
					<span> ${node.nameSearch} </span> <span> ${node.description} </span>
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
		input.on("keyup", function(ev) {
			if (ev.keyCode == 38 || ev.keyCode == 40) {
				return;
			}

			if (ev.keyCode == 13) {
				var key = Std.parseInt(this.selectedNode.attr("node"));
				var posCursor = new Point(lX(ide.mouseX - 25), lY(ide.mouseY - 10));

				var node = classRepository[key];
				var instance = addNode(posCursor, node.cl, node.args);
				instance.nameOverride = node.nameOverride;
				closeAddMenu();
				refreshShaderGraph();

				/*if( key.toLowerCase().indexOf(".shgraph") != -1 ) {
					addSubGraph(posCursor, key);
					closeAddMenu();
					refreshShaderGraph();
				} else {
					addNode(posCursor, ShaderNode.registeredNodes[key], []);
					closeAddMenu();
				}*/
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

			var key = Std.parseInt(this.selectedNode.attr("node"));
			var posCursor = new Point(lX(ide.mouseX - 25), lY(ide.mouseY - 10));

			var node = classRepository[key];
			var instance = addNode(posCursor, node.cl, node.args);
			instance.nameOverride = node.nameOverride;
			closeAddMenu();
			refreshShaderGraph();
		});
	}

	function closeAddMenu() {
		if (addMenu != null) {
			addMenu.hide();
			parent.focus();
			cleanupLinkCreation();
		}
	}

	function beforeChange() {
		lastSnapshot = haxe.Json.parse(shaderGraph.saveToText());
	}

	function afterChange() {
		var newVal = haxe.Json.parse(shaderGraph.saveToText());
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
		currentGraph.removeEdge(edge.to.getId(), edge.inputTo);
	}

	function removeEdgeSubGraphUpdate(edge : Graph.Edge) {
		var subGraph = Std.downcast(edge.to.getInstance(), hrt.shgraph.nodes.SubGraph);
		if (subGraph != null) {
			var newBox = refreshBox(edge.to);
		}
	}

	function commentFromSelection() {
		if (listOfBoxesSelected.length == 0)
			return;

		var bounds = inline new h2d.col.Bounds();
		for (box in listOfBoxesSelected) {
			var x = box.getX();
			var y = box.getY();
			bounds.addPos(x, y);
			var previewHeight = box.getInstance().shouldShowPreview() ? box.getWidth() : 0;
			bounds.addPos(x + box.getWidth(), y + box.getHeight() + previewHeight);
		}

		var border = 10;
		bounds.xMin -= border;
		bounds.yMin -= border + 34;
		bounds.xMax += border;
		bounds.yMax += border;

		beforeChange();
		var comment : hrt.shgraph.nodes.Comment = cast currentGraph.addNode(bounds.xMin, bounds.yMin, hrt.shgraph.nodes.Comment, []);
		comment.width = Std.int(bounds.width);
		comment.height = Std.int(bounds.height);

		var box = addBox(new Point(bounds.xMin, bounds.yMin), hrt.shgraph.nodes.Comment, comment);
		var elem = box.getElement().find(".comment-title").get(0);
		elem.focus();
		afterChange();

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

	function saveSelection(?boxes) : SavedClipboard {
		if( boxes == null )
			boxes = listOfBoxesSelected;
		if( boxes.length == 0 )
			return null;
		var dims = getGraphDims(boxes);
		var baseX = dims.xMin;
		var baseY = dims.yMin;
		var box = boxes[0];
		var nodes = [
			for( b in boxes )
				{
					pos : new Point(b.getX() - baseX, b.getY() - baseY),
					nodeType : std.Type.getClass(b.getInstance()),
					props : b.getInstance().saveProperties(),
				}
		];

		var edges : Array<{ fromIdx : Int, fromOutputId : Int, toIdx : Int, toInputId : Int }> = [];

		for( edge in listOfEdges ) {
			for( fromIdx in 0...boxes.length ) {
				if( boxes[fromIdx] == edge.from ) {
					for( toIdx in 0...boxes.length ) {
						if( boxes[toIdx] == edge.to ) {
							edges.push({
								fromIdx : fromIdx,
								fromOutputId : edge.outputFrom,
								toIdx : toIdx,
								toInputId :  edge.inputTo,
							});
						}
					}
				}
			}
		}

		return {
			nodes : nodes,
			edges : edges,
		};
	}

	function loadClipboard(offset : Point, val : SavedClipboard, selectNew = true) {
		if( val == null )
			return;
		if( offset == null )
			offset = new Point(0, 0);
		var instancedBoxes : Array<Null<Box>> = [];
		for( n in val.nodes ) {
			if( n.nodeType == ShaderParam && lastCopyEditor != this ) {
				instancedBoxes.push(null);
				continue;
			}
			var node = currentGraph.addNode(offset.x + n.pos.x, offset.y + n.pos.y, n.nodeType, []);
			node.loadProperties(n.props);
			initSpecifics(node);
			var shaderParam = Std.downcast(node, ShaderParam);
			if( shaderParam != null ) {
				var paramShader = currentGraph.getParameter(shaderParam.parameterId);
				if( paramShader == null ) {
					currentGraph.removeNode(node.id);
					instancedBoxes.push(null);
					continue;
				}
				shaderParam.variable = paramShader.variable;
				shaderParam.setName(paramShader.name);
				setDisplayValue(shaderParam, paramShader.type, paramShader.defaultValue);
			}
			var box = addBox(offset.add(n.pos), n.nodeType, node);
			instancedBoxes.push(box);
		}
		for( edge in val.edges ) {
			if( instancedBoxes[edge.fromIdx] == null || instancedBoxes[edge.toIdx] == null )
				continue;
			var toCreate : hrt.shgraph.ShaderGraph.Edge = {
				outputNodeId: instancedBoxes[edge.fromIdx].getId(),
				outputId: edge.fromOutputId,
				nameOutput: instancedBoxes[edge.fromIdx].getInstance().getOutputs()[edge.fromOutputId].name,
				inputNodeId: instancedBoxes[edge.toIdx].getId(),
				inputId: edge.toInputId,
				nameInput: instancedBoxes[edge.toIdx].getInstance().getInputs()[edge.toInputId].name,
			}
			if( !currentGraph.addEdge(toCreate) ) {
				error("A pasted edge creates a cycle");
			}
		}
		var newBoxes = [ for( box in instancedBoxes ) if( box != null ) refreshBox(box) ];
		if( selectNew ) {
			clearSelectionBoxes();
			for( box in newBoxes ) {
				box.setSelected(true);
			}
			listOfBoxesSelected = newBoxes;
		}
	}

	function duplicateSelection() {
		if (listOfBoxesSelected.length <= 0)
			return;
		var vals = saveSelection(listOfBoxesSelected);
		var dims = getGraphDims(listOfBoxesSelected);
		var offset = new Point(dims.xMin + 30, dims.yMin + 30);
		lastCopyEditor = this;
		beforeChange();
		loadClipboard(offset, vals);
		afterChange();
	}

	function onCopy() {
		clipboard = saveSelection(listOfBoxesSelected);
		lastCopyEditor = this;
		ide.setClipboard(haxe.Json.stringify(clipboard));
	}

	function onPaste() {
		var jsonClipboard = haxe.Json.stringify(clipboard);
		if( jsonClipboard != ide.getClipboard() || lastCopyEditor == null)
			return;
		var posOffset = new Point(lX(ide.mouseX - 40), lY(ide.mouseY - 20));
		beforeChange();
		loadClipboard(posOffset, clipboard);
		afterChange();
	}

	function onHide() {
		if (listOfBoxesSelected.length <= 0)
			return;

		beforeChange();

		var visiblity = !listOfBoxesSelected[0].getInstance().showPreview;
		for (box in listOfBoxesSelected) {
			box.setPreviewVisibility(visiblity);
		}
		afterChange();
	}

	function deleteSelection() {
		if (currentEdge != null) {
			removeEdge(currentEdge);
		}
		if (listOfBoxesSelected.length > 0) {
			beforeChange();
			for (b in listOfBoxesSelected) {
				removeBox(b, false);
			}
			afterChange();
			clearSelectionBoxes();
		}
	}

	override function removeBox(box : Box, trackChanges = true) {
		if( trackChanges )
			beforeChange();
		var isSubShader = Std.isOfType(box.getInstance(), SubGraph);
		var length = listOfEdges.length;
		for (i in 0...length) {
			var edge = listOfEdges[length-i-1];
			if (edge.from == box || edge.to == box) {
				super.removeEdge(edge);
				removeShaderGraphEdge(edge);
				if (!isSubShader) removeEdgeSubGraphUpdate(edge);
			}
		}
		currentGraph.removeNode(box.getId());
		if( trackChanges )
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
		refreshBox(edge.to);
	}

	override function updatePosition(box : Box) {
		var previewBox = Std.downcast(box.getInstance(), hrt.shgraph.nodes.Preview);
		/*if (previewBox != null){
			previewBox.onMove(gX(box.getX()), gY(box.getY()), transformMatrix[0]);
		}*/
		currentGraph.setPosition(box.getId(), box.getX(), box.getY());
	}

	override function updateMatrix() {
		super.updateMatrix();
		for (b in listOfBoxes) {
			/*var previewBox = Std.downcast(b.getInstance(), hrt.shgraph.nodes.Preview);
			if (previewBox != null){
				previewBox.onMove(gX(b.getX()), gY(b.getY()), transformMatrix[0]);
			}*/
		}
	}

	override function getDefaultContent() {
		var p = (new hrt.shgraph.ShaderGraph(null, null)).serialize();
		return haxe.io.Bytes.ofString(ide.toJSON(p));
	}

	override function onDragDrop(items : Array<String>, isDrop : Bool) {
		var valid = false;
		var offset = 0;
		for (i in items) {
			if (i.indexOf("shgraph") != -1 && i != state.path) {
				if (isDrop) {
					var posCursor = new Point(lX(ide.mouseX - 25 + offset), lY(ide.mouseY - 10 + offset));
					addSubGraph(posCursor, i);
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

	static var _ = FileTree.registerExtension(ShaderEditor,["shgraph"],{ icon : "scribd", createNew: "Shader Graph" });

}
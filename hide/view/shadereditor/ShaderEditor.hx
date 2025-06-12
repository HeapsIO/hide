package hide.view.shadereditor;

import hrt.shgraph.nodes.SubGraph;
import hxsl.DynamicShader;
import h3d.Vector;
import hrt.shgraph.ShaderParam;
import hrt.shgraph.ShaderException;
import haxe.Timer;
using Lambda;

import hide.comp.SceneEditor;
import js.jquery.JQuery;
import h2d.col.Point;
import h2d.col.IPoint;
import hide.view.shadereditor.Box;
import hrt.shgraph.ShaderGraph;
import hrt.shgraph.ShaderNode;
import hide.view.GraphInterface;

typedef HxslType = hxsl.Ast.Type;

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

		@global var global : {
			var time : Float;
			var screenShaderInput : Sampler2D;
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

		var particleRandom : Float;
        var particleLifeTime : Float;
        var particleLife : Float;
		var emissive : Float;
		var metalness : Float;
		var roughness : Float;
		var occlusion : Float;


		function __init__() {
			depth = 0.0;
			relativePosition = vec3(input.position, 0.0);
			transformedPosition = vec3(input.position, 0.0);
			projectedPosition = vec4(input.position, 0.0, 0.0);
			fakeNormal = vec3(0,0,-1);
			transformedNormal = vec3(0,0,-1);
			particleLife = mod(global.time, 1.0);
			particleLifeTime = 1.0;
			particleRandom = hash12(vec2(floor(global.time)));
			emissive = 0.0;
			metalness = 0.0;
			roughness = 0.0;
			occlusion = 0.0;
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

class PreviewSettings {
	public var meshPath : String = "Sphere";
	public var bgColor : Int = 0;
	public var renderPropsPath : String = null;
	public var alphaBlend: Bool = false;
	public var backfaceCulling : Bool = true;
	public var unlit : Bool = false;
	public var previewAlpha : Bool = false;
	public var shadows : Bool = false;

	public var screenFXusePrevTarget : Bool = false;
	public var screenFXBlend : h3d.mat.PbrMaterial.PbrBlend = Alpha;
	public var width : Int = 300;
	public var height : Int = 300;
	public function new() {};
}

@:access(hrt.shgraph.ShaderGraph)
@:access(hrt.shgraph.Graph)
class ShaderEditor extends hide.view.FileView implements GraphInterface.IGraphEditor {
	var graphEditor : hide.view.GraphEditor;
	var shaderGraph : hrt.shgraph.ShaderGraph;
	var currentGraph : hrt.shgraph.ShaderGraph.Graph;

	var compiledShader : hrt.prefab.Cache.ShaderDef;
	var compiledShaderPreview : hrt.prefab.Cache.ShaderDef;

	var previewShaderBase : PreviewShaderBase;
	var previewShaderAlpha : GraphEditor.PreviewShaderAlpha;
	var previewVar : hxsl.Ast.TVar;
	var needRecompile : Bool = true;

	var meshPreviewScene : hide.comp.Scene;
	var meshPreviewMeshes : Array<h3d.scene.Mesh> = [];
	var meshPreviewScreenFX : Array<hrt.prefab.rfx.ScreenShaderGraph> = [];
	var meshPreviewRoot3d : h3d.scene.Object;
	var meshPreviewShader : hxsl.DynamicShader;
	var meshPreviewCameraController : hide.comp.Scene.PreviewCamController;
	var previewSettings : PreviewSettings;
	var meshPreviewPrefab : hrt.prefab.Prefab;
	var meshPreviewprefabWatch : hide.tools.FileWatcher.FileWatchEvent;
	var meshPreviewRenderProps : hrt.prefab.Prefab;
	var meshPreviewRenderPropsRoot : h3d.scene.Object;

	var parametersList : hide.comp.FancyArray<hrt.shgraph.ShaderGraph.Parameter>;
	var variableList : hide.comp.FancyArray<ShaderGraphVariable>;

	var previewElem : Element;
	var draggedParamId : Int;

	var defaultLight : hrt.prefab.Light;

	var queueReloadMesh = false;

	var domainSelection : JQuery;

	var isDisplayed = false;
	var isLoaded = false;

	override function onRebuild() {
		super.onRebuild();
		reloadView();
	}

	function reloadView() {
		// can happen on close
		if (element == null)
			return;

		element.html("");
		loadSettings();
		element.addClass("shader-editor");
 		shaderGraph = Std.downcast(hide.Ide.inst.loadPrefab(state.path, null,  true), hrt.shgraph.ShaderGraph);
		 if (shaderGraph == null) {
			element.html('<p>${state.path} is not a valid shadergrah');
			return;
		}
		isLoaded = true;
		isDisplayed = true;


		var targetGraph : hrt.shgraph.ShaderGraph.Domain = (try
			haxe.EnumTools.createByName(hrt.shgraph.ShaderGraph.Domain, getDisplayState("currentGraph"))
		catch (e) null) ?? Fragment;

		currentGraph = shaderGraph.getGraph(targetGraph);
		previewShaderBase = new PreviewShaderBase();
		previewShaderAlpha = new GraphEditor.PreviewShaderAlpha();

		if (graphEditor != null)
			graphEditor.remove();
		graphEditor = new hide.view.GraphEditor(config, this, this.element);
		graphEditor.onDisplay();

		haxe.Timer.delay(() -> {
			graphEditor.centerView();
		}, 50);

		var canDragFunc = (e:js.html.DragEvent) -> {
			if (e.dataTransfer.types.contains(variableList.getDragKeyName()) || e.dataTransfer.types.contains(parametersList.getDragKeyName())) {
				e.preventDefault();
				e.stopPropagation();
			}
		};

		graphEditor.element.get(0).ondragenter = canDragFunc;
		graphEditor.element.get(0).ondragover = canDragFunc;

		graphEditor.element.get(0).ondrop = (e:js.html.DragEvent) -> {
			var posCursor = new Point(graphEditor.lX(e.clientX - 25), graphEditor.lY(e.clientY-25));

			function addNode(inst: ShaderNode) : Void {
				@:privateAccess var id = currentGraph.current_node_id++;
				inst.id = id;
				inst.setPos(posCursor);
				inst.graph = currentGraph;

				graphEditor.opBox(inst, true, graphEditor.currentUndoBuffer);
				graphEditor.commitUndo();
			}

			var variableIndex = variableList.getDragIndex(e);
			if (variableIndex != null) {
				var hasAnyWrite = false;
				shaderGraph.mapShaderVar((v) -> {
					if (v.varId == variableIndex && Std.downcast(v, hrt.shgraph.nodes.VarWrite) != null) {
						hasAnyWrite = true;
						return false;
					}
					return true;
				});

				if (hasAnyWrite) {
					var read = new hrt.shgraph.nodes.VarRead();
					read.varId = variableIndex;
					addNode(read);
				} else {
					hide.comp.ContextMenu.createFromPoint(e.clientX, e.clientY, [{
						label: "Write", click: () -> {
							var write = new hrt.shgraph.nodes.VarWrite();
							write.varId = variableIndex;
							addNode(write);
						}
					},
					{
						label: "Read", click: () -> {
							var read = new hrt.shgraph.nodes.VarRead();
							read.varId = variableIndex;
							addNode(read);
						}
					}]);
				}
				return;
			}

			var paramIndex = parametersList.getDragIndex(e);
			if (paramIndex != null) {
				var inst = new ShaderParam();
				var varId = -1;
				for (id => param in shaderGraph.parametersAvailable) {
					if (paramIndex == param.index) {
						varId = id;
						break;
					}
				}
				if (varId == -1)
					throw "missing variable id";
				inst.parameterId = varId;
				addNode(inst);
				return;
			}
		};

		var rightPannel = new Element(
			'<div id="rightPanel">
				<div style="flex-grow: 1; display: flex; flex-direction: column;">
					<div class="hide-block flexible param-collapse" >
						<h1 class="subtle-title">Parameters <fancy-button class="quieter btn-collapse"><div class="icon ico ico-chevron-down"></div></fancy-button></h1>

						<to-collapse>
						<fancy-array class="parameters merge-bottom" style="flex-grow: 1">

						</fancy-array>
						<fancy-button class="fancy-small createParameter merge-top"><div class="icon ico ico-plus"></div></fancy-button>
						</to-collapse>
					</div>


					<div class="hide-block flexible var-collapse">
						<h1 class="subtle-title">Variables <fancy-button class="quieter btn-collapse"><div class="icon ico ico-chevron-down"></div></fancy-button></h1 class="subtle-title">

						<to-collapse>
						<fancy-array class="variables merge-bottom" style="flex-grow: 1">
						</fancy-array>
						<fancy-button class="fancy-small add-variable merge-top"><div class="icon ico ico-plus"></div></fancy-button>
						</to-collapse>
					</div>
				</div>

				<div class="options-block hide-block">
					<div>
						Shader :
						<select id="domainSelection"></select>
					</div>
					<div> Preview Alpha<input id="previewAlpha" type="checkbox" /></div>

					<input id="centerView" type="button" value="Center Graph" />
					<input id="debugMenu" type="button" value="Debug Menu"/>
				</div>

			</div>'
		);

		function collapse(name: String) {
			var collapse = rightPannel.find("." + name);
			function refresh() {
				var state = getDisplayState(name) ?? false;
				collapse.toggleClass("collapsed", state);
			}
			collapse.find(".btn-collapse").on("click", () -> {
				saveDisplayState(name, !(getDisplayState(name) ?? false));
				refresh();
			});

			refresh();
		}

		collapse("param-collapse");
		collapse("var-collapse");



		variableList = new hide.comp.FancyArray(null, rightPannel.find(".variables"), "variables", "variables");

		variableList.getItems = () -> shaderGraph.variables;
		variableList.getItemName = (v: ShaderGraphVariable) -> v.name;
		variableList.reorderItem = moveVariable;
		variableList.removeItem = removeVariable;
		variableList.setItemName = renameVariable;
		variableList.getItemContent = getVariableContent;
		variableList.customizeHeader = (v:ShaderGraphVariable, header:Element) -> {
			var type = switch(v.type) {
				case SgFloat(1): "Float";
				case SgFloat(n): "Vec " + n;
				case SgSampler: "Texture";
				case SgInt: "Int";
				case SgBool: "Bool";
				default: "Unknown Type";
			};
			header.find("input").after(new Element('<div class="type">$type</div>'));
		}

		variableList.refresh();

		var addVariable = rightPannel.find(".add-variable");
		var createVariableMenu : Array<hide.comp.ContextMenu.MenuItem> = [
			{
				label: "Int",
				click: () -> createVariable(SgInt),
			},
			{
				label: "Float",
				click: () -> createVariable(SgFloat(1)),
			},
			{
				label: "Vec 2",
				click: () -> createVariable(SgFloat(2)),
			},
			{
				label: "Vec 3",
				click: () -> createVariable(SgFloat(3)),
			},
			{
				label: "Vec 4",
				click: () -> createVariable(SgFloat(4)),
			},
			{
				label: "Color",
				click: () -> createVariable(SgFloat(4), true),
			},
		];

		addVariable.on("click", (e) -> {
			hide.comp.ContextMenu.createDropdown(addVariable.get(0), createVariableMenu);
		});

		variableList.element.on("contextmenu", function(e) {
			e.preventDefault();
			e.stopPropagation();
			var vars = createVariableMenu.copy();
			vars.unshift({label:"New", isSeparator: true});
			hide.comp.ContextMenu.createFromEvent(e.originalEvent, vars);
		});

		rightPannel.find("#centerView").click((e) -> graphEditor.centerView());

		domainSelection = rightPannel.find("#domainSelection");
		for (domain in haxe.EnumTools.getConstructors(hrt.shgraph.ShaderGraph.Domain)) {
			domainSelection.append('<option value="$domain">$domain</option>');
		};

		domainSelection.val(haxe.EnumTools.EnumValueTools.getName(currentGraph.domain));

		domainSelection.on("change", (e) -> {
			var domainString : String = domainSelection.val();
			var domain = haxe.EnumTools.createByName(hrt.shgraph.ShaderGraph.Domain, domainString);
			setDomain(domain, true);
		});

		var previewAlpha = rightPannel.find("#previewAlpha");
		previewAlpha.on("change", (e) -> {
			previewSettings.previewAlpha = (cast previewAlpha[0]:Dynamic).checked;
			savePreviewSettings();
			bitmapToShader.clear();
		});
		(cast previewAlpha[0]:Dynamic).checked = previewSettings.previewAlpha;



		rightPannel.appendTo(element);

		var newParamCtxMenu : Array<hide.comp.ContextMenu.MenuItem> = [
			{ label : "Number", click : () -> createParameter(HxslType.TFloat) },
			{ label : "Vec2", click : () -> createParameter(HxslType.TVec(2, VFloat)) },
			{ label : "Vec3", click : () -> createParameter(HxslType.TVec(3, VFloat)) },
			{ label : "Color", click : () -> createParameter(HxslType.TVec(4, VFloat)) },
			{ label : "Texture", click : () -> createParameter(HxslType.TSampler(T2D,false)) },
		];

		var createParameter = rightPannel.find(".createParameter");
		createParameter.on("click", function(e) {
			hide.comp.ContextMenu.createDropdown(createParameter.get(0), newParamCtxMenu);
		});


		parametersList = new hide.comp.FancyArray(null, rightPannel.find(".parameters"), "parameters", "parameters");
		parametersList.element.on("contextmenu", function(e) {
			e.preventDefault();
			e.stopPropagation();
			var params = newParamCtxMenu.copy();
			params.unshift({label:"New", isSeparator: true});
			hide.comp.ContextMenu.createFromEvent(e.originalEvent, params);
		});

		parametersList.getItems = () -> {
			var values = shaderGraph.parametersAvailable.array();
			values.sort((a, b) -> Reflect.compare(a.index, b.index));
			return values;
		};
		parametersList.getItemName = (v: Parameter) -> v.name;
		parametersList.reorderItem = reorderParameter;
		parametersList.removeItem = removeParameter;
		parametersList.setItemName = renameParameter;
		parametersList.getItemContent = getParameterContent;
		parametersList.customizeHeader = (p:Parameter, header:Element) -> {
			var type = switch(p.type) {
				case TFloat: "Number";
				case TVec(4, VFloat): "Color";
				case TVec(1, VFloat): "Float";
				case TVec(n, VFloat): "Vec " + n;
				case TSampler(_): "Texture";
				default: "Unknown Type";
			};
			header.find("input").after(new Element('<div class="type">$type</div>'));
		}

		parametersList.refresh();

		rightPannel.find("#debugMenu").click((e) -> {
			hide.comp.ContextMenu.createDropdown(rightPannel.find("#debugMenu").get(0), [
				{
					label : "Print Preview Shader code to Console",
					click: () -> trace(hxsl.Printer.shaderToString(shaderGraph.compile(currentGraph.domain).shader.data, true))
				},
				{
					label : "Print Complete Shader code to Console",
					click: () -> trace(hxsl.Printer.shaderToString(shaderGraph.compile(null).shader.data, true))
				},
			]);
		});

		graphEditor.onPreviewUpdate = onPreviewUpdate;
		graphEditor.onNodePreviewUpdate = onNodePreviewUpdate;

		initMeshPreview();
	}

	override function onDragDrop(items : Array<String>, isDrop : Bool, event: js.html.DragEvent) {

		if (previewElem.get(0).matches(":hover")) {
			for (item in items) {
				if (StringTools.endsWith(item, ".prefab") || StringTools.endsWith(item, ".fx")) {
					var renderProp = config.getLocal("scene.renderProps");
					var renderProps : Array<String> = renderProp is String ? [renderProp] : cast renderProp;
					if (renderProps.contains(item)) {
						if (isDrop) {
							previewSettings.renderPropsPath = item;
							refreshRenderProps();
						}
						return true;
					}
					else {
						if (isDrop) {
							setMeshPreviewPrefab(item);
						}
						return true;
					}
				}
				else if (StringTools.endsWith(item, ".fbx")) {
					if (isDrop) {
						setMeshPreviewFBX(item);
					}
					return true;
				}
			}
		}

		return false;
	}

	override function onActivate() {
		super.onActivate();
		if (!isLoaded && isDisplayed) {
			graphEditor.createMiniPreviewScene();
			initMeshPreview();
			isLoaded = true;

		}
	}

	override function onHide() {
		super.onHide();
		if (isLoaded) {
			disposeMeshPreview();
			graphEditor.disposeMiniPreviewScene();
			isLoaded = false;
		}
	}

	override function onBeforeClose() {
		isLoaded = false;
		trace("on before close");

		return true;
	}

	function setDomain(domain : hrt.shgraph.ShaderGraph.Domain, recordUndo : Bool) {
		if (shaderGraph.getGraph(domain) == currentGraph)
			return;

		var from = currentGraph.domain;
		var to = domain;

		function exec(isUndo : Bool) {
			var curr = !isUndo ? to : from;
			currentGraph = shaderGraph.getGraph(curr);
			domainSelection.val(haxe.EnumTools.EnumValueTools.getName(curr));
			graphEditor.reload();
			graphEditor.centerView();
			saveDisplayState("currentGraph", haxe.EnumTools.EnumValueTools.getName(curr));
			requestRecompile();
		}

		exec(false);
		if (recordUndo) {
			undo.change(Custom(exec), null, true);
		}
	}


	function createVariable(type: SgType, isColor: Bool = false) {
		var name = "NewVariable";
		var i = 0;
		var index = 0;
		while(i < shaderGraph.variables.length) {
			if (shaderGraph.variables[i].name == name) {
				i = 0;
				index ++;
				name = 'NewVariable_$index';
			} else {
				i++;
			}
		}

		var variable : ShaderGraphVariable = {
			name: name,
			type: type,
			defValue: hrt.shgraph.ShaderGraph.getSgTypeDefVal(type),
			isColor: isColor,
		}

		function exec(isUndo: Bool) {
			if (!isUndo) {
				shaderGraph.variables.push(variable);
			}
			else {
				shaderGraph.variables.remove(variable);
			}
			variableList.refresh();
			requestRecompile();
		}
		exec(false);
		undo.change(Custom(exec));
		variableList.editTitle(shaderGraph.variables.length-1);
		variableList.toggleItem(shaderGraph.variables.length-1, true);
	}

	var validNameCheck = ~/^[_a-zA-Z][_a-zA-Z0-9]*$/;

	function renameVariable(variable: ShaderGraphVariable, newName: String) {
		if (!validNameCheck.match(newName))
		{
			variableList.refresh();
			ide.quickError('"$newName" is not a valid variable name (must start with _ or a letter, and only contains letters, numbers and underscores)');
			return;
		}

		if (shaderGraph.variables.find(v -> v != variable && v.name == newName) != null) {
			variableList.refresh();
			ide.quickError('Variable name "$newName" already exist in this shadergraph');
			return;
		}

		var oldName = variable.name;
		function exec(isUndo: Bool) {
			variable.name = !isUndo ? newName : oldName;
			variableList.refresh();

			var index = shaderGraph.variables.indexOf(variable);
			currentGraph.mapShaderVar((variable: hrt.shgraph.nodes.ShaderVar) -> {
				if (variable.varId == index) {
					graphEditor.refreshBox(variable.id);
				}
				return true;
			});

			for (node in currentGraph.nodes) {

			}
		}

		exec(false);
		undo.change(Custom(exec));
	}

	function getVariableContent(variable: ShaderGraphVariable) {
		var e = new Element('<div><div>Def value</div></div>');

		switch(variable.type) {
			case SgFloat(n):
				if (n >= 3 && variable.isColor) {
					hide.comp.PropsEditor.makePropEl({name: "defValue", t: PColor}, e);
				} else {
					hide.comp.PropsEditor.makePropEl({name: "defValue", t: PVec(n)}, e);
				}

				if (n >= 3) {
					var colorCheckbox = new Element('<div>Is Color</div>').appendTo(e);
					hide.comp.PropsEditor.makePropEl({name: "isColor", t: PBool}, colorCheckbox);
				}
			case SgInt:
				hide.comp.PropsEditor.makePropEl({name: "defValue", t: PInt()}, e);
			default:
				throw "Unsupported variable type";
		}

		var globalCheckbox = new Element('<div title="If the variable is set to global, it will use the exact same name in the generated shader code, allowing it to be shared between multiple shaders in the shaderlist">Is Global <input type="checkbox"/></div>').appendTo(e);
		var cb = globalCheckbox.find("input");
		cb.prop("checked", variable.isGlobal);
		cb.on("change", (e) -> {
			var old = variable.isGlobal;
			var val = cb.prop("checked");
			variable.isGlobal = val;
			for (graph in shaderGraph.graphs) {
				if (graph.hasCycle()) {
					variable.isGlobal = old;
					ide.quickError('Cannot change isGlobal because variable write and reads are dependant on each other, and isGlobal change the order of the read and writes and it would create a cycle', 10.0);
					variableList.refresh();
					return;
				}
			}

			undo.change(Field(variable, "isGlobal", old), () -> {
				requestRecompile();
				variableList.refresh();
			});
			requestRecompile();
		});

		var editRoot = new Element();
		var edit = new hide.comp.PropsEditor(undo, editRoot);
		edit.add(e, variable, (name: String) -> {
			if (name == "isColor") {
				variableList.refresh();
			}
			else if(StringTools.contains(name, "defValue")) {
				requestRecompile();
			}
		});
		return e;
	}

	function moveVariable(oldIndex: Int, newIndex: Int) {
		var graph = currentGraph;
		var remap: Array<Int> = [];
		function exec(isUndo: Bool) {
			if (!isUndo) {
				var oldOrder = shaderGraph.variables.copy();
				var rem = shaderGraph.variables.splice(oldIndex, 1);
				shaderGraph.variables.insert(newIndex, rem[0]);

				for (oldIndex => v in oldOrder) {
					remap[oldIndex] = shaderGraph.variables.indexOf(v);
				}

				shaderGraph.mapShaderVar((v) -> {
					v.varId = remap[v.varId];
					return true;
				});
			}
			else {
				var rem = shaderGraph.variables.splice(newIndex, 1);
				shaderGraph.variables.insert(oldIndex, rem[0]);

				shaderGraph.mapShaderVar((v) -> {
					v.varId = remap.indexOf(v.varId);
					return true;
				});
			}
			variableList.refresh();
			requestRecompile();
		}
		exec(false);
		undo.change(Custom(exec));
	}

	function removeVariable(index: Int) {
		var usedInGraph = false;
		shaderGraph.mapShaderVar((v) -> {
			if (v.varId == index) {
				usedInGraph = true;
				return false;
			}
			return true;
		});

		if (usedInGraph) {
			hide.Ide.inst.quickError("Can't remove, variable is used in this Shader Graph");
			return;
		}

		var variable = shaderGraph.variables[index];
		function exec(isUndo: Bool) {
			if (!isUndo) {
				shaderGraph.variables.splice(index, 1);

				// fix id of variables above ours
				shaderGraph.mapShaderVar((v) -> {
					if (v.varId > index) {
						v.varId --;
					}
					return true;
				});
			}
			else {
				shaderGraph.variables.insert(index, variable);

				// fix id of variables above ours
				shaderGraph.mapShaderVar((v) -> {
					if (v.varId > index-1) {
						v.varId ++;
					}
					return true;
				});
			}
			variableList.refresh();
			requestRecompile();
		}
		exec(false);
		undo.change(Custom(exec));
	}

	function renameParameter(item: Parameter, name: String) : Void {
		if (!validNameCheck.match(name))
		{
			parametersList.refresh();
			ide.quickError('"$name" is not a valid parameter name (must start with _ or a letter, and only contains letters, numbers and underscores)');
			return;
		}

		if (shaderGraph.parametersAvailable.find(p -> p != item && p.name == name) != null) {
			parametersList.refresh();
			ide.quickError('Parameter name "$name" already exist in this shadergraph');
			return;
		}

		var oldName = item.name;
		function exec(isUndo: Bool) {
			item.name = !isUndo ? name : oldName;
			item.variable.name = item.name;
			for (node in currentGraph.nodes) {
				var param = Std.downcast(node, ShaderParam);
				if (param == null)
					continue;
				graphEditor.refreshBox(node.id);
			}
			requestRecompile();
			parametersList.refresh();
		}
		exec(false);
		undo.change(Custom(exec));
	}

	function getParameterContent(parameter: Parameter) : Element {
		var content = new Element('<div class="content" ></div>');
		var defaultValue = new Element('<div class="values"><span>Default: </span></div>').appendTo(content);

		switch(parameter.type) {
			case TFloat:
				var parentRange = new Element('<input type="range" min="-1" max="1" />').appendTo(defaultValue);
				var range = new hide.comp.Range(null, parentRange);
				var rangeInput = @:privateAccess range.f;

				var save : Null<Float> = null;

				if (parameter.defaultValue == null) parameter.defaultValue = 0;
				range.value = parameter.defaultValue;

				var saveValue : Null<Float> = null;
				range.onChange = function(moving) {
					if (saveValue == null) {
						saveValue = shaderGraph.getParameter(parameter.id).defaultValue;
					}

					if (moving == false) {
						var old = saveValue;
						var curr = range.value;
						saveValue = null;
						function exec(isUndo : Bool) {
							var v = isUndo ? old : curr;
							parameter.defaultValue = v;
							range.value = v;
							updateParam(parameter.id);
						}
						exec(false);
						undo.change(Custom(exec));
						return;
					}

					if (!shaderGraph.setParameterDefaultValue(parameter.id, range.value))
						return;
					updateParam(parameter.id);
				};
			case TVec(4, VFloat):
				var parentPicker = new Element('<div style="width: 35px; height: 25px; display: inline-block;"></div>').appendTo(defaultValue);
				var picker = new hide.comp.ColorPicker.ColorBox(null, parentPicker, true, true);

				if (parameter.defaultValue == null)
					parameter.defaultValue = [0, 0, 0, 1];
				var start : h3d.Vector = h3d.Vector.fromArray(parameter.defaultValue);
				picker.value = start.toColor();

				var saveValue : Null<h3d.Vector4> = null;
				picker.onChange = function(move) {
					if (saveValue == null) {
						saveValue = new h3d.Vector4();
						saveValue.load(h3d.Vector4.fromArray(shaderGraph.getParameter(parameter.id).defaultValue));
					}
					if (!move) {
						var curr = h3d.Vector4.fromColor(picker.value);
						var old = saveValue;
						saveValue = null;
						function exec(isUndo : Bool) {
							var v = isUndo ? old : curr;
							picker.value = v.toColor();
							parameter.defaultValue = [v.x, v.y, v.z, v.w];
							updateParam(parameter.id);
						}
						exec(false);
						undo.change(Custom(exec));
						return;
					}
					var vecColor = h3d.Vector4.fromColor(picker.value);
					if (!shaderGraph.setParameterDefaultValue(parameter.id, [vecColor.x, vecColor.y, vecColor.z, vecColor.w]))
						return;
					//setBoxesParam(parameter.id);
					updateParam(parameter.id);
				};
			case TVec(n, VFloat):
				if (parameter.defaultValue == null)
					parameter.defaultValue = [for (i in 0...n) 0.0];


				var ranges : Array<hide.comp.Range> = [];

				var saveValue : Array<Float> = null;

				for( i in 0...n ) {
					var parentRange = new Element('<input type="range" min="-1" max="1" />').appendTo(defaultValue);
					var range = new hide.comp.Range(null, parentRange);
					ranges.push(range);
					range.value = parameter.defaultValue[i];

					var rangeInput = @:privateAccess range.f;

					range.onChange = function(move) {
						if (saveValue == null) {
							saveValue = (shaderGraph.getParameter(parameter.id).defaultValue:Array<Float>).copy();
						}

						if (move == false) {
							var old = saveValue;
							var curr = [for (i in 0...n) ranges[i].value];
							saveValue = null;
							function exec(isUndo : Bool) {
								var v = isUndo ? old : curr;
								parameter.defaultValue = parameter.id;
								shaderGraph.setParameterDefaultValue(parameter.id, v);
								for (i in 0 ... n)
									ranges[i].value = v[i];

								updateParam(parameter.id);
							}
							exec(false);
							undo.change(Custom(exec));
							return;
						}

						parameter.defaultValue[i] = range.value;
						updateParam(parameter.id);
					};
				}
			case TSampler(_):
				var parentSampler = new Element('<input type="texturepath" field="sampler2d"/>').appendTo(defaultValue);

				var tselect = new hide.comp.TextureChoice(null, parentSampler);
				var saveValue : String = null;
				tselect.value = parameter.defaultValue;
				tselect.onChange = function(notTmpChange: Bool) {
					if (saveValue == null) {
						saveValue = haxe.Json.stringify(parameter.defaultValue);
					}
					var currentValue = haxe.Json.parse(haxe.Json.stringify(tselect.value));
					if (notTmpChange) {
						var prev = haxe.Json.parse(saveValue);
						saveValue = null;
						var curr = currentValue;
						function exec(isUndo: Bool) {
							var v = !isUndo ? curr : prev;
							parameter.defaultValue = v;
							tselect.value = v;

							if (!updateParam(parameter.id)) {
								// If the graph was initialised without the variable,
								// we need to recompile it
								requestRecompile();
							}
						}
						exec(false);
						this.undo.change(Custom(exec));
						return;
					}
					if (!shaderGraph.setParameterDefaultValue(parameter.id, currentValue))
						return;
					if (!updateParam(parameter.id)) {
						// If the graph was initialised without the variable,
						// we need to recompile it
						requestRecompile();
					}
				}

			default:
		}

		var internal = new Element('<div><input type="checkbox" name="internal" id="internal"></input><label for="internal">Internal</label><div>').appendTo(content).find("#internal");
		internal.prop("checked", parameter.internal ?? false);

		internal.on('change', function(e) {
			//beforeChange();
			parameter.internal = internal.prop("checked");
			//afterChange();
		});

		var perInstanceCb = new Element('<div><input type="checkbox" name="perinstance"/><label for="perinstance">Per instance</label><div>');
		var shaderParams : Array<ShaderParam> = [];

		var checkbox = perInstanceCb.find("input");
		if (shaderParams.length > 0)
			checkbox.prop("checked", shaderParams[0].perInstance);
		checkbox.on("change", function() {
			//beforeChange();
			var checked : Bool = checkbox.prop("checked");
			for (shaderParam in shaderParams)
				shaderParam.perInstance = checked;
			//afterChange();
			requestRecompile();
		});
		perInstanceCb.appendTo(content);

		return content;

	}

	function reorderParameter(oldIndex: Int, newIndex: Int) {
		var oldIndexes: Map<Int, Int> = [];
		for (idx => param in shaderGraph.parametersAvailable) {
			oldIndexes[idx] = param.index;
		}

		function exec(isUndo: Bool) {
			if (!isUndo) {
				for (param in shaderGraph.parametersAvailable) {
					if (param.index == oldIndex) {
						param.index = newIndex;
					} else {
						if (param.index >= oldIndex) {
							param.index --;
						}

						if (param.index >= newIndex) {
							param.index ++;
						}
					}
				}
			} else {
				for (i => param in shaderGraph.parametersAvailable) {
					param.index = oldIndexes[i];
				}
			}
			parametersList.refresh();
		}
		exec(false);
		undo.change(Custom(exec));
	}

	function removeParameter(orderIndex: Int) {
		var param = null;
		var index = null;
		for (iterIndex => iterParam in shaderGraph.parametersAvailable) {
			if (iterParam.index == orderIndex) {
				param = iterParam;
				index = iterIndex;
			}
		}

		var canBeDeleted = true;
		for (graph in shaderGraph.graphs) {
			for (node in graph.nodes) {
				var param = Std.downcast(node, ShaderParam);
				if (param == null)
					continue;
				if (param.parameterId == index) {
					canBeDeleted = false;
					break;
				}
			}
			if (!canBeDeleted)
				break;
		}

		if (!canBeDeleted) {
			ide.quickError("Paramter " + param.name + " is used in the graph and can't be deleted");
			return;
		}

		function exec(isUndo: Bool)  {
			if (!isUndo) {
				shaderGraph.parametersAvailable.remove(index);

				for (param in shaderGraph.parametersAvailable) {
					if (param.index > orderIndex) {
						param.index --;
					}
				}
			} else {
				for (param in shaderGraph.parametersAvailable) {
					if (param.index >= orderIndex) {
						param.index ++;
					}
				}

				shaderGraph.parametersAvailable.set(index, param);
			}

			parametersList.refresh();
		}

		exec(false);
		undo.change(Custom(exec));
	}

	function createParameter(type : HxslType) {
		@:privateAccess var paramShaderID : Int = shaderGraph.current_param_id++;
		@:privateAccess
		function exec(isUndo:Bool) {
			if (!isUndo) {
				var name = "Param_" + paramShaderID;
				shaderGraph.parametersAvailable.set(paramShaderID, {id: paramShaderID, name : name, type : type, defaultValue : null, variable : shaderGraph.generateParameter(name, type), index : shaderGraph.parametersAvailable.count()});
			} else {
				shaderGraph.parametersAvailable.remove(paramShaderID);
			}
			parametersList.refresh();
		}

		exec(false);
		undo.change(Custom(exec));
		var paramShader = shaderGraph.getParameter(paramShaderID);
		parametersList.editTitle(paramShader.index);
		parametersList.toggleItem(paramShader.index, true);
	}

	function updateParam(id : Int) : Bool {
		meshPreviewScene.setCurrent(); // needed for texture changes

		var param = shaderGraph.getParameter(id);
		var init = compiledShader.inits.find((i) -> i.variable.name == param.name);
		if (init != null) {
			setParamValue(meshPreviewShader, init.variable, param.defaultValue);
			return true;
		}
		return false;
	}

	var parametersUpdate : Map<Int, (Dynamic) -> Void> = [];

	function toggleParameter( elt : JQuery, ?b : Bool) {
		var icon = elt.find(".ico");
		if (b == null) {
			b = !icon.hasClass("fa-rotate-90");
		}
		if (b)
			elt.find(".content").show();
		else
			elt.find(".content").hide();

		icon.toggleClass("fa-rotate-90", b);
	}


	public function loadSettings() {
		var save = haxe.Json.parse(getDisplayState("previewSettings") ?? "{}");
		previewSettings = new PreviewSettings();
		for (f in Reflect.fields(previewSettings)) {
			var v = Reflect.field(save, f);
			if (v != null) {
				Reflect.setField(previewSettings, f, v);
			}
		}

		previewSettings.renderPropsPath = null;

		if (previewSettings.renderPropsPath == null) {
			previewSettings.renderPropsPath = defaultRenderProps()?.value;
		}
	}

	function listRenderProps() {
		var renderProp = config.getLocal("scene.renderProps");
		if (renderProp != null) {
			var renderProps : Array<Dynamic> = renderProp is String ? [{"name": "Default", "value": renderProp}] : cast renderProp;
			return renderProps;
		}
		return null;
	}

	function defaultRenderProps() {
		var renderProps = listRenderProps();
		if (renderProps != null)
			return renderProps[0];
		return null;
	}

	public function savePreviewSettings() {
		saveDisplayState("previewSettings", haxe.Json.stringify(previewSettings));
	}

	public function revealParameter(id: Int) : Void {
		var param = shaderGraph.parametersAvailable[id];
		parametersList.reveal(param.index);
	}

	public function revealVariable(id: Int) : Void {
		variableList.reveal(id);
	}

	public function disposeMeshPreview() {
		if (meshPreviewScene != null) {
			meshPreviewScene.dispose();
			previewElem.remove();
		}
	}

	public function initMeshPreview() {
		if (meshPreviewScene != null) {
			disposeMeshPreview();
		}
		previewElem = new Element('<div id="preview"></div>').appendTo(graphEditor.element);
		var sceneContainer = new Element('<div class="scene-container"></div>').appendTo(previewElem);

		previewElem.width(previewSettings.width);
		previewElem.height(previewSettings.height);
		meshPreviewScene = new hide.comp.Scene(config, null, sceneContainer);
		meshPreviewScene.onReady = onMeshPreviewReady;
		meshPreviewScene.onUpdate = onMeshPreviewUpdate;
		meshPreviewScene.enableNewErrorSystem = true;

		var resizeUp = new Element('<div class="resize-handle up">').appendTo(previewElem);
		var resizeLeft = new Element('<div class="resize-handle left">').appendTo(previewElem);
		var resizeUpLeft = new Element('<div class="resize-handle up-left">').appendTo(previewElem);

		function configureDrag(elt: js.html.Element, left: Bool, up: Bool) {
			var pressed = false;

			elt.onpointerdown = function(e: js.html.PointerEvent) {
				if (e.button != 0)
					return;
				e.stopPropagation();
				e.preventDefault();
				pressed = true;
				elt.setPointerCapture(e.pointerId);
			};

			elt.onpointermove = function(e: js.html.PointerEvent) {
				if (!pressed)
					return;
				e.stopPropagation();
				e.preventDefault();

				var prev = previewElem.get(0);
				var rect = prev.getBoundingClientRect();

				if (left)
					prev.style.width = rect.right - e.clientX + "px";
				if (up)
					prev.style.height = rect.bottom - e.clientY + "px";
			}

			elt.onpointerup = function (e: js.html.PointerEvent) {
				if (!pressed)
					return;
				pressed = false;
				e.stopPropagation();
				e.preventDefault();

				var prev = previewElem.get(0);
				var rect = prev.getBoundingClientRect();
				previewSettings.width = Std.int(rect.width);
				previewSettings.height = Std.int(rect.height);
				savePreviewSettings();
			};
		}

		configureDrag(resizeUp.get(0), false, true);
		configureDrag(resizeLeft.get(0), true, false);
		configureDrag(resizeUpLeft.get(0), true, true);


		var toolbar = new Element('<div class="hide-toolbar2"></div>').appendTo(previewElem);
		var group = new Element('<div class="tb-group"></div>').appendTo(toolbar);
		var menu = new Element('<div class="button2 transparent" title="More options"><div class="ico ico-navicon"></div></div>');
		menu.appendTo(group);

		function getScreenFXBlend(blend: h3d.mat.PbrMaterial.PbrBlend) : hide.comp.ContextMenu.MenuItem {
			return {label: "Blend " + cast blend, click: () -> {
					previewSettings.screenFXBlend = blend;

					for (fx in meshPreviewScreenFX) {
						fx.blend = blend;
					}

					savePreviewSettings();
				},
				checked: meshPreviewScreenFX[0]?.blend == blend
			}
		};

		var blends: Array<h3d.mat.PbrMaterial.PbrBlend> = [
			None,
			Alpha,
			Add,
			AlphaAdd,
			Multiply,
			AlphaMultiply,
		];


		var screenFXMenu: Array<hide.comp.ContextMenu.MenuItem> = [
			{label: "Use Prev Target", click: () -> setPreviewScreenFXUsePrevTarget(!previewSettings.screenFXusePrevTarget), checked: previewSettings.screenFXusePrevTarget},
			{isSeparator: true},
		];

		for (blend in blends) {
			screenFXMenu.push(getScreenFXBlend(blend));
		}

		var renderPropMenu : Array<hide.comp.ContextMenu.MenuItem> = [];

		var renderProps = listRenderProps();
		if (renderProps != null) {
			for (render in renderProps) {
				renderPropMenu.push({
					label: render.name,
					click: () -> {
						previewSettings.renderPropsPath = render.value;
						refreshRenderProps();
						savePreviewSettings();
					},
					radio: () -> {
						render.value == previewSettings.renderPropsPath;
					},
					stayOpen: true,
				});
			}
		}

		menu.click((e) -> {
			hide.comp.ContextMenu.createDropdown(menu.get(0), [
				{label: "Reset Camera", click: resetPreviewCamera},
				{label: "Reset Preview Size", click: resetPreviewSize},
				{isSeparator: true},
				{label: "Sphere", click: setMeshPreviewSphere},
				{label: "Plane", click: setMeshPreviewPlane},
				{label: "Screen FX", click: setMeshPreviewScreenFX},
				{label: "Mesh ...", click: chooseMeshPreviewFBX},
				{label: "Prefab/FX ...", click: chooseMeshPreviewPrefab},
				{isSeparator: true},
				{label: "Material Settings", menu: [
					{label: "Alpha Blend", click: () -> {previewSettings.alphaBlend = !previewSettings.alphaBlend; meshPreviewShader = null; savePreviewSettings();}, stayOpen: true, checked: previewSettings.alphaBlend},
					{label: "Backface Cull", click: () -> {previewSettings.backfaceCulling = !previewSettings.backfaceCulling; meshPreviewShader = null; savePreviewSettings();}, stayOpen: true, checked: previewSettings.backfaceCulling},
					{label: "Unlit", click: () -> {previewSettings.unlit = !previewSettings.unlit; meshPreviewShader = null; savePreviewSettings();}, stayOpen: true, checked: previewSettings.unlit},
					{label: "Shadows", click: () -> {previewSettings.shadows = !previewSettings.shadows; meshPreviewShader = null; savePreviewSettings();}, stayOpen: true, checked: previewSettings.shadows},
				], enabled: meshPreviewPrefab == null},
				{label: "Screen FX", enabled: meshPreviewPrefab == null && meshPreviewScreenFX.length > 0, menu: screenFXMenu},
				{label: "Render Settings", menu: [
					{label: "Background Color", click: openBackgroundColorMenu},
					{label: "Render Props", menu: renderPropMenu},
					{label: "Clear Render Props", click: clearRenderProps},
				]}
			]);
		});
	}

	public function setPreviewScreenFXUsePrevTarget(value: Bool) {
		previewSettings.screenFXusePrevTarget = value;
		for (fx in meshPreviewScreenFX) {
			fx.usePrevTarget = value;
		}

		savePreviewSettings();
	}

	public function setPrefabAndRenderDelayed(prefab: String, renderProps: String) {
		if (previewSettings == null)
			loadSettings();
		previewSettings.meshPath = prefab;
		previewSettings.renderPropsPath = renderProps;
		savePreviewSettings();
	}

	public function clearRenderProps() {
		previewSettings.renderPropsPath = null;
		refreshRenderProps();
		savePreviewSettings();
	}

	public function selectRenderProps() {
		var basedir = haxe.io.Path.directory(previewSettings.renderPropsPath ?? "");
		if (basedir == "" || !haxe.io.Path.isAbsolute(basedir)) {
			haxe.io.Path.join([Ide.inst.resourceDir, basedir]);
		}

		Ide.inst.chooseFile(["prefab"], (path) -> {
			previewSettings.renderPropsPath = path;
			refreshRenderProps();
			savePreviewSettings();
		}, true, basedir);
	}

	public function openBackgroundColorMenu() {
		var prev = element.find("#preview");

		var cp = new hide.comp.ColorPicker(false, element.find("#preview"));
		@:privateAccess
		{
			var offset = cp.element.offset();
			offset.top -= prev.get(0).offsetHeight;
			cp.element.offset(offset);
		}

		cp.value = previewSettings.bgColor;
		var prev : Null<Int> = null;
		cp.onChange = function(isDragging:Bool) {
			if (prev == null) {
				prev = cp.value;
			}
			if (!isDragging) {
				var cur = cp.value;
				var exec = function(isUndo: Bool) {
					var v = !isUndo ? cur : prev;
					cp.value = v;
					previewSettings.bgColor = v;
					savePreviewSettings();
				}
				exec(false);
				undo.change(Custom(exec));
				return;
			}
			previewSettings.bgColor = cp.value;
		}

	}

	public function onMeshPreviewUpdate(dt: Float) {

		if (queueReloadMesh) {
			queueReloadMesh = false;
			loadMeshPreviewFromString(previewSettings.meshPath);
		}
		if (meshPreviewShader == null) {
			checkCompileShader();
			@:privateAccess meshPreviewScene.checkCurrent();
			meshPreviewShader = new hxsl.DynamicShader(compiledShader.shader);

			for (init in compiledShader.inits) {
				setParamValue(meshPreviewShader, init.variable, init.value);
			}
			for (m in meshPreviewMeshes) {
				replaceMeshShader(m, meshPreviewShader);
			}

			for (fx in meshPreviewScreenFX) {
				@:privateAccess fx.shaderPass.removeShader(fx.shader);

				@:privateAccess fx.shaderDef = compiledShader;
				@:privateAccess fx.shader = meshPreviewShader;

				for (v in compiledShader.inits) {
					Reflect.setField(fx.props, v.variable.name, v.value);
				}

				@:privateAccess fx.shaderPass.addShader(fx.shader);
			}
		}
		meshPreviewScene.engine.backgroundColor = previewSettings.bgColor;

		var anims = meshPreviewRoot3d.findAll((f) -> Std.downcast(f, hrt.prefab.fx.FX.FXAnimation));
		for (anim in anims) {
			@:privateAccess anim.setTime(meshPreviewScene.s3d.renderer.ctx.time % anim.duration, true);
		}
	}

	public function refreshRenderProps() {
		meshPreviewScene.setRenderProps(previewSettings.renderPropsPath);
	}

	public function dispose() {
		cleanupPreview();
		meshPreviewScene.dispose();

	}

	public function cleanupPreview() {
		if (meshPreviewPrefab != null) {
			meshPreviewPrefab.dispose();
			meshPreviewPrefab = null;
			if (meshPreviewprefabWatch != null) {
				Ide.inst.fileWatcher.unregister(meshPreviewprefabWatch.path, meshPreviewprefabWatch.fun);
				meshPreviewprefabWatch = null;
			}
		}
		for (mesh in meshPreviewMeshes)
			mesh.remove();

		for (fx in meshPreviewScreenFX) {
			fx.editorRemoveObjects();
		}
		meshPreviewScreenFX.resize(0);

		meshPreviewRoot3d.removeChildren();
	}

	public function setMeshPreviewMesh(mesh: h3d.scene.Mesh) {
		cleanupPreview();

		meshPreviewRoot3d.addChild(mesh);
		meshPreviewMeshes.resize(0);
		meshPreviewMeshes.push(mesh);

		meshPreviewShader = null;
		resetPreviewCamera();
	}

	public function setMeshPreviewSphere() {
		previewSettings.meshPath = "Sphere";
		savePreviewSettings();

		var sp = new h3d.prim.Sphere(1, 128, 128);
		sp.addNormals();
		sp.addUVs();
		sp.addTangents();
		setMeshPreviewMesh(new h3d.scene.Mesh(sp));
	}

	public function setMeshPreviewPlane() {
		previewSettings.meshPath = "Plane";
		savePreviewSettings();

		var plane = hrt.prefab.l3d.Polygon.createPrimitive(Quad(4));
		var m = new h3d.scene.Mesh(plane);
		m.setScale(2.0);
		m.material.mainPass.culling = None;
		m.z += 0.001;
		setMeshPreviewMesh(m);
	}

	public function setMeshPreviewScreenFX() {
		cleanupPreview();
		previewSettings.meshPath = "ScreenFX";

		var shared = new hide.prefab.ContextShared(null, meshPreviewRoot3d);
		var root = new hrt.prefab.fx.FX(null, shared);
		var screenFX = new hrt.prefab.rfx.ScreenShaderGraph(root, shared);
		@:privateAccess screenFX.shaderGraph = this.shaderGraph;
		root.make();

		meshPreviewScreenFX.push(screenFX);
		meshPreviewShader = null;

		for (fx in meshPreviewScreenFX) {
			fx.usePrevTarget = previewSettings.screenFXusePrevTarget;
			fx.blend = previewSettings.screenFXBlend;
		}
		savePreviewSettings();
	}

	public function chooseMeshPreviewFBX() {
		var basedir = haxe.io.Path.directory(previewSettings.meshPath ?? "");
		if (basedir == "" || !haxe.io.Path.isAbsolute(basedir)) {
			haxe.io.Path.join([Ide.inst.resourceDir, basedir]);
		}
		Ide.inst.chooseFile(["fbx"], (path : String) -> {
			if (path == null)
				return;
			setMeshPreviewFBX(path);
		}, false, basedir);
	}

	public function chooseMeshPreviewPrefab() {
		var basedir = haxe.io.Path.directory(previewSettings.meshPath);
		if (basedir == "" || !haxe.io.Path.isAbsolute(basedir)) {
			haxe.io.Path.join([Ide.inst.resourceDir, basedir]);
		}
		Ide.inst.chooseFile(["prefab", "fx"], (path : String) -> {
			if (path == null)
				return;
			setMeshPreviewPrefab(path);
		}, false, basedir);
	}

	public function resetPreviewCamera() {
		var bounds = meshPreviewRoot3d.getBounds();
		var sp = bounds.toSphere();
		meshPreviewCameraController.set(sp.r * 3.0, Math.PI / 4, Math.PI * 5 / 13, sp.getCenter());
	}

	public function resetPreviewSize() {
		var def = new PreviewSettings();
		previewSettings.width = def.width;
		previewSettings.height = def.height;

		previewElem.width(previewSettings.width);
		previewElem.height(previewSettings.height);

		savePreviewSettings();
	}

	public function loadMeshPreviewFromString(str: String) {
		switch (str){
			case "Sphere":
				setMeshPreviewSphere();
			case "Plane":
				setMeshPreviewPlane();
			case "ScreenFX":
				setMeshPreviewScreenFX();
			default: {
				if (StringTools.endsWith(str, ".fbx")) {
					setMeshPreviewFBX(str);
				}
				else if (StringTools.endsWith(str, ".fx") || StringTools.endsWith(str, ".prefab")) {
					setMeshPreviewPrefab(str);
				}
				else {
					setMeshPreviewSphere();
				}
			}
		}
	}

	public function setMeshPreviewFBX(str: String) {
		var model : h3d.scene.Mesh = null;
		try {
			var loadedModel = meshPreviewScene.loadModel(str, false, true);
			model = loadedModel.find((f) -> Std.downcast(f, h3d.scene.Mesh));
			if (model == null)
				throw "invalid model";
		} catch (e) {
			Ide.inst.quickError('Could not load mesh $str, error : $e');
			setMeshPreviewSphere();
			return;
		}

		setMeshPreviewMesh(model);
		previewSettings.meshPath = str;
		savePreviewSettings();
	}

	public function setMeshPreviewPrefab(str: String) {
		cleanupPreview();
		meshPreviewScene.setCurrent();

		try {
			meshPreviewPrefab = Ide.inst.loadPrefab(str);
		} catch (e) {
			Ide.inst.quickError('Could not load mesh $str, error : $e');
			setMeshPreviewSphere();
			return;
		}


		var ctx = new hide.prefab.ContextShared(null, meshPreviewRoot3d);
		ctx.scene = meshPreviewScene;
		meshPreviewPrefab.setSharedRec(ctx);
		meshPreviewPrefab.make();
		meshPreviewMeshes.resize(0);

		var meshes = meshPreviewRoot3d.findAll((f) -> Std.downcast(f, h3d.scene.Mesh));
		for (mesh in meshes) {
			var mats = mesh.getMaterials();
			for (mat in mats) {
				for (shader in mat.mainPass.getShaders()) {
					var dyn = Std.downcast(shader, DynamicShader);
					if (dyn != null) {
						@:privateAccess
						if (dyn.shader.data.name == this.state.path) {
							meshPreviewMeshes.push(mesh);
							break;
						}
					}
				}
			}
		}

		meshPreviewScreenFX = meshPreviewPrefab.findAll(hrt.prefab.rfx.ScreenShaderGraph, (p) -> p.source == this.state.path);

		if (meshPreviewMeshes.length <= 0 && meshPreviewScreenFX.length <= 0) {
			Ide.inst.quickError('Prefab/FX $str does not contains this shadergraph');
			setMeshPreviewSphere();
			return;
		}

		meshPreviewprefabWatch = Ide.inst.fileWatcher.register(str, () -> queueReloadMesh = true, false);

		meshPreviewShader = null;
		resetPreviewCamera();
		previewSettings.meshPath = str;
		savePreviewSettings();
	}

	public function onMeshPreviewReady() {
		if (meshPreviewScene.s3d == null)
			throw "meshPreviewScene not ready";

		var moved = false;
		meshPreviewCameraController = new hide.comp.Scene.PreviewCamController(meshPreviewScene.s3d);
		meshPreviewRoot3d = new h3d.scene.Object(meshPreviewScene.s3d);

		loadMeshPreviewFromString(previewSettings.meshPath);
		refreshRenderProps();
	}

	public function replaceMeshShader(mesh: h3d.scene.Mesh, newShader: hxsl.DynamicShader) {
		if (newShader == null)
			return;

		var found = false;

		@:privateAccess
		for (m in mesh.getMaterials()) {

			var curShaderList = m.mainPass.shaders;
			while (curShaderList != null && curShaderList != m.mainPass.parentShaders) {
				var dyn = Std.downcast(curShaderList.s, hxsl.DynamicShader);

				@:privateAccess
				if (dyn != null) {
					if (dyn.shader.data.name == newShader.shader.data.name) {
						found = true;
						curShaderList.s = newShader;
						m.mainPass.resetRendererFlags();
						m.mainPass.selfShadersChanged = true;
					}
				}

				// Only override renderer settings if we are not previewing a prefab
				// (because prefabs can have their own material settings)
				if (meshPreviewPrefab == null) {
					m.blendMode = previewSettings.alphaBlend ? Alpha : None;
					m.mainPass.culling = previewSettings.backfaceCulling ? Back : None;
					if (previewSettings.unlit)
						m.mainPass.setPassName("afterTonemapping");
					else
						m.mainPass.setPassName("default");

					m.shadows = previewSettings.shadows;
				}

				curShaderList = curShaderList.next;
			}
		}

		if (!found) {
			for (m in mesh.getMaterials()) {
				m.mainPass.addShader(newShader);
			}
		}
	}


	public function onPreviewUpdate() {
		checkCompileShader();

		@:privateAccess
		{
			var engine = graphEditor.previewsScene.engine;
			var t = engine.getCurrentTarget();
			graphEditor.previewsScene.s2d.ctx.globals.set("global.pixelSize", new h3d.Vector(2 / (t == null ? engine.width : t.width), 2 / (t == null ? engine.height : t.height)));
			graphEditor.previewsScene.s2d.ctx.globals.set("blackChannel", h3d.mat.Texture.fromColor(0));
			graphEditor.previewsScene.s2d.ctx.globals.set("global.screenShaderInput", h3d.mat.Texture.fromColor(0xFF00FF));

		}

		@:privateAccess
		if (meshPreviewScene != null && meshPreviewScene.s3d != null) {
			meshPreviewScene.s3d.renderer.ctx.time = graphEditor.previewsScene.s3d.renderer.ctx.time;
		}

		return true;
	}
	var bitmapToShader : Map<h2d.Bitmap, hxsl.DynamicShader> = [];
	public function onNodePreviewUpdate(node: IGraphNode, bitmap: h2d.Bitmap) {
		if (compiledShaderPreview == null) {
			bitmap.visible = false;
			return;
		}
		var shader = bitmapToShader.get(bitmap);
		if (shader == null) {
			for (s in bitmap.getShaders()) {
				bitmap.removeShader(s);
			}
			shader = new DynamicShader(compiledShaderPreview.shader);
			bitmapToShader.set(bitmap, shader);
			bitmap.addShader(previewShaderBase);
			bitmap.addShader(shader);
			if (previewSettings.previewAlpha)
				bitmap.addShader(previewShaderAlpha);
		}
		for (init in compiledShaderPreview.inits) {
			@:privateAccess graphEditor.previewsScene.checkCurrent();
			if (init.variable == previewVar)
				setParamValue(shader, previewVar, node.id + 1);
			else {
				var param = shaderGraph.parametersAvailable.find((v) -> v.name == init.variable.name);
				if (param !=null) {
					setParamValue(shader, init.variable, param.defaultValue);
				}
			}
		}
	}

	function setParamValue(shader : DynamicShader, variable : hxsl.Ast.TVar, value : Dynamic) {
		@:privateAccess ShaderGraph.setParamValue(shader, variable, value);

		for (fx in meshPreviewScreenFX) {
			Reflect.setField(fx.props, variable.name, value);
		}
	}

	/** IGraphEditor interface **/
	public function getNodes() : Iterator<IGraphNode> {
		return currentGraph.getNodes().iterator();
	}

	public function getEdges() : Iterator<Edge> {
		var edges : Array<Edge> = [];
		for (id => node in currentGraph.getNodes()) {
			for (inputId => connection in node.connections) {
				if (connection != null) {
					edges.push(
						{
							nodeFromId: connection.from.getId(),
							outputFromId: connection.outputId,
							nodeToId: id,
							inputToId: inputId,
						});
				}
			}
		}
		return edges.iterator();
	}

	public function serializeNode(node: IGraphNode) : Dynamic {
		return (cast node:ShaderNode).serializeToDynamic();
	}

	public function unserializeNode(data : Dynamic, newId : Bool) : IGraphNode {
		var node = ShaderNode.createFromDynamic(data, currentGraph);
		if (newId) {
			@:privateAccess var newId = currentGraph.current_node_id++;
			node.setId(newId);
		}
		return node;
	}

	public function createCommentNode() : Null<IGraphNode> {
		var node = new hrt.shgraph.nodes.Comment();
		node.comment = "Comment";
		@:privateAccess var newId = currentGraph.current_node_id++;
		node.setId(newId);
		return node;
	}

	public function getAddNodesMenu(currentEdge: Null<Edge>) : Array<AddNodeMenuEntry> {
		var entries : Array<AddNodeMenuEntry> = [];

		final needCompatibilityCheck = currentEdge != null;

		function checkCompatibilityWithEdge(node: ShaderNode) {
			if (currentEdge != null) {
				node.graph = currentGraph;
				if (currentEdge.nodeToId != null) {
					var to = currentGraph.nodes[currentEdge.nodeToId];
					var input = to.getInputs()[currentEdge.inputToId];
					var outputs = node.getOutputs();
					for (output in outputs) {
						if(hrt.shgraph.ShaderGraph.Graph.areTypesCompatible(input.type, output.type)) {
							return true;
						}
					}
				}

				if (currentEdge.nodeFromId != null) {
					var from = currentGraph.nodes[currentEdge.nodeFromId];
					var output = from.getOutputs()[currentEdge.outputFromId];
					var inputs = node.getInputs();
					for (input in inputs) {
						if (hrt.shgraph.ShaderGraph.Graph.areTypesCompatible(input.type, output.type)) {
							return true;
						}
					}
				}
				return false;
			}
			return true;
		}

		var id = 0;
		for (i => node in ShaderNode.registeredNodes) {
			var metas = haxe.rtti.Meta.getType(node);
			if (metas.group == null) {
				continue;
			}

			if (Reflect.hasField(metas,"hideInAddMenu"))
				continue;

			var group = metas.group != null ? metas.group[0] : "Other";
			var name = metas.name != null ? metas.name[0] : "unknown";
			var description = metas.description != null ? metas.description[0] : "";

			if (!needCompatibilityCheck || checkCompatibilityWithEdge(Type.createInstance(node, []))) {
				entries.push(
					{
						name: name,
						group: group,
						description: description,
						onConstructNode: () -> {
							@:privateAccess var id = currentGraph.current_node_id++;
							var inst = std.Type.createInstance(node, []);
							inst.setId(id);
							return inst;
						},
					}
				);
			}

			var aliases = std.Type.createEmptyInstance(node).getAliases(name, group, description) ?? [];
			for (alias in aliases) {
				if (!needCompatibilityCheck || checkCompatibilityWithEdge(std.Type.createInstance(node, alias.args ?? []))) {
					entries.push(
						{
							name: alias.nameSearch ?? alias.nameOverride ?? name,
							group: alias.group ?? group,
							description: alias.description ?? description,
							onConstructNode: () -> {
								@:privateAccess var id = currentGraph.current_node_id++;
								var inst = std.Type.createInstance(node, alias.args ?? []);
								inst.setId(id);
								return inst;
							},
						}
					);
				}
			}
		}
		return entries;
	}


	public function addNode(node: IGraphNode) : Void {
		currentGraph.addNode(cast node);
		requestRecompile();
	}

	public function removeNode(id: Int) : Void {
		currentGraph.removeNode(id);
		requestRecompile();
	}

	public function canAddEdge(edge: Edge) : Bool {
		return currentGraph.canAddEdge({outputNodeId: edge.nodeFromId, outputId: edge.outputFromId, inputNodeId: edge.nodeToId, inputId: edge.inputToId});
	}

	public function addEdge(edge: Edge) : Void {
		var input = currentGraph.getNode(edge.nodeToId);
		input.connections[edge.inputToId] = {from: currentGraph.getNode(edge.nodeFromId), outputId: edge.outputFromId};
		requestRecompile();
	}

	public function removeEdge(nodeToId: Int, inputToId: Int) : Void {
		var input = currentGraph.getNode(nodeToId);
		input.connections[inputToId] = null;
		requestRecompile();
	}

	public override function save() {
		var content = shaderGraph.saveToText();
		currentSign = ide.makeSignature(content);
		sys.io.File.saveContent(getPath(), content);
		super.save();
	}

	public function getUndo() : hide.ui.UndoHistory {
		return undo;
	}

	override function getDefaultContent() {
		var p = (new hrt.shgraph.ShaderGraph(null, null)).serialize();
		return haxe.io.Bytes.ofString(ide.toJSON(p));
	}

	public function requestRecompile() {
		needRecompile = true;
	}

	public function checkCompileShader() {
		if (!needRecompile)
			return;
		needRecompile = false;
		try {
			var start = Timer.stamp();
			compiledShader = shaderGraph.compile();
			compiledShaderPreview = shaderGraph.compile(currentGraph.domain);
			bitmapToShader.clear();
			previewVar = compiledShaderPreview.inits.find((e) -> e.variable.name == hrt.shgraph.Variables.previewSelectName)?.variable;
			var end = Timer.stamp();

			meshPreviewShader = null;
		} catch (err) {
			Ide.inst.quickError(err);
		}
	}

	static var _ = FileTree.registerExtension(ShaderEditor,["shgraph"],{ icon : "scribd", createNew: "Shader Graph" });
}
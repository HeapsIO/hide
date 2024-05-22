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
import hide.view.GraphInterface;


typedef NodeInfo = { name : String, description : String, key : String };

typedef SavedClipboard = {
	nodes : Array<{
		pos : Point,
		nodeType : Class<ShaderNode>,
		props : Dynamic,
	}>,
	edges : Array<{ fromIdx : Int, fromOutputId : Int, toIdx : Int, toInputId : Int }>,
}

class PreviewCamController extends h3d.scene.Object {
	var target : Vector = new h3d.Vector();
	var targetInterp : Vector = new h3d.Vector();
	var pos : Vector = new h3d.Vector();

	var phi : Float = 0.4;
	var theta : Float = 0.4;
	var r : Float = 4.0;

	var phiInterp : Float = 0.4;
	var thetaInterp : Float = 0.4;
	var rInterp : Float = 4.0;

	function computePos() {
		pos.x = rInterp * hxd.Math.sin(thetaInterp) * hxd.Math.cos(phiInterp);
		pos.y = rInterp * hxd.Math.sin(thetaInterp) * hxd.Math.sin(phiInterp);
		pos.z = rInterp * hxd.Math.cos(thetaInterp);
		pos += targetInterp;
	}

	public function set(r: Float, phi: Float, theta: Float, target: Vector) {
		this.r = r;
		this.phi = phi;
		this.theta = theta;
		this.target.load(target);
	}

	var pushing : Int = -1;
	var ignoreNext : Bool = false;
	function onEvent(e : hxd.Event) {
		switch (e.kind) {
			case EPush: {
				if (pushing != -1)
					return;
				pushing = e.button;
				var win = hxd.Window.getInstance();
				ignoreNext = true;
				win.mouseMode = Relative(onCapture, true);
			}
			case EWheel: {
				r += e.wheelDelta;
				r = hxd.Math.max(r, 0.0001);
			}
			case ERelease, EReleaseOutside:
				if (pushing != e.button) {
					return;
				}
				var win = hxd.Window.getInstance();
				win.mouseMode = Absolute;
				pushing = -1;
			default:
		}
	}

	function pan(dx, dy, dz = 0.) {
		var v = new h3d.Vector(dx, dy, dz);
		var cam = getScene().camera;
		cam.update();
		v.transform3x3(cam.getInverseView());
		target = target.add(v);
	}

	override function sync(ctx: h3d.scene.RenderContext) {
		var cam = getScene().camera;
		if (cam == null)
			return;


		var dt = hxd.Math.min(1, 1 - Math.pow(0.6, ctx.elapsedTime * 60));
		var dt2 = hxd.Math.min(1, 1 - Math.pow(0.4, ctx.elapsedTime * 60));

		thetaInterp = hxd.Math.lerp(thetaInterp, theta, dt2);
		phiInterp = hxd.Math.lerp(phiInterp, phi, dt2);
		rInterp = hxd.Math.lerp(rInterp, r, dt);
		targetInterp.lerp(targetInterp, target, dt);

		computePos();

		cam.target.load(targetInterp);
		cam.pos.load(pos);
	}

	override function onAdd() {
		getScene().addEventListener(onEvent);
	}

	override function onRemove() {
		getScene().removeEventListener(onEvent);
	}

	function onCapture(e: hxd.Event) {
		// For some reason sometimes the first
		// input from a capture has extreme values.
		// We just filter out all first events from a capture to mitigate this
		if (ignoreNext) {
			ignoreNext = false;
			return;
		}

		switch (e.kind) {
			case EMove:
				switch (pushing) {
					case 1:
						pan(-e.relX * 0.01, e.relY * 0.01);
					case 2:
						var dx = e.relX;
						var dy = e.relY;
						phi += dx * 0.01;
						theta -= dy * 0.01;
						theta = hxd.Math.clamp(theta, 0, hxd.Math.PI);
				}
			default:
		}

	}

	function onCleanup() {
		pushing = -1;
	}
}

class PreviewShaderBase extends hxsl.Shader {
	static var SRC = {

		@input var input : {
			var position : Vec2;
		};

		@global var global : {
			var time : Float;
			var pixelSize : Vec2;
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

class PreviewShaderAlpha extends hxsl.Shader {
	static var SRC = {
		@input var input : {
			var uv : Vec2;
		};

		var pixelColor : Vec4;

		function fragment() {
			var cb = floor(mod(input.uv * 10.0, vec2(2.0)));
			var check = mod(cb.x + cb.y, 2.0);
			var color = check >= 1.0 ? vec3(0.22) : vec3(0.44);
			pixelColor.rgb = mix(color, pixelColor.rgb, pixelColor.a);
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
	public function new() {};
}
class ShaderEditor extends hide.view.FileView implements GraphInterface.IGraphEditor {
	var graphEditor : hide.view.GraphEditor;
	var shaderGraph : hrt.shgraph.ShaderGraph;
	var currentGraph : hrt.shgraph.ShaderGraph.Graph;

	var compiledShader : hrt.prefab.Cache.ShaderDef;
	var compiledShaderPreview : hrt.prefab.Cache.ShaderDef;

	var previewShaderBase : PreviewShaderBase;
	var previewShaderAlpha : PreviewShaderAlpha;
	var previewVar : hxsl.Ast.TVar;
	var needRecompile : Bool = true;

	var meshPreviewScene : hide.comp.Scene;
	var meshPreviewMeshes : Array<h3d.scene.Mesh> = [];
	var meshPreviewRoot3d : h3d.scene.Object;
	var meshPreviewShader : hxsl.DynamicShader;
	var meshPreviewCameraController : PreviewCamController;
	var previewSettings : PreviewSettings;
	var meshPreviewPrefab : hrt.prefab.Prefab;
	var meshPreviewprefabWatch : hide.tools.FileWatcher.FileWatchEvent;
	var meshPreviewRenderProps : hrt.prefab.Prefab;
	var meshPreviewRenderPropsRoot : h3d.scene.Object;

	var parametersList : JQuery;
	var draggedParamId : Int;

	var defaultLight : hrt.prefab.Light;

	var queueReloadMesh = false;

	var domainSelection : JQuery;

	override function onDisplay() {
		super.onDisplay();
		element.html("");
		loadSettings();
		element.addClass("shader-editor");
 		shaderGraph = cast hide.Ide.inst.loadPrefab(state.path, null,  true);
		currentGraph = shaderGraph.getGraph(Fragment);
		previewShaderBase = new PreviewShaderBase();
		previewShaderAlpha = new PreviewShaderAlpha();

		if (graphEditor != null)
			graphEditor.remove();
		graphEditor = new hide.view.GraphEditor(config, this, this.element);
		graphEditor.onDisplay();

		graphEditor.element.on("drop" ,function(e) {
			var posCursor = new Point(graphEditor.lX(ide.mouseX - 25), graphEditor.lY(ide.mouseY - 10));
			var inst = new ShaderParam();
			@:privateAccess var id = currentGraph.current_node_id++;
			inst.id = id;
			inst.parameterId = draggedParamId;
			inst.shaderGraph = shaderGraph;
			inst.setPos(posCursor);

			graphEditor.opBox(inst, true, graphEditor.currentUndoBuffer);
			graphEditor.commitUndo();
			// var node = Std.downcast(currentGraph.addNode(posCursor.x, posCursor.y, ShaderParam, []), ShaderParam);
			// node.parameterId = draggedParamId;
			// var paramShader = shaderGraph.getParameter(draggedParamId);
			// node.variable = paramShader.variable;
			// node.setName(paramShader.name);
			//setDisplayValue(node, paramShader.type, paramShader.defaultValue);
			//addBox(posCursor, ShaderParam, node);
		});

		var rightPannel = new Element(
			'<div id="rightPanel">
				<div>
					<span>Parameters</span>
					<div class="hide-block" >
						<div id="parametersList" class="hide-scene-tree hide-list">
						</div>
					</div>
				</div>
				<div class="options-block hide-block">
					<input id="createParameter" type="button" value="Add parameter" />
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
			saveSettings();
			bitmapToShader.clear();
		});
		(cast previewAlpha[0]:Dynamic).checked = previewSettings.previewAlpha;

		rightPannel.appendTo(element);

		var newParamCtxMenu : Array<hide.comp.ContextMenu.ContextMenuItem> = [
			{ label : "Number", click : () -> createParameter(TFloat) },
			{ label : "Vec2", click : () -> createParameter(TVec(2, VFloat)) },
			{ label : "Vec3", click : () -> createParameter(TVec(3, VFloat)) },
			{ label : "Color", click : () -> createParameter(TVec(4, VFloat)) },
			{ label : "Texture", click : () -> createParameter(TSampler(T2D,false)) },
		];

		rightPannel.find("#createParameter").on("click", function() {
			new hide.comp.ContextMenu(newParamCtxMenu);
		});

		parametersList = rightPannel.find("#parametersList");
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

		for (k in shaderGraph.parametersKeys) {
			var pElt = addParameter(shaderGraph.parametersAvailable.get(k), shaderGraph.parametersAvailable.get(k).defaultValue);
		}


		rightPannel.find("#debugMenu").click((e) -> {
			new hide.comp.ContextMenu([
				{
					label : "Print Shader code to Console",
					click: () -> trace(hxsl.Printer.shaderToString(shaderGraph.compile(currentGraph.domain).shader.data, true))
				}
			]);
		});

		graphEditor.onPreviewUpdate = onPreviewUpdate;
		graphEditor.onNodePreviewUpdate = onNodePreviewUpdate;

		initMeshPreview();
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
		}

		exec(false);
		if (recordUndo) {
			undo.change(Custom(exec));
		}
	}

	function createParameter(type : Type) {
		@:privateAccess var paramShaderID : Int = shaderGraph.current_param_id++;
		@:privateAccess
		function exec(isUndo:Bool) {
			if (!isUndo) {
				var name = "Param_" + paramShaderID;
				shaderGraph.parametersAvailable.set(paramShaderID, {id: paramShaderID, name : name, type : type, defaultValue : null, variable : shaderGraph.generateParameter(name, type), index : shaderGraph.parametersKeys.length});
				shaderGraph.parametersKeys.push(paramShaderID);

				var paramShader = shaderGraph.getParameter(paramShaderID);
				var elt = addParameter(paramShader, null);
				elt.find(".input-title").focus();
			} else {
				shaderGraph.parametersAvailable.remove(paramShaderID);
				shaderGraph.parametersKeys.remove(paramShaderID);
				parametersUpdate.remove(paramShaderID);
				shaderGraph.checkParameterIndex();
				parametersList.find("#param_" + paramShaderID).remove();
			}
		}

		exec(false);
		undo.change(Custom(exec));
	}

	function moveParameter(parameter : Parameter, up : Bool) {
		var parameterElt = parametersList.find("#param_" + parameter.id);
		var parameterPrev = shaderGraph.parametersAvailable.get(shaderGraph.parametersKeys[shaderGraph.parametersKeys.indexOf(parameter.id) + (up? -1 : 1)]);
		execMoveParameterTo(parameter, parameterPrev, !up);
	}

	function updateParam(id : Int) {
		meshPreviewScene.setCurrent(); // needed for texture changes

		var param = shaderGraph.getParameter(id);
		var init = compiledShader.inits.find((i) -> i.variable.name == param.name);
		if (init != null) {
			setParamValue(meshPreviewShader, init.variable, param.defaultValue);
		}
	}

	var parametersUpdate : Map<Int, (Dynamic) -> Void> = [];

	function addParameter(parameter : Parameter, ?value : Dynamic) {

		var elt = new Element('<div id="param_${parameter.id}" class="parameter" draggable="true" ></div>').appendTo(parametersList);
		elt.on("click", function(e) {e.stopPropagation();});
		elt.on("contextmenu", function(e) {
			var elements = [];
			e.stopPropagation();
			var newCtxMenu : Array<hide.comp.ContextMenu.ContextMenuItem> = [
				{ label : "Move up", click : () -> {
					//beforeChange();
					moveParameter(parameter, true);
					//afterChange();
				}, enabled: shaderGraph.parametersKeys.indexOf(parameter.id) > 0},
				{ label : "Move down", click : () -> {
					//beforeChange();
					moveParameter(parameter, false);
					//afterChange();
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

				var save : Null<Float> = null;
				rangeInput.on("mousedown", function(e) {
					elt.attr("draggable", "false");
					//beforeChange();
				});
				rangeInput.on("mouseup", function(e) {
					elt.attr("draggable", "true");
					//afterChange();
				});
				if (value == null) value = 0;
				range.value = value;

				parametersUpdate.set(parameter.id, (v:Dynamic) -> range.value = v);
				shaderGraph.setParameterDefaultValue(parameter.id, value);

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
							shaderGraph.setParameterDefaultValue(parameter.id, v);
							parametersUpdate[parameter.id](v);
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
				typeName = "Number";
			case TVec(4, VFloat):
				var parentPicker = new Element('<div style="width: 35px; height: 25px; display: inline-block;"></div>').appendTo(defaultValue);
				var picker = new hide.comp.ColorPicker.ColorBox(null, parentPicker, true, true);


				if (value == null)
					value = [0, 0, 0, 1];
				var start : h3d.Vector = h3d.Vector.fromArray(value);
				shaderGraph.setParameterDefaultValue(parameter.id, value);
				picker.value = start.toColor();

				parametersUpdate.set(parameter.id, (v:Dynamic) -> picker.value = v.toColor());

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
							parametersUpdate[parameter.id](v);
							shaderGraph.setParameterDefaultValue(parameter.id, [v.x, v.y, v.z, v.w]);
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
				typeName = "Color";
			case TVec(n, VFloat):
				if (value == null)
					value = [for (i in 0...n) 0.0];

				shaderGraph.setParameterDefaultValue(parameter.id, value);

				//var row = new Element('<div class="flex"/>').appendTo(defaultValue);

				var ranges : Array<hide.comp.Range> = [];

				var saveValue : Array<Float> = null;

				for( i in 0...n ) {
					var parentRange = new Element('<input type="range" min="-1" max="1" />').appendTo(defaultValue);
					var range = new hide.comp.Range(null, parentRange);
					ranges.push(range);
					range.value = value[i];

					var rangeInput = @:privateAccess range.f;
					rangeInput.on("mousedown", function(e) {
						elt.attr("draggable", "false");
						//beforeChange();
					});
					rangeInput.on("mouseup", function(e) {
						elt.attr("draggable", "true");
						//afterChange();
					});

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
								shaderGraph.setParameterDefaultValue(parameter.id, v);
								parametersUpdate[parameter.id](v);
								updateParam(parameter.id);
							}
							exec(false);
							undo.change(Custom(exec));
							return;
						}

						value[i] = range.value;
						if (!shaderGraph.setParameterDefaultValue(parameter.id, value))
							return;
						//setBoxesParam(parameter.id);
						updateParam(parameter.id);
					};
					//if(min == null) min = isColor ? 0.0 : -1.0;
					//if(max == null)	max = 1.0;
					//e.attr("min", "" + min);
					//e.attr("max", "" + max);
				}
				parametersUpdate.set(parameter.id, (v:Dynamic) -> {
					for (i in 0...n) {
						ranges[i].value = v[i];
					}
				});

				typeName = "Vec" + n;
			case TSampler(_):
				var parentSampler = new Element('<input type="texturepath" field="sampler2d"/>').appendTo(defaultValue);

				var tselect = new hide.comp.TextureChoice(null, parentSampler);
				parametersUpdate.set(parameter.id, (v:Dynamic) -> tselect.value = v);
				var saveValue : String = null;
				tselect.value = value;
				tselect.onChange = function(notTmpChange: Bool) {
					if (saveValue == null) {
						saveValue = haxe.Json.stringify(shaderGraph.parametersAvailable.get(parameter.id).defaultValue);
					}
					var currentValue = haxe.Json.parse(haxe.Json.stringify(tselect.value));
					if (notTmpChange) {
						var prev = haxe.Json.parse(saveValue);
						saveValue = null;
						var curr = currentValue;
						function exec(isUndo: Bool) {
							var v = !isUndo ? curr : prev;
							shaderGraph.setParameterDefaultValue(parameter.id, v);
							parametersUpdate[parameter.id](v);
							updateParam(parameter.id);
						}
						exec(false);
						this.undo.change(Custom(exec));
						return;
					}
					if (!shaderGraph.setParameterDefaultValue(parameter.id, currentValue))
						return;
					//setBoxesParam(parameter.id);
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
			//beforeChange();
			parameter.internal = internal.prop("checked");
			//afterChange();
		});

		var perInstanceCb = new Element('<div><input type="checkbox" name="perinstance"/><label for="perinstance">Per instance</label><div>');
		var shaderParams : Array<ShaderParam> = [];
		// for (b in listOfBoxes) {
		// 	var tmpShaderParam = Std.downcast(b.getInstance(), ShaderParam);
		// 	if (tmpShaderParam != null && tmpShaderParam.parameterId == parameter.id) {
		// 		shaderParams.push(tmpShaderParam);
		// 		break;
		// 	}
		// }

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

		header.appendTo(elt);
		content.appendTo(elt);
		var actionBtns = new Element('<div class="action-btns" ></div>').appendTo(content);
		var deleteBtn = new Element('<input type="button" value="Delete" />');
		deleteBtn.on("click", function() {
			@:privateAccess
			for (graph in shaderGraph.graphs) {
				for (node in graph.getNodes()) {
					var shaderParam = Std.downcast(node, ShaderParam);
					if (shaderParam != null && shaderParam.parameterId == parameter.id) {
						Ide.inst.quickError("This parameter is used in the graph.");
						return;
					}
				}
			}

			function exec(isUndo : Bool) {
				if (!isUndo) {
					shaderGraph.parametersAvailable.remove(parameter.id);
					shaderGraph.parametersKeys.remove(parameter.id);
					parametersUpdate.remove(parameter.id);
					shaderGraph.checkParameterIndex();
					elt.remove();
				} else {
					shaderGraph.parametersAvailable.set(parameter.id, parameter);
					shaderGraph.parametersKeys.insert(parameter.index, parameter.id);
					shaderGraph.checkParameterIndex();

					updateParam(parameter.id);
					addParameter(parameter, parameter.defaultValue);

					for (id in shaderGraph.parametersKeys) {
						var newElt = parametersList.find("#param_" + id);
						parametersList.append(newElt);
					}
				}
			}
			exec(false);
			undo.change(Custom(exec));
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
			// if (shaderGraph.setParameterTitle(parameter.id, newName)) {
			// 	for (b in listOfBoxes) {
			// 		var shaderParam = Std.downcast(b.getInstance(), ShaderParam);
			// 		if (shaderParam != null && shaderParam.parameterId == parameter.id) {
			// 			beforeChange();
			// 			shaderParam.setName(newName);
			// 			afterChange();
			// 		}
			// 	}
			// }
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
			execMoveParameterTo(other, parameter, after);
		});

		return elt;
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

	function execMoveParameterTo(paramA: Parameter, paramB: Parameter, after: Bool) {
		var oldIndex = paramA.index;
		var newIndex = paramB.index;
		var delta = newIndex - oldIndex;
		if (delta == 0)
			return;

		if (after && delta < 0)
			delta += 1;
		if (!after && delta > 0)
			delta -= 1;

		function exec(isUndo: Bool) {
			moveParameterOffset(paramA, isUndo ? -delta : delta);
		}
		exec(false);
		undo.change(Custom(exec));
	}

	function moveParameterOffset(paramA: Parameter, offset: Int) {
		var current = paramA.index;
		var end = current + offset;
		var dir = offset > 0 ? 1 : -1;
		while(current != end) {
			var next = current + dir;
			var tmp = shaderGraph.parametersKeys[current];
			shaderGraph.parametersKeys[current] = shaderGraph.parametersKeys[next];
			shaderGraph.parametersKeys[next] = tmp;
			current = next;
		}

		shaderGraph.checkParameterIndex();

		for (id in shaderGraph.parametersKeys) {
			var elt = parametersList.find("#param_" + id);
			parametersList.append(elt);
		}
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
	}

	public function saveSettings() {
		saveDisplayState("previewSettings", haxe.Json.stringify(previewSettings));
	}

	public function initMeshPreview() {
		if (meshPreviewScene != null) {
			meshPreviewScene.element.remove();
		}
		var container = new Element('<div id="preview"></div>').appendTo(graphEditor.element);
		meshPreviewScene = new hide.comp.Scene(config, null, container);
		meshPreviewScene.onReady = onMeshPreviewReady;
		meshPreviewScene.onUpdate = onMeshPreviewUpdate;

		var toolbar = new Element('<div class="hide-toolbar2"></div>').appendTo(container);
		var group = new Element('<div class="tb-group"></div>').appendTo(toolbar);
		var menu = new Element('<div class="button2 transparent" title="More options"><div class="ico ico-navicon"></div></div>');
		menu.appendTo(group);
		menu.click((e) -> {
			var menu = new hide.comp.ContextMenu([
				{label: "Reset Camera", click: resetPreviewCamera},
				{label: "", isSeparator: true},
				{label: "Sphere", click: setMeshPreviewSphere},
				{label: "Plane", click: setMeshPreviewPlane},
				{label: "Mesh ...", click: chooseMeshPreviewFBX},
				{label: "Prefab/FX ...", click: chooseMeshPreviewPrefab},
				{label: "", isSeparator: true},
				{label: "Material Settings", menu: [
					{label: "Alpha Blend", click: () -> {previewSettings.alphaBlend = !previewSettings.alphaBlend; meshPreviewShader = null; saveSettings();}, stayOpen: true, checked: previewSettings.alphaBlend},
					{label: "Backface Cull", click: () -> {previewSettings.backfaceCulling = !previewSettings.backfaceCulling; meshPreviewShader = null; saveSettings();}, stayOpen: true, checked: previewSettings.backfaceCulling},
					{label: "Unlit", click: () -> {previewSettings.unlit = !previewSettings.unlit; meshPreviewShader = null; saveSettings();}, stayOpen: true, checked: previewSettings.unlit},
				], enabled: meshPreviewPrefab == null},
				{label: "Render Settings", menu: [
					{label: "Background Color", click: openBackgroundColorMenu},
					{label: "Render Props", click: selectRenderProps},
				]}
			]);
		});
	}

	public function selectRenderProps() {
		var basedir = haxe.io.Path.directory(previewSettings.renderPropsPath ?? "");
		if (basedir == "" || !haxe.io.Path.isAbsolute(basedir)) {
			haxe.io.Path.join([Ide.inst.resourceDir, basedir]);
		}

		Ide.inst.chooseFile(["prefab"], (path) -> {
			previewSettings.renderPropsPath = path;
			refreshRenderProps();
			saveSettings();
		}, true, basedir);
	}

	public function openBackgroundColorMenu() {
		var prev = element.find("#preview");

		var cp = new hide.comp.ColorPicker(false, null,element.find("#preview"));
		@:privateAccess
		{
			var offset = cp.popup.offset();
			offset.top -= prev.get(0).offsetHeight;
			cp.popup.offset(offset);
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
					saveSettings();
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
		}
		meshPreviewScene.engine.backgroundColor = previewSettings.bgColor;
	}

	public function refreshRenderProps() {
		if (meshPreviewRenderProps != null) {
			meshPreviewRenderProps.dispose();
		}

		if (meshPreviewRenderPropsRoot != null) {
			meshPreviewRenderPropsRoot.remove();
		}
		meshPreviewRenderPropsRoot = new h3d.scene.Object(meshPreviewScene.s3d);
		if (previewSettings.renderPropsPath == null)
			return;
		try {
			meshPreviewRenderProps = Ide.inst.loadPrefab(previewSettings.renderPropsPath);
		} catch(e) {
			return;
		}
		var ctx = new hide.prefab.ContextShared(null, meshPreviewRenderPropsRoot);
		ctx.scene = meshPreviewScene;
		meshPreviewRenderProps.setSharedRec(ctx);
		meshPreviewRenderProps.make();
		var renderProps = meshPreviewRenderProps.getOpt(hrt.prefab.RenderProps);
		if (renderProps != null)
			renderProps.applyProps(meshPreviewScene.s3d.renderer);
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
		saveSettings();

		var sp = new h3d.prim.Sphere(1, 128, 128);
		sp.addNormals();
		sp.addUVs();
		sp.addTangents();
		setMeshPreviewMesh(new h3d.scene.Mesh(sp));
	}

	public function setMeshPreviewPlane() {
		previewSettings.meshPath = "Plane";
		saveSettings();

		var plane = hrt.prefab.l3d.Polygon.createPrimitive(Quad(4));
		var m = new h3d.scene.Mesh(plane);
		m.setScale(2.0);
		m.material.mainPass.culling = None;
		m.z += 0.001;
		setMeshPreviewMesh(m);
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
		var bounds = new h3d.col.Bounds();
		for (mesh in meshPreviewMeshes) {
			var b = mesh.getBounds();
			bounds.add(b);
		}
		var sp = bounds.toSphere();
		meshPreviewCameraController.set(sp.r * 3.0, Math.PI / 4, Math.PI * 5 / 13, sp.getCenter());
	}

	public function loadMeshPreviewFromString(str: String) {
		switch (str){
			case "Sphere":
				setMeshPreviewSphere();
			case "Plane":
				setMeshPreviewPlane();
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
			model = Std.downcast(meshPreviewScene.loadModel(str, false, true), h3d.scene.Mesh);
		} catch (e) {
			Ide.inst.quickError('Could not load mesh $str, error : $e');
			setMeshPreviewSphere();
			return;
		}

		setMeshPreviewMesh(model);
		previewSettings.meshPath = str;
		saveSettings();
	}

	public function setMeshPreviewPrefab(str: String) {
		cleanupPreview();

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

		if (meshPreviewMeshes.length <= 0) {
			Ide.inst.quickError('Prefab/FX $str does not contains this shadergraph');
			setMeshPreviewSphere();
			return;
		}

		meshPreviewprefabWatch = Ide.inst.fileWatcher.register(str, () -> queueReloadMesh = true, false);

		meshPreviewShader = null;
		resetPreviewCamera();
		previewSettings.meshPath = str;
		saveSettings();
	}

	public function onMeshPreviewReady() {
		if (meshPreviewScene.s3d == null)
			throw "meshPreviewScene not ready";

		var moved = false;
		meshPreviewCameraController = new PreviewCamController(meshPreviewScene.s3d);
		meshPreviewRoot3d = new h3d.scene.Object(meshPreviewScene.s3d);
		loadMeshPreviewFromString(previewSettings.meshPath);
		refreshRenderProps();
	}

	public function replaceMeshShader(mesh: h3d.scene.Mesh, newShader: hxsl.DynamicShader) {
		if (newShader == null)
			return;

		@:privateAccess
		for (m in mesh.getMaterials()) {
			var found = false;

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
					if (previewSettings.unlit) {
						m.mainPass.setPassName("afterTonemapping");
						m.shadows = false;
					}
					else {
						m.mainPass.setPassName("default");
						m.shadows = true;
					}
				}

				curShaderList = curShaderList.next;
			}

			if (!found) {
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
		}

		@:privateAccess
		if (meshPreviewScene.s3d != null) {
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
				setParamValue(shader, previewVar, node.getId() + 1);
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
		var node = ShaderNode.createFromDynamic(data, shaderGraph);
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

	public function getAddNodesMenu() : Array<AddNodeMenuEntry> {
		var entries : Array<AddNodeMenuEntry> = [];

		var id = 0;
		for (i => node in ShaderNode.registeredNodes) {
			var metas = haxe.rtti.Meta.getType(node);
			if (metas.group == null) {
				continue;
			}

			var group = metas.group != null ? metas.group[0] : "Other";
			var name = metas.name != null ? metas.name[0] : "unknown";
			var description = metas.description != null ? metas.description[0] : "";

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

			var aliases = std.Type.createEmptyInstance(node).getAliases(name, group, description) ?? [];
			for (alias in aliases) {
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
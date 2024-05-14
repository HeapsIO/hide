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

class PreviewShaderBase extends hxsl.Shader {
	static var SRC = {

		@input var input : {
			var position : Vec2;
		};

		@global var global : {
			var time : Float;
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
	public var alphaBlend: Bool = false;
	public var backfaceCulling : Bool = true;
	public var unlit : Bool = false;
	public function new() {};
}
class ShaderEditor extends hide.view.FileView implements GraphInterface.IGraphEditor {
	var graphEditor : hide.view.GraphEditor;
	var shaderGraph : hrt.shgraph.ShaderGraph;
	var currentGraph : hrt.shgraph.ShaderGraph.Graph;

	var compiledShader : hrt.prefab.Cache.ShaderDef;
	var previewShaderBase : PreviewShaderBase;
	var previewVar : hxsl.Ast.TVar;
	var needRecompile : Bool = true;

	var meshPreviewScene : hide.comp.Scene;
	var meshPreviewMeshes : Array<h3d.scene.Mesh> = [];
	var meshPreviewRoot3d : h3d.scene.Object;
	var meshShader : hxsl.DynamicShader;
	var meshPreviewCameraController : h3d.scene.CameraController;
	var previewSettings : PreviewSettings;
	var meshPreviewPrefab : hrt.prefab.Prefab;
	var meshPreviewprefabWatch : hide.tools.FileWatcher.FileWatchEvent;

	var defaultLight : hrt.prefab.Light;

	var queueReloadMesh = false;
	
	override function onDisplay() {
		super.onDisplay();
		loadSettings();
		element.addClass("shader-editor");
 		shaderGraph = cast hide.Ide.inst.loadPrefab(state.path, null,  true);
		currentGraph = shaderGraph.getGraph(Fragment);
		previewShaderBase = new PreviewShaderBase();

		if (graphEditor != null)
			graphEditor.remove();
		graphEditor = new hide.view.GraphEditor(config, this, this.element);
		graphEditor.onDisplay();

		graphEditor.onPreviewUpdate = onPreviewUpdate;
		graphEditor.onNodePreviewUpdate = onNodePreviewUpdate;

		initMeshPreview();
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
		var container = new Element('<div id="preview"></div>').appendTo(element);
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
				{label: "Render Settings", menu: [
					{label: "Alpha Blend", click: () -> {previewSettings.alphaBlend = !previewSettings.alphaBlend; applyShaderMesh(); saveSettings();}, stayOpen: true, checked: previewSettings.alphaBlend},
					{label: "Backface Cull", click: () -> {previewSettings.backfaceCulling = !previewSettings.backfaceCulling; applyShaderMesh(); saveSettings();}, stayOpen: true, checked: previewSettings.backfaceCulling},
					{label: "Unlit", click: () -> {previewSettings.unlit = !previewSettings.unlit; applyShaderMesh(); saveSettings();}, stayOpen: true, checked: previewSettings.unlit},
				], enabled: meshPreviewPrefab == null}
			]);
		});
	}

	public function onMeshPreviewUpdate(dt: Float) {
		if (queueReloadMesh) {
			queueReloadMesh = false;
			loadMeshPreviewFromString(previewSettings.meshPath);
		}
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

		applyShaderMesh();
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
		setMeshPreviewMesh(m);
	}

	public function chooseMeshPreviewFBX() {
		var basedir = haxe.io.Path.directory(previewSettings.meshPath);
		if (basedir == "" || !haxe.io.Path.isAbsolute(basedir)) {
			haxe.io.Path.join([Ide.inst.resourceDir, basedir]);
		}
		trace(basedir);
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
		trace(basedir);
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


		meshPreviewPrefab.setSharedRec(new hide.prefab.ContextShared(null, meshPreviewRoot3d));
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

		applyShaderMesh();
		resetPreviewCamera();
		previewSettings.meshPath = str;
		saveSettings();
	}

	public function onMeshPreviewReady() {
		if (meshPreviewScene.s3d == null)
			throw "meshPreviewScene not ready";

		var moved = false;
		meshPreviewCameraController = new h3d.scene.CameraController(meshPreviewScene.s3d);
		meshPreviewCameraController.loadFromCamera(false);
		meshPreviewRoot3d = new h3d.scene.Object(meshPreviewScene.s3d);
		loadMeshPreviewFromString(previewSettings.meshPath);
	}

	public function replaceMeshShader(mesh: h3d.scene.Mesh, newShader: hxsl.DynamicShader) {
		for (m in mesh.getMaterials()) {
			var found = false;

			for (shader in m.mainPass.getShaders()) {
				var dyn = Std.downcast(shader, hxsl.DynamicShader);
				
				@:privateAccess
				if (dyn != null) {
					if (dyn.shader.data.name == newShader.shader.data.name) {
						found = true;
						dyn.shader = newShader.shader;
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
			}
			if (!found) {
				m.mainPass.addShader(newShader);
			}
		}
	}

	public function applyShaderMesh() {
		for (m in meshPreviewMeshes) {
			replaceMeshShader(m, meshShader);
		}
	}


	public function onPreviewUpdate() {
		if (needRecompile) {
			compileShader();
		}

		@:privateAccess
		if (meshPreviewScene.s3d != null) {
			meshPreviewScene.s3d.renderer.ctx.time = graphEditor.previewsScene.s3d.renderer.ctx.time;
		}

		return true;
	}
	var bitmapToShader : Map<h2d.Bitmap, hxsl.DynamicShader> = [];
	public function onNodePreviewUpdate(node: IGraphNode, bitmap: h2d.Bitmap) {
		if (compiledShader == null) {
			bitmap.visible = false;
			return;
		}
		var shader = bitmapToShader.get(bitmap);
		if (shader == null) {
			for (s in bitmap.getShaders()) {
				bitmap.removeShader(s);
			}
			shader = new DynamicShader(compiledShader.shader);
			bitmapToShader.set(bitmap, shader);
			bitmap.addShader(previewShaderBase);
			bitmap.addShader(shader);
		}
		setParamValue(shader, previewVar, node.getId() + 1);
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

	public function compileShader() {
		needRecompile = false;
		try {
			var start = Timer.stamp();
			compiledShader = shaderGraph.compile(Fragment);
			bitmapToShader.clear();
			previewVar = compiledShader.inits.find((e) -> e.variable.name == hrt.shgraph.Variables.previewSelectName).variable;
			var end = Timer.stamp();
			Ide.inst.quickMessage('shader recompiled in ${(end - start) * 1000.0} ms', 2.0);

			meshShader = new hxsl.DynamicShader(compiledShader.shader);
			applyShaderMesh();
		} catch (err) {
			Ide.inst.quickError(err);
		}
	}
	
	static var _ = FileTree.registerExtension(ShaderEditor,["shgraph"],{ icon : "scribd", createNew: "Shader Graph" });
}
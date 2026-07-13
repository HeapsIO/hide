package hide.view;
import hrt.ui.*;

#if hui
enum abstract CollisionMode(Int) from Int to Int {
	var Default = 0;
	var None    = 1;
	var Auto    = 2;
	var Mesh    = 3;
	var Shapes  = 4;
	var Count   = 5;

	public function toString() {
		return switch (this) {
			case Default: "Default";
			case None: "None";
			case Auto: "Auto";
			case Mesh: "Mesh";
			case Shapes: "Shapes";
			default: "Undefined";
		}
	}
}

class CollisionSettings {
	public var mode : Int;
	public var params : hxd.fmt.fbx.HMDOut.CollideParams;

	public function new( mode : Int, params : hxd.fmt.fbx.HMDOut.CollideParams ) {
		this.mode = mode;
		this.params = params;
	}

	public function getDebugCollider(mesh : h3d.scene.Mesh, convertRule : hxd.fs.FileConverter.ConvertRule) : h3d.scene.Object {
		var hmd = Std.downcast(mesh.primitive, h3d.prim.HMDModel);
		if (hmd == null)
			return null;
		var model : hxd.fmt.hmd.Data.Model = null;
		if (params != null) {
			for (m in hmd.lib.header.models)
				if (m.getObjectName() == params.mesh || m.getObjectName() == mesh.name)
					model = m;
		}

		if (model == null)
			return null;

		var defaultParams : hxd.fmt.fbx.HMDOut.CollideParams = null;
		#if ((sys || nodejs) && !macro)
		var fs : hxd.fs.LocalFileSystem = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		if (fs != null) {
			var convertRule = @:privateAccess fs.convert.getConvertRule(hmd.lib.resource.entry.path);
			var collide = convertRule.cmd?.params?.collide;
			if (collide != null) {
				defaultParams = {
					precision : collide.precision,
					maxConvexHulls : collide.maxConvexHulls,
					maxSubdiv : collide.maxSubdiv,
				};
			}
		}
		#end

		var collisionThresholdHeight = Reflect.field(convertRule.cmd.params, "collisionThresholdHeight");
		var collisionUseLowLod = Reflect.field(convertRule.cmd.params, "collisionUseLowLod");
		var noCollision = Reflect.field(convertRule.cmd.params, "noCollision");
		var isDefaultParams = params == null || (params != null && params.useDefault);
		var params = isDefaultParams ? defaultParams : params;
		var colliderType = hxd.fmt.hmd.Data.Collider.resolveColliderType(hmd.lib.header, model, params, isDefaultParams, collisionThresholdHeight, collisionUseLowLod, noCollision);
		if (colliderType == null)
			return null;

		return switch (colliderType) {
			case Mesh(colliderModel):
				var g = hmd.lib.header.geometries[colliderModel.geometry];
				var buffers = hmd.lib.getBuffers(g, hxd.BufferFormat.POS3D);
				var polygonBuffer = new h3d.col.PolygonBuffer();
				polygonBuffer.setData(buffers.vertexes, buffers.indexes);
				var obj = polygonBuffer.makeDebugObj();
				obj.defaultTransform = colliderModel.position.toMatrix();
				if (colliderModel.skin != null)
					obj.defaultTransform.multiply(obj.defaultTransform, colliderModel.skin.joints[0].position.toMatrix());
				obj.defaultTransform.multiply(obj.defaultTransform, model.position.toMatrix().getInverse());
				return obj;

			case ConvexHulls(colliderModel):
				var hmd = Std.downcast(mesh.primitive, h3d.prim.HMDModel);

				var dim = hmd.getBounds().dimension();
				var prec = hxd.Math.min(dim, params.precision);
				var subdiv = hxd.Math.ceil(dim / prec);
				subdiv = hxd.Math.imin(subdiv, params.maxSubdiv);
				var p = { maxConvexHulls: params.maxConvexHulls, maxResolution: subdiv * subdiv * subdiv };

				var vertices : Array<Float> = [];
				var indexes : Array<Int> = [];
				for (idx => m in mesh.getMaterials()) {
					if (Reflect.field(m.props, "ignoreCollide"))
						continue;

					var bufs = hmd.lib.getBuffers(hmd.lib.header.geometries[colliderModel.geometry], hxd.BufferFormat.POS3D, null, idx);
					for (v in bufs.vertexes)
						vertices.push(v);
					for (i in bufs.indexes)
						indexes.push(i);
				}

				var convexHulls = hxd.fmt.hmd.Data.ConvexHullsCollider.buildConvexHulls(vertices, indexes, p);
				if (convexHulls == null)
					return null;

				var parentObj = new h3d.scene.Object();
				for (convexHull in convexHulls) {
					var polygonBuffer = new h3d.col.PolygonBuffer();
					var vbuf = new haxe.ds.Vector<hxd.impl.Float32>(convexHull.vertices.length);
					for (vIdx => v in convexHull.vertices)
						vbuf[vIdx] = v;
					var ibuf = new haxe.ds.Vector<Int>(convexHull.indexes.length);
					for (i => idx in convexHull.indexes)
						ibuf[i] = idx;
					polygonBuffer.setData(vbuf, ibuf, true);
					var obj = polygonBuffer.makeDebugObj();
					obj.defaultTransform = colliderModel.position.toMatrix();
					if (colliderModel.skin != null)
						obj.defaultTransform.multiply(obj.defaultTransform, colliderModel.skin.joints[0].position.toMatrix());
					parentObj.addChild(obj);
				}

				parentObj.defaultTransform = model.position.toMatrix().getInverse();
				return parentObj;

			case Shapes:
				var root = new h3d.scene.Object();
				for (s in toShapeEditor())
					hrt.ui.HuiShapeEditor.getInteractive(s, false, root);

				return root;

			default:
				null;
		}
	}

	public function toShapeEditor() {
		if (params == null || mode != Shapes || params.shapes == null)
			return [];
		var arr : Array<hrt.ui.HuiShapeEditor.Shape> = [];
		inline function makeVector(dyn) {
			return new h3d.Vector(dyn.x, dyn.y, dyn.z);
		}
		for (s in params.shapes) {
			var position = makeVector(s.position);
			switch( s.type ) {
			case Sphere:
				arr.push(Sphere(position, s.radius));
			case Box:
				var halfExtent = makeVector(s.halfExtent);
				var rotation = makeVector(s.rotation);
				arr.push(Box(position, rotation, halfExtent.x * 2, halfExtent.y * 2, halfExtent.z * 2));
			case Capsule:
				var halfExtent = makeVector(s.halfExtent);
				var qrot = new h3d.Quat();
				qrot.initMoveTo(new h3d.Vector(0.0, 0.0, 1.0), halfExtent.normalized());
				arr.push(Capsule(position, qrot.toEuler(), s.radius, halfExtent.length() * 2));
			case Cylinder:
				var halfExtent = makeVector(s.halfExtent);
				var qrot = new h3d.Quat();
				qrot.initMoveTo(new h3d.Vector(0.0, 0.0, 1.0), halfExtent.normalized());
				arr.push(Cylinder(position, qrot.toEuler(), s.radius, halfExtent.length() * 2));
			default:
				Ide.showError("Don't know how to handle shape type " + s.type);
			}
		}
		return arr;
	}

	public function fromShapeEditor(arr : Array<hrt.ui.HuiShapeEditor.Shape>) {
		var shapes : Array<hxd.fmt.fbx.HMDOut.ShapeColliderParams> = [];
		for( s in arr ) {
			switch(s) {
			case Sphere(center, radius):
				shapes.push({ type : Sphere, position : center, radius : radius });
			case Box(center, rotation, sizeX, sizeY, sizeZ):
				var halfExtent = new h3d.Vector(sizeX * 0.5, sizeY * 0.5, sizeZ * 0.5);
				shapes.push({ type : Box, position : center, rotation : rotation, halfExtent: halfExtent });
			case Capsule(center, rotation, radius, height):
				var rmat = h3d.Matrix.R(rotation.x, rotation.y, rotation.z);
				var halfExtent = new h3d.Vector(0.0, 0.0, 1.0);
				halfExtent.transform3x3(rmat);
				halfExtent.normalize();
				halfExtent.scale(height * 0.5);
				shapes.push({ type : Capsule, position: center, halfExtent : halfExtent, radius : radius });
			case Cylinder(center, rotation, radius, height):
				var rmat = h3d.Matrix.R(rotation.x, rotation.y, rotation.z);
				var halfExtent = new h3d.Vector(0.0, 0.0, 1.0);
				halfExtent.transform3x3(rmat);
				halfExtent.normalize();
				halfExtent.scale(height * 0.5);
				shapes.push({ type : Cylinder, position: center, halfExtent : halfExtent, radius : radius });
			}
		}
		return shapes;
	}
}

@:access(hrt.ui.HuiSceneEditor)
class Model extends HuiView<{path: String}> {
	static var SRC =
		<model>
			<hui-scene-editor id="scene-editor"/>
		</model>

	static var _ = HuiView.register("model", Model);

	var obj : h3d.scene.Object;
	var selectedObjects: Array<Dynamic> = [];
	var collisionSettings : Map<String, CollisionSettings>;
	var materialSettings : Map<String, Dynamic>;

	var modelInspector : hrt.ui.HuiModelInspector;
	var materialInspector : hrt.ui.HuiMaterialInspector;

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		var path = Ide.inst.getRelPath(state.path);
		sceneEditor.load = () -> load(path);
		sceneEditor.onScenePush = (e) -> {
			if (e.button == 0)
				setSelection(sceneEditor.getObjectsAt(cast e.relX, cast e.relY, obj, (o) -> Std.isOfType(o, h3d.scene.Mesh)));
		}
		sceneEditor.setColliderDebugVisibility = setColliderDebugVisibility;

		undo.onAfterChange = () -> {
			hasUnsavedChanges = undo.isDirty();
		}

		registerCommand(HuiCommands.save, FocusedView, () -> { save();});

		buildToolbar();

		sceneEditor.load();
		sceneEditor.tree.getItemChildren = (item: Dynamic) -> {
			if (item == null)
				return obj.name == null ? @:privateAccess obj.children : [obj];

			var skin = Std.downcast(item, h3d.scene.Skin);
			var obj = Std.downcast(item, h3d.scene.Object);
			var join = Std.downcast(item, h3d.scene.Skin.Joint);
			var children : Array<Dynamic> = [];

			if (obj != null && @:privateAccess obj.children != null) {
				for (c in @:privateAccess obj.children)
					if (!Std.isOfType(c, h3d.scene.Graphics))
						children.push(c);
			}

			if (skin != null) {
				var joints = skin.getSkinData().rootJoints;
				for (j in joints)
					children.push(skin.getObjectByName(j.name));
			}

			if (obj != null) {
				var mats = item.getMaterials(null, false);
				children = children.concat(mats);
			}

			if (join != null) {
				var sObj : h3d.scene.Object = join;
				while (!Std.isOfType(sObj, h3d.scene.Skin))
					sObj = sObj.parent;
				var skin : h3d.scene.Skin = cast sObj;
				for (j in @:privateAccess skin.getSkinData().allJoints[join.index].subs)
					children.push(skin.getObjectByName(j.name));
			}

			return children;
		};
		sceneEditor.tree.getItemName = (item: Dynamic) -> {
			var obj = Std.downcast(item, h3d.scene.Object);
			if (obj != null) return obj.name;

			var mat = Std.downcast(item, h3d.mat.Material);
			if (mat != null) return mat.name;

			var join = Std.downcast(item, h3d.scene.Skin.Joint);
			if (join != null) return join.name;

			return "";
		};
		sceneEditor.tree.getItemIcon = (item : Dynamic) -> {
			if (Std.isOfType(item, h3d.scene.Object))
				return HuiRes.ui.icons.cube;
			if (Std.isOfType(item, h3d.mat.Material))
				return HuiRes.ui.icons.material;
			if (Std.isOfType(item, h3d.scene.Skin.Joint))
				return HuiRes.ui.icons.bone;
			return HuiRes.ui.icons.file_blank;
		}
		sceneEditor.tree.getIdentifier = (item: Dynamic) -> {
			var o = Std.downcast(item, h3d.scene.Object);
			if (o == null) return item.name;
			var path = o.name;
			var parent = o.parent;
			while (parent != null) {
				path = '${parent.name}/${path}';
				parent = parent.parent;
			}
			return path;
		};
		sceneEditor.tree.onUserSelectionChanged = () -> {
			setSelection(cast sceneEditor.tree.getSelectedItems());
		}
		sceneEditor.tree.onItemDoubleClick = (_, el) -> {
			var obj = Std.downcast(el, h3d.scene.Object);
			if (obj != null)
				sceneEditor.focusObjects([obj]);
		};

		sceneEditor.tree.revealAll();

		// Load collision settings
		collisionSettings = [];
		for (o in obj.getMeshes()) {
			var mesh = Std.downcast(obj, h3d.scene.Mesh);
			var hmd = Std.downcast(mesh?.primitive, h3d.prim.HMDModel);
			if (hmd == null) continue;

			var dirPath = @:privateAccess hmd.lib.resource.entry.directory;
			var resName = @:privateAccess hmd.lib.resource.name;
			var props = @:privateAccess h3d.prim.ModelDatabase.current.getModelData(dirPath, resName, obj.name);
			var settings = new CollisionSettings(Default, { useDefault : true });
			if (props != null && Reflect.hasField(props, h3d.prim.ModelDatabase.COLLIDE_CONFIG)) {
				var collideFields = Reflect.field(props, h3d.prim.ModelDatabase.COLLIDE_CONFIG);
				if (collideFields == null)
					settings = new CollisionSettings(None, null);
				else if(collideFields != null && Std.isOfType(collideFields, Array) ) {
					for (cf in (collideFields:Array<Dynamic>)) {
						var mode = Default;
						if (cf == null)
							mode = None;
						else if (Reflect.field(cf, "useDefault"))
							mode = Default;
						else if (Reflect.hasField(cf, "precision"))
							mode = Auto;
						else if (Reflect.hasField(cf, "mesh"))
							mode = Mesh;
						else if (Reflect.hasField(cf, "shapes"))
							mode = Shapes;
						settings = new CollisionSettings(mode, cf);
					}
				}
			}

			collisionSettings.set(o.name, settings);
		}

		materialSettings = [];
		for (mat in obj.getMaterials()) {
			var props : Dynamic = h3d.mat.MaterialSetup.current.loadMaterialProps(mat);
			if (props == null)
				continue;
			materialSettings.set(mat.name, props);
		}

		sceneEditor.updateDebugOverlayVisibility();
	}

	override function safeSync(ctx) {
		super.safeSync(ctx);
	}

	override function getContextMenuContent(content: Array<hrt.ui.HuiMenu.MenuItem>) {
		// content.push({label: "Save", click: () -> execCommand(HuiCommands.save)});
		// content.push({label: "Rebuild", click: () -> @:privateAccess prefabEditor.tryMake(prefabEditor.prefab)});
		// content.push({isSeparator: true});
		// content.push({label: "Debug dump", click: () -> {
		// 	var ser = @:privateAccess prefabEditor.prefab.serialize();
		// 	trace(haxe.Json.stringify(ser, "\t"));
		// }});
	}

	override function getViewName():String {
		return state.path.split("/").splice(-1, 2).join("/");
	}

	override function requestClose(cb: (canClose:Bool) -> Void) {
		if (hasUnsavedChanges) {
			uiBase.confirm("Save change before closing ?", Save | DontSave | Cancel, (choice: hrt.ui.HuiConfirmPopup.ConfirmButton) -> {
				switch (choice) {
					case Save:
						execCommand(HuiCommands.save);
						cb(true);
					case DontSave:
						cb(true);
					case Cancel:
						cb(false);
					default:
						throw "???";
				}
			});
		} else {
			cb(true);
		}
	}

	override function getToolbarWidgets() : Array<HuiElement> {
		var widgets : Array<HuiElement> = [];

		var cameraBtn = new HuiButton();
		new HuiIcon("camera", cameraBtn);
		cameraBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiCameraSettingsPopup(sceneEditor), { object: Element(cameraBtn), directionX: StartInside, directionY: EndOutside });
		}
		widgets.push(cameraBtn);

		var helpBtn = new HuiButton();
		helpBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiHelpPopup(this.registeredCommands), { object: Element(helpBtn), directionX: StartInside, directionY: EndOutside });
		};
		new HuiIcon("question_mark", helpBtn);
		widgets.push(helpBtn);

		widgets.push(new hrt.ui.HuiToolbar.HuiVisibilityWidget(sceneEditor));
		widgets.push(new hrt.ui.HuiToolbar.HuiViewModesWidget(sceneEditor.scene.s3d));
		widgets.push(new hrt.ui.HuiToolbar.HuiSceneFiltersWidget(sceneEditor));
		widgets.push(new hrt.ui.HuiToolbar.HuiRenderPropsWidget(sceneEditor));

		return widgets;
	}

	function save() {
		if (!hasUnsavedChanges)
			return;

		undo.markClean();
		hasUnsavedChanges = false;

		// Save model props
		for (o in obj.findAll(o -> Std.downcast(o, h3d.scene.Mesh))) {
			var hmd = Std.downcast(o.primitive, h3d.prim.HMDModel);
			if (hmd == null)
				continue;

			var settings = collisionSettings.get(o.name);
			var collide = {};
			if (settings != null) {
				switch (settings.mode) {
					case Default: collide = {};
					case None: collide = { collide : null };
					case Auto, Mesh, Shapes: collide = { collide : [settings.params] };
					default: throw "Unexpected collision mode";
				}
			}

			var input : h3d.prim.ModelDatabase.ModelDataInput = {
				resourceDirectory : @:privateAccess hmd.lib.resource.entry.directory,
				resourceName : @:privateAccess hmd.lib.resource.name,
				objectName : o.name,
				hmd : hmd,
				skin : o.find((o) -> Std.downcast(o, h3d.scene.Skin)),
				collide : collide
			}

			h3d.prim.ModelDatabase.current.saveModelProps(input);
			var lfs = cast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
			lfs.removePathFromCache(state.path);
			@:privateAccess hxd.res.Loader.currentInstance.cache.remove(state.path);
		}

		// Save model library
		for (mat in obj.getMaterials()) {
			var props = materialSettings.get(mat.name);
			if (props != null ) {
				mat.props = props;
			} else {
				Reflect.deleteField((mat.props:Dynamic), "__ref");
				Reflect.deleteField((mat.props:Dynamic), "name");
				Reflect.deleteField((mat.props:Dynamic), "__refMode");
			}
			h3d.mat.MaterialSetup.current.saveMaterialProps(mat);
		}
	}

	function setSelection(selection: Array<Dynamic>) {
		var oldSelection = selectedObjects.copy();
		if (selection.length == oldSelection.length) {
			var same = true;
			for (p in selection) {
				if (!selectedObjects.contains(p)) {
					same = false;
					break;
				}
			}
			if (same)
				return;
		}

		for (s in selectedObjects) {
			var obj = Std.downcast(s, h3d.scene.Object);
			if (obj == null)
				continue;
			for (m in obj.getMaterials()) {
				var p = m.getPass("highlight");
				if (p == null) continue;
				m.removePass(p);
			}
		}

		selectedObjects = [];

		var objs : Array<h3d.scene.Object> = [];
		for (o in selection) {
			selectedObjects.push(o);
			var obj = Std.downcast(o, h3d.scene.Object);
			if (obj != null) {
				objs.push(obj);
				for (m in obj.getMaterials()) {
					var p = m.allocPass("highlight");
					p.culling = None;
					p.depthWrite = false;
					p.depthTest = Always;
				}
			}
		}

		refreshInspector();
	}

	function refreshInspector() {
		sceneEditor.inspectorPanel.removeChildElements();

		// TODO: manage multi-edit for objects
		if (selectedObjects.length != 1)
			return;

		var el = selectedObjects[0];
		var o = Std.downcast(el, h3d.scene.Object);
		if (o != null)
			modelInspector = new hrt.ui.HuiModelInspector(o, this, sceneEditor.inspectorPanel);

		var m = Std.downcast(el, h3d.mat.Material);
		if (m != null)
			materialInspector = new hrt.ui.HuiMaterialInspector(m, this, sceneEditor.inspectorPanel);
	}

	function setColliderDebugVisibility(visible : Bool) {
		if (visible) {
			if (collisionSettings == null || sceneEditor.scene == null)
				return;

			if (sceneEditor.rootDebugCollider == null) {
				sceneEditor.rootDebugCollider = new h3d.scene.Object(sceneEditor.scene.s3d);
				sceneEditor.rootDebugCollider.name = "rootDebugCollider";
			}

			sceneEditor.rootDebugCollider.removeChildren();

			for (k in collisionSettings.keys()) {
				var obj = obj.getObjectByName(k);
				if (obj == null)
					continue;

				var debugCollider = new h3d.scene.Object(sceneEditor.rootDebugCollider);
				debugCollider.name = 'debug collider (${obj.name})';
				debugCollider.follow = obj;

				var fs : hxd.fs.LocalFileSystem = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
				var convertRule = @:privateAccess fs.convert.getConvertRule(state.path);
				var c = collisionSettings.get(k);
				var debugCreated = false;

				// If user is currently using the shape editor, use the shape editors debug as debug colliders
				var shapeEditor = @:privateAccess modelInspector?.shapeEditor;
				if (shapeEditor != null && shapeEditor.visible == true && c.mode == Shapes) {
					shapeEditor.removeAllInteractives();
					shapeEditor.rootDebugObj = debugCollider;
					shapeEditor.createAllInteractives();
					debugCreated = true;
				}

				if (debugCreated)
					continue;

				var debug = c.getDebugCollider(cast obj, convertRule);
				if (debug == null)
					continue;

				debugCollider.addChild(debug);

				var colliderColor = 0x55FFFFFF;
				var intersectionColor = 0x55FF0000;

				for (m in debug.getMeshes()) {
					m.material.castShadows = false;
					m.material.blendMode = Alpha;
					m.material.name = "$collider";
					m.material.color.setColor(colliderColor);
					m.material.mainPass.setPassName("afterTonemapping");

					var debugWireframe = new h3d.scene.Mesh(m.primitive, null, m);
					debugWireframe.forcedLod = m.forcedLod;
					debugWireframe.name = "debugWireframe";
					debugWireframe.material.name = "$collider";
					debugWireframe.material.mainPass.wireframe = true;
					debugWireframe.material.castShadows = false;
					debugWireframe.material.color.setColor(colliderColor);
					debugWireframe.material.mainPass.setPassName("afterTonemapping");

					var debugIntersection = new h3d.scene.Mesh(m.primitive, null, m);
					debugIntersection.forcedLod = m.forcedLod;
					debugIntersection.name = "debugIntersection";
					debugIntersection.material.name = "$collider";
					debugIntersection.material.castShadows = false;
					debugIntersection.material.blendMode = Alpha;
					debugIntersection.material.mainPass.culling = Front;
					debugIntersection.material.mainPass.depth(false, GreaterEqual);
					debugIntersection.material.color.setColor(intersectionColor);
					debugIntersection.material.mainPass.setPassName("afterTonemapping");
				}
			}
		}
		else if (sceneEditor.rootDebugCollider != null) {
			sceneEditor.rootDebugCollider.remove();
			sceneEditor.rootDebugCollider = null;
		}
	}

	function load(path : String) {
		var lib = hxd.res.Loader.currentInstance.load(path).toModel().toHmd();
		obj = lib.makeObject();
		sceneEditor.scene.s3d.addChild(obj);
	}
}

#end
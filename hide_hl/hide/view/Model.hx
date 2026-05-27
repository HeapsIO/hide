package hide.view;
import hrt.ui.*;

private enum abstract CollisionMode(Int) from Int to Int {
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
}

#if hui
class HuiModelInspector extends HuiElement {
	static var SRC = <hui-model-inspector>
		<hui-category("Info")>
			<hui-element class="horizontal"><hui-text("Objects") class="label"/><hui-text("1") class="value" id="obj-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Meshes") class="label"/><hui-text("1") class="value" id="meshes-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Materials") class="label"/><hui-text("1") class="value" id="mats-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Draws") class="label"/><hui-text("1") class="value" id="draws-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Bones") class="label"/><hui-text("1") class="value" id="bones-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Vertexes") class="label"/><hui-text("1") class="value" id="vertices-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Triangles") class="label"/><hui-text("1") class="value" id="triangles-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Vertex Format") class="label"/><hui-text("1") class="value" id="vertex-format"/></hui-element>
			<hui-element class="horizontal"><hui-text("Collider Vertices") class="label"/><hui-text("1") class="value" id="collider-vertices"/></hui-element>
			<hui-element class="horizontal"><hui-text("Collider Triangle") class="label"/><hui-text("1") class="value" id="collider-triangles"/></hui-element>
			<hui-element class="horizontal"><hui-text("Local Pos") class="label"/><hui-text("1") class="value" id="local-pos"/></hui-element>
			<hui-element class="horizontal"><hui-text("Local Rot") class="label"/><hui-text("1") class="value" id="local-rot"/></hui-element>
			<hui-element class="horizontal"><hui-text("Local Scale") class="label"/><hui-text("1") class="value" id="local-scale"/></hui-element>
			<hui-element class="horizontal"><hui-text("Total Size") class="label"/><hui-text("1") class="value" id="total-size"/></hui-element>
			<hui-element class="horizontal"><hui-text("Mesh Size") class="label"/><hui-text("1") class="value" id="mesh-size"/></hui-element>
		</hui-category>
		<hui-category("Collision")>
			<hui-element class="horizontal"><hui-text("Collision Mode") class="label"/><hui-select class="value" id="collision-mode-el"/></hui-element>
			<hui-element class="horizontal"><hui-text("Precision") class="label"/><hui-input-box class="value" id="precision-el"/></hui-element>
			<hui-element class="horizontal"><hui-text("Max Convex Hulls") class="label"/><hui-input-box class="value" id="max-convex-hulls-el"/></hui-element>
			<hui-element class="horizontal"><hui-text("Max Subdivision") class="label"/><hui-input-box class="value" id="max-subdivision-el"/></hui-element>
			<hui-element class="horizontal"><hui-text("Mesh") class="label"/><hui-select class="value" id="mesh-el"/></hui-element>
			<hui-button class="full"><hui-text("Compute Collider")></hui-text></hui-button>
		</hui-category>
		<hui-category("LODs")>
			<hui-element class="horizontal"><hui-text("LOD Count") class="label"/><hui-text("1") class="value" id="lod-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("LOD Vertices") class="label"/><hui-text("1") class="value" id="lod-vertices-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Force Display LOD") class="label"/><hui-select id="force-display-lod" class="value"></hui-select></hui-element>
			<hui-element class="horizontal"><hui-text("Max LOD") class="label"/><hui-input-box id="max-lod" class="value"></hui-input-box></hui-element>
			<hui-lod-line id="lod-line"></hui-lod-line>
			<hui-button class="full" id="copy-lods"><hui-text("Copy")></hui-text></hui-button>
			<hui-button class="full" id="paste-lods"><hui-text("Paste")></hui-text></hui-button>
			<hui-button class="full" id="reset-lods"><hui-text("Reset Defaults")></hui-text></hui-button>
		</hui-category>
		<hui-category("Material Library")>
		</hui-category>
		<hui-category("Textures")>
		</hui-category>
		<hui-category("Material")>
		</hui-category>
		<hui-category("Dynamic Bones")>
		</hui-category>
		<hui-category("Blend Shapes")>
		</hui-category>
	</hui-model-inspector>

	public function new(obj : h3d.scene.Object, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		updateInfosInspector(obj);
		updateLODsInspector(obj);
		updateCollisionInspector(obj);
	}

	function updateInfosInspector(obj : h3d.scene.Object) {
		var meshes = obj.getMeshes();
		var vertCount = 0, triCount = 0, materialDraws = 0, materialCount = 0, jointsCount = 0;
		var uniqueMats = new Map();
		for (m in obj.getMaterials()) {
			if( uniqueMats.exists(m.name) ) continue;
			uniqueMats.set(m.name, true);
			materialCount++;
		}
		for (m in meshes) {
			var p = m.primitive;
			triCount += p.triCount();
			vertCount += p.vertexCount();
			var multi = Std.downcast(m, h3d.scene.MultiMaterial);
			var skin = Std.downcast(m, h3d.scene.Skin);
			if( skin != null )
				jointsCount += skin.getSkinData().allJoints.length;
			var count = if( skin != null && skin.getSkinData().splitJoints != null )
				skin.getSkinData().splitJoints.length;
			else if( multi != null )
				multi.materials.length
			else
				1;
			materialDraws += count;
		}

		var mesh = Std.downcast(obj, h3d.scene.Mesh);
		var hmd = mesh != null ? Std.downcast(mesh.primitive, h3d.prim.HMDModel) : null;
		var vFormat = '';
		if (mesh != null && mesh.primitive.buffer != null) {
			for ( i in mesh.primitive.buffer.format.getInputs() )
				vFormat += ' ' + i.name;
		}

		var colVertices = 0;
		var colTriangles = 0;
		if (hmd != null && @:privateAccess hmd.colliderData != null) {
			var col = hmd.getCollider();
			function recCol(c : h3d.col.Collider) {
				var optimized = Std.downcast(c, h3d.col.Collider.OptimizedCollider);
				if ( optimized != null ) {
					recCol(optimized.b);
					return;
				}
				var list = Std.downcast(c, h3d.col.Collider.GroupCollider);
				if ( list != null ) {
					for ( l in list.colliders )
						recCol(l);
					return;
				}
				var polygonBuffer = Std.downcast(c, h3d.col.PolygonBuffer);
				if ( polygonBuffer != null ) {
					colTriangles += @:privateAccess polygonBuffer.triCount;
					colVertices += @:privateAccess Std.int(polygonBuffer.buffer.length / 3);
					return;
				}
				var polygon = Std.downcast(c, h3d.col.Polygon);
				if ( polygon != null ) {
					var t = @:privateAccess polygon.triPlanes;
					while ( t != null ) {
						colTriangles += 1;
						colVertices += 3;
						t = t.next;
					}
					return;
				}
			}
			recCol(col);
		}

		objCount.text = ""+(1 + obj.getObjectsCount());
		meshesCount.text = ""+meshes.length;
		matsCount.text = ""+materialCount;
		drawsCount.text = ""+materialDraws;
		bonesCount.text = ""+jointsCount;
		verticesCount.text = ""+vertCount;
		trianglesCount.text = ""+triCount;
		vertexFormat.text = vFormat;
		colliderVertices.text = ""+colVertices;
		colliderTriangles.text = ""+colTriangles;

		function round(n : Float) { return hxd.Math.round(n * 100) / 100; }

		var transform = obj.defaultTransform;
		if (transform != null) {
			var p = transform.getPosition();
			localPos.text = 'X: ${round(p.x)}  Y: ${round(p.y)}  Z: ${round(p.z)}';
			var r = transform.getEulerAngles();
			localRot.text = 'X: ${round(hxd.Math.radToDeg(r.x))}  Y: ${round(hxd.Math.radToDeg(r.y))}  Z: ${round(hxd.Math.radToDeg(r.z))}';
			var s = transform.getScale();
			localScale.text = 'X: ${round(s.x)}  Y: ${round(s.y)}  Z: ${round(s.z)}';
		}
	}

	function updateLODsInspector(obj : h3d.scene.Object) {
		var mesh = Std.downcast(obj, h3d.scene.Mesh);
		var hmd = Std.downcast(mesh?.primitive, h3d.prim.HMDModel);

		if (hmd == null || hmd.lodCount() <= 1)
			return;

		lodCount.text = '${hmd.lodCount()}';
		lodVerticesCount.text = '${@:privateAccess hmd.lods[mesh.getLodIndex()].vertexCount}';

		var options = [];
		options.push({ label: 'None', value: -1 });
		for (idx in 0...hmd.lodCount())
			options.push({ label: 'LOD ${idx}', value: idx });
		forceDisplayLod.items = options;
		forceDisplayLod.value = mesh.forcedLod;
		forceDisplayLod.onValueChanged = () -> { mesh.forcedLod = forceDisplayLod.value; updateLODsInspector(obj); };

		lodLine.mesh = mesh;

		maxLod.text = '${lodLine.maxLodRatio * 100}';
		maxLod.onChange = (isTempChange) -> {
			if (isTempChange)
				return;
			var v = Std.parseFloat(maxLod.text) / 100;
			if (hxd.Math.isNaN(v)) {
				maxLod.text = '${lodLine.maxLodRatio * 100}';
				return;
			}

			var oldVal = lodLine.maxLodRatio;
			var newVal = v;
			newVal = Math.max(@:privateAccess lodLine.getLodRatio(0), newVal);

			var exec = function(undo) {
				var m = undo ? oldVal : newVal;
				maxLod.text = '${m * 100}';
				lodLine.maxLodRatio = m;
				@:privateAccess lodLine.updateAreas();
			};

			getView().undo.record(exec, false);
			exec(false);
		}

		copyLods.onClick = (_) -> {
			var config = @:privateAccess hmd.lodConfig?.copy();
			hxd.System.setClipboardText(hide.Ide.inst.toJSON(config));
			Ide.showInfo("Copied current lod config to the clipboard");
		}

		pasteLods.onClick = (_) -> {
			var prevConfig = @:privateAccess hmd.lodConfig?.copy();
			var newConfig = try haxe.Json.parse(hxd.System.getClipboardText()) catch(e) null;

			if (newConfig is Array) {
				for (value in (newConfig:Array<Dynamic>)) {
					if (value is Float || value is Int) {
						continue;
					}
					newConfig = null;
					break;
				}
			}

			if (newConfig == null) {
				Ide.showError("Couldn't paste config from clipboard (invalid data)");
				return;
			}

			var exec = function(undo) {
				if (undo) {
					@:privateAccess hmd.lodConfig = prevConfig;
				} else {
					@:privateAccess hmd.lodConfig = cast newConfig;
				}
				@:privateAccess lodLine.updateAreas();
			}

			getView().undo.record(exec, true);
			exec(false);
			Ide.showInfo("Pasted config from the clipboard");
		};

		resetLods.onClick = (_) -> {
			var prevConfig = @:privateAccess hmd.lodConfig?.copy();
			@:privateAccess hmd.lodConfig = h3d.prim.ModelDatabase.current.getDefaultLodConfig(hmd.lib.resource.entry.directory);
			Ide.showInfo('Lod config reset for object : ${obj.name}');
			@:privateAccess lodLine.updateAreas();

			getView().undo.record((isUndo) -> {
				if (isUndo) {
					@:privateAccess hmd.lodConfig = prevConfig;
				} else {
					@:privateAccess hmd.lodConfig = null;
				}

				@:privateAccess lodLine.updateAreas();
			}, true);
		}
	}

	function updateCollisionInspector(obj : h3d.scene.Object) {
		var mesh = Std.downcast(obj, h3d.scene.Mesh);
		var hmd = Std.downcast(mesh?.primitive, h3d.prim.HMDModel);

		if (hmd == null)
			return;

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
					if( cf == null )
						mode = None;
					else if( Reflect.field(cf, "useDefault") )
						mode = Default;
					else if( Reflect.hasField(cf, "precision") )
						mode = Auto;
					else if( Reflect.hasField(cf, "mesh") )
						mode = Mesh;
					else if( Reflect.hasField(cf, "shapes") )
						mode = Shapes;
					settings = new CollisionSettings(mode, cf);
				}
			}
		}


		function refreshCollisionEdition() {
			precisionEl.parent.visible = collisionModeEl.value == CollisionMode.Auto;
			precisionEl.text = '${settings.params.precision ?? 1.0}';

			maxConvexHullsEl.parent.visible = collisionModeEl.value == CollisionMode.Auto;
			maxConvexHullsEl.text = '${settings.params.maxConvexHulls ?? 1}';

			maxSubdivisionEl.parent.visible = collisionModeEl.value == CollisionMode.Auto;
			maxSubdivisionEl.text = '${settings.params.maxSubdiv ?? 32}';

			meshEl.parent.visible = collisionModeEl.value == CollisionMode.Auto || collisionModeEl.value == CollisionMode.Mesh;
			meshEl.value = settings.params.mesh;
		}

		collisionModeEl.items = [for(idx in 0...CollisionMode.Count) { value: idx, label: cast(idx, CollisionMode).toString()}];
		collisionModeEl.value = settings.mode;
		collisionModeEl.onValueChanged = () -> {
			refreshCollisionEdition();
		}

		refreshCollisionEdition();
	}
}

@:access(hrt.ui.HuiSceneEditor)
class Model extends HuiView<{path: String}> {
	static var SRC =
		<model>
			<hui-scene-editor id="scene-editor"/>
		</model>

	static var _ = HuiView.register("model", Model);

	public static var VIEW_MODE_TYPE = "editor.visibility.viewModeType";

	var obj : h3d.scene.Object;
	var selectedObjects: Array<Dynamic> = [];

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		var path = Ide.inst.getRelPath(state.path);
		sceneEditor.load = () -> load(path);
		sceneEditor.onScenePush = (e) -> {
			if (e.button == 0)
				setSelection(sceneEditor.getObjectsAt(cast e.relX, cast e.relY, obj, (o) -> Std.isOfType(o, h3d.scene.Mesh)));
		}

		undo.onAfterChange = () -> {
			hasUnsavedChanges = undo.isDirty();
		}

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
				return HuiRes.icons.cube;
			if (Std.isOfType(item, h3d.mat.Material))
				return HuiRes.icons.material;
			if (Std.isOfType(item, h3d.scene.Skin.Joint))
				return HuiRes.icons.bone;
			return HuiRes.icons.file_blank;
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
		sceneEditor.tree.revealItem(obj);
	}

	override function sync(ctx) {
		super.sync(ctx);
	}

	override function getContextMenuContent(content: Array<hide.comp.ContextMenu.MenuItem>) {
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
		// if (hasUnsavedChanges) {
		// 	uiBase.confirm("Save change before closing ?", Save | DontSave | Cancel, (choice: hrt.ui.HuiConfirmPopup.ConfirmButton) -> {
		// 		switch (choice) {
		// 			case Save:
		// 				execCommand(HuiCommands.save);
		// 				cb(true);
		// 			case DontSave:
		// 				cb(true);
		// 			case Cancel:
		// 				cb(false);
		// 			default:
		// 				throw "???";
		// 		}
		// 	});
		// } else {
		// 	cb(true);
		// }
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
		undo.markClean();
		hasUnsavedChanges = false;
	}

	function load(path : String) {
		var scene = @:privateAccess sceneEditor.scene;
		var lib = hxd.res.Loader.currentInstance.load(path).toModel().toHmd();
		obj = lib.makeObject();
		sceneEditor.scene.s3d.addChild(obj);
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
			new HuiModelInspector(o, sceneEditor.inspectorPanel);
	}
}

#end
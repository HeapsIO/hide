package hide.view;
import hxd.Key as K;

class Model extends FileView {
	static var KEY_ANIM_PLAYING = "AnimationPlaying";

	var tools : hide.comp.Toolbar;
	var obj : h3d.scene.Object;
	var sceneEditor : hide.comp.SceneEditor;
	var tree : hide.comp.SceneTree;
	var tabs : hide.comp.Tabs;
	var overlay : Element;
	var eventList : Element;

	var plight : hrt.prefab.Prefab;
	var light : h3d.scene.Object;
	var lightDirection : h3d.Vector;

	var aspeed : hide.comp.Range;
	var aloop : { function toggle( v : Bool ) : Void; var element : Element; }
	var apause : { function toggle( v : Bool ) : Void; var element : Element; };
	var aretarget : { var element : Element; };
	var timeline : h2d.Graphics;
	var timecursor : h2d.Bitmap;
	var frameIndex : h2d.Text;
	var currentAnimation : { file : String, name : String };
	var cameraMove : Void -> Void;
	var scene(get,never) : hide.comp.Scene;
	var rootPath : String;
	var root : hrt.prefab.Prefab;
	var selectedAxes : h3d.scene.Object;
	var showSelectionAxes : Bool = false;
	var lastSelectedObject : h3d.scene.Object = null;

	var highlightSelection : Bool = true;
	var shader = new h3d.shader.FixedColor(0xffffff);
	var shader2 = new h3d.shader.FixedColor(0xff8000);

	override function save() {

		if(!modified) return;

		// Save render props
		if (Ide.inst.currentConfig.get("sceneeditor.renderprops.edit", false) && sceneEditor.renderPropsRoot != null)
			sceneEditor.renderPropsRoot.save();

		for (o in obj.findAll(o -> Std.downcast(o, h3d.scene.Mesh))) {

			var hmd = Std.downcast(o.primitive, h3d.prim.HMDModel);
			if (hmd == null)
				continue;

			h3d.prim.ModelDatabase.current.saveModelProps(o.name, hmd);
		}

		// Save current Anim data
		if( currentAnimation != null ) {
			var hideData = loadProps();

			var events : Array<{ frame : Int, data : String }> = [];
			for(i in 0 ... obj.currentAnimation.events.length){
				if( obj.currentAnimation.events[i] == null) continue;
				for( e in obj.currentAnimation.events[i])
					events.push({frame:i, data:e});
			}
			hideData.animations.set(currentAnimation.file.split("/").pop(), {events : events} );

			var bytes = new haxe.io.BytesOutput();
			bytes.writeString(haxe.Json.stringify(hideData, "\t"));
			hxd.File.saveBytes(getPropsPath(), bytes.getBytes());
		}
		super.save();
	}


	override function onFileChanged( wasDeleted : Bool, rebuildView = true ) {
		if (wasDeleted ) {
			super.onFileChanged(wasDeleted);
		} else if (element.find(".heaps-scene").length == 0) {
			super.onFileChanged(wasDeleted);
		} else {
			super.onFileChanged(wasDeleted, false);
			onRefresh();
		}
	}

	function loadProps() {
		var propsPath = getPropsPath();
		var hideData : h3d.prim.ModelCache.HideProps;
		if( sys.FileSystem.exists(propsPath) )
			hideData = haxe.Json.parse(sys.io.File.getContent(propsPath));
		else
			hideData = { animations : {} };
		return hideData;
	}

	function getPropsPath() {
		var path = config.get("hmd.savePropsByAnimation") ? currentAnimation.file : getPath();
		var parts = path.split(".");
		parts.pop();
		parts.push("props");
		return ide.getPath(parts.join("."));
	}

	override function onDisplay() {
		this.saveDisplayKey = "Model:" + state.path;

		element.html('
			<div class="flex vertical">
				<div id="toolbar"></div>
				<div class="flex-elt">
					<div class="heaps-scene">
						<div class="hide-scroll hide-scene-layer">
							<div class="tree"></div>
						</div>
					</div>
					<div class="tabs">
						<div class="tab expand" name="Model" icon="sitemap">
							<div class="hide-block">
							<div class="render-props-edition">
								<div class="hide-toolbar">
									<div class="toolbar-label">
										<div class="icon ico ico-sun-o"></div>
										Render props
									</div>
								</div>
								<div class="hide-scenetree"></div>
								</div>
							</div>
							<div class="props hide-scroll">
							</div>
						</div>
						<div class="tab expand" name="Animation" icon="cog">
							<div class="event-editor"> </div>
						</div>
					</div>

				</div>
			</div>
		');

		tools = new hide.comp.Toolbar(null,element.find("#toolbar"));
		overlay = element.find(".hide-scene-layer .tree");
		tabs = new hide.comp.Tabs(null,element.find(".tabs"));
		eventList = element.find(".event-editor");

		root = new hrt.prefab.Prefab(null, null);
		var def = new hrt.prefab.Prefab(null, null);
		new hrt.prefab.RenderProps(def, null).name = "renderer";
		var l = new hrt.prefab.Light(def, null);
		sceneEditor = new hide.comp.SceneEditor(this, root);
		sceneEditor.editorDisplay = false;
		sceneEditor.onRefresh = onRefresh;
		sceneEditor.onUpdate = update;
		sceneEditor.onSelectionChanged = function(elts : Array<hrt.prefab.Prefab>, ?mode : hide.comp.SceneEditor.SelectMode = Default) {
			if (tree != null) tree.setSelection([]);
			refreshSelectionHighlight(null);
		}
		sceneEditor.view.keys = new hide.ui.Keys(null); // Remove SceneEditor Shortcuts
		sceneEditor.view.keys.register("save", function() {
			save();
			skipNextChange = true;
			modified = false;
		});

		sceneEditor.view.keys.register("undo", function() undo.undo());
		sceneEditor.view.keys.register("redo", function() undo.redo());

		sceneEditor.view.keys.register("view.refresh", function() rebuild());
		sceneEditor.view.keys.register("view.refreshApp", function() untyped chrome.runtime.reload());


		element.find(".hide-scene-tree").first().append(sceneEditor.tree.element);
		element.find(".render-props-edition").find('.hide-scenetree').append(sceneEditor.renderPropsTree.element);
		element.find(".props").first().append(sceneEditor.properties.element);
		element.find(".heaps-scene").first().append(sceneEditor.scene.element);
		sceneEditor.view.keys.register("sceneeditor.focus", {name: "Focus Selection", category: "Scene"},
			function() {if (lastSelectedObject != null) refreshSelectionHighlight(lastSelectedObject);});
		sceneEditor.tree.element.addClass("small");
		sceneEditor.renderPropsTree.element.addClass("small");

		var rpEditionvisible = Ide.inst.currentConfig.get("sceneeditor.renderprops.edit", false);
		setRenderPropsEditionVisibility(rpEditionvisible);
	}

	override function onActivate() {
		if (tools != null)
			tools.refreshToggles();

		setRenderPropsEditionVisibility(Ide.inst.currentConfig.get("sceneeditor.renderprops.edit", false));
	}

	inline function get_scene() return sceneEditor.scene;

	var def = false;
	function selectMaterial( m : h3d.mat.Material ) {
		refreshSelectionHighlight(null);

		highlightMaterial(m);

		var properties = sceneEditor.properties;
		properties.clear();

		var tex = new Element('
		<div class="group" name="Textures">
			<dl>
				<dt>Base</dt><dd><input type="texture" field="texture"/></dd>
				<dt>Spec</dt><dd><input type="texture" field="specularTexture"/></dd>
				<dt>Normal</dt><dd><input type="texture" field="normalMap"/></dd>
			</dl>
		</div>
		<br/>
		');

		var matEl = new Element('
		<div class="group" name="Material ${m.name}">
		</div>
		<dl>
			<dt></dt><dd><input type="button" value="Reset Defaults" class="reset"/></dd>
			<dt></dt><dd><input type="button" value="Save" class="save"/></dd>
		</dl>
		<br/>
		');

		var matLibs = scene.listMatLibraries(getPath());
		var materials = [];

		var selectedLib = null;
		var selectedMat = null;
		var props : Dynamic =  h3d.mat.MaterialSetup.current.loadMaterialProps(m);
		if ( props != null && props.__ref != null && !def ) {
			selectedMat = props.__ref + "/" + props.name;
			selectedLib = props.__ref;
			tex.hide();
			matEl.hide();
		}
		if ( def )
			def = false;
		var matLibrary = new Element('
			<div class="group" name="Material Library">
				<dt>Library</dt>
				<dd>
					<select class="lib">
						<option value="">None</option>
						${[for( i in 0...matLibs.length ) '<option value="${matLibs[i].name}" ${(selectedLib == matLibs[i].path) ? 'selected' : ''}>${matLibs[i].name}</option>'].join("")}
					</select>
				</dd>
				<dt>Material</dt>
				<dd>
					<select class="mat">
						<option value="">None</option>
					</select>
				</dd>
				<dt>Mode</dt>
				<dd>
					<select class="mode">
						<option value="folder">Shared by folder</option>
						<option value="modelSpec">Model specific</option>
					</select>
				</dd>
				<dt></dt><dd><input type="button" value="Go to library" class="goTo"/></dd>
				<dt></dt><dd><input type="button" value="Save" class="save"/></dd>
			</div>
			<br/>
		');

		var mode = matLibrary.find(".mode");
		var saveButton = matLibrary.find(".save");
		var libSelect = matLibrary.find(".lib");
		var matSelect = matLibrary.find(".mat");

		function updateMatSelect() {
			matSelect.empty();
			new Element('<option value="">None</option>').appendTo(matSelect);

			materials = scene.listMaterialFromLibrary(getPath(), libSelect.val());

			for (idx in 0...materials.length) {
				new Element('<option value="${materials[idx].path + "/" + materials[idx].mat.name}" ${(selectedMat == materials[idx].path + "/" + materials[idx].mat.name) ? 'selected' : ''}>${materials[idx].mat.name}</option>').appendTo(matSelect);
			}
		}

		updateMatSelect();

		if ( props != null && props.__refMode != null )
			mode.val((props:Dynamic).__refMode).select();


		function setDefault() {
			tex.show();
			matEl.show();
			def = true;
			selectMaterial(m);
		}

		libSelect.change(function(_) {
			updateMatSelect();

			if (libSelect.val() == "")
				setDefault();
		});

		matSelect.change(function(_) {
			var mat = Reflect.field(scene.findMat(materials, matSelect.val()), "mat");
			if ( mat != null ) {
				@:privateAccess mat.update(m, mat.renderProps(), function(path:String) {
					return hxd.res.Loader.currentInstance.load(path).toTexture();
				});
				tex.hide();
				matEl.hide();
			} else {
				setDefault();
			}
		});

		matLibrary.find(".goTo").click(function(_) {
			var mat = scene.findMat(materials, matSelect.val());
			if ( mat != null ) {
				var matName = mat.mat.name;
				hide.Ide.inst.openFile(Reflect.field(mat, "path"), null, (view) -> {
					var prefabView : hide.view.Prefab.Prefab = cast view;

					prefabView.delaySceneEditor(function() {
						for (p in @:privateAccess prefabView.data.flatten(hrt.prefab.Material)) {
							if (p != null && p.name == matName) {
								prefabView.sceneEditor.selectElements([p]);
								@:privateAccess
								if (p.previewSphere != null) {
									prefabView.sceneEditor.focusObjects([p.previewSphere]);
								}
							}
						}
					});
				});
			}
			else if (libSelect != null) {
				var libraries = scene.listMatLibraries(this.getPath());
				var lPath = "";
				for (l in libraries) {
					if (l.name == libSelect.val()) {
						lPath = l.path;
						break;
					}
				}

				if (lPath == "")
					return;

				hide.Ide.inst.openFile(lPath);
			}
		});

		var lib = @:privateAccess scene.loadHMD(this.getPath(),false);
		var hmd = lib.header;
		var defaultProps = null;
		for ( mat in hmd.materials ) {
			if ( mat.name == m.name ) {
				var material = h3d.mat.MaterialSetup.current.createMaterial();
				material.name = mat.name;
				material.model = lib.resource;
				material.blendMode = mat.blendMode;
				defaultProps = material.getDefaultModelProps();
				break;
			}
		}
		var saveCallback = function(_) {
			var mat = scene.findMat(materials, matSelect.val());
			if ( mat != null ) {
				for ( f in Reflect.fields((m.props:Dynamic)) )
					Reflect.deleteField((m.props:Dynamic), f);
				Reflect.setField((m.props:Dynamic), "__ref", mat.path);
				Reflect.setField((m.props:Dynamic), "name", mat.mat.name);
				if ( mode.val() == "modelSpec" )
					Reflect.setField((m.props:Dynamic), "__refMode", "modelSpec");
				else
					Reflect.deleteField((m.props:Dynamic), "__refMode");
			} else {
				Reflect.deleteField((m.props:Dynamic), "__ref");
				Reflect.deleteField((m.props:Dynamic), "name");
				Reflect.deleteField((m.props:Dynamic), "__refMode");
			}
			h3d.mat.MaterialSetup.current.saveMaterialProps(m, defaultProps);
			Ide.inst.quickMessage('Properties for mat (${m.name}) had been saved');
		};
		saveButton.click(saveCallback);
		properties.add(matLibrary, m);

		properties.add(tex, m);

		var e = properties.add(matEl);

		properties.addMaterial(m, e.find(".group > .content"));
		e.find(".reset").click(function(_) {
			var old = m.props;
			m.props = m.getDefaultModelProps();
			selectMaterial(m);
			undo.change(Field(m, "props", old), selectMaterial.bind(m));
		});
		e.find(".save").click(saveCallback);
	}

	static var lodPow : Float = 0.3;
	var selectedJoint : String = null;
	var selectedMesh : h3d.scene.Mesh = null;
	var displayJoints = null;
	function selectObject( obj : h3d.scene.Object ) {
		if ( Std.isOfType(obj, h3d.scene.Skin.Joint) ) {
			selectedJoint = obj.name;
			if ( @:privateAccess sceneEditor.jointsGraphics != null )
				sceneEditor.setJoints(true, selectedJoint);
		} else
			selectedJoint = null;

		var properties = sceneEditor.properties;
		properties.clear();

		var objectCount = 1 + obj.getObjectsCount();
		var meshes = obj.getMeshes();
		var vertexCount = 0, triangleCount = 0, materialDraws = 0, materialCount = 0, bonesCount = 0;
		var uniqueMats = new Map();
		for( m in obj.getMaterials() ) {
			if( uniqueMats.exists(m.name) ) continue;
			uniqueMats.set(m.name, true);
			materialCount++;
		}
		for( m in meshes ) {
			var p = m.primitive;
			triangleCount += p.triCount();
			vertexCount += p.vertexCount();
			var multi = Std.downcast(m, h3d.scene.MultiMaterial);
			var skin = Std.downcast(m, h3d.scene.Skin);
			if( skin != null )
				bonesCount += skin.getSkinData().allJoints.length;
			var count = if( skin != null && skin.getSkinData().splitJoints != null )
				skin.getSkinData().splitJoints.length;
			else if( multi != null )
				multi.materials.length
			else
				1;
			materialDraws += count;
		}

		function roundVec(vec: Dynamic) : Any {
			var scale = 1000;
			vec.x = hxd.Math.round(vec.x * scale) / scale;
			vec.y = hxd.Math.round(vec.y * scale) / scale;
			vec.z = hxd.Math.round(vec.z * scale) / scale;
			return vec;
		}

		var transform = obj.defaultTransform;

		var mesh = Std.downcast(obj, h3d.scene.Mesh);
		var vertexFormat = '';
		if ( mesh != null && mesh.primitive.buffer != null ) {
			for ( i in mesh.primitive.buffer.format.getInputs() )
				vertexFormat += ' ' + i.name;
			vertexFormat = '<dt>Vertex format</dt><dd>$vertexFormat</dd>';
		}
		var e = properties.add(new Element('
			<div class="group" name="Properties">
				<dl>
					<dt>X</dt><dd><input field="x"/></dd>
					<dt>Y</dt><dd><input field="y"/></dd>
					<dt>Z</dt><dd><input field="z"/></dd>
					<dt>Attach</dt><dd><select class="follow"><option value="">--- None ---</option></select></dd>
				</dl>
			</div>
			<div class="group" name="Info">
				<dl>
					<dt>Objects</dt><dd>$objectCount</dd>
					<dt>Meshes</dt><dd>${meshes.length}</dd>
					<dt>Materials</dt><dd>$materialCount</dd>
					<dt>Draws</dt><dd>$materialDraws</dd>
					<dt>Bones</dt><dd>$bonesCount</dd>
					<dt>Vertexes</dt><dd>$vertexCount</dd>
					<dt>Triangles</dt><dd>$triangleCount</dd>
					' + vertexFormat +
					if (transform != null) {
						var size : h3d.col.Point = roundVec(obj.getBounds().getSize());

						size.x = hxd.Math.max(0, size.x);
						size.y = hxd.Math.max(0, size.y);
						size.z = hxd.Math.max(0, size.z);

						var meshSize : h3d.col.Point = null;
						if (mesh != null) {
							var bounds = mesh.primitive.getBounds().clone();
							bounds.transform(obj.getAbsPos());
							meshSize = bounds.getSize();

							roundVec(meshSize);
							meshSize.x = hxd.Math.max(0, meshSize.x);
							meshSize.y = hxd.Math.max(0, meshSize.y);
							meshSize.z = hxd.Math.max(0, meshSize.z);

						}

						var pos = transform.getPosition();
						roundVec(pos);
						var rot = transform.getEulerAngles();
						rot.x = hxd.Math.radToDeg(rot.x);
						rot.y = hxd.Math.radToDeg(rot.y);
						rot.z = hxd.Math.radToDeg(rot.z);
						rot = roundVec(rot);

						var scale : h3d.Vector = roundVec(transform.getScale());

						'<dt>Local Pos</dt><dd>X: ${pos.x}, Y: ${pos.y}, Z: ${pos.z}</dd>
						<dt>Local Rot</dt><dd>X: ${rot.x}°, Y: ${rot.y}°, Z: ${rot.z}°</dd>
						<dt>Local Scale</dt><dd>X: ${scale.x}, Y: ${scale.y}, Z: ${scale.z}</dd>
						<dt>Total Size</dt><dd>X: ${size.x}, Y: ${size.y}, Z: ${size.z}</dd>
						${meshSize != null ? '<dt>Mesh Size</dt><dd>X: ${meshSize.x}, Y: ${meshSize.y}, Z: ${meshSize.z}</dd>' : ""}';
					} else '' +
				'</dl>
			</div>
			<br/>
		'),obj);

		var mesh = Std.downcast(obj, h3d.scene.Mesh);
		var hmd = mesh != null ? Std.downcast(mesh.primitive, h3d.prim.HMDModel) : null;
		selectedMesh = mesh;

		if (mesh != null && hmd != null) {
			// Blendshapes edition
			if (@:privateAccess hmd.blendshape != null) {
				var blendShape = new Element('
				<div class="group" name="Blend Shapes">
					<dt>Index</dt><dd><input id="bs-index" type="range" min="0" max="${@:privateAccess hmd.blendshape.getBlendshapeCount() - 1}" step="1" field=""/></dd>
					<dt>Amount</dt><dd><input id="bs-amount" type="range" min="0" max="1" field=""/></dd>
				</div>');

				properties.add(blendShape, null, function(pname){
					@:privateAccess hmd.blendshape.setBlendshapeAmount(blendShape.find("#bs-index").val(),blendShape.find("#bs-amount").val());
				});
			}

			// LODs edition
			if (@:privateAccess hmd.lodCount() > 0) {
				var lodsEl = new Element('
					<div class="group lods" name="LODs">
						<dt>LOD Count</dt><dd>${hmd.lodCount()}</dd>
						<dt>Force display LOD</dt>
						<dd>
							<select id="select-lods">
								<option value="-1">None</option>
								${[ for(idx in 0...hmd.lodCount()) '<option value="${idx}">LOD ${idx}</option>'].join("")}
							<select>
						</dd>
						<dt>LOD Vertexes</dt><dd id="vertexes-count">-</dd>
						<div class="lods-line">
							<div class="line"></div>
							<div class="cursor">
								<div class="cursor-line"></div>
								<p class="ratio">100%</p>
							</div>
						</div>
						<div id="buttons">
							<input type="button" value="Reset defaults" id="reset-lods"/>
						</div>
					</div>
				');
				properties.add(lodsEl, null, null);

				function getLodRatioFromIdx(idx : Int) {
					var lodConfig = hmd.getLodConfig();
					if (idx == 0) return 1.;
					if (idx >= hmd.lodCount()) return 0.;
					return lodConfig[idx - 1];
				}

				function getLodRatioFromPx(px : Float) {
					var ratio = 1 - (px / lodsEl.find(".line").width());
					return Math.pow(ratio, 1.0 / lodPow);
				}

				function getLodRatioPowedFromIdx(idx : Int) {
					var lodConfig = hmd.getLodConfig();
					var prev = idx == 0 ? 1 : hxd.Math.pow(lodConfig[idx - 1] , lodPow);

					return (Math.abs(prev - hxd.Math.pow(lodConfig[idx], lodPow)));
				}

				function startDrag(onMove: js.jquery.Event->Void, onStop: js.jquery.Event->Void) {
					var el = new Element(element[0].ownerDocument.body);
					el.on("mousemove.lods", onMove);
					el.on("mouseup.lods", function(e: js.jquery.Event) {
						el.off("mousemove.lods");
						el.off("mouseup.lods");
						e.preventDefault();
						e.stopPropagation();
						onStop(e);
					});
				}

				function refreshLodLine() {
					var areas = lodsEl.find(".area");
					var lineEl = lodsEl.find(".line");
					var idx = 0;
					for (area in areas) {
						var areaEl = new Element(area);
						areaEl.css({ width : '${lineEl.width() * getLodRatioPowedFromIdx(idx)}px' });

						var roundedRatio = Std.int(Math.pow(getLodRatioFromIdx(idx), lodPow) * 10000.) / 100.;
						areaEl.find('#percent').text('${roundedRatio}%');
						idx++;
					}
				}

				var resetLod = lodsEl.find('#reset-lods');
				resetLod.on("click", function() {
					var prevConfig = @:privateAccess hmd.lodConfig?.copy();
					@:privateAccess hmd.lodConfig = null;
					Ide.inst.quickMessage('Lod config reset for object : ${obj.name}');
					refreshLodLine();

					undo.change(Custom(function(undo) {
						if (undo) {
							@:privateAccess hmd.lodConfig = prevConfig;
						} else {
							@:privateAccess hmd.lodConfig = null;
						}

						refreshLodLine();
					}));
				});

				var selectLod = lodsEl.find("select");
				selectLod.on("change", function(){
					hmd.forcedLod = Std.int(lodsEl.find("select").val());
				});

				var lodsLine = lodsEl.find(".line");
				for (idx in 0...hmd.lodCount()) {
					var areaEl = new Element('
					<div class="area">
						<p>LOD&nbsp${idx}</p>
						<p id="percent">-%</p>
					</div>');

					if (idx == hmd.lodCount() - 1)
						areaEl.css({ flex : 1 });

					lodsLine.append(areaEl);
					refreshLodLine();

					var widthHandle = 10;
					areaEl.on("mousemove", function(e:js.jquery.Event) {
						if ((e.offsetX <= widthHandle && idx != 0) || (areaEl.width() - e.offsetX) <= widthHandle && idx != hmd.lodCount() - 1)
							areaEl.css({ cursor : 'w-resize' });
						else
							areaEl.css({ cursor : 'default' });
					});

					areaEl.on("mousedown", function(e:js.jquery.Event) {
						var firstHandle = e.offsetX <= widthHandle && idx != 0;
						var secondHandle = areaEl.width() - e.offsetX <= widthHandle && idx != hmd.lodCount() - 1;

						if (firstHandle || secondHandle) {
							var currIdx = secondHandle ? idx : idx - 1;
							var prevConfig = @:privateAccess hmd.lodConfig?.copy();
							var newConfig = hmd.getLodConfig()?.copy();
							var limits = [ getLodRatioFromIdx(currIdx + 2),  getLodRatioFromIdx(currIdx)];

							startDrag(function(e) {
								var newRatio = getLodRatioFromPx(e.clientX - lodsLine.offset().left);
								newRatio = hxd.Math.clamp(newRatio, limits[0], limits[1]);
								newConfig[currIdx] = newRatio;
								@:privateAccess hmd.lodConfig = newConfig;
								refreshLodLine();
							}, function(e) {

								undo.change(Custom(function(undo) {
									if (undo) {
										@:privateAccess hmd.lodConfig = prevConfig;
									} else {
										@:privateAccess hmd.lodConfig = newConfig;
									}

									refreshLodLine();
								}));
							});
						}
					});
				}

				var cursor = lodsEl.find(".cursor");
				cursor.css({top: '${lodsLine.position().top + 11}px'});
			}
		}

		var select = e.find(".follow");
		for( path in getNamedObjects(obj) ) {
			var parts = path.split(".");
			var opt = new Element("<option>").attr("value", path).html([for( p in 1...parts.length ) "&nbsp; "].join("") + parts.pop());
			select.append(opt);
		}
		select.change(function(_) {
			var name = select.val().split(".").pop();
			obj.follow = this.obj.getObjectByName(name);
		});


		refreshSelectionHighlight(obj);
	}

	function refreshSelectionHighlight(selectedObj: h3d.scene.Object) {
		if (selectedObj == lastSelectedObject && selectedObj != null) {
			sceneEditor.focusObjects([selectedObj]);
		}
		lastSelectedObject = selectedObj;
		var root = this.obj;
		if (root == null)
			return;

		var materials = root.getMaterials();

		for( m in materials ) {
			m.removePass(m.getPass("highlight"));
			m.removePass(m.getPass("highlightBack"));
		}

		if (selectedObj == null) {
			selectedAxes.visible = false;
		}

		if (!highlightSelection || selectedObj == null)
			return;

		{
			selectedAxes.follow = selectedObj;
			selectedAxes.visible = showSelectionAxes;
		}

		materials = selectedObj.getMaterials();

		for( m in materials ) {
			if( m.name != null && StringTools.startsWith(m.name,"$UI.") )
				continue;
			highlightMaterial(m);
		}
	}

	function highlightMaterial(m : h3d.mat.Material) {
		var p = m.allocPass("highlight");
		p.culling = None;
		p.depthWrite = false;
		p.depthTest = LessEqual;
		p.addShader(shader);
		var p = m.allocPass("highlightBack");
		p.culling = None;
		p.depthWrite = false;
		p.depthTest = Always;
		p.addShader(shader2);
	}

	function getNamedObjects( ?exclude : h3d.scene.Object ) {
		var out = [];

		function getJoint(path:Array<String>,j:h3d.anim.Skin.Joint) {
			path.push(j.name);
			out.push(path.join("."));
			for( j in j.subs )
				getJoint(path, j);
			path.pop();
		}

		function getRec(path:Array<String>,o:h3d.scene.Object) {
			if( o == exclude || o.name == null ) return;
			path.push(o.name);
			out.push(path.join("."));
			for( c in o )
				getRec(path, c);
			var sk = Std.downcast(o, h3d.scene.Skin);
			if( sk != null ) {
				var j = sk.getSkinData();
				for( j in j.rootJoints )
					getJoint(path, j);
			}
			path.pop();
		}

		if( obj.name == null )
			for( o in obj )
				getRec([], o);
		else
			getRec([], obj);

		return out;
	}

	function makeAxes(width: Float = 1.0, length: Float = 1.0, ?pass:String = null, alpha:Float = 1.0) {
		var g = new h3d.scene.Graphics(scene.s3d);
		g.lineStyle(width,0xFF0000, alpha);
		g.lineTo(length,0,0);
		g.lineStyle(width,0x00FF00, alpha);
		g.moveTo(0,0,0);
		g.lineTo(0,length,0);
		g.lineStyle(width,0x0000FF, alpha);
		g.moveTo(0,0,0);
		g.lineTo(0,0,length);
		g.lineStyle();

		for(m in g.getMaterials()) {
			if (pass != null)
				m.mainPass.setPassName(pass);
			m.mainPass.depth(false, Always);
			if (alpha != 1.0) {
				m.blendMode = Alpha;
			}
		}

		return g;
	}

	function onRefresh() {
		this.saveDisplayKey = "Model:" + state.path;

		sceneEditor.loadCam3D();

		// Remove current instancied render props
		sceneEditor.root3d.removeChildren();

		// Remove current library to create a new one with the actual render prop
		root = new hrt.prefab.Prefab(null, null);
		for (c in @:privateAccess sceneEditor.sceneData.children)
			@:privateAccess sceneEditor.sceneData.children.remove(c);


		@:privateAccess sceneEditor.createRenderProps(@:privateAccess sceneEditor.sceneData);

		if (sceneEditor.renderPropsRoot != null && sceneEditor.renderPropsRoot.source != null)
			root.children.push(sceneEditor.renderPropsRoot);

		// Create default render props if no render props has been created yet
		var r = root.getOpt(hrt.prefab.RenderProps, true);
		if( r == null) {
			var def = new hrt.prefab.Object3D(root, null);
			def.name = "Default Ligthing";
			var render = new hrt.prefab.RenderProps(def, null);
			render.name = "renderer";
			var l = new hrt.prefab.Light(def, null);
			l.name = "sunLight";
			l.kind = Directional;
			l.power = 1.5;
			var q = new h3d.Quat();
			q.initDirection(new h3d.Vector(-0.28,0.83,-0.47));
			var a = q.toEuler();
			l.rotationX = Math.round(a.x * 180 / Math.PI);
			l.rotationY = Math.round(a.y * 180 / Math.PI);
			l.rotationZ = Math.round(a.z * 180 / Math.PI);
			l.shadows.mode = Dynamic;
			l.shadows.size = 1024;

			def.make(new hrt.prefab.ContextShared());

			r = render;
			r.applyProps(scene.s3d.renderer);
		}

		// Apply render props properties on scene
		var refPrefab = new hrt.prefab.Reference(null, null);
		if( @:privateAccess refPrefab.refInstance != null ) {
			var renderProps = @:privateAccess refPrefab.refInstance.getOpt(hrt.prefab.RenderProps);
			if( renderProps != null )
				renderProps.applyProps(scene.s3d.renderer);
		}

		plight = root.find(hrt.prefab.Light);
		if( plight != null ) {
			this.light = hrt.prefab.Object3D.getLocal3d(plight);

			if (this.light != null)
				lightDirection = this.light.getLocalDirection();
		}

		if (obj != null) {
			for (m in this.obj.getMeshes()) {
				if(m.primitive.buffer != null && !m.primitive.buffer.isDisposed())
					m.primitive.buffer.dispose();
			}

			obj.remove();

			if (obj.isMesh()) {
				obj.toMesh().primitive.buffer.dispose();
			}
		}

		scene.setCurrent();
		obj = scene.loadModel(state.path, true, true);
		new h3d.scene.Object(scene.s3d).addChild(obj);

		var autoHide : Array<String> = config.get("scene.autoHide");

		function hidePropsRec( obj : h3d.scene.Object ) {
			for(n in autoHide)
				if(obj.name != null && obj.name.indexOf(n) == 0)
					obj.visible = false;
			for( o in obj )
				hidePropsRec(o);
		}
		hidePropsRec(obj);

		if( tree != null ) tree.remove();
		tree = new hide.comp.SceneTree(obj, overlay, obj.name != null);
		tree.onSelectMaterial = selectMaterial;
		tree.onSelectObject = selectObject;
		tree.saveDisplayKey = this.saveDisplayKey;

		tools.clear();
		var anims = scene.listAnims(getPath());

		var a = this.getDisplayState(KEY_ANIM_PLAYING);
		if( anims.length > 0 ) {
			var selIdx = 0;
			for (aIdx => anim in anims) {
				if (anim == a)
					selIdx = aIdx + 1;
			}
			var sel = tools.addSelect("play-circle");
			var content = [for( a in anims ) {
				var label = scene.animationName(a);
				{ label : label, value : a }
			}];
			content.unshift({ label : "-- no anim --", value : null });
			sel.setContent(content);
			sel.element.find("select").val(""+selIdx);
			sel.onSelect = function(file:String) {
				if (scene.editor.view.modified && !js.Browser.window.confirm("Current animation has been modified, change animation without saving?"))
				{
					var idx = anims.indexOf(currentAnimation.file)+1;
					sel.element.find("select").val(""+idx);
					return;
				}

				setAnimation(file);
			};
		}

		tools.saveDisplayKey = "ModelTools";

		tools.addButton("video-camera", "Reset Camera", function() {
			sceneEditor.resetCamera();
		});

		tools.makeToolbar([{id: "camSettings", title : "Camera Settings", icon : "camera", type : Popup((e : hide.Element) -> new hide.comp.CameraControllerEditor(sceneEditor,e)) }], null, null);

		tools.addSeparator();

		var axes = makeAxes(0.5, 100.0, "overlay", 0.75);
		axes.visible = false;

		selectedAxes = makeAxes(3.0, 1.0, "overlay");
		selectedAxes.visible = false;

		tools.addToggle("localTransformsToggle", "location-arrow", "Toggle Axis", function(v) {
			axes.visible = v;
			showSelectionAxes = v;
			refreshSelectionHighlight(lastSelectedObject);
		});

		var toolsDefs : Array<hide.comp.Toolbar.ToolDef> = [];

		toolsDefs.push({id: "showViewportOverlays", title : "Viewport Overlays", icon : "eye", type : Toggle((v) -> { sceneEditor.updateViewportOverlays(); }) });
		toolsDefs.push({id: "viewportoverlays-menu", title : "", icon: "", type : Popup((e) -> new hide.comp.SceneEditor.ViewportOverlaysPopup(e, sceneEditor))});

		//toolsDefs.push({id: "iconVisibility", title : "Toggle 3d icons visibility", icon : "image", type : Toggle((v) -> { hide.Ide.inst.show3DIcons = v; }), defaultValue: true });
        //toolsDefs.push({id: "iconVisibility-menu", title : "", icon: "", type : Popup((e) -> new hide.comp.SceneEditor.IconVisibilityPopup(null, e, sceneEditor))});
		tools.makeToolbar(toolsDefs);

		tools.addSeparator();

		tools.addPopup(null, "View Modes", (e) -> new hide.comp.SceneEditor.ViewModePopup(e, Std.downcast(@:privateAccess scene.s3d.renderer, h3d.scene.pbr.Renderer), sceneEditor), null);

		tools.addSeparator();

		tools.addPopup(null, "Render Props", (e) -> new hide.comp.SceneEditor.RenderPropsPopup(e, this, sceneEditor, true, true), null);

		tools.addSeparator();

		aloop = tools.addToggle("refresh", "refresh", "Loop animation", function(v) {
			if( obj.currentAnimation != null ) {
				obj.currentAnimation.loop = v;
				obj.currentAnimation.onAnimEnd = function() {
					if( !v ) haxe.Timer.delay(function() obj.currentAnimation.setFrame(0), 500);
				}
			}
		});

		apause = tools.addToggle("pause", "pause", "Pause animation", function(v) {
			if( obj.currentAnimation != null ) obj.currentAnimation.pause = v;
		});

		aretarget = tools.addToggle("retarget", "share-square-o", "Retarget Animation", function(b) {
			setRetargetAnim(b);
		});

		aspeed = tools.addRange("Animation speed", function(v) {
			if( obj.currentAnimation != null ) obj.currentAnimation.speed = v;
		}, 1, 0, 2);

		initConsole();

		sceneEditor.onResize = buildTimeline;
		setAnimation(a);

		// Adapt initial camera position to model
		var camSettings = @:privateAccess sceneEditor.view.getDisplayState("Camera");
		var isGlobalSettings = Ide.inst.currentConfig.get("sceneeditor.camera.isglobalsettings", false);
		if (isGlobalSettings)
			camSettings = Ide.inst.currentConfig.get("sceneeditor.camera.isglobalsettings", false);

		if (camSettings == null) {
			var bnds = new h3d.col.Bounds();
			var centroid = new h3d.Vector();

			centroid = centroid.add(this.obj.getAbsPos().getPosition());
			bnds.add(this.obj.getBounds());

			var s = bnds.toSphere();
			var r = s.r * 4.0;
			sceneEditor.cameraController.set(r, null, null, s.getCenter());
			sceneEditor.cameraController.toTarget();
		}
	}

	function setRetargetAnim(b:Bool) {
		for( m in obj.getMeshes() ) {
			var sk = Std.downcast(m, h3d.scene.Skin);
			if( sk == null ) continue;
			for( j in sk.getSkinData().allJoints ) {
				if( j.parent == null ) continue; // skip root join (might contain feet translation)
				j.retargetAnim = b;
			}
		}
	}

	function initConsole() {
		var c = new h2d.Console(hxd.res.DefaultFont.get(), scene.s2d);
		c.addCommand("rotate",[{ name : "speed", t : h2d.Console.ConsoleArg.AFloat }], function(r) {
			cameraMove = function() {
				var cam = scene.s3d.camera;
				var dir = cam.pos.sub(cam.target);
				dir.z = 0;
				var angle = Math.atan2(dir.y, dir.x);
				angle += r * hxd.Timer.tmod * 0.01;
				var ray = dir.length();
				cam.pos.set(
					Math.cos(angle) * ray + cam.target.x,
					Math.sin(angle) * ray + cam.target.y,
					cam.pos.z);
				sceneEditor.cameraController.loadFromCamera();
			};
		});
		c.addCommand("stop", [], function() {
			cameraMove = null;
		});
	}

	override function buildTabMenu() {
		var menu = super.buildTabMenu();
		var arr : Array<hide.comp.ContextMenu.MenuItem> = [
			{ label : null, isSeparator : true },
			{ label : "Export", click : function() {
				ide.chooseFileSave(this.getPath().substr(0,-4)+"_dump.txt", function(file) {
					var lib = @:privateAccess scene.loadHMD(this.getPath(),false);
					var hmd = lib.header;
					hmd.data = lib.getData();
					sys.io.File.saveContent(ide.getPath(file), new hxd.fmt.hmd.Dump().dump(hmd));
				});
			} },
			{ label : "Export Animation", enabled : currentAnimation != null, click : function() {
				ide.chooseFileSave(this.getPath().substr(0,-4)+"_"+currentAnimation.name+"_dump.txt", function(file) {
					var lib = @:privateAccess scene.loadHMD(ide.getPath(currentAnimation.file),true);
					var hmd = lib.header;
					hmd.data = lib.getData();
					sys.io.File.saveContent(ide.getPath(file), new hxd.fmt.hmd.Dump().dump(hmd));
				});
			} },
		];
		return menu.concat(arr);
	}

	function setAnimation( file : String ) {

		scene.setCurrent();
		if( timeline != null ) {
			timeline.remove();
			timeline = null;
		}
		apause.toggle(false);
		aloop.toggle(true);
		aspeed.value = 1;
		aloop.element.toggle(file != null);
		aspeed.element.toggle(file != null);
		apause.element.toggle(file != null);
		aretarget.element.toggle(file != null);
		if( file == null ) {
			obj.stopAnimation();
			currentAnimation = null;
			this.removeDisplayState(KEY_ANIM_PLAYING);
			return;
		}
		var anim = scene.loadAnimation(file);
		currentAnimation = { file : file, name : scene.animationName(file) };

		var hideData = loadProps();
		var animData = hideData.animations.get(currentAnimation.file.split("/").pop());
		if( animData != null && animData.events != null )
			anim.setEvents(animData.events);

		obj.playAnimation(anim);
		buildTimeline();
		buildEventPanel();
		modified = false;

		this.saveDisplayState(KEY_ANIM_PLAYING, file);
	}

	function buildEventPanel(){
		eventList.empty();
		var events = @:privateAccess obj.currentAnimation.events;
		var fbxEventList = new Element('<div></div>');
		fbxEventList.append(new Element('<div class="title"><label>Events</label></div>'));
		function addEvent( n : String, f : Float, root : Element ){
			var e = new Element('<div class="event"><span class="label">"$n"</span><span class="label">$f</span></div>');
			root.append(e);
		}
		if(events != null) {
			for( i in 0...events.length ) {
				var el = events[i];
				if( el == null || el.length == 0 ) continue;
				for( e in el )
					addEvent(e, i, fbxEventList);
			}
		}
		eventList.append(fbxEventList);
	}

	function buildTimeline() {
		if( timeline != null ) {
			timeline.remove();
			timeline = null;
		}
		if( obj.currentAnimation == null )
			return;

		scene.setCurrent();

		var H = 15;
		var W = scene.s2d.width;
		timeline = new h2d.Graphics(scene.s2d);
		timeline.y = scene.s2d.height - H;
		timeline.beginFill(0x101010, 0.8);
		timeline.drawRect(0, 0, W, H);

		if( W / obj.currentAnimation.frameCount > 3 ) {
			timeline.beginFill(0x333333);
			for( i in 0...obj.currentAnimation.frameCount+1 ) {
				var p = Std.int(i * W / obj.currentAnimation.frameCount);
				if( p == W ) p--;
				timeline.drawRect(p, 0, 1, H>>1);
			}
		}

		var int = new h2d.Interactive(W, H, timeline);
		int.enableRightButton = true;
		timecursor = new h2d.Bitmap(h2d.Tile.fromColor(0x808080, 8, H), timeline);
		timecursor.x = -100;
		int.onPush = function(e) {
			switch( e.button ) {
			case 0:
				var prevPause = obj.currentAnimation.pause;
				obj.currentAnimation.pause = true;
				var f = (e.relX / W) * obj.currentAnimation.frameCount;
				if (K.isDown(K.SHIFT))
					f = Math.round(f);
				obj.currentAnimation.setFrame(f);
				int.startCapture(function(e) {
					switch(e.kind ) {
					case ERelease:
						obj.currentAnimation.pause = prevPause;
						scene.s2d.stopCapture();
					case EMove:
						var f = (e.relX / W) * obj.currentAnimation.frameCount;
						if (K.isDown(K.SHIFT))
							f = Math.round(f);
						obj.currentAnimation.setFrame(f);
					default:
					}
				});
			}
		}

		int.onClick = (e:hxd.Event) -> {
			if (e.button == 1) {
				var deleteEvent = function(s:String, f:Int){
					obj.currentAnimation.removeEvent(f, s);
					buildTimeline();
					buildEventPanel();

					undo.change(Custom(function(undo) {
						if(undo) {
							obj.currentAnimation.addEvent(f, s);
						}
						else {
							obj.currentAnimation.removeEvent(f, s);
						}

						buildTimeline();
						buildEventPanel();
					}));
				}
				var addEvent = function(s:String, f:Int){
					obj.currentAnimation.addEvent(f, s);
					buildTimeline();
					buildEventPanel();

					undo.change(Custom(function(undo) {
						if(undo) {
							obj.currentAnimation.removeEvent(f, s);
						}
						else {
							obj.currentAnimation.addEvent(f, s);
						}

						buildTimeline();
						buildEventPanel();
					}));
				}
				var frame = Math.round((e.relX / W) * obj.currentAnimation.frameCount);
				var menuItems : Array<hide.comp.ContextMenu.MenuItem> = [
					{ label : "New", click: function(){ addEvent("NewEvent", frame); }},
				];
				if(obj.currentAnimation.events != null && obj.currentAnimation.events[frame] != null){
					for(e in obj.currentAnimation.events[frame])
						menuItems.push({ label : "Delete " + e, click: function(){ deleteEvent(e, frame); }});
				}
				hide.comp.ContextMenu.createFromPoint(ide.mouseX, ide.mouseY, menuItems);
			}
		}

		frameIndex = new h2d.Text(hxd.res.DefaultFont.get(), timecursor);
		frameIndex.y = -30.0;
		frameIndex.textAlign = Center;
		frameIndex.text = "0";
		frameIndex.alpha = 0.5;

		var events = @:privateAccess obj.currentAnimation.events;
		if( events != null ) {
			var upperLines = 0;
			for( i in 0...events.length ) {
				var el = events[i];
				if( el == null || el.length == 0 ) continue;
				var px = Std.int((i / obj.currentAnimation.frameCount) * W);
				var py = -20;
				var lowest = 0;
				for(j in 0 ... el.length ) {
					var event = events[i][j];
					var tf = new h2d.TextInput(hxd.res.DefaultFont.get(), timeline);
					tf.backgroundColor = 0xFF0000;
					tf.onClick = function(e) {
						if (!tf.hasFocus())
							sceneEditor.view.keys.pushDisable();
						e.propagate = false;
					}
					tf.onFocusLost = function(e) {
						var newName = tf.text;
						var oldName = events[i][j];
						events[i][j] = newName;
						if( newName == "" ) {
							events[i].splice(j,1);
							if( events[i].length == 0 ) events[i] = null;
						}
						buildTimeline();
						buildEventPanel();

						undo.change(Custom(function(undo) {
							if(undo) {
								if (events[i] == null)
									events[i] = [oldName];
								else if (events[i][j] != newName)
									events[i].insert(j, oldName);
								else
									events[i][j] = oldName;
							}
							else {
								events[i][j] = newName;
								if( newName == "" ) {
									events[i].splice(j,1);
									if( events[i].length == 0 ) events[i] = null;
								}
							}

							buildTimeline();
							buildEventPanel();
						}));

						sceneEditor.view.keys.popDisable();
					}
					tf.text = event;
					tf.x = px - Std.int(tf.textWidth * 0.5);
					if( tf.textWidth > 100 && j == 0 ) {
						upperLines++;
						py -= upperLines * 40;
					}
					if( j > 0 )
						upperLines++;
					if( lowest == 0 )
						lowest = py;
					tf.y = py;
					tf.alpha = 0.5;
					py -= 15;
					var dragIcon = new h2d.Bitmap(null, timeline);
					dragIcon.scaleX = 5.0;
					dragIcon.scaleY = 2.0;
					dragIcon.color.set(0.34, 0.43, 0, 1);
					dragIcon.x = px - (dragIcon.scaleX * 0.5 * 5);
					dragIcon.y = py;
					py -= Std.int(dragIcon.scaleY * 5 * 2);
					var dragInter = new h2d.Interactive(5, 5, dragIcon, null );
					dragInter.x = 0;
					dragInter.y = 0;
					var curFrame = i;
					var curPos = (curFrame / obj.currentAnimation.frameCount) * W;
					dragInter.onPush = function(e) {
						if( e.button == 0 ){
							var startFrame = curFrame;
							dragInter.startCapture(function(e) {
								switch( e.kind ) {
								case ERelease:
									dragInter.stopCapture();
									buildTimeline();
									buildEventPanel();
									if( curFrame != startFrame ) {
										undo.change(Custom(function(undo) {
											if(undo) {
												events[curFrame].remove(event);
												events[startFrame].push(event);
											}
											else {
												events[curFrame].push(event);
												events[startFrame].remove(event);
											}

											buildTimeline();
											buildEventPanel();
										}));
									}
								case EMove:
									var newFrame = Math.round(( (curPos + (e.relX - 2.5) * dragIcon.scaleX ) / W ) * obj.currentAnimation.frameCount);
									if( newFrame >= 0 && newFrame <= obj.currentAnimation.frameCount ) {
										events[curFrame].remove(event);
										if(events[newFrame] == null)
											events[newFrame] = [];
										events[newFrame].insert(0, event);
										curFrame = newFrame;
										buildTimeline();
										buildEventPanel();
										@:privateAccess dragInter.scene = scene.s2d;
									}
								default:
								}
							});
						}
					};
				}
				timeline.beginFill(0xC0C0C0,0.8);
				timeline.drawRect(px, lowest + 20, 1, H - (lowest + 20));
			}
		}
	}

	function update(dt:Float) {
		var cam = scene.s3d.camera;
		if( light != null ) {
			if( !sceneEditor.isSelected(plight) )
				lightDirection = light.getLocalDirection();
			else {
				var angle = Math.atan2(cam.target.y - cam.pos.y, cam.target.x - cam.pos.x);
				light.setDirection(new h3d.Vector(
					Math.cos(angle) * lightDirection.x - Math.sin(angle) * lightDirection.y,
					Math.sin(angle) * lightDirection.x + Math.cos(angle) * lightDirection.y,
					lightDirection.z
				));
			}
		}
		if( timeline != null ) {
			timecursor.x = Std.int((obj.currentAnimation.frame / obj.currentAnimation.frameCount) * (scene.s2d.width - timecursor.tile.width));
			frameIndex.text = untyped obj.currentAnimation.frame.toFixed(2);
		}
		if( cameraMove != null )
			cameraMove();

		if (selectedMesh != null) {

			function round(number:Float, ?precision=2): Float
			{
				number *= Math.pow(10, precision);
				return Math.round(number) / Math.pow(10, precision);
			}

			var screenRatio = @:privateAccess selectedMesh.curScreenRatio;
			var line = sceneEditor.properties.element.find(".line");
			var cursor = sceneEditor.properties.element.find(".cursor");
			if (cursor.length > 0) {
				cursor?.css({left: '${line.position().left + line.width() * hxd.Math.clamp((1 - hxd.Math.pow(screenRatio, lodPow)), 0, 1)}px'});
				cursor?.find(".ratio").text('${round(hxd.Math.clamp(hxd.Math.pow(screenRatio, lodPow) * 100, 0, 100), 2)}%');
			}

			var hmd = selectedMesh != null ? Std.downcast(selectedMesh.primitive, h3d.prim.HMDModel) : null;
			if ( hmd != null ) {
				var lodsCountEl = sceneEditor.properties.element.find("#vertexes-count");
				var curLod = hmd.forcedLod >= 0 ? hmd.forcedLod : hmd.screenRatioToLod(@:privateAccess selectedMesh.curScreenRatio);
				var lodVertexesCount = @:privateAccess hmd.lods[curLod].vertexCount;
				lodsCountEl.text(lodVertexesCount);
			}

		}
	}

	public function setRenderPropsEditionVisibility(visible : Bool) {
		if (element == null)
			return;
		var renderPropsEditionEl = this.element.find('.render-props-edition');

		if (!visible) {
			renderPropsEditionEl.css({ display : 'none' });
			return;
		}

		renderPropsEditionEl.css({ display : 'block' });
	}

	static var _ = FileTree.registerExtension(Model,["hmd","fbx"],{ icon : "cube" });

}
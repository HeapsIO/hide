package hide.view;
import hxd.Key as K;

class Model extends FileView {
	static var KEY_ANIM_PLAYING = "AnimationPlaying";

	var tools : hide.comp.Toolbar;
	var obj : h3d.scene.Object;
	var sceneEditor : hide.comp.SceneEditor;
	var tree : hide.comp.FancyTree<Dynamic>;
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
	var ignoreReload : Int = 0;

	var highlightSelection : Bool = true;
	var shader = new h3d.shader.FixedColor(0xffffff);
	var shader2 = new h3d.shader.FixedColor(0xff8000);

	var animSelector : hide.comp.Toolbar.ToolSelect<String>;

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

		var def = new hrt.prefab.Prefab(null, null);
		new hrt.prefab.RenderProps(def, null).name = "renderer";
		var l = new hrt.prefab.Light(def, null);
		sceneEditor = new hide.comp.SceneEditor(this);
		sceneEditor.onSceneReady = onSceneReady;

		sceneEditor.editorDisplay = false;
		sceneEditor.onRefresh = onRefresh;
		sceneEditor.onUpdate = onUpdate;
		sceneEditor.onSelectionChanged = function(elts : Array<hrt.prefab.Prefab>, ?mode : hide.comp.SceneEditor.SelectMode = Default) {
			if (tree != null) tree.clearSelection();
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

		sceneEditor.view.keys.register("model.animPrev", changeAnim.bind(-1));
		sceneEditor.view.keys.register("model.animNext", changeAnim.bind(1));


		sceneEditor.view.keys.register("view.refresh", function() rebuild());
		sceneEditor.view.keys.register("view.refreshApp", function() untyped chrome.runtime.reload());

		sceneEditor.view.keys.register("sceneeditor.radialViewModes", {name: "Radial view modes", category: "Scene"}, function() {
			var renderer = Std.downcast(@:privateAccess scene.s3d.renderer, h3d.scene.pbr.Renderer);
			var shader = @:privateAccess renderer.slides.shader;
			hide.comp.RadialMenu.createFromPoint(ide.mouseX, ide.mouseY, [
				{ label: "Velocity", icon:"adjust", click: () -> { renderer.displayMode = h3d.scene.pbr.Renderer.DisplayMode.Debug; shader.mode = h3d.shader.pbr.Slides.DebugMode.Velocity; } },
				{ label: "Performance", icon:"adjust", click: () -> { renderer.displayMode = h3d.scene.pbr.Renderer.DisplayMode.Performance; } },
				{ label: "Shadows", icon:"adjust", click: () -> { renderer.displayMode = h3d.scene.pbr.Renderer.DisplayMode.Debug; shader.mode = h3d.shader.pbr.Slides.DebugMode.Shadow; } },
				{ label: "AO", icon:"adjust", click: () -> { renderer.displayMode = h3d.scene.pbr.Renderer.DisplayMode.Debug; shader.mode = h3d.shader.pbr.Slides.DebugMode.AO; } },
				{ label: "Emissive", icon:"adjust", click: () -> { renderer.displayMode = h3d.scene.pbr.Renderer.DisplayMode.Debug; shader.mode = h3d.shader.pbr.Slides.DebugMode.Emissive; } },
				{ label: "Metalness", icon:"adjust", click: () -> { renderer.displayMode = h3d.scene.pbr.Renderer.DisplayMode.Debug; shader.mode = h3d.shader.pbr.Slides.DebugMode.Metalness; } },
				{ label: "Roughness", icon:"adjust", click: () -> { renderer.displayMode = h3d.scene.pbr.Renderer.DisplayMode.Debug; shader.mode = h3d.shader.pbr.Slides.DebugMode.Roughness; } },
				{ label: "Normal", icon:"adjust", click: () -> { renderer.displayMode = h3d.scene.pbr.Renderer.DisplayMode.Debug; shader.mode = h3d.shader.pbr.Slides.DebugMode.Normal; } },
				{ label: "Albedo", icon:"adjust", click: () -> { renderer.displayMode = h3d.scene.pbr.Renderer.DisplayMode.Debug; shader.mode = h3d.shader.pbr.Slides.DebugMode.Albedo; } },
				{ label: "Full", icon:"adjust", click: () -> { renderer.displayMode = h3d.scene.pbr.Renderer.DisplayMode.Debug; shader.mode = h3d.shader.pbr.Slides.DebugMode.Full; } },
				{ label: "LIT", icon:"adjust", click: () -> { renderer.displayMode = h3d.scene.pbr.Renderer.DisplayMode.Pbr; } }
			]);
		});

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

	override function save() {

		if(!modified) return;

		// Save render props
		if (Ide.inst.currentConfig.get("sceneeditor.renderprops.edit", false) && sceneEditor.renderPropsRoot != null)
			sceneEditor.renderPropsRoot.save();

		for (o in obj.findAll(o -> Std.downcast(o, h3d.scene.Mesh))) {

			var hmd = Std.downcast(o.primitive, h3d.prim.HMDModel);
			if (hmd == null)
				continue;

			var input : h3d.prim.ModelDatabase.ModelDataInput = {
				resourceDirectory : @:privateAccess hmd.lib.resource.entry.directory,
				resourceName : @:privateAccess hmd.lib.resource.name,
				objectName : o.name,
				hmd : hmd,
				skin : o.find((o) -> Std.downcast(o, h3d.scene.Skin))
			}

			h3d.prim.ModelDatabase.current.saveModelProps(input);
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
		}
		else if (ignoreReload > 0) {
			onRefresh();
		} else {
			super.onFileChanged(wasDeleted, false);
			onRefresh();
		}
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

	// Scene tree bindings
	var def = false;
	static var lodPow : Float = 0.3;
	var selectedMesh : h3d.scene.Mesh = null;
	var displayJoints = null;
	var selectedCount = 0;
	var selectedElements : Array<Dynamic>;
	function onTreeSelectionChanged(elts : Array<Dynamic>) {
		function canMultiEdit<T>(cl : Class<T>) {
			for (e in elts)
				if (!Std.isOfType(e, cl))
					return false;

			return true;
		}

		refreshSelectionHighlight(null);
		selectedElements = elts;

		var properties = sceneEditor.properties;
		properties.clear();

		if (canMultiEdit(h3d.scene.Object))
			onSelectObjects(cast elts);

		if (canMultiEdit(h3d.mat.Material))
			onSelectMaterials(cast elts);

		if (canMultiEdit(h3d.scene.Skin.Joint))
			onSelectJoints(cast elts);
	}

	function onSelectObjects(objs : Array<h3d.scene.Object>) {
		// TODO: manage multi-edit for objects
		if (objs.length != 1)
			return;
		var obj = objs[0];

		var properties = sceneEditor.properties;

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
		var hmd = mesh != null ? Std.downcast(mesh.primitive, h3d.prim.HMDModel) : null;
		var vertexFormat = '';
		if ( mesh != null && mesh.primitive.buffer != null ) {
			for ( i in mesh.primitive.buffer.format.getInputs() )
				vertexFormat += ' ' + i.name;
			vertexFormat = '<dt>Vertex format</dt><dd>$vertexFormat</dd>';
		}
		var colliderInfo = '';
		if ( hmd != null && @:privateAccess hmd.colliderData != null ) {
			var colliderVertex = 0;
			var colliderTriangle = 0;
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
					colliderTriangle += @:privateAccess polygonBuffer.triCount;
					colliderVertex += @:privateAccess Std.int(polygonBuffer.buffer.length / 3);
					return;
				}
				var polygon = Std.downcast(c, h3d.col.Polygon);
				if ( polygon != null ) {
					var t = @:privateAccess polygon.triPlanes;
					while ( t != null ) {
						colliderTriangle += 1;
						colliderVertex += 3;
						t = t.next;
					}
					return;
				}
			}
			recCol(col);

			colliderInfo += '<dt>Collider vertices</dt><dd>$colliderVertex</dd>';
			colliderInfo += '<dt>Collider triangle</dt><dd>$colliderTriangle</dd>';
		}
		var e = properties.add(new Element('
			<div class="group" name="Properties">
				<dl>
					<dt>X</dt><dd><input field="x"/></dd>
					<dt>Y</dt><dd><input field="y"/></dd>
					<dt>Z</dt><dd><input field="z"/></dd>
					<dt>Attach</dt><dd><div class="follow">
					<div class="select">
						<div class="header">
							<span class="label">-- None --</span>
							<div class="icon ico ico-caret-right"></div>
						</div>
						<div class="dropdown"/>
					</div></dd>
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
					' + vertexFormat + colliderInfo +
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

		'),obj);

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
			if (@:privateAccess hmd.lodCount() > 1) {
				var lodsEl = new Element('
					<div class="group lods" name="LODs">
						<dt>LOD Count</dt><dd>${hmd.lodCount()}</dd>
						<dt>Force display LOD</dt>
						<dd>
							<select id="select-lods">
								<option value="-1">None</option>
								${[ for(idx in 0...hmd.lodCount()) '<option value="${idx}">LOD ${idx}</option>'].join("")}
							</select>
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
					if (idx == hmd.lodCount() ) return lodConfig[lodConfig.length - 1];
					if (idx >= hmd.lodCount() + 1) return 0.;
					return lodConfig[idx - 1];
				}

				function getLodRatioFromPx(px : Float) {
					var ratio = 1 - (px / lodsEl.find(".line").width());
					return Math.pow(ratio, 1.0 / lodPow);
				}

				function getLodRatioPowedFromIdx(idx : Int) {
					var lodConfig = hmd.getLodConfig();
					var prev = idx == 0 ? 1 : hxd.Math.pow(lodConfig[idx - 1] , lodPow);
					if ( idx == hmd.lodCount() ) prev = lodConfig[lodConfig.length - 1];
					var c = lodConfig[idx] == null ? 0 : lodConfig[idx];
					if ( idx + 1 == hmd.lodCount() ) c = lodConfig[lodConfig.length - 1];
					return (Math.abs(prev - hxd.Math.pow(c, lodPow)));
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

						var roundedRatio = Std.int(getLodRatioFromIdx(idx) * 10000.) / 100.;
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
				for (idx in 0...(hmd.lodCount() + 1)) {
					var isCulledLod = idx == hmd.lodCount();
					var areaEl = new Element('
					<div class="area">
						<p>${isCulledLod ? 'Culled' : 'LOD&nbsp${idx}'}</p>
						<p id="percent">-%</p>
					</div>');

					if (isCulledLod)
						areaEl.css({ flex : 1 });

					lodsLine.append(areaEl);
					refreshLodLine();

					var widthHandle = 10;
					areaEl.on("mousemove", function(e:js.jquery.Event) {
						if ((e.offsetX <= widthHandle && idx != 0) || (areaEl.width() - e.offsetX) <= widthHandle && idx != hmd.lodCount())
							areaEl.css({ cursor : 'w-resize' });
						else
							areaEl.css({ cursor : 'default' });
					});

					areaEl.on("mousedown", function(e:js.jquery.Event) {
						var firstHandle = e.offsetX <= widthHandle && idx != 0;
						var secondHandle = areaEl.width() - e.offsetX <= widthHandle && idx != hmd.lodCount();

						if (firstHandle || secondHandle) {
							var currIdx = secondHandle ? idx : idx - 1;
							var prevConfig = @:privateAccess hmd.lodConfig?.copy();
							var newConfig = hmd.getLodConfig()?.copy();
							var limits = [ getLodRatioFromIdx(currIdx + 2), getLodRatioFromIdx(currIdx)];

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
			}
		}

		var select = e.find(".follow");
		var header = select.find(".header");
		var dropdown = select.find(".dropdown");
		function onFollowSelected(v : String) {
			var name = v.split(".").pop();
			obj.follow = this.obj.getObjectByName(name);
			header.find('.label').text(name);
		}

		var items: Array<hide.comp.ContextMenu.MenuItem> = [{ label: "-- None --", click: () -> onFollowSelected("-- None --")}];
		for( path in getNamedObjects(obj) ) {
			var parts = path.split(".");
			var name = parts[parts.length - 1];
			var label = [for( p in 1...parts.length ) "&nbsp; "].join("") + parts.pop();
			items.push({ label: label, click: () -> onFollowSelected(name) });
		}

		header.click(function(_) {
			var icon = header.find(".icon");
			var visible = icon.hasClass('ico-caret-down');
			visible = !visible;
			icon.toggleClass("ico-caret-right", !visible);
			icon.toggleClass("ico-caret-down", visible);
			if (visible) {
				var menu = hide.comp.ContextMenu.createDropdown(dropdown.get(0), items, { search: hide.comp.ContextMenu.SearchMode.Visible });
				menu.onClose = () -> {
					icon.toggleClass("ico-caret-right", true);
					icon.toggleClass("ico-caret-down", false);
				};
			}

		});

		refreshSelectionHighlight(obj);
	}

	function onSelectMaterials(mats : Array<h3d.mat.Material>) {
		// TODO: manage multi-edit for materials
		if (mats.length != 1)
			return;
		var m = mats[0];

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
		else {
			def = true;
		}

		var matLibrary = new Element('
			<div class="group" name="Material Library">
				<dt>Library</dt>
				<dd>
					<select class="lib">
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

		function updateBaseEdition() {
			if (def) {
				tex.show();
				matEl.show();
			}
			else {
				tex.hide();
				matEl.hide();
			}
		}

		function updateMatSelect() {
			matSelect.empty();
			new Element('<option value="">None</option>').appendTo(matSelect);

			var libName = "";
			for (matLib in matLibs) {
				if (matLib.path == selectedLib)
					libName = matLib.name;
			}

			materials = scene.listMaterialFromLibrary(getPath(), libName);

			for (idx in 0...materials.length)
				new Element('<option value="${materials[idx].path + "/" + materials[idx].mat.name}" ${(selectedMat == materials[idx].path + "/" + materials[idx].mat.name && !def) ? 'selected' : ''}>${materials[idx].mat.name}</option>').appendTo(matSelect);
		}

		function updateLibSelect() {
			libSelect.empty();
			new Element('<option value="">None</option>').appendTo(libSelect);

			for (lib in matLibs)
				new Element('<option value="${lib.name}" ${(selectedLib == lib.path && !def) ? 'selected' : ''}>${lib.name}</option>').appendTo(libSelect);
		}

		updateLibSelect();
		updateMatSelect();
		updateBaseEdition();

		if ( props != null && props.__refMode != null )
			mode.val((props:Dynamic).__refMode).select();

		libSelect.change(function(e :js.jquery.Event) {
			var prevV = selectedLib;
			selectedLib = null;
			for (matLib in matLibs) {
				if (matLib.name == libSelect.val())
					selectedLib = matLib.path;
			}
			var newV = selectedLib;

			function exec(undo : Bool) {
				selectedLib = undo ? prevV : newV;
				def = selectedLib == "" || selectedLib == null;
				updateLibSelect();
				updateMatSelect();
				updateBaseEdition();
			}

			exec(false);
			undo.change(Custom(exec));
		});

		matSelect.change(function(_) {
			var prevV = selectedMat;
			selectedMat = matSelect.val();
			var newV = selectedMat;

			function exec(undo : Bool) {
				selectedMat = undo ? prevV : newV;
				var mat = Reflect.field(scene.findMat(materials, selectedMat), "mat");
				if ( mat != null ) {
					@:privateAccess mat.update(m, mat.renderProps(), function(path:String) {
						return hxd.res.Loader.currentInstance.load(path).toTexture();
					});
					def = false;
				} else {
					def = true;
				}

				updateLibSelect();
				updateMatSelect();
				updateBaseEdition();
			}

			exec(false);
			undo.change(Custom(exec));
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
			onSelectMaterials(mats);
			undo.change(Field(m, "props", old), onSelectMaterials.bind(mats));
		});
		e.find(".save").click(saveCallback);
	}

	function onSelectJoints(joints : Array<h3d.scene.Skin.Joint>) {
		// Graphic debug for selected joints
		if ( @:privateAccess sceneEditor.jointsGraphics != null )
			sceneEditor.setJoints(true, [for (j in joints) j.name]);

		if (joints.length == 0)
			return;

		var skin = joints[0].skin;

		var dynJointEl = new Element('<div class="group" name="Dynamic bone">
			<dt>Apply changes on children</dt><dd><input id="sync-changes" type="checkbox"/></dd>
			<div class="group dynamic-edition" name="Global parameters">
				<dt>Force</dt><dd class="vector"><input id="force-x" type="number"/><input id="force-y" type="number"/><input id="force-z" type="number"/></dd>
			</div>
			<div class="group" name="Local parameters">
				<dt>Is Dynamic</dt><dd><input id="dynamic" type="checkbox"/></dd>
				<div class="dynamic-edition">
					<dt title="Should dynamic movement be applied on existing animation movement or not">Additive</dt><dd><input type="checkbox" id="additive"/></dd>
					<dt title="Lock axis">Lock axis</dt><dd class="checkboxs"><label>X</label><input type="checkbox" id="lockAxisX"/><label>Y</label><input type="checkbox" id="lockAxisY"/><label>Z</label><input type="checkbox" id="lockAxisZ"/></dd>
					<dt title="Reduction of the amplitude of the oscillation movement">Damping</dt><dd><input id="damping" type="number" step="0.1" min="0" max="1"/></dd>
					<dt title="Reduction factor applied on globale force">Resistance</dt><dd><input id="resistance" type="number" step="0.1" min="0" max="1"/></dd>
					<dt title="Rigidity of the bone">Stiffness</dt><dd><input id="stiffness" type="number" step="0.1" min="0" max="1"/></dd>
					<dt title="Elasticity of the bone">Slackness</dt><dd><input id="slackness" type="number" step="0.1" min="0" max="1"/></dd>
				</div>
			</div>
		</div>');

		// Sync is used to propagate parent changes on children dynamic bones if checked
		var synced = getDisplayState("dynamic-bones-sync");
		if (synced == null)
			synced = false;

		var syncEl = dynJointEl.find("#sync-changes");
		syncEl.get(0).toggleAttribute('checked', synced);
		syncEl.change(function(e) {
			synced = !synced;
			saveDisplayState("dynamic-bones-sync", synced);
		});


		function refreshEdition() {
			var skinData = skin.getSkinData();
			var jointsData = [];
			for (j in joints) {
				for (j2 in skinData.allJoints) {
					if (j.name == j2.name)
						jointsData.push(j2);
				}
			}

			function cloneSkinData() {
				var clone = skinData.allJoints.copy();
				for (idx in 0...skinData.allJoints.length) {
					clone[idx] = Type.createInstance(Type.getClass(clone[idx]), []);
					for (f in Reflect.fields(skinData.allJoints[idx]))
						Reflect.setField(clone[idx], f, Reflect.field(skinData.allJoints[idx], f));
				}

				for (idx in 0...skinData.allJoints.length) {
					clone[idx].parent = clone[skinData.allJoints.indexOf(skinData.allJoints[idx].parent)];
					if (skinData.allJoints[idx].subs == null)
						continue;
					clone[idx].subs = [for (s in skinData.allJoints[idx].subs) clone[skinData.allJoints.indexOf(s)]];
				}

				return clone;
			}

			// Find params that are common to the joints that are selected
			var dynFields = ["damping", "resistance", "stiffness", "slackness", "additive", "lockAxis"];
			var commonProperties : Dynamic = null;
			for (j in jointsData) {
				var dyn = Std.downcast(j?.subs[0], h3d.anim.Skin.DynamicJoint);
				if (commonProperties == null) {
					commonProperties = {
						isDynamic: dyn != null,
						lockAxis: dyn?.lockAxis,
						damping: dyn?.damping,
						resistance: dyn?.resistance,
						stiffness: dyn?.stiffness,
						slackness: dyn?.slackness,
						additive: dyn?.additive
					}
				}
				else {
					for (f in Reflect.fields(commonProperties)) {
						if (f == "isDynamic") {
							if ((dyn != null) != Reflect.field(commonProperties, f))
								Reflect.deleteField(commonProperties, "isDynamic");
							continue;
						}

						if (Reflect.field(dyn, f) != Reflect.field(commonProperties, f))
							Reflect.deleteField(commonProperties, f);
					}
				}
			}

			dynJointEl.find("#dynamic");
			var isDynEl = dynJointEl.find("#dynamic");
			if (Reflect.hasField(commonProperties, "isDynamic")) {
				isDynEl.prop('checked', Reflect.field(commonProperties, "isDynamic"));
				isDynEl.removeClass("indeterminate");
			}
			else {
				isDynEl.addClass("indeterminate");
			}

			isDynEl.change(function(e) {
				function toggleDynamicJoint(j : h3d.anim.Skin.Joint, isDynamic : Bool) {
					var newJ = isDynamic ? new h3d.anim.Skin.DynamicJoint() : new h3d.anim.Skin.Joint();
					newJ.index = j.index;
					newJ.name = j.name;
					newJ.bindIndex = j.bindIndex;
					newJ.splitIndex = j.splitIndex;
					newJ.defMat = j.defMat;
					newJ.transPos = j.transPos;
					newJ.parent = j.parent;
					newJ.follow = j.follow;
					newJ.subs = j.subs;
					newJ.offsets = j.offsets;
					newJ.offsetRay = j.offsetRay;
					newJ.retargetAnim = j.retargetAnim;
					skinData.allJoints[j.index] = newJ;

					var idx = j.parent?.subs.indexOf(j);
					j.parent?.subs.remove(j);
					j.parent?.subs.insert(idx, newJ);
					if (j.subs != null)
						for (sub in j.subs)
							sub.parent = newJ;

					if (!isDynamic) {
						// Dynamic bone can't exist with a non-dynamic parent. Check
						// whether or not a sibling bone is dynamic too (meaning that
						// we can't set parent to static bone)

						if (j.parent != null) {
							for (idx in 0...j.parent.subs.length) {
								if (Std.isOfType(j.parent.subs[idx], h3d.anim.Skin.DynamicJoint))
									toggleDynamicJoint(j.parent.subs[idx], isDynamic);
							}

							if (Std.isOfType(j.parent, h3d.anim.Skin.DynamicJoint))
								toggleDynamicJoint(j.parent, isDynamic);
						}

						if (synced) {
							for (idx in 0...j.subs.length)
								toggleDynamicJoint(j.subs[idx], isDynamic);
						}
					}
					else {
						for (idx in 0...j.subs.length)
							toggleDynamicJoint(j.subs[idx], isDynamic);
					}

				}

				var v : Dynamic = isDynEl.is(':checked');
				var oldValues = cloneSkinData();
				for (j in jointsData)
					for (s in j.subs)
						if (!(Std.isOfType(s, h3d.anim.Skin.DynamicJoint) && v))
							toggleDynamicJoint(s, v);
				skin.setSkinData(skinData);
				var newValues = cloneSkinData();
				refreshEdition();

				function exec(undo) {
					for (idx in 0...skinData.allJoints.length)
						skinData.allJoints[idx] = undo ? oldValues[idx] : newValues[idx];
					skin.setSkinData(skinData);
					refreshEdition();
				}

				sceneEditor.properties.undo.change(Custom(exec));
			});

			// Hide dynamic edition in certain cases
			dynJointEl.show();
			dynJointEl.find(".dynamic-edition").show();
			if (!Reflect.field(commonProperties, "isDynamic"))
				dynJointEl.find(".dynamic-edition").hide();
			for (j in jointsData)
				if (j?.subs[0] == null)
					dynJointEl.hide();

			// Edition of dynamic joints params
			var dynJoin = Std.downcast(jointsData[0]?.subs[0], h3d.anim.Skin.DynamicJoint);
			if (dynJoin != null) {
				for (param in dynFields) {
					var el = dynJointEl.find('#$param');
					var isBoolean = el.is(':checkbox');
					if (Reflect.hasField(commonProperties, param)) {
						if (param == "lockAxis") {
							for (f in ["X", "Y", "Z"]) {
								el = dynJointEl.find('#$param'+f);
								el.prop("checked", Reflect.field(Reflect.field(dynJoin, param), f.toLowerCase()) == 1);
								el.removeClass("indeterminate");
							}
						}
						else {
							if (isBoolean) {
								el.prop("checked", Reflect.field(dynJoin, param));
								el.removeClass("indeterminate");
							}
							else
								el.val(Reflect.field(dynJoin, param));
						}
					}
					else {
						if (param == "lockAxis") {
							for (f in ["X", "Y", "Z"]) {
								el = dynJointEl.find('#$param'+f);
								el.addClass("indeterminate");
							}
						}
						else {
							if (isBoolean) {
								el.addClass("indeterminate");
							}
							else {
								el.attr("placeholder", "-");
								el.val("");
							}
						}
					}

					function onChange(e) {
						function apply(j : h3d.anim.Skin.Joint, param : String, v : Dynamic) {
							Reflect.setField(j, param, v);
							if (synced && j.subs != null) {
								for (s in j.subs)
									apply(s, param, v);
							}
						}

						var v : Dynamic = isBoolean ? el.is(':checked') : Std.parseFloat(el.val());
						if (param == "lockAxis") {
							v = new h3d.Vector(dynJointEl.find("#lockAxisX").is(':checked') ? 1 : 0,
							dynJointEl.find("#lockAxisY").is(':checked') ? 1 : 0,
							dynJointEl.find("#lockAxisZ").is(':checked') ? 1 : 0);
						}

						var oldValues = cloneSkinData();
						for (j in jointsData)
							for (s in j.subs)
								apply(s, param, v);
						var newValues = cloneSkinData();

						function exec(undo) {
							for (idx in 0...skinData.allJoints.length)
								skinData.allJoints[idx] = undo ? oldValues[idx] : newValues[idx];
							skin.setSkinData(skinData);
							refreshEdition();
						}

						sceneEditor.properties.undo.change(Custom(exec));
					}

					if (param == "lockAxis") {
						for (f in ["X", "Y", "Z"]) {
							el = dynJointEl.find('#$param'+f);
							el.change(onChange);
						}
					}
					else {
						el.change(onChange);
					}
				}

				var forceEl = dynJointEl.find(".vector");
				var xEl = forceEl.find("#force-x");
				xEl.val(dynJoin.globalForce.x);
				var yEl = forceEl.find("#force-y");
				yEl.val(dynJoin.globalForce.y);
				var zEl = forceEl.find("#force-z");
				zEl.val(dynJoin.globalForce.z);

				function onForceChanged() {
					var newGlobalForce = new h3d.Vector(Std.parseFloat(xEl.val()), Std.parseFloat(yEl.val()), Std.parseFloat(zEl.val()));
					var oldGlobalForce = new h3d.Vector(0, 0, 0);
					for (s in skinData.allJoints) {
						var d = Std.downcast(s, h3d.anim.Skin.DynamicJoint);
						if (d == null)
							continue;

						oldGlobalForce.load(d.globalForce);
						break;
					}

					function exec(undo) {
						var force = undo ? oldGlobalForce : newGlobalForce;
						for (s in skinData.allJoints) {
							var d = Std.downcast(s, h3d.anim.Skin.DynamicJoint);
							if (d != null)
								d.globalForce.load(force);
						}

						xEl.val(force.x);
						yEl.val(force.y);
						zEl.val(force.z);
					}
					exec(false);
					sceneEditor.properties.undo.change(Custom(exec));
				}

				xEl.change((e) -> onForceChanged());
				yEl.change((e) -> onForceChanged());
				zEl.change((e) -> onForceChanged());
			}
		}

		refreshEdition();

		sceneEditor.properties.add(dynJointEl, null, function(pname) {});
	}


	// Scene editor bindings
	inline function get_scene() return sceneEditor.scene;

	function onSceneReady() {
		root = new hrt.prefab.Prefab(null, null);
		sceneEditor.setPrefab(root);
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

		if (sceneEditor.renderPropsRoot != null) {
			@:privateAccess sceneEditor.removeInstance(sceneEditor.renderPropsRoot);
			sceneEditor.renderPropsRoot = null;
		}

		@:privateAccess sceneEditor.queueRefreshRenderProps();

		if (sceneEditor.renderPropsRoot != null && sceneEditor.renderPropsRoot.source != null)
			root.children.push(sceneEditor.renderPropsRoot);

		// Create default render props if no render props has been created yet
		var r = root.getOpt(hrt.prefab.RenderProps, true);
		if( r == null && sceneEditor.renderPropsRoot == null) {
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
				if (obj.toMesh().primitive?.buffer != null) {
					obj.toMesh().primitive.buffer.dispose();
				}
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
		tree = new hide.comp.FancyTree<Dynamic>(overlay);
		tree.element.addClass("overlay");
		tree.getChildren = (item: Dynamic) -> {
			if (item == null)
				return [obj.name == null ? @:privateAccess obj.children[0] : obj];

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
		tree.getName = (item: Dynamic) -> {
			var obj = Std.downcast(item, h3d.scene.Object);
			if (obj != null) return obj.name;

			var mat = Std.downcast(item, h3d.mat.Material);
			if (mat != null) return mat.name;

			var join = Std.downcast(item, h3d.scene.Skin.Joint);
			if (join != null) return join.name;

			return "";
		};
		tree.getUniqueName = (item: Dynamic) -> {
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
		tree.getIcon = (item: Dynamic) -> {
			var skin = Std.downcast(item, h3d.anim.Skin);
			if (skin != null) return '<div class="ico ico-male"></div>';

			var mat = Std.downcast(item, h3d.mat.Material);
			if (mat != null) return '<div class="ico ico-photo"></div>';

			var join = Std.downcast(item, h3d.scene.Skin.Joint);
			if (join != null) return '<div class="ico ico-male"></div>';

			var obj = Std.downcast(item, h3d.scene.Object);
			if (obj != null) return '<div class="ico ico-gg"></div>';

			return null;
		};
		tree.onSelectionChanged = (enterKey : Bool) -> {
			var selection = tree.getSelectedItems();
			onTreeSelectionChanged(selection);
		};
		tree.onDoubleClick = (item: Dynamic) -> {
			var obj = Std.downcast(item, h3d.scene.Object);
			if (obj == null) return;
			sceneEditor.focusObjects([obj]);
		};
		function ctxMenu(item : Dynamic, event : js.html.MouseEvent) {
			event.preventDefault();
			var menuItems : Array<hide.comp.ContextMenu.MenuItem> = [
				{ label : "Merge selected", enabled : false /*canMergeElements(selectedElements)*/, click: () -> mergeModels(cast selectedElements) },
				{ label : "Merge all meshes", enabled : true, click: () -> mergeModels(cast [for (m in obj.findAll(o -> Std.downcast(o, h3d.scene.Mesh))) m]) },
			];

			hide.comp.ContextMenu.createFromEvent(cast event, menuItems);
		};
		tree.onContextMenu = ctxMenu;
		tree.rebuildTree();
		tree.openItem(obj, true);

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
			this.animSelector = sel;
			var content = [for( a in anims ) {
				var label = scene.animationName(a);
				{ label : label, value : a }
			}];
			content.unshift({ label : "-- no anim --", value : null });
			sel.setContent(content);
			sel.element.find(".label").text(content[selIdx].label);
			sel.onSelect = function(file:String) {
				if (scene.editor.view.modified && !js.Browser.window.confirm("Current animation has been modified, change animation without saving?"))
				{
					var idx = anims.indexOf(currentAnimation.file)+1;
					sel.element.find(".label").text(content[idx].label);
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

	function changeAnim(offset: Int) : Void {
		var anims = scene.listAnims(getPath());

		if (anims == null)
			return;

		var index = anims.indexOf(currentAnimation.file);
		index = (index + anims.length + offset) % anims.length;

		setAnimation(anims[index]);
		animSelector.element.find(".label").text(currentAnimation.name);
	}

	function onUpdate(dt:Float) {
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

			function round(number:Float, ?precision=2) : Float {
				number *= Math.pow(10, precision);
				return Math.round(number) / Math.pow(10, precision);
			}

			var screenRatio = @:privateAccess selectedMesh.curScreenRatio;
			var line = sceneEditor.properties.element.find(".line");
			var cursor = sceneEditor.properties.element.find(".cursor");
			if (cursor.length > 0) {
				cursor?.css({left: '${line.position().left + line.width() * hxd.Math.clamp((1 - hxd.Math.pow(screenRatio, lodPow)), 0, 1)}px'});
				cursor?.find(".ratio").text('${round(hxd.Math.clamp(screenRatio * 100, 0, 100), 2)}%');
			}

			var hmd = selectedMesh != null ? Std.downcast(selectedMesh.primitive, h3d.prim.HMDModel) : null;
			if ( hmd != null ) {
				var lodsCountEl = sceneEditor.properties.element.find("#vertexes-count");
				var curLod = hmd.forcedLod >= 0 ? hmd.forcedLod : hmd.screenRatioToLod(@:privateAccess selectedMesh.curScreenRatio);
				var lodVertexesCount = @:privateAccess { ( curLod < hmd.lods.length ) ? hmd.lods[curLod].vertexCount : 0; };
				lodsCountEl.text(lodVertexesCount);
			}

		}
	}


	function canMergeElements(objects : Array<Dynamic>) {
		if (objects == null || objects.length <= 1)
			return false;

		var format : hxd.BufferFormat = null;
		for (o in objects) {
			var m = Std.downcast(o, h3d.scene.Mesh);
			if (m == null)
				return false;
			if (format == null)
				format = m.primitive.buffer.format;
			if (format != m.primitive.buffer.format)
				return false;
		}

		return true;
	}

	function mergeModels(models : Array<h3d.scene.Object>) {
		var relFilePath = ".tmp/tmp.hmd";
		var tmpFilePath = ide.resourceDir + '/$relFilePath';

		function merge(m1: h3d.scene.Mesh, m2: h3d.scene.Mesh, format: hxd.BufferFormat) : h3d.scene.Mesh {
			var p1 = Std.downcast(m1.primitive, h3d.prim.HMDModel);
			var p2 = Std.downcast(m2.primitive, h3d.prim.HMDModel);

			if (p1 == null || p2 == null)
				throw "Can't merge non-HMDModels";

			// Creation of the merged HMD
			var hmd = new hxd.fmt.hmd.Data();
			hmd.version = hxd.fmt.hmd.Data.CURRENT_VERSION;
			hmd.geometries = [];
			hmd.materials = [];
			hmd.models = [];
			hmd.animations = [];
			hmd.shapes = [];

			var maxLod = Std.int(hxd.Math.max(p1.lodCount(), p2.lodCount()));
			var modelName = m1.name + "_" + m2.name;

			var model = new hxd.fmt.hmd.Data.Model();
			model.name = modelName;
			model.name = model.toLODName(0);
			model.geometry = 0;
			model.materials = [];
			model.parent = -1;
			model.position = new hxd.fmt.hmd.Data.Position();
			model.position.x = 0;
			model.position.y = 0;
			model.position.z = 0;
			model.position.sx = 1;
			model.position.sy = 1;
			model.position.sz = 1;
			model.position.qx = 0;
			model.position.qy = 0;
			model.position.qz = 0;
			model.lods = [];
			if (model.props == null) model.props = [];
			model.props.push(HasLod);
			hmd.models.push(model);

			var mat1 = m1.getMaterials();
			var mat2 = m2.getMaterials();
			var indexCounts = [];
			var totalCount = 0;
			var remap : Array<Array<{ count : Int, offset : Int }>> = [];
			for (mIdx in 0...(mat1.length + mat2.length)) {
				var indexCount = mIdx < mat1.length ? p1.getMaterialIndexCount(mIdx) : p2.getMaterialIndexCount(mIdx - mat1.length);
				var m = mIdx < mat1.length ? mat1[mIdx] : mat2[mIdx - mat1.length];
				var mId = -1;
				for (id in model.materials) {
					if (hmd.materials[id].name == m.name)
						mId = id;
				}

				if (mId != -1) {
					indexCounts[mId] += indexCount;
					remap[mId].push({ count: indexCount, offset: totalCount });
					totalCount += indexCount;
					continue;
				}

				mId = hmd.materials.length;

				var matData : hxd.fmt.hmd.Data.Material = null;
				@:privateAccess {
					for (dataIdx in 0...(p1.lib.header.materials.length + p2.lib.header.materials.length)) {
						matData = dataIdx < p1.lib.header.materials.length ? p1.lib.header.materials[dataIdx] :  p1.lib.header.materials[dataIdx - p1.lib.header.materials.length];
						if (matData.name == m.name)
							break;
					}
				}

				remap[mId] = [{ count: indexCount, offset: totalCount }];
				indexCounts.push(indexCount);
				hmd.materials.push(matData);
				model.materials.push(mId);
				totalCount += indexCount;
			}

			var dataOut = new haxe.io.BytesOutput();
			var totalVertexCount = 0;
			for (lodIdx in 0...maxLod) {
				var newFormat = hxd.BufferFormat.make([for (i in format.getInputs()) i]);
				var d1 = hxd.fmt.fbx.Writer.getPrimitiveInfos(p1, newFormat, lodIdx);
				var d2 = hxd.fmt.fbx.Writer.getPrimitiveInfos(p2, newFormat, lodIdx);
				totalVertexCount += Std.int((d1.vertexBuffer.length + d2.vertexBuffer.length) / d1.vertexFormat.stride);
			}

			var is32 = totalVertexCount > 0x10000;
			for (lodIdx in 0...maxLod) {
				var newFormat = hxd.BufferFormat.make([for (i in format.getInputs()) i]);

				var d1 = hxd.fmt.fbx.Writer.getPrimitiveInfos(p1, newFormat, lodIdx);
				var d2 = hxd.fmt.fbx.Writer.getPrimitiveInfos(p2, newFormat, lodIdx);

				var vertexCount = Std.int((d1.vertexBuffer.length + d2.vertexBuffer.length) / d1.vertexFormat.stride);
				var indexCount = d1.indexesBuffer.length + d2.indexesBuffer.length;

				var g = new hxd.fmt.hmd.Data.Geometry();
				g.bounds = new h3d.col.Bounds();
				g.indexCounts = indexCounts;
				g.vertexCount = vertexCount;
				g.vertexFormat = newFormat;
				g.vertexPosition = dataOut.length;
				hmd.geometries.push(g);

				if (lodIdx > 0) {
					var lodModel = new hxd.fmt.hmd.Data.Model();
					lodModel.name = modelName;
					lodModel.name = lodModel.toLODName(lodIdx);
					lodModel.parent = model.parent;
					lodModel.follow = model.follow;
					lodModel.position = model.position;
					lodModel.materials = model.materials;
					lodModel.skin = model.skin;
					lodModel.lods = [];
					lodModel.geometry = hmd.geometries.length - 1;
					if (lodModel.props == null) lodModel.props = [];
					lodModel.props.push(HasLod);
					hmd.models.push(lodModel);
					model.lods.push(hmd.models.length - 1);
				}

				var idx = 0;
				while (idx < vertexCount * g.vertexFormat.stride) {
					function get(vIdx: Int) {
						if (vIdx < d1.vertexBuffer.length)
							return d1.vertexBuffer[vIdx];
						else
							return d2.vertexBuffer[vIdx - d1.vertexBuffer.length];
					}

					for (i in g.vertexFormat.getInputs()) {
						var prec = i.precision;
						var size = i.type.getSize();
						if (i.name == "position") {
							var pos = new h3d.Vector(get(idx), get(idx + 1), get(idx + 2));
							var trs = idx < d1.vertexBuffer.length ? m1.defaultTransform : m2.defaultTransform;
							pos.transform(trs);
							hxd.fmt.fbx.HMDOut.writePrec(dataOut, pos.x, prec);
							hxd.fmt.fbx.HMDOut.writePrec(dataOut, pos.y, prec);
							hxd.fmt.fbx.HMDOut.writePrec(dataOut, pos.z, prec);
						}
						else {
							for (idx2 in 0...size)
								hxd.fmt.fbx.HMDOut.writePrec(dataOut, get(idx + idx2), prec);
						}

						hxd.fmt.fbx.HMDOut.flushPrec(dataOut, prec, size);
						idx += size;
					}
				}

				g.indexPosition = dataOut.length;
				function get(vIdx: Int) {
					if (vIdx < d1.indexesBuffer.length) {
						return d1.indexesBuffer[vIdx];
					}
					else
						return d2.indexesBuffer[vIdx - d1.indexesBuffer.length] + Std.int(d1.vertexBuffer.length / g.vertexFormat.stride);
				}

				for (r in remap) {
					for (i in r) {
						for (idx in 0...i.count) {
							var realIdx = idx + i.offset;
							if (is32)
								dataOut.writeInt32(get(realIdx));
							else
								dataOut.writeUInt16(get(realIdx));
						}
					}
				}
			}

			hmd.data = dataOut.getBytes();

			var out = new haxe.io.BytesOutput();
			var w = new hxd.fmt.hmd.Writer(out);
			w.write(hmd);

			var bytes = out.getBytes();
			sys.io.File.saveBytes(tmpFilePath, bytes);

			// Reload library
			var lib = hxd.res.Loader.currentInstance.load(relFilePath).toModel().toHmd();
			var mesh = lib.makeObject();
			lib.dispose();
			return cast mesh;
		}

		var filePath = Ide.inst.getPath(state.path);
		var oldData = sys.io.File.getContent(filePath);

		var meshes : Array<h3d.scene.Mesh> = cast models;
		var format = meshes[0].primitive.buffer.format;
		var tmp : h3d.scene.Mesh = meshes[0];
		for (idx => m in meshes) {
			if (idx == 0) {
				tmp = m;
				continue;
			}
			tmp = merge(tmp, m, format);
		}

		function onDone() {
			ignoreReload++;
			Ide.inst.quickMessage('Successfully merged objects at path : ${filePath}');

			var newData = sys.io.File.getContent(filePath);
			undo.change(Custom((undo) -> {
				sys.io.File.saveContent(filePath, undo ? oldData : newData);
			}), null);
		}

		// Export merge objects
		meshes = [tmp];
		var params = { forward:"0", forwardSign:"1", up:"2", upSign:"1" };
		new hxd.fmt.fbx.Writer(null).export(
			cast meshes,
			Ide.inst.getPath(filePath),
			onDone,
			params);
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
		var path = config.get("hmd.savePropsByAnimation", true) ? currentAnimation.file : getPath();
		var parts = path.split(".");
		parts.pop();
		parts.push("props");
		return ide.getPath(parts.join("."));
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
		var animData = hideData.animations?.get(currentAnimation.file.split("/").pop());
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
						if (@:privateAccess sceneEditor.view.keys.disabledStack == 0)
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

	static var _ = FileTree.registerExtension(Model,["hmd","fbx"],{ icon : "cube", name: "Model" });

}
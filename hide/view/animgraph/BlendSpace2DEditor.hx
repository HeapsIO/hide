package hide.view.animgraph;

class BlendSpacePreviewSettings {
    public var modelPath: String = null;

    public function new() {};
}

@:access(hrt.animgraph.BlendSpace2D)
class BlendSpace2DEditor extends hide.view.FileView {
	var root : hide.Element;
	var previewContainer : hide.Element;
	var graphContainer : hide.Element;
	var propertiesContainer : hide.Element;
	var mainPanel : hide.Element;

	var scenePreview : hide.comp.ScenePreview;
	var scenePreviewReady = false;
	var previewModel : h3d.scene.Object = null;
	var propsEditor : hide.comp.PropsEditor;

	var blendSpace2D: hrt.animgraph.BlendSpace2D;

	var graph : hide.comp.SVG;

	var graphPoints : Array<js.html.svg.GElement> = [];
	var hoverPoint : Int = -1;
	var selectedPoint : Int = -1;

	var previewAxis : h2d.col.Point = new h2d.col.Point();

	var startMovePos : h2d.col.Point = null;

	var previewSettings : BlendSpacePreviewSettings;

	static final pointRadius = 8;
	var subdivs = 5;

	var animPreview : hrt.animgraph.AnimGraphInstance;

	inline function getPointPos(clientX : Float, clientY : Float, snap: Bool) : h2d.col.Point {
		var x = hxd.Math.clamp(graphXToLocal(clientX), blendSpace2D.minX, blendSpace2D.maxX);
		var y = hxd.Math.clamp(graphYToLocal(clientY), blendSpace2D.minY, blendSpace2D.maxY);

		if (snap) {
			// Snap to grid
			var dx = (x - blendSpace2D.minX) / (blendSpace2D.maxX - blendSpace2D.minX);
			dx = hxd.Math.round(dx * (subdivs+1)) / (subdivs+1);
			x = hxd.Math.lerp(blendSpace2D.minX, blendSpace2D.maxX, dx);

			var dy = (y - blendSpace2D.minY) / (blendSpace2D.maxY - blendSpace2D.minY);
			dy = hxd.Math.round(dy * (subdivs+1)) / (subdivs+1);
			y = hxd.Math.lerp(blendSpace2D.minY, blendSpace2D.maxY, dy);
		}

		return inline new h2d.col.Point(x, y);
	}

	override function onDisplay() {
		previewModel = null;
		animPreview = null;
		blendSpace2D = Std.downcast(hide.Ide.inst.loadPrefab(state.path, null,  true), hrt.animgraph.BlendSpace2D);
		if (blendSpace2D == null)
			throw "Invalid blendSpace2D";
		super.onDisplay();
		if (blendSpace2D.animFolder == null) {
			element.html('');
			element.append(AnimGraphEditor.createChooseFolderPrompt(new haxe.io.Path(this.state.path).dir, (path: String) -> {
				blendSpace2D.animFolder = path;
				save();
				onDisplay();
			}));
			return;
		}

		element.html("");

		root = new hide.Element("<blend-space-2d-root></blend-space-2d-root>").appendTo(element);
		mainPanel = new hide.Element("<main-panel></main-panel>").appendTo(root);
		{
			previewContainer = new hide.Element("<preview-container></preview-container>").appendTo(mainPanel);
			graphContainer = new hide.Element("<graph-container></graph-container>").appendTo(mainPanel);
			var panel = new hide.comp.ResizablePanel(Vertical, graphContainer);
			panel.saveDisplayKey = "graphPanel";
			{
				graph = new hide.comp.SVG(graphContainer);

				//graph.rect(graph.element, -1,-1,1,1, {fill: "red"});
				//graph.circle(graph.element, 0, 0, 0.2, {fill: "blue"});

				var movedPoint = -1;
				var movingPreview = false;
				var svg: js.html.svg.SVGElement = cast graph.element.get(0);

				svg.onpointerdown = (e:js.html.PointerEvent) -> {
					if (e.button != 0)
						return;

					if (e.ctrlKey) {
						movingPreview = true;
						var pt = getPointPos(e.clientX, e.clientY, false);

						previewAxis.x = pt.x;
						previewAxis.y = pt.y;
						updatePreviewAxis();
					}

					if (!movingPreview) {
						movedPoint = hoverPoint;
						if (selectedPoint != hoverPoint) {
							setSelection(hoverPoint);
						}

						if (movedPoint == -1)
							return;
					}

					svg.setPointerCapture(e.pointerId);
					e.preventDefault();
				}

				svg.onpointermove = (e:js.html.PointerEvent) -> {
					if (movingPreview) {
						var pt = getPointPos(e.clientX, e.clientY, false);

						previewAxis.x = pt.x;
						previewAxis.y = pt.y;
						updatePreviewAxis();
						return;
					}

					if (movedPoint == -1) {
						var mouse = inline new h2d.col.Point(e.clientX - cachedRect.x, e.clientY - cachedRect.y);

						hoverPoint = -1;
						for (id => point in blendSpace2D.points) {
							var pt = inline new h2d.col.Point(localXToGraph(point.x), localYToGraph(point.y));
							if (mouse.distanceSq(pt) < pointRadius * pointRadius) {
								hoverPoint = id;
								break;
							}
						}
					}

					if (movedPoint != -1) {
						if (startMovePos == null) {
							startMovePos = new h2d.col.Point(blendSpace2D.points[movedPoint].x, blendSpace2D.points[movedPoint].y);
						}

						var mouse = inline new h2d.col.Point(graphXToLocal(e.clientX), graphYToLocal(e.clientY));

						var pt = getPointPos(e.clientX, e.clientY, !e.altKey);

						blendSpace2D.points[movedPoint].x = pt.x;
						blendSpace2D.points[movedPoint].y = pt.y;

						blendSpace2D.triangulate();
						refreshPreviewAnimation();
					}

					refreshGraph();
				}

				svg.onpointerup = (e:js.html.PointerEvent) -> {
					if (movingPreview) {
						movingPreview = false;
						refreshPropertiesPannel();
						return;
					}

					if (movedPoint == -1)
						return;

					if (startMovePos != null) {
						var ptId = movedPoint;
						var saveX = blendSpace2D.points[ptId].x;
						var saveY = blendSpace2D.points[ptId].y;
						var old = startMovePos;
						startMovePos = null;
						function exec(isUndo: Bool) {
							if (!isUndo) {
								blendSpace2D.points[ptId].x = saveX;
								blendSpace2D.points[ptId].y = saveY;
							} else {
								blendSpace2D.points[ptId].x = old.x;
								blendSpace2D.points[ptId].y = old.y;
							}

							blendSpace2D.triangulate();
							refreshGraph();
							refreshPropertiesPannel();
							refreshPreviewAnimation();
						}

						undo.change(Custom(exec));
						refreshPropertiesPannel();
					}

					movedPoint = -1;
				}

				svg.oncontextmenu = (e:js.html.MouseEvent) -> {
					e.preventDefault();

					var options : Array<hide.comp.ContextMenu.MenuItem> = [];

					if (hoverPoint > -1) {
						var toDel = hoverPoint > -1 ? hoverPoint : selectedPoint;
						options.push({
							label: "Delete",
							click: () -> {
								deletePoint(toDel);
							}
						});
					}
					else {
						selectedPoint = -1;
						var x = e.clientX;
						var y = e.clientY;
						var ctrl = e.ctrlKey;

						options.push({
							label: "Add point",
							click: () -> {
								var pt = getPointPos(x, y, !ctrl);
								var pt2 : hrt.animgraph.BlendSpace2D.BlendSpacePoint = {
									x: pt.x,
									y: pt.y,
									speed: 1.0,
									animPath: "",
								};
								addPoint(pt2);
							}
						});

					}

					hide.comp.ContextMenu.createFromEvent(e, options);
				}

				svg.ondragover = (e:js.html.DragEvent) -> {
					if (e.dataTransfer.types.contains(AnimList.dragEventKey)) {
						e.preventDefault();
					}
				}

				svg.ondrop = (e:js.html.DragEvent) -> {
					if (e.dataTransfer.types.contains(AnimList.dragEventKey)) {
						e.preventDefault();

							var pos = getPointPos(e.clientX, e.clientY, true);
							addPoint({x: pos.x, y: pos.y, animPath: e.dataTransfer.getData(AnimList.dragEventKey)}, true);
					}
				}
			}
			panel.onResize = refreshGraph;

			scenePreview = new hide.comp.ScenePreview(config, previewContainer, null, saveDisplayKey + "/preview");
			scenePreview.listLoadableMeshes = () -> {
				var ret : Array<{label: String, path: String}> = [];
				var list = AnimGraphEditor.gatherAllPreviewModels(blendSpace2D.animFolder);
				for (path in list) {
					ret.push({label: StringTools.replace(path, blendSpace2D.animFolder + "/", ""), path: path});
				}
				return ret;
			}
			scenePreviewReady = false;
			scenePreview.element.addClass("scene-preview");

			scenePreview.onReady = onScenePreviewReady;
			scenePreview.onUpdate = onScenePreviewUpdate;
			scenePreview.onObjectLoaded = () -> {
				previewModel = scenePreview.prefab?.find(hrt.prefab.Model, (f) -> StringTools.startsWith(f.source, blendSpace2D.animFolder))?.local3d;
				refreshPreviewAnimation();
			}
		}

		propertiesContainer = new hide.Element("<properties-container></properties-container>").appendTo(root);
		{
			var paramContainer = new Element('<parameters-container></parameters-container>').appendTo(propertiesContainer);
			new Element("<h1>Parameters</h1>").appendTo(paramContainer);
			propsEditor = new hide.comp.PropsEditor(undo, paramContainer);
			refreshPropertiesPannel();
		}
		refreshGraph();

		keys.register("delete", deleteSelection);
	}

    override function buildTabMenu():Array<hide.comp.ContextMenu.MenuItem> {
        var menu = super.buildTabMenu();
        menu.push({isSeparator: true});
        menu.push({label: "Reset Model Folder", click: () -> {
            if (ide.confirm("Warning, resetting the model folder could lead to incorrect animations. Are you sure you want to proceed ?")) {
                blendSpace2D.animFolder = null;
                save();
                onDisplay();
            }
        }});

        return menu;
    }

	override function getDefaultContent():haxe.io.Bytes {
		var animgraph = (new hrt.animgraph.BlendSpace2D(null, null)).serialize();
		return haxe.io.Bytes.ofString(ide.toJSON(animgraph));
	}

	function refreshPreviewAnimation() {
		if (previewModel != null) {
			if (animPreview == null) {
				var blendSpaceNode = new hrt.animgraph.nodes.BlendSpace2D.BlendSpace2D();
				@:privateAccess blendSpaceNode.blendSpace = blendSpace2D;
				animPreview = new hrt.animgraph.AnimGraphInstance(blendSpaceNode, "", 1000, 1.0/60.0);
				@:privateAccess animPreview.editorSkipClone = true;
				cast previewModel.playAnimation(animPreview);
			}
			else @:privateAccess {
				var root : hrt.animgraph.nodes.BlendSpace2D.BlendSpace2D = cast @:privateAccess animPreview.rootNode;
				var old = root.points[0]?.animInfo?.anim.frame;

				// if the anim or the mesh changed between the last refreshPreviewAnimation
				if (previewModel.currentAnimation == animPreview) {
					animPreview.bind(previewModel);
				} else {
					previewModel.playAnimation(animPreview);
				}
				if (old != null) {
					for (point in root.points) {
						if (point.animInfo != null) {
							point.animInfo.anim.setFrame(old);
						}
					}
				}
			}
		}
	}

	function deleteSelection() {
		if (selectedPoint != -1) {
			deletePoint(selectedPoint);
			setSelection(-1);
		}
	}

	function refreshPropertiesPannel() {
		propsEditor.clear();


		propsEditor.add(new hide.Element('
		<div class="group" name="BlendSpace">
			<dl>
				<dt>Min/MaxX</dt><dd><input type="number" field="minX"/><input type="number" field="maxX"/></dd>
				<dt>Min/MaxY</dt><dd><input type="number" field="minY"/><input type="number" field="maxY"/></dd>
			</dl>
		</div>
		'), blendSpace2D, (_) -> {
			refreshGraph();
		});

		if (selectedPoint != -1) {
			var editor = new hide.Element('
				<div class="group" name="Point">
					<dl>
						<dt>X</dt><dd><input type="range" min="0.0" max="1.0" field="x"/></dd>
						<dt>Y</dt><dd><input type="range" min="0.0" max="1.0" field="y"/></dd>
						<dt>Anim speed</dt><dd><input type="range" min="0.1" max="2.0" field="speed"/></dd>
					</dl>
				</div>
			');

			propsEditor.add(editor, blendSpace2D.points[selectedPoint], (_) -> {
				blendSpace2D.triangulate();
				refreshGraph();
				refreshPreviewAnimation();
			});

			var div = new Element("<div></div>").appendTo(editor.find("dl"));
			new Element("<dt>Anim</dt>").appendTo(div);
			var dd = new Element("<dd>").appendTo(div);
			var button = new hide.comp.Button(dd, null, "", {hasDropdown: true});
			button.label = blendSpace2D.points[selectedPoint].animPath;
			button.onClick = () -> {
				hide.comp.ContextMenu.createDropdown(button.element.get(0), [
					{
						label: "Choose File ...",
						click: () -> {
						ide.chooseFile(["fbx"], (path) -> {
								var old = blendSpace2D.points[selectedPoint].animPath;
								blendSpace2D.points[selectedPoint].animPath = path;
								undo.change(Field(blendSpace2D.points[selectedPoint], "animPath", old), () -> {
									button.label = blendSpace2D.points[selectedPoint].animPath;
								});
							}, true);
						}
					}
				], {search: Visible, autoWidth: true});
			};
		}

		propsEditor.add(new hide.Element('
			<div class="group" name="Preview">
					<dl>
						<dt>X</dt><dd><input type="range" min="0.0" max="1.0" field="x"/></dd>
						<dt>Y</dt><dd><input type="range" min="0.0" max="1.0" field="y"/></dd>
					</dl>
				</div>
		'), previewAxis, (_) -> {
			updatePreviewAxis();
		});
	}

	override function save() {
		var content = ide.toJSON(blendSpace2D.save());
		currentSign = ide.makeSignature(content);
		sys.io.File.saveContent(getPath(), content);
		super.save();
	}

	override function onDragDrop(items : Array<String>, isDrop : Bool) {
		if (items.length != 1)
			return false;
		if (!StringTools.endsWith(items[0], ".fbx"))
			return false;

		var rect = graph.element.get(0).getBoundingClientRect();
		if (ide.mouseX >= rect.x && ide.mouseX <= rect.x + rect.width && ide.mouseY >= rect.y && ide.mouseY <= rect.y + rect.height) {
			if (isDrop) {
				var pos = getPointPos(ide.mouseX, ide.mouseY, true);
				var newPoint : hrt.animgraph.BlendSpace2D.BlendSpacePoint = {x: pos.x, y: pos.y, speed: 1.0, animPath: items[0]};
				addPoint(newPoint, true);
			}
			return true;
		}
		return false;
	}

    function onScenePreviewReady() {
		scenePreviewReady = true;

		if (scenePreview.getObjectPath() == null) {
			var first = AnimGraphEditor.gatherAllPreviewModels(blendSpace2D.animFolder)[0];
			scenePreview.setObjectPath(first);
		}

		var animList = new AnimList(propertiesContainer, null, scenePreview.listAnims(blendSpace2D.animFolder));
		scenePreview.resetPreviewCamera();
    }

	function deletePoint(index: Int) {
		var point = blendSpace2D.points[index];
		function exec(isUndo: Bool) {
			if (!isUndo) {
				blendSpace2D.points.splice(index, 1);
			} else {
				blendSpace2D.points.insert(index, point);
			}
			blendSpace2D.triangulate();
			refreshGraph();
		}
		exec(false);
		undo.change(Custom(exec));
	}

	function addPoint(point: hrt.animgraph.BlendSpace2D.BlendSpacePoint, ?index: Int, select: Bool = false) {
		index ??= blendSpace2D.points.length;
		var prevSelection = selectedPoint;
		function exec(isUndo: Bool) {
			if (!isUndo) {
				blendSpace2D.points.insert(index, point);
				blendSpace2D.triangulate();
				if (select)
					setSelection(index);
			} else {
				blendSpace2D.points.splice(index, 1);
				blendSpace2D.triangulate();
				if (select)
					setSelection(prevSelection);
			}
			refreshGraph();
			refreshPreviewAnimation();
		}
		exec(false);
		undo.change(Custom(exec));
	}

    function onScenePreviewUpdate(dt: Float) {

    }

	function createPoint() {

	}

	function setSelection(index: Int) {
		selectedPoint = index;
		refreshPropertiesPannel();
		refreshGraph();
	}

	function updatePreviewAxis() {
		if (animPreview != null) {
			var root : hrt.animgraph.nodes.BlendSpace2D.BlendSpace2D = cast @:privateAccess animPreview.rootNode;
			@:privateAccess root.bsX = previewAxis.x;
			@:privateAccess root.bsY = previewAxis.y;
		}
		refreshGraph();
	}

	static var losange = [
		new h2d.col.Point(-8, 0),
		new h2d.col.Point(0, -8),
		new h2d.col.Point(8, 0),
		new h2d.col.Point(0, 8),
	];

	var cachedRect : js.html.DOMRect;
	function localXToGraph(x: Float) : Float {
		if (blendSpace2D.maxX - blendSpace2D.minX == 0) return 0;
		var t = (x - blendSpace2D.minX) / (blendSpace2D.maxX - blendSpace2D.minX);
		return t * cachedRect.width;
	}

	function localYToGraph(y: Float) : Float {
		if (blendSpace2D.maxY - blendSpace2D.minY == 0) return 0;
		var t = (y - blendSpace2D.minY) / (blendSpace2D.maxY - blendSpace2D.minY);
		return (1.0-t) * cachedRect.height;
	}

	function graphXToLocal(x: Float) : Float {
		var t = (x - cachedRect.x) / cachedRect.width;
		return hxd.Math.lerp(blendSpace2D.minX, blendSpace2D.maxX, t);
	}

	function graphYToLocal(y: Float) : Float {
		var t = (y - cachedRect.y) / cachedRect.height;
		return hxd.Math.lerp(blendSpace2D.minY, blendSpace2D.maxY, (1.0-t));
	}

	function refreshGraph() {
		cachedRect = graph.element.get(0).getBoundingClientRect();
		graph.element.html("");

		graph.element.attr("viewBox", '0 0 ${cachedRect.width} ${cachedRect.height}');
		//graph.element.attr("preserveAspectRatio", "XMidYMid meet");

		for (i in 1...subdivs+1) {


			var locX = hxd.Math.lerp(blendSpace2D.minX, blendSpace2D.maxX, i / (subdivs+1));
			var locY = hxd.Math.lerp(blendSpace2D.minY, blendSpace2D.maxY, i / (subdivs+1));

			var posX = localXToGraph(locX);
			var posY = localYToGraph(locY);

			graph.line(graph.element, posX, 0, posX, cachedRect.height).addClass("grid");
			graph.line(graph.element, 0, posY, cachedRect.width, posY).addClass("grid");
		}

		for (i in 0...subdivs+2) {
			var percent = i / (subdivs+1);
			var locX = hxd.Math.lerp(blendSpace2D.minX, blendSpace2D.maxX, i / (subdivs+1));
			var locY = hxd.Math.lerp(blendSpace2D.minY, blendSpace2D.maxY, i / (subdivs+1));

			var posX = localXToGraph(locX);
			var posY = localYToGraph(locY);

			var partRoundedX = hxd.Math.round(locX * 100)/100;
			var partRoundedY = hxd.Math.round(locY * 100)/100;

			graph.text(graph.element, 10, posY, '$partRoundedY').addClass("grid-label");
			graph.text(graph.element, posX, cachedRect.height - 10, '$partRoundedX').addClass("grid-label");
		}

		var pts = [new h2d.col.Point(), new h2d.col.Point(), new h2d.col.Point()];
		for (triangle in blendSpace2D.triangles) {
			for (id => point in triangle) {
				pts[id].x = localXToGraph(blendSpace2D.points[point].x);
				pts[id].y = localYToGraph(blendSpace2D.points[point].y);
			}
			var g = graph.polygon2(graph.element, pts, {}).addClass("tri");
		}

		for (id => point in blendSpace2D.points) {
			var g = graph.group(graph.element);
			var svgPoint = graph.polygon2(g, losange).addClass("bs-point");

			g.attr("transform", 'translate(${localXToGraph(point.x)}, ${localYToGraph(point.y)})');

			if (id == hoverPoint) {
				svgPoint.addClass("hover");
			}

			if (id == selectedPoint) {
				svgPoint.addClass("selected");
			}

			var move = false;
			var elem : js.html.svg.CircleElement = cast svgPoint.get(0);
		}

		{
			var g = graph.group(graph.element);
			g.attr("transform", 'translate(${localXToGraph(previewAxis.x)}, ${localYToGraph(previewAxis.y)})');
			final size = 10;
			graph.line(g, -size, -size, size, size).addClass("preview-axis");
			graph.line(g, -size, size, size, -size).addClass("preview-axis");
		}
	}

    static var _ = FileTree.registerExtension(BlendSpace2DEditor,["bs2d"],{ icon : "arrows-alt", createNew: "Blend Space 2D" });
}
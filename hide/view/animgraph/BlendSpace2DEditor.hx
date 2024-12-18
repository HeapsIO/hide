package hide.view.animgraph;

@:access(hrt.animgraph.BlendSpace2D)
class BlendSpace2DEditor extends hide.view.FileView {
	var root : hide.Element;
	var previewContainer : hide.Element;
	var graphContainer : hide.Element;
	var propertiesContainer : hide.Element;
	var mainPanel : hide.Element;

	var scenePreview : hide.comp.Scene;
	var previewCamController : hide.comp.Scene.PreviewCamController;
	var propsEditor : hide.comp.PropsEditor;

	var blendSpace2D: hrt.animgraph.BlendSpace2D;

	var graph : hide.comp.SVG;

	var graphPoints : Array<js.html.svg.GElement> = [];
	var hoverPoint : Int = -1;
	var selectedPoint : Int = -1;

	var startMovePos : h2d.col.Point = null;

	static final pointRadius = 8;
	var subdivs = 5;

	override function onRebuild() {
		blendSpace2D = cast hide.Ide.inst.loadPrefab(state.path, null,  true);
		super.onRebuild();
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
				var svg: js.html.svg.SVGElement = cast graph.element.get(0);

				svg.onpointerdown = (e:js.html.PointerEvent) -> {
					if (e.button != 0)
						return;

					movedPoint = hoverPoint;
					if (selectedPoint != hoverPoint) {
						selectedPoint = hoverPoint;
						refreshGraph();
						refreshPropertiesPannel();
					}

					if (movedPoint == -1)
						return;

					svg.setPointerCapture(e.pointerId);
					e.preventDefault();
				}

				svg.onpointermove = (e:js.html.PointerEvent) -> {
					var rect = svg.getBoundingClientRect();

					if (movedPoint == -1) {
						var mouse = inline new h2d.col.Point((e.clientX - rect.x), e.clientY - rect.y);

						hoverPoint = -1;
						for (id => point in blendSpace2D.points) {
							var pt = inline new h2d.col.Point(point.x * rect.width, point.y * rect.height);
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

						var mouse = inline new h2d.col.Point((e.clientX - rect.x)/rect.width, (e.clientY - rect.y)/rect.height);

						blendSpace2D.points[movedPoint].x = hxd.Math.clamp(mouse.x);
						blendSpace2D.points[movedPoint].y = hxd.Math.clamp(mouse.y);

						if (!e.altKey) {
							// Snap to grid
							blendSpace2D.points[movedPoint].x = hxd.Math.round(blendSpace2D.points[movedPoint].x * (subdivs+1)) / (subdivs+1);
							blendSpace2D.points[movedPoint].y = hxd.Math.round(blendSpace2D.points[movedPoint].y * (subdivs+1)) / (subdivs+1);
						}

						blendSpace2D.reTriangulate();
					}

					refreshGraph();
				}

				svg.onpointerup = (e:js.html.PointerEvent) -> {
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

							blendSpace2D.reTriangulate();
							refreshGraph();
						}

						undo.change(Custom(exec));
					}

					movedPoint = -1;
				}

			}
			panel.onResize = refreshGraph;

			scenePreview = new hide.comp.Scene(config, previewContainer, null);
			scenePreview.element.addClass("scene-preview");

			scenePreview.onReady = onScenePreviewReady;
			scenePreview.onUpdate = onScenePreviewUpdate;
		}

		propertiesContainer = new hide.Element("<properties-container></properties-container>").appendTo(root);
		{
			new Element("<h1>Parameters</h1>").appendTo(propertiesContainer);
			propsEditor = new hide.comp.PropsEditor(undo, propertiesContainer);
		}
		refreshGraph();
	}

	function refreshPropertiesPannel() {
		propsEditor.clear();
		if (selectedPoint != null) {
			propsEditor.add(new hide.Element('
				<div class="group" name="Point">
					<dl>
						<dt>X</dt><input type="range" min="0.0" max="1.0" field="x"/>
						<dt>Y</dt><input type="range" min="0.0" max="1.0" field="y"/>

						<dt>Anim</dt><input type="fileselect" extensions="fbx" field="animPath"/>
					</dl>
				</div>
			'), blendSpace2D.points[selectedPoint], (_) -> {
				blendSpace2D.reTriangulate();
				refreshGraph();
			});
		}
	}

	override function save() {
		var content = ide.toJSON(blendSpace2D.save());
		currentSign = ide.makeSignature(content);
		sys.io.File.saveContent(getPath(), content);
		super.save();
	}

    function onScenePreviewReady() {
        previewCamController = new hide.comp.Scene.PreviewCamController(scenePreview.s3d);
    }

    function onScenePreviewUpdate(dt: Float) {

    }

	function createPoint() {

	}

	static var losange = [
		new h2d.col.Point(-8, 0),
		new h2d.col.Point(0, -8),
		new h2d.col.Point(8, 0),
		new h2d.col.Point(0, 8),
	];

	function refreshGraph() {
		graph.element.html("");

		var width = graph.element.innerWidth();
		var height = graph.element.innerHeight();


		graph.element.attr("viewBox", '0 0 $width $height');
		//graph.element.attr("preserveAspectRatio", "XMidYMid meet");

		for (i in 1...subdivs+1) {
			var posX = (i / (subdivs+1)) * width;
			var posY = (i / (subdivs+1)) * height;
			graph.line(graph.element, posX, 0, posX, height).addClass("grid");
			graph.line(graph.element, 0, posY, width, posY).addClass("grid");
		}

		var pts = [new h2d.col.Point(), new h2d.col.Point(), new h2d.col.Point()];
		for (triangle in blendSpace2D.triangles) {
			for (id => point in triangle) {
				pts[id].x = blendSpace2D.points[point].x * width;
				pts[id].y = blendSpace2D.points[point].y * height;
			}
			var g = graph.polygon2(graph.element, pts, {}).addClass("tri");
		}

		for (id => point in blendSpace2D.points) {
			var g = graph.group(graph.element);
			var svgPoint = graph.polygon2(g, losange).addClass("bs-point");

			g.attr("transform", 'translate(${point.x * width}, ${point.y * height})');

			if (id == hoverPoint) {
				svgPoint.addClass("hover");
			}

			if (id == selectedPoint) {
				svgPoint.addClass("selected");
			}

			var move = false;
			var elem : js.html.svg.CircleElement = cast svgPoint.get(0);
		}
	}

    static var _ = FileTree.registerExtension(BlendSpace2DEditor,["blendspace2d"],{ icon : "arrows-alt", createNew: "Blend Space 2D" });
}
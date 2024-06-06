package hide.view.textureeditor;

import hrt.texgraph.TexNode;
import hide.view.GraphInterface;

class TextureEditor extends hide.view.FileView implements GraphInterface.IGraphEditor {
	public static var DEFAULT_PREVIEW_COLOR = 16716947;
	public static var DEFAULT_PREVIEW_SIZE = 2048;

	var graphEditor : hide.view.GraphEditor;
	var textureGraph : hrt.texgraph.TexGraph;

	// Preview
	var previewScene : hide.comp.Scene;
	var previewBitmap : h2d.Bitmap;
	var previewShaderAlpha : GraphEditor.PreviewShaderAlpha;
	var initializedPreviews : Map<h2d.Bitmap, Bool> = [];
	var camController : hide.view.l3d.CameraController2D;

	var generationRequested : Bool = true;
	var previewRefreshRequested : Bool = true;

	var selectedNodes : Array<TexNode>;

	override function onDisplay() {
		super.onDisplay();
		element.html("");
		element.addClass("texture-editor");
		textureGraph = cast hide.Ide.inst.loadPrefab(state.path, null,  true);
		previewShaderAlpha = new GraphEditor.PreviewShaderAlpha();

		if (graphEditor != null)
			graphEditor.remove();

		graphEditor = new hide.view.GraphEditor(config, this, this.element);
		graphEditor.onDisplay();

		var rightPanel = new Element(
			'<div id="right-panel">
				<div class="group">
					<div class="header">
						<div class="icon ico ico-caret-down"></div>
						<span class="title">Base parameters</span>
					</div>
					<div class="content" id="base-parameters"></div>
				</div>
				<div class="group">
					<div class="header">
						<div class="icon ico ico-caret-down"></div>
						<span class="title">Specific parameters</span>
					</div>
					<div class="content" id="specific-parameters"></div>
				</div>
			</div>'
		);

		var baseParameters = rightPanel.find("#base-parameters");
		var outputSize = new Element('
		<h2 class="title">Output size</h2>
		<div class="fields grid-3">
			<label>Width</label>
			<input type="number" id="output-width" title="Width of the output texture (in px)"/>
			<label>Height</label>
			<input type="number" id="output-height" title="Height of the output texture (in px)"/>
		</div>');
		outputSize.appendTo(baseParameters);

		var outputFormat = new Element('
		<h2 class="title">Output format</h2>
		<div class="fields grid-3">
			<label>Format</label>
			<select name="formats" id="output-format"/>
				${ [for (f in Type.allEnums(hxd.PixelFormat)) '<option value="${f.getIndex()}">${f.getName()}</option>'].join("")}
			</select>
		</div>');
		outputFormat.appendTo(baseParameters);

		function addResetButton(fieldEl : Element, fieldName : String) {
			var resetEl = new Element('<div class="reset icon ico ico-ban" title="Reset value to default (graph global value)"></div>');
			resetEl.insertAfter(fieldEl);

			resetEl.on("click", function() {
				Reflect.deleteField(this.selectedNodes[0].overrides, fieldName);
				Reflect.setField(this.selectedNodes[0], fieldName, Reflect.field(this.textureGraph, fieldName));
				resetEl.css({ visibility : "hidden", "pointers-event" : "none"});
				updateParameters(this.selectedNodes[0]);
				generate();
			});

			if (this.selectedNodes == null || this.selectedNodes.length <= 0 || !Reflect.hasField(this.selectedNodes[0].overrides, fieldName)) {
				resetEl.css({ visibility : "hidden", "pointers-event" : "none"});
				return;
			}
		}

		addResetButton(rightPanel.find("#output-width"), "outputWidth");
		addResetButton(rightPanel.find("#output-height"), "outputHeight");
		addResetButton(rightPanel.find("#output-format"), "outputFormat");

		var headers = rightPanel.find(".header");
		headers.on("click", function(e) {
			var header = new Element(e.target).closest(".header");
			var content = header.siblings(".content");

			if (content.css("display") == "none") {
				content.css({ display: "block" });
				header.find(".icon").removeClass("ico-caret-right").addClass("ico-caret-down");
			}
			else {
				content.css({ display: "none" });
				header.find(".icon").removeClass("ico-caret-down").addClass("ico-caret-right");
			}
		});

		rightPanel.find("#specific-parameters").prev(".header").css({ display : "none" });

		rightPanel.appendTo(element);
		updateParameters(null);

		// Preview
		if (previewScene != null)
			previewScene.element.remove();

		var texPreview = new Element(
			'<div id="tex-preview">
			</div>'
		);

		previewScene = new hide.comp.Scene(config, null, texPreview);
		previewScene.onReady = onPreviewSceneReady;
		previewScene.onUpdate = onPreviewSceneUpdate;

		texPreview.appendTo(graphEditor.element);

		var toolbar = new Element('<div class="hide-toolbar2"></div>').appendTo(texPreview);
		var group = new Element('<div class="tb-group"></div>').appendTo(toolbar);
		var menu = new Element('<div class="button2 transparent" title="More options"><div class="ico ico-navicon"></div></div>');
		menu.appendTo(group);
		menu.click((e) -> {
			var menu = new hide.comp.ContextMenu([
				{ label: "Center preview", click: centerPreviewCamera }
			]);
		});

		graphEditor.onPreviewUpdate = onPreviewUpdate;
		graphEditor.onNodePreviewUpdate = onNodePreviewUpdate;
		graphEditor.onSelectionChanged = onSelectionChanged;
	}

	override function getDefaultContent() : haxe.io.Bytes {
		var p = (new hrt.texgraph.TexGraph(null, null)).serialize();
		return haxe.io.Bytes.ofString(ide.toJSON(p));
	}

	override function save() {
		var content = textureGraph.saveToText();
		currentSign = ide.makeSignature(content);
		sys.io.File.saveContent(getPath(), content);
		super.save();
	}

	public function onPreviewSceneReady() {
		if (previewScene.s3d == null || previewScene.s2d == null)
			throw "Preview scene not ready";

		camController = new hide.view.l3d.CameraController2D(previewScene.s2d);

		var tile = h2d.Tile.fromColor(TextureEditor.DEFAULT_PREVIEW_COLOR);
		previewBitmap = new h2d.Bitmap(tile, previewScene.s2d);

		centerPreviewCamera();
	}

	public function onPreviewSceneUpdate(dt: Float) {
		if (!previewRefreshRequested)
			return;

		previewRefreshRequested = false;

		var outputNodes = textureGraph.getOutputNodes();
		if (outputNodes == null || outputNodes.length <= 0)
			return;

		var outputs = textureGraph.cachedOutputs.get(outputNodes[0].id);
		if (outputs == null || outputs.length <= 0 || outputs[0] == null || previewBitmap == null)
			return;

		try {
			var tex = Std.downcast(outputs[0], h3d.mat.Texture);
			var pixels = tex.capturePixels();
			var outputTexture = new h3d.mat.Texture(tex.width, tex.height, textureGraph.outputFormat);
			outputTexture.uploadPixels(pixels);
			previewBitmap.tile = h2d.Tile.fromTexture(outputTexture);

			centerPreviewCamera();
		}
		catch(e) Ide.inst.quickError("Can't create 2D preview");
	}

	public function onPreviewUpdate() : Bool {
		checkGeneration();

		@:privateAccess
		{
			var engine = graphEditor.previewsScene.engine;
			var t = engine.getCurrentTarget();
			graphEditor.previewsScene.s2d.ctx.globals.set("global.pixelSize", new h3d.Vector(2 / (t == null ? engine.width : t.width), 2 / (t == null ? engine.height : t.height)));
		}

		@:privateAccess
		if (previewScene.s2d != null) {
			previewScene.s2d.ctx.time = graphEditor.previewsScene.s2d.ctx.time;
		}

		return true;
	}

	public function onNodePreviewUpdate(node: IGraphNode, bitmap: h2d.Bitmap) @:privateAccess {
		if (initializedPreviews.get(bitmap) == null) {
			bitmap.addShader(previewShaderAlpha);
			initializedPreviews.set(bitmap, true);
		}

		if (textureGraph.cachedOutputs != null) {
			var outputs = textureGraph.cachedOutputs.get(node.id);

			if (outputs == null || outputs.length <= 0)
				return;

			bitmap.tile = h2d.Tile.fromTexture(outputs[0]);
		}
	}

	public function onSelectionChanged(selectedNodes: Array<IGraphNode>) {
		this.selectedNodes = cast selectedNodes;

		// If there's no selection, show graph editor parameters
		if (this.selectedNodes.length == 0) {
			updateParameters(null);

			element.find("#specific-parameters").empty();
			element.find("#specific-parameters").prev(".header").css({ display : "none" });
			return;
		}

		// If there's only one node selected, show its parameters
		if (this.selectedNodes.length == 1) {
			updateParameters(this.selectedNodes[0]);

			var el = this.selectedNodes[0].getSpecificParametersHTML();
			if (el != null) {
				element.find("#specific-parameters").append(el);
				element.find("#specific-parameters").prev(".header").css({ display : "flex" });
			}

			return;
		}
	}

	public function getNodes():Iterator<IGraphNode> {
		return textureGraph.nodes.iterator();
	}

	public function getEdges():Iterator<Edge> {
		var edges : Array<Edge> = [];
		for (id => node in textureGraph.nodes) {
			for (inputId => connection in node.connections) {
				if (connection != null) {
					edges.push(
						{
							nodeFromId: connection.from.id,
							outputFromId: connection.outputId,
							nodeToId: id,
							inputToId: inputId,
						});
				}
			}
		}
		return edges.iterator();
	}

	public function getAddNodesMenu():Array<AddNodeMenuEntry> {
		var entries : Array<AddNodeMenuEntry> = [];
		var id = 0;
		for (i => node in hrt.texgraph.TexNode.registeredNodes) {
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
						@:privateAccess var id = hrt.texgraph.TexGraph.CURRENT_NODE_ID++;
						var inst = std.Type.createInstance(node, []);
						inst.id = id;
						return inst;
					},
				}
			);
		}

		return entries;
	}

	public function addNode(node: IGraphNode) {
		textureGraph.addNode(cast node);
		generate();
	}

	public function removeNode(id:Int) {
		textureGraph.removeNode(id);
		generate();
	}

	public function serializeNode(node: IGraphNode):Dynamic {
		return (cast node:TexNode).serializeToDynamic();
	}

	public function unserializeNode(data:Dynamic, newId:Bool): IGraphNode {
		var node = TexNode.createFromDynamic(data, textureGraph);
		if (newId) {
			@:privateAccess var newId = hrt.texgraph.TexGraph.CURRENT_NODE_ID++;
			node.id = newId;
		}
		return node;
	}

	public function createCommentNode():Null<IGraphNode> {
		var node = new hrt.texgraph.nodes.Comment();
		node.comment = "Comment";
		@:privateAccess var newId = hrt.texgraph.TexGraph.CURRENT_NODE_ID++;
		node.id = newId;
		return node;
	}

	public function canAddEdge(edge: Edge):Bool {
		return textureGraph.canAddEdge({ outputNodeId: edge.nodeFromId, outputId: edge.outputFromId, inputNodeId: edge.nodeToId, inputId: edge.inputToId });
	}

	public function addEdge(edge: Edge) {
		var input = textureGraph.nodes.get(edge.nodeToId);
		input.connections[edge.inputToId] = {from: textureGraph.nodes.get(edge.nodeFromId), outputId: edge.outputFromId};
		generate();
	}

	public function removeEdge(nodeToId:Int, inputToId:Int) {
		var input = textureGraph.nodes.get(nodeToId);
		input.connections[inputToId] = null;
		generate();
	}

	public function getUndo() : hide.ui.UndoHistory {
		return undo;
	}

	public function generate() {
		generationRequested = true;
	}

	public function refreshPreview() {
		previewRefreshRequested = true;
	}


	function checkGeneration() {
		if (!generationRequested)
			return;

		generationRequested = false;
		textureGraph.generate();

		refreshPreview();
	}

	function centerPreviewCamera() {
		var tile = previewBitmap.tile;

		var ratio = tile.width > tile.height ? tile.width / tile.height : tile.width / tile.height;
		previewBitmap.width = tile.width > tile.height ? TextureEditor.DEFAULT_PREVIEW_SIZE : TextureEditor.DEFAULT_PREVIEW_SIZE * ratio;
		previewBitmap.height = tile.height > tile.width ? TextureEditor.DEFAULT_PREVIEW_SIZE  : TextureEditor.DEFAULT_PREVIEW_SIZE * ratio;

		@:privateAccess camController.targetPos.set(previewBitmap.height / 2, previewBitmap.width / 2, (1 / previewBitmap.width) * 300);
	}

	function updateParameters(node: TexNode) {
		function updateResetButtonVisibility(el : Element, fieldName : String) {
			var resetEl = el.next(".reset");
			if (node == null)
				resetEl.css({ visibility : "hidden", "pointers-event" : "none" });
			else {
				if (Reflect.hasField(node.overrides, fieldName))
					resetEl.css({ visibility : "visible", "pointers-event" : "auto" });
				else
					resetEl.css({ visibility : "hidden", "pointers-event" : "none" });
			}
		}

		var outputWidth = element.find("#output-width");
		outputWidth.val(node == null ? textureGraph.outputWidth : node.outputWidth);
		outputWidth.off();
		outputWidth.on("change", function() {
			var v = Std.parseInt(outputWidth.val());
			if (node == null) {
				textureGraph.outputWidth = v;
			}
			else {
				node.outputWidth = v;
				Reflect.setField(node.overrides, "outputWidth", v);
			}
			updateResetButtonVisibility(outputWidth, "outputWidth");
			generate();
		});
		updateResetButtonVisibility(outputWidth, "outputWidth");

		var outputHeight = element.find("#output-height");
		outputHeight.val(node == null ? textureGraph.outputHeight : node.outputHeight);
		outputHeight.off();
		outputHeight.on("change", function() {
			var v = Std.parseInt(outputHeight.val());
			if (node == null) {
				textureGraph.outputHeight = v;
			}
			else {
				node.outputHeight = v;
				Reflect.setField(node.overrides, "outputHeight", v);
			}
			updateResetButtonVisibility(outputHeight, "outputHeight");
			generate();
		});
		updateResetButtonVisibility(outputHeight, "outputHeight");

		var outputFormat = element.find("#output-format");
		outputFormat.val(node == null ? textureGraph.outputFormat.getIndex() : node.outputFormat.getIndex());
		outputFormat.off();
		outputFormat.on("change", function() {
			var v = hxd.PixelFormat.createByIndex(Std.parseInt(outputFormat.val()));
			if (node == null) {
				textureGraph.outputFormat = v;
			}
			else {
				node.outputFormat = v;
				Reflect.setField(node.overrides, "outputFormat", v);
			}
			updateResetButtonVisibility(outputFormat, "outputFormat");
			generate();
		});
		updateResetButtonVisibility(outputFormat, "outputFormat");
	}

	static var _ = FileTree.registerExtension(TextureEditor, ["texgraph"], { icon : "scribd", createNew: "Texture Graph" });
}
package hide.view.animgraph;
using Lambda;
import hide.view.GraphInterface;
import hrt.animgraph.*;

class PreviewSettings {
    public var modelPath: String = null;

    public function new() {};
}

@:access(hrt.animgraph.AnimGraph)
@:access(hrt.animgraph.AnimGraphInstance)
@:access(hrt.animgraph.Node)
class AnimGraphEditor extends GenericGraphEditor {

    var animGraph : hrt.animgraph.AnimGraph;
    public var previewModel : h3d.scene.Object;
    public var previewPrefab : hrt.prefab.Prefab;

    var parametersList : hide.Element;
    var previewAnimation : AnimGraphInstance = null;

    var previewNode : hrt.animgraph.nodes.AnimNode = null;
    var queuedPreview : hrt.animgraph.nodes.AnimNode = null;

    var previewSettings : PreviewSettings = new PreviewSettings();

    override function reloadView() {
        previewNode = null;
        animGraph = cast hide.Ide.inst.loadPrefab(state.path, null,  true);

        if (animGraph.animFolder == null) {
            element.html("
                <h1>Choose a folder containing the models to animate</h1>
                <button-2></button-2>
            ");

            var button = new hide.comp.Button(null, element.find("button-2"), "Choose folder");
            button.onClick = () -> {
                ide.chooseDirectory((path) -> {
                    if (path != null) {
                        animGraph.animFolder = path;
                        save();
                        reloadView();
                    }
                });
            }

            return;
        }

        super.reloadView();
        loadPreviewSettings();



        var parameters = new Element("<graph-parameters></graph-parameters>").appendTo(propertiesContainer);
        new Element("<h1>Parameters</h1>").appendTo(parameters);
        var addParameterBtn = new Element("<button>Add Parameter</button>").appendTo(parameters);

        addParameterBtn.click((e) -> {
            addParameter();
        });
        parametersList = new Element("<ul></ul>").appendTo(parameters);

        refreshPamamList();

        graphEditor.element.get(0).addEventListener("dragover", (e: js.html.DragEvent) -> {
            var paramIndex = Std.parseInt(e.dataTransfer.getData("index"));
            if (paramIndex != null)
                e.preventDefault(); // prevent default to allow drop
        });

        graphEditor.element.get(0).addEventListener("drop", (e: js.html.DragEvent) -> {
            var paramIndex = Std.parseInt(e.dataTransfer.getData("index"));
            if (paramIndex == null)
                return;


            var posCursor = new h2d.col.Point(graphEditor.lX(e.clientX - 25), graphEditor.lY(e.clientY - 10));
			var inst = new hrt.animgraph.nodes.FloatParameter();
			@:privateAccess var id = animGraph.nodeIdCount++;
			inst.id = id;
            inst.parameter = animGraph.parameters[paramIndex];
			inst.setPos(posCursor);

			graphEditor.opBox(inst, true, graphEditor.currentUndoBuffer);
			graphEditor.commitUndo();
        });

        if (previewSettings.modelPath == null) {
            previewSettings.modelPath = gatherAllPreviewModels(animGraph.animFolder)[0];
        }
    }

    static public function gatherAllPreviewModels(basePath : String) : Array<String> {
        var paths = [];

        function rec(dirPath: String) {
            var files = sys.FileSystem.readDirectory(hide.Ide.inst.getPath(dirPath));
            for (path in files) {
                if (sys.FileSystem.isDirectory(path)) {
                    rec(dirPath + "/" + path);
                } else {
                    var filename = path.split("/").pop();
                    var ext = filename.split(".").pop();

                    if (ext == "prefab") {
                        paths.push(dirPath + "/" + path);
                    }
                    if (ext == "fbx" && !StringTools.startsWith(filename, "Anim_")) {
                        paths.push(dirPath + "/" + path);
                    }
                }
            }
        }

        rec(basePath);
        return paths;
    }

    override function getPreviewOptionsMenu() : Array<hide.comp.ContextMenu.MenuItem> {
        var options = super.getPreviewOptionsMenu();

        var models : Array<hide.comp.ContextMenu.MenuItem> = [];
        var paths = gatherAllPreviewModels(animGraph.animFolder);
        for (path in paths) {
            var basePath = StringTools.replace(path, animGraph.animFolder + "/", "");
            models.push({label: basePath, click: () -> {
                previewSettings.modelPath = path;
                savePreviewSettings();
                reloadPreviewModel();
            }});
        }

        options.push({label: "Set Model", menu: models});
        return options;
    }

    public function setPreviewMesh(path: String) {

        savePreviewSettings();
    }

    public function refreshPreview() {
        if (previewNode != null)
            setPreview(previewNode);
    }

    public function setPreview(newOutput: hrt.animgraph.nodes.AnimNode) {
        queuedPreview = newOutput;
    }

    public function setPreviewInternal(newOutput: hrt.animgraph.nodes.AnimNode) {
        previewNode = newOutput;

        // refresh animation
        {
            if (previewModel == null)
                return;

            var anim = animGraph.getAnimation(previewNode);
            previewModel.playAnimation(anim);
            previewAnimation = cast previewModel.currentAnimation;
            refreshPamamList();
        }

        //copy runtime parameters
        for (index => param in animGraph.parameters) {
            var animParam = @:privateAccess previewAnimation.parameterMap[param.name];
            if (animParam != null) {
                animParam.runtimeValue = param.runtimeValue;
            }
        }
        graphEditor.refreshPreviewButtons();
    }

    function refreshPamamList() {
        parametersList.html("");
        for (paramIndex => param in animGraph.parameters) {
            var paramElement = new Element('<graph-parameter>
                <header>
                    <div class="reorder ico ico-reorder" draggable="true"></div>
                    <div class="ico ico-chevron-down toggle-open"></div>
                    <input type="text" value="${param.name}" class="fill"></input>
                    <button-2 class="menu"><div class="ico ico-ellipsis-v"/></button-2>
                </header>
            </graph-parameter>').appendTo(parametersList);

            var open : Bool = getDisplayState('param.${paramIndex}') ?? false;
            paramElement.toggleClass("folded", open);

            var name = paramElement.find("input");
            name.on("change", (e) -> {
                var prev = param.name;
                var curr = name.val();

                function exec(isUndo: Bool) {
                    if (!isUndo) {
                        param.name = curr;
                    } else {
                        param.name = prev;
                    }
                    name.val(param.name);
                    var toRefresh = animGraph.nodes.filter((n) -> Std.downcast(n, hrt.animgraph.nodes.FloatParameter)?.parameter == param);
                    for (node in toRefresh) {
                        graphEditor.refreshBox(node.id);
                    }
                }

                exec(false);
                undo.change(Custom(exec));
            });

            name.on("contextmenu", (e) -> {
                e.stopPropagation();
            });

            var toggleOpen = paramElement.find(".toggle-open");
            toggleOpen.on("click", (e) -> {
                open = !open;
                saveDisplayState('param.${paramIndex}', open);
                paramElement.toggleClass("folded", open);
            });

            var reorder = paramElement.find(".reorder");
            reorder.get(0).ondragstart = (e: js.html.DragEvent) -> {
                e.dataTransfer.setDragImage(paramElement.get(0), Std.int(paramElement.width()), 0);

                e.dataTransfer.setData("index", '${paramIndex}');
                e.dataTransfer.dropEffect = "move";
                trace("Dragstart", e.dataTransfer.getData("index"));
            }

            inline function isAfter(e) {
                return e.clientY > (paramElement.offset().top + paramElement.outerHeight() / 2.0);
            }

            paramElement.get(0).addEventListener("dragover", function(e : js.html.DragEvent) {
                if (!e.dataTransfer.types.contains("index"))
                    return;
                var after = isAfter(e);
                paramElement.toggleClass("hovertop", !after);
                paramElement.toggleClass("hoverbot", after);
                e.preventDefault();
            });

            paramElement.get(0).addEventListener("dragleave", function(e : js.html.DragEvent) {
                if (!e.dataTransfer.types.contains("index"))
                    return;
                paramElement.toggleClass("hovertop", false);
                paramElement.toggleClass("hoverbot", false);
            });

            paramElement.get(0).addEventListener("dragenter", function(e : js.html.DragEvent) {
                if (!e.dataTransfer.types.contains("index"))
                    return;
                e.preventDefault();
            });

            paramElement.get(0).addEventListener("drop", function(e : js.html.DragEvent) {
                var toMoveIndex = Std.parseInt(e.dataTransfer.getData("index"));
                paramElement.toggleClass("hovertop", false);
                paramElement.toggleClass("hoverbot", false);
                if (paramIndex == null)
                    return;
                var after = isAfter(e);
                execMoveParameterTo(toMoveIndex, paramIndex, after);
            });


            var content = new Element("<content></content>").appendTo(paramElement);
            var props = new Element("<ul>").appendTo(content);
            if (previewAnimation != null) {
                var slider = new Element('<li><dd>Preview</dd><input type="range" min="0.0" max="1.0" step="0.01" value="${param.runtimeValue}"></input></li>').appendTo(props).find("input");
                var range = new hide.comp.Range(null,slider);

                range.setOnChangeUndo(undo, () -> param.runtimeValue, (v:Float) -> {
                    param.runtimeValue = v;
                    var runtimeParam = previewAnimation.parameterMap.get(param.name);
                    if (runtimeParam != null) {
                        runtimeParam.runtimeValue = param.runtimeValue;
                    }
                });

                var def = new Element('<li><dd>Default</dd><input type="range" min="0.0" max="1.0" step="0.01" value="${param.defaultValue}"></input></li>').appendTo(props).find("input");
                var range = new hide.comp.Range(null,def);
                range.setOnChangeUndo(undo, () -> param.defaultValue, (v:Float) -> param.defaultValue = v);
            }

            paramElement.find("header").get(0).addEventListener("contextmenu", function (e : js.html.MouseEvent) {
                e.preventDefault();
                hide.comp.ContextMenu.createFromEvent(e, [
                    {label: "Delete", click: () -> execRemoveParam(paramIndex)}
                ]);
            });

            var menu = paramElement.find(".menu");
            menu.on("click", (e) -> {
                e.preventDefault();
                hide.comp.ContextMenu.createDropdown(menu.get(0), [
                    {label: "Delete", click: () -> execRemoveParam(paramIndex)}
                ]);
            });
        }
    }

    function execRemoveParam(index: Int) {
        var save = @:privateAccess animGraph.parameters[index].copyToDynamic({});
        function exec(isUndo : Bool) {
            if (!isUndo) {
                animGraph.parameters.splice(index, 1);
            } else {
                var param = new hrt.animgraph.AnimGraph.Parameter();
                @:privateAccess param.copyFromDynamic(save);
                animGraph.parameters.insert(index, param);
            }
            refreshPamamList();
        }
        exec(false);
        undo.change(Custom(exec));
    }

    function execMoveParameterTo(oldIndex: Int, newIndex: Int, after: Bool) {
        if (!after) newIndex -= 1;
		if (oldIndex == newIndex)
			return;
        if (newIndex < oldIndex) {
            newIndex += 1;
        }

		function exec(isUndo: Bool) {
            if (!isUndo) {
                var param = animGraph.parameters.splice(oldIndex, 1)[0];
                animGraph.parameters.insert(newIndex, param);
            } else {
                var param = animGraph.parameters.splice(newIndex, 1)[0];
                animGraph.parameters.insert(oldIndex, param);
            }
            refreshPamamList();
		}
		exec(false);
		undo.change(Custom(exec));
	}

    override function getDefaultContent() : haxe.io.Bytes {
        @:privateAccess return haxe.io.Bytes.ofString(ide.toJSON(new hrt.animgraph.AnimGraph(null, null).serialize()));
    }

    override function save() {
        js.Browser.document.activeElement.blur();
        var content = ide.toJSON(animGraph.save());
        currentSign = ide.makeSignature(content);
		sys.io.File.saveContent(getPath(), content);
        super.save();
    }

    override function onScenePreviewReady() {
        super.onScenePreviewReady();

        reloadPreviewModel();
        resetPreviewCamera();
    }

    function reloadPreviewModel() {
        if (previewModel != null) {
            previewModel.remove();
            previewModel = null;
        }

        if (previewPrefab != null) {
            previewPrefab.dispose();
            previewPrefab.shared.root3d?.remove();
            previewPrefab.shared.root2d?.remove();
            previewPrefab = null;
        }

        if (previewSettings.modelPath == null)
            return;

        try {
            if (StringTools.endsWith(previewSettings.modelPath, ".prefab")) {
                try {
                    previewPrefab = Ide.inst.loadPrefab(previewSettings.modelPath);
                } catch (e) {
                    throw 'Could not load mesh ${previewSettings.modelPath}, error : $e';
                }
                var ctx = new hide.prefab.ContextShared(null, new h3d.scene.Object(scenePreview.s3d));
                ctx.scene = scenePreview;
                previewPrefab.setSharedRec(ctx);
                previewPrefab = previewPrefab.make();

                previewModel = previewPrefab.find(hrt.prefab.Model, (m) -> StringTools.startsWith(m.source, animGraph.animFolder))?.local3d;
                if (previewModel == null) {
                    throw "Linked prefab doesn't contain any suitable model";
                }
            } else if (StringTools.endsWith(previewSettings.modelPath, ".fbx")) {
                previewModel =  scenePreview.loadModel(previewSettings.modelPath);
                scenePreview.s3d.addChild(previewModel);
            }
            else {
                throw "Unsupported model format";
            }
        } catch (e) {
            previewSettings.modelPath = null;
            ide.quickError("Couldn't load preview : " + e);
            savePreviewSettings();
            reloadPreviewModel(); // cleanup
            return;
        }

        setPreview(cast animGraph.nodes.find((f) -> Std.downcast(f, hrt.animgraph.nodes.Output) != null));
    }

    override function getNodes() : Iterator<IGraphNode> {
        return animGraph.nodes.iterator();
    }

    override function getEdges():Iterator<Edge> {
        var edges : Array<Edge> = [];
        for (node in animGraph.nodes) {
            for (inputToId => edge in node.inputEdges) {
                if (edge == null)
                    continue;
                edges.push({
                    nodeToId: node.id,
                    inputToId: inputToId,
                    nodeFromId: edge.target.id,
                    outputFromId: edge.outputIndex,
                });
            }
        }
        return edges.iterator();
    }

    override function getAddNodesMenu():Array<AddNodeMenuEntry> {
        var menu : Array<AddNodeMenuEntry> = [];
        for (nodeInternalName => type in hrt.animgraph.Node.registeredNodes) {
            var info = Type.createEmptyInstance(type);
            if (!info.canCreateManually())
                continue;

            var entry : AddNodeMenuEntry = {
                name: info.getDisplayName(),
                description: "",
                group: "Group",
                onConstructNode: () -> {
                    var node : Node = cast Type.createInstance(type, []);
                    animGraph.nodeIdCount ++;
                    node.id = animGraph.nodeIdCount;
                    return node;
                }
            };

            menu.push(entry);
        }
        return menu;
    }

    override function addNode(node: IGraphNode) {
        animGraph.nodes.push(cast node);
    }

    override function removeNode(id: Int) {
        var removedNode = null;
        for (pos => node in animGraph.nodes) {
            if (node.id == id) {
                removedNode = node;
                animGraph.nodes.splice(pos, 1);
                break;
            }
        }

        // Sanity check, normally the graphEditor should remove the edges for us
        // before calling removeNode
        for (node in animGraph.nodes) {
            for (input in node.inputEdges) {
                if (input == null)
                    continue;
                if (input.target == removedNode) {
                    throw "assert";
                }
            }
        }
    }

    override function serializeNode(node : IGraphNode) : Dynamic {
        var node : hrt.animgraph.Node = cast node;
        var ser = node.serializeToDynamic();
        ser.id = node.id;
        var param = Std.downcast(node, hrt.animgraph.nodes.FloatParameter);
        if (param != null) {
            ser.paramId = animGraph.parameters.indexOf(param.parameter);
        }
        return ser;
    }

    override function unserializeNode(data: Dynamic, newId: Bool) : IGraphNode {
        var node = hrt.animgraph.Node.createFromDynamic(data);
        if (newId) {
            animGraph.nodeIdCount ++;
            node.id = animGraph.nodeIdCount;
        } else {
            node.id = data.id;
        }

        var param = Std.downcast(node, hrt.animgraph.nodes.FloatParameter);
        if (param != null) {
            param.parameter = animGraph.parameters[data.paramId];
        }
        return node;
    }

    override function canAddEdge(edge : Edge) : Bool {
        var input = animGraph.getNodeByEditorId(edge.nodeToId).getInputs()[edge.inputToId];
        var output = animGraph.getNodeByEditorId(edge.nodeFromId).getOutputs()[edge.outputFromId];

        return (Node.areOutputsCompatible(input.type, output.type));
    }

    override function addEdge(edge : Edge) : Void {
        var inputNode = animGraph.getNodeByEditorId(edge.nodeToId);
        inputNode.inputEdges[edge.inputToId] = {target: animGraph.getNodeByEditorId(edge.nodeFromId), outputIndex: edge.outputFromId};

        refreshPreview();
    }

    override function removeEdge(nodeToId: Int, inputToId : Int) : Void {
        var inputNode = animGraph.getNodeByEditorId(nodeToId);
        inputNode.inputEdges[inputToId] = null;

        refreshPreview();
    }

    override function onScenePreviewUpdate(dt:Float) {
        super.onScenePreviewUpdate(dt);

        if (queuedPreview != null) {
            setPreviewInternal(queuedPreview);
            queuedPreview = null;
        }
    }

    function resetPreviewCamera() {
        previewFocusObject(previewModel);
    }

    public function loadPreviewSettings() {
		var save = haxe.Json.parse(getDisplayState("previewSettings") ?? "{}");
		previewSettings = new PreviewSettings();
		for (f in Reflect.fields(previewSettings)) {
			var v = Reflect.field(save, f);
			if (v != null) {
				Reflect.setField(previewSettings, f, v);
			}
		}
	}

	public function savePreviewSettings() {
		saveDisplayState("previewSettings", haxe.Json.stringify(previewSettings));
	}

    function addParameter() {
        var newParam = new hrt.animgraph.AnimGraph.Parameter();
        newParam.name = "New Parameter";
        newParam.defaultValue = 0.0;

        var disctictNameId = 0;

        while (true) {
            var retry = false;
            for (param in animGraph.parameters) {
                if (newParam.name == param.name) {
                    disctictNameId += 1;
                    newParam.name = 'New Parameter ($disctictNameId)';
                    retry = true;
                    break;
                }
            }
            if (retry)
                continue;
            break;
        }

        var index = animGraph.parameters.length;
        function exec(isUndo: Bool) {
            if (!isUndo) {
                animGraph.parameters.insert(index, newParam);
            } else {
                animGraph.parameters.splice(index, 1);
            }
            refreshPamamList();
        }

        undo.change(Custom(exec));
        exec(false);
    }

    static var _ = FileTree.registerExtension(AnimGraphEditor,["animgraph"],{ icon : "play-circle-o", createNew: "Anim Graph" });
}
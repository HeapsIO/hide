package hide.view.animgraph;

import hide.view.GraphInterface;
import hrt.animgraph.*;

@:access(hrt.animgraph.AnimGraph)
@:access(hrt.animgraph.AnimGraphInstance)
@:access(hrt.animgraph.Node)
class AnimGraphEditor extends GenericGraphEditor {

    var animGraph : hrt.animgraph.AnimGraph;
    public var previewModel : h3d.scene.Object;

    var parametersList : hide.Element;
    var previewAnimation : AnimGraphInstance = null;

    var previewNode : hrt.animgraph.nodes.AnimNode = null;

    override function reloadView() {
        animGraph = cast hide.Ide.inst.loadPrefab(state.path, null,  true);
        super.reloadView();

        var parameters = new Element("<graph-parameters></graph-parameters>").appendTo(propertiesContainer);
        new Element("<h1>Parameters</h1>").appendTo(parameters);
        var addParameterBtn = new Element("<button>Add Parameter</button>").appendTo(parameters);

        addParameterBtn.click((e) -> {
            addParameter();
        });
        parametersList = new Element("<ul></ul>").appendTo(parameters);

        refreshPamamList();

        var testButton = new Element("<button>Test Bones</button>").appendTo(propertiesContainer);
        testButton.click((_) -> {
            setPreview(null);
        });

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
    }

    public function refreshPreview() {
        setPreview(previewNode);
    }

    public function setPreview(newOutput: hrt.animgraph.nodes.AnimNode) {
        previewNode = newOutput;

        // refresh animation
        {
            if (previewModel == null)
                return;
            var anim = animGraph.getAnimation();
            previewModel.playAnimation(anim);
            previewAnimation = cast previewModel.currentAnimation;
            refreshPamamList();
        }

        if (previewNode != null) {
            var index = animGraph.nodes.indexOf(newOutput);
            if (index == -1)
                throw "Invalid node";
            previewAnimation.outputNode = cast previewAnimation.animGraph.nodes[index];
            @:privateAccess previewAnimation.bind(previewAnimation.target);
        }

        // copy runtime parameters
        for (index => param in animGraph.parameters) {
            previewAnimation.animGraph.parameters[index].runtimeValue = param.runtimeValue;
        }
        graphEditor.refreshPreviewButtons();
    }

    function refreshPamamList() {
        parametersList.html("");
        for (paramIndex => param in animGraph.parameters) {
            var paramElement = new Element('<graph-parameter>
                <header>
                    <div class="ico ico-chevron-down toggle-open"></div>
                    <input type="text" value="${param.name}" class="fill"></input>
                    <div class="reorder ico ico-reorder" draggable="true"></div>
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
            }

            var content = new Element("<content></content>").appendTo(paramElement);
            var props = new Element("<ul>").appendTo(content);
            if (previewAnimation != null) {
                var runtimeParam = previewAnimation.parameterMap.get(param.name);
                var line = new Element("<li></li>").appendTo(props);
                var slider = new Element('<li><dd>Test value</dd><input type="range" min="0.0" max="1.0" step="0.01" value="${param.runtimeValue}"></input></li>').appendTo(line).find("input");

                slider.on("input", (e) -> {
                    var value = Std.parseFloat(slider.val());
                    param.runtimeValue = value;
                    if (runtimeParam != null) {
                        runtimeParam.runtimeValue = value;
                    }
                });
                slider.change((e) -> {
                    var value = Std.parseFloat(slider.val());
                    param.runtimeValue = value;
                    if (runtimeParam != null) {
                        runtimeParam.runtimeValue = value;
                    }
                });

                var line = new Element("<li></li>").appendTo(props);
                var def = new Element('<dd>Default</dd><input type="range" min="0.0" max="1.0" step="0.01" value="${param.runtimeValue}"></input>').appendTo(line).find("input");

                var line = new Element("<li></li>").appendTo(props);
                var def = new Element('<dd>Default</dd><input type="range" min="0.0" max="1.0" step="0.01" value="${param.runtimeValue}"></input>').appendTo(line).find("input");
            }
        }
    }

    override function getDefaultContent() : haxe.io.Bytes {
        @:privateAccess return haxe.io.Bytes.ofString(ide.toJSON(new hrt.animgraph.AnimGraph(null, null).serialize()));
    }

    override function save() {
        var content = ide.toJSON(animGraph.save());
        currentSign = ide.makeSignature(content);
		sys.io.File.saveContent(getPath(), content);
        super.save();
    }

    override function onScenePreviewReady() {
        super.onScenePreviewReady();

        previewModel = scenePreview.loadModel("character/Kobold01/Model.FBX");
        scenePreview.s3d.addChild(previewModel);

        setPreview(previewNode);
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

        setPreview(previewNode);
    }

    override function removeEdge(nodeToId: Int, inputToId : Int) : Void {
        var inputNode = animGraph.getNodeByEditorId(nodeToId);
        inputNode.inputEdges[inputToId] = null;

        setPreview(previewNode);
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
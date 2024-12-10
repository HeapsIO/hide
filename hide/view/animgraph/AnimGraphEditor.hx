package hide.view.animgraph;

import hide.view.GraphInterface;
import hrt.animgraph.*;

@:access(hrt.animgraph.AnimGraph)
@:access(hrt.animgraph.AnimGraphInstance)
@:access(hrt.animgraph.Node)
class AnimGraphEditor extends GenericGraphEditor {

    var animGraph : hrt.animgraph.AnimGraph;
    var previewModel : h3d.scene.Object;

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
            refreshAnimation();
        });
    }

    public function refreshAnimation() {
        var anim = animGraph.getAnimation();
        previewModel.playAnimation(anim);
        previewAnimation = cast previewModel.currentAnimation;
        refreshPamamList();
    }

    public function setPreview(newPreview: hrt.animgraph.nodes.AnimNode) {
        previewNode = newPreview;
        refreshAnimation();
        var index = animGraph.nodes.indexOf(newPreview);
        if (index == -1)
            throw "Invalid node";
        previewAnimation.outputNode = cast previewAnimation.animGraph.nodes[index];
        @:privateAccess previewAnimation.bind(previewAnimation.target);
    }

    function refreshPamamList() {
        parametersList.html("");
        for (param in animGraph.parameters) {
            var paramElement = new Element('<graph-paramater>
                <header>
                    <div class="ico ico-chevron-right"></div>
                    <input type="text" value="${param.name}"></input>
                    <div class="ico ico-reorder"></div>
                </header>
            </graph-parameters>').appendTo(parametersList);

            if (previewAnimation != null) {
                var param = previewAnimation.parameterMap.get(param.name);
                if (param != null) {
                    var slider = new Element('<input type="range" min="0.0" max="1.0" step="0.01" value="${param.runtimeValue}"></input>');

                    slider.on("input", (e) -> {
                        var value = Std.parseFloat(slider.val());
                        param.runtimeValue = value;
                    });
                    slider.change((e) -> {
                        var value = Std.parseFloat(slider.val());
                        param.runtimeValue = value;
                    });
                    paramElement.append(slider);
                }
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

        // var anim = hxd.res.Loader.currentInstance.load("character/Kobold01/Anim_attack01.FBX").toModel().toHmd().loadAnimation();
        // previewModel.playAnimation(anim);
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
        var animNode : hrt.animgraph.Node = cast node;
        var ser = animNode.serializeToDynamic();
        ser.id = animNode.id;
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
    }

    override function removeEdge(nodeToId: Int, inputToId : Int) : Void {
        var inputNode = animGraph.getNodeByEditorId(nodeToId);
        inputNode.inputEdges[inputToId] = null;
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
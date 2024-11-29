package hide.view.animgraph;

import hide.view.GraphInterface;
import hrt.animgraph.*;

@:access(hrt.animgraph.AnimGraph)
@:access(hrt.animgraph.Node)
class AnimGraphEditor extends GenericGraphEditor {

    var animGraph : hrt.animgraph.AnimGraph;
    var previewModel : h3d.scene.Object;

    override function reloadView() {
        animGraph = cast hide.Ide.inst.loadPrefab(state.path, null,  true);
        super.reloadView();
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

        var anim = hxd.res.Loader.currentInstance.load("character/Kobold01/Anim_attack01.FBX").toModel().toHmd().loadAnimation();
        previewModel.playAnimation(anim);
    }

    override function getNodes() : Iterator<IGraphNode> {
        return animGraph.nodes.iterator();
    }

    override function getEdges():Iterator<Edge> {
        var edges : Array<Edge> = [];
        for (nodeToId => node in animGraph.nodes) {
            for (inputToId => edge in node.inputEdges) {
                if (edge == null)
                    continue;
                edges.push({
                    nodeToId: nodeToId,
                    inputToId: inputToId,
                    nodeFromId: edge.nodeTarget,
                    outputFromId: edge.nodeOutputIndex,
                });
            }
        }
        return edges.iterator();
    }

    override function getAddNodesMenu():Array<AddNodeMenuEntry> {
        var menu : Array<AddNodeMenuEntry> = [];
        for (nodeInternalName => type in hrt.animgraph.Node.registeredNodes) {
            var info = Type.createEmptyInstance(type);
            var entry : AddNodeMenuEntry = {
                name: info.getDisplayName(),
                description: "",
                group: "Group",
                onConstructNode: () -> {
                    var node : Node = cast Type.createInstance(type, []);
                    animGraph.nodeIdCount ++;
                    node.id = animGraph.nodeIdCount;
                    return node;
                },
            };

            menu.push(entry);
        }
        return menu;
    }

    override function addNode(node: IGraphNode) {
        animGraph.nodes.set(node.id, cast node);
    }

    override function removeNode(id: Int) {
        animGraph.nodes.remove(id);
    }

    override function serializeNode(node : IGraphNode) : Dynamic {
        var animNode : hrt.animgraph.Node = cast node;
        return animNode.serializeToDynamic();
    }

    override function unserializeNode(data: Dynamic, newId: Bool) : IGraphNode {
        var node = hrt.animgraph.Node.createFromDynamic(data);
        if (newId) {
            animGraph.nodeIdCount ++;
            node.id = animGraph.nodeIdCount;
        }
        return node;
    }

    override function canAddEdge(edge : Edge) : Bool {
        var input = animGraph.nodes.get(edge.nodeToId).getInputs()[edge.inputToId];
        var output = animGraph.nodes.get(edge.nodeFromId).getOutputs()[edge.outputFromId];

        return (Node.areOutputsCompatible(input.type, output.type));
    }

    override function addEdge(edge : Edge) : Void {
        var inputNode = animGraph.nodes.get(edge.nodeToId);
        inputNode.inputEdges[edge.inputToId] = {nodeTarget: edge.nodeFromId, nodeOutputIndex: edge.outputFromId};
    }

    override function removeEdge(nodeToId: Int, inputToId : Int) : Void {
        var inputNode = animGraph.nodes.get(nodeToId);
        inputNode.inputEdges[inputToId] = null;
    }

    static var _ = FileTree.registerExtension(AnimGraphEditor,["animgraph"],{ icon : "play-circle-o", createNew: "Anim Graph" });
}
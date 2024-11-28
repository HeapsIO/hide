package hide.view.animgraph;

import hide.view.GraphInterface;
import hrt.animgraph.*;

@:access(hrt.animgraph.AnimGraph)
@:access(hrt.animgraph.Node)
class AnimGraphEditor extends GenericGraphEditor {

    var animGraph : hrt.animgraph.AnimGraph;

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

    override function getNodes() : Iterator<IGraphNode> {
        return animGraph.nodes.iterator();
    }

    override function getEdges():Iterator<Edge> {
        return [].iterator();
    }

    override function getAddNodesMenu():Array<AddNodeMenuEntry> {
        var menu : Array<AddNodeMenuEntry> = [];
        for (name => nodeClass in hrt.animgraph.Node.registeredNodes) {
            var entry : AddNodeMenuEntry = {
                name: name,
                description: "",
                group: "Group",
                onConstructNode: () -> {
                    var node : Node = cast Type.createInstance(nodeClass, []);
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

    static var _ = FileTree.registerExtension(AnimGraphEditor,["animgraph"],{ icon : "play-circle-o", createNew: "Anim Graph" });
}
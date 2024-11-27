package hide.view.animgraph;

import hide.view.GraphInterface;

@:access(hrt.animgraph.AnimGraph)
@:access(hrt.animgraph.Node)
class AnimGraphEditor extends GenericGraphEditor {

    var animGraph : hrt.animgraph.AnimGraph;

    override function reloadView() {
        super.reloadView();
        animGraph = cast hide.Ide.inst.loadPrefab(state.path, null,  true);
    }

    override function getDefaultContent() : haxe.io.Bytes {
        @:privateAccess return haxe.io.Bytes.ofString(ide.toJSON(new hrt.animgraph.AnimGraph(null, null).serialize()));
    }

    override function getNodes() : Iterator<IGraphNode> {
        return [].iterator();
    }

    override function getEdges():Iterator<Edge> {
        return [].iterator();
    }

    override function getAddNodesMenu():Array<AddNodeMenuEntry> {
        return [];
    }

    static var _ = FileTree.registerExtension(AnimGraphEditor,["animgraph"],{ icon : "play-circle-o", createNew: "Anim Graph" });
}
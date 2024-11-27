package hide.view.animgraph;

@:access(hrt.animgraph.AnimGraph)
@:access(hrt.animgraph.Node)
class AnimGraphEditor extends FileView implements hide.view.GraphInterface.IGraphEditor {

    var editor : hide.view.GraphEditor;
    var animGraph : hrt.animgraph.AnimGraph;

    override function onDisplay() {
        element.html("Hello world");
    }

    function reloadView() {
        animGraph = cast hide.Ide.inst.loadPrefab(state.path, null,  true);
    }

    override function getDefaultContent() : haxe.io.Bytes {
        @:privateAccess return haxe.io.Bytes.ofString(ide.toJSON(new hrt.animgraph.AnimGraph(null, null).serialize()));
    }


    // IGraphEditor interface
    public function getNodes() : Iterator<IGraphNode> {
        return animGraph.nodes.iterator();
    }
    public function getEdges() : Iterator<Edge>;
    public function getAddNodesMenu() : Array<AddNodeMenuEntry>;

    public function addNode(node : IGraphNode) : Void;
    public function removeNode(id:Int) : Void;

    public function serializeNode(node : IGraphNode) : Dynamic;

    /**If newId is true, then the returned node must have a new unique id. This is used when duplicating nodes**/
    public function unserializeNode(data: Dynamic, newId: Bool) : IGraphNode;

    /**Create a comment node. Return null if you don't have a comment node in your editor**/
    public function createCommentNode() : Null<IGraphNode>;


    /**Returns false if the edge can't be created because the input/output types don't match**/
    public function canAddEdge(edge : Edge) : Bool;

    public function addEdge(edge : Edge) : Void;
    public function removeEdge(nodeToId: Int, inputToId : Int) : Void;

    public function getUndo() : hide.ui.UndoHistory;



    static var _ = FileTree.registerExtension(AnimGraphEditor,["animgraph"],{ icon : "play-circle-o", createNew: "Anim Graph" });
}
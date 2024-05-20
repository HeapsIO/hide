package hide.view;


typedef GraphNodeInfo = {
    name: String,
    ?headerColor: Int,
    inputs: Array<NodeInput>,
    outputs: Array<NodeOutput>,
    ?width: Int,

    /**If set, the node can show a preview pannel**/
    ?preview: {
        getVisible : () -> Bool,
        setVisible : (Bool) -> Void,

        /**If the preview takes over the whole node like in texture editing mode**/
        fullSize : Bool,
    },

    ?noHeader: Bool,

    /**If set, the node will be treated as a comment**/
    ?comment : {
        getComment : () -> String,
        setComment : (String) -> Void,
        getSize : (s: h2d.col.Point) -> Void,
        setSize : (s: h2d.col.Point) -> Void,
    }
};

typedef NodeInput = {
    /**Display name of the node input **/
    name: String,
    ?color: Int,

    /**If set, the input will have a input text box next to it when not connected**/
    ?defaultParam: {
        get : () -> String,
        set : (String) -> Void
    },
};

typedef NodeOutput = {
    name: String,
    ?color: Int,
};

typedef AddNodeMenuEntry = {
    name: String,
    description: String,
    group: String,

    /**This function will be called when the user chooses to add a node from the add node menu
        You should generate a unique ID for the new IGraphNode. Don't add the node to your graph datastructure yet,
        the Graph editor will call addNode() with this node at the right time.
    **/
    onConstructNode: () -> IGraphNode,
};


/**An edge between 2 nodes. the inputs/outpus id are based on the order of the inputs/ouputs returned by IGraphNode.getInfo()**/
typedef Edge = {
    nodeFromId : Int,
    outputFromId : Int,
    nodeToId : Int,
    inputToId : Int,
};

interface IGraphNode {
    public function getInfo() : GraphNodeInfo;

    /**
        Returns an unique ID that identifies this node.
        The ID of a given node MUST NERVER change for the entire lifetime of the GraphEditor
    **/
    public function getId() : Int;
    public function getPos(p : h2d.col.Point) : Void;
    public function setPos(p : h2d.col.Point) : Void;

    public function getPropertiesHTML(width : Float) : Array<hide.Element>;

    public var editor : GraphEditor;
}

interface IGraphEditor {
    public function getNodes() : Iterator<IGraphNode>;
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
}
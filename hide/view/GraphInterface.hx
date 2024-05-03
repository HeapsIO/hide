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
    onAdd: () -> IGraphNode,
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

    /**Returns an unique ID that identifies this node**/
    public function getId() : Int;
    public function getPos(p : h2d.col.Point) : Void;
    public function setPos(p : h2d.col.Point) : Void;

    public function getPropertiesHTML(width : Float) : Array<hide.Element>;
}

interface IGraphEditor {
    public function getNodes() : Array<IGraphNode>;
    public function getEdges() : Array<Edge>;
    public function getAddNodesMenu() : Array<AddNodeMenuEntry>;

    public function addNode(node : IGraphNode) : Void;
    public function removeNode(id:Int) : Void;

    /**Returns false if the edge can't be created because the input/output types don't match**/
    public function canAddEdge(edge : Edge) : Bool;

    public function addEdge(edge : Edge) : Void;
    public function removeEdge(nodeToId: Int, inputToId : Int) : Void;
    public function getUndo() : hide.ui.UndoHistory;
}
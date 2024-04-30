package hide.view.shadereditor;


typedef GraphNodeInfo = {
    name: String,
    ?headerColor: Int,
    inputs: Array<NodeInput>,
    outputs: Array<NodeInput>,

    /**If set, the node can show a preview pannel**/
    ?preview: {
        getVisible : () -> Bool,
        setVisible : (Bool) -> Void,

        /**If the preview takes over the whole node like in texture editing mode**/
        fullSize : Bool,
    },

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
    ?defaultparam: {
        get : () -> String,
        set : (String) -> Void
    },
};

typedef AddNodeMenuEntry = {
    name: String,
    description: String,
    category: String,

    /**This function will be called when the user chooses to add a node from the add node menu
        Your editor should register the node, and then returns it's interface to the Graph  
    **/
    onAdd: () -> IGraphNode,
};

typedef NodeOutput = {
    name: String,
    ?color: Int,
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

    public function removeBox(id:Int) : Void;

    /**Returns false if the edge can't be created because of constraints**/
    public function addEdge(edge : Edge) : Bool;
    public function removeEdge(nodeToId: Int, inputToId : Int) : Void;
}
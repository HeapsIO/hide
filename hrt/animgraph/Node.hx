package hrt.animgraph;

typedef Edge = {nodeTarget: Int, nodeOutputIndex: Int};
@:autoBuild(hrt.animgraph.Macros.build())
@:autoBuild(hrt.prefab.Macros.buildSerializable())
@:build(hrt.prefab.Macros.buildSerializable())
@:keep
@:keepSub
class Node
#if editor
implements hide.view.GraphInterface.IGraphNode
#end
{
    @:s public var id : Int;
    @:s public var x : Float;
    @:s public var y : Float;
    @:s public var inputEdges: Array<Edge> = [];

    public function serializeToDynamic() : Dynamic {
        var data = {
            type: std.Type.getClassName(std.Type.getClass(this)),
        };

        copyToDynamic(data);
        return data;
    }

    static public function createFromDynamic(data: Dynamic) : Node {
        var type = std.Type.resolveClass(data.type);
		var inst = Std.downcast(std.Type.createInstance(type, []), Node);
        if (inst == null) {
            throw 'Could\'t not create node form type ${data.type}';
        }
        inst.copyFromDynamic(data);
        return inst;
    }

    #if editor

    public var editor : hide.view.GraphEditor;

    public function getInfo() : hide.view.GraphInterface.GraphNodeInfo {
        return {
            name: Type.getClassName(Type.getClass(this)),
            inputs: [],
            outputs: [],
        }
    }

    public function getPos(p: h2d.col.Point) : Void {
        p.x = x;
        p.y = y;
    }

    public function setPos(p: h2d.col.Point) : Void {
        x = p.x;
        y = p.y;
    }

    public function getPropertiesHTML(width : Float) : Array<hide.Element> {
        return [];
    }

    static public var registeredNodes = new Map<String, Class<Node>>();
    static public function register(name: String, cl: Class<Node>) : Bool {
        registeredNodes.set(name, cl);
        return true;
    }

    #end
}
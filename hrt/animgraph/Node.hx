package hrt.animgraph;

class Node
#if editor
implements hide.view.GraphInterface.IGraphNode
#end
{
    public var id : Int;
    public var x : Float;
    public var y : Float;

    #if editor

    public var editor : hide.view.GraphEditor;

    public function getInfo() : hide.view.GraphInterface.GraphNodeInfo {
        throw "need to implement getInfo";
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
    #end

}
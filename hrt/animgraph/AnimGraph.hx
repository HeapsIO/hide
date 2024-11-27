package hrt.animgraph;

class AnimGraph extends hrt.prefab.Prefab {
    var nodes: Map<Int, Node> = [];

    override function save() {
        var json = super.save();

        json.nodes = [
            for (node in nodes) node.serializeToDynamic()
        ];

        return json;
    }

    override function load(json: Dynamic) {
        super.load(json);
        nodes = [];

        for (nodeData in (json.nodes:Array<Dynamic>)) {
            var node = Node.createFromDynamic(nodeData);
            nodes.set(node.id, node);
        }
    }

    override function copy(other: hrt.prefab.Prefab) {
        throw "Should never be called";
    }

    static var _ = hrt.prefab.Prefab.register("animgraph", AnimGraph, "animgraph");
}
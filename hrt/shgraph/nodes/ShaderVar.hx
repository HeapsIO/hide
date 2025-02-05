package hrt.shgraph.nodes;

abstract class ShaderVar extends ShaderNode {
	@prop() public var varId : Int = 0;
	var graph: Graph;
}
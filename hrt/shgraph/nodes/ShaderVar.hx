package hrt.shgraph.nodes;

abstract class ShaderVar extends ShaderNode {
	@prop() public var varId : Int = 0;

	#if editor
	override function getInfo():hide.view.GraphInterface.GraphNodeInfo {
		var info = super.getInfo();

		info.contextMenu = () -> [
			{label: "Show in Variable list", click: () -> {
				(cast editor.editor: hide.view.shadereditor.ShaderEditor).revealVariable(varId);
			}},
		];
		return info;
	}
	#end
}
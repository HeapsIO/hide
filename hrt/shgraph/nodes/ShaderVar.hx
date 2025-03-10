package hrt.shgraph.nodes;

abstract class ShaderVar extends ShaderNode {
	@prop() public var varId : Int = 0;

	#if editor
	override function getInfo():hide.view.GraphInterface.GraphNodeInfo {
		var info = super.getInfo();

		info.contextMenu = (e: js.html.MouseEvent) -> {
			hide.comp.ContextMenu.createFromEvent(e, [
				{label: "Show in Variable list", click: () -> {
					(cast editor.editor: hide.view.shadereditor.ShaderEditor).revealVariable(varId);
				}},
			]);
		}
		return info;
	}
	#end
}
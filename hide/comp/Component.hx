package hide.comp;

class Component {

	var ide : hide.ui.Ide;
	public var root : Element;

	public function new(root) {
		ide = hide.ui.Ide.inst;
		this.root = root;
	}

}
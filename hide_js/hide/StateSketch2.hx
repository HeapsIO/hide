package hide;


class FileView {
	var localState: State;
	var globalState: State;
	var fileState: State;


	@:state(localState) var localMode: Bool = false; //store in localState
	@:state(fileState) var visible: Bool = false; //store in fileState

	var filePath : String;
	var tree :Tree;

	public new() {
		classState.initLocal(ide.projectState.initView(FileView));
		fileState.initFile(state.path, FileView);

		fileState.setParent(ide.projectState.fileState(state.path), FileView);
		tree = new Tree();
		tree.state.setParent(fileState, "fileTree");

		var sceneTree = new Tree();
		sceneTree.state.setParent(fileState, "sceneTree");
	}
}

/**
	Example class that exposes its state that a parent can link to
**/
class Tree {
	public var state : State = new State();

	@:state(state) var localMode: Bool = false;
}

class State {
	parent: State;
	values: Dynamic = {};

	// ide.globalState use this to save the state on disk
	public dynamic function onSet() {
		parent?.onSet();
	}

	function set(key, value) {
		values.set(key, value);
		onSet();
	}

	function get(key, default) {
		return values.get(key) ?? default;
	}

	function getOrPut(key, def) {
		if (!values.has(key))
			values.set(key, def)
		return values.get(key);
	}

	function addChild(key, state) {
		state.values = this.getOrPut(key, {});
		if (state.parent != null)
			throw "can't reparent states";
		state.parent = this;
	}

	public function setParent(state, key) {
		state.addChild(key, this);
	}

	function initGlobalView(key) {
		var views = Ide.inst.globalState.values.getOrPut("views", {});
		values = views.getOrPut(key, {});
		parent = Ide.inst.globalState;
	}

	function initLocalView(key) {
		var views = Ide.inst.localState.values.getOrPut("views", {});
		values = views.getOrPut(key, {});
		parent = Ide.inst.localState;
	}

	function initFileView(file, view) {
		var files = Ide.inst.localState.values.getOrPut("files", {});
		var views = files.getOrPut("views", {});
		var state = files.getOrPut(key, {});
		values = state;
		parent = Ide.inst.localState;
	}
}

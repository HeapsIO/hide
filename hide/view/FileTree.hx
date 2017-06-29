package hide.view;

class FileTree extends hide.ui.View<{ root : String }> {

	function getPath() {
		if( haxe.io.Path.isAbsolute(state.root) )
			return state.root;
		return ide.resourceDir+"/"+state.root;
	}

	override function onDisplay( j : js.jquery.JQuery ) {
		j.text(getPath());
	}

	static var _ = hide.ui.View.register(FileTree);

}
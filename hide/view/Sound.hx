package hide.view;

class Sound extends FileView {

	override function onDisplay() {
		var path = getPath();
		element.html('<audio ${ide.initializing ? '' : 'autoplay="autoplay"'} controls="controls"><source src="file://${getPath()}"/></audio>');
	}

	static var _ = {
		FileTree.registerExtension(Sound,["wav"],{ icon : "volume-up" });
		FileTree.registerExtension(Sound,["mp3","ogg"],{ icon : "music" });
	};
}
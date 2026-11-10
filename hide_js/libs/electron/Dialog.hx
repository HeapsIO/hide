package electron;

typedef FileDialogOptions = {
	?defaultPath : String,
	?exts : Array<String>,
	?directory : Bool,
	?multiple : Bool,
}

class Dialog {

	/**
		Show a file open dialog, callb receives null if cancelled
	**/
	public static function openFiles( options : FileDialogOptions, callb : Null<Array<String>> -> Void ) {
		Ipc.callAsync("dialog.open", options).then((files) -> callb(files));
	}

	/**
		Show a file save dialog, callb receives null if cancelled
	**/
	public static function saveFile( options : FileDialogOptions, callb : Null<String> -> Void ) {
		Ipc.callAsync("dialog.save", options).then((files : Array<String>) -> callb(files == null ? null : files[0]));
	}

	/**
		Synchronous replacement for window.prompt() which is not supported in Electron
	**/
	public static function prompt( text : String, ?defaultValue : String ) : Null<String> {
		return Ipc.call("dialog.prompt", text, defaultValue);
	}

}

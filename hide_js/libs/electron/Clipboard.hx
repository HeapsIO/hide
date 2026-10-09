package electron;

enum abstract ClipboardType(String) {
	var Text = "text";
	var Png = "png";
	var Jpeg = "jpeg";
	var Html = "html";
	var Rtf = "rtf";
}

typedef ClipboardData = {
	data : String,
	?type : ClipboardType,
}

class Clipboard {

	public static function get( ?type : ClipboardType ) : String {
		var v : String = Ipc.call("clipboard.get", type);
		return v == null ? "" : v;
	}

	public static function set( data : String, ?type : ClipboardType ) {
		setMultiple([{ data : data, type : type == null ? Text : type }]);
	}

	/**
		Set several formats at once in the clipboard
	**/
	public static function setMultiple( datas : Array<ClipboardData> ) {
		Ipc.call("clipboard.set", datas);
	}

	public static function clear() {
		Ipc.call("clipboard.clear");
	}

}

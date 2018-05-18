package hide.comp;

class ColorPicker extends Component {

	public var value(get, set) : Int;
	var innerValue : Int;
	var mask : Int;

	public function new( ?alpha : Bool = false, ?parent : Element, ?root : Element ) {
		if( root == null ) root = new Element("<input>");
		super(parent,root);
		mask = alpha ? -1 : 0xFFFFFF;
		(untyped root.spectrum)({
			showInput : true,
			showAlpha : alpha,
			showButtons: false,
			preferredFormat: alpha ? "hex8" : "hex",
			hide : function() {
				onClose();
			},
			show : function() {
				onOpen();
			},
			change : function(color) {
				innerValue = Std.parseInt("0x"+color.toHex8()) & mask;
				onChange(false);
			},
			move : function(color) {
				innerValue = Std.parseInt("0x"+color.toHex8()) & mask;
				onChange(true);
			}
		});

		// cleanup
		var container = (untyped root.spectrum)("container");
		var timer = new haxe.Timer(1000);
		timer.run = function() {
			if( root.parents("body").length == 0 ) {
				container.remove();
				timer.stop();
			}
		};
	}

	public function open() {
		(untyped root.spectrum)("show");
	}

	public function close() {
		(untyped root.spectrum)("hide");
	}

	public dynamic function onOpen() {
	}

	public dynamic function onClose() {
	}

	public dynamic function onChange(dragging) {
	}

	function get_value() return innerValue;

	function set_value(v) {
		v &= mask;
		if( innerValue == v )
			return v;
		(untyped root.spectrum)("set", "#"+StringTools.hex(v,mask < 0 ? 8 : 6));
		return innerValue = v;
	}

}
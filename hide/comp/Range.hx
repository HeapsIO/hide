package hide.comp;

class Range extends Component {

	var original : Null<Float>;

	public var value(get, set) : Float;

	var current : Float;
	var originMin : Float;
	var originMax : Float;
	var curMin : Float;
	var curMax : Float;

	var f : Element;
	var inputView : Element;
	var scale : Float;

	public function new(?parent:Element,?root:Element, ?className : String) {
		if( root == null )
			root = new Element('<input type="range">');
		super(parent,root);

		this.f = root;
		var fullClassName = className == null ? "hide-range": "hide-range " + className;
		root = root.wrap('<div class="$fullClassName"/>').parent();

		if( f.attr("step") == null )
			f.attr("step", "any");

		scale = Std.parseFloat(f.attr("scale"));
		if( Math.isNaN(scale) ) scale = 1.;

		inputView = new Element('<input type="text">').appendTo(root);
		originMin = Std.parseFloat(f.attr("min"));
		originMax = Std.parseFloat(f.attr("max"));
		if( originMin == null || Math.isNaN(originMin) ) originMin = 0;
		if( originMax == null || Math.isNaN(originMax) ) originMax = 1;
		curMin = originMin;
		curMax = originMax;
		current = Std.parseFloat(f.attr("value"));
		if(current != null && !Math.isNaN(current))
			original = current;
		else
			current = 0;

		element.contextmenu((e) -> {
			e.preventDefault();
			ContextMenu.createFromEvent(cast e, [
				{ label : "Reset", click : reset },
				{ label : "sep", isSeparator: true},
				{ label : "Copy", click : copy},
				{ label : "Paste", click: paste, enabled : canPaste()},
				{ label : "sep", isSeparator: true},
				{ label : "Cancel", click : function() {} },
			]);
		});

		f.on("input", function(_) {
			var v = Math.round(Std.parseFloat(f.val()) * 100 * scale) / 100;
			setInner(v,true);
			inputView.val(current / scale);
			f.val(current / scale);
			onChange(true);
		});

		inputView.keypress((e) -> {
			e.stopPropagation(); // Prevent things like ctrl+Z from getting caught by hide while we are editting
		});

		inputView.keydown((e) -> {
			e.stopPropagation(); // Prevent things like ctrl+Z from getting caught by hide while we are editting
		});

		inputView.keyup(function(e) {
			if( e.keyCode == 13 || e.keyCode == 27 ) {
				inputView.blur();
				inputView.val(current / scale);
				return;
			}
			var v = Std.parseFloat(inputView.val()) * scale;
			if( Math.isNaN(v) ) return;
			setInner(v,true);
			f.val(v / scale);
			onChange(true);
		});
		inputView.change(function(e) {
			var v = Std.parseFloat(inputView.val()) * scale;
			if( Math.isNaN(v) ) return;
			setInner(v,false);
			f.val(v / scale);
			onChange(false);
		});

		f.val(current / scale);
		inputView.val(current / scale);

		f.change(function(e) {
			var v = Math.round(Std.parseFloat(f.val()) * 100 * scale) / 100;
			setInner(v,false);
			inputView.val(current / scale);
			onChange(false);
		});
	}

	public function copy() {
		ide.setClipboard(Std.string(value));
	}

	public function paste() {
		var val = getClipboardValue();
		if (val != null) {
			set_value(val);
			onChange(false);
		}
	}

	public function canPaste() : Bool {
		return getClipboardValue() != null;
	}

	public function getClipboardValue() : Null<Float> {
		var str = ide.getClipboard();
		return Std.parseFloat(str);
	}

	public function reset() {
		value = original;
		onChange(false);
	}

	function set_value(v:Float) : Float{
		if( original == null ) original = v;
		setInner(v,true);
		current = v;
		inputView.val(current / scale);
		f.val(current / scale);
		return v;
	}

	function get_value() {
		return current;
	}

	function setInner(v:Float,tempChange:Bool) {
		current = v;
		if( v < curMin ) {
			curMin = Math.floor(v);
			f.attr("min", curMin);
		}
		if( v > curMax ) {
			curMax = Math.ceil(v);
			f.attr("max", curMax);
		}
		if( v >= originMin && v <= originMax && !tempChange ) {
			f.attr("min", originMin);
			f.attr("max", originMax);
			curMin = originMin;
			curMax = originMax;
		}
	}

	public dynamic function onChange( tempChange : Bool ) {
	}


	/**
		Automatically handle undo/redo, tracking automatically if a change is temporary or not.
		get : a function that returns the current value you wanna change
		set : a function that set the value you wanna change.
	**/
	public function setOnChangeUndo( undo: hide.ui.UndoHistory, get : () -> Float, set : (newValue: Float) -> Void) {
		var save : Null<Float> = get();
		onChange = (tempChange) -> {
			if (!tempChange) {
				var prev = save ?? get();
				var curr = value;
				function exec(isUndo) {
					var newValue = !isUndo ? curr : prev;
					value = newValue;
					set(newValue);
				}
				exec(false);
				undo.change(Custom(exec));
				save = null;
			}
			else {
				if (save == null) {
					save = get();
				}
				set(value);
			}
		}
	}
}
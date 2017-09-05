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

	public function new(f:Element) {
		f.wrap('<div class="hide-range"/>');
		var p = f.parent();
		super(p);

		this.f = f;
		if( f.attr("step") == null )
			f.attr("step", "any");
		inputView = new Element('<input type="text">').appendTo(p);
		originMin = Std.parseFloat(f.attr("min"));
		originMax = Std.parseFloat(f.attr("max"));
		if( originMin == null || Math.isNaN(originMin) ) originMin = 0;
		if( originMax == null || Math.isNaN(originMax) ) originMax = 1;
		curMin = originMin;
		curMax = originMax;
		current = Std.parseFloat(f.attr("value"));
		if( current == null || Math.isNaN(current) ) current = 0;

		p.parent().prev("dt").contextmenu(function(e) {
			e.preventDefault();
			new ContextMenu([
				{ label : "Reset", click : function() { inputView.val(""+original); inputView.change(); } },
				{ label : "Cancel", click : function() {} },
			]);
			return false;
		});

		f.on("input", function(_) {
			var v = Math.round(Std.parseFloat(f.val()) * 100) / 100;
			inputView.val(v);
			current = v;
			onChange(true);
		});
		inputView.keyup(function(e) {
			if( e.keyCode == 13 || e.keyCode == 27 ) {
				inputView.blur();
				inputView.val(current);
				return;
			}
			var v = Std.parseFloat(inputView.val());
			if( Math.isNaN(v) ) return;
			setInner(v);
			f.val(v);
			onChange(false);
		});

		f.val(current);
		inputView.val(current);

		f.change(function(e) {
			var v = Math.round(Std.parseFloat(f.val()) * 100) / 100;
			setInner(v);
			inputView.val(v);
			onChange(false);
		});
	}

	function set_value(v) {
		if( original == null ) original = v;
		setInner(v);
		current = v;
		inputView.val(current);
		f.val(current);
		return v;
	}

	function get_value() {
		return current;
	}

	function setInner(v:Float) {
		current = v;
		if( v < curMin ) {
			curMin = Math.floor(v);
			f.attr("min", curMin);
		}
		if( v > curMax ) {
			curMax = Math.ceil(v);
			f.attr("max", curMax);
		}
		if( v >= originMin && v <= originMax ) {
			f.attr("min", originMin);
			f.attr("max", originMax);
			curMin = originMin;
			curMax = originMax;
		}
	}

	public dynamic function onChange( tempChange : Bool ) {
	}

}
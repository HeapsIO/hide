package hide.comp;


class ExpRange extends Range {
	public function setMinMax(min: Float, max: Float) {
		originMin = Math.log(min) / Math.log(scale);
		originMax = Math.log(max) / Math.log(scale);

		f.attr("min", originMin);
        f.attr("max", originMax);

		curMin = originMin;
		curMax = originMax;
	}

    public function new(?parent:Element,?root:Element) {
        super(parent, root);
        scale = 10;

		setMinMax(0.001, 100000.0);

		current = Std.parseFloat(f.attr("value"));
		if(current != null && !Math.isNaN(current))
			original = current;
		else
			current = 0;

		function contextMenu(e) {
			e.preventDefault();
			new ContextMenu([
				{ label : "Reset", click : reset },
				{ label : "sep", isSeparator: true},
				{ label : "Copy", click : copy},
				{ label : "Paste", click: paste, enabled : canPaste()},
				{ label : "sep", isSeparator: true},
				{ label : "Cancel", click : function() {} },
			]);
			return false;
		}

		element.contextmenu(contextMenu);

		f.on("input", function(_) {
			var v = Math.round(Std.parseFloat(f.val()) * 100) / 100;
			setInner(v,true);
            refresh();
			onChange(true);
		});

		inputView.keyup(function(e) {
			if( e.keyCode == 13 || e.keyCode == 27 ) {
				inputView.blur();
                refresh();
				return;
			}
			var v = Std.parseFloat(inputView.val());
			if( Math.isNaN(v) ) return;
            set_value(v);
			onChange(true);
		});
		inputView.change(function(e) {
			var v = Std.parseFloat(inputView.val());
			if( Math.isNaN(v) ) return;
            set_value(v);
			onChange(false);
		});

        refresh();

		f.change(function(e) {
			var v = Math.round(Std.parseFloat(f.val()) * 100) / 100;
			setInner(v,false);
            refresh();
			onChange(false);
		});
	}

    function refresh() {
		inputView.val(get_value());
		f.val(current);
    }

    override function set_value(v:Float) : Float {
		current = Math.log(v) / Math.log(scale);
		setInner(current,true);
        refresh();
		return current;
	}

	override function get_value() {
		var val = Math.pow(scale, hxd.Math.round(current * 10.0) / 10.0);
		return val;
	}

    override function setInner(v:Float,tempChange:Bool) {
		current = v;
	}
}
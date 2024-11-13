package hide.comp;


class ExpRange extends Range {
	var inputGuard: Bool = false;

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

		element.contextmenu((e: js.jquery.Event) -> {
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

		f.off("input");
		f.on("input", function(_) {
			var v = Math.round(Std.parseFloat(f.val()) * 100) / 100;
			setInner(v,true);
            //refresh();
			inputView.val(roundValue());
			onChange(true);
		});

		f.change(function(e) {
			var v = Math.round(Std.parseFloat(f.val()) * 100) / 100;
			setInner(v,false);
            refresh();
			//inputView.val(roundValue());
			onChange(false);
		});

		inputView.keyup(function(e) {
			if( e.keyCode == 13 || e.keyCode == 27 ) {
				inputView.blur();
                refresh();
				return;
			}
			var v = Std.parseFloat(inputView.val());
			if( Math.isNaN(v) ) return;
			inputGuard = true;
            set_value(v);
			inputGuard = false;
			onChange(true);
		});
		inputView.change(function(e) {
			var v = Std.parseFloat(inputView.val());
			if( Math.isNaN(v) ) return;
            set_value(v);
			onChange(false);
		});

        refresh();
	}

	function roundValue() : Float {
		return Math.round(get_value() * 100)/ 100;
	}

    function refresh() {
		if (!inputGuard)
			inputView.val(roundValue());
		f.val(current);
    }

    override function set_value(v:Float) : Float {
		current = Math.log(v) / Math.log(scale);
		setInner(current,true);
        refresh();
		return current;
	}

	override function get_value() {
		var val = Math.pow(scale, current);
		return val;
	}

    override function setInner(v:Float,tempChange:Bool) {
		current = v;
	}
}
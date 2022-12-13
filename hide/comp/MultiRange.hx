package hide.comp;

class MultiRange extends Component {
    public var value(get, set) : Array<Float>;

    var current : Array<Float> = [];
    var numValues : Int = 0;
    var ranges : Array<Range> = [];
    var isUniform : Bool = true;

    var linkButton : Element;
    var linkIcon : Element;

    function set_value(v : Array<Float>) {
        if (v.length != numValues) 
            throw "assert";
        current = v;
        repaint();
        return v;
    }

    function get_value() {
        return current;
    }

    function repaint(?ignoreIndex : Int) {
        for (i => range in ranges) {
            if (ignoreIndex == null || ignoreIndex != i)
                range.value = current[i];
        }
        syncRanges();
        linkButton.toggleClass("toggled", isUniform);
        linkIcon.toggleClass("ico-link", isUniform);
        linkIcon.toggleClass("ico-unlink", !isUniform);

    }

    function syncRanges() {
        var biggestMin = Math.NEGATIVE_INFINITY;
        var smallestMax = Math.POSITIVE_INFINITY;

        for (range in ranges) {
            biggestMin = Math.max(biggestMin, @:privateAccess range.curMin);
            smallestMax = Math.min(smallestMax, @:privateAccess range.curMax);
        }

        for (range in ranges) {
            range.element.attr("min", biggestMin);
            range.element.attr("max", smallestMax);
        }
    }

    public dynamic function onChange(tempChange : Bool) {

    }

    function change(tempChange : Bool) {
        onChange(tempChange);
    }

	public function new(?parent:Element,?root:Element, num : Int , labels : Array<String>) {
        this.numValues = num;
        super(null, null);

        var flex = new Element("<div>").css("position", "relative").css("width", "110%").appendTo(parent);
        flex.css("display", "flex");


        var rows = new Element("<div>").css("flex", "1 0").appendTo(flex);

        var min = root.attr("min");
        if (min == null) min = "0";
        var max = root.attr("max");
        if (max == null) max = "5";

        for (i in 0...numValues) {
            var row = new Element("<div>").appendTo(rows);
            var dt = new Element("<dt>").text(labels[i]).appendTo(row);

            var dd = new Element("<dd>").appendTo(row);
            var range = new Range(dd, new Element('<input type="range" min="$min" max="$max" tabindex="-1">'));

            PropsEditor.wrapDt(dt, "1", function(e) {
                if (e.ctrlKey) {
                    range.value = Math.round(range.value);
                    range.onChange(false);
                } else {
                    range.value = 1;
                    range.onChange(false);
                }
            });

            range.onChange = function(tempChange:Bool) {
                if (isUniform) {
                    var scale =  range.value / current[i];

                    for (j in 0...numValues) {
                        if (!Math.isFinite(scale)) {
                            current[j] = range.value;
                        }
                        else {
                            current[j] = Math.fround(current[j] * scale * 100.0) / 100.0;
                        }
                    }
                    repaint(i);
                }
                else {
                    current[i] = range.value;
                }

                onChange(tempChange);
            };
            ranges.push(range);
        }

        var linkContainer = new Element("<div class='link-container'>").css("flex-shirnk", "1").css("left","-32px").css("position", "relative").appendTo(flex);
        linkContainer.append(new Element("<div class='link link-up'>"));
        linkButton = new Element("<div class='hide-button' title='Link/Unlink sliders. Right click to open the context menu'>").appendTo(linkContainer);
        linkIcon = new Element("<div class='icon ico ico-link'>").appendTo(linkButton);
        linkContainer.append(new Element("<div class='link link-down'>"));

        linkButton.click(function(e) {
            isUniform = !isUniform;
            repaint();
        });

        linkButton.contextmenu(function(e) {
            e.preventDefault();
            new ContextMenu([
				{ label : "Reset All", click : reset },
				{ label : "Round All", click : round },
				{ label : "sep", isSeparator: true},
				{ label : "Copy", click : copy},
				{ label : "Paste", click: paste, enabled : canPaste()},
				{ label : "sep", isSeparator: true},
				{ label : "Cancel", click : function() {} },
			]);
            return false;
        });

        root.remove();

        repaint();
    }

    function round() {
        for (i => v in current) {
            current[i] = Math.fround(v);
        }
        repaint();
        change(false);
    }

    function reset() {
        value = [for (i in 0...numValues) 1.0];
        change(false);
    }

    function copy() {
        ide.setClipboard(current.join(","));
    }

    function paste() {
        var vals = getPasteValues();
        if (vals != null) {
            value = vals;
            change(false);
        }
    }

    function getPasteValues() : Null<Array<Float>> {
        var arr = ide.getClipboard().split(",");
        if (arr.length == numValues) {
            var arrFloat = arr.map((s) -> Std.parseFloat(s));
            if (!arrFloat.contains(Math.NaN))
                return arrFloat;
        }
        return null;
    }

    function canPaste() {
        return getPasteValues() != null;
    }
}
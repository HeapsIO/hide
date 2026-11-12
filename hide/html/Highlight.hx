package hide.html;

#if js
/**
	CSS Custom Highlight API : a set of ranges styled by `::highlight(name)` once registered in `CSS.highlights`.
**/
@:native("Highlight")
extern class Highlight extends js.lib.Set<js.html.Range> {
	var priority : Int;
	function new(ranges : haxe.extern.Rest<js.html.Range>) : Void;
}
#end

package hide;

typedef Element = #if hl hide.tools.vdom.JQuery #else js.jquery.JQuery #end;
typedef Event = #if hl hide.tools.vdom.Event #else js.jquery.Event #end;
typedef HTMLElement = #if hl hide.tools.vdom.Dom #else js.html.Element #end;

function getVal( e : Element ) {
	return #if js e.val() #else e.getValue() #end;
}
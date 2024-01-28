package hide;

typedef Element = #if hl hltml.JQuery #else js.jquery.JQuery #end;
typedef Event = #if hl hltml.Event #else js.jquery.Event #end;
typedef HTMLElement = #if hl hltml.Dom #else js.html.Element #end;

function getVal( e : Element ) {
	return #if js e.val() #else e.getValue() #end;
}
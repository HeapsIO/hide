package hide;

typedef Element = #if hl Dynamic #else js.jquery.JQuery #end;
typedef Event = #if hl Dynamic #else js.jquery.Event #end;
typedef HTMLElement = #if hl Dynamic #else js.html.Element #end;

function getVal( e : Element ) {
	return #if js e.val() #else e.getValue() #end;
}
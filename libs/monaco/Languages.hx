package monaco;

typedef CompletionProvider = {
	var ?triggerChars : Array<String>;
	function provideCompletionItems( model : Model, position : Position, token : Any, context : CompletionContext ) : Array<CompletionItem>;
}

typedef CompletionContext = {
	var ?triggerCharacter : String;
	var triggerKind : SuggestTriggerKind;
}

enum abstract SuggestTriggerKind(Int) {
	var Invoke;
	var TriggerCharacter;
	var TriggerForIncompleteCompletions;
}

enum abstract CompletionItemKind(Int) {
	var Class = 6;
	var Color = 15;
	var Constructor = 3;
	var Enum = 12;
	var Field = 4;
	var File = 16;
	var Folder = 18;
	var Function = 2;
	var Interface = 7;
	var Keyword = 13;
	var Method = 1;
	var Module = 8;
	var Property = 9;
	var Reference = 17;
	var Snippet = 14;
	var Text = 0;
	var Unit = 10;
	var Value = 11;
	var Variable = 5;
}

typedef CompletionItem = {
	var ?additionalTextEdits : Any;
	var ?command : Any;
	var ?commitCharacters : Array<String>;
	var ?detail : String;
	var ?documentation : MarkdownString;
	var ?filterText : String;
	var ?insertText : String;
	var kind : CompletionItemKind;
	var label : String;
	var ?range : Range;
	var ?sortText : String;
	//var ?textEdit : deprecated
}

@:native("monaco.languages")
extern class Languages {

	public static function registerCompletionItemProvider( language : String, provider : CompletionProvider ) : Void;

}
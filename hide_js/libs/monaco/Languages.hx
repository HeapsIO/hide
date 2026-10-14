package monaco;

typedef CompletionProvider = {
	var ?triggerCharacters : Array<String>;
	function provideCompletionItems( model : Model, position : Position, token : Any, context : CompletionContext ) : { suggestions : Array<CompletionItem>, ?incomplete: Bool };
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

enum abstract CompletionItemInsertTextRule(Int) {
	var InsertAsSnippet = 4;
	var KeepWhitespace = 1;
	var None = 0;
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
	var ?insertTextRules: CompletionItemInsertTextRule;
	//var ?textEdit : deprecated
}

typedef SignatureHelpProvider = {
	var ?signatureHelpTriggerCharacters : Array<String>;
	var ?signatureHelpRetriggerCharacters : Array<String>;
	function provideSignatureHelp( model : Model, position : Position, token : Any, context : SignatureHelpContext ) : Null<SignatureHelpResult>;
}

typedef SignatureHelpContext = {
	var triggerKind : SignatureHelpTriggerKind;
	var ?triggerCharacter : String;
	var isRetrigger : Bool;
	var ?activeSignatureHelp : SignatureHelp;
}

enum abstract SignatureHelpTriggerKind(Int) {
	var Invoke = 1;
	var TriggerCharacter = 2;
	var ContentChange = 3;
}

typedef SignatureHelpResult = {
	var value : SignatureHelp;
	function dispose() : Void;
}

typedef SignatureHelp = {
	var signatures : Array<SignatureInformation>;
	var activeSignature : Int;
	var activeParameter : Int;
}

typedef SignatureInformation = {
	var label : String;
	var ?documentation : MarkdownString;
	var parameters : Array<ParameterInformation>;
	var ?activeParameter : Int;
}

typedef ParameterInformation = {
	var label : String;
	var ?documentation : MarkdownString;
}

@:native("monaco.languages")
extern class Languages {

	public static function registerCompletionItemProvider( language : String, provider : CompletionProvider ) : Void;

	public static function registerSignatureHelpProvider( language : String, provider : SignatureHelpProvider ) : Void;

}
package hide.comp;

/**
	Monarch grammar of Haxe (and hscript) for monaco.
	Regular expressions are written as strings : Haxe EReg literals are not JS RegExp.
**/
class HaxeLanguage {

	@:allow(hide.comp.CodeEditor)
	static function register() {
		monaco.Languages.register({ id : "haxe", extensions : [".hx"] });
		monaco.Languages.setLanguageConfiguration("haxe", {
			comments : { lineComment : "//", blockComment : ["/*", "*/"] },
			brackets : [["{", "}"], ["[", "]"], ["(", ")"]],
			autoClosingPairs : [
				{ open : "{", close : "}" },
				{ open : "[", close : "]" },
				{ open : "(", close : ")" },
				{ open : "\"", close : "\"", notIn : ["string"] },
				{ open : "'", close : "'", notIn : ["string"] },
			],
			surroundingPairs : [
				{ open : "{", close : "}" },
				{ open : "[", close : "]" },
				{ open : "(", close : ")" },
				{ open : "\"", close : "\"" },
				{ open : "'", close : "'" },
				{ open : "<", close : ">" },
			],
		});

		// rules are concatenated instead of using monarch's { include : ... } to keep states typed as arrays of rules
		var whitespace : Array<Array<Any>> = [
			["[ \\t\\r\\n]+", ""],
			["/\\*\\*(?!/)", "comment.doc", "@doc"],
			["/\\*", "comment", "@comment"],
			["//.*$", "comment"],
		];
		var root : Array<Array<Any>> = whitespace.concat([
			["#(?:if|elseif|else|end|error)\\b", "keyword"],
			["@:?[a-zA-Z_][\\w.]*", "annotation"],
			["[a-z_]\\w*", { cases : { "@flowKeywords" : "keyword.flow", "@keywords" : "keyword", "@default" : "identifier" } }],
			["[A-Z]\\w*", "type.identifier"],
			["\\$[a-zA-Z_]\\w*", "variable"],
			["~/(?:[^\\\\/]|\\\\.)+/[gimsu]*", "regexp"],
			["[{}()\\[\\]]", "@brackets"],
			["[<>](?!@symbols)", "@brackets"],
			["\\.\\.\\.", "delimiter"],
			["@symbols", { cases : { "@operators" : "delimiter", "@default" : "" } }],
			["0[xX][0-9a-fA-F_]+(?:@intSuffix)?", "number.hex"],
			["0[bB][01_]+(?:@intSuffix)?", "number.hex"],
			["(?:@digits)?\\.(?:@digits)(?:[eE][\\-+]?(?:@digits))?(?:f64)?", "number.float"],
			["(?:@digits)[eE][\\-+]?(?:@digits)(?:f64)?", "number.float"],
			["(?:@digits)(?:@intSuffix|f64)?", "number"],
			["[;,.]", "delimiter"],
			["\"", "string", "@dstring"],
			["'", "string", "@sstring"],
		]);
		var interpolation : Array<Array<Any>> = [
			["\\{", "delimiter.bracket", "@interpolation"],
			["\\}", "delimiter.bracket", "@pop"],
		];

		monaco.Languages.setMonarchTokensProvider("haxe", {
			defaultToken : "",
			tokenPostfix : ".hx",
			flowKeywords : [
				"break", "case", "catch", "continue", "default", "do", "else", "for", "if", "return", "switch", "throw", "try", "while",
			],
			keywords : [
				"abstract", "cast", "class", "dynamic", "enum", "extends", "extern", "false", "final", "function", "implements", "import",
				"in", "inline", "interface", "is", "macro", "new", "null", "operator", "overload", "override", "package", "private",
				"public", "static", "super", "this", "true", "typedef", "untyped", "using", "var",
			],
			operators : [
				"=", ">", "<", "!", "~", "?", ":", "==", "<=", ">=", "!=", "&&", "||", "++", "--", "+", "-", "*", "/", "&", "|", "^", "%",
				"<<", ">>", ">>>", "+=", "-=", "*=", "/=", "&=", "|=", "^=", "%=", "<<=", ">>=", ">>>=", "=>", "->", "??", "??=",
			],
			symbols : "[=><!~?:&|+\\-*/\\^%]+",
			escapes : "\\\\(?:[nrt\"'\\\\$]|x[0-9A-Fa-f]{2}|u[0-9A-Fa-f]{4}|u\\{[0-9A-Fa-f]+\\})",
			digits : "\\d[\\d_]*",
			intSuffix : "i32|i64|u32",
			tokenizer : {
				root : root,
				comment : [
					["[^/*]+", "comment"],
					["\\*/", "comment", "@pop"],
					["[/*]", "comment"],
				],
				doc : [
					["[^/*]+", "comment.doc"],
					["\\*/", "comment.doc", "@pop"],
					["[/*]", "comment.doc"],
				],
				dstring : [
					["[^\\\\\"]+", "string"],
					["@escapes", "string.escape"],
					["\\\\.", "string.escape.invalid"],
					["\"", "string", "@pop"],
				],
				sstring : [
					["[^\\\\'$]+", "string"],
					["@escapes", "string.escape"],
					["\\\\.", "string.escape.invalid"],
					["\\$\\$", "string.escape"],
					["\\$\\{", "delimiter.bracket", "@interpolation"],
					["\\$[a-zA-Z_]\\w*", "variable"],
					["\\$", "string"],
					["'", "string", "@pop"],
				],
				interpolation : interpolation.concat(root),
			},
		});
	}

}

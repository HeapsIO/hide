package hide.comp.cdb;

import cdb.Data;

class ModalColumnForm extends Modal {

	var contentModal : Element;
	var form : Element;

	public function new(base : cdb.Database, sheet : cdb.Sheet, column : cdb.Data.Column, ?parent,?el) {
		super(parent,el);

		var editForm = (column != null);

		contentModal = new Element("<div tabindex='0'>").addClass("content-modal").appendTo(content);

		if (editForm)
			new Element("<h2> Edit column </h2>").appendTo(contentModal);
		else
			new Element("<h2> Create column </h2>").appendTo(contentModal);
		new Element("<p id='errorModal'></p>").appendTo(contentModal);

		form = new Element('<form id="col_form" onsubmit="return false">

			<table>
				<tr>
				<td class="first">Column name
				<td><input type="text" name="name"/>
				</tr>

				<tr>
				<td>Column type
				<td>
				<select name="type">
				<option value="">---- Choose -----</option>
				<option value="id">Unique Identifier</option>
				<option value="string">Text</option>
				<option value="bool">Boolean</option>
				<option value="int">Integer</option>
				<option value="float">Float</option>
				<option value="enum">Enumeration</option>
				<option value="flags">Flags</option>
				<option value="ref">Reference</option>
				<option value="list">List</option>
				<option value="properties">Properties</option>
				<option value="color">Color</option>
				<option value="file">File</option>
				<option value="image">Image</option>
				<option value="tilepos">Tile</option>
				<option value="dynamic">Dynamic</option>
				<option value="layer">Data Layer</option>
				<option value="tilelayer">Tile Layer</option>
				<option value="custom">Custom Type</option>
				</select>
				</tr>

				<tr class="values">
				<td>Possible Values
				<td><input type="text" name="values" name="vals"/>
				</tr>

				<tr class="sheet">
				<td>Sheet
				<td><select name="sheet"></select>
				</tr>

				<tr class="disp">
				<td>Display
				<td>
					<select name="display">
					<option value="0">Default</option>
					<option value="1">Percentage</option>
					</select>
				</tr>

				<tr class="kind">
					<td>Kind
					<td>
					<select name="kind">
					<option value="">Default</option>
					<option value="localizable">Localizable</option>
					<option value="script">Script</option>
					</select>
				</tr>

				<tr class="custom">
					<td>Type
					<td><select name="ctype"></select>
				</tr>

				<tr class="scope">
					<td>Scope
					<td>
					<select name="scope">
					<option value="">Global</option>
					</select>
				</tr>

				<tr class="opt">
					<td>&nbsp;
					<td><label><input type="checkbox" name="req"/>&nbsp;Required</label>
				</tr>

				<tr>
					<td>&nbsp;
					<td>
						<p class="buttons">
							<input class="edit" type="submit" value="Modify" id="editBtn" />
							<input class="create" type="submit" value="Create" id="createBtn" />
							<input type="submit" value="Cancel" id="cancelBtn" />
						</p>
				</tr>
			</table>

			</form>').appendTo(contentModal);

		var parent = sheet.getParent();
		if( parent == null )
			form.find(".scope").remove();
		else {
			var scope = 1;
			var scopes = form.find("[name=scope]");
			var p = parent;
			while( p != null ) {
				if( p.s.idCol != null )
					new Element("<option>").attr("value",""+scope).text(p.s.name).appendTo(scopes);
				p = p.s.getParent();
				scope++;
			}
		}

		var sheets = form.find("[name=sheet]");
		sheets.empty();
		for( i in 0...base.sheets.length ) {
			var s = base.sheets[i];
			if( s.idCol == null ) continue;
			if( s.idCol.scope != null && !StringTools.startsWith(sheet.name,s.name.split("@").slice(0,-s.idCol.scope).join("@")) ) continue;
			new Element("<option>").attr("value", "" + i).text(s.name).appendTo(sheets);
		}

		var types = form.find("[name=type]");
		function changeFieldType() {
			form.find("table").attr("class","").toggleClass("t_"+types.val());
		}
		types.change(function(_) changeFieldType());
		changeFieldType();

		var ctypes = form.find("[name=ctype]");
		new Element("<option>").attr("value", "").text("--- Select ---").appendTo(ctypes);
		for( t in base.getCustomTypes() )
			new Element("<option>").attr("value", "" + t.name).text(t.name).appendTo(ctypes);

		if (editForm) {
			form.addClass("edit");
			form.find("[name=name]").val(column.name);
			form.find("[name=type]").val(column.type.getName().substr(1).toLowerCase()).change();
			form.find("[name=req]").prop("checked", !column.opt);
			form.find("[name=display]").val(column.display == null ? "0" : Std.string(column.display));
			form.find("[name=kind]").val(column.kind == null ? "" : ""+column.kind);
			form.find("[name=scope]").val(column.scope == null ? "" : ""+column.scope);
			switch( column.type ) {
			case TEnum(values), TFlags(values):
				form.find("[name=values]").val(values.join(","));
			case TRef(sname), TLayer(sname):
				var index = base.sheets.indexOf(base.getSheet(sname));
				form.find("[name=sheet]").val( "" + index);
			case TCustom(name):
				form.find("[name=ctype]").val(name);
			default:
			}
		} else {
			form.addClass("create");
			form.find("input").not("[type=submit]").val("");
			form.find("[name=req]").prop("checked", true);
			form.find("[name=kind]").val("");
		}

		form.find("[name=name]").focus();

		contentModal.keydown(function(e) if( e.keyCode == 27 ) closeModal());
		contentModal.click( function(e) e.stopPropagation());

		element.click(function(e) {
			closeModal();
		});

		form.find("#cancelBtn").click(function(e) closeModal());
	}

	public function setCallback(callback : (Void -> Void)) {
		form.find("#createBtn").click(function(e) callback());
		form.find("#editBtn").click(function(e) callback());
	}

	public function closeModal() {
		content.empty();
		close();
	}

	public function getColumn(base : cdb.Database, sheet : cdb.Sheet, refColumn : cdb.Data.Column) : Column{

		var v : Dynamic<String> = { };
		var cols = form.find("input, select").not("[type=submit]");
		for( i in cols.elements() )
			Reflect.setField(v, i.attr("name"), i.attr("type") == "checkbox" ? (i.is(":checked")?"on":null) : i.val());

		var t : ColumnType = switch( v.type ) {
		case "id": TId;
		case "int": TInt;
		case "float": TFloat;
		case "string": TString;
		case "bool": TBool;
		case "enum":
			var vals = StringTools.trim(v.values).split(",");
			if( vals.length == 0 ) {
				error("Missing value list");
				return null;
			}
			TEnum([for( f in vals ) StringTools.trim(f)]);
		case "flags":
			var vals = StringTools.trim(v.values).split(",");
			if( vals.length == 0 ) {
				error("Missing value list");
				return null;
			}
			TFlags([for( f in vals ) StringTools.trim(f)]);
		case "ref":
			var s = base.sheets[Std.parseInt(v.sheet)];
			if( s == null ) {
				error("Sheet not found");
				return null;
			}
			TRef(s.name);
		case "image":
			TImage;
		case "list":
			TList;
		case "custom":
			var t = base.getCustomType(v.ctype);
			if( t == null ) {
				error("Type not found");
				return null;
			}
			TCustom(t.name);
		case "color":
			TColor;
		case "layer":
			var s = base.sheets[Std.parseInt(v.sheet)];
			if( s == null ) {
				error("Sheet not found");
				return null;
			}
			TLayer(s.name);
		case "file":
			TFile;
		case "tilepos":
			TTilePos;
		case "tilelayer":
			TTileLayer;
		case "dynamic":
			TDynamic;
		case "properties":
			TProperties;
		default:
			return null;
		}
		var c : Column = {
			type : t,
			typeStr : null,
			name : v.name,
		};
		if( v.req != "on" ) c.opt = true;
		if( v.display != "0" ) c.display = cast Std.parseInt(v.display);
		switch( v.kind ) {
		case "localizable": c.kind = Localizable;
		case "script": c.kind = Script;
		}
		if( t == TId && v.scope != "" ) c.scope = Std.parseInt(v.scope);
		return c;
	}

	public function error(str : String) {
		contentModal.find("#errorModal").html(str);
	}

}
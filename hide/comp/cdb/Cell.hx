package hide.comp.cdb;
import hxd.Key in K;

class Cell extends Component {

	static var UID = 0;
	static var typeNames = [for( t in Type.getEnumConstructs(cdb.Data.ColumnType) ) t.substr(1).toLowerCase()];

	var editor : Editor;
	var currentValue : Dynamic;
	public var line(default,null) : Line;
	public var column(default, null) : cdb.Data.Column;
	public var columnIndex(get, never) : Int;
	public var value(get, never) : Dynamic;
	public var table(get, never) : Table;

	public function new( root : Element, line : Line, column : cdb.Data.Column ) {
		super(null,root);
		this.line = line;
		this.editor = line.table.editor;
		this.column = column;
		@:privateAccess line.cells.push(this);
		root.addClass("t_" + typeNames[column.type.getIndex()]);
		if( column.kind == Script ) root.addClass("t_script");
		refresh();
	}

	function get_table() return line.table;
	function get_columnIndex() return table.sheet.columns.indexOf(column);
	inline function get_value() return currentValue;

	public function refresh() {
		currentValue = Reflect.field(line.obj, column.name);
		var html = valueHtml(column, value, editor.sheet, line.obj);
		if( html == "&nbsp;" ) element.text(" ") else if( html.indexOf('<') < 0 && html.indexOf('&') < 0 ) element.text(html) else element.html(html);
		updateClasses();
	}

	function updateClasses() {
		element.removeClass("edit");
		element.removeClass("edit_long");
		switch( column.type ) {
		case TBool:
			element.removeClass("true false").addClass( value==true ? "true" : "false" );
		case TInt, TFloat:
			element.removeClass("zero");
			if( value == 0 ) element.addClass("zero");
		default:
		}
	}

	public function valueHtml( c : cdb.Data.Column, v : Dynamic, sheet : cdb.Sheet, obj : Dynamic ) : String {
		if( v == null ) {
			if( c.opt )
				return "&nbsp;";
			return '<span class="error">#NULL</span>';
		}
		return switch( c.type ) {
		case TInt, TFloat:
			switch( c.display ) {
			case Percent:
				(Math.round(v * 10000)/100) + "%";
			default:
				v + "";
			}
		case TId:
			v == "" ? '<span class="error">#MISSING</span>' : (editor.base.getSheet(sheet.name).index.get(v).obj == obj ? v : '<span class="error">#DUP($v)</span>');
		case TString if( c.kind == Script ):
			v == "" ? "&nbsp;" : colorizeScript(v);
		case TString, TLayer(_):
			v == "" ? "&nbsp;" : StringTools.htmlEscape(v).split("\n").join("<br/>");
		case TRef(sname):
			if( v == "" )
				'<span class="error">#MISSING</span>';
			else {
				var s = editor.base.getSheet(sname);
				var i = s.index.get(v);
				i == null ? '<span class="error">#REF($v)</span>' : (i.ico == null ? "" : tileHtml(i.ico,true)+" ") + StringTools.htmlEscape(i.disp);
			}
		case TBool:
			v?"Y":"N";
		case TEnum(values):
			values[v];
		case TImage:
			'<span class="error">#DEPRECATED</span>';
		case TList:
			var a : Array<Dynamic> = v;
			var ps = sheet.getSub(c);
			var out : Array<String> = [];
			var size = 0;
			for( v in a ) {
				var vals = [];
				for( c in ps.columns )
					switch( c.type ) {
					case TList, TProperties:
						continue;
					default:
						vals.push(valueHtml(c, Reflect.field(v, c.name), ps, v));
					}
				var v = vals.length == 1 ? vals[0] : ""+vals;
				if( size > 200 ) {
					out.push("...");
					break;
				}
				var vstr = v;
				if( v.indexOf("<") >= 0 ) {
					vstr = ~/<img src="[^"]+" style="display:none"[^>]+>/g.replace(vstr, "");
					vstr = ~/<img src="[^"]+"\/>/g.replace(vstr, "[I]");
					vstr = ~/<div id="[^>]+><\/div>/g.replace(vstr, "[D]");
				}
				vstr = StringTools.trim(vstr);
				size += vstr.length;
				out.push(v);
			}
			if( out.length == 0 )
				return "[]";
			return out.join(", ");
		case TProperties:
			var ps = sheet.getSub(c);
			var out = [];
			for( c in ps.columns ) {
				var pval = Reflect.field(v, c.name);
				if( pval == null && c.opt ) continue;
				out.push(c.name+" : "+valueHtml(c, pval, ps, v));
			}
			return out.join("<br/>");
		case TCustom(name):
			var t = editor.base.getCustomType(name);
			var a : Array<Dynamic> = v;
			var cas = t.cases[a[0]];
			var str = cas.name;
			if( cas.args.length > 0 ) {
				str += "(";
				var out = [];
				var pos = 1;
				for( i in 1...a.length )
					out.push(valueHtml(cas.args[i-1], a[i], sheet, this));
				str += out.join(",");
				str += ")";
			}
			str;
		case TFlags(values):
			var v : Int = v;
			var flags = [];
			for( i in 0...values.length )
				if( v & (1 << i) != 0 )
					flags.push(StringTools.htmlEscape(values[i]));
			flags.length == 0 ? String.fromCharCode(0x2205) : flags.join("|<wbr>");
		case TColor:
			'<div class="color" style="background-color:#${StringTools.hex(v,6)}"></div>';
		case TFile:
			var path = ide.getPath(v);
			var url = "file://" + path;
			var ext = v.split(".").pop().toLowerCase();
			var html = v == "" ? '<span class="error">#MISSING</span>' : StringTools.htmlEscape(v);
			if( v != "" && !editor.quickExists(path) )
				html = '<span class="error">' + html + '</span>';
			else if( ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "gif" )
				html = '<span class="preview">$html<div class="previewContent"><div class="label"></div><img src="$url" onload="$(this).parent().find(\'.label\').text(this.width+\'x\'+this.height)"/></div></span>';
			if( v != "" )
				html += ' <input type="submit" value="open" onclick="hide.Ide.inst.openFile(\'$path\')"/>';
			html;
		case TTilePos:
			return tileHtml(v);
		case TTileLayer:
			var v : cdb.Types.TileLayer = v;
			var path = ide.getPath(v.file);
			if( !editor.quickExists(path) )
				'<span class="error">' + v.file + '</span>';
			else
				'#DATA';
		case TDynamic:
			var str = Std.string(v).split("\n").join(" ").split("\t").join("");
			if( str.length > 50 ) str = str.substr(0, 47) + "...";
			str;
		}
	}

	static var KWDS = ["for","if","var","this","while","else","do","break","continue","switch","function","return","new","throw","try","catch","case","default"];
	static var KWD_REG = new EReg([for( k in KWDS ) "(\\b"+k+"\\b)"].join("|"),"g");
	function colorizeScript( ecode : String ) {
		var code = ecode;
		code = StringTools.htmlEscape(code);
		code = code.split("\n").join("<br/>");
		code = code.split("\t").join("&nbsp;&nbsp;&nbsp;&nbsp;");
		// typecheck
		var error = new ScriptEditor.ScriptChecker(editor.config, "cdb."+table.sheet.name+"."+column.name, ["cdb."+table.sheet.name => line.obj]).check(ecode);
		if( error != null )
			return '<span class="error">'+code+'</span>';
		// strings
		code = ~/("[^"]*")/g.replace(code,'<span class="str">$1</span>');
		code = ~/('[^']*')/g.replace(code,'<span class="str">$1</span>');
		// keywords
		code = KWD_REG.map(code, function(r) return '<span class="kwd">${r.matched(0)}</span>');
		return code;
	}

	function tileHtml( v : cdb.Types.TilePos, ?isInline ) {
		var path = ide.getPath(v.file);
		if( !editor.quickExists(path) ) {
			if( isInline ) return "";
			return '<span class="error">' + v.file + '</span>';
		}
		var id = UID++;
		var width = v.size * (v.width == null?1:v.width);
		var height = v.size * (v.height == null?1:v.height);
		var max = width > height ? width : height;
		var zoom = max <= 32 ? 2 : 64 / max;
		var inl = isInline ? 'display:inline-block;' : '';
		var url = "file://" + path;
		var html = '<div class="tile" id="_c${id}" style="width : ${Std.int(width * zoom)}px; height : ${Std.int(height * zoom)}px; background : url(\'$url\') -${Std.int(v.size*v.x*zoom)}px -${Std.int(v.size*v.y*zoom)}px; opacity:0; $inl"></div>';
		html += '<img src="$url" style="display:none" onload="$(\'#_c$id\').css({opacity:1, backgroundSize : ((this.width*$zoom)|0)+\'px \' + ((this.height*$zoom)|0)+\'px\' '+(zoom > 1 ? ", imageRendering : 'pixelated'" : "") +'}); if( this.parentNode != null ) this.parentNode.removeChild(this)"/>';
		return html;
	}

	public function isTextInput() {
		return switch( column.type ) {
		case TString if( column.kind == Script ):
			return false;
		case TString, TInt, TFloat, TId, TCustom(_), TDynamic, TRef(_):
			return true;
		default:
			return false;
		}
	}

	public function select() {
		editor.element.focus();
		editor.cursor.set(table, this.columnIndex, this.line.index);
	}

	public function edit() {
		switch( column.type ) {
		case TString if( column.kind == Script ):
			var str = value == null ? "" : editor.base.valToString(column.type, value);
			@:privateAccess table.toggleList(this, function() return new ScriptTable(editor, this));
		case TInt, TFloat, TString, TId, TCustom(_), TDynamic:
			var str = value == null ? "" : editor.base.valToString(column.type, value);
			var textSpan = element.wrapInner("<span>").find("span");
			var textHeight = textSpan.height();
			var textWidth = textSpan.width();
			var longText = textHeight > 25 || str.indexOf("\n") >= 0;
			element.empty();
			element.addClass("edit");
			var i = new Element(longText ? "<textarea>" : "<input>").appendTo(element);
			i.keypress(function(e) e.stopPropagation());
			//if( str != "" && (table.displayMode == Properties || table.displayMode == AllProperties) )
			//	i.css({ width : Math.ceil(textWidth - 3) + "px" }); -- bug if small text ?
			if( longText ) {
				element.addClass("edit_long");
				i.css({ height : Math.max(25,Math.ceil(textHeight - 1)) + "px" });
			}
			i.val(str);
			i.keydown(function(e) {
				switch( e.keyCode ) {
				case K.ESCAPE:
					refresh();
					table.editor.element.focus();
				case K.ENTER if( !e.shiftKey ):
					closeEdit();
					e.preventDefault();
				case K.ENTER if( !longText ):
					var old = currentValue;
					var newVal = i.val() + "\n";
					Reflect.setField(line.obj, column.name, newVal+"x");
					refresh();
					Reflect.setField(line.obj, column.name,old);
					currentValue = newVal;
					edit();
					(cast element.find("textarea")[0] : js.html.TextAreaElement).setSelectionRange(newVal.length,newVal.length);
					e.preventDefault();
				case K.UP, K.DOWN if( !longText ):
					closeEdit();
					return;
				case K.TAB:
					closeEdit();
					e.preventDefault();
					editor.cursor.move(e.shiftKey ? -1 : 1, 0, false, false);
					var c = editor.cursor.getCell();
					if( c != this ) c.edit();
				}
				e.stopPropagation();
			});
			i.keyup(function(_) try {
				editor.base.parseValue(column.type, i.val());
				setErrorMessage(null);
			} catch( e : Dynamic ) {
				setErrorMessage(StringTools.htmlUnescape(""+e));
			});
			i.keyup(null);
			i.blur(function(_) closeEdit());
			i.focus();
			i.select();
			if( longText ) i.scrollTop(0);
		case TBool:
			setValue( currentValue == false && column.opt && table.displayMode != Properties ? null : currentValue == null ? true : currentValue ? false : true );
			refresh();
		case TProperties, TList:
			@:privateAccess table.toggleList(this);
		case TRef(name):
			var sdat = editor.base.getSheet(name);
			if( sdat == null ) return;
			element.empty();
			element.addClass("edit");

			var s = new Element("<select>");
			var elts = [for( d in sdat.all ){ id : d.id, ico : d.ico, text : d.disp }];
			if( column.opt || currentValue == null || currentValue == "" )
				elts.unshift( { id : "~", ico : null, text : "--- None ---" } );
			element.append(s);

			var props : Dynamic = { data : elts };
			if( sdat.props.displayIcon != null ) {
				function buildElement(i) {
					var text = StringTools.htmlEscape(i.text);
					return new Element("<div>"+(i.ico == null ? "<div style='display:inline-block;width:16px'/>" : tileHtml(i.ico,true)) + " " + text+"</div>");
				}
				props.templateResult = props.templateSelection = buildElement;
			}
			(untyped s.select2)(props);
			(untyped s.select2)("val", currentValue == null ? "" : currentValue);
			(untyped s.select2)("open");

			s.change(function(e) {
				var val = s.val();
				if( val == "~" ) val = null;
				setValue(val);
				closeEdit();
			});
			s.on("select2:close", function(_) closeEdit());
		case TEnum(values):
			element.empty();
			element.addClass("edit");
			var s = new Element("<select>");
			var elts = [for( i in 0...values.length ){ id : ""+i, ico : null, text : values[i] }];
			if( column.opt )
				elts.unshift( { id : "-1", ico : null, text : "--- None ---" } );
			element.append(s);

			var props : Dynamic = { data : elts };
			(untyped s.select2)(props);
			(untyped s.select2)("val", currentValue == null ? "" : currentValue);
			(untyped s.select2)("open");

			s.change(function(e) {
				var val = Std.parseInt(s.val());
				if( val < 0 ) val = null;
				setValue(val);
				closeEdit();
			});
			s.keydown(function(e) {
				switch( e.keyCode ) {
				case K.LEFT, K.RIGHT:
					s.blur();
					return;
				case K.TAB:
					s.blur();
					editor.cursor.move(e.shiftKey? -1:1, 0, false, false);
					var c = editor.cursor.getCell();
					if( c != this ) c.edit();
					e.preventDefault();
				default:
				}
				e.stopPropagation();
			});
			s.on("select2:close", function(_) closeEdit());
		case TColor:
			var modal = new Element("<div>").addClass("hide-modal").appendTo(element);
			var color = new ColorPicker(element);
			color.value = currentValue;
			color.open();
			color.onChange = function(drag) {
				element.find(".color").css({backgroundColor : '#'+StringTools.hex(color.value,6) });
			};
			color.onClose = function() {
				setValue(color.value);
				color.remove();
				closeEdit();
			};
			modal.click(function(_) color.close());
		case TFile:
			ide.chooseFile(["*"], function(file) {
				if( file != null ) {
					setValue(file);
					refresh();
				}
			});
		case TFlags(values):
			var div = new Element("<div>").addClass("flagValues");
			div.click(function(e) e.stopPropagation()).dblclick(function(e) e.stopPropagation());
			var val = currentValue;
			for( i in 0...values.length ) {
				var f = new Element("<input>").attr("type", "checkbox").prop("checked", val & (1 << i) != 0).change(function(e) {
					val &= ~(1 << i);
					if( e.getThis().prop("checked") ) val |= 1 << i;
					e.stopPropagation();
				});
				new Element("<label>").text(values[i]).appendTo(div).prepend(f);
			}
			element.empty();
			var modal = new Element("<div>").addClass("hide-modal").appendTo(element);
			element.append(div);
			modal.click(function(e) {
				setValue(val);
				refresh();
			});
		case TTilePos:
			var modal = new hide.comp.Modal(element);
			modal.element.click(function(_) closeEdit());

			var t : cdb.Types.TilePos = currentValue;
			var file = t == null ? null : t.file;
			var size = t == null ? 16 : t.size;
			var pos = t == null ? { x : 0, y : 0, width : 1, height : 1 } : { x : t.x, y : t.y, width : t.width == null ? 1 : t.width, height : t.height == null ? 1 : t.height };
			if( file == null ) {
				var y = line.index - 1;
				while( y >= 0 ) {
					var o = line.table.lines[y--];
					var v2 = Reflect.field(o.obj, column.name);
					if( v2 != null ) {
						file = v2.file;
						size = v2.size;
						break;
					}
				}
			}

			function setVal() {
				var v : Dynamic = { file : file, size : size, x : pos.x, y : pos.y };
				if( pos.width != 1 ) v.width = pos.width;
				if( pos.height != 1 ) v.height = pos.height;
				setValue(v);
			}

			if( file == null ) {
				ide.chooseFile(["png","jpeg","jpg","gif"],function(path) {
					file = path;
					setVal();
					closeEdit();
					edit();
				});
				return;
			}

			var ts = new hide.comp.TileSelector(file,size,modal.content);
			ts.allowRectSelect = true;
			ts.allowSizeSelect = true;
			ts.allowFileChange = true;
			ts.value = pos;
			ts.onChange = function(rightClick) {
				if( !rightClick ) {
					file = ts.file;
					size = ts.size;
					pos = ts.value;
					setVal();
				}
				refresh();
			};

		case TLayer(_), TTileLayer:
			// no edit
		case TImage:
			// deprecated
		}
	}

	public function setErrorMessage( msg : String ) {
		element.find("div.error").remove();
		if( msg == null )  return;
		new Element("<div>").addClass("error").html(msg).appendTo(element);
	}

	function setRawValue( str : String ) {
		var newValue : Dynamic = try editor.base.parseValue(column.type, str, false) catch( e : Dynamic ) return;
		if( newValue == null || newValue == currentValue )
			return;

		switch( column.type ) {
		case TId:
			var obj = line.obj;
			var prevValue = value;
			// most likely our obj, unless there was a #DUP
			var prevObj = value != null ? table.sheet.index.get(value) : null;
			// have we already an obj mapped to the same id ?
			var prevTarget = table.sheet.index.get(newValue);
			var undo = null;
			if( prevObj == null || prevObj.obj == obj ) {
				// remap
				var m = new Map();
				m.set(value, newValue);
				undo = editor.base.updateRefs(table.sheet, m);
			}
			setValue(newValue, undo);
			// creates or remove a #DUP : need to refresh the whole table
			if( prevTarget != null || (prevObj != null && (prevObj.obj != obj || table.sheet.index.get(prevValue) != null)) )
				table.refresh();
		case TString if( column.kind == Script ):
			setValue(StringTools.trim(newValue));
		default:
			setValue(newValue);
		}
	}

	function setValue( value : Dynamic, ?undo : cdb.Database.Changes ) {
		if( undo == null )
			undo = [];
		currentValue = value;
		undo.push(editor.changeObject(line,column,value));
		editor.addChanges(undo);
	}

	public function closeEdit() {
		var str = element.find("input,textarea").val();
		if( str != null ) setRawValue(str);
		refresh();
		table.editor.element.focus();
	}

}

﻿<cfscript>
component {

	variables.NEWLINE="
";
	variables.TAB = chr(9);
	variables.default={};
	variables.default.browser="html";
	variables.default.console="text";
	variables.supportedFormats=["simple","text","html","classic"];
	
	// Meta data
	this.metadata.hint="Outputs the elements, variables and values of most kinds of CFML objects. Useful for debugging. You can display the contents of simple and complex variables, objects, components, user-defined functions, and other elements.";
	this.metadata.attributetype="fixed";
	this.metadata.attributes={
		var:{required:false,type:"any",hint="Variable to display. Enclose a variable name in pound signs."},
		eval:{required:false,type:"any",hint="name of the variable to display, also used as label, when no label defined."},
		expand:{required:false,type:"boolean",default:true,hint="expands views"},
		label:{required:false,type:"string",default:"",hint="header for the dump output."},
		top:{required:false,type:"number",default:9999,hint="The number of rows to display."},
		showUDFs:{required:false,type:"boolean",default:true,hint="show UDFs in cfdump output."},
		show:{required:false,type:"string",default:"all",hint="show column or keys."},
		output:{required:false,type:"string",default:"browser",hint="Where to send the results:
- console: the result is written to the console (System.out).
- browser (default): the result is written the the browser response stream."},
		metainfo:{required:false,type:"boolean",default:true,hint="Includes information about the query in the cfdump results."},
		keys:{required:false,type:"number",default:9999,hint="For a structure, number of keys to display."},
		hide:{required:false,type:"string",default:"all",hint="hide column or keys."},
		format:{required:false,type:"string",default:"",hint="specify the output format of the dump, the following formats are supported:
- simple: - a simple html output (no javascript or css)
- text (default when output equal console): plain text output (no html)
- html (default when output  equal ""browser""): regular output with html/css/javascript
- classic: classic view with html/css/javascript"},
		abort:{required:false,type:"boolean",default:false,hint="stops further processing of request."},
		contextlevel:{required:false,type:"number",default:2,hidden:true},
		async:{required:false, type="boolean", default=false, hint="if true and output is not to browser, Railo builds the output in a new thread that runs in parallel to the thread that called the dump.  please note that if the calling thread modifies the data before the dump takes place, it is possible that the dump will show the modified data."}
	};


	/* ==================================================================================================
	   INIT invoked after tag is constructed                                                            =
	================================================================================================== */
	void function init(required boolean hasEndTag, component parent) {

		if(server.railo.version LT "3.1.1.011")
			throw message="you need at least version [3.1.1.011] to execute this tag";
	}

	/* ==================================================================================================
	   onStartTag                                                                                       =
	================================================================================================== */
	boolean function onStartTag(required struct attributes, required struct caller) {
		// inital settings

		var attrib = arguments.attributes;

		//eval
		if(not structKeyExists(attrib,'var') and structKeyExists(attrib,'eval')) {
			if(not len(attrib.label))
				attrib['label'] = attrib.eval;

			attrib['var'] = evaluate(attrib.eval, arguments.caller);
		}

		// context
		var context = GetCurrentContext();
		var contextLevel = structKeyExists(attrib,'contextLevel') ? attrib.contextLevel : 2;
		contextLevel = min(contextLevel,arrayLen(context));
		if ( contextLevel gt 0 ) {
			context = context[contextLevel].template & ":" &
					context[contextLevel].line;
		}
		else {
			context = '[unknown file]:[unknown line]';
		}

		// format
		attrib['format'] = trim(attrib.format);

		if(len(attrib.format) EQ 0) {
			if(attrib.output EQ "console")      attrib['format'] = variables.default.console;
			else if(attrib.output EQ "browser") attrib['format'] = variables.default.browser;
			else                                attrib['format'] = variables.default.console;
		}
		else if( !arrayFindNoCase( variables.supportedFormats, attrib.format ) ) {
			throw message="format [#attrib.format#] is not supported, supported formats are [#arrayToList(variables.supportedFormats)#]";
		}

		// create dump struct out of the object
		try {
			var meta = dumpStruct(structKeyExists(attrib,'var') ? attrib.var : nullValue(), attrib.top, attrib.show, attrib.hide, attrib.keys, attrib.metaInfo, attrib.showUDFs, attrib.label);
		}
		catch(e) {
			var meta = dumpStruct(structKeyExists(attrib,'var') ? attrib.var : nullValue(), attrib.top, attrib.show, attrib.hide, attrib.keys, attrib.metaInfo, attrib.showUDFs);
		}
		

		if ( attrib.async && ( attrib.output NEQ "browser" ) ) {

			thread name="dump-#createUUID()#" attrib="#attrib#" meta="#meta#" context="#context#" caller="#arguments.caller#" {

				doOutput( attrib, meta, context, caller );
			}
		} else {

			doOutput( attrib, meta, context, arguments.caller );
		}


		if( attrib.abort )
			abort;

		return true;
	}


	function doOutput( attrib, meta, context, caller  ) {

		var dumpID = createId();

		var hasReference = structKeyExists( arguments.meta,'hasReference' ) && arguments.meta.hasReference;
		var result = this[ arguments.attrib.format ]( arguments.meta, arguments.context, arguments.attrib.expand, arguments.attrib.output, hasReference, 0, dumpID );

		// sleep( 5000 );	// simulate long process to test async=true
		
		if (arguments.attrib.output EQ "browser") {

			echo(variables.NEWLINE & '<!-- ==start== dump #now()# format: #arguments.attrib.format# -->' & variables.NEWLINE);
			echo('<div id="#dumpID#" class="-railo-dump">#result#</div>' & variables.NEWLINE);
			echo('<!-- ==stop== dump -->' & variables.NEWLINE);
		}
		else if (arguments.attrib.output EQ "console") {
			systemOutput(result,true);
		}
		else {
			file action="write" addnewline="yes" file="#arguments.attrib.output#" output="#result#";
		}
	}


	/* ==================================================================================================
	   html                                                                                             =
	================================================================================================== */
	string function html( required struct meta,
						  required string context,
						  required string expand,
						  required string output,
						  required string hasReference ,
						  required string level ,
						  required string dumpID,
						  struct cssColors={}) {
		var NEWLINE=variables.NEWLINE;
		var id = createId();
		var rtn = "";
		var columnCount = structKeyExists(arguments.meta,'data') ? listLen(arguments.meta.data.columnlist) : 0;
		var title = !arguments.level ? ' title="#arguments.context#"' : '';
		var width = structKeyExists(arguments.meta,'width') ? ' width="' & arguments.meta.width & '"' : '';
		var height = structKeyExists(arguments.meta,'height') ? ' height="' & arguments.meta.height & '"' : '';
		var indent = repeatString(variables.TAB, arguments.level);

			rtn&=('<table#width##height##title#>' );

			// title
			if(structKeyExists(arguments.meta, 'title')){
				var metaID = arguments.hasReference && structKeyExists(arguments.meta,'id') ? ' [#arguments.meta.id#]' : '';
				var comment = structKeyExists(arguments.meta,'comment') ? "<br />" & replace(HTMLEditFormat(arguments.meta.comment),chr(10),' <br>','all') : '';

				rtn&=('<tr>');
				rtn&=('<td class="#doCSSColors(arguments.cssColors,arguments.meta.highLightColor)#" onclick="dumpOC(''#id#'');" colspan="#columnCount#" style="cursor:pointer;">');
				rtn&=('<span>#arguments.meta.title##metaID#</span>');
				rtn&=(comment & '</td>');
				rtn&=('</tr>');
			}
			else {
				id = "";
			}

			// data

			if(columnCount) {
				loop query="arguments.meta.data" {
					var c = 1;
					var nodeID = len(id) ? ' name="#id#"' : '';
					var hidden = !arguments.expand && len(id) ? ' style="display:none"' : '';

					rtn&=('<tr#nodeID##hidden#>');

					for(var col=1; col LTE columnCount-1; col++) {
						var node = arguments.meta.data["data" & col];

						if(isStruct(node)) {
							var value = this.html(node, "", arguments.expand, arguments.output, arguments.hasReference, arguments.level+1,arguments.dumpID,arguments.cssColors);

							rtn&=('<td class="#doCSSColors(arguments.cssColors,bgColor(arguments.meta,c))#">');
							rtn&=(value);
							rtn&=('</td>');
						}
						else {
							rtn&=('<td class="#doCSSColors(arguments.cssColors,bgColor(arguments.meta,c))#">' & HTMLEditFormat(node) & '</td>' );
						}
						c *= 2;
					}
					rtn&=('</tr>');
				}
			}
			rtn&=('</table>');

			// Header
			if(arguments.level EQ 0){
				// javascript
				var head=('<script language="JavaScript" type="text/javascript">' & variables.NEWLINE);
				head&=("function dumpOC(name){");
				head&=("var tds=document.all?document.getElementsByTagName('tr'):document.getElementsByName(name);");
				head&=("var s=null;");
				head&=("name=name;");
				head&=("for(var i=0;i<tds.length;i++) {");
				head&=("if(document.all && tds[i].name!=name)continue;");
				head&=("s=tds[i].style;");
				head&=("if(s.display=='none') s.display='';");
				head&=("else s.display='none';");
				head&=("}");
				head&=("}"& variables.NEWLINE);
				head&=("</script>" & variables.NEWLINE);

				// styles
				head&=('<style type="text/css">' & variables.NEWLINE);
				head&=('div###arguments.dumpID# table {font-family:Verdana, Geneva, Arial, Helvetica, sans-serif; font-size:11px; empty-cells:show; color:#arguments.meta.fontColor#; border-spacing: 1px}' & variables.NEWLINE);
				head&=('div###arguments.dumpID# td {border:1px solid #arguments.meta.borderColor#; vertical-align:top; padding:2px; empty-cells:show;}' & variables.NEWLINE);
				head&=('div###arguments.dumpID# td span {font-weight:bold;}' & variables.NEWLINE);
				loop collection="#arguments.cssColors#" item="local.key" {
					head&="td.#key# {background-color:#arguments.cssColors[key]#;}"& variables.NEWLINE;
				}
				head&=('</style>' & variables.NEWLINE);

				rtn=head&rtn;
			}

		return rtn;
	}


	/* ==================================================================================================
	   classic                                                                                          =
	================================================================================================== */
	string function classic( required struct meta,
							 string context = "",
							 string expand = "",
							 string output = "",
							 string hasReference = false,
							 string level = 0,
							 string dumpID = "" ) {

		var id =  createId();
		var rtn = "";
		var columnCount = structKeyExists(arguments.meta,'data') ? listLen(arguments.meta.data.columnlist) : 0;
		var title = !arguments.level ? ' title="#arguments.context#"' : '';
		var width = structKeyExists(arguments.meta,'width') ? ' width="' & arguments.meta.width & '"' : '';
		var height = structKeyExists(arguments.meta,'height') ? ' height="' & arguments.meta.height & '"' : '';
		var indent = repeatString(variables.TAB, arguments.level);

		// define colors
		var h1Color = arguments.meta.highLightColor;
		var h2Color = arguments.meta.normalColor;
		var borderColor = darkenColor( arguments.meta.highLightColor );

		arguments.meta.normalColor = "white";


			if(arguments.level EQ 0){
				// javascript
				rtn&=('<script language="JavaScript" type="text/javascript">' & variables.NEWLINE);
				rtn&=("function dumpOC(name){");
				rtn&=("var tds=document.all?document.getElementsByTagName('tr'):document.getElementsByName(name);" );
				rtn&=("var s=null;");
				rtn&=("name=name;");
				rtn&=("for(var i=0;i<tds.length;i++) {" );
				rtn&=("if(document.all && tds[i].name!=name)continue;");
				rtn&=("s=tds[i].style;" & variables.NEWLINE);
				rtn&=("if(s.display=='none') s.display='';");
				rtn&=("else s.display='none';");
				rtn&=("}" );
				rtn&=("}" & variables.NEWLINE);
				rtn&=("</script>" & variables.NEWLINE);

				// styles
				rtn&=('<style type="text/css">' & variables.NEWLINE);
				rtn&=( 'div###arguments.dumpID# table {font-family:Verdana, Geneva, Arial, Helvetica, sans-serif; font-size:11px; empty-cells:show; color:#arguments.meta.fontColor#; border: 1px solid black; border-collapse:collapse;}' & variables.NEWLINE);
				rtn&=( 'div###arguments.dumpID# td {border:1px solid #arguments.meta.borderColor#; vertical-align:top; padding:2px; empty-cells:show;}' & variables.NEWLINE);
				rtn&=('div###arguments.dumpID# td span {font-weight:bold;}' & variables.NEWLINE);
				rtn&=('</style>' & variables.NEWLINE);
			}

			rtn&=('<table cellspacing="0"#width##height##title# style="color:#arguments.meta.fontColor#; border-color:#borderColor#;">');

			// title
			if(structKeyExists(arguments.meta, 'title')){
				var metaID = arguments.hasReference && structKeyExists(arguments.meta,'id') ? ' [#arguments.meta.id#]' : '';
				var comment = structKeyExists(arguments.meta,'comment') ? "<br />" & replace(HTMLEditFormat(arguments.meta.comment),chr(10),' <br>','all') : '';

				rtn&=('<tr>');
				rtn&=('<td onclick="dumpOC(''#id#'');" colspan="#columnCount#" style="background:#h1Color#; border-color:#borderColor#; color:white;" style="cursor:pointer;">');
				rtn&=('<span>#arguments.meta.title##metaID#</span>');
				rtn&=(comment & '</td>');
				rtn&=('</tr>');
			}
			else {
				id = "";
			}

			// data
			if(columnCount) {
				loop query="arguments.meta.data" {
					var c = 1;
					var nodeID = len(id) ? ' name="#id#"' : '';
					var hidden = !arguments.expand && len(id) ? ' style="display:none"' : '';

					rtn&=('<tr#nodeID##hidden#>');

					for(var col=1; col LTE columnCount-1; col++) {
						var node = arguments.meta.data["data" & col];

						if(isStruct(node)) {
							var value = this.classic(node, "", arguments.expand, arguments.output, arguments.hasReference, arguments.level+1);

							rtn&=('<td style="background:#bgColor(arguments.meta,c,h2Color)#; border-color:#borderColor#;">');
							rtn&=(value);
							rtn&=( '</td>');
						}
						else {
							rtn&=('<td style="background:#bgColor(arguments.meta,c,h2Color)#; border-color:#borderColor#;">' & HTMLEditFormat(node) & '</td>');
						}
						c *= 2;
					}
					rtn&=('</tr>');
				}
			}
			rtn&=('</table>');

		return rtn;
	}

	/* ==================================================================================================
	   simple                                                                                           =
	================================================================================================== */
	string function simple( required struct meta,
							string context = "",
							string expand = "",
							string output = "",
							string hasReference = false,
							string level = 0 ) {

		var rtn = "";
		var col = 0;
		var columnCount = structKeyExists(arguments.meta,'data') ? listLen(arguments.meta.data.columnlist) : 0;
		var width = structKeyExists(arguments.meta,'width') ? ' width="' & arguments.meta.width & '"' : '';
		var height = structKeyExists(arguments.meta,'height') ? ' height="' & arguments.meta.height & '"' : '';
		var indent = repeatString(variables.TAB, arguments.level);


			rtn&=( '<table cellpadding="1" cellspacing="0" border="1" title="#arguments.context#"#width##height#>');

			// title
			if(structKeyExists(arguments.meta, 'title')){
				var metaID = arguments.hasReference && structKeyExists(arguments.meta,'id') ? ' [#arguments.meta.id#]' : '';
				var comment = structKeyExists(arguments.meta,'comment') ? "<br />" & replace(HTMLEditFormat(arguments.meta.comment),chr(10),' <br>','all') : '';

				rtn&=('<tr>');
				rtn&=('<td colspan="#columnCount#" bgcolor="#arguments.meta.highLightColor#">');
				rtn&=('<b>#arguments.meta.title##metaID#</b>');
				rtn&=(comment & '</td>');
				rtn&=('</tr>');
			}

			// data
			var c = 1;
			if(columnCount) {
				loop query="arguments.meta.data" {
					c = 1;

					rtn&=('<tr>');

					for(col=1; col LTE columnCount-1; col++) {
						var node = arguments.meta.data["data" & col];

						if(isStruct(node)) {
							var value = this.simple(node, "", arguments.expand, arguments.output, arguments.hasReference, arguments.level+1);

							rtn&=('<td bgcolor="#bgColor(arguments.meta,c)#">' );
							rtn&=(value);
							rtn&=('</td>');
						}
						else {
							rtn&=('<td bgcolor="#bgColor(arguments.meta,c)#">' & HTMLEditFormat(node) & '</td>');
						}
						c *= 2;
					}
					rtn&=('</tr>');
				}
			}
			rtn&=('</table>');

		return rtn;
	}

	/* ==================================================================================================
	   text                                                                                             =
	================================================================================================== */
	string function text( required struct meta,
						  string context = "",
						  string expand = "",
						  string output = "",
						  string hasReference = false,
						  string level = 0,
						  string parentIndent = "" ) {

		var rtn = "";
		var dataCount = structKeyExists(arguments.meta,'data') ? listLen(arguments.meta.data.columnlist) - 1 : 0;
		var indent = repeatString("    ", arguments.level);
		var type = structKeyExists(arguments.meta,'type') ? arguments.meta.type : '';

		// title
		if(structKeyExists(arguments.meta, 'title')) {
			rtn = trim(arguments.meta.title);
			rtn &= arguments.hasReference && structKeyExists(arguments.meta,'id') ? ' [#arguments.meta.id#]' : '';
			rtn &= structKeyExists(arguments.meta,'comment') ? ' [' & trim(arguments.meta.comment) & ']' : '';
			rtn &= variables.NEWLINE;
		}

		// data
		if(dataCount GT 0) {
			var qRecords = arguments.meta.data;

			loop query="qRecords" {
				var needNewLine = true;

				for(var x=1; x LTE dataCount; x++) {
					var node = qRecords["data" & x];

					if(type EQ "udf") {
						if(needNewLine) {
							rtn &= variables.NEWLINE & arguments.parentIndent;
							rtn &= len(trim(node)) EQ 0 ? "[blank] " : node & " ";
							needNewLine = false;
						}
						else {
							rtn &= len(trim(node)) EQ 0 ? "[blank] " : node & " ";
						}
					}
					else if(isStruct(node)) {
						rtn &= this.text(node, "", arguments.expand, arguments.output, arguments.hasReference, arguments.level+1, indent) & variables.NEWLINE;
					}
					else if(len(trim(node)) GT 0) {
						var test = asc(right(rtn, 1));

						if( test EQ 10 || test EQ 13) {
							rtn &= node & " ";
						}
						else {
							rtn &= node & " ";
						}

					}

				}
			}
		}
		if(arguments.output NEQ "console" && arguments.level EQ 0) {
			return "<pre>" & rtn & "</pre>";
		}

		return rTrim(rtn);
	}

	/* ==================================================================================================
	   helper functions                                                                                 =
	================================================================================================== */
	string function bgColor( required struct meta,
							 required numeric c,
							 string highLightColor = "#arguments.meta.highLightColor#" ) {

		if(arguments.meta.data.highlight EQ -1) {
			return arguments.highLightColor;
		}
		else if(arguments.meta.data.highlight EQ 0) {
			return arguments.meta.normalColor;
		}
		else {
			return bitand(arguments.meta.data.highlight, arguments.c) ? arguments.highLightColor : arguments.meta.normalColor;
		}
	}

	string function createId(){
		return  "x"&(server.railo.version GTE "3.3.0.010"?createUniqueId():hash(createUUID()));
	}


	function doCSSColors(struct data,string color){
		var key=replace(arguments.color,"##","r");
		if(isNumeric(left(key,1)))key="r"&key;


		if(!structKeyExists(arguments.data,key))
			arguments.data[key]=arguments.color;
		return key;
	}


	/** darkens a hex color */
	function darkenColor( color, delta=3 ) {

		if ( len( arguments.color ) != 7 || left( arguments.color, 1 ) != '##' )
			return arguments.color;

		var result = "##";

		for ( var i=2; i<=7; i++ ) {

			var ch = inputBaseN( mid( arguments.color, i, 1 ), 16 );
			ch = max( 0, ch - arguments.delta );
			result &= formatBaseN( ch, 16 );
		}

		return result;
	}


	/** brightens a hex color */
	function brightenColor( color, delta=3 ) {

		if ( len( arguments.color ) != 7 || left( arguments.color, 1 ) != '##' )
			return arguments.color;

		var result = "##";

		for ( var i=2; i<=7; i++ ) {

			var ch = inputBaseN( mid( arguments.color, i, 1 ), 16 );
			ch = min( 15, ch + arguments.delta );
			result &= formatBaseN( ch, 16 );
		}

		return result;
	}

}
</cfscript>
/************************************************************************
* "Epsilon" is a registered trademark licensed to Lugaru Software, Ltd. *
*		"EEL" and "Lugaru" are trademarks of Lugaru Software, Ltd.		*
*																		*
*  Copyright (C) 1985, 1997 Lugaru Software Ltd.  All rights reserved.	*
*																		*
* Limited permission is hereby granted to reproduce and modify this		*
* copyrighted material provided that the resulting code is used only in *
* conjunction with Lugaru products and that this notice is retained in	*
* any such reproduction or modification.								*
************************************************************************/

// This file has commands that deal with command files.

#include "eel.h"

jmp_buf jbuf;
short *keyseq;		/* sequence of key codes, in format used by macros */

command load_file()
{
	char fname[FNAMELEN];

	save_var show_mouse_choices = 1;
	get_file(fname, "Load definitions from file", "");
	if (*fname)
		do_load_file(fname);
}

command load_buffer()
{
	char bname[FNAMELEN], *old = bufname;
	int err;

	get_buf(bname, "Load definitions from buffer", bufname);
	if (exist(bname))
		bufname = bname;
	else
		error("No such buffer");
	err = parse_cmds();
	bufname = old;
	if (err) to_buffer(bname);		/* show offending command */
}

do_load_file(fname)	/* load command file */
char *fname;
{
	int err;
	char *old = bufname, *temp_load;

	temp_load = temp_buf();
	bufname = temp_load;
	filename = fname;
	if (err = do_file_read(fname, FILETYPE_MSDOS)) {
		file_error(err, fname, "read error");
		maybe_ding(bell_on_read_error);
	} else if (parse_cmds()) {
		bufname = old;
		to_buffer(temp_load);	/* show bad commands in window */
		quick_abort();
	}
	bufname = old;
	delete_buffer(temp_load);
}

load_cmd_file_from_path(fname)
char *fname;
{
	char *s;

	if (!(s = lookpath(fname, 1)))
		error("Can't find %s", fname);
	do_load_file(s);
}

// Create an EEL color settings file from the changes file
// written by an older version of Epsilon (v7 or before).
// V8.0's changes file doesn't include 32-bit color information--
// load color customizations in v8.0 from the appropriate EEL file.

command import_colors()
{
	char name[FNAMELEN];
	int tmp, i;

	get_file(name, "Load changes from file", "changes");
	tmp = tmp_buf();
	to_buffer_num(tmp);
	if (read_file(name, FILETYPE_MSDOS))
		quick_abort();

	strcpy(name, "mycolors.e");
	absolute(name);
	if (warn_existing_file(name))
		return;
	do_find(name, FILETYPE_MSDOS);
	buf_zap(bufnum);
	grab_buffer(tmp);
	point = 0;
	do_drop_matching_lines(REGEX, "^&.* color class for ", 0);
	while (re_search(1, ": *([0-9a-fx]+)$")) {
		grab(find_group(1, 1), find_group(1, 0), name);
		point = find_group(1, 1);		// Change old-style color numbers
		delete(point, find_group(1, 0));	// to names.
		i = numtoi(name);
		give_color_combo(name, i);
		stuff(name);
	}
	point = 0;
	for (i = 0; i < 10; i++) {	// Assume class names have no more than 10 -'s.
		noteput("Working... %d%%", 20 + i * 5);
		string_replace("(color class for .*)-", "#1_", REGEX);	// Conv to _'s.
		if (!replace_num_changed)
			break;
	}

	noteput("Working... 70%%");
	// Make into valid EEL definitions.
	string_replace("^&(.*) color class for (.*): (.*)",
				   "color_scheme \"#1\" color_class #2 #3;", REGEX);
	noteput("Working... 80%%");
	// Convert pre-v8 color names to EEL names.
	string_replace(" (blue|green|cyan|red|magenta)", " dark_#1", REGEX);
	string_replace(" white", " grey", REGEX);
	string_replace(" brightblack", " dark_grey", REGEX);
	noteput("Working... 90%%");
	string_replace(" bright(blue|green|cyan|red|magenta|white)", " #1", REGEX);

	stuff("// Automatically generated by import-colors.\n");
	stuff("// Save this file, then press Alt-F3 to import colors.\n\n");
	stuff("#include \"eel.h\"\n\n");
	point = 0;
	buf_delete(tmp);
	say("Done.");
}

// Create an EEL file with the current color settings.

command export_colors()
{
	char name[FNAMELEN], *nm;
	int i, j, fg, bg, max = final_index();

	strcpy(name, "mycolors.e");
	absolute(name);
	if (warn_existing_file(name))
		return;
	do_find(name, FILETYPE_MSDOS);
	buf_zap(bufnum);
	stuff("// Automatically generated by export-colors.\n\n");
	stuff("#include \"eel.h\"\n\n");
	save_var selected_color_scheme;
	for (i = 1; i <= max; i++) {
		check_abort();
		if (name_type(i) != NT_COLSCHEME)
			continue;
		nm = name_name(i);
		noteput("Working...%s", nm);
		bprintf("color_scheme \"%s\" {\n", nm);
		selected_color_scheme = i;
		for (j = 0; j < number_of_color_classes(); j++) {
			bprintf("\tcolor_class %s ", name_color_class(j));
			fg = get_foreground_color(j);
			bg = get_background_color(j);
			if (matches_previous_color_class(j, fg, bg))
				continue;
			bprintf("MAKE_RGB(%d, %d, %d)",
					GETRED(fg), GETGREEN(fg), GETBLUE(fg));
			if (!j || !(bg & ctransparent)
				&& bg != get_background_color(0))
				bprintf(" on MAKE_RGB(%d, %d, %d)",
						GETRED(bg), GETGREEN(bg), GETBLUE(bg));
			stuff(";\n");
		}
		stuff("};\n\n");
	}
	restore_vars();
	point = 0;
	for (i = 0; i < 10; i++) {	// Assume class names have no more than 10 -'s.
		noteput("Working...%d", i);
		string_replace("(color_class .*)-", "#1_", REGEX);
		if (!replace_num_changed)	// Convert -'s in class names to _'s.
			break;
	}
	substitute_color_names();
	say("Done.");
}

// Perhaps record this color class as a copy of a prior one, if this
// seems appropriate.

matches_previous_color_class(j, fg, bg)
{
	int i;

	if (j == color_class default)
		return 0;
	for (i = 0; i < j; i++) {
		if (fg != get_foreground_color(i) || bg != get_background_color(i)
			|| i == color_class echo_area || i == color_class after_exiting
			|| i == color_class debug_text)
			continue;
		if (i == color_class mode_line && j > color_class vert_border)
			continue;
		bprintf("= color_class %s;\n", name_color_class(i));
		return 1;
	}
	return 0;
}

// Replace MAKE_RGB() references in the current buffer with
// the matching color names by interpreting the codes.h file.

substitute_color_names()
{
	char *codes, name[100], defn[100];
	int tmp, orig = bufnum;

	codes = lookpath("codes.h");
	if (!codes)
		codes = lookpath("include\\codes.h");
	if (!codes)
		error("Can't locate codes.h to substitute color names");
	bufnum = tmp = tmp_buf();
	if (err_file_read(codes, FILETYPE_MSDOS))
		quick_abort();
	filename = "";	// Don't accidentally overwrite the real codes.h.
	save_var case_fold = 1;
	if (!re_search(1, "#define[ \t]+black"))
		error("Can't locate start of color names");
	delete(0, give_begin_line());
	if (!re_search(1, "#define[ \t]+ctransparent"))
		error("Can't locate end of color names");
	delete(give_begin_line(), size());
	point = 0;
	string_replace(",[ \t]*", ", ", REGEX);	// standardize MAKE_RGB() calls
	while (re_search(1, "#define[ \t]+")) {
		if (!parse_string(1, "[a-z0-9_]+", name))
			error("Can't interpret color name");
		point += parse_string(1, "[ \t]*");
		if (!parse_string(1, "MAKE_RGB%([a-z0-9, \t]+%)", defn))
			error("Can't interpret color definition");
		bufnum = orig;
		string_replace(defn, name, 0);
		bufnum = tmp;
	}
}

command load_changes()
{
	char name[FNAMELEN], *tmp;
	int i;

	get_file(name, "Load changes from file", "changes");
	tmp = temp_buf();
	to_buffer(tmp);
	if (read_file(name, FILETYPE_MSDOS))
		quick_abort();
	point = 0;
	string_replace("%+(maxmem|minmem|m?colors|normal-cursor"
				   "|-display-characters|buf-accessed-clock"
				   "|-errors-in-cmd-file|-prev-kbd-extended) .*\n",
		       "", REGEX);
	if (re_search(1, "^%&.*\n"))
		bprintf("# COLOR SETTINGS IGNORED: use import-colors\n");
	point = 0;
	string_replace("^%&.*\n", "", REGEX);	// discard color info
	save_var _abort_load_on_error = 0;
	parse_cmds();
	point = 0;
	i = is_gui ? _our_gui_scheme
		   : monochrome ? _our_mono_scheme : _our_color_scheme;
	if (name_type(i) == NT_COLSCHEME)
		selected_color_scheme = i;
}

parse_cmds()	/* load cmds in current buf, return 1 if error occurred */
{
	point = 0;
	_errors_in_cmd_file = 0;
	if (setjmp(&jbuf))			/* errors come here */
		if (_abort_load_on_error)
			return 1;
	for (;;) {
		re_search(1, "[ \n\t]*");	/* skip whitespace */
		if (point >= size() - narrow_end)
			break;
		noteput("Loading: %d%%...", point * 100 / size());
		switch (curchar()) {
			case ';':		/* found comment */
			case '#': nl_forward(); break;
			case '(': paren_cmds(); break;
			case '+': load_var(); break;
			case '~': load_binding(); break;
			case '&': load_color(); break;
			default:  load_other(); break;
		}
	}
	copy_bindings();
	say("%d errors detected.", _errors_in_cmd_file);
	return _errors_in_cmd_file != 0;
}

load_var()	/* variable definition */
{
	int i, new_type, vtype, hasnum;
	char name[80], junk[80], num[20], *p, *tmp;

	point++;			/* skip initial + */
	parse_string(1, "[^ \t\n:]+", name);
	i = find_index(name);
	new_type = parse_string(1, " buffer", junk)
			? NT_BUFVAR : parse_string(1, " window", junk)
			? NT_WINVAR : NT_VAR;
	if (parse_string(1, " (char ptr )?variable: %<complex>", junk)) {
		if (i <= 0 || name_type(i) != new_type)
			init_error("variable %s too complex to define", name);
		nl_forward();
		return;
	} else if (parse_string(1, " char array ", junk))
		vtype = TYPE_CARRAY;
	else if (parse_string(1, " int ", junk))
		vtype = TYPE_INT;
	else if (parse_string(1, " short ", junk))
		vtype = TYPE_SHORT;
	else if (parse_string(1, " char ", junk))
		vtype = TYPE_CHAR;
	else
bad:		init_error("bad definition for variable %s", name);
	if (!parse_string(1, "variable: ", junk))
		goto bad;
	hasnum = parse_string(1, "[-0-9][a-zA-Z0-9]*", num);
	if (vtype == TYPE_CARRAY) {
		if (i <= 0 && hasnum)
			i = new_variable(name, new_type,
				TYPE_CARRAY, numtoi(num));
		if (!parse_string(1, " *<dquote>", junk)
				|| name_type(i) != new_type
				|| vartype(i) != TYPE_CARRAY)
			goto bad;
		use_default = 1;
		tmp = p = varptr(i);
		use_default = 0;
		for (; curchar() != '"'; point++) {
			if (curchar() != '\\') {
				*p++ = curchar();
				continue;
			}
			point++;
			switch (curchar()) {
				case 't': *p++ = '\t'; break;
				case 'r': *p++ = '\r'; break;
				case 'n': *p++ = '\n'; break;
				case 'z': *p++ = 0; break;
				default: *p++ = curchar();
			}
		}
		while (p - tmp < ptrlen(tmp))
			*p++ = 0;
		if (!parse_string(1, "<dquote>$", junk))
			goto bad;
	} else if (vtype) {
		if (i <= 0)
			i = new_variable(name, new_type, vtype, 1);
		if (!hasnum && parse_string(1, ".*", junk))
			sprintf(num, "%d", find_index(junk));
		set_var_val(i, num, 1);
	}
}

load_color()
{
	int i, j, fore, back;
	char scheme[80], class[80], num[50];

	point++;			/* skip initial & */
	parse_string(1, "[^ \t\n:]+", scheme);
	i = find_index(scheme);
	if (!parse_string(1, " color class for ", class)
			|| !parse_string(1, "[^ \t\n:]+", class)
			|| !parse_string(1, ": ", num)
			|| !parse_string(1, "%[?[-a-zA-Z0-9]+", num))
		init_error("bad color definition for %s", scheme);
	if (i <= 0)
		i = new_variable(scheme, NT_COLSCHEME, 0);
	for (j = 0; strcmp(class, name_color_class(j)); )
		if (++j >= number_of_color_classes())
			init_error("undefined color class %s", class);
	if (*num == '[') {		// rgb-style definition
		fore = numtoi(num + 1);
		if (!parse_string(1, " on ", num)
			|| !parse_string(1, "[0-9a-fx]+]", num))
			init_error("bad rgb color definition for %s", scheme);
		back = numtoi(num);
	} else {
		fore = find_color_code(num);
		if (fore < 0)
			init_error("bad color name %s", num);
		if (parse_string(1, " on ", num)
			&& parse_string(1, "[-a-zA-Z0-9]+", num)) {
			back = find_color_code(num);
			if (back < 0)
				init_error("bad color name %s", num);
		}
		fore = attr_to_rgb(fore);
		back = attr_to_rgb(back);
	}
	save_var selected_color_scheme = i;
	set_color_pair(j, fore, back);
}

char color_names[] = "|black|blue|green|cyan|red|magenta|brown|white|"
		     "brightblack|brightblue|brightgreen|brightcyan|"
		     "brightred|brightmagenta|yellow|brightwhite|";

give_color_name(s, i)	// copy name of color i (0..15) into char array
char *s;
{
	char *p;
	int len;

	strcpy(s, "unknown");
	if (i < 0 || i > 15)
		return;
	for (p = color_names + 1; i > 0; i--, p++)
		if (!(p = index(p, '|')))
			return;
	len = index(p, '|') - p;
	strncpy(s, p, len);
	s[len] = 0;
}

give_color_combo(s, i)	// copy name of color combo i (0..255) into char array
char *s;
{
	if (i < 256) {
		give_color_name(s, i & 15);
		s += strlen(s);
		s += sprintf(s, " on ");
		give_color_name(s, (i >> 4) & 15);
	} else
		sprintf(s, "0x%x", i);
}

find_color_code(s)	// return 0..15 for given color code, or -1 if bad
char *s;
{
	char pat[50], *p, *q;
	int i;

	if (isdigit(*s))
		return numtoi(s);
	sprintf(pat, "|%s|", s);
	p = strstr(color_names, pat);
	if (!p)
		return -1;
	for (i = 0, q = color_names + 1; q < p; q++, i++)
		if (!(q = index(q, '|')))
			return -1;
	return i;
}

load_binding()		/* new-style binding declaration */
{
	char name[80], junk[80];
	short *tab, *onekey;
	int i, now_type;

	point++;			/* skip initial ~ */
	parse_string(1, "[^ \t\n:]+", name);
	i = find_index(name);
	now_type = (i > 0) ? name_type(i) : -1;
	if (now_type != NT_TABLE)
		init_error("%s is not a table", name);
	tab = index_table(i);
	point++;			/* skip space before key */
	onekey = get_keycode();
	if (!onekey || onekey[0] != 2 || !parse_string(1, ": ", junk)
				|| !parse_string(1, ".*", name))
		init_error("bad key binding in %s", name);
	i = find_index(name);
	if (i <= 0) {		/* allow name table index too */
		i = numtoi(name);
		if (!i && *name != '0')	/* not a name, not a number */
			init_error("no such command %s", name);
	}
	tab[onekey[1]] = i;
	rebuild_menu();
}

load_other()
{
	char name[80], junk[20];
	int i;

	parse_string(1, "[^ :]+", name);
	i = find_index(name);
	if (parse_string(1, ": macro ", junk)) {
		get_keyseq();
		if (i > 0)
			drop_name(name);
		name_macro(name, keyseq);
	} else if (parse_string(1, ": table", junk)) {
		if (i > 0) {
			if (name_type(i) == NT_TABLE)
				return;
			drop_name(name);
		}
		new_table(name);
	} else if (parse_string(1, ": command", junk)) {
		if (i <= 0 || name_type(i) != NT_COMMAND
		    && name_type(i) != NT_AUTOLOAD)
			init_error("%s is not a currently defined command",
				name);
	} else if (parse_string(1, ": subroutine", junk)) {
		if (i <= 0 || name_type(i) != NT_SUBR
		    && name_type(i) != NT_AUTOSUBR)
			init_error("%s is not a currently defined subroutine",
				name);
	} else
		init_error("%s: unrecognized syntax", name);
}

paren_cmds()		/* handle parenthesized commands */
{
	char funcname[80];

	must_char('(');
	re_search(1, "[ \t\n]*");
	parse_string(1, "[^ \t\n]*", funcname);
	if (!strcmp(funcname,"define-macro"))
		cf_macro();
	else if (!strcmp(funcname, "bind-to-key"))
		cf_bind();
	else if (!strcmp(funcname, "create-prefix-command"))
		cf_prefix();
	else
		init_error("bad command %s in command file ", funcname);
	re_search(1, "[ \t\n]*");
	must_char(')');
}

cf_macro()		/* handle define-macro */
{
	char name[80];

	get_str(name);
	get_keyseq();
	name_macro(name, keyseq);
}

cf_bind()		/* handle bind-to-key */
{
	int index;
	char name[80];

	get_str(name);
	index = find_index(name);
	if (index)
		put_on_key(index);
	else
		init_error("no such command %s", name);
	rebuild_menu();
}

cf_prefix()		/* handle create-prefix-command */
{
	put_on_key(make_anon_keytable());
}

put_on_key(index)		/* parse key seq and bind it to index */
{
	short *curtab;
	int c, i = 1;

	get_keyseq();
	curtab = root_keys;
	for (;;) {
		c = keyseq[i];
		if (++i >= keyseq[0]) break;
		if (name_type(curtab[c]) != NT_TABLE)
			init_error("expected \" in sequence%s", "");
		curtab = index_table(curtab[c]);
	}
	curtab[c] = index;
}

get_keyseq()			/* parse key names, put keys in keyseq */
{
	re_search(1, "[ \t\n]*");
	keyseq = get_keycode();
	if (!keyseq)
		init_error("bad character%s", "");
}

get_str(s)		/* get a quoted string, and put it in s */
char *s;
{
	re_search(1, "[ \t\n]*");
	must_char('"');
	parse_string(1, "<^dquote>*", s);
	must_char('"');
}

must_char(c)	/* move past current character, making sure that it's c */
{
	char buf[2];

	if (curchar() != c) {
		sprintf(buf,"%c", c);
		init_error("expected %s", buf);
	} else
		point++;
}

have_char(c)	/* if this character is c, move past and return 1, else 0 */
{
	int res = (curchar() == c);

	if (res) point++;
	return res;
}

init_error(msg, s)		/* display error and abort loading */
char *msg, *s;
{
	_errors_in_cmd_file++;
	if (_abort_load_on_error)
		say(msg, s);
	else {
		if (!nl_forward())
			insert('\n');
		stuff("# COMMAND FILE ERROR: ");
		bprintf(msg, s);
		stuff("\n");
	}
	longjmp(&jbuf, 1);
}

command insert_macro()		/* insert command-file definition of macro */
{
	char name[80];
	int i;

	save_var show_mouse_choices = 1;
	get_macname(name, "Insert macro", "last-kbd-macro");
	i = find_index(name);
	if (i && name_type(i) == NT_MACRO) {
		bprintf("(define-macro \"%s\" ", name);
		stuff_macro(get_macro(i), 0);
		stuff(")\n");
	} else
		error("Not a macro");
}

command insert_binding()
{
	char name[80];
	int index;

	index = *ask_key("Save binding of key: ", name);
	if (index <= 0)
		error("Key not bound");
	bprintf("(bind-to-key \"%s\" ", name_name(index));
	stuff_macro(key_binding, 1);
	bprintf(")\n");
}

stuff_macro(m, oneline)	/* insert cmd-file format macro text in buffer */
short *m;		// if oneline, use \n instead of actual newline
{
	char tmp[100];
	int i, prev;

	stuff("\"");
	for (i = 1; i < m[0]; i++)
		switch (m[i]) {
			case '-':	prev = character(point - 1);
					if (index("ACSFMN", prev))
						insert('\\');
				/* "F-1" in text resembles special key */
			default:			/* fall through */
					if (!oneline && m[i] == '\n') {
						insert('\n');
						break;
					}
					tmp[0] = 0;
					show_char(tmp, m[i]);
					stuff(tmp);
					break;
			case CTRL('\\'):
					stuff("C-\\\\"); break;
			case ALT(CTRL('\\')):
					stuff("C-A-\\\\"); break;
			case ALT('<'):
			case ALT('"'):
			case ALT('\\'):	stuff("A-");	/* fall through */
			case '<':		/* quote these */
			case '"':
			case '\\':	insert('\\');
					insert(m[i] & 0x7f);
					break;
		}
	stuff("\"");
}

list_color_scheme(i)
{
	char colorpair[100];
	int j, fg, bg;

	save_var selected_color_scheme = i;
	for (j = 0; j < number_of_color_classes(); j++) {
		fg = get_foreground_color(j);
		if (fg & ctransparent)
			fg = get_foreground_color(0);
		bg = get_background_color(j);
		if (bg & ctransparent)
			bg = get_background_color(0);
		if (fg == attr_to_rgb(rgb_to_attr(fg))
			&& bg == attr_to_rgb(rgb_to_attr(bg)))
			give_color_combo(colorpair, alter_color(j, -1));
		else
			sprintf(colorpair, "[0x%x on 0x%x]", fg, bg);
		bprintf("&%s color class for %s: %s\n",
				name_name(i), name_color_class(j), colorpair);
	}
}

command list_colors()
{
	int i, max = final_index();

	tiled_only();
	zap("list-colors");
	to_buffer("list-colors");
	for (i = 1; i <= max; i++) {
		check_abort();
		if (name_type(i) == NT_COLSCHEME)
			list_color_scheme(i);
	}
	point = 0;
}

command list_all()
{
	int i, j, last, val, type, max = final_index(), percent, opercent = -1;
	char tabname[80], *p, *nm, *tname;
	short *k, onekey[2];

	tiled_only();
	onekey[0] = 2;
	zap("list-all");
	to_buffer("list-all");
	save_var use_default;
	for (i = 1; i <= max; i++) {
		check_abort();
		nm = name_name(i);
		percent = i * 100 / max;
		if (opercent != percent) {
			noteput("Describing state: %d%%...", percent);
			opercent = percent;
		}
		switch (name_type(i)) {
		case NT_COMMAND:
		case NT_AUTOLOAD:
			bprintf("%s: command\n", nm); break;
		case NT_SUBR:
		case NT_AUTOSUBR:
			bprintf("%s: subroutine\n", nm); break;
		case NT_MACRO:
			bprintf("%s: macro ", nm);
			stuff_macro(get_macro(i), 1);
			insert('\n');
			break;
		case NT_TABLE:
			bprintf("%s: table\n", nm);
			strcpy(tabname, nm);
			k = index_table(i);
			for (j = 0; j < NUMKEYS; j++) {
				if (k[j] <= 0)
					continue;
				bprintf("~%s ", tabname);
				onekey[1] = j;
				stuff_macro(onekey, 1);
				bprintf(": %s\n", name_name(k[j]));
			}
			break;
		case NT_WINVAR:
		case NT_BUFVAR: case NT_VAR:
			use_default = 1;
			p = varptr(i);
			type = 0;
			switch (vartype(i)) {
				case TYPE_CHAR:	val = *(char *) p;
						tname = "char ";
						break;
				case TYPE_SHORT: val = *(short *) p;
						tname = "short ";
						break;
				case TYPE_INT:	val = *(int *) p;
						tname = "int ";
						break;
				case TYPE_CPTR:	tname = "char ptr ";
						type = 2; break;
				case TYPE_CARRAY: tname = "char array ";
						type = 1; break;
				default:	tname = ""; type = 2; break;
			}
			bprintf("+%s %s%svariable", nm,
					(name_type(i) == NT_WINVAR)
					? "window " :
					(name_type(i) == NT_BUFVAR)
					? "buffer " : "", tname);
			if (type == 0)
				bprintf(": %d\n", val);
			else if (type == 2)
				stuff(": <complex>\n");
			else {
				last = ptrlen(p);
				bprintf(": %d \"", last);
				while (last > 0 && !p[last - 1])
					last--;
				for (j = 0; j < last; j++)
					switch (p[j]) {
					case '\t':	stuff("\\t"); break;
					case '\r':	stuff("\\r"); break;
					case '\n':	stuff("\\n"); break;
					case 0:		stuff("\\z"); break;
					case '\\':
					case '"':	insert('\\');
					default:	insert(p[j]); break;
					}
				stuff("\"\n");
			}
			use_default = 0;
			break;
//		case NT_COLSCHEME:
//			list_color_scheme(i);
//			break;
		}
	}
	point = 0;
	save_var abort_searching = 0;	// use names for color schemes
	while (re_search(1, "^%+-our-(color|mono|gui)-scheme .*: ")) {
		parse_string(1, "[0-9]+", tabname);
		if (i = numtoi(tabname)) {
			delete(matchstart, matchend);
			bprintf("%s", name_name(i));
		}
	}
	point = 0;
	say("");
}

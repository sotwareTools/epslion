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

// This file has commands related to the display.

#include "eel.h"
#include "lowlevel.h"

command set_show_graphic() on reg_tab[FCTRL(6)]
{	/* cycle through the four methods of displaying ctrl & meta chars */
	int mode;

	if (!has_arg)	/* determine old mode */
		mode = (get_show_graphic() + 1) % 4;	/* get to next mode */
	else
		mode = iter % 4;
	switch (mode) {
		case 0: say("Displaying control and meta characters "
			    "as ^A or M-p. [Mode 0]");
			break;
		case 1:	say("Displaying graphic symbols for control "
			    "and meta characters. [Mode 1]");
			break;
		case 2:	say("Displaying control and meta characters "
			    "in hexadecimal. [Mode 2]");
				break;
		case 3:	say("Displaying control characters as ^A, "
					"meta as graphic symbol. [Mode 3]");
	}
	iter = 1;
	do_set_show_graphic(mode);
}

get_show_graphic()	// what's mode code for current graphic representation?
{
	switch (_display_class[0]) { /* check value for null char */
		case BNORMAL: return 1;
		case BHEX: return 2;
	}
	return _display_class[128] == BNORMAL ? 3 : 0;	// int'l vs multi-char
}

do_set_show_graphic(mode)	// set graphic rep by mode code
{				// 0: multi-char, 1: graphic, 2: hexadecimal, 3: int'l
	int i, std, stdctrl;

	if (show_spaces && _display_class == _show_disp_class)
		save_var _display_class = _std_disp_class;
	std = (mode == 0) ? BM : (mode == 2) ? BHEX : BNORMAL;
	stdctrl = (mode == 3) ? BC : std;
	for (i = 0; i < 128; i++)
		if (i < 32 || i == 127) {
			if (i != '\n' && i != '\t')
				_display_class[i] = mode ? stdctrl : BC;
			_display_class[i + 128] = mode ? std : BMC;
		} else {
			_display_class[i] = BNORMAL;
			_display_class[i + 128] = std;
		}
	make_show_spaces();
	full_redraw = 1;
}

make_show_spaces()	// set show-spaces versions of two arrays
{
	int i, ansi_font;
	char *p;

	ansi_font = !using_oem_font(window_to_screen(window_handle));
	if (_show_disp_class) {
		for (i = 0; i < 256; i++)
			_show_disp_class[i] = _std_disp_class[i];
		_show_disp_class[' '] = ansi_font ? 183 : 250;
	}
	if (_show_disp_chars) {
		for (i = 0; i < NUMDISPCHARS + 1; i++)
			_show_disp_chars[i] = _display_characters[i];
		p = _show_disp_chars + NUMLINECHARS + NUMCORNERCHARS;
		p[3] = ansi_font ? 187 : 0x1a;	// tab
		p[4] = ansi_font ? 182 : 0x11;	// newline
	}
}

command change_show_spaces() on reg_tab[FSHIFT(6)]
{
	show_spaces = has_arg ? (iter != 0) : !show_spaces;
	iter = 0;
	when_setting_show_spaces();
	say("%s spaces in this buffer.", show_spaces ? "Showing" : "Hiding");
}

when_setting_show_spaces()
{
	last_show_spaces = show_spaces;
	if (show_spaces) {
		if (!_show_disp_class)
			_show_disp_class = malloc(256);
		if (!_show_disp_chars)
			_show_disp_chars = malloc(NUMDISPCHARS + 1);
		make_show_spaces();
	}
	if (show_spaces && _display_class == _std_disp_class)
		_display_class = _show_disp_class;
	else if (!show_spaces && _display_class == _show_disp_class)
		_display_class = _std_disp_class;
	buffer_display_characters = show_spaces ? _show_disp_chars : 0;
	full_redraw = 1;
}

command ansi_to_oem()
{
	maybe_oem_ansi_translate(1);
}

command oem_to_ansi()
{
	maybe_oem_ansi_translate(0);
}

#define TRANSLATE_SIZE	1024

ask_oem_ansi_translate(int to_oem)	// Returns 0 if we should cancel.
{
	char msg[200];

	if (test_oem_ansi_translate(to_oem))
		return 1;
	sprintf(msg, "This buffer contains characters that may not have "
			"unique%s translations.  Proceed?",
			to_oem ? " DOS/OEM" : " Windows ANSI");
	return ask_yn("Information may be lost", msg, "Yes", "No", 1);
}

maybe_oem_ansi_translate(int to_oem)
{
	if (!ask_oem_ansi_translate(to_oem))
		return;
	save_var window_start;
	oem_ansi_translate(to_oem);
	say("Done.");
}

oem_ansi_translate(int to_oem)
{
	char buf[TRANSLATE_SIZE + 1];

	save_var point = 0;
	save_var narrow_start = 0, narrow_end = 0;
	do {
		grab(point, point + TRANSLATE_SIZE, buf);

		if (is_gui == IS_WIN31)
			call_dll("keyboard.drv", to_oem ? "AnsiToOem" : "OemToAnsi",
					 "p", "ss", buf, buf);
		else
			call_dll("user32.dll", to_oem ? "CharToOemA" : "OemToCharA",
					 "p", "ss", buf, buf);

		delete(point, point + TRANSLATE_SIZE);
		stuff(buf);
	} while (point < size());
}

// Is this conversion reversible?  Return nonzero if so.
test_oem_ansi_translate(int to_oem)
{
	int tmp = tmp_buf(), orig = bufnum, diff;

	bufnum = tmp;
	grab_buffer(orig);
	oem_ansi_translate(to_oem);
	bufnum = tmp;
	oem_ansi_translate(!to_oem);
	bufnum = orig;
	diff = compare_buffer_text(orig, 0, tmp, 0, 0);
	buf_delete(tmp);
	if (diff == size())
		return 1;
	point = diff;		// Go to 1st char w/o reversible translation.
	return 0;
}

char *oem_file_converter(int func)
{
	int write = (func & FILE_CONVERT_WRITE) != 0;

	if (func & FILE_CONVERT_ASK)
		return ask_oem_ansi_translate(write) ? "OK" : NULL;
	if (func & (FILE_CONVERT_READ | FILE_CONVERT_WRITE))
		oem_ansi_translate(write);
	return " OEM";
}

command find_oem_file()
{
	save_var new_file_io_converter = oem_file_converter;
	find_file();
}

// Write this buffer to a file; retrieve current file info
// after writing and return error code.  If necessary, do char set 
// conversion first (and warn/abort if some characters don't convert).

file_convert_write(char *fname, int trans, struct file_info *finfo)
{
	int tmp, err, mod;
	char *(*func)();

	if (is_remote_file(fname))
		return save_remote_file(fname, trans, finfo);
	if (!file_io_converter)
		return new_file_write(fname, trans, finfo, -1, -1);
	if (!file_io_converter(FILE_CONVERT_WRITE | FILE_CONVERT_ASK))
		error("Canceled.");
	func = file_io_converter;
	tmp = tmp_buf();
	buf_xfer(tmp, 0, size());
	save_var bufnum = tmp;
	func(FILE_CONVERT_WRITE);
	err = new_file_write(fname, trans, finfo, -1, -1);
	mod = modified;
	restore_vars();
	modified = mod;
	return err;
}

// After reading a file, call this to convert its character set if needed.

file_convert_read()
{
	if (file_io_converter)
		if (file_io_converter(FILE_CONVERT_READ | FILE_CONVERT_ASK)) {
			save_var modified;
			file_io_converter(FILE_CONVERT_READ);
		} else
			file_io_converter = 0;	// Don't convert on write either.
}

command set_tab_size()
{
	tab_size = get_number("Tab size: ");
	if (tab_size < 2 || tab_size > 256)
		tab_size = 8;
	say("Tab size is %d in this buffer.", tab_size);
	build_first = 1;
}

maybe_ding(want) /* ring if we want this type of bell & want bell generally */
{
	if (want && want_bell)
		ding();
}

show_window_caption()
{
	if (is_gui && is_window(window_handle) == ISTILED) {
		char *s = get_tail(filename, 1);
		char title[FNAMELEN];

		if (s && *s && force_save_as != FSA_NEWFILE)
			sprintf(title, window_caption_file, s);
		else
			sprintf(title, window_caption);
		set_window_caption(window_handle, title);
	}
}

fix_cursor()	// make cursor be the right shape
{		// Epsilon calls while drawing screen
	if (cursor_to_column >= 0 && !in_echo_area && !_doing_input) {
		cursor_shape = over_mode ? virtual_overwrite_cursor
					 : virtual_insert_cursor;
		gui_cursor_shape = over_mode ? virtual_overwrite_gui_cursor
					 : virtual_insert_gui_cursor;
	} else {
		cursor_shape = over_mode ? overwrite_cursor : normal_cursor;
		gui_cursor_shape = over_mode ? overwrite_gui_cursor
						   : normal_gui_cursor;
	}
	show_window_caption();
	check_rebuild_menu();
	show_screen_size();
}

make_mode()	/* tell eps to rebuild mode line for each window showing */
{		/* this buf */
	must_build_mode = 1;
}

prepare_windows()	/* fix up borders before each window */
{			/* is displayed */
	int i = -1, j = 0, popup, wantmode;

	if (show_spaces != last_show_spaces || using_new_font)
		when_setting_show_spaces();
	popup = (is_window(window_handle) == ISPOPUP);
	_window_flags &= ~WANT_MODE_LINE;
	wantmode = popup ? (_window_flags & FORCE_MODE_LINE)
			 : !(_window_flags & NO_MODE_LINE);
	if (wantmode) {
		_window_flags |= WANT_MODE_LINE;
		j = BORD(MODE_EDGE, -1);
	}
	if (!popup) {
		tiled_window_colors();	// set color scheme for tiled window
		j = tiled_window_border(j);
		if (!(_window_flags & FIXED_BORDERS))
			display_scroll_bar = tiled_scroll_bar && !is_gui;
		i = tiled_border & j;
	} else if (wantmode) {
		i = get_wattrib(window_number, PBORDERS);
		if (!(i & BORD(MODE_EDGE, -1)))
			i |= tiled_border & BORD(MODE_EDGE, -1);
	}
	if (i != -1 && !(_window_flags & FIXED_BORDERS))
		set_wattrib(window_number, PBORDERS, i);
}

build_mode()	/* construct mode line for this window */
{
	char mode_line[FNAMELEN];

	if (_window_flags & WANT_MODE_LINE) {
		assemble_mode_line(mode_line);
		window_title(window_number, MODE_EDGE, mode_line_position,
			mode_line);
	}
}

assemble_mode_line(m)	/* construct mode line in m */
char *m;
{
	int i, left;
	char *p, file[FNAMELEN];

	strcpy(m, mode_start);
	if (mode_extra)
		strcat(m, mode_extra);
	p = m + strlen(m);
	left = ptrlen(p) - 30;
	if (!*filename || fnamecmp(get_tail(filename, 0), bufname)) {
		if (is_dired_buf())
			sprintf(p, "%.*s ", left, bufname);
		else
			sprintf(p, "(%.*s) ", left, bufname);
		p += strlen(p);
		left = ptrlen(p) - 30;
	}
	if (*filename && force_save_as != FSA_NEWFILE) {
		relative(filename, file);		/* if file, put name */
		sprintf(p, "%.*s ", left, file);
	}
	if (mode_line_shows_mode) {
		for (i = _recursion_level; i-- >= 0;)
			strcat(p, "[");
		set_mode(p + strlen(p)); /* build part inside []'s in mode */
		for (i = _recursion_level; i-- >= 0;)
			strcat(p, "]");
	}
	strcat(p, mode_end);
}

char *name_of_filetype(t)
int t;
{
	
	switch(t){
		case FILETYPE_AUTO:
		case FILETYPE_MSDOS:
			if (default_translation_type != FILETYPE_AUTO)
				return " DOS";
			else
				return "";
		case FILETYPE_BINARY:  return " Binary";
		case FILETYPE_UNIX:    return " Unix";
		case FILETYPE_MAC:     return " Mac";
		default: return " Unknown translation type";
	}
}

set_mode(mode)	/* add major and minor modes to mode line */
char *mode;
{
	strcpy(mode, major_mode);
	if (fill_mode)
		strcat(mode, " Fill");
	if (over_mode)
		strcat(mode, " Over");

	strcat(mode, name_of_filetype(translation_type));
	if (file_io_converter)
		strcat(mode, (*file_io_converter)(0));
	if (_len_def_mac)
		strcat(mode, " Def");
	if (ignore_kbd_macro || final_macro_pause || recording_suspended)
		strcat(mode, " Susp");
	if (narrow_start > 0 || narrow_end > 0)
		strcat(mode, " Narrow");
	if (_buf_readonly)
		strcat(mode, " RO");
}

command toggle_borders()
{
	want_window_borders = !want_window_borders;	
	border_inside = want_window_borders;
	last_window_color_scheme = 0;
	full_redraw = 1;
}

tiled_window_border(j)		// adjust border code for this window
{
	if (!want_window_borders) {
		_window_flags &= ~WANT_MODE_LINE;
		return (tiled_scroll_bar && !is_gui) ? BORD(BRIGHT, -1) : 0;
	}
	if (!window_left && border_left)
		j |= BORD(BLEFT, -1);
	if (window_top <= !echo_line && border_top)
		j |= BORD(BTOP, -1);
	if (window_left + window_width >= screen_cols ? border_right
						      : border_inside)
		j |= BORD(BRIGHT, -1);
	if (window_top + window_height >= screen_lines - !!echo_line
	    && border_bottom)
		j |= BORD(BBOTTOM, -1);
	return j;
}

tiled_window_colors()		// set color scheme for tiled window
{
	if (want_window_borders)
		window_color_scheme = 0;
	else if (!window_color_scheme)
		window_color_scheme = set_window_color_scheme();
}

set_window_color_scheme()	// pick a set of colors for this window
{				// use one after the last we assigned
	int i, flags = STARTMATCH;

	do {		// get to scheme we assigned last time
		i = give_next_color_scheme(flags);
		if (!i && flags)	// no matching schemes
			return 0;
		flags = 0;		// next time, give next one
		if (i == last_window_color_scheme) {	// use next one
			i = give_next_color_scheme(flags);
			break;
		}
	} while (i);
	if (!i)			// start over from first
		i = give_next_color_scheme(STARTMATCH);
	return last_window_color_scheme = i;
}

give_next_color_scheme(flags)	// find next avail borderless win color scheme
{				// return its index, or 0 if no more
	int i;

	do {
		i = name_match("window-", flags);
		flags = 0;
	} while (i && name_type(i) != NT_COLSCHEME);
	return i;
}

display_more_msg(w)	/* put up "More" in lower right corner */
{
	window_title(w, BBOTTOM, TITLERIGHT(1), "%m");
}

command show_version()
{
	say("Epsilon Programmer's Editor %s", version);
}

command highlight_region() on cx_tab[CTRL('H')]	/* toggle highlighting */
{
	if (has_arg ? (iter != 0) : !is_highlight_on())
		highlight_on();
	else
		highlight_off();
	iter = 1;
}

is_highlight_on()	/* 0 if no, else 1 region, 2 rect, 3 line highlight */
{			/* 4 inclusive region */
	return _highlight_control ? modify_region(1, MRTYPE, -1) : 0;
}

region_type()
{
	int type = modify_region(1, MRTYPE, -1);

	return (type < REGNORM) ? REGNORM : type;
}

set_region_type(type)
{
	modify_region(1, MRTYPE, type);
}

highlight_on()
{
	_highlight_control = 1;
	call_on_modify = 1;
}

highlight_off()
{
	_highlight_control = 0;
}

command redisplay()
{
	refresh();
}

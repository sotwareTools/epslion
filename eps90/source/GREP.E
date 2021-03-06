/************************************************************************
* "Epsilon" is a registered trademark licensed to Lugaru Software, Ltd. *
*		"EEL" and "Lugaru" are trademarks of Lugaru Software, Ltd.		*
*																		*
*  Copyright (C) 1988, 1997 Lugaru Software Ltd.  All rights reserved.	*
*																		*
* Limited permission is hereby granted to reproduce and modify this		*
* copyrighted material provided that the resulting code is used only in *
* conjunction with Lugaru products and that this notice is retained in	*
* any such reproduction or modification.								*
************************************************************************/

// This file has the commands for search and replacing in multiple
// files.

#include "eel.h"
#include "grep.h"
#include "colcode.h"

when_loading()	/* disable normal keys, copy some dired definitions */
{

	fix_key_table(reg_tab, (short) normal_character, grep_tab, -1);
	set_list_keys(grep_tab);
	fix_key_table(dired_tab, (short) dired_examine_in_window,
		grep_tab, (short) dired_examine_in_window);
}

command grep() on reg_tab[FALT(7)]
{
	grep_prompt(REGEX | UNKNOWN, has_arg);
}

grep_prompt(flags, inbufs)
{
	char filepat[FNAMELEN];

	_last_was_grep = 1;
	tiled_only();
	iter = 0;
	error_if_input(1);	/* error if we're in the middle of input */
	flags = get_search_string("List lines with: ",
				  flags | (inbufs ? BUFGREP : FILEGREP));
	flags &= ~(INCR | FAILING | BAD | REVERSE);
	if (!get_grep_file(inbufs, filepat))
		return;
	do_grep("grep", (flags & REGEX) ? _default_regex_search
			: _default_search, flags, filepat, inbufs);
}

char *(*give_grep_finder)()(inbufs, filepat, ps)
char *filepat, **ps;	// put 1st match in ps & return finder for next matches
{
	char *(*finder)();

	finder = inbufs ? b_match : f_all_match;
	*ps = (*finder)(filepat, STARTMATCH
			    | (inbufs ? 0 : (EXACTONLY | FM_NO_DIRS)));
	if (!ps)
		error("No matches");
	return finder;
}

get_grep_file(inbufs, filepat)
char *filepat;
{
	char pr[FNAMELEN];

	if (!inbufs) {
		if (*_grep_files)
			sprintf(pr, "In file(s) [%r]: ", _grep_files);
		else
			sprintf(pr, "In file(s): ");
		save_var prompt_with_buffer_directory = 0;
		get_file_dir(filepat, pr);
		if (*filepat)
			strcpy(_grep_files, filepat);
		relative(_grep_files, filepat);
		if (!*filepat)
			return 0;
	} else
		comp_read(filepat, "In buffers starting with [all buffers]: ",
			  b_match, 0, bufname);
	return 1;
}

do_grep(buf, pat, flags, filepat, inbufs)
char *buf, *pat, *filepat;
{
	int res = 0, aborted = 0, cnt = 0, start, tempbuf = 0;
	int orig, before_head, this_err;
	char *s, rel[FNAMELEN], abs[FNAMELEN], search_type[80], *(*finder)();

	create(buf);
	if (grep_empties_buffer)
		zap(buf);
	locate_window(buf, "");
	point = size();
	if (size())
		bprintf("\n");	/* separate from previous query */
	make_search_prompt(search_type, flags & SMODES);
	before_head = point;
	bprintf("Found 0 lines with %s\"%s\" in %s\n",
		search_type, pat, filepat);
	set_character_color(before_head, point, color_class grep_filename);
	start = point;
	if (display_column.default != -1)
		display_column = 0;	/* horizontally scroll this window */
	grep_mode();
	finder = give_grep_finder(inbufs, filepat, &s);	// get 1st match
	save_var readonly_warning = 0;
	orig = bufnum;
	for (; s; s = (*finder)(filepat, 0)) {
		grep_make_names(rel, abs, s, inbufs);
		noteput("%d matches, searching %s...", cnt, rel);
		if (inbufs)	// skip over grep results buffer
			this_err = !strcmp(s, buf);
		else if (!look_file(abs)) {
			this_err = find_it(abs, default_translation_type);
			if (!grep_keeps_files)
				tempbuf = bufnum;
		} else
			this_err = 0;
		if (this_err == EREADABORT || user_abort) {
			aborted = 1;
			break;
		} else if (this_err) {
			window_bufnum = orig;
			if (tempbuf)
				buf_delete(tempbuf);
			tempbuf = 0;
			continue;
		}
		res = copy_matches(name_to_bufnum(buf), flags, pat, rel);
		window_bufnum = orig;
		if (res < 0)	/* error occurred during search */
			break;
		else if (res > 0) {
			cnt += res;
			build_first = 1;
			point = start;
			delete(point, before_head);
			bprintf("Found %d lines with %s\"%s\" in %s\n",
				cnt, search_type, pat, filepat);
			start = point;
			point = size();
			refresh();
		}
		if (tempbuf)
			buf_delete(tempbuf);
		tempbuf = 0;
	}
	window_bufnum = orig;
	point = start;
	build_first = 1;
	if (tempbuf)
		buf_delete(tempbuf);
	say("");
	if (aborted)
		quick_abort();
	if (res == -DSBAD)
		error("Illegal search pattern: %s", pat);
	else if (res != -DSABORT && cnt) {
		locate_window(buf, "");
		modified = 0;
		point = start;
	}
}

grep_make_names(rel, abs, s, inbufs)	// put name to use in grep results
char *rel, *abs, *s;				// for any matches in rel
{
	if (inbufs) {
		bufname = s;
		if (*filename)
			relative(filename, rel);
		else
			sprintf(rel, BUFPREFIX "%s", s);
	} else
		relative(s, rel);
	strcpy(abs, rel);
	if (!inbufs)
		absolute(abs);
}

get_buffer_point(bnum)
{
	save_var bufnum = bnum;
	return point;
}

/* copy matches in current buf to other buffer */
/* returns 0=no matches, >0=# of matches, <0= -(error code) */

copy_matches(tobuf, flags, pat, rel)
char *pat, *rel;
{
	int sbuf = bufnum, cnt = 0, i, more, srcherr;
	int before, file, do_color;

	do_color = want_code_coloring && recolor_range;
	save_var point = 0;
	while ((srcherr = do_searching(flags, pat)) == 1) {
		to_begin_line();
		i = point;
		more = nl_forward();
		before = get_buffer_point(tobuf);
		buf_printf(tobuf, "%s: ", rel);
		file = get_buffer_point(tobuf);
		if (do_color)			// Color in place, then copy.
			color_for_area(i, point - more);
		buf_xfer_colors(tobuf, i, point - more);
		bufnum = tobuf;
		set_character_color(before, file, color_class grep_filename);
		if (!do_color)
			set_character_color(file, point, color_class grep_text);
		bprintf("\n");
		set_character_color(point - 1, point, color_class grep_filename);
		point = file;
		while ((srcherr = do_searching(flags, pat)) == 1 && point > file) {
			set_character_color(matchstart, matchend, color_class grep_match);
			file = point;
		}
		point = size();
		bufnum = sbuf;
		cnt++;
		if (srcherr)
			return -srcherr;
		if (!more)
			return cnt;
	}
	return srcherr ? -srcherr : cnt;
}

grep_mode()
{
	mode_keys = grep_tab;
	major_mode = _grep_mode_name;
	mouse_dbl_selects = 1;
	make_mode();
}

grep_help() on grep_tab['h'], grep_tab['?']
{
	help_on_command("grep-mode");
}

grep_examine() on grep_tab[' '], grep_tab['\n'],
		   grep_tab['e'], grep_tab['\r'], grep_tab[GREYENTER]
{
	int start, end, colon, old, instance, i, toolong = 0;
	char file[FNAMELEN], string[FNAMELEN], line[FNAMELEN], *p;

	_last_was_grep = 1;
	to_begin_line();
	save_var case_fold = 0;		/* turn off for grep buffer */
	if (!search(1, ": "))
		error("Can't read file name");
	colon = point;
	to_begin_line();
	start = point;
	to_end_line();
	end = point;
	point = start;
	grab(start, colon - 2, file);
	if (start + FNAMELEN - 3 < end)
		end = toolong = start + FNAMELEN - 3;
	grab(colon, end, string);
	line[0] = '\n';		// Put \n at start and end of line.
	grab(start, end + 1, line + 1);
	instance = count_instances(line) + 1;
	if (strstr(file, BUFPREFIX) != file) {
		absolute(file);
		locate_window("", file);
		if (find_it(file, ask_line_translate()))
			return;
	} else if (exist(p = file + sizeof(BUFPREFIX) - 1))
		to_buffer(p);
	else
		error("Can't find buffer %s.", p);
	if (strlen(line) != end - start + 2)
		error("Can't find matching lines with null characters.");
	old = point;
	save_var case_fold = 0;		/* turn off for user buffer */
	point = 0;
	for (i = 0; i < instance; i++)
		if (toolong ? !search(1, string) : !line_search(1, string)) {
			point = old;
			if (i == 0 || instance == 1)
				error("Can't find \"%s\"", string);
			else
				error("Can't find this copy of "
						"repeated line");
		} else {
			old = point;
			if (i + 1 < instance)
				nl_forward();
		}
	to_begin_line();
	if (toolong)
		say("Line too long; this may not be the correct match.");
}

line_search(dir, s)	/* search for line with only s on it */
char *s;		/* go to its end (if reverse: start) */
{
	int start, end;

	if (!*s)
		return re_search(dir, "^$");
	while (search(dir, s)) {
		start = (dir > 0) ? matchstart : point;
		end = (dir > 0) ? point : matchstart;
		if ((end >= size() - narrow_end || character(end) == '\n')
				&& (start <= narrow_start
					|| character(start - 1) == '\n'))
			return 1;
	}
	return 0;
}

count_instances(s)	/* how many times does s occur before pt in this */
char *s;		/* search? */
{
	int count = 0;

	save_var narrow_end = size() - point;
	search(-1, "\nFound ");
	save_var narrow_start = point;
	for (; search(1, s); point--)
		count++;
	return count;
}

command next_match()
{
	by_matches(iter);
	iter = 0;
}

command previous_match()
{
	by_matches(-iter);
	iter = 0;
}

by_matches(val)
{
	int owin, win, pt, dir = RE_FORWARD, buf = name_to_bufnum("grep");

	tiled_only();
	_last_was_grep = 1;
	if (!buf)
		error("No grep buffer.");
	win = buf_in_window(buf);
	if (win >= 0) {
		owin = window_handle;
		window_handle = win;
	} else
		bufnum = buf;
	if (val < 0)
		val = -val, dir = RE_REVERSE;
	else
		to_end_line();
	while (val-- > 0)
		if (!re_search(dir, "^(<(>buffer<)> )?[^\n\t]+: "))
			error("No more matches.");
	if (win >= 0) {
		pt = point;
		window_handle = owin;
		bufnum = buf;
		point = pt;
	}
	has_arg = iter = 0;
	grep_examine();
}

command next_position() on cx_tab[CTRL('N')]
{
	if (_last_was_grep)
		next_match();
	else
		next_error();
}

command previous_position() on cx_tab[CTRL('P')]
{
	if (_last_was_grep)
		previous_match();
	else
		previous_error();
}

command keep_matching_lines()
{
	drop_matching_lines(0, "Delete lines not containing: ");
}

command delete_matching_lines()
{
	drop_matching_lines(1, "Delete lines containing: ");
}

drop_matching_lines(drop, pr)
char *pr;
{
	int flags;

	tiled_only();
	iter = 0;
	error_if_input(1);	/* error if we're in the middle of input */
	save_var point;
	flags = get_search_string(pr, UNKNOWN | REGEX | BUFGREP);
	restore_vars();
	flags &= ~(INCR | FAILING | BAD | REVERSE);
	do_drop_matching_lines(flags, (flags & REGEX) ? _default_regex_search
		: _default_search, drop);
}

do_drop_matching_lines(flags, pat, drop)
char *pat;		// keep or drop lines after pt matching pattern
{
	int res, here, there, cnt = 0;

	save_spot point;
	to_begin_line();
	for (;; cnt++) {
		here = point;
		res = do_searching(flags, pat);
		if (res != 1 || point == ((flags & REVERSE) ? narrow_start
								  : size() - narrow_end))
			break;
		there = give_begin_line();
		nl_forward();
		delete(there, drop ? point : here);
	}
	if (!res && !drop)
		delete(here, size());
	if (!res)
		say("Deleted %s%d lines.", drop ? "" : "all but ", cnt);
	else if (res == DSBAD)
		error("Bad search pattern: %s", pat);
	return cnt;
}

command file_query_replace() on reg_tab[FSHIFT(7)]
{
	prompt_file_replace(QUERY | UNKNOWN, has_arg);
}

prompt_file_replace(flags, inbufs)
{		// prompt for replacing in files/buffers, then do it
	char str[FNAMELEN], with[FNAMELEN], filepat[FNAMELEN];

	flags = get_replace_text(flags | (inbufs ? BUFGREP : FILEGREP),
				 str, with);
	if (flags == -1 || !get_grep_file(inbufs, filepat))
		return;
	do_file_replace(str, with, flags, filepat, inbufs);
}
			
do_file_replace(str, with, flags, filepat, inbufs)
char *str, *with, *filepat;	// (query-) replace across files/buffers
{
	int res, oldbuf = 1, prevbuf = 0, total = 0, cnt = 0;
	char rel[FNAMELEN], abs[FNAMELEN], *s, *(*finder)();
	int total_found = 0, total_changed = 0, old_readonly;

	old_readonly = readonly_warning;
	save_var readonly_warning;
	readonly_warning &= ~5;	// don't show msg or ring bell unless matches
	finder = give_grep_finder(inbufs, filepat, &s);	// get 1st match
	save_var window_bufnum;
	for (; s; s = (*finder)(filepat, 0)) {
		grep_make_names(rel, abs, s, inbufs);
		noteput("Searching %s...", rel);
		if (!inbufs) {
			oldbuf = look_file(abs);
			find_it(abs, default_translation_type);
		} else
			to_buffer(s);
		undo_mainloop();
		res = one_file_replace(str, with, flags, oldbuf, old_readonly);
		total_found += replace_num_found;
		total_changed += replace_num_changed;
		total++;
		if (res >= 0)
			cnt++;
		if (prevbuf && buf_in_window(prevbuf) == -1) {
			buf_delete(prevbuf);	// delete untouched new bufs
			prev_forget(_prev_num - 1); // fix default
		}
		prevbuf = (oldbuf || modified) ? 0 : bufnum;
		if ((flags & QUERY) && key == '!'
			&& ask_continue_replace("Replace without asking"))
			flags &= ~QUERY;	// no more querying
		else if (res == DSABORT) {
			if (!ask_continue_replace("Continue replacing"))
				break;
		} else if (res > 0) {	// user said to stop
			user_abort = 0;
			return;
		}
		if (user_abort)
			break;
	}
	user_abort = 0;
	say("Replaced %d of %d matches in %d of %d %s.",
	    total_changed, total_found, cnt, total,
	    inbufs ? "buffers" : "files");
}

ask_continue_replace(pr)	// ask question, return 1 if default of yes,
char *pr;			// or 0 if user pressed N
{
	char msg[FNAMELEN];

	drop_pending_says();
	sprintf(msg, "%s in remaining files? ", pr);
	return ask_yn(pr, msg, "Yes", "No", 1);
}

one_file_replace(str, with, flags, oldbuf, old_readonly)
char *str, *with;	// return 0=ok, 1=user said to stop,
{			// DSABORT=aborted, DSBAD=bad pat, -1=no matches
	int res;

	replace_num_found = replace_num_changed = 0;
	save_var point = 0;
	res = do_searching(flags, str);
	if (res != 1)
		return res ? res : -1;
	if (!oldbuf && (flags & FILEGREP))	// had to read file to search
		replace_in_readonly_hook(old_readonly);
	else
		replace_in_existing_hook(old_readonly);
	point = matchstart - 1;
	show_replace(str, with, flags);
	return string_replace(str, with, flags);
}

replace_in_readonly_hook(old_readonly)	// called when file-query-replace
{			// needs to modify a file that might be read-only
	if (file_info.check_type == CHECK_FILE
				&& (file_info.attr & ATTR_READONLY)) {
		save_var readonly_warning = old_readonly;
		do_readonly_warning();
		make_mode();
	}
}

// Epsilon wants to replace in an existing buffer.  (Might be readonly.)

replace_in_existing_hook(old_readonly)
{
	old_readonly = old_readonly;		// prevent compiler warning
}

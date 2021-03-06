/************************************************************************
* "Epsilon" is a registered trademark licensed to Lugaru Software, Ltd. *
*		"EEL" and "Lugaru" are trademarks of Lugaru Software, Ltd.		*
*																		*
*  Copyright (C) 1989, 1997 Lugaru Software Ltd.  All rights reserved.	*
*																		*
* Limited permission is hereby granted to reproduce and modify this		*
* copyrighted material provided that the resulting code is used only in *
* conjunction with Lugaru products and that this notice is retained in	*
* any such reproduction or modification.								*
************************************************************************/

// This file handles remembering the window and buffer configuration
// you used the last time you ran Epsilon.

#include "eel.h"
#include "proc.h"
#include "bufed.h"

/* functions for remembering window configurations, which files
   we were editing, etc., from session to session */

#ifdef UNIX
#define DEFSESSNAME	".epsilon.ses"
#define DEFSESSDIR	"~/"
#else
#define DEFSESSNAME	"epsilon.ses"
#define DEFSESSDIR	"/"
#endif

give_session_file(file)
char *file;
{
	char *s, *p, dir[FNAMELEN];

	if (explicit_session_file) {
		strcpy(file, explicit_session_file);
		return;
	}
	s = cmd_line_session_file;
	if (!s)
		s = verenv("ESESSION");
	if (!s)
		s = DEFSESSNAME;
	if (look_up_tree(file, s, NULL, session_tree_root))
		return;
	strcpy(file, s);
	if (*session_default_directory)
		absolute(file, session_default_directory);
	else if (p = verenv("EPSPATH")) {
		strcpy(dir, p);
		p = index(dir, path_list_char);
		if (p)
			*p = 0;
		absolute(file, dir);
	} else
		absolute(file, DEFSESSDIR);
}

ask_session_file(file, pr)	/* ask user for a session file */
char *file, *pr;
{
	char def[FNAMELEN];

	save_var only_file_extensions = "|.ses|";
	give_session_file(def);
	get_file(file, pr, def);
}

save_session()		/* write out the session */
{			/* return error code */
	char file[FNAMELEN];

	if (!(preserve_session & (SAVE_RESTORE_SESSION | SAVE_SESSION)))
		return 0;
	give_session_file(file);
	return do_save_session(file);
}

command write_session()
{
	char file[FNAMELEN];
	int err;

	ask_session_file(file, "Write session to");
	err = do_save_session(file);
	if (err) {
		file_error(err, file, "write error");
		maybe_ding(bell_on_write_error);
	} else {
		say("Session saved on %s", file);
		if (explicit_session_file)
			free(explicit_session_file);
		explicit_session_file = strsave(file);
	}
}

do_save_session(file)	/* write out the session putting fname in file */
char *file;		/* and return error code */
{
	int b, err;

	make_session(b = tmp_buf(), file);
	save_var bufnum = b;
	err = file_write(file, 0);
	restore_vars();
	buf_delete(b);
	return err;
}

char *give_buffer_name(buf)	/* give name or "" if bad buffer # */
{
	return buf_exist(buf) ? bufnum_to_name(buf) : "";
}

make_session(b, sesfile)
char *sesfile;
{
	int i, wins, owin = window_number;
	struct window_info w;
	char sdir[FNAMELEN];	// dir of session file
	char file[FNAMELEN];

	strcpy(sdir, sesfile);
	absolute(sdir);
	*get_tail(sdir, 0) = 0;
	buf_printf(b, SES_HDR "\n");
	for (i = buf_list(0, 0); i; i = buf_list(1, 1)) {
		bufnum = i;
		if (i != b && remember_this_buffer()) {
			relative(filename, file, sdir);
			buf_printf(b, "%s\n%s\n%d %d %d\n",
				bufname, file, point, mark, translation_type);
			buf_printf(b, "%d %d %d %d\n", over_mode, fill_mode,
				indent_with_tabs, margin_right);
			buf_printf(b, "%d %d %d %d %d %d %d\n", tab_size,
					   case_fold, 0, want_warn,
					   _buf_readonly, buf_accessed,
					   (file_io_converter == oem_file_converter));
		}
	}
	buf_printf(b, "\n%d\n", _prev_num);
	for (i = 0; i < _prev_num; i++)
		buf_printf(b, "%s\n", give_buffer_name(_prev_old_buffers[i]));
	save_bookmark_session(b);

	wins = number_of_windows() - number_of_popups();
	buf_printf(b, "%d %d %d %d %d %d\n",
			   wins, screen_cols, screen_lines, is_gui, opsys,
			   buf_accessed_clock);
	for (i = 0; i < wins; i++) {
		get_window_info(i, &w);
		buf_printf(b, "%d %d %d %d\n",
			w.left, w.top, w.right, w.bottom);
		buf_printf(b, "%d %d %d %d\n",
			w.textcolor, w.hbordcolor, w.vbordcolor, w.titlecolor);
		buf_printf(b, "%d %d\n", w.borders, w.other);
		buf_printf(b, "%s\n", give_buffer_name(w.bufnum));
		buf_printf(b, "%s\n", give_buffer_name(w.prevbuf));
		buf_printf(b, "%d %d %d\n", w.point, w.dcolumn, w.dpoint);
	}
	buf_printf(b, "%d %d %d %d %d 0 0\n", owin, echo_line,
		   permanent_menu, avoid_top_lines, avoid_bottom_lines);
	buf_printf(b, "%d %d %d\n",
		   _default_flags, _default_regex_flags, _last_was_regex);
	buf_printf(b, "%s" SES_DELIM "%s" SES_DELIM,
		_default_search, _default_regex_search);
	buf_printf(b, "%s" SES_DELIM "%s" SES_DELIM,
		_default_replace, _default_regex_replace);
	relative(_region_file, file, sdir);
	if (!*_region_file)
		*file = 0;
	buf_printf(b, "%s" SES_DELIM "%s" SES_DELIM,
		push_cmd, file);
	if (!*_grep_files)
		*file = 0;
	else if (is_pattern(_grep_files) & 1)
		strcpy(file, _grep_files);	// Don't mess with complex patterns.
	else
		relative(_grep_files, file, sdir);
	buf_printf(b, "%s" SES_DELIM "\n", file);
	make_session_hook(b);
	save_recall_session(b);
	getcd(file);
	buf_printf(b, "CWD: %s\n", file);
}

remember_this_buffer()	/* should we record this buffer in session file? */
{
	if (*bufname == '-' || is_dired_buf() || !size() || !*filename)
		return 0;
	if (!strcmp(bufname, PROCBUF))
		return 0;
	if (file_info.year && file_info.check_type != CHECK_FILE)
		return 0;
	if (is_remote_file(filename))
		return 0;
	return 1;
}

save_bookmark_session(b)
{
	int i, buf;
	spot m;

	buf_printf(b, "%d %d\n", _bookmark_slot, _last_bookmark);
	for (i = 0; i < NUM_BOOKMARKS; i++) {
		m = _bookmark_spots[i];
		if (m && (buf = spot_to_buffer(m)) > 0)
			buf_printf(b, "%s\n%d\n", give_buffer_name(buf), *m);
		else
			buf_printf(b, "\n0\n");
	}
}

save_recall_session(b)	// store saved prompt responses in session file
{
	save_var bufnum = create(OLDRESP);
	point = size() - recall_maximum_session;
	to_begin_line();	// only keep last N chars worth
	buf_xfer(b, point, size());
	buf_printf(b, SES_DELIM "\n");
}

command read_session() on reg_tab[FSHIFT(5)]
{
	char file[FNAMELEN];
	int res;

	if (maybe_save_all())
		return;
	ask_session_file(file, "Read session from");
	res = load_this_session(file);
	return res;
}

load_session()		/* maybe search for a session file & load it */
{			/* return 1 if session was loaded */
	char file[FNAMELEN];

	if (!(preserve_session & (SAVE_RESTORE_SESSION | RESTORE_SESSION)))
		return 0;
	give_session_file(file);
	return load_this_session(file);
}

load_this_session(file)		/* return 1 if session was loaded */
char *file;
{
	int b, err;

	bufnum = b = create(SES_BNAME);
	err = file_read(file, 0);
	if (!err) {
		if (explicit_session_file)
			free(explicit_session_file);
		explicit_session_file = strsave(file);
		maybe_refresh();
		err = restore_session(b);
		switching_to_buffer();
		if (buf_in_window(b) == -1)
			buf_delete(b);
		if (!err)
			note("");
		else if (err != 100)
			say("Invalid format, code %d, in session %s",
				err, file);
		return 1;
	} else if (err != 2) {
		file_error(err, file, "couldn't read session");
		maybe_ding(bell_on_read_error);
	}
	return 0;
}

restore_session(b)	/* if error in session file, return error code # */
{			/* for debugging purposes, else 0 */
	int nums[10], i, j, wins, err, readerrs = 0;
	int def_buf = 0;
	char buf[FNAMELEN], file[FNAMELEN];
	char sdir[FNAMELEN];	// dir of session file

	give_session_file(sdir);
	absolute(sdir);
	*get_tail(sdir, 0) = 0;
	bufnum = b;
	point = 0;
	if (!grab_line(b, buf) || strcmp(buf, SES_HDR))
		return 1;
	while (grab_line(b, buf)) {
		grab_line(b, file);
		if (grab_numbers(b, nums) < 3)
			return 2;
		if (session_restore_files)
			bufnum = create(buf);
		if (!def_buf) {
			if (is_gui)
				note("Restoring session...");
			else
				noteput("Restoring session...");
			def_buf = bufnum;
		}
		if (session_restore_files)
			filename = file;
		if (*file && session_restore_files) {
			absolute(file, sdir);
			i = do_file_read(file, nums[2]);
			if (user_abort || i == EREADABORT)
				return 0;
			if (!i || i == 2) {
				if (!i)
					set_readonly_from_file();
				window_bufnum = bufnum;		// make suffix- kbd macros work
				call_mode(filename);
				make_mode();
			} else if (!readerrs++) {
				file_error(i, file, "read error");
				maybe_ding(bell_on_read_error);
			} else
				note("%d files could not be read", readerrs);
		}
		if (session_restore_files) {
			if (bufnum != b)	/* same tmp name as session buffer */
				point = nums[0];
			mark = nums[1];
			translation_type = nums[2];
		}
		if (grab_numbers(b, nums) < 4)
			return 3;
		if (session_restore_files) {
			over_mode = nums[0];
			fill_mode = nums[1];
			indent_with_tabs = nums[2];
			margin_right = nums[3];
		}
		if ((i = grab_numbers(b, nums)) < 5)
			return 4;
		if (session_restore_files) {
			tab_size = nums[0];
			case_fold = nums[1]; // nums[2] var was removed
			want_warn = nums[3];
			if (nums[4] == 1)
				set_read_only(1);
			buf_accessed = i > 5 ? nums[5] : 0;
			file_io_converter = 0;
			if (i > 6 && nums[6]) {
				file_io_converter = oem_file_converter;
				file_convert_read();
			}
			undo_mainloop();
		}
	}
	if (grab_numbers(b, nums) != 1)
		return 12;
	j = nums[0];
	if (session_restore_files)
		_prev_num = j;
	for (i = 0; i < j; i++) {
		grab_line(b, buf);
		if (session_restore_files)
			_prev_old_buffers[i] = name_to_bufnum(buf);
	}
	if (restore_bookmark_session(b))
		return 13;
	i = grab_numbers(b, nums);
	if (i < 3)
		return 5;
	wins = nums[0];
	if (!is_gui && !want_lines && !want_cols)
		try_set_screen_size(nums[2], nums[1], "");
	if (i > 5)
		buf_accessed_clock = nums[5];

	err = rest_sess_wins(b, wins, !session_restore_files, def_buf,
						 nums[2], nums[1]);
	if (err) {
		def_buf = give_prev_buf();
		if (def_buf)
			to_buffer_num(def_buf);
	}
	if (grab_numbers(b, nums) >= 3) {
		_default_flags = nums[0];
		_default_regex_flags = nums[1];
		_last_was_regex = nums[2];
		grab_string(b, _default_search, SES_DELIM);
		grab_string(b, _default_regex_search, SES_DELIM);
		grab_string(b, _default_replace, SES_DELIM);
		grab_string(b, _default_regex_replace, SES_DELIM);
		grab_string(b, push_cmd, SES_DELIM);
		grab_string(b, _region_file, SES_DELIM);
		if (*_region_file)
			absolute(_region_file, sdir);
		grab_string(b, _grep_files, SES_DELIM);
		if (*_grep_files && !(is_pattern(_grep_files) & 1))
			absolute(_grep_files, sdir);	// Don't mess with complex pats.
		restore_session_hook(b);
		restore_recall(b);
		grab_line(b, file);		// skip \n after recall buffer
		grab_line(b, file);
		if (!strncmp(file, "CWD: ", 5) && (directory_flags & DIR_CWD_RESTORE))
			chdir(file + 5);
	} else
		err = 11;
	return err ? err : readerrs ? 100 : 0;
}

set_readonly_from_file()
{
	if (file_info.check_type == CHECK_FILE &&
			(file_info.attr & ATTR_READONLY) &&
			(readonly_warning & 2)) {
		_buf_readonly = 2;	// set from file
		call_on_modify = 1;
	}
}

restore_bookmark_session(b)
{
	int nums[10], i;
	char buf[FNAMELEN];

	if (grab_numbers(b, nums) < 2)
		return 1;
	_bookmark_slot = nums[0];
	_last_bookmark = nums[1];
	for (i = 0; i < NUM_BOOKMARKS; i++) {
		grab_line(b, buf);
		if (grab_numbers(b, nums) < 1)
			return 1;
		if (*buf && exist(buf)) {
			bufname = buf;
			_bookmark_spots[i] = alloc_spot(0);
			*_bookmark_spots[i] = nums[0];
		}
	}
	return 0;
}

/* restore windows from b */
/* if skip, just parse them, don't restore */

rest_sess_wins(b, wins, skip, def_buf, lines, cols)
{
	int nums[10], i, err = 0, bnum, must_default;
	char buf[FNAMELEN];
	struct window_info w;

	for (i = 0; i < wins; i++) {
		if (grab_numbers(b, nums) < 4)
			err = 6;
		w.left = nums[0];
		w.top = nums[1];
		w.right = nums[2];
		w.bottom = nums[3];
		if (grab_numbers(b, nums) < 4)
			err = 7;
		w.textcolor = nums[0];
		w.hbordcolor = nums[1];
		w.vbordcolor = nums[2];
		w.titlecolor = nums[3];
		if (grab_numbers(b, nums) < 2)
			err = 8;
		w.borders = nums[0];
		w.other = nums[1];
		grab_line(b, buf);
		w.point = -1;
		w.dpoint = -1;
		bnum = name_to_bufnum(buf);
		must_default = !bnum;
		grab_line(b, buf);
		w.prevbuf = name_to_bufnum(buf);
		w.bufnum = bnum ? bnum : w.prevbuf ? w.prevbuf :
			(bnum = give_prev_buf()) ? bnum : def_buf;
		if (grab_numbers(b, nums) < 3)
			err = 9;
		w.dcolumn = nums[1];
		if (!must_default) {
			w.point = nums[0];
			w.dpoint = nums[2];
		}
		if (err)
			break;
		if (!skip) {
			window_create(!i, &w);
			fix_window_start();
		}
	}
	nums[1] = screen_lines - 1;	/* echo line */
	nums[2] = 0;			/* want perm menu? */
	nums[3] = 0;			/* top avoid lines */
	nums[4] = 1;			/* bottom avoid lines */
	if (!err && !grab_numbers(b, nums))
		err = 10;
	if (err)
		one_window();
	else if (!skip) {
		echo_line = nums[1];
		select_low_window(nums[0], nums[3], nums[4], lines, cols);
		i = permanent_menu;
		restore_menu(nums[2]);
		set_menu_bar(i);	// undo setting in session file
	}
	return err;
}

restore_recall(b)	// get saved prompt responses from session
{
	int orig;

	save_var bufnum = b;
	orig = point;
	if (search(1, SES_DELIM))
		buf_xfer(zap(OLDRESP), orig, matchstart);
}

make_session_hook(b)
{
	b = b;				/* silence eel's warning */
}

restore_session_hook(b)
{
	b = b;				/* silence eel's warning */
}

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

// This file has commands that deal with paired delimiters
// like [ and ].

#include "eel.h"
#include "colcode.h"
#include "c.h"

	/* the delimiters in use */
#define LEFTD	"[({"
#define RIGHTD	"])}"

/* user command to move past the next s-expression like object */
command forward_level() on reg_tab[ALT(CTRL('F'))]
{
	if (iter < 0) {
		iter = -iter;
		backward_level();
	}
	while (iter-- > 0)
		move_level(1, LEFTD, RIGHTD, 1);
}

command backward_level() on reg_tab[ALT(CTRL('B'))]
{
	if (iter < 0) {
		iter = -iter;
		forward_level();
	}
	while (iter-- > 0)
		move_level(-1, RIGHTD, LEFTD, 1);
}

command find_delimiter() on reg_tab[ALT(')')]
{
	int orig=point;

	say("");
	iter=0;
	if (in_macro())
		return;
	if (move_level(-1, RIGHTD, LEFTD, 1)) {
		show_line();
		point = orig;
	}
}

command show_matching_delimiter()
{
	if (key > 32 && key < 255 && !isalpha(key) && !isdigit(key))
		normal_character();
	find_delimiter();
}

show_line()		/* display point for a moment, then restore */
{
	int oldstart = window_start;
	int time;

	if (in_macro())
		return;
	maybe_refresh();
	time = (window_start == oldstart) ? near_pause : far_pause;
	delay(time, COND_KEY);
	window_start = oldstart;
	build_first = 1;
}

/*
Move in direction dir past a matched pair of characters.
The first is from findch, the second one is at the same
position in otherch.
On success, or if the end of the buffer is encountered before the
first character is found, return the new buffer position.
Otherwise return -1.
*/

default_move_level(dir, findch, otherch)
char *findch, *otherch;
{
	int first, second;
	int level = 0;
	char pat[6];			/* temporary pattern */

	save_var point;			// if aborted, don't move anywhere
	sprintf(pat, "[%s]", findch);
	if (!re_search(dir, pat))	/* find the first char of pair */
		return point;	/* at end of buffer */

	point -= dir;			/* move back over first char */
	first = character(point - (dir < 0)); /* get the character we found */
	second = otherch[index(findch, first) - findch];
					/* find the matching char */

	if (second == ']')		/* ] is special in patterns, so */
		strcpy(pat, "[][]");	/* use this: matches [ or ] */
	else
		sprintf(pat, "[%c%c]", first, second);

	while (re_search(dir, pat)) {	/* look for either first or second */
		if (character(point - (dir > 0)) == first)
			level++;
		else
			level--;
		if (level == 0)  /* when we return to same level, done */
			return point;
	}
	return -1;
}

/*
Move in direction dir past a matched pair of characters.
The first is from findch, the second one is at the same
position in otherch.
Return 1 on success, or if the end of the buffer is encountered
before the first character is found.  Otherwise maybe show message,
go to starting point, and return 0.
*/

move_level(int dir, char *findch, char *otherch, int show)
{
	int res;

	if (mode_move_level)
		res = (*mode_move_level)(dir);
	else
		res = default_move_level(dir, findch, otherch);
	if (res == -1) {
		if (show)
			say("Unmatched delimiter");
		return 0;
	}
	point = res;
	return 1;
}

init_auto_show_delimiter()
{
	if (!show_matching_start_spot) {	// Initialize.
		show_matching_start_spot = alloc_spot(1);
		show_matching_end_spot = alloc_spot(1);
		if (modify_region(SHOW_MATCHING_REGION, MRTYPE, -1) != -1)
			remove_region(SHOW_MATCHING_REGION);
		add_region(show_matching_start_spot, show_matching_start_spot,
				   color_class show_matching_start, 0,
				   SHOW_MATCHING_REGION);
		add_region(show_matching_end_spot, show_matching_end_spot,
				   color_class show_matching_end, 0,
				   SHOW_MATCHING_REGION);
	}
}

// Try moving in the indicated direction over a set of delimiters.
// Then see if we can return to our starting point.  Return 1 if so.

try_auto_show_delimiter(int dir, char *near, char *far)
{
	int orig, there;

	save_var point;
	if (dir > 0) {	// Only go one line forward, and not too far back.
		save_var narrow_start = give_begin_line();
		save_var narrow_end = size() - (point + c_look_back);
	} else {		// Only go one line back, and not too far forward.
		save_var narrow_start = ++point - c_look_back;
		save_var narrow_end = size() - give_end_line();
	}
	orig = point;
	if (!move_level(dir, near, far, 0))
		return 0;
	there = point;
	if (!move_level(-dir, far, near, 0) || point != orig)
		return 0;
	if (there < point) {
		*show_matching_start_spot = there;
		*show_matching_end_spot = point - 1;
	} else {
		*show_matching_start_spot = point;
		*show_matching_end_spot = there - 1;
	}
	return 1;
}

// Highlight matching delimiter if we're on one.
// Returns 0 if we're not supposed to highlight, 1 if we're not
// on a delimiter character, 2 if we couldn't find its match,
// or 3 if we successfully highlighted delimiters.

int maybe_auto_show_delimiter()
{
	if (show_matching_start_spot)	// Remove existing highlight.
		modify_region(SHOW_MATCHING_REGION, MRTYPE, 0);
	if (!auto_show_matching_characters || number_of_popups() > 0)
		return 0;
	if (!index(auto_show_matching_characters, curchar()))
		return 1;				// Not a delimiter we can match.
	save_var point, matchstart, matchend, abort_searching = 0;
	init_auto_show_delimiter();
	if (try_auto_show_delimiter(1, LEFTD, RIGHTD) ||
		try_auto_show_delimiter(-1, RIGHTD, LEFTD)) {
		modify_region(SHOW_MATCHING_REGION, MRTYPE, REGINCL);
		return 3;			// Show the two regions.
	}
	return 2;
}

// Copy buffer-specific variables from one buffer to another,
// then clear those that should be unique to each buffer.

safe_copy_buffer_variables(to, from)
{
	copy_buffer_variables(to, from);
	save_var bufnum = to;
	show_matching_start_spot = 0;	// A spot in the current buffer.
	show_matching_end_spot = 0;	// A spot in the current buffer.
	precol = 0;		// A structure with spots in it.
}

to_line_comment()	/* go to start of comment on this line, or eol */
{			/* return 1 if there was comment, else 0 */
	int end;

	save_var narrow_start = give_begin_line();
	to_end_line();
	end = point;
	if (re_search(RE_REVERSE, comment_start))
		return 1;
	point = end;
	return 0;
}

to_comment_column()	/* replace whitespace here with comment indentation */
{
	int this;

	delete_horizontal_space();
	this = current_column();
	if (!this && !comment_column)
		return;
	else if (this >= comment_column)
		stuff(" ");	/* code extends past comment col */
	else
		insert_to_column(this, comment_column);
}

command indent_for_comment() on reg_tab[ALT(';')]
{
	int pt = point, scom;

	if (has_arg) {
		if (iter < 0) {
			to_begin_line();
			if (!re_search(RE_REVERSE, comment_start)) {
				point = pt;
				error("No previous comment found.");
			}
		}
		if (!re_search(RE_FORWARD, comment_start)) {
			point = pt;
			error("No comment found.");
		}
		iter = 0;
		return;
	}
	if (to_line_comment()) {	/* line has comment */
		if (pt > point) {	/* if we were in the comment */
			scom = point;	/* remember where comment was */
			point = pt;	/* stay there after */
			save_spot point = scom;
			to_comment_column();	/* now reindent it */
		} else {
			to_comment_column();	/* reindent it */
			re_search(RE_FORWARD, comment_start);
		}			/* go to start of comment */
	} else {
		to_comment_column();	/* make a new comment on this line */
		stuff(comment_begin);
		pt = point;
		stuff(comment_end);
		point = pt;		/* insert comment text here */
	}
}

command set_comment_column() on cx_tab[';']
{				/* put future comments in this column */
	int newcol, orig = point;

	if (iter < 0) {
		kill_comment();
		return;
	}
	if (has_arg) {	/* copy comment column from last comment */
		to_begin_line();
		re_search(RE_REVERSE, comment_start);
		newcol = current_column();
		point = orig;
		iter = 0;
	} else
		newcol = current_column(); /* start comments here */
	comment_column = newcol;
	if (!to_line_comment()) {
		point = orig;
		return;
	}
	to_comment_column();
}

command kill_comment()		/* kill any comment on this line */
{
	int start;

	iter = 0;
	if (!to_line_comment())
		error("This line has no comment.");
	re_search(RE_REVERSE, "[ \t]*");
	start = point;
	re_search(RE_FORWARD, comment_pattern);
	do_save_kill(start, point);
}

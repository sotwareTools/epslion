/************************************************************************
* "Epsilon" is a registered trademark licensed to Lugaru Software, Ltd. *
*		"EEL" and "Lugaru" are trademarks of Lugaru Software, Ltd.		*
*																		*
*  Copyright (C) 1996, 1997 Lugaru Software Ltd.  All rights reserved.  *
*																		*
* Limited permission is hereby granted to reproduce and modify this		*
* copyrighted material provided that the resulting code is used only in *
* conjunction with Lugaru products and that this notice is retained in	*
* any such reproduction or modification.								*
************************************************************************/

char _tex_mode_name[] = "TeX";
char _latex_mode_name[] = "LaTeX";
user char tex_auto_show_delim_chars[20] = "{[]}";

user int tex_look_back = 20000;
	// When to give up on finding paragraph boundaries while coloring.

keytable tex_tab;			/* key table for TeX mode */
user buffer char tex_force_latex = 1;
// 0=assume raw TeX, 1=assume LaTeX, 2=LaTeX if there's a \begin{document}
#define TEX_ENV_BUF		"-TeX Envs"
user char tex_environment_name[80] = "document";	// last env selected
user char compile_tex_cmd[128] = "tex \"%r\""; // cmd line to compile TeX

color_class tex_text;
color_class tex_comment;
color_class tex_curly_brace;
color_class tex_square_bracket;
color_class tex_math;
color_class tex_literal;
color_class tex_command;
color_class tex_begin_end;
color_class tex_section;

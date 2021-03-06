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

/* subprocess variables */

keytable process_tab;
char _process_mode_name[] = "Process";

user char shell_shrinks = 1;	// should epsilon swap itself out during push?
user char capture_output = 0; // should epsilon intercept output during push?
user char save_when_making = 2; // should make call save-all-buffers first?
	/* if not 0 or 1, ask when there are unsaved changes */
user char push_cmd[FNAMELEN] = "make";
user char concurrent_make = 1; // 2=always, 1=if concur proc, 0=never
user buffer char concurrent_compile = 3;  // like above, for compiling, if < 3
user char restart_concurrent = 1; // after stopping concur to run proc
buffer int (*pre_compile_hook)(); // mode-based adjustments
buffer int (*post_compile_hook)();
user buffer char *compile_buffer_cmd;  // compile-buffer runs this cmd
user char compile_eel_cmd[128] = "%Xeel \"%r\"";
									// c mode uses this for .e files
user char compile_eel_dll_flags[128] = "-n -q";	// internal compile flags
user char compile_c_cmd[128] = "cl \"%r\"";	  // set for your c compiler
user char compile_cpp_cmd[128] = "cl \"%r\""; // set for your c++ compiler
user char compile_java_cmd[128] = "javac \"%r\""; // ... java compiler

spot error_spot = 0;		/* last error parsed in process buffer */
user char clear_process_buffer = 0; // does new process cmd clear proc buffer?
#define PROCBUF		"process"	/* name of the process buffer */
zeroed char _had_errors;
user char ignore_error[70]; // if error matches this pattern, we will ignore it
			// to ignore warnings, for example, set to .*warning.*

user char use_process_current_directory = 1; // share cur dir with concur?
user char start_process_in_buffer_directory = 2; // run proc in buf's dir?
user char start_make_in_buffer_directory = 0; // run make in buf's dir?
user char process_enter_whole_line = 1;	// <Enter> sends whole line?
user short process_tab_size = 8;
int color_process_range(int from, int to);

color_class process_output;
color_class process_input;
color_class process_prompt;

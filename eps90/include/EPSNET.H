/************************************************************************
* "Epsilon" is a registered trademark licensed to Lugaru Software, Ltd. *
*		"EEL" and "Lugaru" are trademarks of Lugaru Software, Ltd.		*
*																		*
*	   Copyright (C) 1997 Lugaru Software Ltd.  All rights reserved.	*
*																		*
* Limited permission is hereby granted to reproduce and modify this		*
* copyrighted material provided that the resulting code is used only in *
* conjunction with Lugaru products and that this notice is retained in	*
* any such reproduction or modification.								*
************************************************************************/

#define EPSNET_DLL "epsnet.dll"
#define finger_user(request, hostname, bufname) \
			(call_dll(EPSNET_DLL, "finger_user", "c", "sss", request, hostname, bufname))

#define http_retrieve(filename, hostname, port, bufname, flags) \
			(call_dll(EPSNET_DLL, "http_retrieve", "c", "ssisi", filename, hostname, port, bufname, flags))

#define telnet_host(hostname, port, bufname) \
			(call_dll(EPSNET_DLL, "telnet_host", "c", "sis", hostname, port, bufname))

#define telnet_send(telnet_id, text) \
			(call_dll(EPSNET_DLL, "telnet_send", "c", "is", telnet_id, text))


#define ftp_op(bufname, logname, host, usr, passwd, name, op) \
			(call_dll(EPSNET_DLL, "ftp_op", "c", "ssssssi", bufname, logname, host, usr, passwd, name, op))



#define active_callbacks() (call_dll(EPSNET_DLL, "active_callbacks", "c", ""))


buffer int (*when_net_activity)();	// called by epsilon during net job

char finger_default[FNAMELEN];
user char anon_ftp_password[FNAMELEN] = "-EpsilonUser@unknown.host";
user char ftp_ascii_transfers;	// Set nonzero for VMS and similar systems.
user char ftp_compatible_dirs;	// Set nonzero for VMS and similar systems.
buffer int telnet_id;
buffer int (*buffer_ftp_activity)();
char *get_url_file_part(char *url, int separator);
#define CONNECT_LIST_BUF	"-connections"

// Parsing the URL puts the data in one of these.

struct url_parts {
	char service[FNAMELEN];		// "http", "ftp", etc.
	char host[FNAMELEN];		// The host name.
	char usr[FNAMELEN];			// User name (can be "anonymous").
	char pwd[FNAMELEN];			// Password (can be empty).
	char port[FNAMELEN];		// Port number if any, as text.
	char fname[FNAMELEN];		// The file name.
	int have_password, have_usr; // These items can be specififed but empty.
};

// We must send a password to the DLL on every FTP operation.
// Maintain the passwords here so we don't have to keep asking
// the user.  The structure is marked "zeroed" to ensure that it's
// never saved in an Epsilon state file.

zeroed struct password_data {
	struct password_data *next;
	char host[FNAMELEN];
	char usr[FNAMELEN];
	char pwd[FNAMELEN];
	int invalid;		// If nonzero, prompt for a new pwd next time.
} *password_data;

struct ftp_job {
	int id;				// A code from the DLL.
	int operation;		// FTP_SEND, FTP_RECV, etc.
	int buf;			// Data goes in this buffer.
	int log_buf;		// The log file with status messages.
	int file_size;		// We need to send/retrieve this many bytes
	int so_far;			// and we've done this many bytes so far.
	int time_started;	// Value of time_ms() when we started.
};
buffer struct ftp_job *ftp_job;

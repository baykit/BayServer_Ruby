# BayServer for Ruby

# 3.0.1

- Fixes minor bugs

# 3.0.0

- [Core] Performes a significant overall refactoring.
- [Core] Introduces a multiplexer type to allow flexible configuration of the I/O multiplexing method.
- [Core] Adopts the CIDR format for specifying source IP control.
- [CGI] Introduce the maxProcesses parameter to allow control over the number of processes to be started.

# 2.3.2

- [core] Fixes the issue encountered when aborting GrandAgent.

# 2.3.1

- [Core] Addresses potential issues arising from I/O errors.
- [Core] Fixes the issue encountered when aborting GrandAgent.

# 2.3.0

- [CGI] Supports "timeout" parameter. (The timed-out CGI processes are killed)
- [Core] Improves the memusage output
- [Core] Fixes some bugs

# 2.2.2

- Fixes some bugs

# 2.2.1

- Implements unimplemented methods when aborting grand agent
- Adds license and readme to each gem
- Changes startup script from bayserver to bayserver_rb

# 2.2.0
- Supports Gem install


# 2.1.1

- Supports control commands (reload, relodCert, shutdown, abort)
- Fixes some bugs

# 2.1.0

- Supports multi core mode for Windows
- Fixes some bugs

# 2.0.4

- Fixes problem on handling admin-ajax.php of WordPress
- Fixes write error when socket write buffer is full
- Fixes some bugs and syntax erros

# 2.0.3

- Fixes problem of AJP warp docker
- Fixes problem of FCGI warp docker
- Fixes problem on high CPU usage on using proxy front of BayServer

# 2.0.2

- Fixes HTTP/2 bugs
- Fixes problem on handling wp-cron.php of WordPress
- Fixes error on writing access logs 

# 2.0.1

- Modifies bayserver.plan to avoid resolving host name


# 2.0.0

- First version

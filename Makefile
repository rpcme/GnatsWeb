# Makefile for gnatsweb
#
# $Id: Makefile,v 1.1.1.1 2001/04/28 11:00:57 yngves Exp $

INSTALL_CGI =	gnatsweb.pl gnats.pm \
		gnatsweb.html \
		gnatsweb-site-sente.pl \
		gnats/*.pm \
		charts/*.pl
INSTALL_LOCAL = 
OTHER_FILES =	ChangeLog INSTALL Makefile README TODO \
		test.pl
TARBALL_ALL =	$(INSTALL_CGI) $(OTHER_FILES)
PERL =		perl

default:
	@echo "usage:"
	@echo
	@echo '    make test'
	@echo '    make install CGI_DIR=/home/httpd/cgi-bin'
	@echo
	@false

test:
	$(PERL) test.pl

install:
	if [ -z "$(CGI_DIR)" ]; then \
		echo 'The CGI_DIR macro is required:'; \
		echo ''; \
		echo '    make install CGI_DIR=/home/httpd/cgi-bin'; \
		echo ''; \
		exit 1; \
	else \
		tar -cf - $(INSTALL_CGI) $(INSTALL_LOCAL) \
			| (cd $(CGI_DIR); tar xvf -); \
	fi

#-----------------------------------------------------------------------------
# targets I use for development

# Extract the revision string from gnatsweb.pl into VERSION.
VERSION := $(shell $(PERL) -e '$$suppress_main=1; do "gnatsweb.pl"; print $$VERSION;')

# Hide certain site specific code from others.
REMOVE_PRIVATE_STUFF = $(PERL) -p -i -e 'undef $$_ if /EXCLUDE THIS LINE/;'

no-debug-statements:
	if egrep -s 'debug = 1' gnatsweb.pl; then \
		echo '*** get rid of those debugging stmts, bonehead ***'; \
		exit 1; \
	else :; \
	fi

tarball: no-debug-statements
	rm -rf gnatsweb-$(VERSION)
	mkdir gnatsweb-$(VERSION)
	tar -cvf - $(TARBALL_ALL) \
		| (cd gnatsweb-$(VERSION); tar xf -)
	$(REMOVE_PRIVATE_STUFF) gnatsweb-$(VERSION)/gnatsweb-site-sente.pl
	tar -czf $$HOME/gnatsweb-$(VERSION).tar.gz gnatsweb-$(VERSION)
	rm -rf gnatsweb-$(VERSION)
	ncftpput -f ~/.ncftp/ftp.senteinc.com /public_ftp/gnatsweb \
		$$HOME/gnatsweb-$(VERSION).tar.gz
	@echo
	@echo release is at:
	@echo "  ftp://ftp.senteinc.com/gnatsweb/gnatsweb-$(VERSION).tar.gz"
	@echo

contrib: no-debug-statements test
	tar -cvf - $(TARBALL_ALL) \
		| (cd $$HOME/src/gnats/contrib/gnatsweb; tar xf -)
	$(REMOVE_PRIVATE_STUFF) $$HOME/src/gnats/contrib/gnatsweb/gnatsweb-site-sente.pl

TAGS: $(INSTALL_CGI)
	etags $(INSTALL_CGI)

# i - install here
i: TAGS no-debug-statements test
	# save old tag so we know what last worked
	#cvs rcs -Npreviously_installed_at_sente:installed_at_sente .
	$(MAKE) install CGI_DIR=/home/httpd/cgi-bin \
		INSTALL_LOCAL=sente-reports.html
	# create new tag so we know what's installed locally
	cvs tag -F installed_at_sente

.PHONY: t
t:
	$(MAKE) test USERNAME=$(LOGNAME) PASSWORD=$(LOGNAME) DATABASE=main

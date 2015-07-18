# Makefile for Gnatsweb
#
# Copyright 1998, 1999, 2001, 2003
# - The Free Software Foundation Inc.
#
# This file is part of GNU Gnatsweb 
#
# GNU Gnatsweb is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# GNU Gnatsweb is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details. 
#
# You should have received a copy of the GNU General Public License
# along with Gnatsweb; see the file COPYING. If not, write to the Free
# Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
# 02111-1307, USA.
#
# $Id: Makefile,v 1.11.2.1 2003/07/29 12:24:22 yngves Exp $
#

INSTALL_CGI =	gnatsweb.pl \
		gnatsweb-site.pl gnatsweb.html
OTHER_FILES =	COPYING ChangeLog CUSTOMIZE CUSTOMIZE.cb CUSTOMIZE.vars \
		INSTALL NEWS Makefile README TROUBLESHOOTING test.pl \
		gnatsweb-site-example.pl 
INSTALL_ALL =	$(INSTALL_CGI) $(OTHER_FILES)
TARBALL_ALL =   $(INSTALL_CGI) $(OTHER_FILES)
PERL =		perl

default:
	@echo "usage:"
	@echo
	@echo '    make test'
	@echo '    make install CGI_DIR=/usr/local/apache/cgi-bin'
	@echo
	@false

test:
	@set -e; \
	$(PERL) test.pl

install:
	@set -e; \
	if test -z "$(CGI_DIR)"; then \
		echo 'The CGI_DIR option is required:'; \
		echo ''; \
		echo '    make install CGI_DIR=/usr/local/apache/cgi-bin'; \
		echo ''; \
		exit 1; \
	else \
		if test -f "$(CGI_DIR)/gnatsweb.pl"; then \
			mv $(CGI_DIR)/gnatsweb.pl $(CGI_DIR)/gnatsweb.pl.old; \
			echo "Preserved old gnatsweb.pl as gnatsweb.pl.old"; \
		fi; \
		cp gnatsweb.pl $(CGI_DIR); \
		echo "Copied gnatsweb.pl to $(CGI_DIR)"; \
		if test -f "$(CGI_DIR)/gnatsweb-site.pl"; then \
			echo "The $(CGI_DIR)/gnatsweb-site.pl file exists."; \
			echo "We will not overwrite it."; \
		else \
			cp gnatsweb-site.pl $(CGI_DIR); \
			echo "Copied gnatsweb-site.pl to $(CGI_DIR)"; \
		fi; \
		if test -f "$(CGI_DIR)/gnatsweb.html"; then \
			mv $(CGI_DIR)/gnatsweb.html $(CGI_DIR)/gnatsweb.html.old; \
			echo "Preserved old gnatsweb.html as gnatsweb.html.old"; \
		fi; \
		cp gnatsweb.html $(CGI_DIR); \
		echo "Copied gnatsweb.html to $(CGI_DIR)"; \
	fi

#-----------------------------------------------------------------------------
# targets I use for development

# Extract the revision string from gnatsweb.pl into VERSION.
VERSION := $(shell $(PERL) -e '$$suppress_main=1; do "gnatsweb.pl"; print $$VERSION;')

# Hide certain site specific code from others.
REMOVE_PRIVATE_STUFF = $(PERL) -p -i -e 'undef $$_ if /EXCLUDE THIS LINE/;'

no-debug-statements:
	if egrep -s '$$debug = 1' gnatsweb.pl; then \
		echo '**** Left-over debug statements detected. Please fix ****'; \
		exit 1; \
	else :; \
	fi

tarball: no-debug-statements
	rm -rf gnatsweb-$(VERSION)
	mkdir gnatsweb-$(VERSION)
	tar -cvf - $(TARBALL_ALL) \
		| (cd gnatsweb-$(VERSION); tar xf -)
	tar -cf - gnatsweb-$(VERSION) | gzip > $$HOME/gnatsweb-$(VERSION).tar.gz 
	rm -rf gnatsweb-$(VERSION)
	@echo
	@echo release is ready as:
	@echo "  gnatsweb-$(VERSION).tar.gz"
	@echo

contrib: no-debug-statements test
	tar -cvf - $(INSTALL_CGI) $(OTHER_FILES) \
		| (cd $$HOME/src/gnats/contrib/gnatsweb; tar xf -)
	$(REMOVE_PRIVATE_STUFF) $$HOME/src/gnats/contrib/gnatsweb/gnatsweb-site-sente.pl

TAGS: $(INSTALL_CGI)
	etags $(INSTALL_CGI)

install-snapshot: TAGS no-debug-statements test
	# save old tag so we know what last worked
	cvs rcs -Npreviously_installed_at_sente:installed_at_sente .
	$(MAKE) install CGI_DIR=..
	# create new tag so we know what's installed locally
	cvs tag -F installed_at_sente

install-tarball: TAGS tarball
	zcat gnatsweb-$(VERSION).tar.gz | (cd ..; tar xvf -)

link:
	rm -f gnatsweb-site.pl
	ln -s gnatsweb-site-sente.pl gnatsweb-site.pl

.PHONY: t
t:
	$(MAKE) test USERNAME=$(LOGNAME) DATABASE=test

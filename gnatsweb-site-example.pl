# gnatsweb-site.pl -
#     Gnatsweb site-specific variables and subroutines.
#
# Copyright 1998, 1999, 2001, 2003
# - The Free Software Foundation Inc.
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
# $Id: gnatsweb-site-example.pl,v 1.9.2.1 2003/07/29 12:24:22 yngves Exp $
#

# GNATS host.
$site_gnats_host = 'localhost';

# The port which the GNATS server is running on.
# Default installations of GNATS run on port 1529.
$site_gnats_port = '1529';

# Subroutine for customizing setup and behaviour.
# Gnatsweb customizations should be done here instead of in the main script.
# This isolates changes and makes for easier upgrades.
# We provide a range of example callbacks below.
sub site_callback {
    my($reason, @args) = @_;

    # Use warn() to facilitate debugging.
    # Look for the messages in the web server error log.
    #warn "site_callback: @_\n";


	# The following callback routine creates a form button which takes
	# the user to the Create PR page with Class set to 'support' and
	# Submitter-Id set to 'external'.  It is called from inside the
	# main_page subroutine of gnatsweb.pl.
    if ($reason eq 'main_page_top_buttons')
	{
		my $html = one_line_form('Open Support Issue:',
					  $q->submit(-name=>'cmd', -value=>'create'),
					  $q->hidden(-name=>'Class', -default=>'support'),
					  $q->hidden(-name=>'Submitter-Id', -default=>'internal'));
		return $html;
	}

    # The following routine is similar to the previous one.  It
    # creates two buttons for the bottom of the main page.  The first
    # button allows the user to search directly for all open PRs, the
    # second provides a direct search for all non-closed PRs.  Note
    # that the buttons submit the commands 'open' and 'not closed'
    # respectively.  These are commands that aren't supported in the
    # default gnatsweb.pl, but below, we use the 'cmd' callback hook
    # to provide these commands.
    elsif ($reason eq 'main_page_bottom_buttons')
    {
        my $html = one_line_form('Direct search:',
                            $q->submit(-name=>'cmd', -value=>'open'),
                            '&nbsp;',
						    $q->submit(-name=>'cmd', -value=>'not closed'));
        return $html;
    }

	# This routine is called from the page_start_html subroutine of
	# gnatsweb.pl.  It overrides the default HTML written on top of
	# each page, i.e. the banner and the button bar, replacing it with
	# a very simplistic banner.
	elsif ($reason eq 'page_start_html')
	{
		my $title = $args[0];
		my $html = $q->b(uc("$title - $site_banner_text")) . $q->hr;
		return $html;
	}

    # Construct the HTML which will be printed just below the heading
    # on the login page.
    elsif ($reason eq 'login_page_text')
    {
        my $html = $q->p('This is the GNATS bug tracking system used for
                          reporting bugs in our defrobulator products.') .
                   $q->p("Use your password and username to log in.
                          If you haven't been assigned a login,
                          please contact " .
                   $q->a({-href=>'mailto:helpdesk@example.com'},
                          'helpdesk@example.com'));
        return $html;
    }

	# Construct HTML which will be added above the Description field
    # in the View and Edit pages.
    elsif ($reason =~ /^(sendpr|edit)_intro_Description$/)
    {
        my $stuff = "<b>Description should include contact info<b>"
            . "<br>";
        return $stuff;
    }

	# The following block of code is called from the end of the main
	# routine of gnatsweb.pl.  It allows us to define custom commands,
	# in this case 'open' and 'not closed'.  The first searches for
	# all open PRs and the second searches for all non-closed PRs.  We
	# use this commands to provide direct searches from the main page,
	# see above.
    elsif ($reason eq 'cmd')
    {
        my $cmd = $args[0];

        if ($cmd eq 'open')
        {
            # Direct search for open PRs
			print_header(-cookie => create_global_cookie());
            initialize();
            my $page = 'Query Results';
            my $heading = 'Query Results';
            page_start_html($page);
            page_heading($page, $heading);
            $q->param(-name=>'columns',-values=>['Category','Synopsis','Responsible',
                                                 'State','Arrival-Date'
                                                 ]);
            client_cmd("rset");
            client_cmd('qfmt "%s^_%d^_%s^_%d^_%d^_%{%Y-%m-%d %H:%M:%S %Z}D" ' . 
                       'builtinfield:Number Category Synopsis Responsible State Arrival-Date');
			client_cmd("expr State~\"open\"");
            my(@query_results) = client_cmd("quer");
            display_query_results(@query_results);
            page_footer($page);
            page_end_html($page);
            exit;
        }

		elsif ($cmd eq 'not closed')
		{
            # Direct search for non-closed PRs
			print_header(-cookie => create_global_cookie());
			initialize();
			my $page = 'Query Results';
			my $heading = 'Query Results';
			page_start_html($page);
			page_heading($page, $heading);
            $q->param(-name=>'columns',-values=>['Category','Synopsis','Responsible',
                                                 'State','Arrival-Date'
                                                 ]);
            client_cmd("rset");
            client_cmd('qfmt "%s^_%d^_%s^_%d^_%d^_%{%Y-%m-%d %H:%M:%S %Z}D" ' . 
                       'builtinfield:Number Category Synopsis Responsible State Arrival-Date');
			client_cmd("expr ((! builtinfield:State[type]=\"closed\"))");
			my(@query_results) = client_cmd("quer");
			display_query_results(@query_results);
			page_footer($page);
			page_end_html($page);
			exit;
		}
	}
}

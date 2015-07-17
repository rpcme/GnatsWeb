#
# gnatsweb-site.pl -
#     Gnatsweb site-specific variables and subroutines.
#
# $Id: gnatsweb-site-sente.pl,v 1.1.1.1 2001/04/28 11:00:57 yngves Exp $

# Gnats host.
$site_gnats_host = 'gnats.senteinc.com';
$site_gnats_port = 1529;

# Name you want in the page banner.
$site_banner_text = 'Sente gnatsweb';

# Make gnatsweb appear different if I'm running a test version,
# so I know where I am.
if (($ENV{'SCRIPT_NAME'} =~ m@/cgi-bin/gnatsweb/@)   # running in test subdir
    || ($ENV{'REMOTE_ADDR'} eq '127.0.0.1')) # testing @ home
{
    $site_banner_text = 'TEST VERSION OF GNATSWEB';
    $site_banner_background = 'red';
    $site_background = 'bisque';
}

# Turn on special checking for Doug MacEachern's modperl
if (exists $ENV{'GATEWAY_INTERFACE'} 
    && ($MOD_PERL = $ENV{'GATEWAY_INTERFACE'} =~ /^CGI-Perl\//))
{
    $site_banner_text = 'mod_perl TEST';
    $site_banner_background = 'orange';
    $site_background = '#c0ffc0';
}

# Make sure nobody tries to swamp our server with a huge file attachment.
$site_post_max = 2000000; # 2Mb

# site_callback -
#     Override gnatsweb behavior under certain circumstances.
#
#     Return undef if not handling it.
#
sub site_callback {
    my($reason, @args) = @_;

    # Use warn() to facilitate debugging.  Look for the messages in the
    # system log, e.g. /var/log/httpd/error_log
    #warn "site_callback: @_\n";

    if ($reason eq 'main_page_top_buttons')
    {
        # Add buttons to the top of the main page.
        # A support issue is different from a regular PR in that the
        # responsible person is the submitter and the class is 'support'.
        # See also PR 1309.
        my $form = one_line_form('Open Support Issue:',
                                 one_line_submit('cmd', 'support call'),
                                 hidden('Class', 'support'),
                                 hidden('Responsible', $ENV{'REMOTE_USER'}),
                                 hidden('Submitter-Id', 'sente'));
        return $form;
    }
    elsif ($reason eq 'main_page_bottom_buttons')
    {
        # Add report buttons to the bottom of the main page.
        my $form = one_line_form('Reports and Charts:',
                                 one_line_submit('cmd', 'reports'));
        return $form;
    }
    elsif ($reason eq 'cmd')
    {
        # Handle site-specific values for 'cmd' param.
        my $cmd = shift(@args);
        if ($cmd eq 'reports') {
            my $page = 'Reports and Charts';
            print $q->header();
            page_start_html($page);
            page_heading("Sente $page", $page);
            send_html('sente-reports.html');
            page_footer($page);
            page_end_html($page);
            return 1;
        }
        elsif ($cmd eq 'support call') {
            initialize();
            sendpr();
            return 1;
        }
    }
    elsif ($reason eq 'get_default_value')
    {
        my $default_what = shift(@args);
        if ($default_what eq 'email') {
            return "$ENV{'REMOTE_USER'}\@senteinc.com";
        }
    }
    elsif ($reason eq 'sendpr_fix')
    {
        # default Fix text
        return " Fix for: \n Fixed in: \n";
    }
    elsif ($reason =~ /^(sendpr|edit)_intro_description$/)
    {
        # Stuff to include on top of the Description textarea.
        my $new_frame = "frame" . $q->escape(scalar(localtime()));
        my $stuff = "Description should include contact info; "
            . "<br>";
        return $stuff;
    }
    elsif ($reason eq 'initialize')
    {
        # Include changes to the Fix field in the Audit-Trail.
        $fieldnames{'Fix'} |= $AUDITINCLUDE;
        # Allow assigning user upon PR submission.  See also PR 1309.
        $fieldnames{'Responsible'} &= ~$SENDEXCLUDE;
        # Allow assigning state upon PR submission.  See also PR 1308.
        $fieldnames{'State'} &= ~$SENDEXCLUDE;
    }
    elsif ($reason eq 'page_footer')
    {
        # override footer html
        my($title) = @args;
        if ($title eq 'View PR')
        {
            # Add one-click buttons at footer of view PR page.
            return sente_view_postlude();
        }
        #return h3("$title -- page_footer");
    }
    #elsif ($reason eq 'page_heading')
    #{
    #    # override heading html
    #    my($title, $heading) = @args;
    #    return h1({-style=>'color:red'}, $heading);
    #}
    #elsif ($reason eq 'page_start_html')
    #{
    #    # override initial html
    #    my($title) = @args;
    #    return start_html(-title=>$title, -bgcolor=>'yellow') .
    #            hr({-width=>'50%', -noshade=>1, -size=>10});
    #}
    #elsif ($reason eq 'page_end_html')
    #{
    #    # override final html
    #    my $title = shift(@args);
    #    return h3("$title -- page_end_html") . end_html();
    #}
    undef;
}

# sente_one_click_edit_form -
#
#     Helper function to sente_view_postlude
#
sub sente_one_click_edit_form
{
    my($short_desc, $button_name, $reason, @form_elems) = @_;
    my $disclaimer = "[standard one-click response]\n";

    # This bit of HTML is common to all one-click edit actions.
    my $html = '<tr align=left valign=top><td>'
        . $q->start_form()
        . $q->hidden(-name=>'Editor', -value=>$db_prefs{'user'}, -override=>1)
        . $q->hidden(-name=>'Last-Modified',
                     -value=>$fields{'Last-Modified'},
                     -override=>1)
        . $q->hidden(-name=>'pr', -value=>$pr, -override=>1)
        . $q->hidden(-name=>'cmd',
                     -value=>'submit edit',
                     -override=>1);

    # Add the button and the other form elements.
    $html .= $q->submit(-name=>'unused', -value=>$button_name)
        . "@form_elems";

    $html .= $q->end_form()
        . '</td>'
        . '<td>&nbsp;&nbsp;&nbsp;</td>'
        . "<td><strong>$short_desc</strong></td>"
        . '<td>&nbsp;&nbsp;&nbsp;</td>'
        . "<td><pre><small>$disclaimer$reason</small></pre></td>"
        . '</tr>';

    $html;
}

# sente_view_postlude -
#
#     Print forms which perform one-click actions.
#
sub sente_view_postlude
{
    # These one-click actions only apply to editors.
    return undef unless can_edit();

    # Canned reasons to submit as "-Why" fields during one-click actions.
    my(%reason) =
        ('mine' =>     "This issue is mine.",
         'analyzed' => "I understand the problem.");

    my $html = "<table cellspacing=0 cellpadding=0 border=0>\n";
    $html .= sente_one_click_edit_form('Responsible = me',
                                       'mine',
                                       $reason{'mine'},
         $q->hidden(-name=>'Responsible',
                    -value=>$db_prefs{'user'}, -override=>1),
         $q->hidden(-name=>'Responsible-Why',
                    -value=>$reason{'mine'}, -override=>1));
    $html .= sente_one_click_edit_form('State = analyzed',
                                       'analyzed',
                                       $reason{'analyzed'},
         $q->hidden(-name=>'State', -value=>'analyzed', -override=>1),
         $q->hidden(-name=>'State-Why',
                    -value=>$reason{'analyzed'}, -override=>1));
    $html .= '</table>';
    #warn "---html---\n$html\n---\n";
    $html;
}

1;

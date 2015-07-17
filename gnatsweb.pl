#!/usr/bin/perl -w
#
# Gnatsweb - web front-end to gnats
#
# Copyright 1998-1999 - Matt Gerassimoff
# and Ken Cox
#
# $Id: gnatsweb.pl,v 1.30 2001/06/27 16:58:10 yngves Exp $
#

#-----------------------------------------------------------------------------
# Site-specific customization -
#
#     WE STRONGLY SUGGEST you don't edit these variables here, but instead
#     put them in a file called 'gnatsweb-site.pl' in the same directory.
#     That way, when a new version of gnatsweb is released, you won't
#     need to edit them again.
#

# Info about your gnats host.
$site_gnats_host = 'localhost';
$site_gnats_port = 1529;

# Set to true if you compiled gnats with GNATS_RELEASE_BASED defined.
$site_release_based = 0;

# Name you want in the page banner and banner color.
$site_banner_text = 'gnatsweb';
$site_banner_background = '#000000';
$site_banner_foreground = '#ffffff';

# Page background color -- not used unless defined.
#$site_background = '#c0c0c0';

# Uncomment the following line and insert stylesheet URL in order to
# link all generated pages to an external stylesheet. Both absolute
# and relative URLs are supported.
#$site_stylesheet='http://url.of/stylesheet';

# Have the HTTP header, start_html, heading already been printed?
my $print_header_done = 0;
my $page_start_html_done = 0;
my $page_heading_done = 0;

# Program to send email notifications.
if (-x '/usr/sbin/sendmail')
{
  $site_mailer = '/usr/sbin/sendmail -oi -t';
}
elsif (-x '/usr/lib/sendmail')
{
  $site_mailer = '/usr/lib/sendmail -oi -t';
}
else
{
  die("Can't locate 'sendmail'; must set \$site_mailer in gnats-site.pl");
}

# site_callback -
#
#     If defined, this subroutine gets called at various times.  The
#     reason it is being called is indicated by the $reason argument.
#     It can return undef, in which case gnatsweb does its default
#     thing.  Or, it can return a piece of HTML to implement
#     site-specific behavior or appearance.
#
#     Sorry, the reasons are not documented.  Either put a call to
#     'warn' into your gnats-site.pl file, or search this file for 'cb('.
#     For examples of some of the things you can do with the site_callback
#     subroutine, see gnatsweb-site-sente.pl.
#
# arguments:
#     $reason - reason for the call.  Each reason is unique.
#     @args   - additional parameters may be provided in @args.
#
# returns:
#     undef     - take no special action
#     string    - string is used by gnatsweb according to $reason
#
# example:
#     See gnatsweb-site-sente.pl for an extended example.
#
#     sub site_callback {
#         my($reason, @args) = @_;
#         if ($reason eq 'sendpr_description') {
#             return 'default description text used in sendpr form';
#         }
#         undef;
#     }
#

# end customization
#-----------------------------------------------------------------------------

# Use CGI::Carp first, so that fatal errors come to the browser, including
# those caused by old versions of CGI.pm.
use CGI::Carp qw/fatalsToBrowser/;
# 8/22/99 kenstir: CGI.pm-2.50's file upload is broken.
# 9/19/99 kenstir: CGI.pm-2.55's file upload is broken.
use CGI 2.56 qw(-oldstyle_urls :all);
use gnats qw/client_init client_exit client_cmd/;

# Debugging fresh code.
#$gnats::DEBUG_LEVEL = 2;

# Version number + RCS revision number
$VERSION = '2.8.2';
$REVISION = (split(/ /, '$Revision: 1.30 $ '))[1];

# width of text fields
$textwidth = 60;

# where to get help -- a web site with translated info documentation
#$gnats_info_top = 'http://www.hyperreal.org/info/gnuinfo/index?(gnats)';
$gnats_info_top = 'http://sources.redhat.com/gnats/gnats_toc.html';

# bits in %fieldnames has (set=yes not-set=no)
$MULTILINE    = 1;   # whether field is multi line
$SENDEXCLUDE  = 2;   # whether the send command should exclude the field
$REASONCHANGE = 4;   # whether change to a field requires reason
$ENUM         = 8;   # whether field should be displayed as enumerated
$EDITEXCLUDE  = 16;  # if set, don't display on edit page
$AUDITINCLUDE = 32;  # if set, save changes in Audit-Trail

$| = 1; # flush output after each print

# Return true if module MIME::Base64 is available.  If available, it's
# loaded the first time this sub is called.
sub can_do_mime
{
  return $can_do_mime if (defined($can_do_mime));

  # Had to basically implement 'require' myself here, otherwise perl craps
  # out into the browser window if you don't have the MIME::Base64 package.
  #$can_do_mime = eval 'require MIME::Base64';
  ITER: {
    foreach my $dir (@INC) {
      my $filename = "$dir/MIME/Base64.pm";
      if (-f $filename) {
        do $filename;
        die $@ if $@;
        $can_do_mime = 1;
        last ITER;
      }
    }
    $can_do_mime = 0;
  }
  #warn "NOTE: Can't use file upload feature without MIME::Base64 module\n";
  return $can_do_mime;
}

# Take the file attachment's file name, and return only the tail.  Don't
# want to store any path information, for security and clarity.  Support
# both DOS-style and Unix-style paths here, because we have both types of
# clients.
sub attachment_filename_tail
{
  my($filename) = @_;
  $filename =~ s,.*/,,;  # Remove leading Unix path elements.
  $filename =~ s,.*\\,,; # Remove leading DOS path elements.

  return $filename;
}

# Retrieve uploaded file attachment.  Return it as
# ($filename, $content_type, $data).  Returns (undef,undef,undef)
# if not present.
#
# See 'perldoc CGI' for details about this code.
sub get_attachment
{
  my $upload_param_name = shift;
  my $debug = 0;
  my $filename = $q->param($upload_param_name);
  return (undef, undef, undef) unless $filename;

  # 9/6/99 kenstir: My testing reveals that if uploadInfo returns undef,
  # then you can't read the file either.
  warn "get_attachment: filename=$filename\n" if $debug;
  my $hashref = $q->uploadInfo($filename);
  if (!defined($hashref)) {
    die "Got attachment filename ($filename) but no attachment data!  Probably this is a programming error -- the form which submitted this data must be multipart/form-data (start_multipart_form()).";
  }
  if ($debug) {
    while (($k, $v) = each %$hashref) {
      warn "get_attachment: uploadInfo($k)=$v\n";
    }
  }

  # 9/6/99 kenstir: When testing locally on Linux, a .gz file yielded
  # no Content-Type.  Therefore, have to assume binary.  Would like to
  # check (-B $fh) to see if the stream is binary but that doesn't work.
  my $ctype = $hashref->{'Content-Type'} || 'application/octet-stream';
  warn "get_attachment: Content-Type=$ctype\n" if $debug;

  my $data = '';
  my $buf;
  my $fh = $q->upload($upload_param_name);
  warn "get_attachment: fh=$fh\n" if $debug;
  while (read($fh, $buf, 1024)) {
    $data .= $buf;
  }
  close $fh;

  return ($filename, $ctype, $data);
}

# Retrieve uploaded file attachment, and encode it so that it's 
# printable, for inclusion into the PR text.
#
# Returns the printable text representing the attachment.  Returns '' if
# the attachment was not present.
sub encode_attachment
{
  my $upload_param_name = shift;
  my $debug = 0;

  return '' unless can_do_mime();

  my ($filename, $ctype, $data) = get_attachment($upload_param_name);
  return '' unless $filename;

  # Strip off path elements in $filename.
  $filename = attachment_filename_tail($filename);

  warn "encode_attachment: $filename was ", length($data), " bytes of $ctype\n"
        if $debug;
  my $att = '';

  # Plain text is included inline; all else is encoded.
  $att .= "Content-Type: $ctype; name=\"$filename\"\n";
  if ($ctype eq 'text/plain') {
    $att .= "Content-Disposition: inline; filename=\"$filename\"\n\n";
    $att .= $data;
  }
  else {
    $att .= "Content-Transfer-Encoding: base64\n";
    $att .= "Content-Disposition: attachment; filename=\"$filename\"\n\n";
    $att .= MIME::Base64::encode_base64($data);
  }
  warn "encode_attachment: done\n" if $debug;

  return $att;
}

# Takes the encoded file attachment, decodes it and returns it as a hashref.
sub decode_attachment
{
  my $att = shift;
  my $debug = 0;
  my $hash_ref = {'original_attachment' => $att};

  # Split the envelope from the body.
  my ($envelope, $body) = split(/\n\n/, $att);
  return $hash_ref unless ($envelope && $body);

  # Split mbox-like headers into (header, value) pairs, with a leading
  # "From_" line swallowed into USELESS_LEADING_ENTRY. Junk the leading
  # entry. Chomp all values.
  %$hash_ref = (USELESS_LEADING_ENTRY => split /^(\S*?):\s*/m, $envelope);
  delete($hash_ref->{USELESS_LEADING_ENTRY});
  for (keys %$hash_ref) {
    chomp $hash_ref->{$_};
  }

  # Keep the original_attachment intact.
  $$hash_ref{'original_attachment'} = $att;

  if (!$$hash_ref{'Content-Type'}
      || !$$hash_ref{'Content-Disposition'})
  {
    die "Unable to parse file attachment";
  }

  # Parse filename.
  # Note: the extra \ before the " is just so that perl-mode can parse it.
  if ($$hash_ref{'Content-Disposition'} !~ /(\S+); filename=\"([^\"]+)\"/) {
    die "Unable to parse file attachment Content-Disposition";
  }
  $$hash_ref{'filename'} = attachment_filename_tail($2);

  # Decode the data if encoded.
  if (exists($$hash_ref{'Content-Transfer-Encoding'})
      && $$hash_ref{'Content-Transfer-Encoding'} eq 'base64')
  {
    $$hash_ref{'data'} = MIME::Base64::decode_base64($body);
  }
  else {
    $$hash_ref{'data'} = $body;
  }

  return $hash_ref;
}

# Print file attachment browser and buttons to download the attachments.
# Which of these appear depend on the mode.
sub print_attachments
{
  my($fields_hash_ref, $mode) = @_;

  return unless can_do_mime();

  print "<tr><td valign=top><b>File Attachments:</b></td>\n<td>";

  # Add file upload button for adding new attachment.
  if ($mode eq 'sendpr' || $mode eq 'edit') {
    print "Add a file attachment:<br>",
          $q->filefield(-name=>'attached_file',
                        -size=>50);
  }

  # Print table of existing attachments.
  # Add column with delete button in edit mode.
  my $array_ref = $$fields_hash_ref{'attachments'};
  my $table_rows_aref = [];
  my $i = 0;
  foreach $hash_ref (@$array_ref) {
    my $size = int(length($$hash_ref{'data'}) / 1024.0);
    $size = 1 if ($size < 1);
    my $row_data = $q->td( [ $q->submit('cmd', "download attachment $i"),
                             $$hash_ref{'filename'},
                             "${size}k" ] );
    $row_data .= $q->td($q->checkbox(-name=>'delete attachments',
                                     -value=>$i,
                                     -label=>"delete attachment $i"))
          if ($mode eq 'edit');
    push(@$table_rows_aref, $row_data);
    $i++;
  }
  if (@$table_rows_aref)
  {
    my $header_row_data = $q->th( ['download','filename','size' ] );
    $header_row_data .= $q->th('delete')
          if ($mode eq 'edit');
    print $q->table({-border=>1},
                    $q->Tr($header_row_data),
                    $q->Tr($table_rows_aref));
  }
}

# The user has requested download of a particular attachment.
# Serve it up.
sub download_attachment
{
  my $attachment_number = shift;
  my($pr) = $q->param('pr');
  die "download_attachment called with no PR number"
        if(!$pr);

  my(%fields) = readpr($pr);
  my $array_ref = $fields{'attachments'};
  my $hash_ref = $$array_ref[$attachment_number];
  my $disp;

  # Internet Explorer 5.5 does not handle "content-disposition: attachment"
  # in the expected way. It needs a content-disposition of "file".
  ($ENV{'HTTP_USER_AGENT'} =~ "MSIE 5.5") ? ($disp = 'file') : ($disp = 'attachment');
  # Now serve the attachment, with the appropriate headers.
  print $q->header(-type => 'application/octet-stream',
                   -content_disposition => "$disp; filename=\"$$hash_ref{'filename'}\""),
  $$hash_ref{'data'};
}

# Add the given (gnatsweb-encoded) attachment to the %fields hash.
sub add_encoded_attachment_to_pr
{
  my($fields_hash_ref, $encoded_attachment) = @_;
  return unless $encoded_attachment;
  my $ary_ref = $$fields_hash_ref{'attachments'} || [];
  my $hash_ref = { 'original_attachment' => $encoded_attachment };
  push(@$ary_ref, $hash_ref);
  $$fields_hash_ref{'attachments'} = $ary_ref;
}

# Add the given (gnatsweb-decoded) attachment to the %fields hash.
sub add_decoded_attachment_to_pr
{
  my($fields_hash_ref, $decoded_attachment_hash_ref) = @_;
  return unless $decoded_attachment_hash_ref;
  my $ary_ref = $$fields_hash_ref{'attachments'} || [];
  push(@$ary_ref, $decoded_attachment_hash_ref);
  $$fields_hash_ref{'attachments'} = $ary_ref;
}

# Remove the given attachments from the %fields hash.
sub remove_attachments_from_pr
{
  my($fields_hash_ref, @attachment_numbers) = @_;
  return unless @attachment_numbers;
  my $ary_ref = $$fields_hash_ref{'attachments'} || [];
  foreach my $attachment_number (@attachment_numbers)
  {
    # Remove the attachment be replacing it with the empty hash.
    # The sub unparsepr skips these.
    $$ary_ref[$attachment_number] = {};
  }
}

# sendpr -
#     The Create PR page.
#
sub sendpr
{
  my $page = 'Create PR';
  print_header();
  page_start_html($page);
  page_heading($page, 'Create Problem Report', 1);

  # remove "all" from arrays
  shift(@category);
  shift(@severity);
  shift(@priority);
  shift(@class);
  shift(@confidential);
  shift(@responsible);
  shift(@state);
  shift(@submitter_id);

  # Add '<default>' to @responsible, in case the site_callback alows
  # Responsible to be set upon submission.  This is filtered out in
  # &submitnewpr.
  unshift(@responsible, '<default>');

  print $q->start_multipart_form(),
        hidden_db(),
	$q->p($q->submit('cmd', 'submit'),
	" or ",
	$q->reset(-name=>'reset')),
	"<hr>\n",
	"<table>";
  my $def_email = $global_prefs{'email'}
        || cb('get_default_value', 'email') || '';
  print "<tr>\n<td><b>Reporter's email:</b></td>\n<td>",
        $q->textfield(-name=>'email',
                      -default=>$def_email,
                      -size=>$textwidth),
	"</td>\n</tr>\n<tr>\n<td><b>CC these people<br>on PR status email:</b></td>\n<td>",
	$q->textfield(-name=>'X-GNATS-Notify',
		      -size=>$textwidth),
        # a blank row, to separate header info from PR info
        "</td>\n</tr>\n<tr>\n<td>&nbsp;</td>\n<td>&nbsp;</td>\n</tr>\n";

  foreach (@fieldnames)
  {
    next if ($fieldnames{$_} & $SENDEXCLUDE);
    my $lc_fieldname = field2param($_);

    # Get default value from site_callback if provided, otherwise take
    # our defaults.
    my $default;
    $default = 'serious'                   if /Severity/;
    $default = 'medium'                    if /Priority/;
    $default = $global_prefs{'Submitter-Id'} || 'unknown' if /Submitter-Id/;
    $default = $global_prefs{'Originator'} if /Originator/;
    $default = grep(/^unknown$/i, @category) ? "unknown" : $category[0]
                                           if /Category/;
    $default = $config{'DEFAULT_RELEASE'}  if /Release/;
    $default = ''                          if /Responsible/;
    $default = cb("sendpr_$lc_fieldname") || $default;

    # The "intro" provides a way for the site callback to print something
    # at the top of a given field.
    my $intro = cb("sendpr_intro_$lc_fieldname") || '';

    if ($fieldnames{$_} & $ENUM)
    {
      print "<tr>\n<td><b>$_:</b>\n</td>\n<td>",
            $intro,
            $q->popup_menu(-name=>$_,
                           -values=>\@$lc_fieldname,
                           -default=>$default);
      print "</td>\n</tr>\n";
    }
    elsif ($fieldnames{$_} & $MULTILINE)
    {
      my $rows = 4;
      $rows = 8 if /Description/;
      $rows = 2 if /Environment/;
      print "<tr>\n<td valign=top><b>$_:</b></td>\n<td>",
            $intro,
            $q->textarea(-name=>$_,
                         -cols=>$textwidth,
                         -rows=>$rows,
                         -default=>$default);
      # Create file upload button after Description.
      print_attachments(\%fields, 'sendpr') if /Description/;
      print "</td>\n</tr>\n";
    }
    else
    {
      print "<tr>\n<td><b>$_:</b></td>\n<td>",
            $intro,
            $q->textfield(-name=>$_,
                          -size=>$textwidth,
                          -default=>$default);
      print "</td>\n</tr>\n";
    }
    print "\n";
  }
  print "</table>",
	$q->p($q->submit('cmd', 'submit'),
	" or ",
	$q->reset(-name=>'reset')),
	$q->end_form();

  page_footer($page);
  page_end_html($page);
}

# validate_email_field -
#     Used by validate_new_pr to check email address fields in a new PR.
sub validate_email_field
{
  my($fieldname, $fieldval, $required) = @_;

  my $blank = ($fieldval =~ /^\s*$/);
  if ($required && $blank)
  {
    return "$fieldname is blank";
  }
  # From rkimball@vgi.com, allows @ only if it's followed by what looks
  # more or less like a domain name.
  my $email_addr = '[^@\s]+(@\S+\.\S+)?';
  if (!$blank && $fieldval !~ /^\s*($email_addr\s*)+$/)
  {
    return "'$fieldval' doesn't look like a valid email address (xxx\@xxx.xxx)";
  }
  return '';
}

# validate_new_pr -
#     Make sure fields have reasonable values before submitting a new PR.
sub validate_new_pr
{
  my(%fields) = @_;
  my(@errors) = ();
  my $err;

  # validate email fields
  $err = validate_email_field('E-mail Address', $fields{'email'}, 'required');
  push(@errors, $err) if $err;
#  $err = validate_email_field('CC', $fields{'cc'});
#  push(@errors, $err) if $err;
  $err = validate_email_field('X-GNATS-Notify', $fields{'X-GNATS-Notify'});
  push(@errors, $err) if $err;

  # validate some other fields
  push(@errors, "Category is blank or 'unknown'")
        if($fields{'Category'} =~ /^\s*$/ || $fields{'Category'} eq "unknown");
  push(@errors, "Synopsis is blank")
        if($fields{'Synopsis'} =~ /^\s*$/);
  push(@errors, "Release is blank")
        if($fields{'Release'} =~ /^\s*$/);
  push(@errors, "Submitter-Id is 'unknown'")
        if($fields{'Submitter-Id'} eq 'unknown');

  @errors;
}

sub submitnewpr
{
  my $page = 'Create PR Results';
  page_start_html($page);

  my $debug = 0;
  my(@values, $key);
  my(%fields);

  foreach $key ($q->param)
  {
    my $val = $q->param($key);
    if($fieldnames{$key} && ($fieldnames{$key} & $MULTILINE))
    {
      $val = fix_multiline_val($val);
    }
    $fields{$key} = $val;
  }

  # If Responsible is '<default>', delete it; gnats handles that.  See
  # also &sendpr.
  if($fields{'Responsible'} eq '<default>') {
    delete $fields{'Responsible'};
  }

  # Make sure the pr is valid.
  my(@errors) = validate_new_pr(%fields);
  if (@errors)
  {
    page_heading($page, 'Error');
    print "<h3>Your problem report has not been sent.</h3>\n",
          "<p>Fix the following problems, then submit the problem report again:</p>",
          $q->ul($q->li(\@errors));
    return;
  }

  # Supply a default value for Originator
  $fields{'Originator'} = $fields{'Originator'} || $fields{'email'};

  # Handle the attached_file, if any.
  add_encoded_attachment_to_pr(\%fields, encode_attachment('attached_file'));

  # Compose the message
  my $text = unparsepr('send', %fields);
  $text = <<EOT . $text;
To: $config{'GNATS_ADDR'}
CC: $fields{'X-GNATS-Notify'}
Subject: $fields{'Synopsis'}
From: $fields{'email'}
Reply-To: $fields{'email'}
X-Send-Pr-Version: gnatsweb-$VERSION ($REVISION)
X-GNATS-Notify: $fields{'X-GNATS-Notify'}

EOT

  # Allow debugging
  if($debug)
  {
    print "<h3>debugging -- PR NOT SENT</h3>",
          $q->pre($q->escapeHTML($text)),
          "<hr>";
    page_end_html($page);
    return;
  }

  # Send the message
  if(!open(MAIL, "|$site_mailer"))
  {
    page_heading($page, 'Error');
    print "<h3>Error invoking $site_mailer</h3>";
    return;
  }
  print MAIL $text;
  if(!close(MAIL))
  {
    page_heading($page, 'Error');
    print "<h3>Bad pipe to $site_mailer</h3>";
    exit;
  }

  # Give feedback for success
  page_heading($page, 'Problem Report Sent');
  print "<p>Thank you for your report.  It will take a short while for
your report to be processed.  When it is, you will receive
an automated message about it, containing the Problem Report
number, and the developer who has been assigned to
investigate the problem.</p>";

  page_footer($page);
  page_end_html($page);
}

# Return a URL which will take one to the specified $pr and with a
# specified $cmd.  For ease of use, when the user makes a successful edit,
# we want to return to the URL he was looking at before he decided to edit
# the PR.  The return_url param serves to store that info, and is included
# if $include_return_url is specified.  Note that the return_url is saved
# even when going into the view page, since the user might go from there
# to the edit page.
#
sub get_pr_url
{
  my($cmd, $pr, $include_return_url) = @_;
  my $url = $q->url() . "?cmd=$cmd&pr=$pr&database=$global_prefs{'database'}";
  $url .= "&return_url=" . $q->escape($q->self_url())
        if $include_return_url;
  return $url;
}

# Return a URL to edit the given pr.  See get_pr_url().
#
sub get_editpr_url
{
  return get_pr_url('edit', @_);
}

# Return a URL to view the given pr.  See get_pr_url().
#
sub get_viewpr_url
{
  return get_pr_url('view', @_);
}

# Same as script_name(), but includes 'database=xxx' param.
#
sub get_script_name
{
  my $url = $q->script_name();
  $url .= "?database=$global_prefs{'database'}"
        if defined($global_prefs{'database'});
  return $url;
}

# Return a link which sends email regarding the current PR.
sub get_mailto_link
{
  my($pr,%fields) = @_;
  my $mailto  = $q->escape(scalar(interested_parties($pr, 1, %fields)));
  my $subject = $q->escape("Re: $fields{'Category'}/$pr");
  my $body    = $q->escape(get_viewpr_url($pr));

  # MSIE users fork Outlook and Outlook Express,
  # they need semicolons and the &'s used to view-pr need more quoting
  if ($ENV{'HTTP_USER_AGENT'} =~ /MSIE/)
  {
    my $ecomma     = $q->escape(",");
    my $esemicolon = $q->escape(";");
    my $ampsand    = $q->escape("&");
    $mailto =~ s/$ecomma/$esemicolon/g ;
    $body =~ s/$ampsand/%2526/g ;
  }

  return "<a href=\"mailto:$mailto?Subject=$subject&Body=$body\">"
        . "send email to interested parties</a>\n";
}

# Look for text that looks like URLs and turn it into actual links.
sub mark_urls
{
  my ($val) = @_;
  # This probably doesn't catch all URLs, but one hopes it catches the
  # majority.
  $val =~ s/\b((s?https?|ftp):\/\/[-a-zA-Z0-9_.]+(:[0-9]+)?[-a-zA-Z0-9_\$.+\!*\(\),;:\@\&\%\x93\x90=?~\#\/]*)/
        \<a href="$1">$1\<\/a\>/g;
  return $val;
}

sub view
{
  my($viewaudit, $tmp) = @_;
  # $pr must be 'local' to be available to site callback
  local($pr) = $q->param('pr');
  if(!$pr)
  {
    error_page('Error', 'You must specify a problem report number');
    return;
  }
  if($pr =~ /\D/)
  {
    error_page('Error', 'Invalid PR number');
    return;
  }
  my $page = "View PR $pr";
  print_header();
  page_start_html($page);
  page_heading($page, "View Problem Report: $pr", 1);

  # %fields must be 'local' to be available to site callback
  local(%fields) = readpr($pr);

  print $q->start_form(),
        hidden_db(),
	$q->hidden('pr'),
        $q->hidden('return_url');

  # print 'edit' and 'view audit-trail' buttons as appropriate, mailto link
  print "<p>";
  print $q->submit('cmd', 'edit')             if (can_edit());
  print " or "                                if (can_edit() && !$viewaudit);
  print $q->submit('cmd', 'view audit-trail') if (!$viewaudit);
  print " or ",
        get_mailto_link($pr, %fields), "</p>";
  print $q->hr(),
        "<table>\n";
  print "<tr>\n<td><b>Reporter's email:</b></td>\n<td>",
        $q->tt($fields{'Reply-To'}),
#	"<tr><td><b>Others to notify<br>of updates to this PR:</b><td>",
	"</td>\n</tr>\n<tr>\n<td><b>CC these people<br>on PR status email:</b></td>\n<td>",
	$q->tt($fields{'X-GNATS-Notify'}),
        # a blank row, to separate header info from PR info
        "</td>\n</tr>\n<tr>\n<td>&nbsp;</td>\n<td>&nbsp;</td>\n</tr>\n";

  foreach (@fieldnames)
  {
    next if $_ eq 'Audit-Trail';
    my $val = $q->escapeHTML($fields{$_}) || ''; # to avoid -w warning
    my $valign = '';
    if ($fieldnames{$_} & $MULTILINE)
    {
      $valign = 'valign=top';
      $val =~ s/$/<br>/gm;
      $val =~ s/<br>$//; # previous substitution added one too many <br>'s
      $val = mark_urls($val);
    }
    print "<tr><td $valign nowrap><b>$_:</b></td>\n<td>",
          $q->tt($val), "\n";
    # Print attachments after Description.
    if (/Description/) {
      print "</td>\n</tr>\n";
      print_attachments(\%fields, 'view');
    }
    print "</td>\n</tr>\n"
  }
  print "</table>",
        $q->hr();

  # print 'edit' and 'view audit-trail' buttons as appropriate, mailto link
  print "\n<p>";
  print $q->submit('cmd', 'edit')             if (can_edit());
  print " or "                                if (can_edit() && !$viewaudit);
  print $q->submit('cmd', 'view audit-trail') if (!$viewaudit);
  print " or ",
        get_mailto_link($pr, %fields);
  print "</p>\n";
  print $q->end_form();

  # Footer comes before the audit-trail.
  page_footer($page);

  if($viewaudit)
  {
    print "<h3>Audit Trail:</h3>\n",
          mark_urls($q->pre($q->escapeHTML($fields{'Audit-Trail'})));
  }

  page_end_html($page);
}

# edit -
#     The Edit PR page.
#
sub edit
{
  #my $debug = 0; # no debug code in here
  my($pr) = $q->param('pr');
  if(!$pr)
  {
    error_page('Error', 'You must specify a problem report number');
    return;
  }

  if($pr =~ /\D/)
  {
    error_page('Error', 'Invalid PR number');
    return;
  }

  my $page = "Edit PR $pr";
  print_header();
  page_start_html($page);
  page_heading($page, "Edit Problem Report: $pr", 1);

  # Read the PR.
  my(%fields) = readpr($pr);

  # Trim Responsible for compatibility.
  $fields{'Responsible'} = trim_responsible($fields{'Responsible'});

  # remove "all" from arrays
  shift(@category);
  shift(@severity);
  shift(@priority);
  shift(@class);
  shift(@confidential);
  shift(@responsible);
  shift(@state);
  shift(@submitter_id);

  print $q->start_multipart_form(),
        hidden_db(),
        $q->p($q->submit('cmd', 'submit edit'),
        " or ",
        $q->reset(-name=>'reset'),
        " or ",
        get_mailto_link($pr, %fields)),
	$q->hidden(-name=>'Editor',
                   -value=>$db_prefs{'user'},
                   -override=>1),
	$q->hidden(-name=>'Last-Modified',
		   -value=>$fields{'Last-Modified'},
		   -override=>1),
        #$q->hidden(-name=>'pr', -value=>$pr, -override=>1),
        #$q->hidden(-name=>'return_url'),
	$q->hidden(-name=>'pr'),
        $q->hidden(-name=>'return_url'),
        "<hr>\n";

  print "<table>\n";
  print "<tr>\n<td><b>Reporter's email:</b></td>\n<td>",
        $q->textfield(-name=>'Reply-To',
                      -default=>$fields{'Reply-To'},
                      -size=>$textwidth),
#	"<tr><td><b>Others to notify<br>of updates to this PR:</b><td>",
	"</td>\n</tr>\n<tr>\n<td><b>CC these people<br>on PR status email:</b></td>\n<td>",
	$q->textfield(-name=>'X-GNATS-Notify',
                      -default=>$fields{'X-GNATS-Notify'},
		      -size=>$textwidth),
        # a blank row, to separate header info from PR info
        "</td>\n</tr>\n<tr>\n<td>&nbsp;</td>\n<td>&nbsp;</td>\n</tr>\n";

  foreach (@fieldnames)
  {
    next if ($fieldnames{$_} && ($fieldnames{$_} & $EDITEXCLUDE));
    my $lc_fieldname = field2param($_);

    # The "intro" provides a way for the site callback to print something
    # at the top of a given field.
    my $intro = cb("edit_intro_$lc_fieldname") || '';

    if ($fieldnames{$_} && ($fieldnames{$_} & $ENUM))
    {
      my @values = cb('edit_pr', $fields{'Category'}, $lc_fieldname);
      @values = @$lc_fieldname unless (defined($values[0]));
      print "<tr>\n<td><b>$_:</b></td>\n<td>",
            $intro,
            $q->popup_menu(-name=>$_,
                           -values=>\@values,
                           -default=>$fields{$_});
      print "</td>\n</tr>\n";
    }
    elsif ($fieldnames{$_} && ($fieldnames{$_} & $MULTILINE))
    {
      my $rows = 4;
      $rows = 8 if /Description/;
      $rows = 2 if /Environment/;
      print "<tr>\n<td valign=top><b>$_:</b></td>\n<td>",
            $intro,
            $q->textarea(-name=>$_,
                         -cols=>$textwidth,
                         -rows=>$rows,
                         -default=>$fields{$_});
      # Print attachments after Description.
      if (/Description/) {
        print "</td>\n</tr>\n";
        print_attachments(\%fields, 'edit');
      }
      print "</td>\n</tr>\n";
    }
    else
    {
      print "<tr>\n<td><b>$_:</b></td>\n<td>",
            $intro,
            $q->textfield(-name=>$_,
                          -size=>$textwidth,
                          -default=>$fields{$_});
      print "</td>\n</tr>\n";
    }
    if ($fieldnames{$_} && $fieldnames{$_} & $REASONCHANGE)
    {
      print "<tr>\n<td valign=top><b>Reason Changed:</b></td>\n<td>",
            $q->textarea(-name=>"$_-Why",
			 -default=>'',
			 -override=>1,
			 -cols=>$textwidth,
			 -rows=>2);
      print "</td>\n</tr>\n";
    }
    print "\n";
  }
  print	"</table>",
	$q->p($q->submit('cmd', 'submit edit'),
	" or ",
	$q->reset(-name=>'reset'),
        " or ",
        get_mailto_link($pr, %fields)),
	$q->end_form(),
	$q->hr();

  # Footer comes before the audit-trail.
  page_footer($page);

  print "<h3>Audit-Trail:</h3>\n",
        mark_urls($q->pre($q->escapeHTML($fields{'Audit-Trail'})));
  page_end_html($page);
}

# Print out the %fields hash for debugging.
sub debug_print_fields
{
  my $fields_hash_ref = shift;
  print "<table cellspacing=0 cellpadding=0 border=1>\n";
  foreach my $f (sort keys %$fields_hash_ref)
  {
    print "<tr valign=top><td>$f</td><td>",
          $q->pre($q->escapeHTML($$fields_hash_ref{$f})),
          "</td></tr>\n";
  }
  my $aref = $$fields_hash_ref{'attachments'} || [];
  my $i=0;
  foreach my $href (@$aref) {
    print "<tr valign=top><td>attachment $i</td><td>",
          ($$href{'original_attachment'}
           ?  $$href{'original_attachment'} : "--- empty ---"),
          "</td></tr>\n";
    $i++;
  }
  print "</table><hr>\n";
}

# submitedit -
#     User pressed 'submit' on the edit page.  If the edits are applied
#     successfully, give a message then return the user to the URL
#     specified in param('return_url') so that he can continue doing what
#     he was previously doing (e.g. looking at query results).  If the
#     edits are not successful, print and error and stay put.
#     
sub submitedit
{
  local($page) = 'Edit PR Results'; # local so visible to &$err_sub
  my $debug = 0;

  # Local sub to report errors while editing.
  # This allows us to postpone calling print_header().
  my $err_sub = sub {
    my($err_heading, $err_text) = @_;
    print_header();
    page_start_html($page);
    page_heading($page, 'Error');
    print "<h3>$err_heading</h3>";
    print "<p>$err_text</p>" if $err_text;
    page_footer($page);
    page_end_html($page);
    return;
  };

  my($pr) = $q->param('pr');
  if(!$pr)
  {
    &$err_sub("You must specify a problem report number");
    return;
  }

  my(%fields, %mailto, $adr);
  my $audittrail = '';
  my $err = '';
  my $ok = 1;

  # Retrieve new attachment (if any) before locking PR, in case it fails.
  my $encoded_attachment = encode_attachment('attached_file');

  my(%oldfields) = lockpr($pr, $db_prefs{'user'});

  if ($gnats::ERRSTR) {
    &$err_sub("$gnats::ERRSTR", "The PR has not been changed. "
              . "If this problem persists, please contact a "
              . "Gnats administrator.");
    client_exit();
    exit();
  }

  LOCKED:
  {
    # Trim Responsible for compatibility.
    $oldfields{'Responsible'} = trim_responsible($oldfields{'Responsible'});

    # Merge %oldfields and CGI params to get %fields.  Not all gnats
    # fields have to be present in the CGI params; the ones which are
    # not specified default to their old values.
    %fields = %oldfields;
    foreach my $key ($q->param)
    {
      my $val = $q->param($key);
      if($key =~ /-Why/
         || ($fieldnames{$key} && ($fieldnames{$key} & $MULTILINE)))
      {
	$val = fix_multiline_val($val);
      }
      $fields{$key} = $val;
    }

    # Add the attached file, if any, to the new PR.
    add_encoded_attachment_to_pr(\%fields, $encoded_attachment);

    # Delete any attachments, if directed.
    my(@deleted_attachments) = $q->param('delete attachments');
    remove_attachments_from_pr(\%fields, @deleted_attachments);

    if($fields{'Last-Modified'} ne $oldfields{'Last-Modified'})
    {
      &$err_sub("PR $pr has been modified since you started editing it.",
                "Please return to the edit form, press the Reload button, "
                . "then make your edits again.\n"
                . "<pre>Last-Modified was    '$fields{'Last-Modified'}'\n"
                . "Last-Modified is now '$oldfields{'Last-Modified'}'</pre>\n");
      last LOCKED;
    }

    if($db_prefs{'user'} eq "" || $fields{'Responsible'} eq "")
    {
      &$err_sub("Can't make the edit",
                "Responsible is '$fields{'Responsible'}', user is '$db_prefs{'user'}'");
      last LOCKED;
    }

    # If X-GNATS-Notify or Reply-To changed, we need to splice the
    # change into the envelope.
    foreach ('Reply-To', 'X-GNATS-Notify')
    {
      if($fields{$_} ne $oldfields{$_})
      {
        if ($fields{'envelope'} =~ /^$_:/m)
        {
          # Replace existing header with new one.
          $fields{'envelope'} =~ s/^$_:.*$/$_: $fields{$_}/m;
        }
        else
        {
          # Insert new header at end (blank line).  Keep blank line at end.
          $fields{'envelope'} =~ s/^$/$_: $fields{$_}\n/m;
        }
      }
    }

    if ($debug)
    {
      &$err_sub("debugging -- PR edits not submitted");
      debug_print_fields(\%fields);
      last LOCKED;
    }

    # Leave an Audit-Trail
    foreach (@fieldnames)
    {
      if($_ ne "Audit-Trail")
      {
        $oldfields{$_} = '' if !defined($oldfields{$_}); # avoid -w warning
        $fields{$_} = '' if !defined($fields{$_}); # avoid -w warning
	if($fields{$_} ne $oldfields{$_})
	{
          next unless ($fieldnames{$_} & $AUDITINCLUDE);
	  if($fieldnames{$_} & $MULTILINE)
	  {
            # For multitext fields, indent the values.
            my $tmp = $oldfields{$_};
            $tmp =~ s/^/    /gm;
	    $audittrail .= "$_-Changed-From:\n$tmp";
            $tmp = $fields{$_};
            $tmp =~ s/^/    /gm;
	    $audittrail .= "$_-Changed-To:\n$tmp";
	  }
          else
          {
            $audittrail .= "$_-Changed-From-To: $oldfields{$_}->$fields{$_}\n";
	  }
	  $audittrail .= "$_-Changed-By: $db_prefs{'user'}\n";
	  $audittrail .= "$_-Changed-When: " . scalar(localtime()) . "\n";
	  if($fieldnames{$_} & $REASONCHANGE)
	  {
	    if($fields{"$_-Why"} =~ /^\s*$/)
	    {
              if ($ok) {
                $ok = 0;
                print_header();
                page_start_html($page);
                page_heading($page, 'Error');
              }
	      print "<h3>Field '$_' must have a reason for change</h3>",
                    "Old $_: $oldfields{$_}<br>",
                    "New $_: $fields{$_}";
	    }
            else
            {
              # Indent the "Why" value.
              my $tmp = $fields{"$_-Why"};
              $tmp =~ s/^/    /gm;
              $audittrail .= "$_-Changed-Why:\n" . $tmp;
            }
	  }
	}
      }
    }
    $fields{'Audit-Trail'} = $oldfields{'Audit-Trail'} . $audittrail;

    last LOCKED unless $ok;

    my $mail_sent = 0;

    # Get list of people to notify, then add old responsible person.
    # If that person doesn't exist, don't worry about it.
    %mailto = interested_parties($pr, 0, %fields);
    if(defined($adr = praddr($oldfields{'Responsible'})))
    {
      $mailto{$adr} = 1;
    }

    my($newpr) = unparsepr('gnatsd', %fields);
    $newpr =~ s/\r//g;
    #print $q->pre($q->escapeHTML($newpr));
    #last LOCKED; # debug

    # Submit the edits.
    client_cmd("edit $fields{'Number'}");
    client_cmd("$newpr\n.");

    if ($gnats::ERRSTR) {
      print_gnatsd_error($gnats::ERRSTR);
      client_exit();
      exit();
    }

    # Now send mail to all concerned parties,
    # but only if there's something interesting to say.
    my($mailto);
    delete $mailto{''};
    $mailto = join(", ", sort(keys(%mailto)));
    #print $q->pre($q->escapeHTML("mailto->$mailto<-\n"));
    #last LOCKED; # debug
    if($mailto ne "" && $audittrail ne "")
    {
      # Use email address in responsible file as From, if present.
      my $from = $responsible_address{$db_prefs{'user'}} || $db_prefs{'user'};
      if(!open(MAILER, "|$site_mailer"))
      {
        &$err_sub("Edit successful, but email notification failed",
                  "Can't open pipe to $site_mailer: $!");
        last LOCKED;
      }
      else
      {
        print MAILER "To: $mailto\n";
        print MAILER "From: $from\n";
        print MAILER "Subject: Re: $fields{'Category'}/$pr\n\n";
        if ($oldfields{'Synopsis'} eq $fields{'Synopsis'})
        {
          print MAILER "Synopsis: $fields{'Synopsis'}\n\n";
        }
        else
        {
          print MAILER "Old Synopsis: $oldfields{'Synopsis'}\n";
          print MAILER "New Synopsis: $fields{'Synopsis'}\n\n";
        }
        print MAILER "$audittrail\n";
        # Print URL so that HTML-enabled mail readers can jump to the PR.
        print MAILER get_viewpr_url($pr), "\n";
        if(!close(MAILER))
        {
          &$err_sub("Edit successful, but email notification failed",
                    "Can't close pipe to $site_mailer: $!");
          last LOCKED;
        }
        $mail_sent = 1;
      }
    }
    $lock_end_reached = 1;
  }
  unlockpr($fields{'Number'});

  if ($lock_end_reached) {
    # We print out the "Edit successful" message after unlocking the PR. If the user hits
    # the Stop button of the browser while submitting, the web server won't terminate the
    # script until the next time the server attempts to output something to the browser.
    # Since this is the first output after the PR was locked, we print it after the unlocking.
    # Let user know the edit was successful. After a 2s delay, refresh back
    # to where the user was before the edit. Internet Explorer does not honor the
    # HTTP Refresh header, so we have to complement the "clean" CGI.pm method
    # with the ugly hack below, with a HTTP-EQUIV in the HEAD to make things work.
    my $return_url = $q->param('return_url') || get_script_name();
    my $refresh = 2;
    print_header(-Refresh => "$refresh; URL=$return_url");
    print "<HTML><HEAD><TITLE>$page</TITLE>"
          , "<META HTTP-EQUIV=\"Refresh\" CONTENT=\"$refresh; URL=$return_url\"></HEAD>";
    print "\n<BODY>\n";
    page_start_html($page);
    page_heading($page, ($mail_sent ? 'Edit successful; mail sent'
                         : 'Edit successful'));
    print "<p>Page will refresh in $refresh seconds...</p>\n";
  }

  page_footer($page);
  page_end_html($page);
}

sub query_page
{
  my $page = 'Query PR';
  page_start_html($page);
  page_heading($page, 'Query Problem Reports', 1);
  print_stored_queries();
  print $q->start_form(),
        hidden_db(),
	$q->submit('cmd', 'submit query'),
        "<hr>",
	"<table>\n",
	"<tr>\n<td>Category:</td>\n<td>",
	$q->popup_menu(-name=>'category',
		       -values=>\@category,
		       -default=>$category[0]),
	"</td>\n</tr>\n<tr>\n<td>Severity:</td>\n<td>",
	$q->popup_menu(-name=>'severity',
	               -values=>\@severity,
		       -default=>$severity[0]),
	"</td>\n</tr>\n<tr>\n<td>Priority:</td>\n<td>",
	$q->popup_menu(-name=>'priority',
	               -values=>\@priority,
		       -default=>$priority[0]),
	"</td>\n</tr>\n<tr>\n<td>Responsible:</td>\n<td>",
	$q->popup_menu(-name=>'responsible',
		       -values=>\@responsible,
		       -default=>$responsible[0]),
	"</td>\n</tr>\n<tr>\n<td>State:</td>\n<td>",
	$q->popup_menu(-name=>'state',
		       -values=>\@state,
		       -default=>$state[0]),
	"</td>\n</tr>\n<tr>\n<td>\n</td>\n<td>",
	$q->checkbox_group(-name=>'ignoreclosed',
	               -values=>['Ignore Closed'],
		       -defaults=>['Ignore Closed']),
	"</td>\n</tr>\n<tr>\n<td>Class:</td>\n<td>",
	$q->popup_menu(-name=>'class',
		       -values=>\@class,
		       -default=>$class[0]),
	"</td>\n</tr>\n<tr>\n<td>Synopsis Search:</td>\n<td>",
	$q->textfield(-name=>'synopsis',-size=>25),
	"</td>\n</tr>\n<tr>\n<td>Multi-line Text Search:</td>\n<td>",
	$q->textfield(-name=>'multitext',-size=>25),
	"</td>\n</tr>\n<tr>\n<td>\</td>\n<td>",
	$q->checkbox_group(-name=>'originatedbyme',
	               -values=>['Originated by You'],
		       -defaults=>[]),
	"</td>\n</tr>\n<tr valign=top>\n<td>Column Display:</td>\n<td>";
  my(@columns) = split(' ', $global_prefs{'columns'});
  @columns = @deffields unless @columns;
  print $q->scrolling_list(-name=>'columns',
                           -values=>\@fields,
                           -defaults=>\@columns,
                           -multiple=>1,
                           -size=>5),
	"</td>\n</tr>\n</table>",
        "<hr>",
	$q->submit('cmd', 'submit query'),
        $q->end_form();

  page_footer($page);
  page_end_html($page);
}

sub advanced_query_page
{
  my $page = 'Advanced Query';
  page_start_html($page);
  page_heading($page, 'Query Problem Reports', 1);
  print_stored_queries();
  print $q->start_form(),
        hidden_db();

  my $width = 30;
  my $heading_bg = '#9fbdf9';
  my $cell_bg = '#d0d0d0';

  print $q->p($q->submit('cmd', 'submit query'),
	" or ",
	$q->reset(-name=>'reset'));
  print "<hr>";
  print "<center>";

  ### Text and multitext queries

  print "<table border=1 bgcolor=$cell_bg>",
        "<caption>Search All Text</caption>",
        "<tr bgcolor=$heading_bg>\n",
        "<th nowrap>Search these text fields</th>\n",
        "<th nowrap>using regular expression</th>\n",
        "</tr>\n";
  print "<tr>\n<td>Single-line text fields:</td>\n<td>",
        $q->textfield(-name=>'text', -size=>$width),
        "</td>\n</tr>\n",
        "<tr>\n<td>Multi-line text fields:</td>\n<td>",
        $q->textfield(-name=>'multitext', -size=>$width),
        "</td>\n</tr>\n",
        "</table>\n";

  print "<div>&nbsp;</div>\n";

  ### Date queries

  print "<table border=1 bgcolor=$cell_bg>",
        "<caption>Search By Date</caption>",
        "<tr bgcolor=$heading_bg>\n",
        "<th nowrap>Date Search</th>\n",
        "<th nowrap>Example: <tt>1999-04-01 05:00 GMT</tt></th>\n",
        "</tr>\n";
  my(@date_queries) =  ('Arrived After', 'Arrived Before',
                        'Modified After', 'Modified Before',
                        'Closed After', 'Closed Before');
  push(@date_queries, 'Required After', 'Required Before')
        if $site_release_based;
  foreach (@date_queries)
  {
    my $param_name = lc($_);
    $param_name =~ s/ //;
    print "<tr>\n<td>$_:</td>\n<td>",
          $q->textfield(-name=>$param_name, -size=>$width),
          "</td>\n</tr>\n";
  }
  print $q->Tr( $q->td({-colspan=>2},
        $q->small( $q->b("NOTE:"), "If your search includes 'Closed After'
                   or 'Closed Before', uncheck 'Ignore Closed' below.")));
  print "</table>\n";

  print "<div>&nbsp;</div>\n";

  ### Field queries

  print "<table border=1 bgcolor=$cell_bg>",
        "<caption>Search Individual Fields</caption>",
        "<tr bgcolor=$heading_bg>\n",
        "<th nowrap>Search this field</th>\n",
        "<th nowrap>using regular expression, or</th>\n",
        "<th nowrap>using multi-selection</th>\n",
        "</tr>\n";
  foreach (@fieldnames)
  {
    my $lc_fieldname = field2param($_);
    next unless ($gnatsd_query{$lc_fieldname});

    print "<tr valign=top>\n";

    # 1st column is field name
    print "<td>$_:</td>\n";

    # 2nd column is regexp search field
    print "<td>",
          $q->textfield(-name=>$lc_fieldname,
                        -size=>$width);
    if ($_ eq 'State')
    {
      print "<br>",
            $q->checkbox_group(-name=>'ignoreclosed',
                               -values=>['Ignore Closed'],
                               -defaults=>['Ignore Closed']),
    }
    print "</td>\n";
    # 3rd column is blank or scrolling multi-select list
    print "<td>";
    if ($fieldnames{$_} & $ENUM)
    {
      my $ary_ref = \@$lc_fieldname;
      my $size = scalar(@$ary_ref);
      $size = 4 if $size > 4;
      print $q->scrolling_list(-name=>$lc_fieldname,
                               -values=>$ary_ref,
                               -multiple=>1,
                               -size=>$size);
    }
    else
    {
      print "&nbsp;";
    }
    print "</td>\n";
    print "</tr>\n";
  }
  print	"</table>\n";

  print "<div>&nbsp;</div>\n";

  ### Column selection

  my(@columns) = split(' ', $global_prefs{'columns'});
  @columns = @deffields unless @columns;
  print "<table border=1 bgcolor=$cell_bg>",
        "<caption>Select Columns to Display</caption>",
        "<tr valign=top><td>Display these columns:</td>\n<td>",
        $q->scrolling_list(-name=>'columns',
                           -values=>\@fields,
                           -defaults=>\@columns,
                           -multiple=>1),
	"</td>\n</tr>\n</table>\n";

  ### Wrapup

  print "</center>\n";
  print "<hr>",
	$q->p($q->submit('cmd', 'submit query'),
	" or ",
	$q->reset(-name=>'reset')),
	$q->end_form();
  page_footer($page);
  page_end_html($page);
}

sub print_gnatsd_error
{
  my($errstr) = @_;
  print $q->h2("Error: $errstr");
}

sub error_page
{
  my($err_heading, $err_text) = @_;
  my $page = 'Error';
  print_header();
  page_start_html($page);
  page_heading($page, $err_heading);
  print $q->p($err_text) if $err_text;
  page_footer($page);
  page_end_html($page);
}

sub submitquery
{
  my $page = 'Query Results';
  my $queryname = $q->param('queryname');
  my $originatedbyme = $q->param('originatedbyme');
  my $ignoreclosed   = $q->param('ignoreclosed');
  my $debug = 0;

  my $heading = 'Query Results';
  $heading .= ": $queryname" if $queryname;
  page_start_html($page);
  page_heading($page, $heading, 1, 1);

  local($gnats::DEBUG_LEVEL) = 1 if $debug;
  client_cmd("rset");
  client_cmd("orig $db_prefs{'user'}") if($originatedbyme);
  client_cmd("nocl")                   if($ignoreclosed);

  # Submit client_cmd for each param which specifies a query.
  my($param, $regexp, @val);
  foreach $param ($q->param())
  {
    next unless $gnatsd_query{$param};

    # Turn multiple param values into regular expression.
    @val = $q->param($param);
    $regexp = join('|', @val);

    # Discard trailing '|all', or leading '|'.
    $regexp =~ s/\|all$//;
    $regexp =~ s/^\|//;

    # If there's still a query here, make it.
    client_cmd("$gnatsd_query{$param} $regexp")
          if($regexp && $regexp ne 'all');
  }

  my(@query_results) = client_cmd("sql2");
  if ($gnats::ERRSTR) {
    print_gnatsd_error($gnats::ERRSTR);
  }
  else {
    display_query_results(@query_results);
  }

  page_footer($page);
  page_end_html($page);
}

# by_field -
#     Sort routine called by display_query_results.
#
#     Assumes $sortby is set by caller.
#
sub by_field
{
  my($val);
  # Handle common cases first.
  if (!$sortby || $sortby eq 'PR')
  {
    $val = $b->[0] <=> $a->[0];
  }
  elsif ($sortby eq 'Category')
  {
    $val = $a->[1] cmp $b->[1];
  }
  elsif ($sortby eq 'Confidential')
  {
    $val = $a->[3] cmp $b->[3];
  }
  elsif ($sortby eq 'Severity')
  {
    # sort by Severity then Priority then Class
    $val = $a->[4] <=> $b->[4]
                   ||
           $a->[5] <=> $b->[5]
                   ||
           $a->[8] <=> $b->[8]
                   ;
  }
  elsif ($sortby eq 'Priority')
  {
    # sort by Priority then Severity then Class
    $val = $a->[5] <=> $b->[5]
                   ||
           $a->[4] <=> $b->[4]
                   ||
           $a->[8] <=> $b->[8]
                   ;
  }
  elsif ($sortby eq 'Responsible')
  {
    $val = $a->[6] cmp $b->[6];
  }
  elsif ($sortby eq 'State')
  {
    $val = $a->[7] <=> $b->[7];
  }
  elsif ($sortby eq 'Class')
  {
    $val = $a->[8] <=> $b->[8];
  }
  elsif ($sortby eq 'Submitter-Id')
  {
    $val = $a->[9] cmp $b->[9];
  }
  elsif ($sortby eq 'Release')
  {
    $val = $a->[12] cmp $b->[12];
  }
  elsif ($sortby eq 'Arrival-Date')
  {
    $val = $a->[10] cmp $b->[10];
  }
  elsif ($sortby eq 'Closed-Date')
  {
    $val = $a->[14] cmp $b->[14];
  }
  elsif ($sortby eq 'Last-Modified')
  {
    $val = $a->[13] cmp $b->[13];
  }
  else
  {
    $val = $a->[0] <=> $b->[0];
  }
  $val;
}

# nonempty -
#     Turn empty strings into "&nbsp;" so that Netscape tables won't
#     look funny.
#
sub nonempty
{
  my $str = shift;
  $str = '&nbsp;' if !$str;
  $str;
}

# field2param -
#     Convert gnats field name into parameter name, e.g.
#     "Submitter-Id" => "submitter_id".  It's done this crazy way for
#     compatibility with queries stored by gnatsweb 2.1.
#
sub field2param
{
  my $name = shift;
  $name =~ s/-/_/g;
  $name = lc($name);
}

# param2field -
#     Convert parameter name into gnats field name, e.g.
#     "submitter_id" => "Submitter-Id".  It's done this crazy way for
#     compatibility with queries stored by gnatsweb 2.1.
#
sub param2field
{
  my $name = shift;
  my @words = split(/_/, $name);
  map { $_ = ucfirst($_); } @words;
  $name = join('-', @words);
}

# display_query_results -
#     Display the query results, and the "store query" form.
sub display_query_results
{
  my(@query_results) = @_;
  my(@fields) = $q->param('columns');
  my($field);
  my(%vis); # hash of displayed fields

  # Print number of matches found, and return if that number is 0.
  my $num_matches = scalar(@query_results);
  my $heading = sprintf("%s %s found",
                        $num_matches ? $num_matches : "No",
                        ($num_matches == 1) ? "match" : "matches");
  print $q->h2($heading);
  return if ($num_matches == 0);

  #warn "---------  query results ---------\n";
  #foreach $p (@query_results) {
  #  warn "$p\n";
  #}

  # If there's a site callback to sort, provide a link to do it.
  if(cb('sort_query', 'custom', 'checking_if_custom_sort_exists')) {
    my $href = $q->self_url();
    $href =~ s/&sortby=[^&]+//;
    $href .= "&sortby=custom";
    # 6/25/99 kenstir: CEL claims this avoids a problem w/ apache+mod_perl.
    $href =~ s/^[^?]*\?/$sn\?/; #CEL
    print "Site-specific <a href=\"$href\">sort</a>";
  }

  # Sort @query_results according to the rules in by_field().
  # Using the "map, sort" idiom allows us to perform the expensive
  # split() only once per item, as opposed to during every comparison.
  # Note that $sortby must be 'local'...it's used in by_field().
  local($sortby) = $q->param('sortby');
  my(@sortable) = ('PR','Category','Confidential',
                   'Severity','Priority','Responsible',
                   'State','Class','Release','Submitter-Id',
                   'Arrival-Date', 'Closed-Date', 'Last-Modified');
  my(@presplit_prs) = map { [ (split /\|/) ] } @query_results;
  my(@sorted_prs) = cb('sort_query', $sortby, @presplit_prs);
  if(!defined($sorted_prs[0])) {
    @sorted_prs = sort by_field @presplit_prs;
  }

  print "\n<table border=1>\n";

  # Print table header which allows sorting by some columns.
  # While printing the headers, temporarily override the 'sortby' param
  # so that self_url() works right.
  print "<tr>\n";
  my(@cols) = ('PR', @fields);
  for $field (@cols)
  {
    $ufield = param2field($field);
    if (grep(/$ufield/, @sortable))
    {
      $q->param(-name=>'sortby', -value=>$ufield);
      my $href = $q->self_url();
      # 6/25/99 kenstir: CEL claims this avoids a problem w/ apache+mod_perl.
      $href =~ s/^[^?]*\?/$sn\?/; #CEL
      print "<th><a href=\"$href\">$ufield</a></th>\n";
    }
    else
    {
      print "<th>$ufield</th>\n";
    }
    $vis{$field}++;
  }
  # Reset param 'sortby' to its original value, so that 'store query' works.
  $q->param(-name=>'sortby', -value=>$sortby);
  print "</tr>\n";

  # Print the PR's.
  my $myurl = $q->url();
  foreach (@sorted_prs)
  {
    print "<tr valign=top>\n";
    my($id, $cat, $syn, $conf, $sev,
       $pri, $resp, $state, $class, $sub,
       $arrival, $orig, $release, $lastmoddate, $closeddate,
       $quarter, $keywords, $daterequired) = @{$_};
    print "<td nowrap><a href=\"" . get_viewpr_url($id, 1) . "\">$id</a>";
    print " <a href=\"" . get_editpr_url($id, 1) .
          "\"><font size=-1>edit</font></a>"
          if can_edit();
    print "</td>\n";
    # CGI.pm does not like boolean attributes like nowrap. We add =>'1' to avoid a -w warning.
    print $q->td({-nowrap=>'1'}, $q->escapeHTML($cat)) if $vis{'category'};
    print $q->td({-nowrap=>'1'}, $q->escapeHTML($conf)) if $vis{'confidential'};
    print $q->td({-nowrap=>'1'}, $q->escapeHTML($state[$state])) if $vis{'state'};
    print $q->td({-nowrap=>'1'}, $q->escapeHTML($class[$class])) if $vis{'class'};
    print $q->td({-nowrap=>'1'}, $q->escapeHTML($severity[$sev])) if $vis{'severity'};
    print $q->td({-nowrap=>'1'}, $q->escapeHTML($priority[$pri])) if $vis{'priority'};
    print $q->td({-nowrap=>'1'}, nonempty($q->escapeHTML($release))) if $vis{'release'};
    print $q->td({-nowrap=>'1'}, nonempty($q->escapeHTML($quarter))) if($site_release_based
                                                                  && $vis{'quarter'});
    print $q->td(nonempty($q->escapeHTML($keywords))) if($site_release_based
                                                                   && $vis{'keywords'});
    print $q->td({-nowrap=>'1'}, $q->escapeHTML($resp)) if $vis{'responsible'};
    print $q->td({-nowrap=>'1'}, nonempty($q->escapeHTML($sub))) if $vis{'submitter_id'};
    print $q->td({-nowrap=>'1'}, nonempty($q->escapeHTML($orig))) if $vis{'originator'};
    print $q->td({-nowrap=>'1'}, $q->escapeHTML($arrival)) if $vis{'arrival_date'};
    print $q->td({-nowrap=>'1'}, nonempty($q->escapeHTML($daterequired))) if($site_release_based
                                                                       && $vis{'date_required'});
    print $q->td({-nowrap=>'1'}, nonempty($q->escapeHTML($lastmoddate))) if $vis{'last_modified'};
    print $q->td({-nowrap=>'1'}, nonempty($q->escapeHTML($closeddate))) if $vis{'closed_date'};
    print $q->td($q->escapeHTML($syn)) if $vis{'synopsis'};
    print "</tr>\n";
  }
  print "</table>\n";

  # Provide a URL which someone can use to bookmark this query.
  my $url = $q->self_url();
  print $q->p(qq{<a href="$url">View for bookmarking</a>\n});

  # Allow the user to store this query.  Need to repeat params as hidden
  # fields so they are available to the 'store query' handler.
  print $q->start_form();
  foreach ($q->param())
  {
    # Ignore certain params.
    next if /^(cmd|queryname)$/;
    print $q->hidden($_);
  }
  print "<table>\n",
        "<tr>\n",
        "<td>Remember this query as:</td>\n",
        "<td>",
        $q->textfield(-name=>'queryname', -size=>25),
        "</td>\n<td>";
  # Note: include hidden 'cmd' so user can simply press Enter w/o clicking.
  print $q->hidden(-name=>'cmd', -value=>'store query', -override=>1),
        $q->submit('cmd', 'store query'),
        "</td>\n</tr>\n</table>",
        $q->end_form();
}

# store_query -
#     Save the current query in a cookie.
#
#     Queries are stored as individual cookies named
#     'gnatsweb-query-$queryname'.
#
sub store_query
{
  my $debug = 0;
  my $queryname = $q->param('queryname');

  # First make sure we don't already have too many cookies.
  # See http://home.netscape.com/newsref/std/cookie_spec.html for
  # limitations -- 20 cookies; 4k per cookie.
  my(@cookie_names) = $q->cookie();
  if (@cookie_names >= 20) {
    error_page('Cannot store query -- too many cookies',
               "Gnatsweb cannot store the query as another cookie because"
               . "there already are "
               . scalar(@cookie_names)
               . " cookies being passed to gnatsweb.  There is a maximum"
               . " of 20 cookies per server or domain as specified in"
               . " http://home.netscape.com/newsref/std/cookie_spec.html");
    exit();
  }

  # Don't save certain params.
  $q->delete('cmd');

  # Have to generate the cookie before printing the header.
  my $query_string = $q->query_string();
  my $new_cookie = $q->cookie(-name => "gnatsweb-query-$queryname",
                              -value => $query_string,
                              -path => $global_cookie_path,
                              -expires => '+10y');
  print $q->header(-cookie => $new_cookie);

  # Now print the page.
  my $page = 'Query Saved';
  page_start_html($page);
  page_heading($page, 'Query Saved');
  print "<h2>debugging</h2><pre>",
        "query_string: $query_string",
        "cookie: $new_cookie\n",
        "</pre><hr>\n"
        if $debug;
  print "<p>Your query \"$queryname\" has been saved.  It will be available ",
        "the next time you reload the Query page.";
  page_footer($page);
  page_end_html($page);
}

# print_stored_queries -
#     Retrieve any stored queries and print out a short form allowing
#     the submission of these queries.
#
#     Queries are stored as individual cookies named
#     'gnatsweb-query-$queryname'.
#
# side effects:
#     Sets global %stored_queries.
#
sub print_stored_queries
{
  %stored_queries = ();
  foreach my $cookie ($q->cookie())
  {
    if ($cookie =~ /gnatsweb-query-(.*)/)
    {
      $stored_queries{$1} = $q->cookie($cookie);
    }
  }
  if (%stored_queries)
  {
    print "<table cellspacing=0 cellpadding=0 border=0>",
          "<tr valign=top>",
          $q->start_form(),
          "<td>",
          hidden_db(),
          $q->submit('cmd', 'submit stored query'),
          "<td>&nbsp;<td>",
          $q->popup_menu(-name=>'queryname',
                         -values=>[ sort(keys %stored_queries) ]),
          $q->end_form(),
          $q->start_form(),
          "<td>",
          $q->hidden('return_url', $q->self_url()),
          hidden_db(),
          $q->submit('cmd', 'delete stored query'),
          "<td>&nbsp;<td>",
          $q->popup_menu(-name=>'queryname',
                         -values=>[ sort(keys %stored_queries) ]),
          $q->end_form(),
          "</tr></table>";
  }
}

# submit_stored_query -
#     Submit the query named in the param 'queryname'.
#
#     Queries are stored as individual cookies named
#     'gnatsweb-query-$queryname'.
#
sub submit_stored_query
{
  my $debug = 0;
  my $queryname = $q->param('queryname');
  my $query_string;
  my $err = '';
  if (!$queryname)
  {
    $err = "Internal error: no 'queryname' parameter";
  }
  elsif (!($query_string = $q->cookie("gnatsweb-query-$queryname")))
  {
    $err = "No such named query: $queryname";
  }
  if ($err)
  {
    print $q->header(),
          $q->start_html('Error'),
          $q->h3($err),
          $q->end_html();
  }
  else
  {
    # 9/10/99 kenstir: Must use full (not relative) URL in redirect.
    # Patch by Elgin Lee <ehl@terisa.com>.
    my $query_url = $q->url() . '?cmd=' . $q->escape('submit query')
          . '&' . $query_string;
    if ($debug)
    {
      print $q->header(),
            $q->start_html(),
            $q->pre("debug: query_url: $query_url\n");
    }
    else
    {
      print $q->redirect($query_url);
    }
  }
}

# delete_stored_query -
#     Delete the query named in the param 'queryname'.
#
#     Queries are stored as individual cookies named
#     'gnatsweb-query-$queryname'.
#
sub delete_stored_query
{
  my $debug = 0;
  my $queryname = $q->param('queryname');
  my $query_string;
  my $err = '';
  if (!$queryname)
  {
    $err = "Internal error: no 'queryname' parameter";
  }
  elsif (!($query_string = $q->cookie("gnatsweb-query-$queryname")))
  {
    $err = "No such named query: $queryname";
  }
  if ($err)
  {
    print $q->header(),
          $q->start_html('Error'),
          $q->h3($err),
          $q->end_html();
  }
  else
  {
    # The negative -expire causes the old cookie to expire immediately.
    my $expire_cookie_with_path =
          $q->cookie(-name => "gnatsweb-query-$queryname",
                     -value => 'does not matter',
                     -path => $global_cookie_path,
                     -expires => '-1d');
    my $expire_cookies = $expire_cookie_with_path;

    # If we're using a non-empty $global_cookie_path, then we need to
    # create two expire cookies.  One or the other will delete the stored
    # query, depending on whether the query was created with this version
    # of gnatsweb, or with an older version.
    if ($global_cookie_path)
    {
      my $expire_cookie_no_path =
            $q->cookie(-name => "gnatsweb-query-$queryname",
                       -value => 'does not matter',
                       # No -path here!
                       -expires => '-1d');
      $expire_cookies = [ $expire_cookie_with_path, $expire_cookie_no_path ];
    }

    # Return the user to the page they were viewing when they pressed
    # 'delete stored query'.
    print $q->redirect(-cookie => $expire_cookies,
                       -location => $q->param('return_url'));
  }
}

# send_html -
#     Send HTML help file, after first trimming out everything but
#     <body>..</body>.  This is done in this way for convenience of
#     installation.  If the gnatsweb.html is installed into the cgi-bin
#     directory along with the gnatsweb.pl file, then it can't be loaded
#     directly by Apache.  So, we send it indirectly through gnatsweb.pl.
#     This approach has the benefit that the resulting page has the
#     customized gnatsweb look.
#
sub send_html
{
  my $file = shift;
  open(HTML, "<$file") || die "Can't open $file: $!";
  undef $/; # slurp file whole
  my $html = <HTML>;
  close(HTML);

  # send just the stuff inside <body>..</body>
  $html =~ s/.*<body>//is;
  $html =~ s/<\/body>.*//is;

  print $html;
}

sub help_page
{
  my $html_file = 'gnatsweb.html';
  my $page      = $q->param('help_title') || 'Help';
  my $heading   = $page;
  page_start_html($page);
  page_heading($page, $heading);

  # If send_html doesn't work, print some default, very limited, help text.
  if (!send_html($html_file))
  {
    print p('Welcome to our problem report database. ',
            'You\'ll notice that here we call them "problem reports" ',
            'or "PR\'s", not "bugs".');
    print p('This web interface is called "gnatsweb". ',
            'The database system itself is called "gnats".',
            'You may want to peruse ',
            a({-href=>"$gnats_info_top"}, 'the gnats manual'),
            'to read about bug lifecycles and the like, ',
            'but then again, you may not.');
  }

  page_footer($page);
  page_end_html($page);
}

# hidden_db -
#    Return hidden form element to maintain current database.  This
#    enables people to keep two browser windows open to two databases.
#
sub hidden_db
{
  return $q->hidden(-name=>'database', -value=>$global_prefs{'database'},
                    -override=>1);
}

# one_line_form -
#     One line, two column form used for main page.
#
sub one_line_form
{
  my($label, @form_body) = @_;
  return one_line_layout($label,
                         $q->start_form(-name=>$label),
                         hidden_db(),
                         @form_body,
                         $q->end_form());
}

# one_line_layout -
#     One line, two column layout used by forms on main page.
#
sub one_line_layout
{
  my($label, @rhs) = @_;
  my $valign = 'baseline';
  return $q->Tr({-valign=>$valign},
                $q->td($q->b($label)),
                $q->td('&nbsp;'),
                $q->td(@rhs));
}

# one_line_submit -
#     Submit button which takes up less vertical space.
#     Used by callers to one_line_form().
#
sub one_line_submit
{
  my($name, $value, $exclude_hidden_input) = @_;
  my $html = '';

  # This is a basic implementation which doesn't use Javascript, but       
  # takes up more vertical space. Requiring JavaScript is unacceptable
  # for many sites. For sites where this is OK, comment the following 
  # line, then uncomment the subsequent 4 lines.
  $html .= $q->submit($name,$value); 

#  $html .= $q->hidden($name, $value)
#        unless $exclude_hidden_input;
#  $html .= qq{<input type="button" value="$value"
#               onclick="this.form.cmd.value = '$value'; submit()">};
  return $html;
}

# can_edit -
#     Return true if the user has edit priviledges or better.
#
sub can_edit
{
  return ($access_level =~ /edit|admin/);
}

sub main_page
{
  my $page = 'Main';
  print_header();
  page_start_html($page);
  page_heading($page, 'Main Page', 1);

  print '<p><table cellspacing=0 cellpadding=0 border=0>';

  my $top_buttons_html = cb('main_page_top_buttons') || '';
  print $top_buttons_html;

  print one_line_form('Create Problem Report:',
                      one_line_submit('cmd', 'create'));
  # Only include Edit action if user is allowed to edit PRs.
  # Note: include hidden 'cmd' so user can simply type into the textfield
  # and press Enter w/o clicking.
  print one_line_form('Edit Problem Report:',
                      hidden(-name=>'cmd', -value=>'edit', -override=>1),
                      one_line_submit('unused', 'edit', 1),
                      '#',
                      textfield(-size=>6, -name=>'pr'))
        if can_edit();
  print one_line_form('View Problem Report:',
                      hidden(-name=>'cmd', -value=>'view', -override=>1),
                      one_line_submit('unused', 'view', 1),
                      '#',
                      textfield(-size=>6, -name=>'pr'));
  print one_line_form('Query Problem Reports:',
                      one_line_submit('cmd', 'query', 1),
                      '&nbsp;',
                      one_line_submit('cmd', 'advanced query', 1));
  print one_line_form('Login Again:',
                      one_line_submit('cmd', 'login again'));
  print one_line_form('Get Help:',
                      one_line_submit('cmd', 'help'));

  my $bot_buttons_html = cb('main_page_bottom_buttons') || '';
  print $bot_buttons_html;

  print '</table>';
  page_footer($page);
  print '<hr><small>'
      . 'Gnatsweb by Matt Gerassimoff and Kenneth H. Cox<br>'
      . "Gnatsweb v$VERSION, Gnats v$GNATS_VERS"
      . '</small>';
  page_end_html($page);
}

# cb -
#
#     Calls site_callback subroutine if defined.
#
# usage:
#     $something = cb($reason, @args) || 'default_value';
#     # -or-
#     $something = cb($reason, @args)
#     $something = 'default_value' unless defined($something);
#
# arguments:
#     $reason - reason for the call.  Each reason is unique.
#     @args   - additional parameters may be provided in @args.
#
# returns:
#     undef if &site_callback is not defined,
#     else value returned by &site_callback.
#
sub cb
{
  my($reason, @args) = @_;
  my @val = undef;
  if (defined &site_callback)
  {
    (@val) = site_callback($reason, @args);
  }

  return wantarray ? @val : $val[0];
}

# print_header -
#     Print HTTP header unless it's been printed already.
#
sub print_header
{
  # Protect against multiple calls.
  return if $print_header_done;
  $print_header_done = 1;

  print $q->header(@_);
}

# page_start_html -
#
#     Print the HTML which starts off each page (<html><head>...</head>).  
#
#     By default, print a banner containing $site_banner_text, followed
#     by the given page $title.
#
#     The starting HTML can be overridden by &site_callback.
#
#     Supports debugging.
#
# arguments:
#     $title - title of page
#
sub page_start_html
{
  my $title = shift;
  my $debug = 0;

  # Protect against multiple calls.
  return if $page_start_html_done;
  $page_start_html_done = 1;

  # Allow site callback to override html.
  my $html = cb('page_start_html', $title);
  if ($html)
  {
    print $html;
    return;
  }

  # Call start_html, with -bgcolor if we need to override that.
  my @args = (-title=>"$title - $site_banner_text");
  push(@args, -bgcolor=>$site_background)
        if defined($site_background);
  push(@args, -style=>{-src=>$site_stylesheet})
        if defined($site_stylesheet);
  print $q->start_html(@args);

  # Add the page banner.  This banner is a string slammed to the right
  # of a 100% width table.  The data is a link back to the main page.
  #
  # Note that the banner uses inline style, rather than a GIF; this
  # makes installation easier by eliminating the need to install GIFs
  # into a separate directory.  At least for Apache, you can't serve
  # GIFs out of your CGI directory.
  #
  # Danger!  Don't use double quotes inside $style; that will confuse
  # Netscape 4.5.  Use single quotes if needed.  Don't use multi-line
  # comments; they confuse Netscape 4.5.
  my $browser = $ENV{'HTTP_USER_AGENT'};
  my $style;

  if ($browser =~ /Mozilla.*X11/)
  {
    # Netscape Unix
    $style = <<END_OF_STYLE;
    color: $site_banner_foreground;
    font-family: helvetica, sans;
    font-size: 18pt;
    text-decoration: none;
END_OF_STYLE
    }
  else
  {
    $style = <<END_OF_STYLE;
    color: $site_banner_foreground;
    font-family: 'Verdana', 'Arial', 'Helvetica', monospace;
    font-size: 14pt;
    font-weight: light;
    text-decoration: none;
END_OF_STYLE
  }
  my($row, $banner);
  $row = $q->Tr($q->td({-align=>'right'},
                       $q->a({-style=>$style, -href=>get_script_name()},
                             ' ', $site_banner_text, ' ')));
  $banner = $q->table({-bgcolor=>$site_banner_background, -width=>'100%',
                       -border=>0, -cellpadding=>2, -cellspacing=>0},
                      $row);
  print $banner;

  # debugging
  if ($debug)
  {
    print "<h3>debugging params</h3><font size=1><pre>";
    my($param,@val);
    foreach $param (sort $q->param())
    {
      @val = $q->param($param);
      printf "%-12s %s\n", $param, $q->escapeHTML(join(' ', @val));
    }
    print "</pre></font><hr>\n";
  }
}

# page_heading -
#
#     Print the HTML which starts off a page.  Basically a fancy <h1>
#     plus user + database names.
#
sub page_heading
{
  my($title, $heading, $display_user_info, $display_date) = @_;

  # Protect against multiple calls.
  return if $page_heading_done;
  $page_heading_done = 1;

  # Allow site callback to override html.
  my $html = cb('page_heading', $title, $heading);
  if ($html)
  {
    print $html;
    return;
  }

  my $leftcol = $heading ? $heading : '&nbsp;';
  my $rightcol;

  if ($db_prefs{'user'} && defined($display_user_info))
  {
    $rightcol= "<tt><small>User: $db_prefs{'user'}<br>" .
               "Database: $global_prefs{'database'}<br>" .
               "Access: $access_level";
    if ($display_date)
    {
      my $date = localtime;
      $date =~ s/:[0-9]+\s/ /;
      $rightcol .= "<br>Date: $date";
    }
    $rightcol .= "</small></tt>";
  }
  else
  {
    $rightcol = '&nbsp;';
  }

  print $q->table({-width=>'100%'}, $q->Tr($q->td({-nowrap=>'1'}, $q->h1($leftcol)),
                         # this column serves as empty expandable filler
                         $q->td({-width=>'100%'}, '&nbsp;'),
                         $q->td({-nowrap=>'1'}, $rightcol)));
}

# page_footer -
#
#     Allow the site_callback to take control before the end of the
#     page.
#
sub page_footer
{
  my $title = shift;

  my $html = cb('page_footer', $title);
  print $html if ($html);
}

# page_end_html -
#
#     Print the HTML which ends a page.  Allow the site_callback to
#     take control here too.
#
sub page_end_html
{
  my $title = shift;

  # Allow site callback to override html.
  my $html = cb('page_end_html', $title);
  if ($html)
  {
    print $html;
    return;
  }

  print $q->end_html();
}

# fix_multiline_val -
#     Modify text of multitext field so that it contains \n separators
#     (not \r\n or \n as some platforms use), and so that it has a \n
#     at the end.
#
sub fix_multiline_val
{
  my $val = shift;
  $val =~ s/\r\n?/\n/g;
  $val .= "\n" unless $val =~ /\n$/;
  $val;
}

# parse_config -
#     Parse the config file, storing the name/value pairs in the global
#     hash %config.
sub parse_config
{
  my(@lines) = @_;

  %config = ();

  # Default value for GNATS_ADDR is 'bugs'.
  $config{'GNATS_ADDR'} = 'bugs';

  # Note that the values may be quoted, as the config file uses
  # Bourne-shell syntax.
  foreach $_ (@lines)
  {
    if (/(\S+)\s*=\s*['"]?([^'"]*)['"]?/)
    {
      $config{$1} = $2;
    }
  }
}

# parse_categories -
#     Parse the categories file.
sub parse_categories
{
  my(@lines) = @_;

  @category = ("all");
  %category_notify = ();
  %category_responsible = ();

  foreach $_ (sort @lines)
  {
    my($cat, $desc, $resp, $notify) = split(/:/);
    # Uncomment to exclude administrative category 'pending'.
    # next if($cat eq 'pending');
    push(@category, $cat);
    $category_responsible{$cat} = $resp;
    $category_notify{$cat} = $notify;
  }
}

# parse_submitters -
#     Parse the submitters file.
sub parse_submitters
{
  my(@lines) = @_;

  @submitter_id = ("all");
  %submitter_contact = ();
  %submitter_notify = ();

  foreach $_ (sort @lines)
  {
    my($submitter, $full_name, $type, $response_time, $contact, $notify)
          = split(/:/);
    push(@submitter_id, $submitter);
    $submitter_contact{$submitter} = $contact;
    $submitter_notify{$submitter} = $notify;
  }
}

# parse_responsible -
#     Parse the responsible file.
sub parse_responsible
{
  my(@lines) = @_;

  @responsible = ("all");
  %responsible_fullname = ();
  %responsible_address = ();

  foreach $_ (sort @lines)
  {
    my($person, $fullname, $address) = split(/:/);
    push(@responsible, $person);
    $responsible_fullname{$person} = $fullname;
    $responsible_address{$person} = $address || $person;
  }
}

# connect_to_gnatsd -
#     Connect to gnatsd.
#
sub connect_to_gnatsd
{
  my($response) = client_init($site_gnats_host, $site_gnats_port);
  if (!$response) {
    error_page("Error: Couldn't connect to gnats server",
               "host $site_gnats_host, port $site_gnats_port<br>"
               . $gnats::ERRSTR);
    exit();
  }
  return $response;
}

# initialize -
#     Initialize gnatsd-related globals and login to gnatsd.
#
sub initialize
{
  my $regression_testing = shift;

  @severity = ("all", "critical", "serious", "non-critical");
  @priority = ("all", "high", "medium", "low");
  @confidential = ("all", "no", "yes");

  # @fields - param names of columns displayable in query results
  # @deffields - default displayed columns
  @deffields = ("category", "state", "responsible", "synopsis");
  @fields = ("category", "confidential", "state", "class",
             "severity", "priority",
             "release", "quarter", "responsible", "submitter_id", "originator",
             "arrival_date", "date_required",
             "last_modified", "closed_date", "synopsis");

  # @fieldnames - fields appear in the standard order, defined by pr.h
  @fieldnames = (
    "Number",
    "Category",
    "Synopsis",
    "Confidential",
    "Severity",
    "Priority",
    "Responsible",
    "State",
    "Quarter",
    "Keywords",
    "Date-Required",
    "Class",
    "Submitter-Id",
    "Arrival-Date",
    "Closed-Date",
    "Last-Modified",
    "Originator",
    "Release",
    "Organization",
    "Environment",
    "Description",
    "How-To-Repeat",
    "Fix",
    "Release-Note",
    "Audit-Trail",
    "Unformatted",
  );

  # %fieldnames maps the field name to a flag value composed of bits.
  # See $MULTILINE above for bit definitions.
  %fieldnames = (
    "Number"        => $SENDEXCLUDE | $EDITEXCLUDE,
    "Category"      => $ENUM,
    "Synopsis"      => 0,
    "Confidential"  => $ENUM,
    "Severity"      => $ENUM,
    "Priority"      => $ENUM,
    "Responsible"   => $ENUM | $REASONCHANGE | $SENDEXCLUDE | $AUDITINCLUDE,
    "State"         => $ENUM | $REASONCHANGE | $SENDEXCLUDE | $AUDITINCLUDE,
    "Quarter"        => 0,
    "Keywords"      => 0,
    "Date-Required" => 0,
    "Class"         => $ENUM,
    "Submitter-Id"  => $ENUM | $EDITEXCLUDE,
    "Arrival-Date"  => $SENDEXCLUDE | $EDITEXCLUDE,
    "Closed-Date"   => $SENDEXCLUDE | $EDITEXCLUDE,
    "Last-Modified" => $SENDEXCLUDE | $EDITEXCLUDE,
    "Originator"    => $EDITEXCLUDE,
    "Release"       => 0,
    "Organization"  => $MULTILINE | $SENDEXCLUDE | $EDITEXCLUDE, # => $MULTILINE
    "Environment"   => $MULTILINE,
    "Description"   => $MULTILINE,
    "How-To-Repeat" => $MULTILINE,
    "Fix"           => $MULTILINE,
    "Release-Note"  => $MULTILINE | $SENDEXCLUDE,
    "Audit-Trail"   => $MULTILINE | $SENDEXCLUDE | $EDITEXCLUDE,
    "Unformatted"   => $MULTILINE | $SENDEXCLUDE | $EDITEXCLUDE,
  );

  $attachment_delimiter = "----gnatsweb-attachment----\n";

  # gnatsd query commands: maps param name to gnatsd command
  %gnatsd_query = (
    "category"        => 'catg',
    "synopsis"        => 'synp',
    "confidential"    => 'conf',
    "severity"        => 'svty',
    "priority"        => 'prio',
    "responsible"     => 'resp',
    "state"           => 'stat',
    "class"           => 'clss',
    "submitter_id"    => 'subm',
    "originator"      => 'orig',
    "release"         => 'rlse',
    "text"            => 'text',
    "multitext"       => 'mtxt',
    "arrivedbefore"   => 'abfr',
    "arrivedafter"    => 'araf',
    "modifiedbefore"  => 'mbfr',
    "modifiedafter"   => 'maft',
    "closedbefore"    => 'cbfr',
    "closedafter"     => 'caft',
    "quarter"	      => 'qrtr',
    "keywords"	      => 'kywd',
    "requiredbefore"  => 'bfor',
    "requiredafter"   => 'aftr',
  );

  # clear out some unused fields if not used
  if (!$site_release_based)
  {
    @fields = grep(!/quarter|keywords|date_required/, @fields);
    @fieldnames = grep(!/Quarter|Keywords|Date-Required/, @fieldnames);
  }

  my(@lines);
  my($response);

  # Get gnatsd version from initial server connection text.
  $GNATS_VERS = 999.0;
  $response = connect_to_gnatsd();
  if ($response =~ /GNATS server (.*) ready/)
  {
    $GNATS_VERS = $1;
  }

  # Login to selected database.
  LOGIN:
  {
    # Issue CHDB command; revert to login page if it fails.
    ($response) = client_cmd("chdb $global_prefs{'database'}");
    if (!$response)
    {
      login_page($q->self_url(), $gnats::ERRSTR);
      exit();
    }

    # Get user permission level from USER command.  Revert to the
    # login page if the command fails.
    ($response) = client_cmd("user $db_prefs{'user'} $db_prefs{'password'}");
    if (!$response)
    {
      login_page($q->self_url(), $gnats::ERRSTR);
      exit();
    }
    $access_level = 'edit';
    if ($response =~ /User access level set to (\w*)/)
    {
      $access_level = $1;
    }
  }

  # Get some enumerated lists
  my($x, $dummy);
  @state = ("all");
  foreach $_ (client_cmd("lsta"))
  {
    ($x, $dummy) = split(/:/);
    push(@state, $x);
  }
  @class = ("all");
  foreach $_ (client_cmd("lcla"))
  {
    ($x, $dummy) = split(/:/);
    push(@class, $x);
  }

  # List various gnats-adm files, and parse their contents for data we
  # will need later.  Each parse subroutine stashes information away in
  # its own global vars.  The call to client_cmd() happens here to
  # enable regression testing of the parse subs using fixed files.
  @lines = client_cmd("lcfg");
  parse_config(@lines);
  @lines = client_cmd("lcat");
  parse_categories(@lines);
  @lines = client_cmd("lsub");
  parse_submitters(@lines);
  @lines = client_cmd("lres");
  parse_responsible(@lines);

  # Now that everything's all set up, let the site_callback have at it.
  # It's return value doesn't matter, but here it can muck with our defaults.
  cb('initialize');
}

# trim_responsible -
#     Trim the value of the Responsible field to get a
#     valid responsible person.  This exists here, and in gnats itself
#     (modify_pr(), check_pr(), gnats(), append_report()), for
#     compatibility with old databases, which had 'person (Full Name)'
#     in the Responsible field.
sub trim_responsible
{
  my $resp = shift;
  $resp =~ s/ .*//;
  $resp;
}

# fix_email_addrs -
#     Trim email addresses as they appear in an email From or Reply-To
#     header into a comma separated list of just the addresses.
#
#     Delete everything inside ()'s and outside <>'s, inclusive.
#
sub fix_email_addrs
{
  my $addrs = shift;
  my @addrs = split(/,/, $addrs);
  my @trimmed_addrs;
  my $addr;
  foreach $addr (@addrs)
  {
    $addr =~ s/\(.*\)//;
    $addr =~ s/.*<(.*)>.*/$1/;
    $addr =~ s/^\s+//;
    $addr =~ s/\s+$//;
    push(@trimmed_addrs, $addr);
  }
  $addrs = join(', ', @trimmed_addrs);
  $addrs;
}

sub parsepr
{
  # 9/18/99 kenstir: This two-liner can almost replace the next 30 or so
  # lines of code, but not quite.  It strips leading spaces from multiline
  # fields.
  #my $prtext = join("\n", @_);
  #my(%fields) = ('envelope' => split /^>(\S*?):\s*/m, $prtext);
  #  my $prtext = join("\n", @_);
  #  my(%fields) = ('envelope' => split /^>(\S*?):(?: *|\n)/m, $prtext);

  my $debug = 0;

  my($hdrmulti) = "envelope";
  my(%fields);
  foreach (@_)
  {
    chomp($_);
    $_ .= "\n";
    if(!/^([>\w\-]+):\s*(.*)\s*$/)
    {
      if($hdrmulti ne "")
      {
        $fields{$hdrmulti} .= $_;
      }
      next;
    }
    local($hdr, $arg, $ghdr) = ($1, $2, "*not valid*");
    if($hdr =~ /^>(.*)$/)
    {
      $ghdr = $1;
    }
    if(exists($fieldnames{$ghdr}))
    {
      if($fieldnames{$ghdr} & $MULTILINE)
      {
        $hdrmulti = $ghdr;
	$fields{$ghdr} = "";
      }
      else
      {
        $hdrmulti = "";
        $fields{$ghdr} = $arg;
      }
    }
    elsif($hdrmulti ne "")
    {
      $fields{$hdrmulti} .= $_;
    }

    # Grab a few fields out of the envelope as it flies by
    # 8/25/99 ehl: Grab these fields only out of the envelope, not
    # any other multiline field.
    if($hdrmulti eq "envelope" &&
       ($hdr eq "Reply-To" || $hdr eq "From" || $hdr eq "X-GNATS-Notify"))
    {
      $arg = fix_email_addrs($arg);
      $fields{$hdr} = $arg;
      #print "storing, hdr = $hdr, arg = $arg\n";
    }
  }

  # 5/8/99 kenstir: To get the reporter's email address, only
  # $fields{'Reply-to'} is consulted.  Initialized it from the 'From'
  # header if it's not set, then discard the 'From' header.
  $fields{'Reply-To'} = $fields{'Reply-To'} || $fields{'From'};
  delete $fields{'From'};

  # Ensure that the pseudo-fields are initialized to avoid perl warnings.
  $fields{'X-GNATS-Notify'} ||= '';

  # 3/30/99 kenstir: For some reason Unformatted always ends up with an
  # extra newline here.
  $fields{'Unformatted'} =~ s/\n$//;

  # Decode attachments stored in Unformatted field.
  my $any_attachments = 0;
  if (can_do_mime()) {
    my(@attachments) = split(/$attachment_delimiter/, $fields{'Unformatted'});
    # First element is any random text which precedes delimited attachments.
    $fields{'Unformatted'} = shift(@attachments);
    foreach $attachment (@attachments) {
      warn "att=>$attachment<=\n" if $debug;
      $any_attachments = 1;
      add_decoded_attachment_to_pr(\%fields, decode_attachment($attachment));
    }
  }

  if ($debug) {
    warn "--- parsepr fields ----\n";
    my %fields_copy = %fields;
    foreach (@fieldnames)
    {
      warn "$_ =>$fields_copy{$_}<=\n";
      delete $fields_copy{$_}
    }
    warn "--- parsepr pseudo-fields ----\n";
    foreach (sort keys %fields_copy) {
      warn "$_ =>$fields_copy{$_}<=\n";
    }
    warn "--- parsepr attachments ---\n";
    my $aref = $fields{'attachments'} || [];
    foreach $href (@$aref) {
      warn "    ----\n";
      while (($k,$v) = each %$href) {
        warn "    $k =>$v<=\n";
      }
    }
  }

  return %fields;
}

# unparsepr -
#     Turn PR fields hash into a multi-line string.
#
#     The $purpose arg controls how things are done.  The possible values
#     are:
#         'send'    - PR will be submitted as a new PR via email
#         'gntasd'  - PR will be filed using gnatsd; proper '.' escaping done
#         'test'    - we're being called from the regression tests
sub unparsepr
{
  my($purpose, %fields) = @_;
  my($tmp, $text);
  my $debug = 0;

  # First create or reconstruct the Unformatted field containing the
  # attachments, if any.
  $fields{'Unformatted'} ||= ''; # Default to empty.
  warn "unparsepr 1 =>$fields{'Unformatted'}<=\n" if $debug;
  my $array_ref = $fields{'attachments'};
  foreach $hash_ref (@$array_ref) {
    my $attachment_data = $$hash_ref{'original_attachment'};
    # Deleted attachments leave empty hashes behind.
    next unless defined($attachment_data);
    $fields{'Unformatted'} .= $attachment_delimiter . $attachment_data;
  }
  warn "unparsepr 2 =>$fields{'Unformatted'}<=\n" if $debug;

  # Reconstruct the text of the PR into $text.
  $text = $fields{'envelope'};
  foreach (@fieldnames)
  {
    # Do include Unformatted field in 'send' operation, even though
    # it's excluded.  We need it to hold the file attachment.
    #next if($purpose eq "send" && $fieldnames{$_} & $SENDEXCLUDE);
    next if(($purpose eq 'send')
            && ($fieldnames{$_} & $SENDEXCLUDE)
            && ($_ ne 'Unformatted'));
    if($fieldnames{$_} & $MULTILINE)
    {
      # Lines which begin with a '.' need to be escaped by another '.'
      # if we're feeding it to gnatsd.
      $tmp = $fields{$_};
      $tmp =~ s/^[.]/../gm
            if ($purpose eq 'gnatsd');
      $text .= sprintf(">$_:\n%s", $tmp);
    }
    else
    {
      # Format string derived from gnats/pr.c.
      $text .= sprintf("%-16s %s\n", ">$_:", $fields{$_});
    }
  }
  return $text;
}

sub lockpr
{
  my($pr, $user) = @_;
  #print "<pre>locking $pr $user\n</pre>";
  return parsepr(client_cmd("lock $pr $user"));
}

sub unlockpr
{
  my($pr) = @_;
  #print "<pre>unlocking $pr\n</pre>";
  client_cmd("unlk $pr");
}

sub readpr
{
  my($pr) = @_;
  my(@result) = client_cmd("full $pr");

  if ($gnats::ERRSTR) {
    print_gnatsd_error($gnats::ERRSTR);
    client_exit();
    exit();
  }

  return parsepr(@result);
}

# interested_parties -
#     Get list of parties to notify about a PR change.
#
#     Returns hash in array context; string of email addrs otherwise.
sub interested_parties
{
  my($pr, $include_gnats_addr, %fields) = @_;

  # Gnats 3.110 has some problems in MLPR --
  # * it includes the category's responsible person (even if that person
  #   is not responsible for this PR)
  # * it does not include the PR's responsible person
  # * it does not include the Reply-To or From
  #
  # So for now, don't use it.  However, for versions after 3.110 my
  # patch to the MLPR command should be there and this can be fixed.

  my(@people);
  my $person;
  my $list;

  ## Get list from MLPR command.
  #@people = client_cmd("mlpr $pr");
  # Ignore intro message
  #@people = grep(!/Addresses to notify/, @people);

  # Get list of people by constructing it ourselves.
  @people = ();
  my(@prospect_list) = ($fields{'Reply-To'},
                        $fields{'Responsible'},
                        $fields{'X-GNATS-Notify'},
                        $category_notify{$fields{'Category'}},
                        $submitter_contact{$fields{'Submitter-Id'}},
                        $submitter_notify{$fields{'Submitter-Id'}});
  push(@prospect_list, $config{'GNATS_ADDR'})
        if $include_gnats_addr;
  foreach $list (@prospect_list) {
    if (defined($list)) {
      foreach $person (split(/,/, $list)) {
        push(@people, $person) if $person;
      }
    }
  }

  # Expand any unexpanded addresses, and build up the %addrs hash.
  my(%addrs) = ();
  my $addr;
  foreach $person (@people)
  {
    $addr = praddr($person) || $person;
    $addrs{$addr} = 1;
  }
  return wantarray ? %addrs : join(', ', keys(%addrs));
}

# praddr -
#     Return email address of responsible person, or undef if not found.
sub praddr
{
  my $person = shift;
  # Done this way to avoid -w warning
  my $addr = exists($responsible_address{$person})
        ? $responsible_address{$person} : undef;
}

# login_page_javascript -
#     Returns some Javascript code to test if cookies are being accepted.
#
sub login_page_javascript
{
  my $ret = q{
<SCRIPT LANGUAGE="JavaScript" TYPE="text/javascript">
//<!-- 
// JavaScript courtesy of webcoder.com.

function getCookie(name) {
    var cname = name + "=";               
    var dc = document.cookie;             
    if (dc.length > 0) {              
        begin = dc.indexOf(cname);       
        if (begin != -1) {           
            begin += cname.length;       
            end = dc.indexOf(";", begin);
            if (end == -1) end = dc.length;
            return unescape(dc.substring(begin, end));
        } 
    }
    return null;
}

function setCookie(name, value, expires) {
    document.cookie = name + "=" + escape(value) + "; path=/" +
        ((expires == null) ? "" : "; expires=" + expires.toGMTString());
}

function delCookie(name) {
    document.cookie = name + "=; path=/; expires=Thu, 01-Jan-70 00:00:01 GMT";
}

exp = new Date();
exp.setTime(exp.getTime() + (1000 * 60 * 60)); // +1 hour
setCookie("gnatsweb-test-cookie", "whatever", exp);
val = getCookie("gnatsweb-test-cookie");
delCookie("gnatsweb-test-cookie");
if (val == null) {
    document.write("<h2>Warning: your browser is not accepting cookies!</h2>"
        + "Gnatsweb requires cookies to keep track of your login and other "
        + "information.  Please enable cookies before pressing the "
        + "<tt>login</tt> button.");
}

//-->
</SCRIPT>
  };
}

# login_page -
#     Show the login page.
#
#     If $return_url passed in, then we are showing the login page because
#     the user failed to login.  In that case, when the login is
#     successful, we want to redirect to the given url.  For example, if a
#     user follows a ?cmd=view url, but hasn't logged in yet, then we want
#     to forward him to the originally requested url after logging in.
#
sub login_page
{
  my($return_url, $err_msg) = @_;

  my $page = 'Login';
  print_header();
  page_start_html($page);
  page_heading($page, 'Login');

  # A previous error gets first billing.
  if ($err_msg) {
    print_gnatsd_error($err_msg);
  }

  # Inside the javascript a cookie warning can be printed.
  print login_page_javascript();

  # Connect to server.
  connect_to_gnatsd();

  # Get list of database aliases.
  my(@dbs) = client_cmd("dbla");
  my(@mydbs) = cb('list_databases', @dbs);
  if(defined($mydbs[0])) {
    @dbs = @mydbs;
  }

  # Get a default username and password.
  # Lousy assumption alert!  Assume that if the site is requiring browser
  # authentication (REMOTE_USER is defined), then their gnats passwords
  # are not really needed; use the username as the default.
  my $def_user = $db_prefs{'user'} || $ENV{'REMOTE_USER'};
  my $def_password = $db_prefs{'password'} || $ENV{'REMOTE_USER'};

  # Print the login form.
  print $q->start_form(),
        "<table>",
        "<tr>\n<td>User Name:</td>\n<td>",
        $q->textfield(-name=>'user',
                      -size=>20,
		      -default=>$def_user),
        "</td>\n</tr>\n<tr>\n<td>Password:</td>\n<td>",
        $q->password_field(-name=>'password',
                           -value=>$def_password,
                           -size=>20),
	"</td>\n</tr>\n<tr>\n<td>Database:</td>\n<td>",
	$q->popup_menu(-name=>'database',
	               -values=>\@dbs,
                       -default=>$global_prefs{'database'}),
        "</td>\n</tr>\n</table>";
  print $q->hidden('return_url', $return_url)
        if $return_url;
  print $q->submit('cmd','login'),
        $q->end_form();

  page_footer($page);
  page_end_html($page);
}

sub debug_print_all_cookies
{
  # Debug: print all our cookies into server log.
  warn "================= all cookies ===================================\n";
  my @c;
  $i = 0;
  foreach my $y ($q->cookie())
  {
    @c = $q->cookie($y);
    warn "got cookie: length=", scalar(@c), ": $y =>@c<=\n";
    $i += length($y);
  }
  @c = $q->raw_cookie();
  warn "debug 0.5: @c:\n";
  warn "debug 0.5: total size of raw cookies: ", length("@c"), "\n";
}

# set_pref -
#     Set the named preference.  Param values override cookie values, and
#     don't set it if we end up with an undefined value.
#
sub set_pref
{
  my($pref_name, $pref_hashref, $cval_hashref) = @_;
  my $val = $q->param($pref_name) || $$cval_hashref{$pref_name};
  $$pref_hashref{$pref_name} = $val
        if defined($val);
}

# init_prefs -
#     Initialize global_prefs and db_prefs from cookies and params.
#
sub init_prefs
{
  my $debug = 0;

  if ($debug) {
    debug_print_all_cookies();
    # Don't 'use Data::Dumper' because that always loads and causes
    # compile-time errors for those who don't have this module.
    require Data::Dumper;
    $Data::Dumper::Terse = $Data::Dumper::Terse = 1; # avoid -w warning
    warn "-------------- init_prefs -------------------\n";
  }

  # Global prefs.
  my %cvals = $q->cookie('gnatsweb-global');
  %global_prefs = ();
  set_pref('database', \%global_prefs, \%cvals);
  set_pref('email', \%global_prefs, \%cvals);
  set_pref('Originator', \%global_prefs, \%cvals);
  set_pref('Submitter-Id', \%global_prefs, \%cvals);

  # columns is treated differently because it's an array which is stored
  # in the cookie as a joined string.
  if ($q->param('columns')) {
    my(@columns) = $q->param('columns');
    $global_prefs{'columns'} = join(' ', @columns);
  }
  elsif (defined($cvals{'columns'})) {
    $global_prefs{'columns'} = $cvals{'columns'};
  }

  # DB prefs.
  my $database = $global_prefs{'database'} || '';
  %cvals = $q->cookie("gnatsweb-db-$database");
  %db_prefs = ();
  set_pref('user', \%db_prefs, \%cvals);
  set_pref('password', \%db_prefs, \%cvals);

  # Debug.
  warn "global_prefs = ", Data::Dumper::Dumper(\%global_prefs) if $debug;
  warn "db_prefs = ", Data::Dumper::Dumper(\%db_prefs) if $debug;
}

# create_global_cookie -
#     Create cookie from %global_prefs.
#
sub create_global_cookie
{
  my $debug = 0;
  # As of gnatsweb-2.6beta, the name of this cookie changed.  This was
  # done so that the old cookie would not be read.
  my $cookie = $q->cookie(-name => 'gnatsweb-global',
                          -value => \%global_prefs,
                          -path => $global_cookie_path,
                          -expires => $global_cookie_expires);
  warn "storing cookie: $cookie\n" if $debug;
  return $cookie;
}

#
# MAIN starts here:
#
sub main
{
  # Load gnatsweb-site.pl if present.  Die if there are errors;
  # otherwise the person who wrote gnatsweb-site.pl will never know it.
  do './gnatsweb-site.pl' if (-e './gnatsweb-site.pl');
  die $@ if $@;

  # Make sure nobody tries to swamp our server with a huge file attachment.
  # Has to happen before 'new CGI'.
  $CGI::POST_MAX = $site_post_max if defined($site_post_max);

  # Create the query object.  Check to see if there was an error, which
  # happens if the post exceeds POST_MAX.
  $q = new CGI;
  if ($q->cgi_error())
  {
    print $q->header(-status=>$q->cgi_error());
          $q->start_html('Error');
    page_heading('Initialization failed', 'Error');
    print $q->h3('Request not processed: ', $q->cgi_error());
    exit();
  }

  $sn = $q->script_name;
  my $cmd = $q->param('cmd') || ''; # avoid perl -w warning

  ### Cookie-related code must happen before we print the HTML header.

  # What to use as the -path argument in cookies.  Using '' (or omitting
  # -path) causes CGI.pm to pass the basename of the script.  With that
  # setup, moving the location of gnatsweb.pl causes it to see the old
  # cookies but not be able to delete them.
  $global_cookie_path = '/';
  $global_cookie_expires = '+30d';
  init_prefs();

  # Big old switch to handle commands.
  if($cmd eq 'store query')
  {
    store_query();
    exit();
  }
  elsif($cmd eq 'delete stored query')
  {
    delete_stored_query();
    exit();
  }
  elsif($cmd eq 'submit stored query')
  {
    submit_stored_query();
    exit();
  }
  elsif($cmd eq 'login')
  {
    # User came from login page; store user/password/database in cookies,
    # and proceed to the appropriate page.
    my $global_cookie = create_global_cookie();
    my $db = $global_prefs{'database'};
    my $db_cookie = $q->cookie(-name => "gnatsweb-db-$db",
                               -value => \%db_prefs,
                               -path => $global_cookie_path,
                               -expires => $global_cookie_expires);
    my $expire_old_cookie = $q->cookie(-name => 'gnatsweb',
                               -value => 'does not matter',
                               -path => $global_cookie_path,
                               #-path was not used for gnatsweb 2.5 cookies
                               -expires => '-1d');
    my $url = $q->param('return_url') || $q->url();
    # 11/14/99 kenstir: For some reason setting cookies during a redirect
    # didn't work; got a 'page contained no data' error from NS 4.7.  This
    # technique did work for me in a small test case but not in gnatsweb.
    # 11/27/99 kenstir: Use zero-delay refresh all the time.
    # 1/15/2000 kenstir: Note that the CGI.pm book says that -cookie may
    # be ignored during a redirect.
    #print $q->redirect(-location => $url,
    #                   -cookie => [$global_cookie, $db_cookie]);
    # So, this is sort of a lame replacement; a zero-delay refresh.
    print $q->header(-Refresh => "0; URL=$url",
                     -cookie => [$global_cookie, $db_cookie,
                                 $expire_old_cookie]),
          $q->start_html();
    my $debug = 0;
    if ($debug) {
      print "<h3>debugging params</h3><font size=1><pre>";
      my($param,@val);
      foreach $param (sort $q->param()) {
        @val = $q->param($param);
        printf "%-12s %s\n", $param, $q->escapeHTML(join(' ', @val));
      }
      print "</pre></font><hr>\n";
    }
    # Add a link to the new URL. In case the refresh/redirect above did not
    # work, at least the user can select the link manually.
    print $q->h3("Hold on... Redirecting...<br>".
                 "In case it does not work automatically, please follow ".
                 "<a href=\"$url\">this link</a>."),
    $q->end_html();
    exit();
  }
  elsif($cmd eq 'login again')
  {
    # User is specifically requesting to login again.
    login_page();
    exit();
  }
  elsif(!$global_prefs{'database'}
        || !$db_prefs{'user'} || !$db_prefs{'password'})
  {
    # We don't have username/password/database; give login page then
    # redirect to the url they really want (self_url).
    login_page($q->self_url());
    exit();
  }
  elsif($cmd eq 'submit')
  {
    # User is submitting a new PR.  Store cookie because email address may
    # have changed.  This facilitates entering bugs the next time.
    print $q->header(-cookie => create_global_cookie());
    initialize();
    submitnewpr();
    exit();
  }
  elsif($cmd eq 'submit query')
  {
    # User is querying.  Store cookie because column display list may
    # have changed.
    print $q->header(-cookie => create_global_cookie());
    initialize();
    submitquery();
    exit();
  }
  elsif($cmd =~ /download attachment (\d+)/)
  {
    # User is downloading an attachment.  Must initialize but not print header.
    initialize();
    download_attachment($1);
    exit();
  }
  elsif($cmd eq 'create')
  {
    initialize();
    sendpr();
  }
  elsif($cmd eq 'view')
  {
    initialize();
    view(0);
  }
  elsif($cmd eq 'view audit-trail')
  {
    initialize();
    view(1);
  }
  elsif($cmd eq 'edit')
  {
    initialize();
    edit();
  }
  elsif($cmd eq 'submit edit')
  {
    initialize();
    submitedit();
  }
  elsif($cmd eq 'query')
  {
    print $q->header();
    initialize();
    query_page();
  }
  elsif($cmd eq 'advanced query')
  {
    print $q->header();
    initialize();
    advanced_query_page();
  }
  elsif($cmd eq 'help')
  {
    print $q->header();
    help_page();
  }
  elsif (cb('cmd', $cmd)) {
    ; # cmd was handled by callback
  }
  else {
    initialize();
    main_page();
  }

  client_exit();
  exit();
}

# To make this code callable from another source file, set $suppress_main.
$suppress_main ||= 0;
main() unless $suppress_main;

# Emacs stuff -
#
# Local Variables:
# perl-indent-level:2
# perl-continued-brace-offset:-6
# perl-continued-statement-offset:6
# End:

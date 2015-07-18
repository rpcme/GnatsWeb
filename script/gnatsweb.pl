#!/usr/bin/perl -w
#
# Gnatsweb - web front-end to GNATS
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
# $Id: gnatsweb.pl,v 1.124.2.2 2003/07/29 12:24:22 yngves Exp $
#

use strict;

# static global configuration switches and values.  set at the top of
# this program, but overridable in gnatsweb-site.pl
use vars qw($site_gnats_host $site_gnats_port
$site_gnatsweb_server_auth $site_no_gnats_passwords
$no_create_without_access $site_mail_domain $site_post_max
$description_in_view $help_page_path $site_banner_text
$site_banner_background $site_banner_foreground
$site_button_foreground $site_button_background $site_stylesheet
$include_audit_trail $popup_menu_becomes_obnoxious
$scrolling_menu_default_size $site_background
$site_required_field_color $use_temp_db_prefs_cookie
$global_cookie_expires $global_cookie_path $textwidth
$site_allow_remote_debug $attachment_delimiter %mark_urls
$gnats_info_top %site_pr_submission_address $VERSION);

# dynamic configuration switches, set during initial gnatsd
# communication and general setup
use vars qw($script_name $global_no_cookies $global_list_of_dbs
$client_cmd_debug $reply_debug $access_level);

# these vars are used for error handling in communications
# with gnatsd
use vars qw($client_would_have_exited $suppress_client_exit);

# the following variable needs to be global in order to make gnatsweb
# callable from another source file. Used for 'make test...'
use vars qw($suppress_main);

# global variables containing most of the info from the gnats-adm
# directory.  these should probably be rolled into one giant hash.
# in fact, this code should be set up so that gnatsweb under mod_perl
# could cache all this hooey...
use vars qw(%category_notify @submitter_id %submitter_contact
%submitter_complete %submitter_notify @responsible
%responsible_address %category_desc %responsible_complete %fielddata
@fieldnames %responsible_fullname);

# the information from the user cookies.
# db_prefs just has username & password
# global_prefs has email address, default columns for query results
# SUBMITTER_ID_FIELD default value and ORIGINATOR_FIELD default value
# i think that the columns info should be moved to db_prefs, and the
# code suitably munged so that a user could have different column
# prefs for different databases.
use vars qw(%global_prefs %db_prefs);

# the CGI object
use vars '$q';

# i couldn't manage to get these two beaten into shape as
# lexical variables.  maybe next time...
use vars qw($pr %fields);

#-----------------------------------------------------------------------------
# what do you call the file containing the site-specific customizations?
# you could, i suppose, by dint of creative programming, have different
# config files for different databases, or some such madness...
my $gnatsweb_site_file = './gnatsweb-site.pl';

# Site-specific customization -
#
#     DO NOT EDIT THESE VARIABLES HERE!
#
#     Instead, put them in a file called 'gnatsweb-site.pl' in the
#     same directory.  That way, when a new version of gnatsweb is
#     released, you won't need to edit them again.
#

# Info about your gnats host.
$site_gnats_host = 'localhost';
$site_gnats_port = 1529;

# is your installation of gnatsweb set up with server authentication?
# if you want to set up a more tightly secured installation, you can
# have the web server do authentication (against an htpasswd file,
# LDAP server, or some third-party system).  this will set the
# REMOTE_USER environment variable with the correct user id.  with
# this switch set, the "logout" button is replaced by a "change
# database" button.
$site_gnatsweb_server_auth = 0;

# or does it merely ignore the gnats password?  the gnats network mode
# is quite cavalier about passwords, and some sites may elect not to
# use gnats passwords.  if so, there's no point in gnatsweb asking for
# them.  if this switch is set, the login page does not prompt for a
# password.  this means that anyone can pretend to be anyone, but
# since the gnats command line tools are hardly more secure, it's not
# a big deal...
$site_no_gnats_passwords = 0;

# set a minimum access level for access to the create function
# (this is probably only meaningful if gnatsweb is the only interface
#  to your gnats installation, since by default gnats allows *everyone*
#  to submit PRs)
# value must be a valid gnatsd.h access level, see %LEVEL_TO_CODE below.
#$no_create_without_access = 'edit';
$no_create_without_access = '';

# mail domain for responsible field -- bare user-ids in responsible
# fields will have this added to the end to create a sane mailto: link.
# you must put the '@' sign at the beginning of the string
$site_mail_domain = '@yourdomain.here';

# hash of addresses that your site uses for submission of PRs
# if this is defined for a given database, the edit and view pages
# will include a link "submit a follup by email" -- a mailto: this
# address and the Reply-To address of the PR.
#%site_pr_submission_address = ('default'  => 'bugs@example.com',
#			        'other_db' => 'other-bugs@example.com');
%site_pr_submission_address = ();

# the maximum size posting we'll accept
$site_post_max = 1024 * 1024;

# show field descriptions on the view PR page?  this tends to look
# messy, so by default we only show them on the create and edit pages.
$description_in_view = 0;

# path to the gnatsweb help page.  this is the file that will be
# returned when the user clicks on the Help button.
$help_page_path = './gnatsweb.html';

# Name you want in the page banner and banner colors.
$site_banner_text = 'GNU Gnatsweb';
$site_banner_background = '#000000';
$site_banner_foreground = '#ffffff';
$site_button_background = '#000000';
$site_button_foreground = '#ffffff';

# Uncomment the following line and insert stylesheet URL in order to
# link all generated pages to an external stylesheet. Both absolute
# and relative URLs are supported.
#$site_stylesheet='http://url.of/stylesheet';
$site_stylesheet = undef;

# When $include_audit_trail is set to 1, the Audit-Trail will be
# visible by default in the View PR screen.  Sites that expect large
# Audit-Trails, i.e. lot of mail back and forth etc., will want to set
# this to 0.
$include_audit_trail = 1;

# when we have more than this many items, use a scrolling list
# instead of a popup
$popup_menu_becomes_obnoxious = 20;

# default size for scrolling lists.  overridden for some fields
$scrolling_menu_default_size = 3;

# Page background color -- not used unless defined.
#$site_background = '#c0c0c0';
$site_background = undef;

# Color to use for marking the names of required fields on the Create
# PR page.
$site_required_field_color = '#ff0000';

# control the mark_urls routine, which "htmlifies" PRs for view_pr.
# it adds a lot of usability, but can be slow for huge (100K+) fields.
# urls = make links clickable
# emails = make addresses mailto: links
# prs = make PR numbers links to gnatsweb
# max_length = strings larger than this will not be processed
%mark_urls = (
	     'urls'       => 1,
	     'emails'     => 1,
	     'prs'        => 1,
	     'max_length' => 1024*100,
	    );

# Use temporary cookie for login information?  Gnatsweb stores login
# information in the db_prefs cookie in the user's browser.  With
# $use_temp_db_prefs_cookie set to 1, the cookie is stored in the
# browser, not on disk.  Thus, the cookie gets deleted when the user
# exits the browser, improving security.  Otherwise, the cookie will
# remain active until the expiration date specified by
# $global_cookie_expires arrives.
$use_temp_db_prefs_cookie = 0;

# What to use as the -path argument in cookies.  Using '' (or omitting
# -path) causes CGI.pm to pass the basename of the script.  With that
# setup, moving the location of gnatsweb.pl causes it to see the old
# cookies but not be able to delete them.
$global_cookie_path = '/';
$global_cookie_expires = '+30d';

# width of text fields
$textwidth = 60;

# do we allow users to spy on our communications with gnatsd?
# if this is set, setting the 'debug' param will display communications
# with gnatsd to the browser.  really only useful to gnats administrators.
$site_allow_remote_debug = 1;

# delimiter to use within PRs for storage of attachments
# if you change this, all your old PRs with attachments will
# break...
$attachment_delimiter = "----gnatsweb-attachment----\n";

# where to get help -- a web site with translated info documentation
$gnats_info_top = 'http://www.gnu.org/software/gnats/gnats_toc.html';

# end customization
#-----------------------------------------------------------------------------

# Use CGI::Carp first, so that fatal errors come to the browser, including
# those caused by old versions of CGI.pm.
use CGI::Carp qw/fatalsToBrowser/;
# 8/22/99 kenstir: CGI.pm-2.50's file upload is broken.
# 9/19/99 kenstir: CGI.pm-2.55's file upload is broken.
use CGI 2.56 qw/-nosticky/;
use Socket;
use IO::Handle;
use Text::Tabs;

# Version number + RCS revision number
$VERSION = '4.00';
my $REVISION = (split(/ /, '$Revision: 1.124.2.2 $ '))[1];
my $GNATS_VERS = '0.0';

# bits in fieldinfo(field, flags) has (set=yes not-set=no)
my $SENDINCLUDE  = 1;   # whether the send command should include the field
my $REASONCHANGE = 2;   # whether change to a field requires reason
my $READONLY  = 4;      # if set, can't be edited
my $AUDITINCLUDE = 8;   # if set, save changes in Audit-Trail
my $SENDREQUIRED = 16;  # whether the send command _must_ include this field

# The possible values of a server reply type.  $REPLY_CONT means that there
# are more reply lines that will follow; $REPLY_END Is the final line.
my $REPLY_CONT = 1;
my $REPLY_END = 2;

#
# Various PR field names that should probably not be referenced in here.
#
# Actually, the majority of uses are probably OK--but we need to map
# internal names to external ones.  (All of these field names correspond
# to internal fields that are likely to be around for a long time.)
#
my $CATEGORY_FIELD = 'Category';
my $SYNOPSIS_FIELD = 'Synopsis';
my $SUBMITTER_ID_FIELD = 'Submitter-Id';
my $ORIGINATOR_FIELD = 'Originator';
my $AUDIT_TRAIL_FIELD = 'Audit-Trail';
my $RESPONSIBLE_FIELD = 'Responsible';
my $LAST_MODIFIED_FIELD = 'Last-Modified';
my $NUMBER_FIELD = 'builtinfield:Number';
my $STATE_FIELD = 'State';
my $UNFORMATTED_FIELD = 'Unformatted';
my $RELEASE_FIELD = 'Release';

# we use the access levels defined in gnatsd.h to do
# access level comparisons
#define ACCESS_UNKNOWN  0x00
#define ACCESS_DENY     0x01
#define ACCESS_NONE     0x02
#define ACCESS_SUBMIT   0x03
#define ACCESS_VIEW     0x04
#define ACCESS_VIEWCONF 0x05
#define ACCESS_EDIT     0x06
#define ACCESS_ADMIN    0x07
my %LEVEL_TO_CODE = ('deny' => 1,
		     'none' => 2,
		     'submit' => 3,
		     'view' => 4,
		     'viewconf' => 5,
		     'edit' => 6,
		     'admin' => 7);


my $CODE_GREETING = 200;
my $CODE_CLOSING = 201;
my $CODE_OK = 210;
my $CODE_SEND_PR = 211;
my $CODE_SEND_TEXT = 212;
my $CODE_NO_PRS_MATCHED = 220;
my $CODE_NO_ADM_ENTRY = 221;
my $CODE_PR_READY = 300;
my $CODE_TEXT_READY = 301;
my $CODE_INFORMATION = 350;
my $CODE_INFORMATION_FILLER = 351;
my $CODE_NONEXISTENT_PR = 400;
my $CODE_EOF_PR = 401;
my $CODE_UNREADABLE_PR = 402;
my $CODE_INVALID_PR_CONTENTS = 403;
my $CODE_INVALID_FIELD_NAME = 410;
my $CODE_INVALID_ENUM = 411;
my $CODE_INVALID_DATE = 412;
my $CODE_INVALID_FIELD_CONTENTS = 413;
my $CODE_INVALID_SEARCH_TYPE = 414;
my $CODE_INVALID_EXPR = 415;
my $CODE_INVALID_LIST = 416;
my $CODE_INVALID_DATABASE = 417;
my $CODE_INVALID_QUERY_FORMAT = 418;
my $CODE_NO_KERBEROS = 420;
my $CODE_AUTH_TYPE_UNSUP = 421;
my $CODE_NO_ACCESS = 422;
my $CODE_LOCKED_PR = 430;
my $CODE_GNATS_LOCKED = 431;
my $CODE_GNATS_NOT_LOCKED = 432;
my $CODE_PR_NOT_LOCKED = 433;
my $CODE_CMD_ERROR = 440;
my $CODE_WRITE_PR_FAILED = 450;
my $CODE_ERROR = 600;
my $CODE_TIMEOUT = 610;
my $CODE_NO_GLOBAL_CONFIG = 620;
my $CODE_INVALID_GLOBAL_CONFIG = 621;
my $CODE_NO_INDEX = 630;
my $CODE_FILE_ERROR = 640;

$| = 1; # flush output after each print

# A couple of internal status variables:
# Have the HTTP header, start_html, heading already been printed?
my $print_header_done = 0;
my $page_start_html_done = 0;
my $page_heading_done = 0;

sub gerror
{
  my($text) = @_;
  my $page = 'Error';
  print_header();
  page_start_html($page);
  page_heading($page, 'Error');
  print "<p>$text\n</p>\n";
}

# Close the client socket and exit.  The exit can be suppressed by:
# setting $suppress_client_exit = 1 in the calling routine (using local)
# [this is only set in edit_pr and the initial login section]
sub client_exit
{
  if (! defined($suppress_client_exit))
  {
    close(SOCK);
    exit();
  }
  else
  {
    $client_would_have_exited = 1;
  }
}

sub server_reply
{
  my($state, $text, $type);
  my $raw_reply = <SOCK>;
  if(defined($reply_debug))
  {  
    print_header();
    print "<tt>server_reply: $raw_reply</tt><br>\n";
  }
  if($raw_reply =~ /(\d+)([- ]?)(.*$)/)
  {
    $state = $1;
    $text = $3;
    if($2 eq '-')
    {
      $type = $REPLY_CONT;
    }
    else
    {
      if($2 ne ' ')
      {
        gerror("bad type of reply from server");
      }
      $type = $REPLY_END;
    }
    return ($state, $text, $type);
  }
  else
  {
    # unparseable reply.  send back the raw reply for error reporting
    return (undef, undef, undef, $raw_reply);
  }
}

sub read_server
{
  my(@text);

  while(<SOCK>)
  {
    if(defined($reply_debug))
    {
      print_header();
      print "<tt>read_server: $_</tt><br>\n";
    }
    if(/^\.\r/)
    {
      return @text;
    }
    $_ =~ s/[\r\n]//g;
    # Lines which begin with a '.' are escaped by gnatsd with another '.'
    $_ =~ s/^\.\././;
    push(@text, $_);
  }
}

sub get_reply
{
  my @rettext = ();
  my ($state, $text, $type, $raw_reply);

  do {
    ($state, $text, $type, $raw_reply) = server_reply();

    unless ($state) {
	# gnatsd has returned something unparseable
	if ($reply_debug || $client_cmd_debug) {
	    gerror("unparseable reply from gnatsd: $raw_reply")
	} else {
	    gerror("Unparseable reply from gnatsd");
	}
	warn("gnatsweb: unparseable gnatsd output: $raw_reply; user=$db_prefs{'user'}, db=$global_prefs{'database'}; stacktrace: ", print_stacktrace());
	return;
    }

    if($state == $CODE_GREETING)
    {
      push(@rettext, $text);
      # nothing
    }
    elsif($state == $CODE_OK || $state == $CODE_GREETING 
          || $state == $CODE_CLOSING)
    {
      push(@rettext, $text);
      # nothing
    }
    elsif($state == $CODE_PR_READY || $state == $CODE_TEXT_READY)
    {
      @rettext = read_server();
    }
    elsif($state == $CODE_SEND_PR || $state == $CODE_SEND_TEXT)
    {
      # nothing, tho it would be better...
    }
    elsif($state == $CODE_INFORMATION_FILLER)
    {
      # nothing
    }
    elsif($state == $CODE_INFORMATION)
    {
      push(@rettext, $text);
    }
    elsif($state == $CODE_NO_PRS_MATCHED)
    {
      gerror("Return code: $state - $text");
      page_footer('Error');
      page_end_html('Error');
      client_exit();
      push(@rettext, $text);
    }
    elsif($state >= 400 && $state <= 799)
    {
      if ($state == $CODE_NO_ACCESS) 
      {
	if ($site_gnatsweb_server_auth) {
	    $text = " You do not have access to database \"$global_prefs{'database'}\"";
	} else {
	    $text = " Access denied (login again & check usercode/password)";
       }
      }
      gerror("Return code: $state - $text");
      warn("gnatsweb: gnatsd error $state-$text; user=$db_prefs{'user'}, db=$global_prefs{'database'}; stacktrace: ", print_stacktrace());
      page_footer('Error');
      page_end_html('Error');
      client_exit();
      push(@rettext, $text);
    }
    else
    {
      # gnatsd returned a state, but we don't know what it is
      push(@rettext, $text);
      gerror("Cannot understand gnatsd output: $state '$text'");
      warn("gnatsweb: gnatsd error $state-$text; user=$db_prefs{'user'}, db=$global_prefs{'database'}; stacktrace: ", print_stacktrace());
    }
  } until ($type != $REPLY_CONT);
  return @rettext;
}


# print a stacktrace
# used by the various warn() statments to emit useful diagnostics
# to the web server error logs.
sub print_stacktrace {
    my @stacktrace;
    my $i = 1;
    while ( my($subroutine) = (caller($i++))[3] ) {
 	push(@stacktrace, $subroutine);
    }
    return 'In: ' . join(' <= ', @stacktrace);
}

sub multiselect_menu
{
  my $size = @{$_[1]} < 4 ? @{$_[1]} : 4;
  return $q->scrolling_list(-name=>$_[0], -values=>$_[1], -size=>$size,
                            -multiple=>'true', -default=>$_[2]);
}

sub popup_or_scrolling_menu
{
  my $size=$_[3];
  if (!(defined $size))
  {
    $size = $scrolling_menu_default_size;
   }

# a hack to make responsible field easier to deal with when
# there are many names in the responsible file
  if ($_[0] =~ m/responsible/i) {
      $size = 5;
  }

  # put human readable values in the popup lists for common
  # gnats fields
  my $labels;
  if ($_[0] eq "Category") {
      $labels = \%category_desc;
  }
  elsif ($_[0] eq "Responsible") {
    $labels = \%responsible_complete;
  }
  elsif ($_[0] eq "Submitter-Id") {
    $labels = \%submitter_complete;
  }

  if ($#{$_[1]} >= $popup_menu_becomes_obnoxious)
  {
    return $q->scrolling_list (-name=>$_[0],
                               -size=>$size,
                               -values=>$_[1],
			        -labels=>$labels,
                               -default=>$_[2]);
  }
  else
  {
    return $q->popup_menu (-name=>$_[0],
                           -values=>$_[1],
			    -labels=>$labels,
                           -default=>$_[2]);

  }
}

# wrapper functions for formstart...
sub multipart_form_start
{
    formstart(1, @_);
}
sub form_start
{
    formstart(0, @_);
}

# workaround for an exceedingly dumb netscape bug.  we hates
# netscape...  this bug manifests if you click on the "create"
# button bar link (but not the grey button on the main page), submit a
# PR, then hit the back button (usually because you got an error).
# you're taken "back" to the same error page -- all the stuff you
# entered into the submission form is *gone*.  this is kind of annoying...
# (it also manifests if you click the edit link from the query results page.)
sub formstart
{
    # this bugfix is mostly lifted from the CGI.pm docs.  here's what they
    # have to say:
    #   When you press the "back" button, the same page is loaded, not
    #   the previous one.  Netscape's history list gets confused
    #   when processing multipart forms. If the script generates
    #   different pages for the form and the results, hitting the
    #   "back" button doesn't always return you to the previous page;
    #   instead Netscape reloads the current page. This happens even
    #   if you don't use an upload file field in your form.
    #
    #   A workaround for this is to use additional path information to
    #   trick Netscape into thinking that the form and the response
    #   have different URLs. I recommend giving each form a sequence
    #   number and bumping the sequence up by one each time the form
    #   is accessed:

    # should we do multipart?
    my $multi = shift;

    # in case the caller has some args to pass...
    my %args = @_;

    # if the caller has given an "action" arg, we don't do any
    # subterfuge.  let the caller worry about the bug...
    if (!exists $args{'-action'}) {
	# get sequence number and increment it
	my $s = $q->path_info =~ m{/(\d+)/?$};
	$s++;
	# Trick Netscape into thinking it's loading a new script:
	$args{-action} = $q->script_name . "/$s";
    }

    if ($multi) {
	print $q->start_multipart_form(%args);
    } else {
	print $q->start_form(%args);
    }

    return;
}

sub fieldinfo
{
    my ($fieldname, $member) = @_;
  return $fielddata{$fieldname}{$member};
}

sub isvalidfield
{
  return exists($fielddata{$_[0]}{'fieldtype'});
}

sub init_fieldinfo
{
  my $debug = 0;
  my $field;

  @fieldnames = client_cmd("list FieldNames");
  my @type = client_cmd ("ftyp ". join(" ",@fieldnames));
  my @desc = client_cmd ("fdsc ". join(" ",@fieldnames));
  my @flgs = client_cmd ("fieldflags ". join(" ",@fieldnames));
  my @fdflt = client_cmd ("inputdefault ". join(" ",@fieldnames));
  foreach $field (@fieldnames) {
    $fielddata{$field}{'flags'} = 0;
    $fielddata{$field}{'fieldtype'} = lc(shift @type);
    $fielddata{$field}{'desc'} = shift @desc;
    $fielddata{$field}{'fieldflags'} = lc(shift @flgs);
    if ($fielddata{$field}{'fieldflags'} =~ /requirechangereason/)
    {
      $fielddata{$field}{'flags'} |= $REASONCHANGE;
    }
    if ($fielddata{$field}{'fieldflags'} =~ /readonly/)
    {
      $fielddata{$field}{'flags'} |= $READONLY;
    }
    if ($fielddata{$field}{'fieldtype'} eq 'multienum')
    {
      my @response = client_cmd("ftypinfo $field separators");
      $response[0] =~ /'(.*)'/;
      $fielddata{$field}{'separators'} = $1;
      $fielddata{$field}{'default_sep'} = substr($1, 0, 1);
    }
    my @values = client_cmd ("fvld $field");
    $fielddata{$field}{'values'} = [@values];
    $fielddata{$field}{'default'} = shift (@fdflt);
    $fielddata{$field}{'default'} =~ s/\\n/\n/g;
    $fielddata{$field}{'default'} =~ s/\s$//;
  }
  foreach $field (client_cmd ("list InitialInputFields")) {
    $fielddata{$field}{flags} |= $SENDINCLUDE;
  }
  foreach $field (client_cmd ("list InitialRequiredFields")) {
    $fielddata{$field}{flags} |= $SENDREQUIRED;
  }
  if ($debug)
  {
    foreach $field (@fieldnames) {
      warn "name = $field\n";
      warn "  type   = $fielddata{$field}{'fieldtype'}\n";
      warn "  flags  = $fielddata{$field}{'flags'}\n";
      warn "  values = $fielddata{$field}{'values'}\n";
      warn "\n";
    }
  }
}

sub client_init
{
  my($iaddr, $paddr, $proto, $line, $length);
  if(!($iaddr = inet_aton($site_gnats_host)))
  {
    error_page("Unknown GNATS host '$site_gnats_host'",
               "Check your Gnatsweb configuration.");
    exit();
  }
  $paddr = sockaddr_in($site_gnats_port, $iaddr);

  $proto = getprotobyname('tcp');
  if(!socket(SOCK, PF_INET, SOCK_STREAM, $proto))
  {
    gerror("socket: $!");
    warn("gnatsweb: client_init error: $! ; user=$db_prefs{'user'}, db=$global_prefs{'database'}; stacktrace: ", print_stacktrace());
    exit();
  }
  if(!connect(SOCK, $paddr))
  {
    gerror("connect: $!");
    warn("gnatsweb: client_init error: $! ; user=$db_prefs{'user'}, db=$global_prefs{'database'}; stacktrace: ", print_stacktrace());
    exit();
  }
  SOCK->autoflush(1);
  get_reply();
}

# to debug:
#     local($client_cmd_debug) = 1;
#     client_cmd(...);
sub client_cmd
{
  my($cmd) = @_;
  my $debug = 0;
  print SOCK "$cmd\n";
  warn "client_cmd: $cmd" if $debug;
  if(defined($client_cmd_debug))
  {
    print_header();
    print "<br><tt>client_cmd: <pre>$cmd</pre></tt><br>\n";
  }
  return get_reply();
}


    # keep the "cached" value of $can_do_mime lexically scoped
do {
    my $can_do_mime;

    # Return true if module MIME::Base64 is available.  If available, it's
    # loaded the first time this sub is called.
    sub can_do_mime
      {
	  return $can_do_mime if (defined($can_do_mime));

	  eval 'use MIME::Base64;';
	  if ($@) {
	      warn "NOTE: Can't use file upload feature without MIME::Base64 module\n";
	      $can_do_mime = 0;
	  } else {
	      $can_do_mime = 1;
	  }
	  $can_do_mime;
      }
};

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
    warn("gnatsweb: attachment filename w/o attachment; user=$db_prefs{'user'}, db=$global_prefs{'database'}; stacktrace: ", print_stacktrace());
    die "Got attachment filename ($filename) but no attachment data!  Probably this is a programming error -- the form which submitted this data must be multipart/form-data (start_multipart_form()).";
  }
  if ($debug) {
    my ($k, $v);
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
    $att .= encode_base64($data);
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
  my ($envelope, $body) = split(/\n\n/, $att, 2);
  return $hash_ref unless ($envelope && $body);

  # Split mbox-like headers into (header, value) pairs, with a leading
  # "From_" line swallowed into USELESS_LEADING_ENTRY. Junk the leading
  # entry. Chomp all values.
  warn "decode_attachment: envelope=>$envelope<=\n" if $debug;
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
    warn("gnatsweb: unable to parse file attachment; user=$db_prefs{'user'}, db=$global_prefs{'database'}; stacktrace: ", print_stacktrace());
    die "Unable to parse file attachment";
  }

  # Parse filename.
  # Note: the extra \ before the " is just so that perl-mode can parse it.
  if ($$hash_ref{'Content-Disposition'} !~ /(\S+); filename=\"([^\"]+)\"/) {
    warn("gnatsweb: unable to parse file attachment Content-Disposition; user=$db_prefs{'user'}, db=$global_prefs{'database'}; stacktrace: ", print_stacktrace());
    die "Unable to parse file attachment Content-Disposition";
  }
  $$hash_ref{'filename'} = attachment_filename_tail($2);

  # Decode the data if encoded.
  if (exists($$hash_ref{'Content-Transfer-Encoding'})
      && $$hash_ref{'Content-Transfer-Encoding'} eq 'base64')
  {
    $$hash_ref{'data'} = decode_base64($body);
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
    print "Add a file attachment:<br />",
          $q->filefield(-name=>'attached_file',
                        -size=>50);
    # that's all we need to do if this is the sendpr page
    return if $mode eq 'sendpr';
  }

  # Print table of existing attachments.
  # Add column with delete button in edit mode.
  my $array_ref = $$fields_hash_ref{'attachments'};
  my $table_rows_aref = [];
  my $i = 0;
  foreach my $hash_ref (@$array_ref) {
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
    print "</td>\n</tr>\n";
  }
}

# The user has requested download of a particular attachment.
# Serve it up.
sub download_attachment
{
  my $attachment_number = shift;
  my($pr) = $q->param('pr');

  # strip out leading category (and any other non-digit trash) from $pr
  $pr =~ s/\D//g;

  if(!$pr) { 
      warn("gnatsweb: download_attachment called with no PR number; user=$db_prefs{'user'}, db=$global_prefs{'database'}; stacktrace: ", print_stacktrace());
      die "download_attachment called with no PR number"
  }

  my(%fields) = readpr($pr);
  my $array_ref = $fields{'attachments'};
  my $hash_ref = $$array_ref[$attachment_number];
  my $disp;

  # Internet Explorer 5.5 does not handle "content-disposition: attachment"
  # in the expected way. It needs a content-disposition of "file".
  ($ENV{'HTTP_USER_AGENT'} =~ "MSIE 5.5") ? ($disp = 'file') : ($disp = 'attachment');
  # Now serve the attachment, with the appropriate headers.
  print_header(-type => 'application/octet-stream',
               -content_disposition => "$disp; filename=\"$$hash_ref{'filename'}\"");
  print $$hash_ref{'data'};
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
  page_start_html($page);
  page_heading($page, 'Create Problem Report');

  print multipart_form_start(-name=>'PrForm'), "\n",
        hidden_db(),
	hidden_debug(),
        $q->span($q->submit('cmd', 'submit'),
        " or ",
        $q->reset(-name=>'reset')),
        $q->hidden(-name=>'return_url'),
        "<hr />\n",
        "<table>";
  my $def_email = $global_prefs{'email'} || '';
  print "<tr>\n<td width=\"20%\"><b>Reporter's email:</b></td>\n<td>",
        $q->textfield(-name=>'email',
                      -default=>$def_email,
                      -size=>$textwidth), "</td>\n</tr>\n";
  # keep count of field number, so that javascript hooks can
  # have a way to access fields with dashes in their names
  # they'll need to use PrForm.elements[fieldNumber].value
  # instead of the dashed name
  # note that this is a zero-based count!!
  # there are six fields "hardcoded" into the form above this point.
  my $field_number = 5;

  foreach (@fieldnames)
  {
    if (! (fieldinfo ($_, 'flags') & $SENDINCLUDE))
    {
      next;
    }

    $field_number++;

    # Get default value(s).
    my $default = fieldinfo($_, 'default');

    my $values = fieldinfo($_, 'values');

    # The "intro" provides a way for the site callback to print something
    # at the top of a given field.
    my $intro = cb("sendpr_intro_$_", $field_number) || '';

    print "<tr><td valign=\"top\" width=\"20%\">";
    fieldinfo ($_, 'flags') & $SENDREQUIRED ?
	  print "<font color=\"$site_required_field_color\"><b>$_</b></font>" : print "<b>$_</b>";
    print "<br /><small>\n",
          fieldinfo($_, 'desc'),
	  "</small></td><td>\n", $intro, "\n";

    if (fieldinfo($_, 'fieldtype') eq "enum")
    {
      # Force user to choose a category.
      if ($_ eq $CATEGORY_FIELD)
      {
        push(@$values, "unknown") if (!grep /^unknown$/, @$values);
        $default = "unknown";
      }
      if ($_ eq $SUBMITTER_ID_FIELD)
      {
	    $default = $global_prefs{$SUBMITTER_ID_FIELD} || '';
      }
      print popup_or_scrolling_menu($_, $values, $default),
            "</td>\n</tr>\n";
    }
    elsif (fieldinfo ($_, 'fieldtype') eq 'multienum')
    {
      my $defaultsref = parse_multienum($default, $_);
      print multiselect_menu($_, $values, $defaultsref),
            "</td>\n</tr>\n";
    }
    elsif (fieldinfo($_, 'fieldtype') eq "multitext")
    {
      my $rows = 4;
      print $q->textarea(-name=>$_,
                         -cols=>$textwidth,
                         -rows=>$rows,
                         -default=>$default),
            "</td>\n</tr>\n";
      # Create file upload button after Description.
      if (/Description/)
      {
        print_attachments(undef, 'sendpr');
      }
    }
    else
    {
      print $q->textfield(-name=>$_,
                          -size=>$textwidth,
                          -default=>$default),
            "</td>\n</tr>\n";
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
  my $email = '[^@\s]+(@\S+\.\S+)?';
  if (!$blank && $fieldval !~ /^\s*($email\s*)+$/)
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

  # XXX ??? !!! FIXME
  # validate some other fields
  if($fields{$CATEGORY_FIELD} =~ /^\s*$/ 
     || $fields{$CATEGORY_FIELD} eq "unknown")
  {
    push(@errors, "Category is blank or 'unknown'");
  }
  if($fields{$SYNOPSIS_FIELD} =~ /^\s*$/
     || $fields{$SYNOPSIS_FIELD} eq "unknown")
  {
    push(@errors, "Synopsis is blank or 'unknown'");
  }
  if($fields{$SUBMITTER_ID_FIELD} eq 'unknown')
  {
    push(@errors, "Submitter-Id is 'unknown'");
  }

  @errors;
}

sub submitnewpr
{
  my $page = 'Create PR Results';

  my $debug = 0;
  my(@values, $key);
  my(%fields);

  foreach $key ($q->param)
  {
    my $val = $q->param($key);
    if((fieldinfo ($key, 'fieldtype') || '') eq 'multitext')
    {
      $val = fix_multiline_val($val);
    }
    elsif((fieldinfo ($key, 'fieldtype') || '') eq 'multienum')
    {
      my @val = $q->param($key);
      $val = unparse_multienum(\@val, $key);
    }
    $fields{$key} = $val;
  }

  # Make sure the pr is valid.
  my(@errors) = validate_new_pr(%fields);
  if (@errors)
  {
    print_header(-cookie => create_global_cookie());
    page_start_html($page);
    page_heading($page, 'Error');
    print "<h3>Your problem report has not been sent.</h3>\n",
          "<p>Fix the following problems, then submit the problem report again:</p>",
          $q->ul($q->li(\@errors));
    return;
  }

  my $fullname=$db_prefs{'user'};
  if (exists ($responsible_fullname{$fullname}))
  {
    $fullname=" (".$responsible_fullname{$fullname}.")";
  }
  else
  {
    $fullname="";
  }
  # Supply a default value for Originator
  $fields{$ORIGINATOR_FIELD} = $fields{$ORIGINATOR_FIELD} || ($fields{'email'} . $fullname);

  # Handle the attached_file, if any.
  add_encoded_attachment_to_pr(\%fields, encode_attachment('attached_file'));

  # Compose the PR.
  my $text = unparsepr('send', %fields);
  $text = <<EOT . $text;
To: bugs
CC:
Subject: $fields{$SYNOPSIS_FIELD}
From: $fields{'email'}
Reply-To: $fields{'email'}
X-Send-Pr-Version: gnatsweb-$VERSION ($REVISION)
X-GNATS-Notify: $fields{'X-GNATS-Notify'}

EOT

  # Allow debugging
  if($debug)
  {
    print_header(-cookie => create_global_cookie());
    page_start_html($page);
    print "<h3>debugging -- PR NOT SENT</h3>",
          $q->pre($q->escapeHTML($text)),
          "<hr />";
    page_end_html($page);
    return;
  }

  # Check PR text before submitting
  client_cmd ("chek initial");
  # If the check fails, the next call will exit after leaving
  # an error message.
  client_cmd("$text.");

  client_cmd ("subm");
  client_cmd("$text.");

  my $return_url = $q->param('return_url') || get_script_name();
  my $refresh = 5;

  print_header(-Refresh => "$refresh; URL=$return_url",
               -cookie => create_global_cookie());

  # Workaround for MSIE:
  my @extra_head_args = (-head => $q->meta({-http_equiv=>'Refresh',
                                  -content=>"$refresh; URL=$return_url"}));

  page_start_html($page, 0, \@extra_head_args);

  # Give feedback for success
  page_heading($page, 'Problem Report Sent');
  print "<p>Thank you for your report.  It will take a short while for
your report to be processed.  When it is, you will receive
an automated message about it, containing the Problem Report
number, and the developer who has been assigned to
investigate the problem.</p>";
  print "<p>You will be returned to <a href=\"$return_url\">your previous page</a>
in $refresh seconds...</p>";

  page_footer($page);
  page_end_html($page);
}

# Return a URL which will take one to the specified $pr and with a
# specified $cmd.  For commands such as 'create' that have no
# associated PR number, we pass $pr = 0, and this routine then leaves
# out the pr parameter.  For ease of use, when the user makes a
# successful edit, we want to return to the URL he was looking at
# before he decided to edit the PR.  The return_url param serves to
# store that info, and is included if $include_return_url is
# specified.  Note that the return_url is saved even when going into
# the view page, since the user might go from there to the edit page.
#
sub get_pr_url
{
  my($cmd, $pr, $include_return_url) = @_;
  my $url = $q->url() . "?cmd=$cmd&database=$global_prefs{'database'}";
  $url .= "&pr=$pr" if $pr;
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
  my $viewcmd = $include_audit_trail ? 'view%20audit-trail' : 'view';
  return get_pr_url($viewcmd, @_);
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

# Return links which send email regarding the current PR.
# first link goes to interested parties, second link goes to
# PR submission address and Reply-To (ie. it gets tacked on to
# the audit trail).
sub get_mailto_link
{
  my $sub_mailto = '';
  my($pr,%fields) = @_;
  my $int_mailto  = $q->escape(scalar(interested_parties($pr, %fields)));
  if (defined($site_pr_submission_address{ $global_prefs{'database'} }))
  {
    $sub_mailto  = $q->escape($site_pr_submission_address{$global_prefs{'database'}} .
			      ',' . $fields{'Reply-To'});
  }
  my $subject = $q->escape("Re: $fields{$CATEGORY_FIELD}/$pr: $fields{$SYNOPSIS_FIELD}");
  my $body    = $q->escape(get_viewpr_url($pr));

  # Netscape Navigator up to and including 4.x should get the URL in
  # the body encoded only once -- and so should Opera
  unless ( ($ENV{'HTTP_USER_AGENT'} =~ "Mozilla\/(.)(.*)") && ($1 < 5)
           && ($2 !~ "compatible") || $ENV{'HTTP_USER_AGENT'} =~ "Opera\/" )
  {
    $body = $q->escape($body);
  }

  my $reply = "<a href=\"mailto:$int_mailto?Subject=$subject&Body=$body\">" .
    "send email to interested parties</a>\n";

  if ($sub_mailto) {
      # include a link to email followup
      $reply .= "or <a href=\"mailto:$sub_mailto" .
	"?subject=$subject\">send email followup to audit-trail</a>\n";
  }

  return $reply;
}

sub view
{
  my($viewaudit, $tmp) = @_;

  # $pr must be 'local' to be available to site callback
  local($pr) = $q->param('pr');
  # strip out leading category (and any other non-digit trash) from $pr
  $pr =~ s/\D//g;

  my $page = "View PR $pr";
  page_start_html($page);

  if(!$pr)
  {
    error_page("You must specify a problem report number");
    return;
  }

  # %fields must be 'local' to be available to site callback
  local(%fields) = readpr($pr);

  if (scalar(keys(%fields)) < 4) {
      # looks like there is no such PR, complain to the customer
      # (readpr() hardcodes 3 fields, even if there's no PR)
      gerror("PR $pr does not exist");
      page_end_html($page);
      return;
  }

  page_heading($page, "View Problem Report: $pr");

  print $q->start_form(-method=>'get'),
    hidden_db(),
    hidden_debug(),
    $q->hidden('pr', $pr),
    $q->hidden('return_url');

  # print 'edit' and 'view audit-trail' buttons as appropriate, mailto link
  print "<span>";
  print $q->submit('cmd', 'edit'), ' or '             if (can_edit());
  print $q->submit('cmd', 'view audit-trail'), ' or ' if (!$viewaudit);
  print get_mailto_link($pr, %fields);
  print "</span>";
  print $q->hr(),
        "\n<table>";
  print "\n<tr>\n<td><b>Reporter's email:</b></td>\n<td>",
        $q->tt(make_mailto($fields{'Reply-To'})), "</td>\n</tr>\n";

  foreach (@fieldnames)
  {
    # XXX ??? !!! FIXME
    if ($_ eq $AUDIT_TRAIL_FIELD)
    {
      next;
    }
    my $val = $q->escapeHTML($fields{$_}) || ''; # to avoid -w warning
    my $valign = '';
    if (fieldinfo($_, 'fieldtype') eq 'multitext')
    {
      $valign = ' valign="top"';
      $val = expand($val);
      $val =~ s/$/<br>/gm;
      $val =~ s/<br>$//; # previous substitution added one too many <br>'s
      $val =~ s/  /&nbsp; /g;
      $val =~ s/&nbsp;  /&nbsp; &nbsp;/g;
    }

      # make links in various fields
      if ($_ =~ /responsible/i) {
	  # values in the responsible field are likely to be bare usernames,
	  # so mark_urls won't work on them.
	  $val = make_mailto($val);
      } elsif ($_ =~ /related-prs/i) {
         # make the Related-PRs field show links to the PRs
# dtb - this is juniper specific, but i think it's a good field to have in
# the dbconfig...
	  $val =~ s{(\b|PR)(\d+)\b}{'<a href="'.get_viewpr_url($2)."\">$1$2</a>"}egi;
      } else {
	  # make urls and email addresses into live hrefs
	  $val = mark_urls($val);
      }

   if ($description_in_view) {
       print "<tr><td width=\"20%\"$valign><b>$_:</b><br /><font size=\"-1\" color=\"#999999\">\n",
	     fieldinfo($_, 'desc'),
	     "</font></td>\n<td>";
   } else {
       print "<tr><td nowrap$valign><b>$_:</b></td>\n<td>";
   }
   print $q->tt($val), "</td></tr>\n";

    # Print attachments after Description.
    print_attachments(\%fields, 'view') if /Description/;
  }
  print "</table>",
        $q->hr();

  # print 'edit' and 'view audit-trail' buttons as appropriate, mailto link
  print "<p>";
  print $q->submit('cmd', 'edit'), ' or '             if (can_edit());
  print $q->submit('cmd', 'view audit-trail'), ' or ' if (!$viewaudit);
  print get_mailto_link($pr, %fields);
  print "</p>";
  print $q->end_form();

  # Footer comes before the audit-trail.
  page_footer($page);

  if($viewaudit)
  {
    print "\n<h3>Audit Trail:</h3>\n<pre>\n",
          mark_urls($q->escapeHTML($fields{$AUDIT_TRAIL_FIELD})),
	  "\n</pre>\n";
  }

  page_end_html($page);
}

# edit -
#     The Edit PR page.
#
sub edit
{
  my($pr) = $q->param('pr');
  # strip out leading category (and any other non-digit trash) from
  # $pr, since it will unduly confuse gnats when we try to submit the
  # edit
  $pr =~ s/\D//g;
  my $page = "Edit PR $pr";
  page_start_html($page);

  #my $debug = 0;


  if(!$pr)
  {
    error_page("You must specify a problem report number");
    return;
  }

  my(%fields) = readpr($pr);

  page_heading($page, "Edit Problem Report: $pr");

  # Trim Responsible for compatibility. XXX ??? !!! FIXME
  $fields{$RESPONSIBLE_FIELD} = trim_responsible($fields{$RESPONSIBLE_FIELD});

  print multipart_form_start(-name=>'PrForm'), "\n",
        hidden_db(),
	hidden_debug(),
        $q->span($q->submit('cmd', 'submit edit'),
        " or ",
        $q->reset(-name=>'reset'),
        " or ",
        get_mailto_link($pr, %fields)),
        $q->hidden(-name=>'Editor',
                   -value=>$db_prefs{'user'},
                   -override=>1), "\n",
        $q->hidden(-name=>'Last-Modified',
                   -value=>$fields{$LAST_MODIFIED_FIELD},
                   -override=>1), "\n",
        $q->hidden(-name=>'pr', -value=>$pr, -override=>1),
        $q->hidden(-name=>'return_url'),
        "<hr>\n";

  print "<table>\n";
  print "<tr>\n<td><b>Reporter's email:</b></td>\n<td>",
        $q->textfield(-name=>'Reply-To',
                      -default=>$fields{'Reply-To'},
                      -size=>$textwidth),
        "</td>\n</tr>\n";

  # keep count of field number, so that javascript hooks can
  # have a way to access fields with dashes in their names
  # they'll need to use PrForm.elements[fieldNumber].value
  # instead of the dashed name
  # note that this is a zero-based count!!
  # there are nine fields "hardcoded" into the form above this point.
  my $field_number = 8;

  foreach (@fieldnames)
  {
    if (fieldinfo ($_, 'flags') & $READONLY)
    {
      next;
    }

    $field_number++;

    my $values = fieldinfo($_, 'values');

    # The "intro" provides a way for the site callback to print something
    # at the top of a given field.
    my $intro = cb("edit_intro_$_", $field_number) || '';
    print "<tr><td valign=\"top\" width=\"20%\"><b>$_:</b><br /><small>\n",
          fieldinfo($_, 'desc'),
	  "</small><td>\n", $intro, "\n";

    if (fieldinfo ($_, 'fieldtype') eq 'enum')
    {
      my $default = $fields{$_};
      my $found = 0;
      my $nopush = 0;
      # Check whether field value is a known enumeration value.
      foreach(@$values)
      {
        $found = 1 if $_ eq $default;
        $nopush = 1 if $_ eq 'unknown';
      }
      unless ($found)
      {
        push(@$values, 'unknown') unless $nopush;
        $default = 'unknown';
      }
      print popup_or_scrolling_menu($_, $values, $default),
            "</td>\n</tr>\n";
    }
    elsif (fieldinfo ($_, 'fieldtype') eq 'multienum')
    {
      my $defaultsref = parse_multienum($fields{$_}, $_);
      print multiselect_menu($_, $values, $defaultsref),
      "</td>\n</tr>\n";
    }
    elsif (fieldinfo ($_, 'fieldtype') eq 'multitext')
    {
      my $rows = 4;
      $rows = 8 if /Description/;
      $rows = 2 if /Environment/;
      print $q->textarea(-name=>$_,
                         -cols=>$textwidth,
                         -rows=>$rows,
                         -default=>$fields{$_}),
            "</td>\n</tr>\n";
      # Print attachments after Description.
      print_attachments(\%fields, 'edit') if /Description/;
    }
    else
    {
      print $q->textfield(-name=>$_,
                          -size=>$textwidth,
                          -default=>$fields{$_}),
            "</td>\n</tr>\n";
    }
    if (fieldinfo ($_, 'flags') & $REASONCHANGE)
    {
      print "<tr><td valign=\"top\"><b>Reason Changed:</b></td>\n<td>",
            $q->textarea(-name=>"$_-Changed-Why",
                         -default=>'',
                         -override=>1,
                         -cols=>$textwidth,
                         -rows=>2,
                         -wrap=>'hard'),
            "</td>\n</tr>\n";
    }
    print "\n";
  }
  print "</table>",
        $q->p($q->submit('cmd', 'submit edit'),
        " or ",
        $q->reset(-name=>'reset'),
        " or ",
        get_mailto_link($pr, %fields)), "\n",
        $q->end_form(), "\n",
        $q->hr(), "\n";

  # Footer comes before the audit-trail.
  page_footer($page);

    print "\n<h3>Audit Trail:</h3>\n<pre>\n",
          mark_urls($q->escapeHTML($fields{$AUDIT_TRAIL_FIELD})),
	  "\n</pre>\n";
  page_end_html($page);
}

# Print out the %fields hash for debugging.
sub debug_print_fields
{
  my $fields_hash_ref = shift;
  foreach my $f (sort keys %$fields_hash_ref)
  {
    print "<tr valign=top><td>$f</td><td>",
          $q->pre($q->escapeHTML($$fields_hash_ref{$f})),
          "</td></tr>\n";
  }
  my $aref = $$fields_hash_ref{'attachments'} || [];
  my $i=0;
  foreach my $href (@$aref) {
    print "<tr valign=top><td>attachment $i<td>",
          ($$href{'original_attachment'}
           ?  $$href{'original_attachment'} : "--- empty ---");
    $i++;
  }
  print "</table></font><hr>\n";
}

sub submitedit
{
  my $page = 'Edit PR Results';

  my $debug = 0;
  my $lock_end_reached;

  my($pr) = $q->param('pr');

  # strip out leading category (and any other non-digit trash) from
  # $pr, since it will unduly confuse gnats when we try to submit the
  # edit
  $pr =~ s/\D//g;

  if(!$pr)
  {
    error_page("You must specify a problem report number");
    return;
  }

  my(%fields, %mailto, $adr);
  my $audittrail = '';
  my $err = '';

  # Retrieve new attachment (if any) before locking PR, in case it fails.
  my $encoded_attachment = encode_attachment('attached_file');

  my(%oldfields) = lockpr($pr, $db_prefs{'user'});
  LOCKED:
  {
    # Trim Responsible for compatibility.
    $oldfields{$RESPONSIBLE_FIELD} = trim_responsible($oldfields{$RESPONSIBLE_FIELD});

    # Merge %oldfields and CGI params to get %fields.  Not all gnats
    # fields have to be present in the CGI params; the ones which are
    # not specified default to their old values.
    %fields = %oldfields;
    foreach my $key ($q->param)
    {
      my $val = $q->param($key);
      my $ftype = fieldinfo($key, 'fieldtype') || '';
      if($key =~ /-Changed-Why/
         || ($ftype eq 'multitext'))
      {
        $val = fix_multiline_val($val);
      }
      elsif($ftype eq 'multienum')
      {
        my @val = $q->param($key);
        $val = unparse_multienum(\@val, $key);
      }
      $fields{$key} = $val;
    }

    # Add the attached file, if any, to the new PR.
    add_encoded_attachment_to_pr(\%fields, $encoded_attachment);

    # Delete any attachments, if directed.
    my(@deleted_attachments) = $q->param('delete attachments');
    remove_attachments_from_pr(\%fields, @deleted_attachments);

    if ($debug)
    {
      print "<h3>debugging -- PR edits not submitted</h3><font size=1><table>";
      debug_print_fields(\%fields);
      last LOCKED;
    }

    my $newlastmod = $fields{$LAST_MODIFIED_FIELD} || '';
    my $oldlastmod = $oldfields{$LAST_MODIFIED_FIELD} || '';

    if($newlastmod ne $oldlastmod)
    {
      error_page("Sorry, PR $pr has been modified since you started editing it.",
                "Please return to the edit form, press the Reload button, " .
                "then make your edits again.\n" .
                "<pre>Last-Modified was    '$newlastmod'\n" .
                "Last-Modified is now '$oldlastmod'</pre>");
      last LOCKED;
    }

    my (@errors) = ();
    if ($fields{$RESPONSIBLE_FIELD} eq "unknown")
    {
      push(@errors, "$RESPONSIBLE_FIELD is 'unknown'");
    }
    if ($fields{$CATEGORY_FIELD} eq "unknown")
    {
      push(@errors, "$CATEGORY_FIELD is 'unknown'.");
    }
    if($fields{$SUBMITTER_ID_FIELD} eq "unknown")
    {
      push(@errors, "$SUBMITTER_ID_FIELD is 'unknown'.");
    }
    if (@errors)
    {
      push(@errors,
	 "Go back to the edit form, correct the errors and submit again.");
      error_page("The PR has not been submitted.", \@errors);
      last LOCKED;
    }

    # If Reply-To changed, we need to splice the change into the envelope.
    if($fields{'Reply-To'} ne $oldfields{'Reply-To'})
    {
      if ($fields{'envelope'} =~ /^'Reply-To':/m)
      {
        # Replace existing header with new one.
        $fields{'envelope'} =~ s/^'Reply-To':.*$/'Reply-To': $fields{'Reply-To'}/m;
      }
      else
      {
        # Insert new header at end (blank line).  Keep blank line at end.
        $fields{'envelope'} =~ s/^$/'Reply-To': $fields{'Reply-To'}\n/m;
      }
    }

    # Check whether fields that are specified in dbconfig as requiring a
    # 'Reason Changed' have the reason specified:
    foreach my $fieldname (keys %fields)
    {
      my $newvalue = $fields{$fieldname} || '';
      my $oldvalue = $oldfields{$fieldname} || '';
      my $fieldflags = fieldinfo($fieldname, 'flags') || 0;
      if ( ($newvalue ne $oldvalue) && ( $fieldflags & $REASONCHANGE) )
      {
        if($fields{$fieldname."-Changed-Why"} =~ /^\s*$/)
        {
          error_page("Field '$fieldname' must have a reason for change",
                    "Please press the 'Back' button of you browser, correct the problem and resubmit.");
          last LOCKED;
        }
      }
      if ($newvalue eq $oldvalue && exists $fields{$fieldname."-Changed-Why"} )
      {
        delete $fields{$fieldname."-Changed-Why"};
      }
    }

    my($newpr) = unparsepr('gnatsd', %fields);
    $newpr =~ s/\r//g;

    # Submit the edits.  We need to unlock the PR even if the edit fails
    local($suppress_client_exit) = 1;
	client_cmd("editaddr $db_prefs{'user'}");
	last LOCKED if ($client_would_have_exited);
    client_cmd("edit $pr");
	last LOCKED if ($client_would_have_exited);
    client_cmd("$newpr.");

    $lock_end_reached = 1;
  }
  unlockpr($pr);

  if ( (! $client_would_have_exited) && $lock_end_reached) {
    # We print out the "Edit successful" message after unlocking the PR. If the user hits
    # the Stop button of the browser while submitting, the web server won't terminate the
    # script until the next time the server attempts to output something to the browser.
    # Since this is the first output after the PR was locked, we print it after the unlocking.
    # Let user know the edit was successful. After a 2s delay, refresh back
    # to where the user was before the edit. Internet Explorer does not honor the
    # HTTP Refresh header, so we have to complement the "clean" CGI.pm method
    # with the ugly hack below, with a HTTP-EQUIV in the HEAD to make things work.
    my $return_url = $q->param('return_url') || get_script_name();
    # the refresh header chokes on the query-string if the
    # params are separated by semicolons...
    $return_url =~ s/\;/&/g;

    my $refresh = 2;
    print_header(-Refresh => "$refresh; URL=$return_url");

    # Workaround for MSIE:
    my @extra_head_args = (-head => $q->meta({-http_equiv=>'Refresh',
                                    -content=>"$refresh; URL=$return_url"}));

    page_start_html($page, 0, \@extra_head_args);
    page_heading($page, 'Edit successful');
    print <<EOM;
<p>You will be returned to <a href="$return_url">your previous page</a>
in $refresh seconds...</p>
EOM
  }

  page_footer($page);
  page_end_html($page);
}

sub query_page
{
  my $page = 'Query PR';
  page_start_html($page);
  page_heading($page, 'Query Problem Reports');
  print_stored_queries();
  print $q->start_form(),
          hidden_db(),
	hidden_debug(),
        $q->submit('cmd', 'submit query'),
        "<hr>",
        "<table>";

  foreach (@fieldnames) 
  {
    if (fieldinfo($_, 'fieldtype') =~ /enum/)
    {
      print "<tr><td valign=top>$_:</td>\n<td>";
      my $value_list=fieldinfo($_, 'values');
      my @values=('any', @$value_list);
      if (fieldinfo($_, 'fieldtype') eq 'enum')
      {
        print popup_or_scrolling_menu ($_, \@values, $values[0]);
      }
      elsif (fieldinfo($_, 'fieldtype') eq 'multienum')
      {
        my $size = @values < 4 ? @values : 4;
        print $q->scrolling_list(-name=>$_, -values=>\@values, -size=>$size,
                                 -multiple=>'true', -defaults=>$values[0]);
      }
      if ($_ eq $STATE_FIELD)
      {
        print "<br />",
              $q->checkbox_group(-name=>'ignoreclosed',
                                 -values=>['Ignore Closed'],
                                 -defaults=>['Ignore Closed']);
      }
      elsif ($_ eq $SUBMITTER_ID_FIELD)
      {
        print "<br />",
              $q->checkbox_group(-name=>'originatedbyme',
                                 -values=>['Originated by You'],
                                 -defaults=>[]);
      }
      print "</td>\n</tr>\n";
    }
  }
  
  print
        "<tr>\n<td>$SYNOPSIS_FIELD Search:</td>\n<td>",
        $q->textfield(-name=>$SYNOPSIS_FIELD,-size=>25),
        "</td>\n</tr>\n",
        "<tr>\n<td>Multi-line Text Search:</td>\n<td>",
        $q->textfield(-name=>'multitext',-size=>25),
        "</td>\n</tr>\n",
        "<tr valign=top>\n<td>Column Display:</td>\n<td>";

  my @allcolumns;
  foreach (@fieldnames) {
    if (fieldinfo($_, 'fieldtype') ne 'multitext') {
      push (@allcolumns, $_);
    }
  }
  # The 'number' field is always first in the @allcolumns array. If
  # users were allowed to select it in this list, the PR number would
  # appear twice in the Query Results table. We prevent this by
  # shifting 'number' out of the array.
  shift(@allcolumns);

  my(@columns) = split(' ', $global_prefs{'columns'} || '');
  @columns = @allcolumns unless @columns;

  print $q->scrolling_list(-name=>'columns',
                           -values=>\@allcolumns,
                           -defaults=>\@columns,
                           -multiple=>1,
                           -size=>5),
        "</td>\n</tr>\n";

  print "<tr valign=top>\n<td>Sort By:</td>\n<td>",
        $q->scrolling_list(-name=>'sortby',
                           -values=>\@fieldnames,
                           -multiple=>0,
                           -size=>1),
        "<br />",
        $q->checkbox_group(-name=>'reversesort',
                           -values=>['Reverse Order'],
                           -defaults=>[]),
        "</td>\n</tr>\n";

  print "<tr valign=top>\n<td>Display:</td>\n<td>",
        $q->checkbox_group(-name=>'displaydate',
               -values=>['Current Date'],
               -defaults=>['Current Date']),
        "</td>\n</tr>\n",
        "</table>\n",
        "<hr>\n",
        $q->submit('cmd', 'submit query'),
        $q->end_form();

  page_footer($page);
  page_end_html($page);
}

sub advanced_query_page
{
  my $page = 'Advanced Query';
  page_start_html($page);
  page_heading($page, 'Query Problem Reports');
  print_stored_queries();
  print $q->start_form(),
	hidden_debug(),
        hidden_db();

  my $width = 30;
  my $heading_bg = '#9fbdf9';
  my $cell_bg = '#d0d0d0';

  print $q->span($q->submit('cmd', 'submit query'),
        " or ",
        $q->reset(-name=>'reset'));
  print "<hr>";
  print "<center>";

  ### Text and multitext queries

  print "<table border=1 cellspacing=0 bgcolor=$cell_bg>\n",
        "<caption>Search All Text</caption>\n",
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

  print "<table border=1 cellspacing=0 bgcolor=$cell_bg>\n",
        "<caption>Search By Date</caption>\n",
        "<tr bgcolor=$heading_bg>\n",
        "<th nowrap>Date Search</th>\n",
        "<th nowrap>Example: <tt>1999-04-01 05:00 GMT</tt></th>\n",
        "</tr>\n";

  foreach (@fieldnames)
  {
    if (fieldinfo ($_, 'fieldtype') eq 'date')
    {
      print "<tr>\n<td>$_ after:</td>\n<td>",
          $q->textfield(-name=>$_."_after", -size=>$width),
          "</td>\n</tr>\n";
      print "<tr>\n<td>$_ before:</td>\n<td>",
          $q->textfield(-name=>$_."_before", -size=>$width),
          "</td>\n</tr>\n";
    }
  }
  print $q->Tr( $q->td({-colspan=>2},
        $q->small( $q->b("NOTE:"), "If your search includes 'Closed After'
                   or 'Closed Before', uncheck 'Ignore Closed' below.")));
  print "</table>\n";
  print "<div>&nbsp;</div>\n";

  ### Field queries

  print "<table border=1 cellspacing=0 bgcolor=$cell_bg>\n",
        "<caption>Search Individual Fields</caption>\n",
        "<tr bgcolor=$heading_bg>\n",
        "<th nowrap>Search this field</th>\n",
        "<th nowrap>using regular expression, or</th>\n",
        "<th nowrap>using multi-selection</th>\n",
        "</tr>\n";
  foreach (@fieldnames)
  {
    print "<tr valign=top>\n";

    # 1st column is field name
    print "<td>$_:</td>\n";

    # 2nd column is regexp search field
    print "<td>",
          $q->textfield(-name=>$_,
                        -size=>$width);
    print "\n";
    # XXX ??? !!! FIXME
    # This should be fixed by allowing a 'not' in front of the fields, so
    # one can simply say "not closed".
    if ($_ eq $STATE_FIELD)
    {
      print "<br />",
            $q->checkbox_group(-name=>'ignoreclosed',
                               -values=>['Ignore Closed'],
                               -defaults=>['Ignore Closed']),
    }
    print "</td>\n";

    # 3rd column is blank or scrolling multi-select list
    print "<td>";
    if (fieldinfo($_, 'fieldtype') =~ 'enum')
    {
      my $ary_ref = fieldinfo($_, 'values');
      my $size = scalar(@$ary_ref);
      $size = 4 if $size > 4;
      print $q->scrolling_list(-name=>$_,
                               -values=>$ary_ref,
                               -multiple=>1,
                               -size=>$size);
    }
    else
    {
      print "&nbsp;";
    }
    print "</td>\n</tr>\n";
  }
  print "</table>\n";
  print "<div>&nbsp;</div>\n";

  print "<table border=1 cellspacing=0 bgcolor=$cell_bg>\n",
        "<caption>Display</caption>\n",
        "<tr valign=top>\n<td>Display these columns:</td>\n<td>";

  my @allcolumns;
  foreach (@fieldnames) {
    if (fieldinfo($_, 'fieldtype') ne 'multitext') {
      push (@allcolumns, $_);
    }
  }
  # The 'number' field is always first in the @allcolumns array. If
  # users were allowed to select it in this list, the PR number would
  # appear twice in the Query Results table. We prevent this by
  # shifting 'number' out of the array.
  shift(@allcolumns);

  my(@columns) = split(' ', $global_prefs{'columns'} || '');
  @columns = @allcolumns unless @columns;

  print $q->scrolling_list(-name=>'columns',
                           -values=>\@allcolumns,
                           -defaults=>\@columns,
                           -multiple=>1,
                           -size=>5),
        "</td>\n</tr>\n";

  print "<tr valign=top>\n<td>Sort By:</td>\n<td>",
        $q->scrolling_list(-name=>'sortby',
                           -values=>\@fieldnames,
                           -multiple=>0,
                           -size=>1),
        "<br />",
        $q->checkbox_group(-name=>'reversesort',
                           -values=>['Reverse Order'],
                           -defaults=>[]),
        "</td>\n</tr>\n";
  print "<tr valign=top>\n<td>Display:</td>\n<td>",
        $q->checkbox_group(-name=>'displaydate',
                           -values=>['Current Date'],
                           -defaults=>['Current Date']),
        "</td>\n</tr>\n",
        "</td>\n</tr>\n</table>\n";
  print "<div>&nbsp;</div>\n";
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


# takes a string, and turns it into a mailto: link
# if it's not a full address, $site_mail_domain is appended first
sub make_mailto {
    my $string = shift;
    if ($string !~ /@/) {
	$string = qq*<a href="mailto:${string}${site_mail_domain}">$string</a>*;
    } else {
	$string = qq*<a href="mailto:$string">$string</a>*;
    }
    return $string;
}

# takes a string, attempts to make urls, PR references and email
# addresses in that string into links:
# 'foo bar baz@quux.com flibbet PR# 1234 and furthermore
#  http://www.abc.com/whatever.html'
# is returned as:
# 'foo bar <a href="mailto:baz@quux.com">baz@quux.com</a> flibbet
#   <a href="http://site.com/cgi-bin/gnats?cmd=view;pr=1234;database=default">PR# 1234</a>
#   <a href="http://www.abc.com/whatever.html" target="showdoc">
#   http://www.abc.com/whatever.html</a>'
# returns the (possibly) modified string
# behavior can be modified by twiddling knobs in the %mark_urls hash.
sub mark_urls {
    my $string = shift || '';

    # skip empty strings, or strings longer than the limit
    return $string if ($string =~ /^\s*$/ ||
		       length($string) > $mark_urls{'max_length'});

    if ($mark_urls{'urls'})
    {
	# make URLs live
	$string =~ s{
		     \b
		     (
		      (http|telnet|gopher|file|wais|ftp):
		      [\w/#~+=&%@!.:;?\-]+?
		      )
		      (?=
		       [.:?\-]*
		       [^\w/#~+=&%@!.;:?\-]
			|
			$
		       )
		     }
		     {<a href="$1" target="showdoc">$1</a>}igx;
    }

    if ($mark_urls{'prs'})
    {
	# make "PR: 12345" into a link to "/cgi-bin/gnats?cmd=view;pr=12345"
	$string =~ s{
		     (\WPR[:s#]?\s?)     # PR followed by :|s|whitespace
		     (\s[a-z0-9-]+\/)?    # a category name & a slash (optional)
		     ([0-9]+)           # the PR number
		     }
		     {$1.'<a href="'.get_viewpr_url($3).'">'.$2.$3.'</a>'}egix;
    }

    if ($mark_urls{'emails'})
    {
	# make email addresses live
	$string =~ s{
		     \b
		     (
                      (?<!ftp://)
		      [\w+=%!.\-]+?
		      @
		      (?:
		       [\w\-_]+?
		       \.
		      )+
		      [\w\-_]+?
		     )
		     (?=
		      [.:?\-]*
		      (?:
		       [^\w\-_]
		       |
		       \s
		      )
		      |
		      $
		     )
		   }
		   {<a href="mailto:$1">$1</a>}igx;
    }

    return $string;
}


sub appendexpr
{
  my $lhs = shift;
  my $op = shift;
  my $rhs = shift;

  if ($lhs eq "")
  {
    return $rhs;
  }
  if ($rhs eq "")
  {
    return $lhs;
  }
  return "($lhs) $op ($rhs)";
}

sub submitquery
{
  my $page = 'Query Results';
  my $queryname = $q->param('queryname');

  my $heading = 'Query Results';
  $heading .= ": $queryname" if $queryname;
  page_start_html($page);
  page_heading($page, $heading);
  my $debug = 0;

  my $originatedbyme = $q->param('originatedbyme');
  my $ignoreclosed   = $q->param('ignoreclosed');

  local($client_cmd_debug) = 1 if $debug;
  client_cmd("rset");

  my $expr = "";
  if ($originatedbyme)
  {
    $expr = 'builtinfield:originator="'.$db_prefs{'user'}.'"';
  }
  if ($ignoreclosed)
  {
    $expr = appendexpr ('(! builtinfield:State[type]="closed")', '&', $expr);
  }

  ### Construct expression for each param which specifies a query.
  my $field;
  foreach $field ($q->param())
  {
    my @val = $q->param($field);
    my $stringval = join(" ", @val);

    # Bleah. XXX ??? !!!
    if ($stringval ne '')
    {
      if (isvalidfield ($field))
      {
        my $subexp = "";
        my $sval;

        # Turn multiple param values into ORs.
        foreach $sval (@val)
        {
          if ($sval ne 'any' && $sval ne '')
          {
            # Most (?) people expect queries on enums to be of the
            # exact, not the substring type.
	    # Hence, provide explicit anchoring for enums. This
	    # still leaves the user the possibility of inserting
	    # ".*" before and/or after regular expression searches
	    # on the advanced query page.
            if (fieldinfo($field, 'fieldtype') =~ "enum|multienum")
            {
              $subexp = appendexpr ($subexp, '|', "$field~\"^$sval\$\"");
            }
            else
            {
              $subexp = appendexpr ($subexp, '|', "$field~\"$sval\"");
            }
          }
        }
        $expr = appendexpr ($expr, '&', $subexp);
      }
      elsif ($field eq 'text' || $field eq 'multitext')
      {
        $expr = appendexpr ($expr, '&', "fieldtype:$field~\"$stringval\"");
      }
      elsif ($field =~ /_after$/ || $field =~ /_before$/)
      {
        my $op;
        # Waaah, nasty. XXX ??? !!!
        if ($field =~ /_after$/)
        {
          $op = '>';
        }
        else
        {
          $op = '<';
        }
        # Whack off the trailing _after or _before.
        $field =~ s/_[^_]*$//;
        $expr = appendexpr ($expr, '&', $field.$op.'"'.$stringval.'"');
      }
    }
  }

  my $format="\"%s";

  my @columns = $q->param('columns');
  # We are using ASCII octal 037 (unit separator) to separate the
  # fields in the query output. Note that the format strings are
  # interpolated (quoted with ""'s), so make sure to escape any $ or @
  # signs.
  foreach (@columns) {
	if (fieldinfo ($_, 'fieldtype') eq 'date') {
      $format .= "\037%{%Y-%m-%d %H:%M:%S %Z}D";
	} elsif (fieldinfo ($_, 'fieldtype') eq 'enum') {
      $format .= "\037%d";
	} else {
      $format .= "\037%s";
    }
  }

  $format .= "\" ".${NUMBER_FIELD}." ".join (" ", @columns);

  client_cmd("expr $expr") if $expr;
  client_cmd("qfmt $format");

  my(@query_results) = client_cmd("quer");

  display_query_results(@query_results);
  page_footer($page);
  page_end_html($page);
}

# nonempty -
#     Turn empty strings into "&nbsp;" so that Netscape tables won't
#     look funny.
#
sub nonempty
{
  my $str = shift;
  $str = '&nbsp;' if !$str;
 return $str;
}


# display_query_results -
#     Display the query results, and the "store query" form.
#     The results only have the set of fields that we requested, although
#     the first field is always the PR number.
sub display_query_results
{
  my(@query_results) = @_;
  my $displaydate = $q->param('displaydate');
  my $reversesort = $q->param('reversesort');

  my $num_matches = scalar(@query_results);
  my $heading = sprintf("%s %s found",
                        $num_matches ? $num_matches : "No",
                        ($num_matches == 1) ? "match" : "matches");
  my $heading2 = $displaydate ? $q->small("( Query executed ",
			(scalar localtime), ")") : '';
  print $q->table({cellpadding=>0, cellspacing=>0, border=>0},
                  $q->Tr($q->td($q->font({size=>'+2'},
		  $q->strong($heading)))), $q->Tr($q->td($heading2)));
  print $q->start_form(),
	hidden_debug(),
        $q->hidden(name=>'cmd', -value=>'view', -override=>1),
        "<table border=1 cellspacing=0 cellpadding=1><tr>\n";

  # By default sort by PR number.
  my($sortby) = $q->param('sortby') || $fieldnames[0];

  my $whichfield = 0;
  my ($sortbyfieldnum) = 0;
  my @columns = $q->param('columns');
  my $noofcolumns = @columns;
  # Print table header which allows sorting by columns.
  # While printing the headers, temporarily override the 'sortby' param
  # so that self_url() works right.
  for ($fieldnames[0], @columns)
  {
    $q->param(-name=>'sortby', -value=>$_);
    if ($_ eq $sortby) {
      $sortbyfieldnum = $whichfield;
    }
    $whichfield++;

    # strip empty params out of self_url().  in a gnats db with many
    # fields, the url query-string will become very long.  this is a
    # problem, since IE5 truncates query-strings at ~2048 characters.
    my ($query_string) = $q->self_url() =~ m/^[^?]*\?(.*)$/;
    $query_string =~ s/(\w|-)+=;//g;

    my $href = $script_name . '?' . $query_string;
    print "\n<th><a href=\"$href\">$_</a></th>\n";
  }
  # finished the header row
  print "</tr>\n";

  # Reset param 'sortby' to its original value, so that 'store query' works.
  $q->param(-name=>'sortby', -value=>$sortby);

  # Sort @query_results according to the rules in by_field().
  # Using the "map, sort" idiom allows us to perform the expensive
  # split() only once per item, as opposed to during every comparison.
  my(@presplit_prs) = map { [ (split /\037/) ] } @query_results;
  my(@sorted_prs);
  my $sortby_fieldtype = fieldinfo ($sortby, 'fieldtype') || '';
  if ($sortby_fieldtype eq 'enum' || $sortby_fieldtype eq 'integer') {
    # sort numerically
    @sorted_prs = sort({$a->[$sortbyfieldnum] <=> $b->[$sortbyfieldnum]}
		       @presplit_prs);
  } else {
    # sort alphabetically
    @sorted_prs = sort({lc($a->[$sortbyfieldnum] || '') cmp lc($b->[$sortbyfieldnum] ||'')}
		       @presplit_prs);
  }

  @sorted_prs = reverse @sorted_prs if $reversesort;

  # Print the PR's.
  my @fieldtypes = map { fieldinfo ($_, 'fieldtype') } @columns;
  foreach (@sorted_prs)
  {
    print "<tr valign=top>\n";
    my $id = shift @{$_};

    print "<td nowrap><a href=\"" . get_viewpr_url($id, 1) . "\">$id</a>"; 
    if (can_edit())
    {
      print " <a href=\"" . get_editpr_url($id, 1) . "\"><font size=-1>edit</font></a>";
    }
    print "</td>";

    my $fieldcontents;
    my $whichfield = 0;
    foreach $fieldcontents (@{$_})
    {
      # The query returned the enums as numeric values, now we have to
      # map them back into strings.
      if ($fieldtypes[$whichfield] eq 'enum')
      {
        my $enumvals = fieldinfo($columns[$whichfield], 'values');
	# A zero means that the string is absent from the enumeration type.
        $fieldcontents = $fieldcontents ? $$enumvals[$fieldcontents - 1] : 'unknown';
      }
      $fieldcontents = $q->escapeHTML($fieldcontents);
      $fieldcontents = nonempty($fieldcontents);

      if ($columns[$whichfield] =~ /responsible/i) {
	  $fieldcontents = make_mailto($fieldcontents);
      } else {
	  # make urls and email addresses into live hrefs
	  $fieldcontents = mark_urls($fieldcontents);
      }

      print "<td nowrap>$fieldcontents</td>";
      $whichfield++;
    }
    # Pad the remaining, empty columns with &nbsp;'s
    my $n = @{$_};
    while ($noofcolumns - $n > 0)
    {
      print "<td>&nbsp;</td>";
      $n++;
    }
    print "\n</tr>\n";
  }
  print "</table>",
        $q->end_form();

  # Provide a URL which someone can use to bookmark this query.
  my $url = $q->self_url();
  # strip empty params out of $url.  in a gnats db with many
  # fields, the url query-string will become very long.  this is a
  # problem, since IE5 truncates query-strings at ~2048 characters.
  $url =~ s/(\w|-)+=;//g;

  print "\n<p>",
        qq{<a href="$url">View for bookmarking</a>},
        "<br />";
  if ($reversesort) {
    $url =~ s/[&;]reversesort=[^&;]*//;
  } else {
    $url .= $q->escapeHTML(";reversesort=Descending Order");
  }
  print qq{<a href="$url">Reverse sort order</a>},
        "</p>";

  # Allow the user to store this query.  Need to repeat params as hidden
  # fields so they are available to the 'store query' handler.
  print $q->start_form(), hidden_debug();
  foreach ($q->param())
  {
    # Ignore certain params.
    next if /^(cmd|queryname)$/;
    print $q->hidden($_), "\n";
  }
  print "\n<table>\n",
        "<tr>\n",
        "<td>Remember this query as:</td>\n",
        "<td>",
        $q->textfield(-name=>'queryname', -size=>25),
        "</td>\n<td>";
  # Note: include hidden 'cmd' so user can simply press Enter w/o clicking.
  print $q->hidden(-name=>'cmd', -value=>'store query', -override=>1),
        $q->submit('cmd', 'store query'),
        $q->hidden('return_url', $q->self_url()),
        "\n</td>\n</tr>\n</table>",
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
  if (!$queryname || ($queryname =~ /[;|,|\s]+/) ) {
    error_page('Illegal query name',
               "You tried to store the query with an illegal name. "
               . "Legal names are not blank and do not contain the symbols "
               . "';' (semicolon), ',' (comma) or the space character.");
    exit();
  }
  # First make sure we don't already have too many cookies.
  # See http://home.netscape.com/newsref/std/cookie_spec.html for
  # limitations -- 20 cookies; 4k per cookie.
  my(@cookie_names) = $q->cookie();
  if (@cookie_names >= 20) {
    error_page('Cannot store query -- too many cookies',
               "Gnatsweb cannot store this query as another cookie because"
               . "there already are "
               . scalar(@cookie_names)
               . " cookies being passed to gnatsweb.  There is a maximum"
               . " of 20 cookies per server or domain as specified in"
               . " <a href=\"http://home.netscape.com/newsref/std/cookie_spec.html\">"
               . "http://home.netscape.com/newsref/std/cookie_spec.html</a>");
    exit();
  }

  # Don't save certain params.
  $q->delete('cmd');
  my $query_string = $q->query_string();

  # strip empty params out of $query_string.  in a gnats db with many
  # fields, the query-string will become very long, and may exceed the
  # 4K limit for cookies.
  $query_string =~ s/\w+=;//g;

  if (length($query_string . $global_cookie_path . "gnatsweb-query-$queryname") > 4050) {
    # this cookie is going to be longer than 4K, so we'll have to punt
    error_page('Cannot store query -- cookie too large',
               "Gnatsweb cannot store this query as a cookie because"
               . " it would exceed the maximum of 4K per cookie, as specified in"
               . " <a href=\"http://home.netscape.com/newsref/std/cookie_spec.html\">"
               . "http://home.netscape.com/newsref/std/cookie_spec.html</a>");
  exit();
  }

  # Have to generate the cookie before printing the header.
  my $new_cookie = $q->cookie(-name => "gnatsweb-query-$queryname",
                              -value => $query_string,
                              -path => $global_cookie_path,
                              -expires => '+10y');

  # Now print the page.
  my $page = 'Query Saved';
  my $return_url = $q->param('return_url') || get_script_name();
  my $refresh = 5;

  print_header(-Refresh => "$refresh; URL=$return_url",
               -cookie => $new_cookie);

  # Workaround for MSIE:
  my @extra_head_args = (-head => $q->meta({-http_equiv=>'Refresh',
                                            -content=>"$refresh; URL=$return_url"}));

  page_start_html($page, 0, \@extra_head_args);

  page_heading($page, 'Query Saved');
  print "<h2>debugging</h2><pre>",
        "query_string: $query_string",
        "cookie: $new_cookie\n",
        "</pre><hr>\n"
        if $debug;
  print "<p>Your query \"$queryname\" has been saved.  It will be available ",
        "the next time you reload the Query page.</p>";
  print "<p>You will be returned to <a href=\"$return_url\">your previous page ",
        "</a> in $refresh seconds...</p>";
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
  my %stored_queries = ();
  foreach my $cookie ($q->cookie())
  {
    if ($cookie =~ /gnatsweb-query-(.*)/)
    {
      my $query_key = $1;
      my $query_param = $q->cookie($cookie);
      # extract queries relevant to the current database:
      if ($query_param =~ /database=$global_prefs{'database'}/ )
      {
        $stored_queries{$query_key} = $query_param;
      }
    }
  }
  if (%stored_queries)
  {
    print "<table cellspacing=0 cellpadding=0 border=0>",
          "<tr valign=top>",
          $q->start_form(),
	  hidden_debug(),
          "<td>",
          hidden_db(),
          $q->submit('cmd', 'submit stored query'),
          "<td>&nbsp;<td>",
          $q->popup_menu(-name=>'queryname',
                         -values=>[ sort(keys %stored_queries) ]),
          $q->end_form(),
          $q->start_form(),
	  hidden_debug(),
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
    error_page($err);
  }
  else
  {
    # 9/10/99 kenstir: Must use full (not relative) URL in redirect.
    # Patch by Elgin Lee <ehl@terisa.com>.
    my $query_url = $q->url() . '?cmd=' . $q->escape('submit query')
          . ';' . $query_string;
    if ($debug)
    {
      print_header(),
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
    error_page($err);
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
    my $return_url = $q->param('return_url') || get_script_name();
    my $refresh = 0;

    print_header(-Refresh => "$refresh; URL=$return_url",
                 -cookie => $expire_cookies);

    # Workaround for MSIE:
    print $q->start_html(-head => $q->meta({-http_equiv=>'Refresh',
                                    -content=>"$refresh; URL=$return_url"}));
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
  open(HTML, "<$file") || return;
  local $/ = undef; # slurp file whole
  my $html = <HTML>;
  close(HTML);

  # send just the stuff inside <body>..</body>
  $html =~ s/.*<body>//is;
  $html =~ s/<\/body>.*//is;

  print $html;
}

sub error_page
{
  my($err_heading, $err_text) = @_;
  my $page = 'Error';
  print_header();
  page_start_html($page);
  page_heading($page, 'Error');
  print $q->h3($err_heading);
  print $q->p($err_text) if $err_text;
  page_footer($page);
  page_end_html($page);
}

sub help_page
{
  my $html_file = $help_page_path;
  my $page      = $q->param('help_title') || 'Help';
  my $heading   = $page;
  page_start_html($page);
  page_heading($page, $heading);

  # If send_html doesn't work, print some default, very limited, help text.
  if (!send_html($html_file))
  {
    print $q->p('Welcome to our problem report database. ',
            'You\'ll notice that here we call them "problem reports" ',
            'or "PR\'s", not "bugs".');
    print $q->p('This web interface is called "gnatsweb". ',
            'The database system itself is called "gnats".',
            'You may want to peruse ',
            $q->a({-href=>"$gnats_info_top"}, 'the gnats manual'),
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
  return $q->hidden(-name=>'database', -value=>$global_prefs{'database'}, -override=>1);
}

# hidden_debug -
#    Return hidden form element to maintain state of debug params
#
sub hidden_debug
{
    if ($site_allow_remote_debug) {
	return $q->hidden(-name=>'debug');
    } else {
	return;
    }
}

# one_line_form -
#     One line, two column form used for main page.
#
sub one_line_form
{
  my($label, @form_body) = @_;
  my $valign = 'baseline';
  return $q->Tr({-valign=>$valign},
                $q->td($q->b($label)),
                $q->td($q->start_form(-method=>'get'), hidden_debug(),
		       hidden_db(), @form_body, $q->end_form()));
}

# can_create -
#     If $no_create_without_access is set to a defined gnats
#     access_level, return false unless user's access_level is >= to
#     level set in $no_create_without_access
sub can_create
{
    if (exists($LEVEL_TO_CODE{$no_create_without_access})) {
      return ($LEVEL_TO_CODE{$access_level} >= $LEVEL_TO_CODE{$no_create_without_access});
    } else {
      return 1;
    }
}

# can_edit -
#     Return true if the user has edit privileges or better.
sub can_edit
{
  return ($LEVEL_TO_CODE{$access_level} >= $LEVEL_TO_CODE{'edit'});
}

sub main_page
{
  my $page = 'Main';

  my $viewcmd = $include_audit_trail ? 'view audit-trail' : 'view';

  page_start_html($page);
  page_heading($page, 'Main Page');

  print '<table>';

  my $top_buttons_html = cb('main_page_top_buttons') || '';
  print $top_buttons_html;

  # Only include Create action if user is allowed to create PRs.
  # (only applicable if $no_create_without_edit flag is set)
  print one_line_form('Create Problem Report:',
                      $q->submit('cmd', 'create'))
        if can_create();
  # Only include Edit action if user is allowed to edit PRs.
  # Note: include hidden 'cmd' so user can simply type into the textfield
  # and press Enter w/o clicking.
  print one_line_form('Edit Problem Report:',
                      $q->hidden(-name=>'cmd', -value=>'edit', -override=>1),
                      $q->submit('cmd', 'edit'),
                      '#',
                      $q->textfield(-size=>6, -name=>'pr'))
        if can_edit();
  print one_line_form('View Problem Report:',
                      $q->hidden(-name=>'cmd', -value=>$viewcmd, -override=>1),
                      $q->submit('cmd', 'view'),
                      '#',
                      $q->textfield(-size=>6, -name=>'pr'));
  print one_line_form('Query Problem Reports:',
                      $q->submit('cmd', 'query'),
                      '&nbsp;', $q->submit('cmd', 'advanced query'));
  if ($site_gnatsweb_server_auth)
  {
    print one_line_form('Change Database:',
		        $q->scrolling_list(-name=>'new_db',
                               -values=>$global_list_of_dbs,
			       -default=>$global_prefs{'database'},
                               -multiple=>0,
			       -size=>1),
			$q->submit('cmd', 'change database') );
  }
  else
  {
    print one_line_form("Log Out / Change Database:&nbsp;",
                      $q->submit('cmd', 'logout'));
  }
  print one_line_form('Get Help:',
                      $q->submit('cmd', 'help'));

  my $bot_buttons_html = cb('main_page_bottom_buttons') || '';
  print $bot_buttons_html;

  print '</table>';
  page_footer($page);
  print '<hr><small>'
      . "Gnatsweb v$VERSION, Gnats v$GNATS_VERS"
      . '</small>';
  page_end_html($page);
  exit;
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
  my $val = undef;
  if (defined &site_callback)
  {
    $val = site_callback($reason, @args);
  }
  $val;
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
  my $title = $_[0];
  my $no_button_bar = $_[1];
  my @extra_head_args = @{$_[2]} if defined $_[2];
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
  push(@args, @extra_head_args);
  print $q->start_html(@args);

  # Add the page banner. The $site_banner_text is linked back to the
  # main page.
  #
  # Note that the banner uses inline style, rather than a GIF; this
  # makes installation easier by eliminating the need to install GIFs
  # into a separate directory.  At least for Apache, you can't serve
  # GIFs out of your CGI directory.
  #
  my $bannerstyle = <<EOF;
  color: $site_banner_foreground; 
  font-family: 'Verdana', 'Arial', 'Helvetica', 'sans';   
  font-weight: light;
  text-decoration: none;
EOF

  my $buttonstyle = <<EOF;
  color: $site_button_foreground;
  font-family: 'Verdana', 'Arial', 'Helvetica', 'sans';
  font-size: 8pt;
  font-weight: normal;
  text-decoration: none;
EOF

  my $banner_fontsize1 = "font-size: 14pt; ";
  my $banner_fontsize2 = "font-size: 8pt; ";

  my($row, $row2, $banner);
  my $url = "$script_name";
  $url .= "?database=$global_prefs{'database'}"
        if defined($global_prefs{'database'});

  my $createurl = get_pr_url('create', 0, 1);

  $row = qq(<tr>\n<td><table border="0" cellspacing="0" cellpadding="3" width="100%">);
  $row .= qq(<tr style="background-color: $site_banner_background">\n<td align="left">);
  $row .= qq(<span style="$bannerstyle $banner_fontsize1">$global_prefs{'database'}&nbsp;&nbsp;</span>)
                 if $global_prefs{'database'};
  $row .= qq(<span style="$bannerstyle $banner_fontsize2">User: $db_prefs{'user'}&nbsp;&nbsp;</span>)
                 if $db_prefs{'user'};
  $row .= qq(<span style="$bannerstyle $banner_fontsize2">Access: $access_level</span>)
                 if $access_level;
  $row .= qq(\n</td>\n<td align="right">
           <a href="$url" style="$bannerstyle $banner_fontsize1">$site_banner_text</a>
           </td>\n</tr>\n</table></td></tr>\n);

  $row2 = qq(<tr>\n<td colspan="2">);
  $row2 .= qq(<table border="1" cellspacing="0" bgcolor="$site_button_background" cellpadding="3">);
  $row2 .= qq(<tr>\n);
  $row2 .= qq(<td><a href="$url" style="$buttonstyle">MAIN PAGE</A></TD>);
  $row2 .= qq(<td><a href="$createurl" style="$buttonstyle">CREATE</a></td>)
        if can_create();
  $row2 .= qq(<td><a href="$url&cmd=query" style="$buttonstyle">QUERY</a></td>);
  $row2 .= qq(<td><a href="$url&cmd=advanced%20query" style="$buttonstyle">ADV. QUERY</a></td>);
  $row2 .= qq(<td><a href="$url&cmd=logout" style="$buttonstyle">LOG OUT</a></td>)
        unless ($site_gnatsweb_server_auth);
  $row2 .= qq(<td><a href="$url&cmd=help" style="$buttonstyle">HELP</a></td>);
  $row2 .= qq(</tr>\n);
  $row2 .= qq(</table>\n</td>\n</tr>);

  $banner = qq(<table width="100%" border="0" cellpadding="0" cellspacing="0">$row);
  $banner .= qq($row2) unless $no_button_bar;
  $banner .= qq(</table>);

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
  my($title, $heading) = @_;

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
  print $q->h1({-style=>'font-weight: normal'}, $heading);
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
  # Prevent a field value of all-blank characters
  $val = "" if ($val =~ /^\s*$/);
  return $val;
}

# unparse_multienum -
#     Multienum field values arrive from the form as an array.  We
#     need to put all values into one string, values separated by the
#     multienum separator specified in the field config.
sub unparse_multienum
{
  my @values = @{$_[0]};
  my $field = $_[1];
  my $valstring;

  # Prepare the string of separated values.
  $valstring = join($fielddata{$field}{'default_sep'}, @values);

  return $valstring;
}

# parse_multienum
#     Passed a properly separated Multienum value string, we parse it
#     by splitting on the multienum separator(s) specified in the
#     field config and return the result as an array ref.
sub parse_multienum
{
  my $valstring = $_[0];
  my $field = $_[1];
  
  # Split and return array ref.
  my @values = split /[$fielddata{$field}{'separators'}]/, $valstring;
  return \@values;
}

# parse_categories -
#     Parse the categories file.
sub parse_categories
{
  my(@lines) = @_;

# dtb - it looks to me like @category is only used within this sub
# so why is it used at all?
  my @category = ();
  %category_notify = ();
  %category_desc = ();

  foreach $_ (sort @lines)
  {
    my($cat, $desc, $resp, $notify) = split(/:/);
    $category_desc{$cat} = $cat . ' - ' . $desc;
    push(@category, $cat);
    $category_notify{$cat} = $notify;
  }
}

# parse_submitters -
#     Parse the submitters file.
sub parse_submitters
{
  my(@lines) = @_;

  @submitter_id = ();
  %submitter_complete = ();
  %submitter_contact = ();
  %submitter_notify = ();

  foreach $_ (sort @lines)
  {
    my($submitter, $fullname, $type, $response_time, $contact, $notify)
          = split(/:/);
    push(@submitter_id, $submitter);
    $submitter_complete{$submitter} = $submitter .' - ' . $fullname;
    $submitter_contact{$submitter} = $contact;
    $submitter_notify{$submitter} = $notify;
  }
}

# parse_responsible -
#     Parse the responsible file.
sub parse_responsible
{
  my(@lines) = @_;

  @responsible = ();
  %responsible_fullname = ();
  %responsible_address = ();

  foreach $_ (sort @lines)
  {
    my($person, $fullname, $address) = split(/:/);
    push(@responsible, $person);
    $responsible_fullname{$person} = $fullname;
    $responsible_complete{$person} = $person . ' - ' . $fullname;
    $responsible_address{$person} = $address || $person;
  }
}

# initialize -
#     Initialize gnatsd-related globals and login to gnatsd.
#
sub initialize
{
  my $regression_testing = shift;

  my(@lines);
  my $response;

  ($response) = client_init();

  # Get gnatsd version from initial server connection text.
  if ($response =~ /GNATS server (.*) ready/)
  {
    $GNATS_VERS = $1;
  }

  # Suppress fatal exit while issuing CHDB and USER commands.  Otherwise
  # an error in the user or database cookie values can cause a user to
  # get in a bad state.
  LOGIN:
  {
    local($suppress_client_exit) = 1
          unless $regression_testing;

  	# Issue DBLS command, so that we have a list of databases, in case
  	# the user has tried to get into a db they don't have access to,
  	# after which we won't be able to do this

  	my (@db_list) = client_cmd("dbls");
  	if (length($db_list[0]) == 0 || $client_would_have_exited) {
  	    login_page($q->url());
  	    exit();
  	} else {
  	    # store the list of databases for later use
  	    $global_list_of_dbs = \@db_list;
  	}

  	# Issue CHDB command; revert to login page if it fails.
  	# use the three-arg version, to authenticate at the same time
  	my (@chdb_response) = client_cmd("chdb $global_prefs{'database'} $db_prefs{'user'} $db_prefs{'password'}");
  	if (length($chdb_response[0]) == 0 || $client_would_have_exited) {
  	    login_page($q->url());
  	    exit();
  	}

  	# Get user permission level from the return value of CHDB
  	# three arg CHDB should return something like this:
  	# 210-Now accessing GNATS database 'foo'
  	# 210 User access level set to 'edit'
  	if ($chdb_response[1] =~ /User access level set to '(\w*)'/) {
  	    $access_level = lc($1);
  	} else {
  	    $access_level = 'view';
  	}

  	# check access level.  if < view, make them log in again.
        # it might be better to allow "create-only" access for users
        # with 'submit' access.
  	if ($LEVEL_TO_CODE{$access_level} < $LEVEL_TO_CODE{'view'}) {
  	    login_page(undef, "You do not have access to database: $global_prefs{'database'}.<br />\nPlease log in to another database<br /><br />\n");
  	    undef($suppress_client_exit);
  	    client_exit();
  	}
    }

    # Now initialize our metadata from the database.
    init_fieldinfo ();

  # List various gnats-adm files, and parse their contents for data we
  # will need later.  Each parse subroutine stashes information away in
  # its own global vars.  The call to client_cmd() happens here to
  # enable regression testing of the parse subs using fixed files.
  @lines = client_cmd("LIST Categories");
  parse_categories(@lines);
  @lines = client_cmd("LIST Submitters");
  parse_submitters(@lines);
  @lines = client_cmd("LIST Responsible");
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
  my @addrs = split_csl ($addrs);
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
    my ($hdr, $arg, $ghdr) = ($1, $2, "*not valid*");
    if($hdr =~ /^>(.*)$/)
    {
      $ghdr = $1;
    }

    my $cleanhdr = $ghdr;
    $cleanhdr =~ s/^>([^:]*).*$/$1/;

    if(isvalidfield ($cleanhdr))
    {
      if(fieldinfo($cleanhdr, 'fieldtype') eq 'multitext')
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
       ($hdr eq "Reply-To" || $hdr eq "From"))
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
  $fields{$UNFORMATTED_FIELD} ||= ''; # Default to empty value
  $fields{$UNFORMATTED_FIELD} =~ s/\n$//;

  # Decode attachments stored in Unformatted field.
  my $any_attachments = 0;
  if (can_do_mime()) {
    my(@attachments) = split(/$attachment_delimiter/, $fields{$UNFORMATTED_FIELD});
    # First element is any random text which precedes delimited attachments.
    $fields{$UNFORMATTED_FIELD} = shift(@attachments);
    foreach my $attachment (@attachments) {
      warn "att=>$attachment<=\n" if $debug;
      $any_attachments = 1;
      # Strip leading spaces on each line of the attachment
      $attachment =~ s/^[ ]//mg;
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
    foreach my $href (@$aref) {
      warn "    ----\n";
      my ($k,$v);
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
#         'gnatsd'  - PR will be filed using gnatsd; proper '.' escaping done
#         'send'    - PR will be field using gnatsd, and is an initial PR.
#         'test'    - we're being called from the regression tests
sub unparsepr
{
  my($purpose, %fields) = @_;
  my($tmp, $text);
  my $debug = 0;

  # First create or reconstruct the Unformatted field containing the
  # attachments, if any.
  $fields{$UNFORMATTED_FIELD} ||= ''; # Default to empty.
  warn "unparsepr 1 =>$fields{$UNFORMATTED_FIELD}<=\n" if $debug;
  my $array_ref = $fields{'attachments'};
  foreach my $hash_ref (@$array_ref) {
    my $attachment_data = $$hash_ref{'original_attachment'};
    # Deleted attachments leave empty hashes behind.
    next unless defined($attachment_data);
    $fields{$UNFORMATTED_FIELD} .= $attachment_delimiter . $attachment_data . "\n";
  }
  warn "unparsepr 2 =>$fields{$UNFORMATTED_FIELD}<=\n" if $debug;

  # Reconstruct the text of the PR into $text.
  $text = $fields{'envelope'};
  foreach (@fieldnames)
  {
    # Do include Unformatted field in 'send' operation, even though
    # it's excluded.  We need it to hold the file attachment.
    # XXX ??? !!! FIXME
    if(($purpose eq 'send')
       && (! (fieldinfo ($_, 'flags') & $SENDINCLUDE))
       && ($_ ne $UNFORMATTED_FIELD))
    {
      next;
    }
    if(fieldinfo($_, 'fieldtype') eq 'multitext')
    {
      # Lines which begin with a '.' need to be escaped by another '.'
      # if we're feeding it to gnatsd.
      $tmp = $fields{$_};
      $tmp =~ s/^[.]/../gm
            if ($purpose ne 'test');
      $text .= sprintf(">$_:\n%s", $tmp);
    }
    else
    {
      # Format string derived from gnats/pr.c.
      $fields{$_} ||= ''; # Default to empty
      $text .= sprintf("%-16s %s\n", ">$_:", $fields{$_});
    }
    if (exists ($fields{$_."-Changed-Why"}))
    {
      # Lines which begin with a '.' need to be escaped by another '.'
      # if we're feeding it to gnatsd.
      $tmp = $fields{$_."-Changed-Why"};
      $tmp =~ s/^[.]/../gm
            if ($purpose ne 'test');
      $text .= sprintf(">$_-Changed-Why:\n%s\n", $tmp);
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

  # Not sure if we want to do a RSET here but it probably won't hurt.
  client_cmd ("rset");
  client_cmd ("QFMT full");
  return parsepr(client_cmd("quer $pr"));
}

# interested_parties -
#     Get list of parties to notify about a PR change.
#
#     Returns hash in array context; string of email addrs otherwise.
sub interested_parties
{
  my($pr, %fields) = @_;

  my(@people);
  my $person;
  my $list;

  # Get list of people by constructing it ourselves.
  @people = ();
  foreach $list ($fields{'Reply-To'},
                 $fields{$RESPONSIBLE_FIELD},
                 $category_notify{$fields{$CATEGORY_FIELD}},
                 $submitter_contact{$fields{$SUBMITTER_ID_FIELD}},
                 $submitter_notify{$fields{$SUBMITTER_ID_FIELD}})
  {
    if (defined($list)) {
      foreach $person (split_csl ($list))
      {
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

# Split comma-separated list.
# Commas in quotes are not separators!
sub split_csl
{
  my ($list) = @_;
  
  # Substitute commas in quotes with \002.
  while ($list =~ m~"([^"]*)"~g)
  {
    my $pos = pos($list);
    my $str = $1;
    $str =~ s~,~\002~g;
    $list =~ s~"[^"]*"~"$str"~;
		 pos($list) = $pos;
  }

  my @res;
  foreach my $person (split(/\s*,\s*/, $list))
  {
    $person =~ s/\002/,/g;
    push(@res, $person) if $person;
  }
  return @res;
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
    document.write(
         "<p><strong>Warning: your browser is not accepting cookies!</strong> "
        +"Unfortunately, Gnatsweb requires cookies to keep track of your "
        +"login and other information. "
        +"Please enable cookies before logging in.</p>");
}

//-->
</SCRIPT>
<noscript>
<p>(Due to the fact that your browser does not support Javascript,
there is no way of telling whether it can accept cookies.)

Unfortunately, Gnatsweb requires cookies to keep track of your
login and other information. 
Please enable cookies before logging in.</p>
</noscript>   
  };
}
 

# change the database in the global cookie
#
sub change_database
{
    $global_prefs{'database'} = $q->param('new_db');
    my $global_cookie = create_global_cookie();
    my $url = $q->url();
    # the refresh header chokes on the query-string if the
    # params are separated by semicolons...
    $url =~ s/\;/&/g;

    print_header(-Refresh => "0; URL=$url",
                     -cookie => [$global_cookie]),
          $q->start_html();
    print $q->h3("Hold on... Redirecting...<br />".
                 "In case it does not work automatically, please follow ".
                 "<a href=\"$url\">this link</a>."),
    $q->end_html();
}

# clear the db_prefs cookie containing username and password and take
# the user back to the login page
sub cmd_logout
{
  my $db = $global_prefs{'database'};
  my $db_cookie = $q->cookie(-name => "gnatsweb-db-$db",
                             -value => 'does not matter',
                             -path => $global_cookie_path,
                             -expires => '-1d');
  my $url = $q->url();
  # the refresh header chokes on the query-string if the
  # params are separated by semicolons...
  $url =~ s/\;/&/g;

  print_header(-Refresh => "0; URL=$url",
               -cookie => [$db_cookie]),
  $q->start_html();
  print $q->h3("Hold on... Redirecting...<br />".
               "In case it does not work automatically, please follow ".
               "<a href=\"$url\">this link</a>."),
  $q->end_html();
}

# execute the login, after the user submits from the login page
#
sub cmd_login {
    unless ($site_gnatsweb_server_auth) {
	# first, do some sanity checking on the username
	# user name must be something reasonable
	# and must not be all digits (like a PR number...)
	my $user = $q->param('user');
	if ($user !~ /^[\w-]+$/ || $user !~ /[a-z]/i) {
	    if ($user =~ /\s/) {
		$user = $user . ' (contains whitespace)';
	    }
	    print_header();
	    login_page(undef, 'Invalid User Name: "'.$user.'", please log in again');
	    exit();
	}
    }

    my $global_cookie = create_global_cookie();
    my $db = $global_prefs{'database'};

    # Have to generate the cookie before printing the header.
    my %cookie_hash = (
                       -name => "gnatsweb-db-$db",
                       -value => camouflage(\%db_prefs),
                       -path => $global_cookie_path
                       );
    %cookie_hash = (%cookie_hash, -expires => $global_cookie_expires)
          unless $use_temp_db_prefs_cookie;
    my $db_cookie = $q->cookie(%cookie_hash);

    my $expire_old_cookie = $q->cookie(-name => 'gnatsweb',
                               -value => 'does not matter',
                               #-path was not used for gnatsweb 2.5 cookies
                               -expires => '-1d');
    my $url = $q->param('return_url');
    # the refresh header chokes on the query-string if the
    # params are separated by semicolons...
    $url =~ s/\;/&/g;

    # 11/27/99 kenstir: Try zero-delay refresh all the time.
    $url = $q->url() if (!defined($url));
    # 11/14/99 kenstir: For some reason doing cookies + redirect didn't
    # work; got a 'page contained no data' error from NS 4.7.  This cookie
    # + redirect technique did work for me in a small test case.
    #print $q->redirect(-location => $url,
    #                   -cookie => [$global_cookie, $db_cookie]);
    # So, this is sort of a lame replacement; a zero-delay refresh.
    print_header(-Refresh => "0; URL=$url",
                     -cookie => [$global_cookie, $db_cookie, $expire_old_cookie]),
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
    print $q->h3("Hold on... Redirecting...<br />".
                 "In case it does not work automatically, please follow ".
                 "<a href=\"$url\">this link</a>."),
    $q->end_html();
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
  my ($return_url, $message) = @_;
  my $page = 'Login';
  page_start_html($page, 1);
  page_heading($page, 'Login');

  print login_page_javascript();

  my $html = cb('login_page_text');
  print $html || '';

  if ($message) {
      print $message;
  }

  client_init();
  my(@dbs) = client_cmd("dbls");
  print $q->start_form(), hidden_debug(), "<table>";
  unless($site_gnatsweb_server_auth) {
      print "<tr><td><font color=\"red\"><b>User Name</b></font>:</td><td>",
        $q->textfield(-name=>'user',
                      -size=>20,
                      -default=>$db_prefs{'user'}),
        "</td>\n</tr>\n";
      if ($site_no_gnats_passwords) {
	  # we're not using gnats passwords, so the password input
	  # is superfluous.  put in a hidden field with a bogus value,
	  # just so other parts of the program don't get confused
	  print qq*<input type="hidden" name="password" value="not_applicable">*;
      } else {
	    print "<tr>\n<td>Password:</td>\n<td>",
	    $q->password_field(-name=>'password',
			       -value=>$db_prefs{'password'},
			       -size=>20),
            "</td>\n</tr>\n";
      }
  }
  print "<tr>\n<td>Database:</td>\n<td>",
        $q->popup_menu(-name=>'database',
                       -values=>\@dbs,
                       -default=>$global_prefs{'database'}),
        "</td>\n</tr>\n",
        "</table>\n";
  if (defined($return_url))
  {
    print $q->hidden('return_url', $return_url);
  }
  # we need this extra hidden field in case users
  # just type in a username and hit return.  this will
  # ensure that cmd_login() gets called to process the login.
  print qq*<input type="hidden" name="cmd" value="login">*;
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
  my $i = 0;
  foreach my $y ($q->cookie())
  {
    @c = $q->cookie($y);
    warn "got cookie: length=", scalar(@c), ": $y =>@c<=\n";
    $i += length($y);
  }
#  @c = $q->raw_cookie();
#  warn "debug 0.5: @c:\n";
#  warn "debug 0.5: total size of raw cookies: ", length("@c"), "\n";
}

# set_pref -
#     Set the named preference.  Param values override cookie values, and
#     don't set it if we end up with an undefined value.
#
sub set_pref
{
  my($pref_name, $pref_hashref, $cval_hashref) = @_;
  my $val = $q->param($pref_name) || ($pref_name eq "password" ?
              uncamouflage($$cval_hashref{$pref_name}) :
              $$cval_hashref{$pref_name}
      );

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
    use Data::Dumper;
    $Data::Dumper::Terse = 1;
    warn "-------------- init_prefs -------------------\n";
  }

  # Global prefs.
  my %cvals = $q->cookie('gnatsweb-global');
  if (! %cvals) {
    $global_no_cookies = 1;
  }

  # deal with legacy cookies, which used email_addr
  if ($cvals{'email_addr'})
  {
      $cvals{'email'} = $cvals{'email_addr'};
  }

  %global_prefs = ();
  set_pref('database', \%global_prefs, \%cvals);
  set_pref('email', \%global_prefs, \%cvals);
  set_pref($ORIGINATOR_FIELD, \%global_prefs, \%cvals);
  set_pref($SUBMITTER_ID_FIELD, \%global_prefs, \%cvals);

  # columns is treated differently because it's an array which is stored
  # in the cookie as a joined string.
  if ($q->param('columns')) {
    my(@columns) = $q->param('columns');
    $global_prefs{'columns'} = join(' ', @columns);
  }
  elsif (defined($cvals{'columns'})) {
    $global_prefs{'columns'} = $cvals{'columns'};
  }

  if (!$cvals{'email'}) {
      $global_prefs{'email'} = $q->param('email') || '';
  }

  # DB prefs.
  my $database = $global_prefs{'database'} || '';
  if ($site_gnatsweb_server_auth)
  {
    # we're not using cookies for user/password
    # since the server is doing authentication
    %cvals = ( 'password' => $ENV{REMOTE_USER},
	       'user'     => $ENV{REMOTE_USER} );
  }
  else
  {
   %cvals = $q->cookie("gnatsweb-db-$database");
  }
  %db_prefs = ();
  set_pref('user', \%db_prefs, \%cvals);
  set_pref('password', \%db_prefs, \%cvals);

  # Debug.
  warn "global_prefs = ", Dumper(\%global_prefs) if $debug;
  warn "db_prefs = ", Dumper(\%db_prefs) if $debug;
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

# camouflage -
#     If passed a scalar, camouflages it by XORing it with 19 and
#     reversing the string.  If passed a hash reference with key
#     "password", it camouflages the values of this key  using the
#     same algorithm.
#
sub camouflage
{
  my $clear = shift || '';
  if (ref($clear) =~ "HASH")
  {
    my $res = {};
    foreach my $key (keys %$clear)
    {
      $$res{$key} = ( $key eq "password" ?
                     camouflage($$clear{$key}) : $$clear{$key} );
    }
    return $res;
  }
  $clear =~ s/(.)/chr(19 ^ ord $1)/eg;
  return (reverse $clear) || '';
}

# uncamouflage
#     Since the camouflage algorithm employed is symmetric...
#
sub uncamouflage
{
  return camouflage(@_);
}

#
# MAIN starts here:
#
sub main
{
  # Load $gnatsweb_site_file if present.  Die if there are errors;
  # otherwise the person who wrote $gnatsweb_site_file will never know it.
  if (-e $gnatsweb_site_file && -r $gnatsweb_site_file) {
      open(GWSP, "<$gnatsweb_site_file");
      local $/ = undef;
      my $gnatsweb_site_pl = <GWSP>;
      eval($gnatsweb_site_pl);
      if ($@) {
	  warn("gnatsweb: error in eval of $gnatsweb_site_file: $@; user=$db_prefs{'user'}, db=$global_prefs{'database'}; stacktrace: ", print_stacktrace());
	  die $@
      }
  }

  # Make sure nobody tries to swamp our server with a huge file attachment.
  # Has to happen before 'new CGI'.
  $CGI::POST_MAX = $site_post_max if defined($site_post_max);

  # Create the query object.  Check to see if there was an error, which
  # happens if the post exceeds POST_MAX.
  $q = new CGI;
  if ($q->cgi_error())
  {
    print_header(-status=>$q->cgi_error());
          $q->start_html('Error');
    page_heading('Initialization failed', 'Error');
    print $q->h3('Request not processed: ', $q->cgi_error());
    warn("gnatsweb: cgi error: ", $q->cgi_error(), " ; user=$db_prefs{'user'}, db=$global_prefs{'database'}; stacktrace: ", print_stacktrace());
    exit();
  }

  if ($site_allow_remote_debug) {
    my $debugparam = $q->param('debug') || '';
    # check for debug flag in query string.
    if ($debugparam eq 'cmd') {
	  $client_cmd_debug = 1;
    }
    if ($debugparam eq 'reply') {
	  $reply_debug = 1;
    }
    if ($debugparam eq 'all') {
	  $reply_debug = 1;
	  $client_cmd_debug = 1;
    }
  }

  $script_name = $q->script_name;
  my $cmd = $q->param('cmd') || ''; # avoid perl -w warning

  ### Cookie-related code must happen before we print the HTML header.
  init_prefs();

  if(!$global_prefs{'database'}
        || !$db_prefs{'user'})
  {
    # We don't have username/database; give login page then
    # redirect to the url they really want (self_url).
    print_header();
    login_page($q->self_url());
    exit();
  }

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
  elsif($cmd eq 'change database')
  {
    # change the user's database in global cookie
    change_database();
    exit();
  }
  elsif($cmd eq 'submit stored query')
  {
    submit_stored_query();
    exit();
  }
  elsif($cmd eq 'login')
  {
    cmd_login();
  }
  elsif($cmd eq 'logout')
  {
    # User is logging out.
    cmd_logout();
    exit();
  }
  elsif($cmd eq 'submit')
  {
    initialize();

    # Only include Create action if user is allowed to create PRs.
    # (only applicable if $no_create_without_edit flag is set)
    main_page() unless can_create();

    submitnewpr();
    exit();
  }
  elsif($cmd eq 'submit query')
  {
    # User is querying.  Store cookie because column display list may
    # have changed.
    print_header(-cookie => create_global_cookie());
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
    print_header();
    initialize();

    # Only include Create action if user is allowed to create PRs.
    # (only applicable if $no_create_without_edit flag is set)
    main_page() unless can_create();

    sendpr();
  }
  elsif($cmd eq 'view')
  {
    print_header();
    initialize();
    view(0);
  }
  elsif($cmd eq 'view audit-trail')
  {
    print_header();
    initialize();
    view(1);
  }
  elsif($cmd eq 'edit')
  {
    print_header();
    initialize();

    # Only include Edit action if user is allowed to Edit PRs.
    main_page() unless can_edit();

    edit();
  }
  elsif($cmd eq 'submit edit')
  {
    initialize();

    # Only include Edit action if user is allowed to Edit PRs.
    main_page() unless can_edit();

    submitedit();
  }
  elsif($cmd eq 'query')
  {
    print_header();
    initialize();
    query_page();
  }
  elsif($cmd eq 'advanced query')
  {
    print_header();
    initialize();
    advanced_query_page();
  }
  elsif($cmd eq 'store query')
  {
    print_header();
    initialize();
    store_query();
  }
  elsif($cmd eq 'help')
  {
    print_header();
    initialize();
    help_page();
  }
  elsif (cb('cmd', $cmd)) {
    ; # cmd was handled by callback
  }
  else
  {
    print_header();
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

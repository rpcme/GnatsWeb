package gnats;

# See the bottom of this file for the POD documentation.  Search for the
# string '=head'.

# You can run this file through either pod2man or pod2html to produce pretty
# documentation in manual or html file format (these utilities are part of the
# Perl 5 distribution).

use Socket;
use IO::Handle;
use Carp;

# Version stuff
$VERSION = '0.1';
$REVISION = (split(/ /, '$Revision: 1.2 $ '))[1];

use Exporter ();
@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(&client_init &client_cmd &client_exit);

# Package variables

$ERRSTR = '';                # error string
$FULL_ERRSTR = '';           # full error string from gnatsd
$DEBUG_LEVEL = 0;            # controls debug stmts
$RAISE_ERROR = 0;            # call die on error

# Local variables

# Gnatsd-related "constants"

my $REPLY_CONT = 1;
my $REPLY_END = 2;

my $CODE_GREETING = 200;
my $CODE_OK = 210;
my $CODE_PR_READY = 220;
my $CODE_CLOSING = 205;
my $CODE_INFORMATION = 230;
my $CODE_HELLO = 250;

my $CODE_INVALID_PR = 410;
my $CODE_INVALID_CATEGORY = 420;
my $CODE_UNREADABLE_PR = 430;
my $CODE_NO_PRS = 440;
my $CODE_NO_KERBEROS = 450;
my $CODE_INVALID_SUBMITTER = 460;
my $CODE_INVALID_STATE = 461;
my $CODE_INVALID_RESPONSIBLE = 465;
my $CODE_INVALID_DATE = 468;
my $CODE_FILE_ERROR = 480;
my $CODE_LOCKED_PR = 490;
my $CODE_GNATS_LOCKED = 491;
my $CODE_PR_NOT_LOCKED = 495;

my $CODE_ERROR = 500;
my $CODE_NO_ACCESS = 520;

sub clearerr
{
  $ERRSTR = '';
  $FULL_ERRSTR = '';
}

sub gerror
{
  my($text) = @_;
  $ERRSTR = $text;
  croak "Error: $text" if ($RAISE_ERROR);
  warn "Error: $text" if ($DEBUG_LEVEL >= 1);
}

sub client_exit
{
  close(SOCK);
}

sub server_reply
{
  my($state, $text, $type);
  $_ = <SOCK>;
  warn "server_reply: $_" if ($DEBUG_LEVEL >= 2);
  if(/(\d+)([- ]?)(.*$)/)
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
        $FULL_ERRSTR = $_;
        gerror("bad type of reply from server");
      }
      $type = $REPLY_END;
    }
    return ($state, $text, $type);
  }
  return (undef, undef, undef);
}

sub read_server
{
  my(@text);

  while(<SOCK>)
  {
    warn "read_server: $_" if ($DEBUG_LEVEL >= 3);
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
  my($state, $text, $type) = server_reply();
  my(@rettext) = ($text);
  if($state == $CODE_GREETING)
  {
    while($type == $REPLY_CONT)
    {
      ($state, $text, $type) = server_reply();
      if(!defined($state))
      {
        gerror("null reply from the server");
        return undef;
      }
      push(@rettext, $text);
    }
  }
  elsif($state == $CODE_OK || $state == $CODE_HELLO)
  {
    # nothing
  }
  elsif($state == $CODE_CLOSING)
  {
    # nothing
  }
  elsif($state == $CODE_PR_READY)
  {
    @rettext = read_server();
  }
  elsif($state == $CODE_INFORMATION)
  {
    ($state, $text, $type) = server_reply();
    while($type == $REPLY_CONT)
    {
      push(@rettext, $text);
      ($state, $text, $type) = server_reply();
    }
  }
  elsif($state == $CODE_INVALID_PR)
  {
    $FULL_ERRSTR = $text;
    $text =~ / (.*)/;
    gerror("couldn't find $1");
    return undef;
  }
  elsif($state == $CODE_INVALID_CATEGORY)
  {
    $FULL_ERRSTR = $text;
    $text =~ / (.*)/;
    gerror($1);
    return undef;
  }
  elsif($state == $CODE_INVALID_SUBMITTER)
  {
    $FULL_ERRSTR = $text;
    $text =~ / (.*)/;
    gerror($1);
    return undef;
  }
  elsif($state == $CODE_INVALID_STATE)
  {
    $FULL_ERRSTR = $text;
    $text =~ / (.*)/;
    gerror("no such state $1");
    return undef;
  }
  elsif($state == $CODE_INVALID_RESPONSIBLE)
  {
    $FULL_ERRSTR = $text;
    $text =~ / (.*)/;
    gerror($1);
    return undef;
  }
  elsif($state == $CODE_INVALID_DATE)
  {
    $FULL_ERRSTR = $text;
    $text =~ / (.*)/;
    gerror($1);
    return undef;
  }
  elsif($state == $CODE_UNREADABLE_PR)
  {
    $FULL_ERRSTR = $text;
    $text =~ / (.*)/;
    gerror("couldn't read $1");
    return undef;
  }
  elsif($state == $CODE_PR_NOT_LOCKED)
  {
    $FULL_ERRSTR = $text;
    gerror("PR is not locked");
    return undef;
  }
  elsif($state == $CODE_LOCKED_PR ||
        $state == $CODE_FILE_ERROR ||
	$state == $CODE_ERROR)
  {
    $FULL_ERRSTR = $text;
    $text =~ s/\r//g;
    gerror($text);
    return undef;
  }
  elsif($state == $CODE_GNATS_LOCKED)
  {
    $FULL_ERRSTR = $text;
    gerror("lock file exists");
    return undef;
  }
  elsif($state == $CODE_NO_PRS)
  {
    # 1/6/2000 kenstir: I don't consider this an error; don't set ERRSTR.
    # 4/30/2001 yngves: Not really an error, but we still need to return something to Gnatsweb.
    # $FULL_ERRSTR = $text;
    gerror("no PRs matched");
    return ();
  }
  elsif($state == $CODE_NO_KERBEROS)
  {
    $FULL_ERRSTR = $text;
    gerror("no Kerberos support, authentication failed");
    return undef;
  }
  elsif($state == $CODE_NO_ACCESS)
  {
    $FULL_ERRSTR = $text;
    gerror("access denied");
    return undef;
  }
  else
  {
    $FULL_ERRSTR = $text;
    gerror("cannot understand $state '$text'");
    return undef;
  }
  return @rettext;
}

# client_init($host,$port)
# 
sub client_init
{
  my($host, $port) = @_;
  my($iaddr, $paddr, $proto, $line, $length);

  clearerr();
  warn "client_init: $host $port\n" if ($DEBUG_LEVEL >= 1);

  if (!$host && !$port) {
    carp("client_init called with null argument(s)");
    return undef;
  }

  $iaddr = inet_aton($host);
  $paddr = sockaddr_in($port, $iaddr);

  $proto = getprotobyname('tcp');
  if(!socket(SOCK, PF_INET, SOCK_STREAM, $proto))
  {
    gerror("socket: $!");
    return undef;
  }
  if(!connect(SOCK, $paddr))
  {
    gerror("connect: $!");
    return undef;
  }
  SOCK->autoflush(1);
  return get_reply();
}

# client_cmd -
#     Send a command to gnatsd and return the response.  Response is a
#     list of lines.
#
# to debug:
#     $gnats::DEBUG_LEVEL = 1;
#
sub client_cmd
{
  my($cmd) = @_;
  clearerr();
  warn "client_cmd: $cmd\n" if ($DEBUG_LEVEL >= 1);
  print SOCK "$cmd\n";
  return get_reply();
}

1;

__END__

=head1 NAME

gnats - interface to GNATS network daemon

=head1 SYNOPSIS

    # A simple script to connect to gnatsd and get a list
    # of the open PRs.
    use gnats;
    $gnats::DEBUG_LEVEL = 1;
    $gnats::RAISE_ERROR = 1;

    # login to gnatsd
    gnats::client_init('gnats', 1529);
    gnats::client_cmd('chdb main');
    gnats::client_cmd('user kenstir password');

    # NOCL - ignore closed PRs
    # SQL2 - issue query and return list in sql-like format
    gnats::client_cmd('nocl');
    @open_prs = gnats::client_cmd('sql2');

    # print the PRs
    $num_prs = @open_prs;
    printf("\n%s open %s found\n\n",
           $num_prs ? $num_prs : "No",
           ($num_prs == 1) ? "PR" : "PRs");
    printf "%4s %12s %s\n", "PR", "Category", "Synopsis";
    printf "---------------------------------------------\n";
    foreach $pr (@open_prs) {
        ($id, $category, $synopsis) = split('\|', $pr);
        printf "%4d %12s %s\n", $id, $category, $synopsis;
    }
    gnats::client_exit();

=head1 DESCRIPTION

This module makes it easy to write scripts which talk to GNATS, the
GNU bug tracking system, through gnatsd the GNATS network daemon.

=head1 SEE ALSO

The GNATS home page at
http://sourceware.cygnus.com/gnats/

=head1 AUTHOR

Copyright 1998-2000 by Matt Gerassimoff and Kenneth Cox.

The gnatsd code was written by Matt Gerassimoff and it was put into
this awful package by Kenneth Cox who also turned it into gnatsweb.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# Emacs stuff -
#
# Local Variables:
# perl-indent-level:2
# perl-continued-brace-offset:-6
# perl-continued-statement-offset:6
# End:

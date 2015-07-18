#!/usr/bin/perl
#
# test.pl -
#      Test code for GNU Gnatsweb
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
# $Id: test.pl,v 1.8.2.1 2003/07/29 12:24:22 yngves Exp $
#

#-----------------------------------------------------------------------------
# test harness setup

use POSIX;
use Getopt::Std;

getopts('d');

$suppress_main = 1;
do 'gnatsweb.pl';
die $@ if $@;
do './gnatsweb-site.pl' if (-e './gnatsweb-site.pl');
die $@ if $@;

$errors = 0;

open(LOG, ">test.log") || die;

# turn on debug options if -d
$client_cmd_debug = $opt_d;

# get connection info from environment
$db_prefs{'user'}         = $ENV{'USERNAME'} || 'anonymous';
$db_prefs{'password'}     = $ENV{'PASSWORD'} || 'guest';
$global_prefs{'database'} = $ENV{'DATABASE'} || 'main';

#-----------------------------------------------------------------------------
# support subs

# print the test summary
sub sum {
    my($test, $passed) = @_;
    print $test, '.' x (50 - length($test));
    if ($passed) {
        print "pass\n";
    }
    else {
        $errors++;
        print "FAIL\n";
        if ($test eq 'connect')
        {
            print <<EOF;

Gnatsweb was unable to connect to the GNATS server.

There are several possible reasons for this.  Start off by checking
that the USERNAME, PASSWORD and DATABASE parameters you supplied are
valid.  If they are, there may be a problem in the configuration of
your GNATS server.  Check your GNATS installation, particularly the
host access files (remember that the web server needs access to the
GNATS server), then run the tests again.

EOF
        }
    }
}

# if program exits while we are running a test, this is a failure!
END {
    if ($test) {
        sum($test, 0);
    }
    # can't exit from here
    #exit $errors;
}

#-----------------------------------------------------------------------------
# connect -
#
#     Connect to gnatsd and initialize.
$test = 'connect';
local $SIG{__WARN__} = END;
local $SIG{__DIE__} = END;
open(STDERR, "/dev/null");
initialize('regression_testing');
sum($test, $access_level);
# can't do anything if this test fails
exit $errors if $errors;
#-----------------------------------------------------------------------------
# query -
#
#     Simple query.  Results used for parsepr/unparsepr test

$test = 'query';
client_cmd("qfmt sql2");
@query_results = client_cmd("quer");
sum($test, $#query_results + 1);

#-----------------------------------------------------------------------------
# address parsing -
#     Make sure that parsing addresses works.

# maps original => expected return value
%test_addrs = ('"Kenneth H. Cox" <kenstir@senteinc.com>, bug-gnats@gnu.org'
               => 'kenstir@senteinc.com, bug-gnats@gnu.org',
               'Rick Macdonald <rickm@vsl.com>'
               => 'rickm@vsl.com',
               'mg@digalogsys.com'
               => 'mg@digalogsys.com',
               'gnats-admin@senteinc.com (GNATS Management)'
               => 'gnats-admin@senteinc.com',
               'Rick Macdonald <rickm@vsl.com>, Paul Traina <pst@juniper.net>'
               => 'rickm@vsl.com, pst@juniper.net',
               );

$i = 1;
foreach $key (keys %test_addrs) {
    $test = "fix_email_addrs $i";
    print LOG "test: $test\n";
    $new_addr = fix_email_addrs($key);
    $expected_addr = $test_addrs{$key};
    print LOG "\texpected_addr: $expected_addr\n\tnew_addr: $new_addr\n";
    sum($test, ($new_addr eq  $expected_addr));
    $i++;
}

#-----------------------------------------------------------------------------
# trim_responsible -
#     Test sub by this name.

# maps original => expected return value
%test_data = ('kenstir (Kenneth Cox)' => 'kenstir',
              'kenstir' => 'kenstir',
              'Matt-Gerassimoff' => 'Matt-Gerassimoff',
              );

$i = 1;
foreach $key (keys %test_data) {
    $test = "trim_responsible $i";
    print LOG "test: $test\n";
    $got = trim_responsible($key);
    $expected = $test_data{$key};
    print LOG "\texpected: $expected\n\tgot: $got\n";
    sum($test, ($got eq  $expected));
    $i++;
}

#-----------------------------------------------------------------------------
# finalize

$test = '';
if ($errors) {
    exit $errors;
}
else {
    print "All tests passed.\n";
    exit 0;
}

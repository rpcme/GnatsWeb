#!/usr/bin/perl
#
# gnats-test.pl -
#      Test code for gnats-lib.pl
#
# $Id: test.pl,v 1.1.1.1 2001/04/28 11:00:57 yngves Exp $

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
initialize('regression_testing');
sum($test, $access_level);

# can't do anything if this test fails
exit $errors if $errors;

#-----------------------------------------------------------------------------
# query -
#
#     Simple query.  Results used for parsepr/unparsepr test

$test = 'query';
@query_results = client_cmd("sql2");
sum($test, $#query_results + 1);

#-----------------------------------------------------------------------------
# parse_pr, unparse_pr -
#
#     loop over first PRs found (max 50) and make sure
#     that parsing and then unparsing them does not change the PR.

# trim @query_results to be PR numbers only
map { $_ = (split/\|/, $_)[0] } @query_results;

# sort it by PR number
@query_results = sort { $a <=> $b } @query_results;

# trim it to 50 PR's max
#if ($ENV{'LOGNAME'} ne 'kenstir') {
    splice(@query_results, 49);
#} else {
#    # kenstir-special test.
#    #splice(@query_results, 49);
#    #@query_results = (42,43,44);
#}

foreach my $mypr (@query_results) {
    $test = "parsepr/unparsepr $mypr";
    print LOG "test: $test\n";
    my %fields = readpr($mypr);
    my $reconstructed_pr = unparsepr('test', %fields);
    my @pr_lines = client_cmd("full $mypr");
    my $orig_pr = join("\n", @pr_lines);
    my $ok = 1;
    if ($orig_pr ne $reconstructed_pr) {
        # print PRs into two files and use diff for ease of debugging
        my $origfile = POSIX::tmpnam();
        open(ORIG, ">$origfile") || die;
        print ORIG $orig_pr;
        close(ORIG) || die;

        my $newfile = POSIX::tmpnam();
        open(NEW, ">$newfile") || die;
        print NEW $reconstructed_pr;
        close(NEW) || die;

        # 12/18/99: Not everyone has gnu diff; don't use -u by default.
        #my $cmd = "diff -u $origfile $newfile";
        my $cmd = "diff $origfile $newfile";
        my $result = `$cmd`;
        if ($?) {
            print LOG "-"x50, " pr: $mypr\n$cmd\n", $result;
            $ok = 0;
        }
        #unlink($origfile, $newfile);
    }
    sum($test, $ok);
}

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

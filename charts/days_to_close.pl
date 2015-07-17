#!/usr/bin/perl -w
#
# Display the opened_vs_closed chart.
#
# $Id: days_to_close.pl,v 1.1.2.2 2001/07/01 17:46:36 yngves Exp $

# BEGIN configuration
@GNATS_LOGIN_DATA = ('gnats', 1529, 'main', 'guest', 'guest');
# END configuration

# Get the output stream going.
use CGI::Carp qw(fatalsToBrowser);
use CGI qw(:standard);
print header('image/gif');

# Use some pkgs.
use lib "..";
use gnats::chart;
use File::Basename;

# Create a chart object (login to gnatsd).
$chart = gnats::chart->new(@GNATS_LOGIN_DATA,
                           { RaiseError => 1, DebugLevel => 0 });

# Set the chart's features.
$now = time();
$twelve_weeks_ago = $now - 12 * 7 * (24*60*60);
$chart->start_time($twelve_weeks_ago);
$chart->end_time($now);
$chart->subtitle("for PRs closed in last 12 weeks");

# Generate the chart.
# "catg [^z]" avoids matching the zz_gnats_testing category.
$img = $chart->plot_days_to_close("catg [^z]");

# Display the chart.
binmode STDOUT; # make sure we are writing to a binary stream
print $img;

exit;

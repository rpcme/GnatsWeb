#!/usr/bin/perl -w
#
# Display the opened_vs_closed chart.
#
# $Id: support_opened_vs_closed.pl,v 1.1.1.1 2001/04/28 11:00:57 yngves Exp $

# BEGIN configuration
@GNATS_LOGIN_DATA = ('gnats', 1529, 'main', 'guest', 'guest');
# END configuration

# Get the HTML stream going.
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
$chart->subtitle("for support issues, last 12 weeks");

# Generate the chart.
# "catg [^z]" avoids matching the zz_gnats_testing category.
# "clss support" restricts us to support issues.
$img = $chart->plot_opened_vs_closed("catg [^z]", "clss support");

# Display the chart.
binmode STDOUT;
print $img;

exit;

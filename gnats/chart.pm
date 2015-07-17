package gnats::chart;

# See the bottom of this file for the POD documentation.  Search for the
# string '=head'.

# You can run this file through either pod2man or pod2html to produce pretty
# documentation in manual or html file format (these utilities are part of the
# Perl 5 distribution).

# Version stuff
$VERSION = '0.1';
$REVISION = (split(/ /, '$Revision: 1.1.1.1 $ '))[1];

# Package stuff

#use Exporter ();
#@ISA = qw(Exporter);
#@EXPORT = qw();
#@EXPORT_OK = qw();

# Package variables

$GNUPLOT = '/usr/bin/gnuplot';
$TMPDIR = '/tmp';

# Local variables

my($TMP_COUNTER) = 0;

# Subs

use gnats;
use Carp;
use Date::Parse;
use Date::Format;
use File::Basename;

# new -
#     Create an obj and login to gnatsd.
#
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my($host, $port, $db, $user, $pass, $attrs) = @_;
    my $self = {};
    bless($self, $class);

    # init our fields
    $self->{START_TIME} = 0;
    $self->{END_TIME} = 0;
    $self->{START_DATE} = '';
    $self->{END_DATE} = '';
    $self->{SUBTITLE} = '';

    # init other fields -- these should maybe be inherited from gnats?
    $self->{HOST} = $host || 'gnats';
    $self->{PORT} = $port || 1529;
    $self->{DATABASE} = $db || 'main';
    $self->{USER} = $user || 'guest';
    $self->{PASSWORD} = $pass || 'guest';

    # init attrs
    my $a;
    $self->{Verbose} = 0;
    foreach $a (qw(RaiseError DebugLevel Verbose)) {
        if (exists($$attrs{$a})) {
            $self->{$a} = $$attrs{$a};
            delete $$attrs{$a};
        } else {
            $self->{$a} = 0;
        }
    }
    foreach $a (keys(%$attrs)) {
        carp "unrecognized attribute: $a";
    }
    $gnats::DEBUG_LEVEL = $self->{DebugLevel};
    $gnats::RAISE_ERROR = $self->{RaiseError};

    # login
    gnats::client_init($host, $port);
    gnats::client_cmd("chdb $db");
    gnats::client_cmd("user $user $pass");

    return $self;
}

# start_time, end_time -
#     Set various date
#
sub start_time {
    my $self = shift;
    $self->{START_TIME} = shift;
    delete $self->{START_DATE};
}
sub end_time   {
    my $self = shift;
    $self->{END_TIME} = shift;
    delete $self->{END_DATE};
}
sub start_date {
    my $self = shift;
    $self->{START_DATE} = shift;
    delete $self->{START_TIME};
}
sub end_date {
    my $self = shift;
    $self->{END_DATE} = shift;
    delete $self->{END_TIME};
}

# subtitle -
#     Set subtitle.
#
sub subtitle   { my $self = shift; $self->{SUBTITLE} = shift; }

# _carp -
#     Carp with given message, and croak if RaiseError turned on.
#
sub _carp
{
    my $self = shift;
    my($msg) = @_;

    croak $msg if $self->{RaiseError};
    carp $msg;
}

# _set_dates -
#     Set start_date and end_date from time values, or vice-versa.
#
# TODO:
#     Institute reasonable default, like 3 months or 12 weeks.
#
sub _set_dates
{
    my $self = shift;

    if ($self->{START_DATE}) {
        if ($self->{START_TIME}) {
            $self->_carp("both start_date and start_time set for chart");
            return 0;
        }
        $self->{START_TIME} = str2time($self->{START_DATE});
    }
    else {
        if (!$self->{START_TIME}) {
            $self->_carp("neither start_date nor start_time set for chart");
            return 0;
        }
        chomp($self->{START_DATE} = ctime($self->{START_TIME}));
    }

    if ($self->{END_DATE}) {
        if ($self->{END_TIME}) {
            $self->_carp("both end_date and end_time set for chart");
            return 0;
        }
        $self->{END_TIME} = str2time($self->{END_DATE});
    }
    else {
        if (!$self->{END_TIME}) {
            $self->_carp("neither end_date nor end_time set for chart");
            return 0;
        }
        chomp($self->{END_DATE} = ctime($self->{END_TIME}));
    }

    return 1;
}

# plot_opened_vs_closed -
#     create a chart of opened versus closed PRs
#
sub plot_opened_vs_closed
{
    my $self = shift;
    my(@extra_cmds) = @_;
    my $cmd;

    # convert time values to date strings
    $self->_set_dates() || return '';

    # set @opened_prs to PRs opened during period
    gnats::client_cmd('rset');
    gnats::client_cmd("araf $self->{START_DATE}");
    gnats::client_cmd("abfr $self->{END_DATE}");
    foreach $cmd (@extra_cmds) {
        gnats::client_cmd($cmd);
    }
    my(@opened_prs) = gnats::client_cmd('sql2');
    my $num_opened = scalar(@opened_prs);
    print "$num_opened opened prs\n" if $self->{Verbose};

    # set @closed_prs to PRs closed during period
    gnats::client_cmd('rset');
    gnats::client_cmd("caft $self->{START_DATE}");
    gnats::client_cmd("cbfr $self->{END_DATE}");
    foreach $cmd (@extra_cmds) {
        gnats::client_cmd($cmd);
    }
    my(@closed_prs) = gnats::client_cmd('sql2');
    my $num_closed = scalar(@closed_prs);
    print "$num_closed closed prs\n" if $self->{Verbose};

    # merge + convert to strange wwwgnats format
    my($qresults) = _sql2_to_qresults(@opened_prs, @closed_prs);
    my $num_prs = scalar(keys(%$qresults));
    printf("\n%s unique %s\n\n", $num_prs ? $num_prs : "No",
           ($num_prs == 1) ? "PR" : "PRs")
        if $self->{Verbose};

    # check that there are some PRs or bail out
    if (!$num_prs) {
        $self->_carp("No PRs closed between $self->{START_DATE} and $self->{END_DATE}");
        return '';
    }

    # dump the data to tempFile
    my(@tempFiles) = _time_vs_count_chart($qresults,
                                          $self->{START_TIME},
                                          $self->{END_TIME},
                                          "Arrival-Date", "Closed-Date");
    return '' unless @tempFiles;

    # setup some gnuplot vars
    my $title = "Weekly Opened versus Closed PRs";
    $title .= "\\n$self->{SUBTITLE}" if defined($self->{SUBTITLE});
    $title .= "\\n$num_opened opened, $num_closed closed";
    my $graphFile = _get_temp_file();

    # call gnuplot to do the work
    if (!open(GP, "|$GNUPLOT")) {
        $self->_carp("Can't open pipe to $GNUPLOT: $!");
        return '';
    }
    print GP qq{
set data style lines
set xdata time
set timefmt "%Y-%m-%d"
set xlabel "Week"
set ylabel "Number of PRs"
set title "$title"
set grid
set key left
set term gif small size 640,480 xffffff x000000 x404040 x0000ff xff0000 xffa500 x66cdaa xcdb5cd xadd8e6 xdda0dd x9500d3
set out "$graphFile"
plot "$tempFiles[0]" using 1:2 title "Opened PRs" with linespoints,\\
     "$tempFiles[1]" using 1:2 title "Closed PRs" with linespoints
};
    close(GP);

    # read the image file and unlink the temp files
    my $img = _read_img_file($graphFile);
    unlink $graphFile;
    unlink @tempFiles;

    return $img;
}

#-----------------------------------------------------------------
# create time versus count chart
#
# args: $qresults, @fields
# $qresults - href to query results hash
# @fields - list of date fields to plot
#
# returns list of temp files created.
#-----------------------------------------------------------------
sub _time_vs_count_chart
{
    my($qresults, $start_time, $end_time, @fields) = @_;
    my $debug = 0;
    printf "time_vs_count_chart: qresults=%s, fields=@fields\n", scalar(keys(%$qresults)) if $debug;

    my(@tempFiles, $field);

    foreach $field (@fields)
    {
	my ($temp) = "$TMPDIR/wwwgnats.chart.$TMP_COUNTER.$$";
        print "time_vs_count_chart: temp=$temp\n" if $debug;
        $TMP_COUNTER++;
	push(@tempFiles, $temp);
	open(TF, ">$temp")
	    or die("Can't open temp file '$temp' in time_vs_count_chart");
	_dump_date_counts(*TF, $field, $qresults,
                         $start_time, $end_time, \&date_o2n);
	close(TF);
    }
    return @tempFiles;
}

# _get_temp_file -
#     Open temp file and return its name.
#
sub _get_temp_file
{
    my ($temp) = "$TMPDIR/wwwgnats.chart.$TMP_COUNTER.$$";
    $TMP_COUNTER++;
    return $temp;
}

# _read_img_file -
#     Read image file and return the contents.
#
sub _read_img_file
{
    my ($img_file) = @_;
    open(IMG, $img_file) || die;
    binmode IMG; # make sure stream is binary
    undef $/; # get whole file at once
    my $img = <IMG>;
    close(IMG) || die;
    return $img;
}

#-----------------------------------------------------------------
# kenstir: filling in holes not provided by chart.pl

sub date_o2n
{
    #str2time($a->[1]) <=> str2time($b->[1]);
    str2time($$qresults{$a}{$field}) <=> str2time($$qresults{$b}{$field});
}

sub numerically
{
    #$a->[1] <=> $b->[1];
    $a <=> $b;
}

sub sort_by_field
{
    #my($field, $sortFn, $qresults) = @_;
    local($field, $sortFn, $qresults) = @_;
    #warn "sort_by_field $field\n";

#    # presplit into array of [Id,$field]
#    my(@presplit_prs) =
#        map { [ $_ , $$qresults{$_}{$field} ] } keys(%$qresults);
#
#    # now sort using sortFn
#    my(@sorted_list) = sort $sortFn @presplit_prs;
#
#    # rebuild list with just PR numbers
#    my(@list) = ();
#    foreach my $pr (@sorted_list) {
#        push(@list, $pr);
#    }

    #my(@list) = sort {$a <=> $b} keys(%$qresults);

    my(@list) = sort $sortFn keys(%$qresults);

    @list;
}

# kenstir: end of filling in holes not provided by chart.pl
#-----------------------------------------------------------------

#-----------------------------------------------------------------
# dump the query results into a format for gnuplot.
#
# Args: $fh, $field, $qresults
# $fh - file handle
# $field - field name
# $qresults - href to a query hash
#-----------------------------------------------------------------
sub _dump_date_counts
{
    my($fh, $field, $qresults, $start_time, $end_time) = @_;
    my($debug) = 0;
    printf("dump_date_counts: field=$field, qresults=%s\n",
           scalar(keys(%$qresults))) if $debug;

    my(@list) = keys(%$qresults);
    printf "dump_date_counts: list=%s\n", scalar(@list) if $debug;
    my(%date_count);
    my($i);
    foreach $i (@list)
    {
        next unless $$qresults{$i}{$field};
	my($time) = str2time($$qresults{$i}{$field});
	next unless (($time >= $start_time) && ($time <= $end_time));

        # Collect dates in day-sized buckets.
        #my($date) = time2str("%Y-%m-%d", $time);
        #$date_count{$date}++;

        # Collect dates in week-sized buckets using %U (week number, with
        # Sunday as 1st day of week).
        my($date) = time2str("%U", $time);
        if (exists($date_count{$date})) {
            #printf "count of $date was: %s", $date_count{$date}->[0];
            $date_count{$date}->[0] += 1;
            #printf ",\tis: %s\n", $date_count{$date}->[0];
        } else {
            #printf "date was: %s", $$qresults{$i}{$field};
            # For purposes of data file, use date of week start (Sunday==0).
            my($day_of_week) = time2str("%w", $time);
            $time -= $day_of_week * (24*60*60); # subtract # of days from Sun
            my($date_of_sun) = time2str("%Y-%m-%d", $time);
            #printf ",\tis: %s\n", $date_of_sun;
            $date_count{$date} = [ 1, $date_of_sun ];
        }
    }
    #foreach $i (sort(keys(%date_count)))
    #{
    #    print $fh "$i $date_count{$i}\n";
    #    print "$i = $date_count{$i}<br>\n" if $debug;
    #}
    foreach $i (sort {$date_count{$a}->[1] cmp $date_count{$b}->[1] }
                keys(%date_count))
    {
        printf $fh "%s %s\n", $date_count{$i}->[1], $date_count{$i}->[0];
        print "$i = $date_count{$i}<br>\n" if $debug;
    }
}

### category_count -
###     create a chart of counts vs time for the super categories
###
##sub category_count
##{
##    my($qresults) = @_;
##
##    # split results up by supercategory
##    my(%superCats, $sc, $i);
##    my(@sCats) = sort keys(%SUPER_CATS);
##    my(@prs)   = keys(%{$qresults});
##
##    foreach $sc (@sCats)
##    {
##	my($regex) = "$SUPER_CATS{$sc}{'regex'}\$";
##	foreach $i (@prs)
##        {
###print "<p>sc = $sc cat = $$qresults{$i}{'Category'} regex = $regex\n";
##	    next unless ($$qresults{$i}{'Category'} =~ m/$regex/);
###print "<p>sc = $sc  pr = $i";
##	    $superCats{$sc}{$i} = $$qresults{$i};
##        }
##    }
##
##    my(@tempFiles);
##    @sCats = sort keys %superCats;
##
###print "<p> sCats = " . join(" ", @sCats);
##    foreach $sc (@sCats)
##    {
###print "<p> prs = " . join(" ", keys (%{$superCats{$sc}}));
##	push(@tempFiles, _time_vs_count_chart(\%{$superCats{$sc}},
##					     "Arrival-Date"));
##    }
##
##    if (@tempFiles)
##    {
##	if ($#tempFiles != $#sCats)
##        {
##	    die("Count mismatch in supercat_count_chart");
##        }
##
##	# gen gnuplot command file
##        if (!open(GP, "|$GNUPLOT")) {
##            $self->_carp("Can't open pipe to $GNUPLOT: $!");
##            return 0;
##        }
##
##	my($graphFileUrl) = $graphFile;
##	$graphFileUrl = $TMP_IMG_URL . basename($graphFile);
##	print "<p><img src=\"$graphFileUrl\">\n";
##
##	print GP "set data style lines
##set xdata time
##set timefmt \"%m/%d/%Y\"
##set xlabel \"Date\"
##set ylabel \"Number of Items\"
##set title \"Types Trend\"
##set grid
##set key left
##set term gif small size 640,480 xffffff x000000 x404040 x0000ff xff0000 xffa500 x66cdaa xcdb5cd xadd8e6 xdda0dd x9500d3
##set out \"$graphFile\"    
##plot ";
##	$i = 0;
##	my($str) = "";
##	foreach $sc (@sCats)
##        {
##	    $str .= "\"$tempFiles[$i]\" u 1:2 t \"$SUPER_CATS{$sc}{'label'} Count\",\\\n";
##	    $i++;
##        }
##	chop $str;chop $str;chop $str;
##	print GP "$str\n";
##
##	close(GP);
##	unlink @tempFiles;
##    }
##}

# plot_days_to_close -
#     Plot a histogram of days to close a PR vs the PR number.
#
sub plot_days_to_close
{
    my $self = shift;
    my(@extra_cmds) = @_;
    my $cmd;

    # convert time values to date strings
    $self->_set_dates() || return '';

    # set @closed_prs to PRs closed during period
    gnats::client_cmd('rset');
    gnats::client_cmd("caft $self->{START_DATE}");
    gnats::client_cmd("cbfr $self->{END_DATE}");
    foreach $cmd (@extra_cmds) {
        gnats::client_cmd($cmd);
    }
    my(@closed_prs) = gnats::client_cmd('sql2');
    printf "%s closed prs\n", scalar(@closed_prs)
        if $self->{Verbose};

    # convert to qresults format
    my($qresults) = _sql2_to_qresults(@closed_prs);
    my $num_prs = scalar(keys(%$qresults));
    printf("\n%s unique %s\n\n", $num_prs ? $num_prs : "No",
           ($num_prs == 1) ? "PR" : "PRs")
        if $self->{Verbose};

    # check that there are some PRs or bail out
    if (!$num_prs) {
        $self->_carp("No PRs closed between $self->{START_DATE} and $self->{END_DATE}");
        return '';
    }

    # dump the data to tempFile
    my($tempFile, $average) = _dump_days_to_close($qresults);
    return '' unless $tempFile;

    # setup some gnuplot vars
    my $title = "Days to Close";
    $title .= "\\n$self->{SUBTITLE}" if defined($self->{SUBTITLE});
    $title .= "\\n$num_prs PRs, average = $average days";
    my $graphFile = _get_temp_file();

    # call gnuplot to do the work
    if (!open(GP, "|$GNUPLOT")) {
        $self->_carp("Can't open pipe to $GNUPLOT: $!");
        return '';
    }
    print GP qq{
set data style lines
set xlabel "PR Number"
set ylabel "Days to Close"
set title "$title"
set grid
set key right
set term gif small size 640,480 xffffff x000000 x404040 x0000ff xff0000 xffa500 x66cdaa xcdb5cd xadd8e6 xdda0dd x9500d3
set out "$graphFile"
plot "$tempFile" title "" with impulses, $average title "Average"
};
    close(GP);

    # read the image file and unlink the temp files
    my $img = _read_img_file($graphFile);
    unlink $tempFile;
    unlink $graphFile;

    return $img;
}

#-----------------------------------------------------------------
# create temp file with days to close data
# Args: $qresults
# 
# returns: $tempFile, $average_days
#
# caller: plot_days_to_close
#-----------------------------------------------------------------
sub _dump_days_to_close
{
    my($qresults) = @_;

    my ($temp) = "$TMPDIR/wwwgnats.chart.$TMP_COUNTER.$$";
    $TMP_COUNTER++;
    #warn "temp=$temp\n";

    open(TF, ">$temp")
        or die("Can't open temp file '$temp' in dump_days_to_close");
    
    my(@list) = sort_by_field("Number", \&numerically, $qresults);
    $n = @list;
    #warn "list has $n elements\n";
    my($i, $total, $count, $average);
    $count = 0;
    foreach $i (@list)
    {
        #printf("$i:\t%s\t%4d %12s %s\n", $$qresults{$i}{'Id'}, $$qresults{$i}{'Category'}, $$qresults{$i}{'Synopsis'});
        next unless ($$qresults{$i}{'Closed-Date'});
	my($open) = str2time($$qresults{$i}{'Arrival-Date'});
	my($close) = str2time($$qresults{$i}{'Closed-Date'});
	# convert seconds to days 60*60*24 = 86400 sec per day
	my($days) = ($close - $open) / 86400;
	$total += $days;
	$count++;

	print TF sprintf("%i %.1f\n", $i, $days);
    }
    close(TF);
    $average = ($count > 0) ? sprintf("%.1f", $total/$count) : 999 ;

    return $temp, $average;
}

# _sql2_to_qresults -
#     Convert sql2 results into "qresults" format.  This format is used in
#     Mike Sutton's version of wwwgnats, and is the format expected by the
#     original versions of the charting functions.
#
sub _sql2_to_qresults
{
    my(@sql2_prs) = @_;
    my $debug = 0;
    my($pr);
    my($qresults);
    $qresults = {};
    foreach $pr (@sql2_prs) 
    {
        my($id, $cat, $syn, $conf, $sev,
           $pri, $resp, $state, $class, $sub,
           $arrival, $orig, $release, $lastmoddate, $closeddate,
           $quarter, $keywords, $daterequired) = split('\|', $pr);
        print "pr=$pr\n" if $debug;
#        next unless $id;
        $$qresults{$id} = {
            'Id' => $id,
            'Category' => $cat,
            'Synopsis' => $syn,
            'Confidential' => $conf,
            'Severity' => $sev,
            'Priority' => $pri,
            'Responsible' => $resp,
            'State' => $state,
            'Class' => $class,
            'Submitter-Id' => $sub,
            'Arrival-Date' => $arrival,
            'Originator' => $orig,
            'Release' => $release,
            'Last-Modified' => $lastmoddate,
            'Closed-Date' => $closeddate,
            'Quarter' => $quarter,
            'Keywords' => $keywords,
            'Date-Required' => $daterequired,
        };
        printf("%4d %12s %s\n", $$qresults{$id}{'Id'},
               $$qresults{$id}{'Category'}, $$qresults{$id}{'Synopsis'})
             if $debug;
        print Dumper($qresults) if $debug;
    }
    return $qresults;
}

#-----------------------------------------------------------------
# wait and then remove files, to give web client a chance to
# download it
#
# args: @files
#-----------------------------------------------------------------
sub unlink_after_delay
{
    my(@files) = @_;
    if (@files)
    {
	system("echo \"rm -f " . join(" " ,@files) .
	       "\" | at now +1 minute >/dev/null 2>&1");
    }
}

1;

__END__

#---------------------------------------------------------------------
#    -- format of query results hash --
# qeury the pr data base using the --sql2 option and passed args and
# return a hash of the results.  The keys of the has are the pr
# numbers which point to a hash that has the field names as keys.  The
# hash has the following format.
#
# { pr#1 => { 'Category' => xxx,
#             'Synopsis' => xxx,
#             .....},
#   pr#2 => { 'Category' => xxx,
#             'Synopsis' => xxx,
#             .....}
# }
#
# Note that 'Number' must be in the subhash.

=head1 NAME

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 SEE ALSO

The GNATS home page at
http://sourceware.cygnus.com/gnats/

=head1 AUTHORS

Copyright 2000 by Mike Sutton and Kenneth Cox.

The chart code was written by Mike Sutton and packaged and modified by
Kenneth Cox.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

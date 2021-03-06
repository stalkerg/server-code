#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut 

use strict;
use DBI;
use Template;
use CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir);


$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my $query = new CGI;
my @members; my @branches; my@stages;
if ($CGI::VERSION < 4.08)
{
    @members = grep {$_ ne "" } $query->param('member');
    @branches = grep {$_ ne "" } $query->param('branch');
    @stages = grep {$_ ne "" } $query->param('stage');
}
else
{
    @members = grep {$_ ne "" } $query->multi_param('member');
    @branches = grep {$_ ne "" } $query->multi_param('branch');
    @stages = grep {$_ ne "" } $query->multi_param('stage');
}
map { s/[^a-zA-Z0-9_ -]//g; } @branches;
map { s/[^a-zA-Z0-9_ -]//g; } @members;
map { s/[^a-zA-Z0-9_ :-]//g; } @stages;
my $max_days =  $query->param('max_days') + 0 || 10;

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;


my $sort_clause = "";
my $presort_clause = "";
my $sortby = $query->param('sortby') || 'nosort';
if ($sortby eq 'name')
{
	$sort_clause = 'lower(b.sysname),';
}
elsif ($sortby eq 'namenobranch')
{
	$presort_clause = "lower(b.sysname), b.snapshot desc,"
}

my $db = DBI->connect($dsn,$dbuser,$dbpass,{pg_expand_array => 0}) 
    or die("$dsn,$dbuser,$dbpass,$!");

my $get_all_branches = qq{

  select distinct branch
  from nrecent_failures
  where branch <> 'HEAD'
  order by branch desc

};

my $all_branches = $db->selectcol_arrayref($get_all_branches);
unshift (@$all_branches,'HEAD');

my $get_all_members = qq{

  select distinct sysname
  from nrecent_failures
  order by sysname

};

my $all_members = $db->selectcol_arrayref($get_all_members);

my $get_all_stages = qq{

  select distinct stage 
  from build_status 
    join nrecent_failures using (sysname,snapshot,branch)

};

my $all_stages = $db->selectcol_arrayref($get_all_stages);

my $statement =<<EOS;


  select timezone('GMT'::text, 
	now())::timestamp(0) without time zone - b.snapshot AS when_ago, 
	b.*,
	d.stage as current_stage
  from nrecent_failures_db_data b
	left join  dashboard_mat d
		on (d.sysname = b.sysname and d.branch = b.branch)
  where (now()::timestamp(0) without time zone - b.snapshot) < (? * interval '1 day')
  order by $presort_clause 
        b.branch = 'HEAD' desc,
        b.branch desc, 
        $sort_clause 
        b.snapshot desc

EOS
;

my $statrows=[];
my $sth=$db->prepare($statement);
$sth->execute($max_days);
while (my $row = $sth->fetchrow_hashref)
{
    next if (@members && ! grep {$_ eq $row->{sysname} } @members);
    next if (@stages && ! grep {$_ eq $row->{stage} } @stages);
    next if (@branches && ! grep {$_ eq $row->{branch} } @branches);
    $row->{build_flags}  =~ s/^\{(.*)\}$/$1/;
    $row->{build_flags}  =~ s/,/ /g;
	# enable-integer-datetimes is now the default
	if ($row->{branch} eq 'HEAD' || $row->{branch} gt 'REL8_3_STABLE')
	{
		$row->{build_flags} .= " --enable-integer-datetimes "
			unless ($row->{build_flags} =~ /--(en|dis)able-integer-datetimes/);
	}
	# enable-thread-safety is now the default
	if ($row->{branch} eq 'HEAD' || $row->{branch} gt 'REL8_5_STABLE')
	{
		$row->{build_flags} .= " --enable-thread-safety "
			unless ($row->{build_flags} =~ /--(en|dis)able-thread-safety/);
	}
    $row->{build_flags}  =~ s/--((enable|with)-)?//g;
	$row->{build_flags} =~ s/libxml/xml/;
    $row->{build_flags}  =~ s/\S+=\S+//g;
    push(@$statrows,$row);
}
$sth->finish;


$db->disconnect;


my $template_opts = { INCLUDE_PATH => $template_dir };
my $template = new Template($template_opts);

print "Content-Type: text/html\n\n";

$template->process('fstatus.tt',
		{statrows=>$statrows, 
		 sortby => $sortby,
		 max_days => $max_days,
		 all_branches => $all_branches,
		 all_members => $all_members,
		 all_stages => $all_stages,
		 qmembers=> \@members,
		 qbranches => \@branches,
		 qstages => \@stages} );

exit;


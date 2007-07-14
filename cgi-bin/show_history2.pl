#!/usr/bin/perl

use strict;
use DBI;
use Template;
use CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport);


require "$ENV{BFConfDir}/BuildFarmWeb.pl";
#require "BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn,$dbuser,$dbpass);

die $DBI::errstr unless $db;

my $query = new CGI;
my $member = $query->param('nm');
my $branch = $query->param('br');

# we don't really need to do this join, since we only want
# one row from buildsystems. but it means we only have to run one
# query. If it gets heavy we'll split it up and run two

my $statement = <<EOS;

  select (now() at time zone 'GMT')::timestamp(0) - snapshot as when_ago,
      sysname, snapshot, b.status, stage,
      operating_system, os_version, compiler, compiler_version, architecture 
  from buildsystems s, 
       build_status b 
  where name = ?
        and branch = ?
        and s.status = 'approved'
        and name = sysname
  order by snapshot desc
  limit 240

EOS
;

my $statrows=[];
my $sth=$db->prepare($statement);
$sth->execute($member,$branch);
while (my $row = $sth->fetchrow_hashref)
{
	push(@$statrows,$row);
}
$sth->finish;

$db->disconnect;

my $template = new Template({EVAL_PERL => 1, 
			     INCLUDE_PATH => "/home/community/pgbuildfarm/templates",
				});

print "Content-Type: text/html\n\n";

$template->process("dyn/history.tt",
	{statrows=>$statrows, branch=>$branch, member => $member});


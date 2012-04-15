#! /usr/bin/perl

use strict;
use warnings;

use Net::SSH::Perl;
use Time::HiRes qw(gettimeofday tv_interval);

BEGIN { $| = 1 } # disable buffering on pipes

my @hosts = (
  "rc01xcs213.managed.mst.edu",
  "rc02xcs213.managed.mst.edu",
  "rc03xcs213.managed.mst.edu",
  "rc04xcs213.managed.mst.edu",
#  "rc05xcs213.managed.mst.edu",
  "rc06xcs213.managed.mst.edu",
  "rc07xcs213.managed.mst.edu",
  "rc08xcs213.managed.mst.edu",
  "rc09xcs213.managed.mst.edu",
  "rc10xcs213.managed.mst.edu",
  "rc11xcs213.managed.mst.edu",
#  "rc12xcs213.managed.mst.edu",
  "rc13xcs213.managed.mst.edu",
  "rc14xcs213.managed.mst.edu",
  "rc15xcs213.managed.mst.edu",
  "rc16xcs213.managed.mst.edu",
);

my $interval = 5;

# Signalflags
my $written = 0;
my $run = 1;
my $go = 1;

my @sshpids;
my @readpids;

my %readtx;
my %readrx;
my %readhandles;

$SIG{USR1} = "onewrote";
$SIG{USR2} = "killchild";

foreach my $host(@hosts) {
  # Spawn an SSH connection
  my $sshpid = sshfork($host); 

  push(@sshpids, $sshpid);
}

$SIG{INT} = "killme";
open(my $logfh, '>', "./net.log");
open(my $hostfh, '>', "./hosts.log");

while($go) {
  while($go && (scalar @hosts > $written)) {
    sleep 1;
  }
 
  last if(! $go);
 
  $written = 0;

  my $txsum = 0;
  my $rxsum = 0 ;

  foreach my $key(sort keys %readhandles) {
    last if(! $go);

    my $handle = $readhandles{$key};
    my $tx = <$handle>;
    my $rx = <$handle>;
    my $time = <$handle>;
    chomp($time);
    chomp($tx);
    chomp($rx);
    if($readtx{$key}) {
      my $net = $tx - $readtx{$key};
      $net /= $time;
      my $pretty = $net/(1024);
      print "$key: $pretty (tx)";
      print $hostfh "$key: $pretty (tx)";
      $txsum += $net;
    }
    $readtx{$key} = $tx;
    
    if($readrx{$key}) {
      my $net = $rx - $readrx{$key};
      $net /= $time;
      my $pretty = $net/(1024*$time);
      print " $pretty (rx)\n";
      print $hostfh " $pretty (rx)\n";
      $rxsum += $net;
    }
    $readrx{$key} = $rx;
  }
  
  $txsum /= 1024;
  $rxsum /= 1024;
  print "\nTotal: $txsum (tx) $rxsum (rx)\n\n";
  print $logfh "$txsum\t$rxsum\n";
}

for my $pid (@sshpids) {
  kill "USR2", $pid;
}

close($logfh);
close($hostfh);
exit(0);

## SIGNAL HANDLERS ##

sub onewrote {
  $written++;
}

sub killme {
  undef $go;
}

sub killchild {
  undef $run;
}

## SUBPROCESSES ##

sub sshfork {
  my $host = shift;

  my $parent = $$;
  my $pid = open($readhandles{$host}, "-|");
  if(not defined $pid) {
    die "Error launching ssh process for $host: $!\n";
  }
  elsif($pid == 0) { #child
    my $ssh = Net::SSH::Perl->new($host, protocol => '2,1') or die "Could not connect to $host: $!";
    $ssh->login("USERNAME", "PASSWORD") or die "Could not log in to $host: $!";

    my $time = [gettimeofday];
    while($run) {
      my($stdout, $stderr, $exit) = $ssh->cmd("cat /sys/class/net/eth0/statistics/tx_bytes");
      die "Error connecting to $host\n" if not defined $stdout;
      print $stdout;
      ($stdout, $stderr, $exit) = $ssh->cmd("cat /sys/class/net/eth0/statistics/rx_bytes");
      print $stdout;
      my $newtime = [gettimeofday];
      print tv_interval($time, $newtime) . "\n";
      $time = $newtime;
      kill "USR1", $parent or die "cannot kill $parent: $!";
      sleep $interval;
    }
  } 
  else { #parent    
    return $pid;
  }
}

sub readfork {
  my $host = shift;

  my $parent = $$;
  my $pid = open($readhandles{$host}, "-|");

  if(not defined $pid) {
    die "Error launching read proccess for $host: $!\n";
  }
  elsif($pid == 0) { #child
    while($run) {
      open(my $fifo, '<', $host) or die "Cannot read $host: $!\n";

      my $line = <$fifo>;
      print $line;
      
      kill "USR1", $parent; 
      sleep 1;
    }
  }
  else { #parent
    return $pid;
  }
}


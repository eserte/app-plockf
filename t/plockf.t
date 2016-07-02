#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;

BEGIN {
    if (!eval q{
	use Test::More;
	1;
    }) {
	print "1..0 # skip no Test::More module\n";
	exit;
    }
}

plan 'no_plan';

my $use_blib = 1;
my $plockf = "$FindBin::RealBin/../blib/script/plockf";
unless (-f $plockf) {
    # blib version not available, use ../bin source version
    $plockf = "$FindBin::RealBin/../bin/plockf";
    $use_blib = 0;
}

# Special handling for systems without shebang handling
my @full_script = $^O eq 'MSWin32' || !$use_blib ? ($^X, $plockf) : ($plockf);

my $lock_file = "$FindBin::RealBin/plockf.lck";
my $signal_file = "$FindBin::RealBin/plockf.signal";

{
    my @cmd = (@full_script, '-h');
    my($ret, undef, $stderr) = run(\@cmd);
    is $ret, 64, 'bad usage'; # hmmm, should it really fail if the user specifies --help?
    defined $stderr and like $stderr, qr{usage};
}

{
    my @cmd = (@full_script);
    my($ret, undef, $stderr) = run(\@cmd);
    is $ret, 64, 'bad usage';
    defined $stderr and like $stderr, qr{Lock file is not specified};
    defined $stderr and like $stderr, qr{usage};
}

{
    my @cmd = (@full_script, '-t', '-123', $lock_file, 'never_executed');
    my($ret, undef, $stderr) = run(\@cmd);
    is $ret, 64, 'bad usage';
    defined $stderr and like $stderr, qr{Timeout must be positive};
}

{
    my @cmd = (@full_script, $lock_file);
    my($ret, undef, $stderr) = run(\@cmd);
    is $ret, 64, 'bad usage';
    defined $stderr and like $stderr, qr{Command is not specified};
}

{
    my @cmd = (@full_script, $lock_file, $^X, '-e1');
    my($ret) = run(\@cmd);
    is $ret, 0;
    ok !-f $lock_file, 'lock file was not kept';
}

{
    my @cmd = (@full_script, '-k', $lock_file, $^X, '-e1');
    my($ret) = run(\@cmd);
    is $ret, 0;
    ok -f $lock_file, '-k works';
}

{
    my @cmd = (@full_script, $lock_file, $^X, '-e', 'exit 12');
    my($ret) = run(\@cmd);
    is $ret, 12, 'exit code of command propagated';
}

{
    my @cmd = (@full_script, $lock_file, $^X, '-e', 'kill 9 => $$');
    my($ret) = run(\@cmd);
    if ($^O eq 'MSWin32') {
	# signals are not reported in $? on Windows, so we
	# only know that it failed
	isnt $ret, 0, 'command was not successful, special Windows check';
    } else {
	is $ret, 70, 'command was killed, EX_SOFTWARE returned';
    }
}

{
    my $pid = run_blocking_process(3);
    my @cmd = (@full_script, '-t', 0, $lock_file, $^X, '-e1');
    my($ret, undef, $stderr) = run(\@cmd);
    is $ret, 75, 'lock error on -t 0';
    defined $stderr and like $stderr, qr{plockf: .*plockf.lck: already locked$};
    kill 9 => $pid;
    waitpid $pid, 0;
}

{
    my $pid = run_blocking_process(3);
    my @cmd = (@full_script, '-s', '-t', 0, $lock_file, $^X, '-e1');
    my($ret, undef, $stderr) = run(\@cmd);
    is $ret, 75, 'silent lock error on -t 0';
    defined $stderr and is $stderr, '';
    kill 9 => $pid;
    waitpid $pid, 0;
}

{
    my $pid = run_blocking_process(4);
    my @cmd = (@full_script, '-t', 0.2, $lock_file, $^X, '-e1');
    my($ret, undef, $stderr) = run(\@cmd);
    is $ret, 75, 'lock error on -t > 0s';
    defined $stderr and like $stderr, qr{plockf: .*plockf.lck: already locked$};
    kill 9 => $pid;
    waitpid $pid, 0;
}

{
    my $pid = run_blocking_process(1);
    my @cmd = (@full_script, '-t', 100, $lock_file, $^X, '-e1');
    my($ret, undef, $stderr) = run(\@cmd);
    is $ret, 0, 'got lock within timeout interval';
    defined $stderr and is $stderr, '';
}

{
    my $pid = run_blocking_process(1);
    my @cmd = (@full_script, $lock_file, $^X, '-e1');
    my($ret, undef, $stderr) = run(\@cmd);
    is $ret, 0, 'no lock error, blocking lock';
    defined $stderr and is $stderr, '';
}

{
    # assume .lck file is non existent at this point
    my @cmd = (@full_script, '-n', $lock_file, $^X, '-e1');
    my($ret, undef, $stderr) = run(\@cmd);
    is $ret, 69, 'error on -n option';
    defined $stderr and like $stderr, qr{plockf: cannot open .*plockf.lck:};
}

sub run_blocking_process {
    my $seconds = shift;
    unlink $signal_file;
    my $pid = fork;
    die $! if !defined $pid;
    if ($pid == 0) {
	my @cmd = (@full_script, $lock_file, $^X, '-e', qq{open my \$fh, ">", shift; sleep $seconds}, $signal_file);
	exec @cmd;
	die "@cmd failed: $!";
    }
    my $t0 = time;
    while() {
	last if -f $signal_file;
	die "Something went wrong; signal file never created" if time - $t0 > 60;
	select undef, undef, undef, 0.05;
    }
    $pid;
}

sub run {
    my($cmdref) = @_;
    if (eval { require IPC::Run; 1 }) {
	my($stdout, $stderr) = ('', '');
	IPC::Run::run($cmdref, '>', \$stdout, '2>', \$stderr);
	($?>>8, $stdout, $stderr);
    } else {
	system @$cmdref;
	($?>>8, undef, undef);
    }
}

__END__

# SUSE's openQA tests
#
# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Check system journal for errors given a list of known patterns
#          referring to known bugs. This module will fail in case an unknown
#          message was found and in case a failing systemd service was found.
# Maintainer: qa-c team <qa-c@suse.de>

use base "opensusebasetest";
use strict;
use warnings;
use testapi;
use serial_terminal 'select_serial_terminal';
use version_utils 'is_opensuse';
use Mojo::JSON qw(decode_json);

sub parse_bug_refs {
    my $bug_file = sprintf("%s/data/journal_check/bug_refs.json", get_var('CASEDIR'));
    my $tested_product = get_required_var('DISTRI');
    my $tested_version = get_required_var('VERSION');
    my %bp;

    # Treat staging projects like the full product
    $tested_version = 'Tumbleweed' if (is_opensuse && $tested_version =~ /^Staging:/);

    my $data;
    {
        open(my $fh_json, '<', $bug_file) or die "Can't open \"$bug_file\": $!\n";
        local $/ = undef;
        $data = <$fh_json>;
        close $fh_json;
    };

    my $bugs = decode_json($data);
    foreach my $bugid (keys %$bugs) {
        if (exists $bugs->{$bugid}->{products}->{$tested_product} && ref $bugs->{$bugid}->{products}->{$tested_product} eq ref []) {
            foreach my $ver (@{$bugs->{$bugid}->{products}->{$tested_product}}) {
                if ($ver eq $tested_version) {
                    $bp{$bugid} = {%{$bugs->{$bugid}}{qw(type description)}};
                    last;
                }
            }
        } else {
            bmwqemu::diag("Versions of a product in journal_check::bug_refs.json should be stored in an array, or the product key is missing!");
        }
    }
    return !%bp ? undef : \%bp;
}

sub run {
    my $self = shift;
    my $bug_pattern = parse_bug_refs();

    select_serial_terminal;

    my @journal_output = split(/\n/, script_output("journalctl --no-pager --quiet -p ${\get_var('JOURNAL_LOG_LEVEL', 'err')} -o short-precise"));
    my @matched_bugs;

    # Find lines which matches to the pattern_bug
    foreach my $bsc (keys %$bug_pattern) {
        my $buffer = "";
        foreach my $line (@journal_output) {
            if ($line =~ /$bug_pattern->{$bsc}->{description}/) {
                $buffer .= $line . "\n";
                push @matched_bugs, $bsc;
            }
        }
        if ($buffer) {
            if ($bug_pattern->{$bsc}->{type} eq 'feature') {
                record_info($bsc, $buffer);
            } elsif ($bug_pattern->{$bsc}->{type} eq 'ignore') {
                bmwqemu::diag("Ignoring log message:\n$buffer\n");
            } else {
                record_soft_failure("$bsc\n$buffer");
            }
        }
    }

    my $failed;
    # Find lines which doesn't match to the pattern_bug by using master_pattern
  OUT: foreach my $line (@journal_output) {
        foreach my $mp (map { $bug_pattern->{$_}->{description} } keys %$bug_pattern) {
            next OUT if ($line =~ /$mp/);
        }
        record_info('Unknown issue', $line, result => 'fail');
        $failed = 1;
    }

    # Write full journal output for reference and upload it into Uploaded Logs section in test webUI
    script_run("journalctl --no-pager -o short-precise > /tmp/full_journal.txt");
    upload_logs "/tmp/full_journal.txt";

    # Check for failed systemd services and examine them
    # script_run("pkill -SEGV dbus-daemon"); # comment out for a test
    my $failed_services = script_output("systemctl --failed --no-legend --plain --no-pager");
  SRV: foreach my $line (split(/\n/, $failed_services)) {
        if ($line =~ /^([\w.-]+)\s.+$/) {
            my $service = $1;
            my $failed_service_output = script_output("systemctl status $service -l || true");
            foreach my $bsc (@matched_bugs) {
                if ($failed_service_output =~ $bug_pattern->{$bsc}->{description}) {
                    record_soft_failure("$service failed due to $bsc\n$failed_service_output") unless $bug_pattern->{$bsc}->{type} eq 'ignore';
                    next SRV;
                }
            }
            record_info "$service failed", $failed_service_output, result => 'fail';
            $failed = 1;
        }
    }

    # upload all content of audit directory
    if (script_run('test -d /var/log/audit/') == 0) {
        assert_script_run('tar cvf /tmp/audit.tar  /var/log/audit/*');
        upload_logs('/tmp/audit.tar');
    }

    $self->result('fail') if $failed;
}

sub test_flags {
    return {fatal => 0};
}

1;

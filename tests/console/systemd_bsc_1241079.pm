# Copyright 2025 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: systemd_regression
# Summary: https://bugzilla.suse.com/show_bug.cgi?id=1241079#c13
# - follow steps mentioned in https://github.com/systemd/systemd/issues/10627
# - check no systemd hang/core dump/crash
# - test other service like 'sshd' is working fine
# Maintainer: qe-core <qe-core@suse.com>

use base 'consoletest';
use strict;
use warnings;
use testapi;
use serial_terminal 'select_serial_terminal';
use power_action_utils 'power_action';
use utils;


# script to reload systemd daemon and edit a test service
my $pid_1 = '';
my $pid_2 = '';
my $script
  = 'while :; do dbus-send --system --print-reply --dest=org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager.Reload; sleep 1; done';

sub install_broken_pkgs {
    # Install broken systemd packages
    my ($self) = @_;
    assert_script_run('curl -o bsc_1241079.tar ' . data_url('bsc_1241079.tar'));
    assert_script_run('tar xf bsc_1241079.tar');
    assert_script_run('rpm -Uvh --force bsc_1241079/*.rpm');

    power_action('reboot', textmode => 1);
    $self->wait_boot;
}

sub add_test_service {
    select_serial_terminal;
    script_output(
        "echo  \"\$(cat <<EOF
[Service]
Type=simple
WorkingDirectory=/tmp
ExecStart=/usr/bin/sleep 100
EOF
        )\"  >> /run/systemd/system/_test.service"
    );
}

sub run_daemon_reload {
    select_console 'root-console';
    $pid_1 = background_script_run "$script";
    wait_still_screen 3;
    assert_script_run('echo "" > /etc/systemd/system/_test.service');
}

sub run_2nd_daemon_reload {
    select_console 'root-console';
    $pid_2 = background_script_run "$script";
    wait_still_screen 3;
    enter_cmd('echo "" > /etc/systemd/system/_test.service');
}

sub reset_system {
    my ($self) = @_;
    select_serial_terminal;
    enter_cmd("reboot -f");
    select_console('root-console', await_console => 0);
    $self->wait_boot;
    select_serial_terminal;
}

sub restore_system {
    my ($self) = @_;
    zypper_call 'up';
    power_action('reboot', textmode => 1);
    $self->wait_boot;
}

sub reproduce_bug {
    select_serial_terminal;
    # we can see error messages from journal log
    validate_script_output_retry("journalctl -b -n 30", sub { m/failed at src\/core\/dbus-manager.c/ }, retry => 10, delay => 5);
}

sub verify_fix {
    select_serial_terminal;
    # no issue with systemd service like sshd after running script a while
    # in case some failures, below command will get stuck
    sleep 30;
    systemctl 'status sshd';
}

sub clean_up {
    enter_cmd("rm -f /etc/systemd/system/_test.servcie");
}

sub run {
    my ($self) = shift;
    select_serial_terminal;

    add_test_service();

    # you can reproduce the bug via job setting "REPRODUCE_BUG=1"
    if (get_var('REPRODUCE_BUG_1241079', '')) {
        $self->install_broken_pkgs();
        add_test_service();
        run_daemon_reload();
        run_2nd_daemon_reload();
        reproduce_bug();
        # verify bug is fixed in latest build
        $self->reset_system();
        $self->restore_system();
    }
    # verify the issue is not seen in the latest build
    run_daemon_reload();
    run_2nd_daemon_reload();
    verify_fix();
    $self->reset_system();
    clean_up();
}

sub post_fail_hook {
    my ($self) = shift;
    $self->SUPER::post_fail_hook;
    clean_up();
}

1;

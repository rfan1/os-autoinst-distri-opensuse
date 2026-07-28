# SUSE's openQA tests
#
# Copyright 2018-2020 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: mdadm
# Summary: mdadm test, run script creating RAID 0, 1, 5, re-assembling and replacing faulty drive
# - Fetch mdadm.sh from datadir
# - Execute bash mdadm.sh |& tee mdadm.log
# - Upload mdadm.log
# Maintainer: QE Core <qe-core@suse.de>

use Mojo::Base 'consoletest';
use testapi;
use Utils::Logging 'save_and_upload_log';
use serial_terminal 'select_serial_terminal';
use package_utils 'install_package';
use version_utils 'is_sle';
use power_action_utils;

sub run {
    my $self = shift;
    select_serial_terminal;

    install_package('mdadm expect', trup_reboot => 1);

    record_info("mdadm build", script_output("rpm -q --qf '%{version}-%{release}' mdadm"));

    assert_script_run 'wget ' . data_url('qam/mdadm.sh');
    assert_script_run 'wget http://openqa.suse.de/assets/repo/kernel-default-6.12.0-160099.294.1.g2573cf4.x86_64.rpm';
    assert_script_run 'rpm -Uvh --force --nodeps kernel-default-6.12.0-160099.294.1.g2573cf4.x86_64.rpm';
    power_action('reboot', textmode => 1);
    $self->wait_boot(ready_time => 600, bootloader_time => get_var('BOOTLOADER_TIMEOUT', 300));
    select_serial_terminal;

    my $timeout = 360;
    if (is_sle('<15')) {
        if (script_run('bash mdadm.sh |& tee mdadm.txt; if [ ${PIPESTATUS[0]} -ne 0 ]; then false; fi', $timeout)) {
            record_soft_failure 'bsc#1105628';
            assert_script_run 'bash mdadm.sh |& tee mdadm.txt; if [ ${PIPESTATUS[0]} -ne 0 ]; then false; fi', $timeout;
        }
    }
    else {
        assert_script_run 'bash mdadm.sh |& tee mdadm.txt; if [ ${PIPESTATUS[0]} -ne 0 ]; then false; fi', $timeout;
    }
    upload_logs 'mdadm.txt';
}

sub post_fail_hook {
    select_serial_terminal;
    upload_logs 'mdadm.txt';
    save_and_upload_log('journalctl --no-pager -ab -o short-precise', 'journal.txt');
}

1;

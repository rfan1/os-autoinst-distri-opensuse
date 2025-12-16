# SUSE's openQA tests
#
# Copyright 2019 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: sudo expect
# Summary: sudo test
#          - single command
#          - I/O redirection
#          - starting a shell
#          - environment variables
#          - sudoers configuration
#          https://documentation.suse.com/en-us/sles/15-SP7/html/SLES-all/cha-adm-sudo.html
# Maintainer: QE Core <qe-core@suse.de>


use base "consoletest";
use testapi;
use utils 'zypper_call';
use version_utils qw(is_sle is_public_cloud is_opensuse);
use publiccloud::utils qw(is_azure is_byos);


sub run {
    foreach my $num (1 .. 1000) {
        record_info "iteration $num";
        select_console 'root-console';
        sleep 2;
        select_console 'log-console';
    }
}

1;

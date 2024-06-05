# SUSE's openQA tests
#
# Copyright 2017 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: gnuhealth stack installation
# Maintainer: Oliver Kurz <okurz@suse.de>

use base 'x11test';
use strict;
use warnings;
use testapi;
use serial_terminal 'select_serial_terminal';
use utils "zypper_call";
sub run {
    my ($self) = @_;
    select_console 'x11';
    ensure_installed 'gnuhealth', timeout => 300;
    record_info "GNUOLDPKG";
    select_serial_terminal;
    zypper_call "install --oldpackage trytond=6.0.38-bp155.2.15.1";
    select_console 'x11';
}

sub test_flags {
    return {fatal => 1};
}

1;

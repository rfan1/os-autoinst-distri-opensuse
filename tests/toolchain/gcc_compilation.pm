# SUSE's openQA tests
#
# Copyright 2017 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: C and C++ source compilation to check that gcc from toolchain module
# Maintainer: qe-core@suse.de

use base "opensusebasetest";
use strict;
use warnings;
use testapi;
use utils 'clear_console';

sub run {
    assert_script_run('curl --output ./gawk-src.tar.gz ' . data_url('toolchain/gawk-src.tar.gz'));
    assert_script_run('tar xf gawk-src.tar.gz');
    assert_script_run('cd ./gawk-4.1.4');
    assert_script_run('./configure 2>&1 | tee /tmp/configure.log; if [ ${PIPESTATUS[0]} -ne 0 ]; then false; fi', 600);
    assert_script_run('make -j$(getconf _NPROCESSORS_ONLN) 2>&1 | tee /tmp/make.log; if [ ${PIPESTATUS[0]} -ne 0 ]; then false; fi', 3600);
    assert_script_run('./gawk \'{ print }\' /etc/hostname');
    save_screenshot;
    clear_console;
}

sub post_fail_hook {
    my $self = shift;
    upload_logs '/tmp/make.log';
    upload_logs '/tmp/configure.log';
    $self->export_logs();
}

1;

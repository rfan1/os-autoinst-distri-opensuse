# SUSE's openQA tests
#
# Copyright 2021 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Handles Language and Keyboard Layout dialog
# in YaST Firstboot Configuration
#
# Maintainer: QA SLE YaST team <qa-sle-yast@suse.de>

use base 'y2_firstboot_basetest';
use strict;
use warnings;
use scheduler 'get_test_suite_data';
use cfg_files_utils;

sub run {
    my $test_data = get_test_suite_data()->{language_and_keyboard};
    my $lang_and_key = $testapi::distri->get_firstboot_language_and_keyboard_layout();
    compare_settings({
            expected => $test_data,
            current => $lang_and_key->collect_current_language_and_keyboard_layout_info(),
            suppress_info => 1});
    $lang_and_key->proceed_with_current_configuration();
}

1;
